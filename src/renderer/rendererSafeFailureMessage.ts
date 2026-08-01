const SENSITIVE_FAILURE_PATTERNS: readonly RegExp[] = [
  /(?:[a-z][a-z0-9+.-]*:\/\/|token|credential|secret|header|\\\\|(?:^|[^\p{L}\p{N}._~+/-])(?:~\/|\/(?!\/)\S+)|[A-Za-z]:[\\/])/iu,
  /\b(?:authorization|x-api-key|password)\s*[:=]\s*\S+/iu,
  /\bbearer\s+\S+/iu,
  /(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?![A-Za-z0-9_-])/u,
  /(?:^|[^\p{L}\p{N}._~+-])\.{1,2}[\\/]\S+/u,
];

function containsSensitiveFailureText(value: string): boolean {
  return SENSITIVE_FAILURE_PATTERNS.some((pattern) => pattern.test(value));
}

export function toRendererSafeFailureMessage(message: string, fallback: string): string {
  const compact = message
    .replace(/\p{Cc}/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
  if (compact.length === 0 || containsSensitiveFailureText(compact)) {
    return fallback;
  }
  return compact.slice(0, 180);
}
