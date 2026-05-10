const REDACTED_DIAGNOSTIC_KEYS = [
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

const REDACTED_DIAGNOSTIC_PATTERNS = [
  new RegExp(
    String.raw`(?:"(?:${REDACTED_DIAGNOSTIC_KEY_PATTERN})"|'(?:${REDACTED_DIAGNOSTIC_KEY_PATTERN})'|(?:${REDACTED_DIAGNOSTIC_KEY_PATTERN}))\s*(?:=|:)\s*(?:"[^"]*"|'[^']*'|[^\s,}]+)`,
    'giu',
  ),
  ...REDACTED_DIAGNOSTIC_KEYS.map(
    (key) => new RegExp(String.raw`\b${escapeRegExp(key)}\b`, 'giu'),
  ),
  /https?:\/\/[^\s"')]+/giu,
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

  return REDACTED_DIAGNOSTIC_PATTERNS.reduce(
    (current, pattern) => current.replace(pattern, '[redacted]'),
    message,
  );
}

export function reportMainProcessDiagnostic(message: string, error: unknown): void {
  console.error(`${message}: ${redactMainProcessError(error)}`);
}
