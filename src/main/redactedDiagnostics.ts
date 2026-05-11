const REDACTED_DIAGNOSTIC_KEYS = [
  'token',
  'authToken',
  'authenticationToken',
  'accountToken',
  'activeToken',
  'plexToken',
  'clientSecret',
  'pin',
  'header',
  'headers',
  'authorization',
  'secret',
  'credential',
  'password',
  'X-Plex-Token',
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
] as const;

const REDACTED_DIAGNOSTIC_KEY_PATTERN = REDACTED_DIAGNOSTIC_KEYS
  .map(escapeRegExp)
  .join('|');

const REDACTED_DIAGNOSTIC_VALUE = '[redacted]';

const REDACTED_DIAGNOSTIC_PATTERNS = [
  new RegExp(
    String.raw`(\\")\s*(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*(\\")(\s*:\s*)(\\")([^\\"]*)(\\")`,
    'giu',
  ),
  new RegExp(
    String.raw`(")\s*(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*(")(\s*:\s*)(")([^"\\]*(?:\\.[^"\\]*)*)(")`,
    'giu',
  ),
  new RegExp(
    String.raw`\b(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,}]+)`,
    'giu',
  ),
  /([?&][^=]*token[^=]*=)[^&\s"')]+/giu,
  /\b(bearer)\s+[-A-Za-z0-9._~+/=]+/giu,
  /https?:\/\/[^\s"')]+/giu,
  ...REDACTED_DIAGNOSTIC_KEYS.map(
    (key) => new RegExp(String.raw`\b${escapeRegExp(key)}\b`, 'giu'),
  ),
] as const;

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

export function redactMainProcessError(
  error: unknown,
  fallback = 'Main process operation failed.',
): string {
  const message = error instanceof Error && error.message.trim().length > 0
    ? error.message
    : fallback;

  const redactedStructuredValues = message
    .replace(REDACTED_DIAGNOSTIC_PATTERNS[0], REDACTED_DIAGNOSTIC_VALUE)
    .replace(REDACTED_DIAGNOSTIC_PATTERNS[1], REDACTED_DIAGNOSTIC_VALUE)
    .replace(REDACTED_DIAGNOSTIC_PATTERNS[4], '$1 [redacted]')
    .replace(REDACTED_DIAGNOSTIC_PATTERNS[3], '$1[redacted]')
    .replace(REDACTED_DIAGNOSTIC_PATTERNS[2], REDACTED_DIAGNOSTIC_VALUE)
    .replace(REDACTED_DIAGNOSTIC_PATTERNS[5], REDACTED_DIAGNOSTIC_VALUE);

  return REDACTED_DIAGNOSTIC_PATTERNS.slice(6).reduce(
    (current, pattern) => current.replace(pattern, REDACTED_DIAGNOSTIC_VALUE),
    redactedStructuredValues,
  );
}

export function reportMainProcessDiagnostic(message: string, error: unknown): void {
  console.error(`${message}: ${redactMainProcessError(error)}`);
}
