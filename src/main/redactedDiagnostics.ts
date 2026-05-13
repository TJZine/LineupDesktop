/**
 * Best-effort diagnostic redaction patterns cover token-shaped keys, auth
 * headers, URLs, native handles, and secret-shaped fields before main-process
 * errors are logged.
 */
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

const REDACTED_DIAGNOSTIC_KEY_PATTERN = [...REDACTED_DIAGNOSTIC_KEYS]
  .sort((left, right) => right.length - left.length)
  .map(escapeRegExp)
  .join('|');

const REDACTED_DIAGNOSTIC_VALUE = '[redacted]';
const REDACTED_DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN = 'bearer|basic|token';
const REDACTED_DIAGNOSTIC_CREDENTIAL_VALUE_PATTERN =
  String.raw`(?:(?=\S*[:0-9._~+/=-])\S+|[A-Za-z]{16,})`;
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
  String.raw`(?<![?&\w-])\b(${REDACTED_DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN})\s*[:=]\s*(?:(?:${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*:\s*)?(?:(?:${REDACTED_DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN})\s+)?\S+`,
  'giu',
);
const AUTH_HEADER_OBJECT_LITERAL_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${REDACTED_DIAGNOSTIC_AUTH_HEADER_KEY_PATTERN})\s*[:=]\s*\{[^{}\r\n]*\}`,
  'giu',
);
const KEY_VALUE_PAIR_PATTERN = new RegExp(
  String.raw`(?<![?&\w-])\b(${REDACTED_DIAGNOSTIC_KEY_PATTERN})\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,}]+)`,
  'giu',
);
const TOKEN_QUERY_PARAM_PATTERN = /([?&][^=]*token[^=]*=)[^&\s"')]+/giu;
const CREDENTIAL_SCHEME_PREFIX_PATTERN = new RegExp(
  String.raw`\b(${REDACTED_DIAGNOSTIC_CREDENTIAL_SCHEME_PATTERN})\s+${REDACTED_DIAGNOSTIC_CREDENTIAL_VALUE_PATTERN}`,
  'giu',
);
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
    .replace(AUTH_HEADER_OBJECT_LITERAL_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(AUTH_HEADER_KEY_VALUE_PAIR_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(TOKEN_QUERY_PARAM_PATTERN, `$1${REDACTED_DIAGNOSTIC_VALUE}`)
    .replace(KEY_VALUE_PAIR_PATTERN, REDACTED_DIAGNOSTIC_VALUE)
    .replace(CREDENTIAL_SCHEME_PREFIX_PATTERN, `$1 ${REDACTED_DIAGNOSTIC_VALUE}`)
    .replace(URL_PATTERN, REDACTED_DIAGNOSTIC_VALUE);

  return redactedStructuredValues.replace(COMBINED_KEYWORD_PATTERN, REDACTED_DIAGNOSTIC_VALUE);
}

export function reportMainProcessDiagnostic(message: string, error: unknown): void {
  console.error(`${message}: ${redactMainProcessError(error)}`);
}
