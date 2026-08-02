import type {
  PlayerCommand,
  PlayerError,
  PlayerErrorCategory,
  PlayerMediaSummary,
  PlayerRequestId,
  PlayerStatus,
  PlayerTimeRange,
  PlayerTrackId,
  PlayerTrackSummary,
  PlayerPlaybackQualitySummary,
} from '../../contracts/player.js';

export type NativePlayerHostStatus = Extract<
  PlayerStatus,
  'ready' | 'buffering' | 'playing' | 'paused' | 'seeking' | 'stalled'
>;

export type NativePlayerHostFailureCategory = Exclude<
  PlayerErrorCategory,
  'stale-request' | 'validation-failure'
>;

export type NativePlayerHostEvent =
  | {
      type: 'media.loaded';
      requestId: PlayerRequestId;
      media: PlayerMediaSummary;
      durationMs: number | null;
      tracks?: readonly PlayerTrackSummary[];
    }
  | {
      type: 'playback.state';
      requestId: PlayerRequestId;
      status: NativePlayerHostStatus;
      playing: boolean;
    }
  | {
      type: 'time.updated';
      requestId: PlayerRequestId;
      positionMs: number;
      durationMs: number | null;
    }
  | {
      type: 'buffer.updated';
      requestId: PlayerRequestId;
      bufferedRanges: readonly PlayerTimeRange[];
    }
  | {
      type: 'tracks.changed';
      requestId: PlayerRequestId;
      tracks: readonly PlayerTrackSummary[];
    }
  | {
      type: 'track.selection.changed';
      requestId: PlayerRequestId;
      audioTrackId: PlayerTrackId | null;
      subtitleTrackId: PlayerTrackId | null;
      videoTrackId: PlayerTrackId | null;
    }
  | {
      type: 'quality.changed';
      requestId: PlayerRequestId;
      quality: PlayerPlaybackQualitySummary;
    }
  | {
      type: 'ended';
      requestId: PlayerRequestId;
    }
  | {
      type: 'error';
      requestId: PlayerRequestId | null;
      error: PlayerError;
    };

export interface NativePlayerHostFailure {
  code: string;
  message: string;
  category: NativePlayerHostFailureCategory;
  recoverable: boolean;
  retryable: boolean;
}

export interface NativePlayerHostLifecycleFailure {
  requestId: PlayerRequestId | null;
  error: NativePlayerHostFailure;
}

export type NativePlayerHostCommandResult =
  | {
      ok: true;
      events?: unknown;
    }
  | {
      ok: false;
      error: NativePlayerHostFailure;
    };

export interface NativeAudioOutput {
  nativeKey: string;
  label: string;
}

export type NativePlayerHostAudioOutputResult =
  | { ok: true; outputs: NativeAudioOutput[] }
  | { ok: false; error: NativePlayerHostFailure };

export interface NativePlayerPresentationUpdate {
  documentEpoch: number;
  revision: number;
  parentHwnd: string;
  parentPid: number;
  loadedRequestId: PlayerRequestId | null;
  mode: 'hidden' | 'player-full' | 'guide-overlay-full' | 'guide-classic-pip';
  bounds: { x: number; y: number; width: number; height: number } | null;
}

export type NativePlayerPresentationResult =
  | { ok: true; status: 'applied' | 'hidden' | 'stale' }
  | {
      ok: false;
      classification: 'pre-send-rejected' | 'shared-host-failure';
      error: NativePlayerHostFailure;
    };

import type { PrivilegedPlaybackDispatchContext } from './privilegedPlaybackDispatchContext.js';

export interface NativePlayerHostPort {
  execute(
    command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<NativePlayerHostCommandResult>;
  queryAudioOutputs(requestId: PlayerRequestId): Promise<NativePlayerHostAudioOutputResult>;
  updatePresentation?(
    update: NativePlayerPresentationUpdate,
  ): Promise<NativePlayerPresentationResult>;
  cleanup(requestId: PlayerRequestId | null): Promise<void>;
  onLifecycleFailure?(
    listener: (failure: NativePlayerHostLifecycleFailure) => void,
  ): () => void;
  onEvent?(
    listener: (event: unknown) => void,
  ): () => void;
}

export type NativePlayerHostFactory = () => NativePlayerHostPort;
