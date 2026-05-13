import {
  DIAGNOSTIC_FORBIDDEN_FIELD_KEYS,
  type DiagnosticForbiddenFieldKey,
} from './redaction.js';

export const DIAGNOSTIC_SCHEMA_VERSION = 1 as const;
export const DIAGNOSTIC_REDACTION_VERSION = 'rd17-redaction-v1' as const;
export const SUPPORT_BUNDLE_SCHEMA_VERSION = 1 as const;

export const DIAGNOSTIC_SURFACES = [
  'renderer',
  'preload',
  'main',
  'player-ipc',
  'desktop-player-adapter',
  'native-host-process',
  'plex-playback-runtime',
  'support-bundle',
  'redaction',
] as const;

export type DiagnosticSurface = (typeof DIAGNOSTIC_SURFACES)[number];

export const DIAGNOSTIC_CATEGORIES = [
  'lifecycle',
  'ipc',
  'validation',
  'playback',
  'helper-crash',
  'helper-restart',
  'cleanup',
  'support-bundle-export',
  'redaction-scan',
  'security-boundary',
  'unknown',
] as const;

export type DiagnosticCategory = (typeof DIAGNOSTIC_CATEGORIES)[number];

export const DIAGNOSTIC_SEVERITIES = [
  'debug',
  'info',
  'warning',
  'error',
] as const;

export type DiagnosticSeverity = (typeof DIAGNOSTIC_SEVERITIES)[number];

export const DIAGNOSTIC_STATUSES = [
  'observed',
  'started',
  'succeeded',
  'failed',
  'rejected',
  'ignored',
  'redacted',
  'truncated',
  'cancelled',
] as const;

export type DiagnosticStatus = (typeof DIAGNOSTIC_STATUSES)[number];

export const DIAGNOSTICS_ERROR_CODES = [
  'DIAGNOSTICS_UNAUTHORIZED',
  'DIAGNOSTICS_VALIDATION_FAILED',
  'DIAGNOSTICS_EXPORT_CANCELLED',
  'DIAGNOSTICS_EXPORT_FAILED',
  'DIAGNOSTICS_REDACTION_FAILED',
  'DIAGNOSTICS_UNAVAILABLE',
  'DIAGNOSTICS_UNKNOWN',
] as const;

export type DiagnosticsErrorCode = (typeof DIAGNOSTICS_ERROR_CODES)[number];

export const DIAGNOSTIC_RESULT_VALUES = [
  'success',
  'failure',
  'cancelled',
  'ignored',
] as const;

export type DiagnosticRecordResult = (typeof DIAGNOSTIC_RESULT_VALUES)[number];

export const DIAGNOSTIC_TRUNCATION_LIMITS = {
  rawInputBytes: 64 * 1024,
  messageCharacters: 512,
  operationCharacters: 80,
  requestIdCharacters: 120,
  contextKeyCharacters: 64,
  contextStringCharacters: 256,
  contextEntries: 16,
  nativeOutputSampleCharacters: 1024,
  storeRecords: 500,
  exportRecords: 500,
  diagnosticsNdjsonBytes: 1024 * 1024,
} as const;

export const DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE = '^[A-Za-z0-9._-]{1,120}$' as const;
export const DIAGNOSTICS_REQUEST_ID_PATTERN = new RegExp(
  DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE,
  'u',
);

export const DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE =
  String.raw`(?:[?&][^\s=]*(?:token|auth|secret|credential|password)[^\s=]*=|\b[\w-]*(?:token|auth|secret|credential|password)[\w-]*\s*[:=]|\b(?:authorization|x-plex-token|authHeaders|rawAuthHeaders|bearer|basic|token)\b\s*\S*|(?:[A-Za-z]:\\|\\\\[^\\\s]+\\[^\\\s]+|\/(?:Users|home|var|tmp|private|Volumes|Library)(?:\/|\s+Application\s+Support(?:\/|\b)))|\b(?:pid|processId|process|argv|env|stderr|stdout|crashDump|minidump|rawLog|rawIpc(?:Frame)?|nativeHandle|native_handle|libmpvObject|engineId)[\w-]*\s*[:=]?)`;
export const DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN = new RegExp(
  DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE,
  'iu',
);

export type DiagnosticContextValue = string | number | boolean | null;
export type DiagnosticContext = Readonly<Record<string, DiagnosticContextValue>>;

