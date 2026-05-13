export type PlayerRequestId = string;

export type PlayerMediaId = string;

export type PlayerTrackId = string;

export type PlayerTrackKind = 'audio' | 'subtitle' | 'video';

export type PlayerStatus =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'buffering'
  | 'playing'
  | 'paused'
  | 'seeking'
  | 'stalled'
  | 'ended'
  | 'error'
  | 'destroyed';

export type PlayerCommandName =
  | 'load'
  | 'play'
  | 'pause'
  | 'stop'
  | 'seek.absolute'
  | 'seek.relative'
  | 'volume.set'
  | 'mute.set'
  | 'track.audio.select'
  | 'track.subtitle.select';

export type PlayerTrackDeliveryType =
  | 'embedded'
  | 'sidecar'
  | 'external'
  | 'burned-in'
  | 'unknown';

export type PlayerCapabilitySupport = 'supported' | 'unsupported' | 'unknown' | 'unproven';

export type PlayerSubtitleDeliveryMode =
  | 'embedded'
  | 'sidecar'
  | 'external'
  | 'burn-in'
  | 'none'
  | 'unknown';

export type PlayerErrorCategory =
  | 'source'
  | 'authentication'
  | 'authorization'
  | 'network'
  | 'unsupported-media'
  | 'unsupported-capability'
  | 'timeout'
  | 'aborted'
  | 'stale-request'
  | 'engine-failure'
  | 'helper-failure'
  | 'render-failure'
  | 'track-failure'
  | 'cleanup-failure'
  | 'validation-failure'
  | 'unknown';

export const PLAYER_ERROR_CATEGORIES = [
  'source',
  'authentication',
  'authorization',
  'network',
  'unsupported-media',
  'unsupported-capability',
  'timeout',
  'aborted',
  'stale-request',
  'engine-failure',
  'helper-failure',
  'render-failure',
  'track-failure',
  'cleanup-failure',
  'validation-failure',
  'unknown',
] as const satisfies readonly PlayerErrorCategory[];

export const PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS = [
  'rawMediaUrl',
  'tokenizedUrl',
  'authHeaders',
  'rawAuthHeaders',
  'persistentToken',
  'credentialMaterial',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
] as const;

export type PlayerForbiddenPrivilegedFieldKey =
  (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number];

/** Renderer-safe player validation rejects known privileged field names without proving arbitrary strings or unlisted keys secret-free. */ export interface PlayerMediaSummary {
  id: PlayerMediaId;
  title: string;
  subtitle?: string;
  durationMs?: number | null;
  container?: string;
}

export interface PlayerLoadPolicy {
  autoplay: boolean;
  startPositionMs?: number;
  preferredAudioTrackId?: PlayerTrackId | null;
  preferredSubtitleTrackId?: PlayerTrackId | null;
}

export interface PlayerLoadCommandPayload {
  media: PlayerMediaSummary;
  policy: PlayerLoadPolicy;
  capabilityProfileId?: string;
}

export interface PlayerSeekAbsolutePayload {
  positionMs: number;
}

export interface PlayerSeekRelativePayload {
  deltaMs: number;
}

export interface PlayerSetVolumePayload {
  volume: number;
}

export interface PlayerSetMutePayload {
  muted: boolean;
}

export interface PlayerSelectAudioTrackPayload {
  trackId: PlayerTrackId;
}

export interface PlayerSelectSubtitleTrackPayload {
  trackId: PlayerTrackId | null;
}

export type PlayerCommand =
  | {
      command: 'load';
      requestId: PlayerRequestId;
      payload: PlayerLoadCommandPayload;
    }
  | {
      command: 'play' | 'pause' | 'stop';
      requestId: PlayerRequestId;
      payload: Record<string, never>;
    }
  | {
      command: 'seek.absolute';
      requestId: PlayerRequestId;
      payload: PlayerSeekAbsolutePayload;
    }
  | {
      command: 'seek.relative';
      requestId: PlayerRequestId;
      payload: PlayerSeekRelativePayload;
    }
  | {
      command: 'volume.set';
      requestId: PlayerRequestId;
      payload: PlayerSetVolumePayload;
    }
  | {
      command: 'mute.set';
      requestId: PlayerRequestId;
      payload: PlayerSetMutePayload;
    }
  | {
      command: 'track.audio.select';
      requestId: PlayerRequestId;
      payload: PlayerSelectAudioTrackPayload;
    }
  | {
      command: 'track.subtitle.select';
      requestId: PlayerRequestId;
      payload: PlayerSelectSubtitleTrackPayload;
    };

export interface PlayerTrackSummary {
  id: PlayerTrackId;
  kind: PlayerTrackKind;
  label: string;
  language?: string;
  codec?: string;
  format?: string;
  channelCount?: number;
  deliveryType?: PlayerTrackDeliveryType;
  forced?: boolean;
  default?: boolean;
  selected: boolean;
  available: boolean;
}

