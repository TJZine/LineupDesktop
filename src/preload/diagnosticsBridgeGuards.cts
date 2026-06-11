import type {
  DiagnosticsExportSupportBundleResult,
  DiagnosticsGetSummaryResult,
  DiagnosticsRecordRendererEventResult,
  DiagnosticsRendererEventEnvelope,
  DiagnosticRecord,
} from '../contracts/diagnostics.js';

export const DIAGNOSTICS_REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
export const DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN =
  /(?:[?&][^\s=]*(?:token|auth|secret|credential|password)[^\s=]*=|\b[\w-]*(?:token|auth|secret|credential|password)[\w-]*\s*[:=]|\b(?:authorization|x-plex-token|authHeaders|rawAuthHeaders|bearer|basic|token)\b\s*\S*|(?:[A-Za-z]:\\|\\\\[^\\\s]+\\[^\\\s]+|\/(?:Users|home|var|tmp|private|Volumes|Library)(?:\/|\s+Application\s+Support(?:\/|\b)))|\b(?:pid|processId|process|argv|env|stderr|stdout|crashDump|minidump|rawLog|rawIpc(?:Frame)?|nativeHandle|native_handle|libmpvObject|engineId)[\w-]*\s*[:=]?)/iu;

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
export const DIAGNOSTIC_SEVERITIES = [
  'debug',
  'info',
  'warning',
  'error',
] as const;
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
export const DIAGNOSTICS_RENDERER_EVENT_CATEGORIES = [
  'lifecycle',
  'validation',
  'ipc',
  'support-bundle-export',
] as const;
export const DIAGNOSTICS_RENDERER_EVENT_SEVERITIES = [
  'info',
  'warning',
  'error',
] as const;
export const DIAGNOSTICS_ERROR_CODES = [
  'DIAGNOSTICS_UNAUTHORIZED',
  'DIAGNOSTICS_VALIDATION_FAILED',
  'DIAGNOSTICS_EXPORT_CANCELLED',
  'DIAGNOSTICS_EXPORT_FAILED',
  'DIAGNOSTICS_REDACTION_FAILED',
  'DIAGNOSTICS_UNAVAILABLE',
  'DIAGNOSTICS_UNKNOWN',
] as const;
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

export const DIAGNOSTIC_FORBIDDEN_FIELD_KEYS = [
  'rawMediaUrl',
  'tokenizedUrl',
  'authHeaders',
  'rawAuthHeaders',
  'persistentToken',
  'credentialMaterial',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
  'path',
  'filePath',
  'directory',
  'userData',
  'home',
  'username',
  'env',
  'argv',
  'pid',
  'process',
  'stderr',
  'stdout',
  'crashDump',
  'minidump',
  'stack',
  'rawLog',
  'rawIpc',
  'mediaPath',
  'localPath',
  'serverUri',
  'connectionUri',
  'privatePlaybackDescriptor',
  'headers',
  'authorization',
  'token',
  'credential',
  'secret',
] as const;
const DIAGNOSTIC_FORBIDDEN_FIELD_KEY_SET = new Set(
  DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.map((key) => key.toLowerCase()),
);

export function diagnosticsValidationFailure(
  requestId: string,
  message: string,
): DiagnosticsRecordRendererEventResult | DiagnosticsGetSummaryResult {
  return {
    ok: false,
    requestId,
    error: {
      code: 'DIAGNOSTICS_VALIDATION_FAILED',
      message,
      recoverable: false,
      retryable: false,
    },
  };
}

export function diagnosticsExportValidationFailure(message: string): DiagnosticsExportSupportBundleResult {
  return {
    status: 'failed',
    error: {
      code: 'DIAGNOSTICS_VALIDATION_FAILED',
      message,
      recoverable: false,
      retryable: false,
    },
  };
}


export function readDiagnosticsRequestId(value: unknown): string {
  if (
    isPlainRecord(value) &&
    isNonEmptyString(value.requestId) &&
    DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId)
  ) {
    return value.requestId;
  }
  return createRequestId('diagnostics-validation');
}

function createRequestId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function isFiniteNonNegativeNumberMap(value: unknown, allowedKeys: readonly string[]): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, [], allowedKeys) &&
    Object.values(value).every(isFiniteNonNegativeNumber)
  );
}


