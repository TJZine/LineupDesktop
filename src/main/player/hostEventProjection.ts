import type { NativePlayerHostEvent, NativePlayerHostStatus } from './nativePlayerHostPort.js';
import { normalizeHostErrorPayload, validationFailure, type ValidationFailure } from './playerAdapterErrors.js';
import {
  hasForbiddenPrivilegedField,
  isNonEmptyString,
  isNullableFiniteNonNegativeNumber,
  isNullableNonEmptyString,
  isRecord,
  isStringInSet,
  readRequestId,
  validateMediaSummary,
  validateTimeRanges,
  validateTracks,
} from './playerAdapterValidation.js';

const HOST_PLAYBACK_STATUSES = [
  'ready',
  'buffering',
  'playing',
  'paused',
  'seeking',
  'stalled',
] as const satisfies readonly NativePlayerHostStatus[];

export function validateHostEvent(
  event: unknown,
): { event: NativePlayerHostEvent } | ValidationFailure {
  if (!isRecord(event)) {
    return validationFailure(undefined, 'host event must be an object');
  }
  if (hasForbiddenPrivilegedField(event)) {
    return validationFailure(readRequestId(event), 'host event contained privileged fields');
  }
  const type = event.type;
  if (typeof type !== 'string') {
    return validationFailure(readRequestId(event), 'host event type must be a string');
  }
  switch (type) {
    case 'media.loaded': {
      const requestId = event.requestId;
      const media = validateMediaSummary(event.media);
      const tracks = event.tracks === undefined ? undefined : validateTracks(event.tracks);
      if (
        !isNonEmptyString(requestId) ||
        'error' in media ||
        !isNullableFiniteNonNegativeNumber(event.durationMs) ||
        (tracks !== undefined && 'error' in tracks)
      ) {
        return validationFailure(readRequestId(event), 'media loaded host event was invalid');
      }
      return {
        event: {
          type,
          requestId,
          media: media.value,
          durationMs: event.durationMs,
          tracks: tracks?.value,
        },
      };
    }
    case 'playback.state': {
      const requestId = event.requestId;
      if (
        !isNonEmptyString(requestId) ||
        !isStringInSet(event.status, HOST_PLAYBACK_STATUSES) ||
        typeof event.playing !== 'boolean'
      ) {
        return validationFailure(readRequestId(event), 'playback state host event was invalid');
      }
      return { event: { type, requestId, status: event.status, playing: event.playing } };
    }
    case 'time.updated': {
      const requestId = event.requestId;
      if (
        !isNonEmptyString(requestId) ||
        typeof event.positionMs !== 'number' ||
        !Number.isFinite(event.positionMs) ||
        event.positionMs < 0 ||
        !isNullableFiniteNonNegativeNumber(event.durationMs)
      ) {
        return validationFailure(readRequestId(event), 'time host event was invalid');
      }
      return {
        event: {
          type,
          requestId,
          positionMs: event.positionMs,
          durationMs: event.durationMs,
        },
      };
    }
    case 'buffer.updated': {
      const requestId = event.requestId;
      const bufferedRanges = validateTimeRanges(event.bufferedRanges);
      if (!isNonEmptyString(requestId) || 'error' in bufferedRanges) {
        return validationFailure(readRequestId(event), 'buffer host event was invalid');
      }
      return { event: { type, requestId, bufferedRanges: bufferedRanges.value } };
    }
    case 'tracks.changed': {
      const requestId = event.requestId;
      const tracks = validateTracks(event.tracks);
      if (!isNonEmptyString(requestId) || 'error' in tracks) {
        return validationFailure(readRequestId(event), 'tracks host event was invalid');
      }
      return { event: { type, requestId, tracks: tracks.value } };
    }
    case 'track.selection.changed': {
      const requestId = event.requestId;
      if (
        !isNonEmptyString(requestId) ||
        !isNullableNonEmptyString(event.audioTrackId) ||
        !isNullableNonEmptyString(event.subtitleTrackId) ||
        !isNullableNonEmptyString(event.videoTrackId)
      ) {
        return validationFailure(readRequestId(event), 'track selection host event was invalid');
      }
      return {
        event: {
          type,
          requestId,
          audioTrackId: event.audioTrackId,
          subtitleTrackId: event.subtitleTrackId,
          videoTrackId: event.videoTrackId,
        },
      };
    }
    case 'ended': {
      const requestId = event.requestId;
      if (!isNonEmptyString(requestId)) {
        return validationFailure(readRequestId(event), 'ended host event was invalid');
      }
      return { event: { type, requestId } };
    }
    case 'error': {
      if (!(event.requestId === null || isNonEmptyString(event.requestId))) {
        return validationFailure(undefined, 'error host event request id was invalid');
      }
      const error = normalizeHostErrorPayload(event.error, event.requestId);
      if ('error' in error) {
        return error;
      }
      return { event: { type, requestId: event.requestId, error } };
    }
    default:
      return validationFailure(readRequestId(event), 'host event type is unsupported');
  }
}