export interface PlaybackCapabilityProfile {
  id: string;
  containerFormats: readonly string[];
  videoCodecs: readonly string[];
  audioCodecs: readonly string[];
  subtitleDeliveryModes: readonly PlayerSubtitleDeliveryMode[];
  headerAuthSetup: PlayerCapabilitySupport;
  seek: PlayerCapabilitySupport;
  volume: PlayerCapabilitySupport;
  audioTrackSwitching: PlayerCapabilitySupport;
  subtitleTrackSwitching: PlayerCapabilitySupport;
  overlayComposition: PlayerCapabilitySupport;
  fullscreenHandling: PlayerCapabilitySupport;
  livePlayback: PlayerCapabilitySupport;
  diagnostics: PlayerCapabilitySupport;
}

export interface PlayerRendererSafeDiagnostic {
  component: string;
  operation: string;
  status?: string;
  reason?: string;
  counts?: Readonly<Record<string, number>>;
  capabilityProfileId?: string;
  trackIds?: readonly PlayerTrackId[];
  media?: Pick<PlayerMediaSummary, 'id' | 'title'>;
  timestampMs?: number;
}

export interface PlayerError {
  code: string;
  category: PlayerErrorCategory;
  message: string;
  recoverable: boolean;
  retryable: boolean;
  requestId?: PlayerRequestId;
  diagnostic?: PlayerRendererSafeDiagnostic;
}

export interface PlayerSnapshot {
  requestId: PlayerRequestId | null;
  status: PlayerStatus;
  media: PlayerMediaSummary | null;
  capabilityProfileId: string | null;
  positionMs: number;
  durationMs: number | null;
  bufferedRanges: readonly PlayerTimeRange[];
  playing: boolean;
  volume: number;
  muted: boolean;
  playbackRate: number;
  selectedAudioTrackId: PlayerTrackId | null;
  selectedSubtitleTrackId: PlayerTrackId | null;
  selectedVideoTrackId: PlayerTrackId | null;
  tracks: readonly PlayerTrackSummary[];
  lastError: PlayerError | null;
}

export type PlayerIpcResult<T> =
  | { ok: true; value: T; requestId: PlayerRequestId }
  | { ok: false; error: PlayerError; requestId: PlayerRequestId };

export interface PlayerDispatchResult {
  accepted: boolean;
  events: readonly PlayerEvent[];
  snapshot: PlayerSnapshot;
}

export interface PlayerTimeRange {
  startMs: number;
  endMs: number;
}

export type PlayerEvent =
  | {
      event: 'state.changed';
      requestId: PlayerRequestId | null;
      snapshot: PlayerSnapshot;
    }
  | {
      event: 'time.updated';
      requestId: PlayerRequestId;
      positionMs: number;
      durationMs: number | null;
    }
  | {
      event: 'buffer.updated';
      requestId: PlayerRequestId;
      bufferedRanges: readonly PlayerTimeRange[];
    }
  | {
      event: 'media.loaded';
      requestId: PlayerRequestId;
      media: PlayerMediaSummary;
      durationMs: number | null;
    }
  | {
      event: 'tracks.changed';
      requestId: PlayerRequestId;
      tracks: readonly PlayerTrackSummary[];
    }
  | {
      event: 'track.selection.changed';
      requestId: PlayerRequestId;
      audioTrackId: PlayerTrackId | null;
      subtitleTrackId: PlayerTrackId | null;
      videoTrackId: PlayerTrackId | null;
    }
  | {
      event: 'command.settled';
      requestId: PlayerRequestId;
      command: PlayerCommandName;
      ok: boolean;
      error?: PlayerError;
    }
  | {
      event: 'ended';
      requestId: PlayerRequestId;
    }
  | {
      event: 'warning';
      requestId: PlayerRequestId | null;
      warning: PlayerError;
    }
  | {
      event: 'error';
      requestId: PlayerRequestId | null;
      error: PlayerError;
    };

export const PLAYER_STATUS_VALUES = [
  'idle',
  'loading',
  'ready',
  'buffering',
  'playing',
  'paused',
  'seeking',
  'stalled',
  'ended',
  'error',
  'destroyed',
] as const satisfies readonly PlayerStatus[];

export const PLAYER_COMMAND_VALUES = [
  'load',
  'play',
  'pause',
  'stop',
  'seek.absolute',
  'seek.relative',
  'volume.set',
  'mute.set',
  'track.audio.select',
  'track.subtitle.select',
] as const satisfies readonly PlayerCommandName[];

export const PLAYER_TRACK_KIND_VALUES = [
  'audio',
  'subtitle',
  'video',
] as const satisfies readonly PlayerTrackKind[];