function hasForbiddenDiagnosticField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenDiagnosticField(item));
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return (
      DIAGNOSTIC_FORBIDDEN_FIELD_KEY_SET.has(key.toLowerCase()) ||
      hasForbiddenDiagnosticField(child)
    );
  });
}

export function isDiagnosticsRendererEventEnvelope(value: unknown): value is DiagnosticsRendererEventEnvelope {
  if (
    !isPlainRecord(value) ||
    !isNonEmptyString(value.requestId) ||
    !DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId) ||
    hasForbiddenDiagnosticField(value)
  ) {
    return false;
  }
  if (!hasOnlyKeys(value, ['requestId', 'event'])) {
    return false;
  }
  const event = value.event;
  return (
    isPlainRecord(event) &&
    hasOnlyKeys(event, ['surface', 'category', 'severity', 'operation', 'message'], ['context']) &&
    event.surface === 'renderer' &&
    isStringInSet(event.category, DIAGNOSTICS_RENDERER_EVENT_CATEGORIES) &&
    isStringInSet(event.severity, DIAGNOSTICS_RENDERER_EVENT_SEVERITIES) &&
    isNonEmptyString(event.operation) &&
    isNonEmptyString(event.message) &&
    (event.context === undefined || isDiagnosticContext(event.context))
  );
}

function isDiagnosticContext(value: unknown): boolean {
  if (!isPlainRecord(value) || hasForbiddenDiagnosticField(value)) {
    return false;
  }
  return Object.values(value).every((item) => (
    item === null ||
    (typeof item === 'string' && !DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN.test(item)) ||
    typeof item === 'boolean' ||
    (typeof item === 'number' && Number.isFinite(item))
  ));
}

export function isDiagnosticsRecordRendererEventResult(value: unknown): value is DiagnosticsRecordRendererEventResult {
  return isDiagnosticsResult(value, isDiagnosticRecord);
}

export function isDiagnosticsGetSummaryResult(value: unknown): value is DiagnosticsGetSummaryResult {
  return isDiagnosticsResult(value, isDiagnosticsSummary);
}

function isDiagnosticsResult<T>(
  value: unknown,
  isValue: (candidate: unknown) => candidate is T,
): boolean {
  if (
    !isPlainRecord(value) ||
    typeof value.ok !== 'boolean' ||
    !isNonEmptyString(value.requestId) ||
    !DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId)
  ) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'requestId', 'value']) && isValue(value.value);
  }
  const hasValidCancellationFlag = value.cancelled === undefined || value.cancelled === true;
  return hasOnlyKeys(value, ['ok', 'requestId', 'error'], ['cancelled']) &&
    hasValidCancellationFlag && isDiagnosticsError(value.error);
}

function isDiagnosticRecord(value: unknown): value is DiagnosticRecord {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['schemaVersion', 'id', 'timestampMs', 'surface', 'category', 'severity', 'status', 'operation', 'message'],
      ['requestId', 'result', 'context', 'truncation'],
    ) &&
    value.schemaVersion === 1 &&
    isNonEmptyString(value.id) &&
    isFiniteNonNegativeNumber(value.timestampMs) &&
    isStringInSet(value.surface, DIAGNOSTIC_SURFACES) &&
    isStringInSet(value.category, DIAGNOSTIC_CATEGORIES) &&
    isStringInSet(value.severity, DIAGNOSTIC_SEVERITIES) &&
    isStringInSet(value.status, DIAGNOSTIC_STATUSES) &&
    isNonEmptyString(value.operation) &&
    typeof value.message === 'string' &&
    (value.requestId === undefined || isNonEmptyString(value.requestId)) &&
    (value.context === undefined || isDiagnosticContext(value.context)) &&
    !hasForbiddenDiagnosticField(value)
  );
}

