import type {
  ChannelBuilderStrategyKey,
  ChannelSetupConfig,
  ChannelSetupReviewDiff,
  ChannelSetupWarning,
  NormalizedChannelSetupConfig,
} from '../domain/channelBuilder/types.js';

export const CHANNEL_SETUP_STATUS_VALUES = [
  'not-configured',
  'configured',
  'recovering',
  'recovery-failed',
] as const;

export const CHANNEL_SETUP_ERROR_CODES = [
  'CHANNEL_UNAUTHORIZED',
  'CHANNEL_VALIDATION_FAILED',
  'CHANNEL_BUSY',
  'CHANNEL_PLEX_REQUIRED',
  'CHANNEL_CONTEXT_CHANGED',
  'CHANNEL_LINEUP_CONFLICT',
  'CHANNEL_PLAN_NOT_FOUND',
  'CHANNEL_PLAN_EXPIRED',
  'CHANNEL_PLAN_ALREADY_USED',
  'CHANNEL_OPERATION_NOT_FOUND',
  'CHANNEL_OPERATION_EXPIRED',
  'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
  'CHANNEL_REPLACEMENT_EMPTY',
  'CHANNEL_STORAGE_UNAVAILABLE',
  'CHANNEL_STORAGE_CORRUPT',
  'CHANNEL_UNKNOWN',
] as const;

export const CHANNEL_SETUP_OPERATIONS = [
  'getStatus',
  'startReview',
  'startApply',
  'getOperation',
  'cancel',
] as const;

export const CHANNEL_SETUP_BUILD_MODES = ['append', 'replace', 'merge'] as const;

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
export type ChannelSetupErrorCode = (typeof CHANNEL_SETUP_ERROR_CODES)[number];
export type ChannelSetupOperationName = (typeof CHANNEL_SETUP_OPERATIONS)[number];
export type ChannelSetupBuildMode = (typeof CHANNEL_SETUP_BUILD_MODES)[number];

export type {
  ChannelSetupConfig,
  ChannelSetupReviewDiff,
  ChannelSetupWarning,
  NormalizedChannelSetupConfig,
};

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
  lineupRevision: number;
  channelCount: number;
  currentChannelId: string | null;
  currentChannelNumber: number | null;
  currentChannelName: string | null;
  channelNumbers: readonly number[];
  channels: readonly ChannelSetupPersistedChannelSummary[];
  builder:
    | {
        completion: 'unknown';
        normalizedConfig: null;
        completedAtMs: null;
      }
    | {
        completion: 'complete';
        normalizedConfig: NormalizedChannelSetupConfig;
        completedAtMs: number;
      };
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
  operation: ChannelSetupOperationName;
}

export interface ChannelSetupOperationProgress {
  completed: number;
  total: number | null;
}

type ChannelSetupOperationBase = {
  operationId: string;
  startedAtMs: number;
  updatedAtMs: number;
  progress: ChannelSetupOperationProgress;
};

export type ChannelSetupApplySummary = Readonly<{
  created: number;
  removed: number;
  unchanged: number;
  skipped: number;
  finalChannelCount: number;
  reachedMaxChannels: boolean;
  watchChannelId: string | null;
  byStrategy: Readonly<
    Record<ChannelBuilderStrategyKey, Readonly<{ created: number; skipped: number }>>
  >;
  warnings: readonly ChannelSetupWarning[];
}>;

export type ChannelSetupOperation =
  | (ChannelSetupOperationBase & {
      kind: 'review';
      state: 'queued';
      phase: 'discover-facets';
      result: null;
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'review';
      state: 'running' | 'canceling';
      phase: 'discover-facets' | 'plan';
      result: null;
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'review';
      state: 'review-ready';
      phase: 'review-ready';
      result: {
        kind: 'review';
        planId: string | null;
        contextEpoch: number;
        lineupRevision: number;
        status: 'ready' | 'slow' | 'blocked';
        diff: ChannelSetupReviewDiff;
        warnings: readonly ChannelSetupWarning[];
        reachedCap: boolean;
      };
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'apply';
      state: 'queued' | 'canceling';
      phase: 'materialize';
      result: null;
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'apply';
      state: 'running';
      phase: 'materialize' | 'persist' | 'refresh-guide';
      result: null;
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'apply';
      state: 'succeeded';
      phase: 'done';
      result: {
        kind: 'apply';
        commit: 'committed';
        summary: ChannelSetupApplySummary;
        guideRefresh: 'completed' | 'failed';
      };
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'review' | 'apply';
      state: 'canceled';
      phase: 'done';
      result: { kind: 'canceled' };
      error: null;
    })
  | (ChannelSetupOperationBase & {
      kind: 'review' | 'apply';
      state: 'failed';
      phase: 'done';
      result: null;
      error: ChannelSetupRuntimeError;
    });

export type ChannelSetupIpcResult<TValue> =
  | { ok: true; requestId: string; value: TValue }
  | { ok: false; requestId: string; error: ChannelSetupRuntimeError };

export type ChannelSetupGetStatusRequest = {
  requestId: string;
  payload: Record<string, never>;
};

export type ChannelSetupStartReviewRequest = {
  requestId: string;
  payload: { config: ChannelSetupConfig };
};

export type ChannelSetupStartApplyRequest = {
  requestId: string;
  payload: { planId: string; confirmReplace: boolean };
};

export type ChannelSetupGetOperationRequest = {
  requestId: string;
  payload: { operationId: string };
};

export type ChannelSetupCancelRequest = ChannelSetupGetOperationRequest;

export type ChannelSetupAcceptedOperation = {
  accepted: true;
  operation: ChannelSetupOperation;
};

export type ChannelSetupOperationResult = {
  operation: ChannelSetupOperation;
};

export type ChannelSetupCancelResult = {
  accepted: boolean;
  reason: null | 'already-terminal' | 'commit-started';
  operation: ChannelSetupOperation;
};

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