export const PLAYER_TRACK_DELIVERY_TYPE_VALUES = [
  'embedded',
  'sidecar',
  'external',
  'burned-in',
  'unknown',
] as const satisfies readonly PlayerTrackDeliveryType[];

/** Guards player events before renderer delivery by checking expected shapes and recursively rejecting known privileged field names. */ export function isRendererSafePlayerEvent(value: unknown): value is PlayerEvent {
  if (!isPlainRecord(value) || hasPlayerForbiddenPrivilegedField(value)) {
    return false;
  }

  switch (value.event) {
    case 'state.changed':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'snapshot']) &&
        isNullableNonEmptyString(value.requestId) &&
        isRendererSafePlayerSnapshot(value.snapshot)
      );
    case 'time.updated':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'positionMs', 'durationMs']) &&
        isNonEmptyString(value.requestId) &&
        isFiniteNonNegativeNumber(value.positionMs) &&
        isNullableFiniteNonNegativeNumber(value.durationMs)
      );
    case 'buffer.updated':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'bufferedRanges']) &&
        isNonEmptyString(value.requestId) &&
        isRendererSafeTimeRanges(value.bufferedRanges)
      );
    case 'media.loaded':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'media', 'durationMs']) &&
        isNonEmptyString(value.requestId) &&
        isRendererSafeMediaSummary(value.media) &&
        isNullableFiniteNonNegativeNumber(value.durationMs)
      );
    case 'tracks.changed':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'tracks']) &&
        isNonEmptyString(value.requestId) &&
        isRendererSafeTracks(value.tracks)
      );
    case 'track.selection.changed':
      return (
        hasOnlyKeys(value, [
          'event',
          'requestId',
          'audioTrackId',
          'subtitleTrackId',
          'videoTrackId',
        ]) &&
        isNonEmptyString(value.requestId) &&
        isNullableNonEmptyString(value.audioTrackId) &&
        isNullableNonEmptyString(value.subtitleTrackId) &&
        isNullableNonEmptyString(value.videoTrackId)
      );
    case 'command.settled': {
      if (
        !isNonEmptyString(value.requestId) ||
        !isStringInSet(value.command, PLAYER_COMMAND_VALUES) ||
        typeof value.ok !== 'boolean'
      ) {
        return false;
      }
      if (value.ok) {
        return hasOnlyKeys(value, ['event', 'requestId', 'command', 'ok']);
      }
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'command', 'ok', 'error']) &&
        isRendererSafePlayerError(value.error)
      );
    }
    case 'ended':
      return (
        hasOnlyKeys(value, ['event', 'requestId']) &&
        isNonEmptyString(value.requestId)
      );
    case 'warning':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'warning']) &&
        isNullableNonEmptyString(value.requestId) &&
        isRendererSafePlayerError(value.warning)
      );
    case 'error':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'error']) &&
        isNullableNonEmptyString(value.requestId) &&
        isRendererSafePlayerError(value.error)
      );
    default:
      return false;
  }
}

export function hasPlayerForbiddenPrivilegedField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasPlayerForbiddenPrivilegedField(item));
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return (
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as PlayerForbiddenPrivilegedFieldKey,
      ) || hasPlayerForbiddenPrivilegedField(child)
    );
  });
}

function isRendererSafePlayerSnapshot(value: unknown): value is PlayerSnapshot {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, [
      'requestId',
      'status',
      'media',
      'capabilityProfileId',
      'positionMs',
      'durationMs',
      'bufferedRanges',
      'playing',
      'volume',
      'muted',
      'playbackRate',
      'selectedAudioTrackId',
      'selectedSubtitleTrackId',
      'selectedVideoTrackId',
      'tracks',
      'lastError',
    ]) &&
    isNullableNonEmptyString(value.requestId) &&
    isStringInSet(value.status, PLAYER_STATUS_VALUES) &&
    (value.media === null || isRendererSafeMediaSummary(value.media)) &&
    (value.capabilityProfileId === null || isNonEmptyString(value.capabilityProfileId)) &&
    isFiniteNonNegativeNumber(value.positionMs) &&
    isNullableFiniteNonNegativeNumber(value.durationMs) &&
    isRendererSafeTimeRanges(value.bufferedRanges) &&
    typeof value.playing === 'boolean' &&
    isFiniteRangeNumber(value.volume, 0, 1) &&
    typeof value.muted === 'boolean' &&
    isFiniteNonNegativeNumber(value.playbackRate) &&
    isNullableNonEmptyString(value.selectedAudioTrackId) &&
    isNullableNonEmptyString(value.selectedSubtitleTrackId) &&
    isNullableNonEmptyString(value.selectedVideoTrackId) &&
    isRendererSafeTracks(value.tracks) &&
    (value.lastError === null || isRendererSafePlayerError(value.lastError))
  );
}