export interface DiagnosticTruncation {
  messageCharacters?: number;
  operationCharacters?: number;
  requestIdCharacters?: number;
  contextEntries?: number;
  contextKeys?: number;
  contextStringValues?: number;
  nativeOutputCharacters?: number;
}

export interface DiagnosticsError {
  code: DiagnosticsErrorCode;
  message: string;
  recoverable: boolean;
  retryable: boolean;
  diagnostic?: DiagnosticRecord;
}

export interface DiagnosticRecord {
  schemaVersion: typeof DIAGNOSTIC_SCHEMA_VERSION;
  id: string;
  timestampMs: number;
  surface: DiagnosticSurface;
  category: DiagnosticCategory;
  severity: DiagnosticSeverity;
  status: DiagnosticStatus;
  operation: string;
  message: string;
  requestId?: string;
  result?: DiagnosticRecordResult;
  context?: DiagnosticContext;
  truncation?: DiagnosticTruncation;
}

export type DiagnosticsResult<T> =
  | { ok: true; requestId: string; value: T }
  | { ok: false; requestId: string; error: DiagnosticsError }
  | { ok: false; requestId: string; cancelled: true; error: DiagnosticsError };

export interface DiagnosticsSummary {
  schemaVersion: typeof DIAGNOSTIC_SCHEMA_VERSION;
  redactionVersion: typeof DIAGNOSTIC_REDACTION_VERSION;
  recordCount: number;
  lastEventTimestampMs: number | null;
  surfaceCounts: Readonly<Partial<Record<DiagnosticSurface, number>>>;
  severityCounts: Readonly<Partial<Record<DiagnosticSeverity, number>>>;
  lastExportStatus: 'succeeded' | 'failed' | 'cancelled' | null;
  redactionFailureCount: number;
}

export const REDACTION_SCAN_FINDING_LABELS = [
  'token-query-parameter',
  'raw-auth-header',
  'credential-scheme',
  'header-map-credential',
  'secret-field-value',
  'privileged-diagnostic-field-value',
  'oauth-token-path-segment',
  'raw-filesystem-path',
  'raw-process-data',
  'native-handle',
  'raw-ipc-frame',
] as const;

export type RedactionScanFindingLabel = (typeof REDACTION_SCAN_FINDING_LABELS)[number];

export interface RedactionScanReport {
  redactionVersion: typeof DIAGNOSTIC_REDACTION_VERSION;
  scannedFileCount: number;
  scannedByteCount: number;
  findingCount: number;
  findingsByLabel: Readonly<Partial<Record<RedactionScanFindingLabel, number>>>;
  truncatedRecordCount: number;
  omittedFileCount: number;
  status: 'passed' | 'failed';
  timestampMs: number;
}

export interface SupportBundleExportResult {
  status: 'succeeded';
  bundleId: string;
  bundleDirectoryName: string;
  createdAtMs: number;
  fileCount: number;
  byteCount: number;
  includedFiles: readonly string[];
  redactionReport: RedactionScanReport;
}

export interface SupportBundleExportFailure {
  status: 'failed' | 'cancelled';
  error: DiagnosticsError;
  redactionReport?: RedactionScanReport;
}

export const DIAGNOSTICS_RENDERER_EVENT_CATEGORIES = [
  'lifecycle',
  'validation',
  'ipc',
  'support-bundle-export',
] as const satisfies readonly DiagnosticCategory[];

export type DiagnosticsRendererEventCategory =
  (typeof DIAGNOSTICS_RENDERER_EVENT_CATEGORIES)[number];

export const DIAGNOSTICS_RENDERER_EVENT_SEVERITIES = [
  'info',
  'warning',
  'error',
] as const satisfies readonly DiagnosticSeverity[];

export type DiagnosticsRendererEventSeverity =
  (typeof DIAGNOSTICS_RENDERER_EVENT_SEVERITIES)[number];

export interface DiagnosticsRendererEventInput {
  surface: 'renderer';
  category: DiagnosticsRendererEventCategory;
  severity: DiagnosticsRendererEventSeverity;
  operation: string;
  message: string;
  context?: DiagnosticContext;
}

export interface DiagnosticsRendererEventEnvelope {
  requestId: string;
  event: DiagnosticsRendererEventInput;
}