function isDiagnosticsSummary(value: unknown): value is DiagnosticsGetSummaryResult extends { ok: true; value: infer T } ? T : never {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      [
        'schemaVersion',
        'redactionVersion',
        'recordCount',
        'lastEventTimestampMs',
        'surfaceCounts',
        'severityCounts',
        'lastExportStatus',
        'redactionFailureCount',
      ],
    ) &&
    value.schemaVersion === 1 &&
    value.redactionVersion === 'rd17-redaction-v1' &&
    isFiniteNonNegativeNumber(value.recordCount) &&
    (value.lastEventTimestampMs === null || isFiniteNonNegativeNumber(value.lastEventTimestampMs)) &&
    isFiniteNonNegativeNumberMap(value.surfaceCounts, DIAGNOSTIC_SURFACES) &&
    isFiniteNonNegativeNumberMap(value.severityCounts, DIAGNOSTIC_SEVERITIES) &&
    (
      value.lastExportStatus === null ||
      value.lastExportStatus === 'succeeded' ||
      value.lastExportStatus === 'failed' ||
      value.lastExportStatus === 'cancelled'
    ) &&
    isFiniteNonNegativeNumber(value.redactionFailureCount) &&
    !hasForbiddenDiagnosticField(value)
  );
}

export function isDiagnosticsExportSupportBundleResult(
  value: unknown,
): value is DiagnosticsExportSupportBundleResult {
  if (!isPlainRecord(value) || hasForbiddenDiagnosticField(value)) {
    return false;
  }
  if (value.status === 'succeeded') {
    return (
      hasOnlyKeys(
        value,
        [
          'status',
          'bundleId',
          'bundleDirectoryName',
          'createdAtMs',
          'fileCount',
          'byteCount',
          'includedFiles',
          'redactionReport',
        ],
      ) &&
      isSafeBundleId(value.bundleId) &&
      isSafeBundleDirectoryName(value.bundleDirectoryName) &&
      isFiniteNonNegativeNumber(value.createdAtMs) &&
      isFiniteNonNegativeNumber(value.fileCount) &&
      isFiniteNonNegativeNumber(value.byteCount) &&
      Array.isArray(value.includedFiles) &&
      value.includedFiles.every(isSafeBundleFileName) &&
      isRedactionScanReport(value.redactionReport)
    );
  }
  return (
    (value.status === 'failed' || value.status === 'cancelled') &&
    hasOnlyKeys(value, ['status', 'error'], ['redactionReport']) &&
    isDiagnosticsError(value.error) &&
    (value.redactionReport === undefined || isRedactionScanReport(value.redactionReport))
  );
}

function isDiagnosticsError(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'recoverable', 'retryable'], ['diagnostic']) &&
    isStringInSet(value.code, DIAGNOSTICS_ERROR_CODES) &&
    typeof value.message === 'string' &&
    typeof value.recoverable === 'boolean' &&
    typeof value.retryable === 'boolean' &&
    (value.diagnostic === undefined || isDiagnosticRecord(value.diagnostic)) &&
    !hasForbiddenDiagnosticField(value)
  );
}

function isRedactionScanReport(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      [
        'redactionVersion',
        'scannedFileCount',
        'scannedByteCount',
        'findingCount',
        'findingsByLabel',
        'truncatedRecordCount',
        'omittedFileCount',
        'status',
        'timestampMs',
      ],
    ) &&
    value.redactionVersion === 'rd17-redaction-v1' &&
    isFiniteNonNegativeNumber(value.scannedFileCount) &&
    isFiniteNonNegativeNumber(value.scannedByteCount) &&
    isFiniteNonNegativeNumber(value.findingCount) &&
    isFiniteNonNegativeNumberMap(value.findingsByLabel, REDACTION_SCAN_FINDING_LABELS) &&
    isFiniteNonNegativeNumber(value.truncatedRecordCount) &&
    isFiniteNonNegativeNumber(value.omittedFileCount) &&
    (value.status === 'passed' || value.status === 'failed') &&
    isFiniteNonNegativeNumber(value.timestampMs)
  );
}

function isSafeBundleId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9-]{1,80}$/u.test(value);
}

function isSafeBundleDirectoryName(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    /^lineup-desktop-support-[A-Za-z0-9-]{1,80}$/u.test(value) &&
    !/[\\/]/u.test(value) &&
    !/^[A-Za-z]:/u.test(value)
  );
}

function isSafeBundleFileName(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9.-]*$/u.test(value) && !/[\\/]/u.test(value);
}


function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isStringInSet<TValue extends string>(
  value: unknown,
  allowed: readonly TValue[],
): value is TValue {
  return typeof value === 'string' && allowed.includes(value as TValue);
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return requiredKeys.every((key) => Object.hasOwn(value, key));
}