function isRendererSafeMediaSummary(value: unknown): value is PlayerMediaSummary {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'title'], ['subtitle', 'durationMs', 'container']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title) &&
    (value.subtitle === undefined || typeof value.subtitle === 'string') &&
    (value.durationMs === undefined || isNullableFiniteNonNegativeNumber(value.durationMs)) &&
    (value.container === undefined || typeof value.container === 'string')
  );
}

function isRendererSafeTracks(value: unknown): value is readonly PlayerTrackSummary[] {
  return Array.isArray(value) && value.every((track) => isRendererSafeTrack(track));
}

function isRendererSafeTrack(value: unknown): value is PlayerTrackSummary {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['id', 'kind', 'label', 'selected', 'available'],
      [
        'language',
        'codec',
        'format',
        'channelCount',
        'deliveryType',
        'forced',
        'default',
      ],
    ) &&
    isNonEmptyString(value.id) &&
    isStringInSet(value.kind, PLAYER_TRACK_KIND_VALUES) &&
    isNonEmptyString(value.label) &&
    (value.language === undefined || typeof value.language === 'string') &&
    (value.codec === undefined || typeof value.codec === 'string') &&
    (value.format === undefined || typeof value.format === 'string') &&
    (value.channelCount === undefined || isFiniteRangeNumber(value.channelCount, 1, 64)) &&
    (value.deliveryType === undefined ||
      isStringInSet(value.deliveryType, PLAYER_TRACK_DELIVERY_TYPE_VALUES)) &&
    (value.forced === undefined || typeof value.forced === 'boolean') &&
    (value.default === undefined || typeof value.default === 'boolean') &&
    typeof value.selected === 'boolean' &&
    typeof value.available === 'boolean'
  );
}

function isRendererSafeTimeRanges(value: unknown): value is readonly PlayerTimeRange[] {
  if (!Array.isArray(value)) {
    return false;
  }
  return value.every((range) => {
    return (
      isPlainRecord(range) &&
      hasOnlyKeys(range, ['startMs', 'endMs']) &&
      isFiniteNonNegativeNumber(range.startMs) &&
      isFiniteNonNegativeNumber(range.endMs) &&
      range.endMs >= range.startMs
    );
  });
}

function isRendererSafePlayerError(value: unknown): value is PlayerError {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['code', 'category', 'message', 'recoverable', 'retryable'],
      ['requestId', 'diagnostic'],
    ) &&
    isNonEmptyString(value.code) &&
    isStringInSet(value.category, PLAYER_ERROR_CATEGORIES) &&
    isNonEmptyString(value.message) &&
    typeof value.recoverable === 'boolean' &&
    typeof value.retryable === 'boolean' &&
    (value.requestId === undefined || isNonEmptyString(value.requestId)) &&
    (value.diagnostic === undefined || isRendererSafeDiagnostic(value.diagnostic))
  );
}

function isRendererSafeDiagnostic(value: unknown): value is PlayerRendererSafeDiagnostic {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['component', 'operation'],
      ['status', 'reason', 'counts', 'capabilityProfileId', 'trackIds', 'media', 'timestampMs'],
    ) &&
    isNonEmptyString(value.component) &&
    isNonEmptyString(value.operation) &&
    (value.status === undefined || typeof value.status === 'string') &&
    (value.reason === undefined || typeof value.reason === 'string') &&
    (value.counts === undefined || isRendererSafeCounts(value.counts)) &&
    (value.capabilityProfileId === undefined || isNonEmptyString(value.capabilityProfileId)) &&
    (value.trackIds === undefined ||
      (Array.isArray(value.trackIds) && value.trackIds.every(isNonEmptyString))) &&
    (value.media === undefined || isRendererSafeDiagnosticMedia(value.media)) &&
    (value.timestampMs === undefined || isFiniteNonNegativeNumber(value.timestampMs))
  );
}

function isRendererSafeCounts(value: unknown): value is Readonly<Record<string, number>> {
  return (
    isPlainRecord(value) &&
    Object.values(value).every((item) => typeof item === 'number' && Number.isFinite(item))
  );
}

function isRendererSafeDiagnosticMedia(
  value: unknown,
): value is Pick<PlayerMediaSummary, 'id' | 'title'> {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'title']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title)
  );
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return requiredKeys.every((key) => Object.hasOwn(value, key));
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isNullableNonEmptyString(value: unknown): value is string | null {
  return value === null || isNonEmptyString(value);
}

function isStringInSet<TValue extends string>(
  value: unknown,
  allowed: readonly TValue[],
): value is TValue {
  return typeof value === 'string' && allowed.includes(value as TValue);
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function isFiniteRangeNumber(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}

function isNullableFiniteNonNegativeNumber(value: unknown): value is number | null {
  return value === null || isFiniteNonNegativeNumber(value);
}
