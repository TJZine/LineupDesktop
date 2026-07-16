export const CHANNEL_SETUP_STATUS_VALUES = [
  'not-configured',
  'configured',
  'recovering',
  'recovery-failed',
] as const;

export const CHANNEL_SETUP_ERROR_CODES = [
  'CHANNEL_UNAUTHORIZED',
  'CHANNEL_VALIDATION_FAILED',
  'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
  'CHANNEL_PLEX_REQUIRED',
  'CHANNEL_STORAGE_UNAVAILABLE',
  'CHANNEL_STORAGE_CORRUPT',
  'CHANNEL_STORAGE_UNSUPPORTED_VERSION',
  'CHANNEL_BUILD_ACTIVE',
  'CHANNEL_BUILD_ID_REUSED',
  'CHANNEL_BUILD_ID_CAPACITY',
  'CHANNEL_BUILD_CANCELED',
  'CHANNEL_BUILD_TOO_LATE',
  'CHANNEL_UNKNOWN',
] as const;

export const CHANNEL_SETUP_OPERATIONS = [
  'getStatus',
  'getRecord',
  'preview',
  'review',
  'build',
  'cancelBuild',
  'commit',
] as const;

export const CHANNEL_SETUP_COMMIT_MODES = ['append', 'replace', 'merge'] as const;

export const CHANNEL_SETUP_STRATEGY_KEYS = [
  'playlists',
  'collections',
  'recentlyAdded',
  'genres',
  'studios',
  'actors',
  'decades',
  'directors',
] as const;

export const CHANNEL_SETUP_PROGRESS_TASKS = [
  'fetch_playlists',
  'fetch_collections',
  'fetch_facets',
  'scan_library_items',
  'build_pending',
  'create_channels',
  'apply_channels',
  'refresh_guide',
  'done',
] as const;

export const CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS = [
  'rawPayload',
  'rawPlexPayload',
  'headers',
  'header',
  'authHeaders',
  'authHeader',
  'rawAuthHeaders',
  'token',
  'accessToken',
  'refreshToken',
  'path',
  'filePath',
  'localPath',
  'url',
  'uri',
  'endpointUrl',
  'baseUrl',
  'tokenizedUrl',
  'serverUri',
  'connectionUri',
  'appPath',
  'userDataPath',
  'filesystemPath',
  'persistenceFilePath',
  'storedChannelData',
  'credential',
  'secret',
  'nativeHandle',
] as const;

export type ChannelSetupStatusValue = (typeof CHANNEL_SETUP_STATUS_VALUES)[number];
export type ChannelSetupWorkflowErrorCode = (typeof CHANNEL_SETUP_ERROR_CODES)[number];
export type ChannelSetupErrorCode = Exclude<ChannelSetupWorkflowErrorCode,
  | 'CHANNEL_STORAGE_UNSUPPORTED_VERSION'
  | 'CHANNEL_BUILD_ACTIVE'
  | 'CHANNEL_BUILD_ID_REUSED'
  | 'CHANNEL_BUILD_ID_CAPACITY'
  | 'CHANNEL_BUILD_CANCELED'
  | 'CHANNEL_BUILD_TOO_LATE'>;
export type ChannelSetupOperation = (typeof CHANNEL_SETUP_OPERATIONS)[number];
export type ChannelSetupCommitMode = (typeof CHANNEL_SETUP_COMMIT_MODES)[number];
export type ChannelSetupStrategyKey = (typeof CHANNEL_SETUP_STRATEGY_KEYS)[number];
export type ChannelSetupStrategyScope = 'per-library' | 'cross-library';
export type ChannelSetupActorStudioCombineMode = 'separate' | 'combined';
export type ChannelSetupSeriesPlaybackMode = 'shuffle' | 'sequential' | 'block';
export type ChannelSetupVariantType = 'none' | 'sequential' | 'block';
export type ChannelSetupProgressTask = (typeof CHANNEL_SETUP_PROGRESS_TASKS)[number];

export interface ChannelSetupStrategyConfig {
  enabled: boolean;
  priority: number;
  scope: ChannelSetupStrategyScope;
}

export interface ChannelSetupExpansionConfig {
  addAlternateLineups: boolean;
  alternateLineupCopies: number;
  variantType: ChannelSetupVariantType;
  variantBlockSize: number;
}

export interface ChannelSetupSeriesOrderingConfig {
  basePlaybackMode: ChannelSetupSeriesPlaybackMode;
  baseBlockSize: number;
}

export interface ChannelSetupConfigDraft {
  selectedLibraryIds: readonly string[];
  maxChannels: number;
  buildMode: ChannelSetupCommitMode;
  strategyConfig: Partial<Record<ChannelSetupStrategyKey, Partial<ChannelSetupStrategyConfig>>>;
  channelExpansion?: Partial<ChannelSetupExpansionConfig>;
  seriesOrdering?: Partial<ChannelSetupSeriesOrderingConfig>;
  actorStudioCombineMode: ChannelSetupActorStudioCombineMode;
  minItemsPerChannel: number;
}

export interface ChannelSetupConfig {
  selectedLibraryIds: readonly string[];
  maxChannels: number;
  buildMode: ChannelSetupCommitMode;
  strategyConfig: Readonly<Record<ChannelSetupStrategyKey, ChannelSetupStrategyConfig>>;
  channelExpansion: ChannelSetupExpansionConfig;
  seriesOrdering: ChannelSetupSeriesOrderingConfig;
  actorStudioCombineMode: ChannelSetupActorStudioCombineMode;
  minItemsPerChannel: number;
}