export type DiagnosticsRecordRendererEventResult = DiagnosticsResult<DiagnosticRecord>;
export type DiagnosticsGetSummaryResult = DiagnosticsResult<DiagnosticsSummary>;
export type DiagnosticsExportSupportBundleResult =
  | SupportBundleExportResult
  | SupportBundleExportFailure;

export interface SanitizedDiagnosticContext {
  context?: DiagnosticContext;
  rejectedForbiddenKeys: readonly string[];
  truncation?: Pick<DiagnosticTruncation, 'contextEntries' | 'contextKeys' | 'contextStringValues'>;
}

const FORBIDDEN_DIAGNOSTIC_FIELD_KEY_SET = new Set(
  DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.map((key) => key.toLowerCase()),
);

const REDACTED_DIAGNOSTIC_VALUE = '[redacted]';
const DIAGNOSTIC_SECRET_KEY_PATTERN = [
  ...DIAGNOSTIC_FORBIDDEN_FIELD_KEYS,
  'authToken',
  'authenticationToken',
  'accountToken',
  'activeToken',
  'plexToken',
  'clientSecret',
  'pin',
  'header',
  'password',
  'X-Plex-Token',
]
  .sort((left, right) => right.length - left.length)
  .map(escapeRegExp)
  .join('|');
const DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN = 'bearer|basic|token';
const DIAGNOSTIC_CREDENTIAL_VALUE_PATTERN =
  String.raw`(?:(?=\S*[:0-9._~+/=-])\S+|[A-Za-z]{16,})`;
const DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN = [
  'authorization',
  'header',
  'headers',
  'X-Plex-Token',
  'authHeaders',
  'rawAuthHeaders',
]
  .map(escapeRegExp)
  .join('|');
const DIAGNOSTIC_PATH_KEY_PATTERN = [
  'path',
  'filePath',
  'directory',
  'userData',
  'home',
  'mediaPath',
  'localPath',
]
  .map(escapeRegExp)
  .join('|');
