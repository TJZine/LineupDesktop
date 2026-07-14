export const SETTINGS_INVALID_REQUEST_ID = 'settings-invalid-request';
export const SETTINGS_REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/u;
export const SETTINGS_ERROR_CODES = [
  'unauthorized',
  'validation-failed',
  'revision-conflict',
  'storage-unavailable',
  'unsupported-version',
  'operation-failed',
] as const;
export const SETTINGS_ERROR_MESSAGES = {
  unauthorized: 'Desktop settings request was not authorized.',
  'validation-failed': 'Desktop settings request or response was invalid.',
  'revision-conflict': 'Desktop settings changed; refresh and try again.',
  'storage-unavailable': 'Desktop settings storage is unavailable.',
  'unsupported-version': 'Desktop settings require a newer compatible version.',
  'operation-failed': 'Desktop settings operation failed.',
} as const;

export type PreloadSettingsErrorCode = (typeof SETTINGS_ERROR_CODES)[number];

export function readSettingsRequestId(value: unknown): string {
  return isPlainRecord(value) && isSettingsRequestId(value.requestId)
    ? value.requestId
    : SETTINGS_INVALID_REQUEST_ID;
}

export function isSettingsGetSnapshotRequest(value: unknown): value is { requestId: string } {
  return isPlainRecord(value) && hasOnlyKeys(value, ['requestId']) &&
    isSettingsRequestId(value.requestId);
}

export function isSettingsReplaceRequest(value: unknown): value is {
  requestId: string;
  expectedRevision: number;
  values: {
    launchMode: 'windowed' | 'fullscreen';
    guideDensity: 'comfortable' | 'compact';
    previewBadgesEnabled: boolean;
    setupReminderEnabled: boolean;
  };
} {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['requestId', 'expectedRevision', 'values']) &&
    isSettingsRequestId(value.requestId) &&
    isSafeRevision(value.expectedRevision) &&
    isSettingsValues(value.values);
}

export function isSettingsResult(value: unknown, expectedRequestId: string): boolean {
  if (!isPlainRecord(value) || typeof value.ok !== 'boolean' ||
    value.requestId !== expectedRequestId || !isSettingsRequestId(value.requestId)) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'value', 'requestId']) && isSettingsSnapshot(value.value);
  }
  if (!hasOnlyKeys(value, ['ok', 'error', 'requestId']) || !isPlainRecord(value.error) ||
    !hasOnlyKeys(value.error, ['code', 'message'])) {
    return false;
  }
  const code = value.error.code as PreloadSettingsErrorCode;
  return SETTINGS_ERROR_CODES.includes(code) && value.error.message === SETTINGS_ERROR_MESSAGES[code];
}

export function settingsBridgeFailure(
  requestId: string,
  code: PreloadSettingsErrorCode,
): { ok: false; error: { code: PreloadSettingsErrorCode; message: string }; requestId: string } {
  return { ok: false, error: { code, message: SETTINGS_ERROR_MESSAGES[code] }, requestId };
}

function isSettingsSnapshot(value: unknown): boolean {
  return isPlainRecord(value) && hasOnlyKeys(value, ['schemaVersion', 'revision', 'status', 'values']) &&
    value.schemaVersion === 1 && isSafeRevision(value.revision) &&
    ['ready', 'missing', 'corrupt', 'unsupported-version'].includes(String(value.status)) &&
    isSettingsValues(value.values);
}

function isSettingsValues(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['launchMode', 'guideDensity', 'previewBadgesEnabled', 'setupReminderEnabled']) &&
    (value.launchMode === 'windowed' || value.launchMode === 'fullscreen') &&
    (value.guideDensity === 'comfortable' || value.guideDensity === 'compact') &&
    typeof value.previewBadgesEnabled === 'boolean' && typeof value.setupReminderEnabled === 'boolean';
}

function isSettingsRequestId(value: unknown): value is string {
  return typeof value === 'string' && SETTINGS_REQUEST_ID_PATTERN.test(value);
}

function isSafeRevision(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasOnlyKeys(value: Record<string, unknown>, requiredKeys: readonly string[]): boolean {
  return Object.keys(value).length === requiredKeys.length &&
    requiredKeys.every((key) => Object.hasOwn(value, key));
}
