const SENSITIVE_FAILURE_TEXT = /(?:[a-z][a-z0-9+.-]*:\/\/|token|credential|secret|header|\\\\|(?:^|[^\p{L}\p{N}._~+/-])(?:~\/|\/(?!\/)\S+)|[A-Za-z]:[\\/])/iu;

export function toRendererSafeFailureMessage(message: string, fallback: string): string {
  const compact = message
    .replace(/\p{Cc}/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
  if (compact.length === 0 || SENSITIVE_FAILURE_TEXT.test(compact)) {
    return fallback;
  }
  return compact.slice(0, 180);
}