export interface ChannelSetupEstimates {
  total: number;
  playlists: number;
  collections: number;
  recentlyAdded: number;
  genres: number;
  studios: number;
  actors: number;
  decades: number;
  directors: number;
}

export interface ChannelSetupPreview {
  status: 'ready' | 'blocked' | 'slow';
  config: ChannelSetupConfig;
  estimates: ChannelSetupEstimates;
  eligibleGeneratedCount: number;
  selectedGeneratedCount: number;
  droppedByMinItemsCount: number;
  droppedByPlanCapCount: number;
  reachedMaxChannels: boolean;
  warnings: readonly string[];
  message?: string;
  failureReason?: 'unsupported' | 'empty' | 'timeout' | 'error' | 'transient';
}

export interface ChannelSetupDiffSummary {
  created: number;
  removed: number;
  unchanged: number;
}

export interface ChannelSetupDiffSamples {
  created: readonly string[];
  removed: readonly string[];
  unchanged: readonly string[];
}

export interface ChannelSetupReview {
  preview: ChannelSetupPreview;
  diff: {
    summary: ChannelSetupDiffSummary;
    samples: ChannelSetupDiffSamples;
  };
}

export type ChannelSetupRecordSummary =
  | { status: 'missing' }
  | { status: 'ready'; config: ChannelSetupConfig; createdAtMs: number; updatedAtMs: number }
  | { status: 'corrupt' }
  | { status: 'unsupported-version' }
  | { status: 'unavailable' };

export interface ChannelSetupBuildProgress {
  task: ChannelSetupProgressTask;
  current: number;
  total: number | null;
  label: string;
  detail: string;
}

export type ChannelSetupGuideRefreshResult =
  | { kind: 'completed' }
  | { kind: 'failed'; message: string }
  | { kind: 'interrupted'; message: string };

export interface ChannelSetupBuildCounts {
  plannedGeneratedCount: number;
  createdCount: number;
  updatedCount: number;
  preservedCount: number;
  removedCount: number;
  skippedCount: number;
  reachedMaxChannels: boolean;
  channelNumberCapacityExhausted: boolean;
  errorCount: number;
}

export type ChannelSetupBuildResult =
  | { kind: 'canceled'; buildId: string; counts: ChannelSetupBuildCounts; warnings: readonly string[] }
  | { kind: 'failed'; buildId: string; counts: ChannelSetupBuildCounts; warnings: readonly string[]; error: ChannelSetupWorkflowError }
  | {
      kind: 'committed' | 'committed-with-record-warning';
      buildId: string;
      counts: ChannelSetupBuildCounts;
      warnings: readonly string[];
      guideRefresh: ChannelSetupGuideRefreshResult;
    };

export type ChannelSetupCancelStatus = 'accepted' | 'too-late' | 'not-active';

export interface ChannelSetupCancelResult {
  buildId: string;
  status: ChannelSetupCancelStatus;
}

export interface ChannelSetupPersistedChannelSummary {
  id: string;
  number: number;
  name: string;
  sourceLibraryId: string | null;
  sourceLibraryName: string | null;
  itemCount: number;
}

export interface ChannelSetupSummary {
  status: ChannelSetupStatusValue;
  channelCount: number;
  currentChannelId: string | null;
  currentChannelNumber: number | null;
  currentChannelName: string | null;
  channelNumbers: readonly number[];
  channels: readonly ChannelSetupPersistedChannelSummary[];
  updatedAtMs: number;
  recovery: {
    loaded: boolean;
    repaired: boolean;
  };
}

export interface ChannelSetupRuntimeError {
  code: ChannelSetupErrorCode;
  message: string;
  retryable: boolean;
  recoverable: boolean;
  operation: ChannelSetupOperation;
}

export interface ChannelSetupWorkflowError extends Omit<ChannelSetupRuntimeError, 'code'> {
  code: ChannelSetupWorkflowErrorCode;
}

export type ChannelSetupIpcResult<TValue> =
  | { ok: true; requestId: string; value: TValue }
  | { ok: false; requestId: string; error: ChannelSetupRuntimeError };

export type ChannelSetupWorkflowIpcResult<TValue> =
  | { ok: true; requestId: string; value: TValue }
  | { ok: false; requestId: string; error: ChannelSetupWorkflowError };

export type ChannelSetupEmptyRequest = {
  requestId: string;
  payload: Record<string, never>;
};

export type ChannelSetupCommitRequest = {
  requestId: string;
  payload: {
    mode: ChannelSetupCommitMode;
    sectionIds: readonly string[];
    confirmReplace?: boolean;
  };
};

export type ChannelSetupConfigRequest = {
  requestId: string;
  payload: { config: ChannelSetupConfigDraft };
};

export type ChannelSetupBuildRequest = {
  requestId: string;
  payload: { buildId: string; config: ChannelSetupConfigDraft; confirmReplace: boolean };
};

export type ChannelSetupCancelRequest = {
  requestId: string;
  payload: { buildId: string };
};

export interface ChannelSetupProgressEnvelope {
  buildId: string;
  buildRequestId: string;
  sequence: number;
  progress: ChannelSetupBuildProgress;
}

export function channelSetupSuccess<TValue>(
  requestId: string,
  value: TValue,
): ChannelSetupIpcResult<TValue> {
  return { ok: true, requestId, value };
}

export function channelSetupFailure<TValue>(
  requestId: string,
  error: ChannelSetupRuntimeError,
): ChannelSetupIpcResult<TValue> {
  return { ok: false, requestId, error };
}
