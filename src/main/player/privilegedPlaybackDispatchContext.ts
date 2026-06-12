import type { PlayerError, PlayerRequestId } from '../../contracts/player.js';
import type { PlexPrivilegedPlaybackDescriptor } from '../plex/streamResolver.js';

type TrackMapKey = 'video' | 'audio' | 'subtitle';
type ValidatedTrackMapItem = {
  publicTrackId: string;
  privateTrackId: string | null;
};
type ValidatedTrackMap = Record<TrackMapKey, readonly ValidatedTrackMapItem[]>;
type ValidatedTrackSelection = Record<TrackMapKey, string | null>;

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

  const setupValidation = validatePlaybackSetup(descriptor.setup);
  if (!setupValidation.ok) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      setupValidation.reason,
      'Privileged playback setup is missing required fields.',
    );
  }

  const { setup } = setupValidation;
  const mode = setup.playbackMode;
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

  const selectedValidation = validateSelectedTrackConsistency(
    setup.selectedTrackIds,
    setup.selectedPrivateTrackIds,
    setup.trackMap,
  );
  if (!selectedValidation.ok) {
    return invalidPrivilegedPlaybackDescriptor(
      commandRequestId,
      selectedValidation.reason,
      'Privileged playback track map is missing required fields.',
    );
  }

  return { ok: true };
}

function validatePlaybackSetup(
  value: unknown,
): { ok: true; setup: ValidatedPlaybackSetup } | { ok: false; reason: string } {
  if (!isRecord(value)) {
    return { ok: false, reason: 'missing-setup' };
  }
  if (
    !hasOnlyKeys(value, [
      'playbackMode',
      'mediaPath',
      'variantId',
      'partPath',
      'selectedTrackIds',
      'selectedPrivateTrackIds',
      'trackMap',
    ])
  ) {
    return { ok: false, reason: 'unsupported-setup-field' };
  }
  if (
    !isNonEmptyString(value.mediaPath) ||
    !isNonEmptyString(value.variantId) ||
    !isNonEmptyString(value.partPath)
  ) {
    return { ok: false, reason: 'invalid-setup-scalar' };
  }
  const selectedTrackIds = validateTrackSelection(value.selectedTrackIds, 'selected-track-ids');
  if (!selectedTrackIds.ok) {
    return selectedTrackIds;
  }
  const selectedPrivateTrackIds = validateTrackSelection(
    value.selectedPrivateTrackIds,
    'selected-private-track-ids',
  );
  if (!selectedPrivateTrackIds.ok) {
    return selectedPrivateTrackIds;
  }
  const trackMap = validateTrackMap(value.trackMap);
  if (!trackMap.ok) {
    return trackMap;
  }
  return {
    ok: true,
    setup: {
      playbackMode: value.playbackMode,
      selectedTrackIds: selectedTrackIds.selection,
      selectedPrivateTrackIds: selectedPrivateTrackIds.selection,
      trackMap: trackMap.map,
    },
  };
}

type ValidatedPlaybackSetup = {
  playbackMode: unknown;
  selectedTrackIds: ValidatedTrackSelection;
  selectedPrivateTrackIds: ValidatedTrackSelection;
  trackMap: ValidatedTrackMap;
};

function validateTrackSelection(
  value: unknown,
  reasonPrefix: string,
): { ok: true; selection: ValidatedTrackSelection } | { ok: false; reason: string } {
  if (!isRecord(value) || !hasOnlyKeys(value, ['video', 'audio', 'subtitle'])) {
    return { ok: false, reason: `invalid-${reasonPrefix}` };
  }
  const selection: Partial<ValidatedTrackSelection> = {};
  for (const key of TRACK_MAP_KEYS) {
    const trackId = value[key];
    if (!(trackId === null || isNonEmptyString(trackId))) {
      return { ok: false, reason: `invalid-${reasonPrefix}-${key}` };
    }
    selection[key] = trackId;
  }
  return { ok: true, selection: selection as ValidatedTrackSelection };
}

