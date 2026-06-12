import type { PlayerError, PlayerRequestId } from '../../contracts/player.js';
import type { PlexPrivilegedPlaybackDescriptor } from '../plex/streamResolver.js';

export interface PrivilegedPlaybackDispatchContext {
  privatePlayback: PlexPrivilegedPlaybackDescriptor;
}

export type PrivilegedPlaybackDescriptorValidationResult =
  | { ok: true }
  | { ok: false; error: PlayerError };

export function validatePrivilegedPlaybackDescriptor(
  descriptor: PlexPrivilegedPlaybackDescriptor,
  commandRequestId: PlayerRequestId,
): PrivilegedPlaybackDescriptorValidationResult {
  if (!isRecord(descriptor)) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'descriptor-not-object',
      'Privileged playback descriptor is invalid.',
    );
  }

  if (descriptor.requestId !== commandRequestId) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'request-id-mismatch',
      'Privileged playback descriptor request ID does not match command request ID.',
    );
  }

  const kind = descriptor.decisionKind;
  if (kind !== 'direct-play' && kind !== 'direct-stream' && kind !== 'transcode') {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'unsupported-decision-kind',
      'Unsupported privileged playback decision kind.',
    );
  }

  if (!isRecord(descriptor.setup)) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'missing-setup',
      'Privileged playback setup is missing required fields.',
    );
  }

  const mode = descriptor.setup.playbackMode;
  if (mode !== 'direct-play' && mode !== 'direct-stream' && mode !== 'transcode') {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'unsupported-playback-mode',
      'Unsupported privileged playback mode.',
    );
  }

  if (!descriptor.playbackUrl || descriptor.playbackUrl.trim().length === 0) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'empty-playback-url',
      'Privileged playback URL is empty.',
    );
  }

  if (!descriptor.credentialHeader || !descriptor.credentialHeader.name || !descriptor.credentialHeader.value) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      'missing-credential-header',
      'Privileged credential header is missing required fields.',
    );
  }

  const trackMapValidation = validateTrackMap(descriptor.setup.trackMap);
  if (!trackMapValidation.ok) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      trackMapValidation.reason,
      'Privileged playback track map is missing required fields.',
    );
  }

  return { ok: true };
}

function validateTrackMap(value: unknown): { ok: true } | { ok: false; reason: string } {
  if (!isRecord(value)) {
    return { ok: false, reason: 'missing-track-map' };
  }
  for (const key of ['video', 'audio', 'subtitle'] as const) {
    const tracks = value[key];
    if (!Array.isArray(tracks)) {
      return { ok: false, reason: `invalid-${key}-track-map` };
    }
    for (const track of tracks) {
      if (!isRecord(track)) {
        return { ok: false, reason: `invalid-${key}-track-map-item` };
      }
      if (!isNonEmptyString(track.publicTrackId)) {
        return { ok: false, reason: `missing-${key}-public-track-id` };
      }
      if (!(track.privateTrackId === null || isNonEmptyString(track.privateTrackId))) {
        return { ok: false, reason: `invalid-${key}-private-track-id` };
      }
      if (key === 'video') {
        if (track.codec !== null && track.codec !== undefined && typeof track.codec !== 'string') {
          return { ok: false, reason: 'invalid-video-codec' };
        }
        if (!isNonEmptyString(track.dynamicRange)) {
          return { ok: false, reason: 'invalid-video-dynamic-range' };
        }
      }
    }
  }
  return { ok: true };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function invalidPrivilegedPlaybackDescriptor(
  commandRequestId: PlayerRequestId,
  reason: string,
  message: string,
): PrivilegedPlaybackDescriptorValidationResult {
  return {
    ok: false,
    error: {
      code: 'PLAYER_PRIVILEGED_DESCRIPTOR_INVALID',
      category: 'validation-failure',
      message,
      recoverable: false,
      retryable: false,
      requestId: commandRequestId,
      diagnostic: {
        component: 'privileged-playback-dispatch-context',
        operation: 'validate',
        status: 'rejected',
        reason,
      },
    },
  };
}
