import type {
  ChannelSetupIpcResult,
  ChannelSetupOperation,
  ChannelSetupSummary,
} from '../contracts/channel.js';

export const CHANNEL_SETUP_STATUS_VALUES = [
  'not-configured',
  'configured',
  'recovering',
  'recovery-failed',
] as const;
export const CHANNEL_SETUP_ERROR_CODES = [
  'CHANNEL_UNAUTHORIZED',
  'CHANNEL_VALIDATION_FAILED',
  'CHANNEL_STORAGE_UNAVAILABLE',
  'CHANNEL_STORAGE_CORRUPT',
  'CHANNEL_UNKNOWN',
] as const;
export const CHANNEL_SETUP_OPERATIONS = ['getStatus'] as const;
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

const CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS_LOWER = new Set(
  CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS.map(normalizeForbiddenFieldKey),
);
const CHANNEL_SETUP_REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const CHANNEL_SETUP_MIN_CHANNEL_NUMBER = 1;
const CHANNEL_SETUP_MAX_CHANNEL_NUMBER = 500;
const CHANNEL_SETUP_FORBIDDEN_STRING_PATTERNS = [
  /https?:\/\//iu,
  /file:\/\//iu,
  /\b[A-Za-z]:[\\/]/u,
  /\\\\[A-Za-z0-9._-]+[\\/]/u,
  /\b(?:bearer|token|authorization|headers?)\s*[:=]/iu,
  /\b(?:accessToken|refreshToken|x-plex-token)\b/iu,
] as const;

export function createChannelSetupEmptyRequest(): {
  requestId: string;
  payload: Record<string, never>;
} {
  return {
    requestId: `channel-setup-status-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    payload: {},
  };
}

export function isChannelSetupStatusResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupIpcResult<ChannelSetupSummary> {
  if (!isPlainRecord(value) || hasForbiddenChannelSetupField(value)) {
    return false;
  }
  if (value.ok === true) {
    return (
      hasOnlyKeys(value, ['ok', 'requestId', 'value']) &&
      value.requestId === requestId &&
      isChannelSetupSummary(value.value)
    );
  }
  return (
    value.ok === false &&
    hasOnlyKeys(value, ['ok', 'requestId', 'error']) &&
    value.requestId === requestId &&
    isChannelSetupError(value.error)
  );
}

export function channelSetupValidationFailure(
  requestId: string,
): ChannelSetupIpcResult<ChannelSetupSummary> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'CHANNEL_VALIDATION_FAILED',
      message: 'Channel setup result is invalid.',
      retryable: false,
      recoverable: false,
      operation: 'getStatus',
    },
  };
}

function isChannelSetupSummary(value: unknown): value is ChannelSetupSummary {
  return (
    isPlainRecord(value) &&
    !hasForbiddenChannelSetupField(value) &&
    hasOnlyKeys(value, [
      'status',
      'channelCount',
      'currentChannelId',
      'currentChannelNumber',
      'currentChannelName',
      'channelNumbers',
      'updatedAtMs',
      'recovery',
    ]) &&
    isStringInSet(value.status, CHANNEL_SETUP_STATUS_VALUES) &&
    isFiniteNonNegativeInteger(value.channelCount) &&
    isNullableSafeString(value.currentChannelId) &&
    isNullableChannelNumber(value.currentChannelNumber) &&
    isNullableSafeDisplayString(value.currentChannelName) &&
    Array.isArray(value.channelNumbers) &&
    value.channelNumbers.every(isChannelNumber) &&
    typeof value.updatedAtMs === 'number' &&
    Number.isFinite(value.updatedAtMs) &&
    isRecoverySummary(value.recovery)
  );
}

function isChannelSetupError(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    isStringInSet(value.code, CHANNEL_SETUP_ERROR_CODES) &&
    isSafeChannelSetupString(value.message) &&
    value.message.length > 0 &&
    value.message.length <= 160 &&
    typeof value.retryable === 'boolean' &&
    typeof value.recoverable === 'boolean' &&
    isStringInSet(value.operation, CHANNEL_SETUP_OPERATIONS)
  );
}

function isRecoverySummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['loaded', 'repaired']) &&
    typeof value.loaded === 'boolean' &&
    typeof value.repaired === 'boolean'
  );
}

function hasForbiddenChannelSetupField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenChannelSetupField(item));
  }
  if (typeof value === 'string') {
    return hasForbiddenChannelSetupString(value);
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, entry]) => {
    if (CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS_LOWER.has(normalizeForbiddenFieldKey(key))) {
      return true;
    }
    return hasForbiddenChannelSetupField(entry);
  });
}

function normalizeForbiddenFieldKey(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, '');
}

function hasForbiddenChannelSetupString(value: string): boolean {
  return CHANNEL_SETUP_FORBIDDEN_STRING_PATTERNS.some((pattern) => pattern.test(value));
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasOnlyKeys(value: object, requiredKeys: readonly string[]): boolean {
  const allowed = new Set(requiredKeys);
  return requiredKeys.every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function isStringInSet<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === 'string' && values.includes(value as T);
}

function isNullableSafeString(value: unknown): value is string | null {
  return value === null ||
    (typeof value === 'string' &&
      value.length <= 160 &&
      CHANNEL_SETUP_REQUEST_ID_PATTERN.test(value));
}

function isNullableSafeDisplayString(value: unknown): value is string | null {
  return value === null ||
    (isSafeChannelSetupString(value) &&
      !/[<>]/u.test(value));
}

function isSafeChannelSetupString(value: unknown): value is string {
  return typeof value === 'string' &&
    value.length <= 160 &&
    !hasForbiddenChannelSetupString(value);
}

function isNullableChannelNumber(value: unknown): value is number | null {
  return value === null || isChannelNumber(value);
}

function isFiniteNonNegativeInteger(value: unknown): value is number {
  return (
    typeof value === 'number' &&
    Number.isFinite(value) &&
    Number.isInteger(value) &&
    value >= 0
  );
}

function isChannelNumber(value: unknown): value is number {
  return (
    typeof value === 'number' &&
    Number.isFinite(value) &&
    Number.isInteger(value) &&
    value >= CHANNEL_SETUP_MIN_CHANNEL_NUMBER &&
    value <= CHANNEL_SETUP_MAX_CHANNEL_NUMBER
  );
}

export type PreloadChannelSetupOperation = ChannelSetupOperation;
