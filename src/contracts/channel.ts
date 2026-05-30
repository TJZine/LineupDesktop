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
  'CHANNEL_UNKNOWN',
] as const;

export const CHANNEL_SETUP_OPERATIONS = ['getStatus', 'commit'] as const;

export const CHANNEL_SETUP_COMMIT_MODES = ['append', 'replace'] as const;

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
export type ChannelSetupOperation = (typeof CHANNEL_SETUP_OPERATIONS)[number];
export type ChannelSetupCommitMode = (typeof CHANNEL_SETUP_COMMIT_MODES)[number];

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

export type ChannelSetupIpcResult<TValue> =
  | { ok: true; requestId: string; value: TValue }
  | { ok: false; requestId: string; error: ChannelSetupRuntimeError };

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