function validateTrackMap(
  value: unknown,
): { ok: true; map: ValidatedTrackMap } | { ok: false; reason: string } {
  if (!isRecord(value)) {
    return { ok: false, reason: 'missing-track-map' };
  }
  if (!hasOnlyKeys(value, TRACK_MAP_KEYS)) {
    return { ok: false, reason: 'unsupported-track-map-field' };
  }

  const seenPublicTrackIds = new Set<string>();
  const map: Partial<Record<TrackMapKey, ValidatedTrackMapItem[]>> = {};
  for (const key of TRACK_MAP_KEYS) {
    const tracks = value[key];
    if (!Array.isArray(tracks)) {
      return { ok: false, reason: `invalid-${key}-track-map` };
    }
    const mappedTracks: ValidatedTrackMapItem[] = [];
    for (const track of tracks) {
      if (!isRecord(track)) {
        return { ok: false, reason: `invalid-${key}-track-map-item` };
      }
      if (!hasOnlyKeys(track, TRACK_ITEM_KEYS[key])) {
        return { ok: false, reason: `unsupported-${key}-track-map-item-field` };
      }
      if (!isNonEmptyString(track.publicTrackId)) {
        return { ok: false, reason: `missing-${key}-public-track-id` };
      }
      if (seenPublicTrackIds.has(track.publicTrackId)) {
        return { ok: false, reason: 'duplicate-public-track-id' };
      }
      seenPublicTrackIds.add(track.publicTrackId);
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
      if (key === 'audio') {
        if (track.label !== undefined && typeof track.label !== 'string') {
          return { ok: false, reason: 'invalid-audio-label' };
        }
        if (track.language !== undefined && typeof track.language !== 'string') {
          return { ok: false, reason: 'invalid-audio-language' };
        }
        if (track.codec !== undefined && typeof track.codec !== 'string') {
          return { ok: false, reason: 'invalid-audio-codec' };
        }
        if (track.channelCount !== undefined && !isFiniteRangeNumber(track.channelCount, 1, 64)) {
          return { ok: false, reason: 'invalid-audio-channel-count' };
        }
        if (track.default !== undefined && typeof track.default !== 'boolean') {
          return { ok: false, reason: 'invalid-audio-default' };
        }
      }
      if (key === 'subtitle') {
        if (track.label !== undefined && typeof track.label !== 'string') {
          return { ok: false, reason: 'invalid-subtitle-label' };
        }
        if (track.language !== undefined && typeof track.language !== 'string') {
          return { ok: false, reason: 'invalid-subtitle-language' };
        }
        if (track.format !== undefined && typeof track.format !== 'string') {
          return { ok: false, reason: 'invalid-subtitle-format' };
        }
        if (track.deliveryType !== undefined && typeof track.deliveryType !== 'string') {
          return { ok: false, reason: 'invalid-subtitle-delivery-type' };
        }
        if (track.forced !== undefined && typeof track.forced !== 'boolean') {
          return { ok: false, reason: 'invalid-subtitle-forced' };
        }
        if (track.default !== undefined && typeof track.default !== 'boolean') {
          return { ok: false, reason: 'invalid-subtitle-default' };
        }
      }
      mappedTracks.push({
        publicTrackId: track.publicTrackId,
        privateTrackId: track.privateTrackId,
      });
    }
    map[key] = mappedTracks;
  }
  return { ok: true, map: map as ValidatedTrackMap };
}

function validateSelectedTrackConsistency(
  selectedTrackIds: ValidatedTrackSelection,
  selectedPrivateTrackIds: ValidatedTrackSelection,
  trackMap: ValidatedTrackMap,
): { ok: true } | { ok: false; reason: string } {
  for (const key of TRACK_MAP_KEYS) {
    const selectedPublicId = selectedTrackIds[key];
    const selectedPrivateId = selectedPrivateTrackIds[key];
    if (selectedPublicId === null) {
      if (selectedPrivateId !== null) {
        return { ok: false, reason: `selected-${key}-private-without-public` };
      }
      continue;
    }
    const mappedTrack = trackMap[key].find((track) => track.publicTrackId === selectedPublicId);
    if (mappedTrack === undefined) {
      return { ok: false, reason: `selected-${key}-public-missing-from-map` };
    }
    if (mappedTrack.privateTrackId !== selectedPrivateId) {
      return { ok: false, reason: `selected-${key}-private-mismatch` };
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

function isFiniteRangeNumber(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}

function hasOnlyKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const allowed = new Set(keys);
  return Object.keys(value).every((key) => allowed.has(key));
}

const TRACK_MAP_KEYS = ['video', 'audio', 'subtitle'] as const;
const TRACK_ITEM_KEYS = {
  video: ['publicTrackId', 'privateTrackId', 'codec', 'dynamicRange'],
  audio: [
    'publicTrackId',
    'privateTrackId',
    'label',
    'language',
    'codec',
    'channelCount',
    'default',
  ],
  subtitle: [
    'publicTrackId',
    'privateTrackId',
    'label',
    'language',
    'format',
    'deliveryType',
    'forced',
    'default',
  ],
} as const satisfies Record<TrackMapKey, readonly string[]>;

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
