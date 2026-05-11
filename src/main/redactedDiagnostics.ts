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
const REDACTED_DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN = [
  'authorization',
  'header',
  'headers',
  'X-Plex-Token',
  'authHeaders',
  'rawAuthHeaders',
].map(escapeRegExp).join('|');

const JSON_QUOTED_ESCAPED_KEY_PATTERN = new RegExp(
  String.raw`(\\")\s*(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*(\\")(\s*:\s*)(\\")([^\\"]*)(\\")`,
  'giu',
);
const JSON_QUOTED_KEY_PATTERN = new RegExp(
  String.raw`(")\s*(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*(")(\s*:\s*)(")([^"\\]*(?:\\.[^"\\]*)*)(")`,
  'giu',
);
const AUTH_HEADER_KEY_VALUE_PAIR_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${REDACTED_DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN})\s*[:=]\s*(?:(?:${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*:\s*)?(?:(?:bearer|token)\s+)?[-A-Za-z0-9._~+/=]+`,
  'giu',
);
const KEY_VALUE_PAIR_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,}]+)`,
  'giu',
);
const TOKEN_QUERY_PARAM_PATTERN = /([?&][^=]*token[^=]*=)[^&\s"')]+/giu;
const BEARER_TOKEN_PREFIX_PATTERN = /\b(bearer)\s+[-A-Za-z0-9._~+/=]+/giu;
const URL_PATTERN = /https?:\/\/[^\s"')]+/giu;
const COMBINED_KEYWORD_PATTERN = new RegExp(
  String.raw`(?<![\w-])\b(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\b(?!\s*[=:])`,
  'giu',
);

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
    .replace(JSON_QUOTED_ESCAPED_KEY_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(JSON_QUOTED_KEY_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(AUTH_HEADER_KEY_VALUE_PAIR_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(BEARER_TOKEN_PREFIX_PATTERN, `$1 ${REDACTED_DIAGNOSTIC_VALUE}`)
    .replace(TOKEN_QUERY_PARAM_PATTERN, `$1${REDACTED_DIAGNOSTIC_VALUE}`)
    .replace(KEY_VALUE_PAIR_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(URL_PATTERN, REDACTED_DIAGNOSTIC_VALUE);

  return redactedStructuredValues.replace(COMBINED_KEYWORD_PATTERN, REDACTED_DIAGNOSTIC_VALUE);
}

export function reportMainProcessDiagnostic(message: string, error: unknown): void {
  console.error(`${message}: ${redactMainProcessError(error)}`);
}
