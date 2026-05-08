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

export interface PlayerMediaSummary {
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
