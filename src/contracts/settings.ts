export const SETTINGS_SCHEMA_VERSION = 1 as const;

export const DESKTOP_SETTINGS_LOAD_STATUSES = [
  'ready',
  'missing',
  'corrupt',
  'unsupported-version',
] as const;

export const DESKTOP_SETTINGS_ERROR_CODES = [
  'unauthorized',
  'validation-failed',
  'revision-conflict',
  'storage-unavailable',
  'unsupported-version',
  'operation-failed',
] as const;

export const DESKTOP_SETTINGS_ERROR_MESSAGES = {
  unauthorized: 'Desktop settings request was not authorized.',
  'validation-failed': 'Desktop settings request or response was invalid.',
  'revision-conflict': 'Desktop settings changed; refresh and try again.',
  'storage-unavailable': 'Desktop settings storage is unavailable.',
  'unsupported-version': 'Desktop settings require a newer compatible version.',
  'operation-failed': 'Desktop settings operation failed.',
} as const satisfies Record<DesktopSettingsErrorCode, string>;

export const SETTINGS_REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/u;
export const SETTINGS_INVALID_REQUEST_ID = 'settings-invalid-request' as const;

export interface DesktopSettingsValues {
  launchMode: 'windowed' | 'fullscreen';
  guideDensity: 'comfortable' | 'compact';
  previewBadgesEnabled: boolean;
  setupReminderEnabled: boolean;
}

export type DesktopSettingsLoadStatus = (typeof DESKTOP_SETTINGS_LOAD_STATUSES)[number];
export type DesktopSettingsErrorCode = (typeof DESKTOP_SETTINGS_ERROR_CODES)[number];

export interface DesktopSettingsSnapshot {
  schemaVersion: typeof SETTINGS_SCHEMA_VERSION;
  revision: number;
  status: DesktopSettingsLoadStatus;
  values: DesktopSettingsValues;
}

export interface DesktopSettingsGetSnapshotRequest {
  requestId: string;
}

export interface DesktopSettingsReplaceRequest {
  requestId: string;
  expectedRevision: number;
  values: DesktopSettingsValues;
}

export type DesktopSettingsIpcResult<T> =
  | { ok: true; value: T; requestId: string }
  | {
      ok: false;
      error: { code: DesktopSettingsErrorCode; message: string };
      requestId: string;
    };

export const DEFAULT_DESKTOP_SETTINGS_VALUES: Readonly<DesktopSettingsValues> = Object.freeze({
  launchMode: 'windowed',
  guideDensity: 'comfortable',
  previewBadgesEnabled: true,
  setupReminderEnabled: true,
});

export function createDefaultDesktopSettingsValues(): DesktopSettingsValues {
  return { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
}

export function isDesktopSettingsRequestId(value: unknown): value is string {
  return typeof value === 'string' && SETTINGS_REQUEST_ID_PATTERN.test(value);
}

export function readDesktopSettingsRequestId(value: unknown): string {
  if (isPlainRecord(value) && isDesktopSettingsRequestId(value.requestId)) {
    return value.requestId;
  }
  return SETTINGS_INVALID_REQUEST_ID;
}

export function isDesktopSettingsValues(value: unknown): value is DesktopSettingsValues {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['launchMode', 'guideDensity', 'previewBadgesEnabled', 'setupReminderEnabled']) &&
    (value.launchMode === 'windowed' || value.launchMode === 'fullscreen') &&
    (value.guideDensity === 'comfortable' || value.guideDensity === 'compact') &&
    typeof value.previewBadgesEnabled === 'boolean' &&
    typeof value.setupReminderEnabled === 'boolean';
}

export function isDesktopSettingsGetSnapshotRequest(
  value: unknown,
): value is DesktopSettingsGetSnapshotRequest {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['requestId']) &&
    isDesktopSettingsRequestId(value.requestId);
}

export function isDesktopSettingsReplaceRequest(
  value: unknown,
): value is DesktopSettingsReplaceRequest {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['requestId', 'expectedRevision', 'values']) &&
    isDesktopSettingsRequestId(value.requestId) &&
    isSafeRevision(value.expectedRevision) &&
    isDesktopSettingsValues(value.values);
}

export function isDesktopSettingsSnapshot(value: unknown): value is DesktopSettingsSnapshot {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['schemaVersion', 'revision', 'status', 'values']) &&
    value.schemaVersion === SETTINGS_SCHEMA_VERSION &&
    isSafeRevision(value.revision) &&
    DESKTOP_SETTINGS_LOAD_STATUSES.includes(value.status as DesktopSettingsLoadStatus) &&
    isDesktopSettingsValues(value.values);
}

export function isDesktopSettingsIpcResult<T>(
  value: unknown,
  isValue: (candidate: unknown) => candidate is T,
): value is DesktopSettingsIpcResult<T> {
  if (!isPlainRecord(value) || typeof value.ok !== 'boolean' || !isDesktopSettingsRequestId(value.requestId)) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'value', 'requestId']) && isValue(value.value);
  }
  if (!hasOnlyKeys(value, ['ok', 'error', 'requestId']) || !isPlainRecord(value.error)) {
    return false;
  }
  if (!hasOnlyKeys(value.error, ['code', 'message'])) {
    return false;
  }
  const code = value.error.code as DesktopSettingsErrorCode;
  return DESKTOP_SETTINGS_ERROR_CODES.includes(code) &&
    value.error.message === DESKTOP_SETTINGS_ERROR_MESSAGES[code];
}

export function desktopSettingsSuccess<T>(
  requestId: string,
  value: T,
): DesktopSettingsIpcResult<T> {
  return { ok: true, value, requestId };
}

export function desktopSettingsFailure<T>(
  requestId: string,
  code: DesktopSettingsErrorCode,
): DesktopSettingsIpcResult<T> {
  return {
    ok: false,
    error: { code, message: DESKTOP_SETTINGS_ERROR_MESSAGES[code] },
    requestId,
  };
}

export function isSafeRevision(value: unknown): value is number {
  return Number.isSafeInteger(value) && typeof value === 'number' && value >= 0;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasOnlyKeys(value: Record<string, unknown>, requiredKeys: readonly string[]): boolean {
  return Object.keys(value).length === requiredKeys.length &&
    requiredKeys.every((key) => Object.hasOwn(value, key));
}
