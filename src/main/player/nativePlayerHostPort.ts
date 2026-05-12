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
      events?: readonly NativePlayerHostEvent[];
    }
  | {
      ok: false;
      error: NativePlayerHostFailure;
    };

export interface NativePlayerHostPort {
  execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult>;
  cleanup(requestId: PlayerRequestId | null): Promise<void>;
  onLifecycleFailure?(
    listener: (failure: NativePlayerHostLifecycleFailure) => void,
  ): () => void;
}

export type NativePlayerHostFactory = () => NativePlayerHostPort;