const DIAGNOSTIC_JSON_QUOTED_ESCAPED_KEY_PATTERN = new RegExp(
  String.raw`(\\")\s*(${DIAGNOSTIC_SECRET_KEY_PATTERN})\s*(\\")(\s*:\s*)(\\")([^\\"]*)(\\")`,
  'giu',
);
const DIAGNOSTIC_JSON_QUOTED_KEY_PATTERN = new RegExp(
  String.raw`(")\s*(${DIAGNOSTIC_SECRET_KEY_PATTERN})\s*(")(\s*:\s*)(")([^"\\]*(?:\\.[^"\\]*)*)(")`,
  'giu',
);
const DIAGNOSTIC_AUTH_HEADER_KEY_VALUE_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN})\s*[:=]\s*(?:(?:${DIAGNOSTIC_SECRET_KEY_PATTERN})\s*:\s*)?(?:(?:${DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN})\s+)?\S+`,
  'giu',
);
const DIAGNOSTIC_AUTH_HEADER_OBJECT_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN})\s*[:=]\s*\{[^{}\r\n]*\}`,
  'giu',
);
const DIAGNOSTIC_PATH_KEY_VALUE_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${DIAGNOSTIC_PATH_KEY_PATTERN})\s*[:=]\s*(?:"[^"]*"|'[^']*'|(?:[A-Za-z]:\\|\/)[\s\S]*?)(?=\s+\b(?:${DIAGNOSTIC_SECRET_KEY_PATTERN})\b\s*[:=]|$)`,
  'giu',
);
const DIAGNOSTIC_KEY_VALUE_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${DIAGNOSTIC_SECRET_KEY_PATTERN})\s*[:=]\s*(?:"[^"]*"|'[^']*'|\{[^{}\r\n]*\}|[^\s,}]+)`,
  'giu',
);
const DIAGNOSTIC_TOKEN_QUERY_PARAM_PATTERN = /([?&][^=]*token[^=]*=)[^&\s"')]+/giu;
const DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN_REGEXP = new RegExp(
  String.raw`\b(${DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN})\s+${DIAGNOSTIC_CREDENTIAL_VALUE_PATTERN}`,
  'giu',
);
const DIAGNOSTIC_URL_PATTERN = /https?:\/\/[^\s"')]+/giu;
const DIAGNOSTIC_RAW_FILESYSTEM_PATH_WITH_SPACES_PATTERN =
  /(?:[A-Za-z]:\\(?:Users|ProgramData|Windows|Temp|tmp)\\[^\r\n"')]*?\.[A-Za-z0-9]{1,8}|\/(?:Users|home|var|tmp|private|Volumes)\/[^\r\n"')]*?\.[A-Za-z0-9]{1,8})/gu;
const DIAGNOSTIC_RAW_FILESYSTEM_PATH_PATTERN =
  /(?:[A-Za-z]:\\(?:Users|ProgramData|Windows|Temp|tmp)\\[^\s"')]+|\/(?:Users|home|var|tmp|private|Volumes)\/[^\s"')]+)/gu;
const DIAGNOSTIC_FREEFORM_PROCESS_NATIVE_IPC_PATTERN = new RegExp(
  String.raw`(?<![\w-])\b(?:pid|process|argv|env|stderr|stdout|crashDump|minidump|rawLog|nativeHandle|libmpvObject|engineId)[-:\s]+\d{2,}\b|(?<![\w-])\brawIpc[-:\s]+(?:channel\s+)?[^\s"')]+`,
  'giu',
);
const DIAGNOSTIC_FREEFORM_CREDENTIAL_VALUE_PATTERN =
  /(?<![\w-])\b(?:credential|secret|token)[-_:.\s]?[A-Za-z0-9._~+/=-]*\d[A-Za-z0-9._~+/=-]*\b/giu;
const DIAGNOSTIC_KEYWORD_PATTERN = new RegExp(
  String.raw`(?<![\w-])\b(${DIAGNOSTIC_SECRET_KEY_PATTERN})\b(?!\s*[=:])`,
  'giu',
);
const REDACTED_DIAGNOSTIC_KEY_PREFIX = 'redacted-context-key';

export function isDiagnosticForbiddenFieldKey(key: string): key is DiagnosticForbiddenFieldKey {
  return FORBIDDEN_DIAGNOSTIC_FIELD_KEY_SET.has(key.toLowerCase());
}

export function containsDiagnosticForbiddenField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => containsDiagnosticForbiddenField(item));
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return isDiagnosticForbiddenFieldKey(key) || containsDiagnosticForbiddenField(child);
  });
}

export function truncateDiagnosticString(
  value: string,
  maxCharacters: number,
): { value: string; truncatedCharacters: number } {
  if (value.length <= maxCharacters) {
    return { value, truncatedCharacters: 0 };
  }
  return {
    value: value.slice(0, maxCharacters),
    truncatedCharacters: value.length - maxCharacters,
  };
}

export function redactDiagnosticText(value: string): string {
  return value
    .replace(DIAGNOSTIC_JSON_QUOTED_ESCAPED_KEY_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_JSON_QUOTED_KEY_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_AUTH_HEADER_OBJECT_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_AUTH_HEADER_KEY_VALUE_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_PATH_KEY_VALUE_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_KEY_VALUE_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_TOKEN_QUERY_PARAM_PATTERN, `$1${REDACTED_DIAGNOSTIC_VALUE}`)
    .replace(DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN_REGEXP, `$1 ${REDACTED_DIAGNOSTIC_VALUE}`)
    .replace(DIAGNOSTIC_URL_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_RAW_FILESYSTEM_PATH_WITH_SPACES_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_RAW_FILESYSTEM_PATH_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_FREEFORM_PROCESS_NATIVE_IPC_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_FREEFORM_CREDENTIAL_VALUE_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(DIAGNOSTIC_KEYWORD_PATTERN, REDACTED_DIAGNOSTIC_VALUE);
}

export function sanitizeDiagnosticOperation(value: string): {
  operation: string;
  truncation?: Pick<DiagnosticTruncation, 'operationCharacters'>;
} {
  const normalized = redactDiagnosticText(value).trim() || 'unknown';
  const result = truncateDiagnosticString(
    normalized,
    DIAGNOSTIC_TRUNCATION_LIMITS.operationCharacters,
  );
  return {
    operation: result.value,
    truncation: result.truncatedCharacters > 0
      ? { operationCharacters: result.truncatedCharacters }
      : undefined,
  };
}

export function sanitizeDiagnosticMessage(value: string): {
  message: string;
  truncation?: Pick<DiagnosticTruncation, 'messageCharacters'>;
} {
  const redacted = redactDiagnosticText(value);
  const result = truncateDiagnosticString(
    redacted,
    DIAGNOSTIC_TRUNCATION_LIMITS.messageCharacters,
  );
  return {
    message: result.value,
    truncation: result.truncatedCharacters > 0
      ? { messageCharacters: result.truncatedCharacters }
      : undefined,
  };
}

export function sanitizeDiagnosticRequestId(value: string | undefined): {
  requestId?: string;
  truncation?: Pick<DiagnosticTruncation, 'requestIdCharacters'>;
} {
  if (value === undefined) {
    return {};
  }
  const redacted = redactDiagnosticText(value).trim();
  if (redacted.length === 0) {
    return {};
  }
  const result = truncateDiagnosticString(
    redacted,
    DIAGNOSTIC_TRUNCATION_LIMITS.requestIdCharacters,
  );
  return {
    requestId: result.value,
    truncation: result.truncatedCharacters > 0
      ? { requestIdCharacters: result.truncatedCharacters }
      : undefined,
  };
}

export function sanitizeDiagnosticContext(value: unknown): SanitizedDiagnosticContext {
  if (!isPlainRecord(value)) {
    return { rejectedForbiddenKeys: [] };
  }

  const context: Record<string, DiagnosticContextValue> = {};
  const rejectedForbiddenKeys: string[] = [];
  let skippedEntries = 0;
  let truncatedKeys = 0;
  let truncatedStringValues = 0;

  for (const [rawKey, rawValue] of Object.entries(value)) {
    if (isDiagnosticForbiddenFieldKey(rawKey)) {
      rejectedForbiddenKeys.push(rawKey);
      continue;
    }
    if (Object.keys(context).length >= DIAGNOSTIC_TRUNCATION_LIMITS.contextEntries) {
      skippedEntries += 1;
      continue;
    }
    if (!isDiagnosticContextValue(rawValue)) {
      continue;
    }

    const redactedKey = redactDiagnosticText(rawKey).trim();
    if (redactedKey.length === 0) {
      rejectedForbiddenKeys.push(rawKey);
      continue;
    }
    const keyResult = truncateDiagnosticString(
      redactedKey,
      DIAGNOSTIC_TRUNCATION_LIMITS.contextKeyCharacters,
    );
    const redactedValue = typeof rawValue === 'string' ? redactDiagnosticText(rawValue) : rawValue;
    const valueResult = typeof redactedValue === 'string'
      ? truncateDiagnosticString(redactedValue, DIAGNOSTIC_TRUNCATION_LIMITS.contextStringCharacters)
      : { value: rawValue, truncatedCharacters: 0 };

    if (keyResult.truncatedCharacters > 0) {
      truncatedKeys += keyResult.truncatedCharacters;
    }
    if (valueResult.truncatedCharacters > 0) {
      truncatedStringValues += valueResult.truncatedCharacters;
    }
    context[normalizeSanitizedContextKey(keyResult.value, context)] = valueResult.value;
  }

  const truncation: SanitizedDiagnosticContext['truncation'] = {
    ...(skippedEntries > 0 ? { contextEntries: skippedEntries } : {}),
    ...(truncatedKeys > 0 ? { contextKeys: truncatedKeys } : {}),
    ...(truncatedStringValues > 0 ? { contextStringValues: truncatedStringValues } : {}),
  };

  return {
    context: Object.keys(context).length > 0 ? context : undefined,
    rejectedForbiddenKeys,
    truncation: Object.keys(truncation).length > 0 ? truncation : undefined,
  };
}

function isDiagnosticContextValue(value: unknown): value is DiagnosticContextValue {
  return (
    value === null ||
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  ) && (typeof value !== 'number' || Number.isFinite(value));
}

export function isSafeRendererDiagnosticContextValue(value: DiagnosticContextValue): boolean {
  if (typeof value !== 'string') {
    return true;
  }
  return !DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN.test(value);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

function normalizeSanitizedContextKey(
  key: string,
  context: Record<string, DiagnosticContextValue>,
): string {
  const safeKey = key.includes(REDACTED_DIAGNOSTIC_VALUE)
    ? REDACTED_DIAGNOSTIC_KEY_PREFIX
    : key;
  if (!Object.hasOwn(context, safeKey)) {
    return safeKey;
  }

  let index = 2;
  while (Object.hasOwn(context, `${safeKey}-${index}`)) {
    index += 1;
  }
  return `${safeKey}-${index}`;
}
