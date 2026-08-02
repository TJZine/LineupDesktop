import type { ArtworkRef } from './artwork.js';

export interface EpgProgramViewModel {
  id: string;
  title: string;
  subtitle: string;
  description: string;
  showTitle: string;
  episodeLabel: string;
  rating: string;
  quality: readonly string[];
  genres: readonly string[];
  startsAtMs: number;
  endsAtMs: number;
  artwork: ArtworkRef | null;
}

export interface EpgChannelViewModel {
  id: string;
  number: string;
  name: string;
  programs: readonly EpgProgramViewModel[];
}

export interface EpgCurrentProgramViewModel {
  title: string;
  subtitle: string;
  channelId: string;
  startsAtMs: number;
  endsAtMs: number;
}

export interface EpgPresentationSource {
  channels: readonly EpgChannelViewModel[];
  nowWatching: EpgCurrentProgramViewModel | null;
}

export interface GuideGetPresentationRequest {
  requestId: string;
  payload: {
    startTimeMs: number;
    durationMs: number;
  };
}

export interface GuideTuneChannelRequest {
  requestId: string;
  payload: {
    channelId: string;
  };
}

export interface GuideRuntimeError {
  code: string;
  message: string;
  retryable: boolean;
  recoverable: boolean;
  operation: string;
}

export type GuideIpcResult<T> =
  | { ok: true; value: T; requestId: string }
  | { ok: false; error: GuideRuntimeError; requestId: string };
