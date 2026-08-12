import type { GuideArtworkSet } from './artwork.js';

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
  artwork: GuideArtworkSet;
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

export type GuideLibraryContentKind = 'show' | 'movie' | 'mixed';
export type GuideLibraryPersistenceStatus = 'ready' | 'missing' | 'corrupt' | 'unsupported-version';

export interface GuideLibraryFilterOption {
  id: string;
  name: string;
  contentKind: GuideLibraryContentKind;
}

export interface GuideLibraryFilterState {
  scopeToken: string;
  revision: number;
  libraries: readonly GuideLibraryFilterOption[];
  selectedLibraryId: string | null;
  persistenceStatus: GuideLibraryPersistenceStatus;
}

export interface GuidePresentationSource extends EpgPresentationSource {
  channelWindow: { offset: number; total: number };
  libraryFilter: GuideLibraryFilterState;
  minimumStartTimeMs: number;
}

export interface GuideGetPresentationRequest {
  requestId: string;
  payload: {
    startTimeMs: number;
    durationMs: number;
    channelOffset?: number;
    channelLimit?: number;
  };
}

export interface GuideSetLibraryFilterRequest {
  requestId: string;
  payload: {
    expectedScopeToken: string;
    expectedRevision: number;
    libraryId: string | null;
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
