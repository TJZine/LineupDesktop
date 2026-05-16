export type LivePlexTransportErrorCode =
  | 'auth-required'
  | 'auth-invalid'
  | 'resource-not-found'
  | 'rate-limited'
  | 'server-unreachable'
  | 'parse-error'
  | 'aborted'
  | 'timeout'
  | 'server-error';

export class LivePlexTransportError extends Error {
  public readonly retryable: boolean;

  constructor(
    public readonly code: LivePlexTransportErrorCode,
    message: string,
    public readonly httpStatus?: number,
    options: { retryable?: boolean; cause?: unknown } = {},
  ) {
    super(message);
    this.name = 'LivePlexTransportError';
    this.retryable = options.retryable ?? false;
    if (options.cause !== undefined) {
      this.cause = sanitizeTransportCause(options.cause);
    }
  }
}

function sanitizeTransportCause(cause: unknown): unknown {
  if (cause instanceof Error) {
    return { name: cause.name, message: redactTransportText(cause.message) };
  }
  if (typeof cause === 'string') {
    return redactTransportText(cause).slice(0, 256);
  }
  return undefined;
}

function redactTransportText(value: string): string {
  return value
    .replace(/([?&]X-Plex-Token=)[^&\s)]+/giu, '$1[REDACTED]')
    .replace(/([?&]pin=)[^&#\s)'"<>]+/giu, '$1[REDACTED]')
    .replace(/(X-Plex-Token\s*[:=]\s*)[^\s,;)]+/giu, '$1[REDACTED]')
    .replace(/(\btoken=)[^&\s)]+/giu, '$1[REDACTED]')
    .replace(/(\bpin["']?\s*[:=]\s*["']?)[^"',\s)]+/giu, '$1[REDACTED]')
    .replace(/(\bauthToken["']?\s*[:=]\s*["']?)[^"',\s)]+/giu, '$1[REDACTED]');
}
