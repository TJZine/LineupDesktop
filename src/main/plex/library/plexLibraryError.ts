export type PlexLibraryErrorCode =
  | 'parse-error'
  | 'network-error'
  | 'authentication-expired'
  | 'server-error'
  | 'rate-limited'
  | 'aborted';

export interface PlexLibraryErrorOptions {
  cause?: unknown;
  context?: unknown;
}

export class PlexLibraryError extends Error {
  public readonly cause: unknown;
  public readonly context: unknown;

  constructor(
    public readonly code: PlexLibraryErrorCode,
    message: string,
    public readonly httpStatus?: number,
    options: PlexLibraryErrorOptions = {},
  ) {
    super(redactLibraryErrorText(message));
    this.name = 'PlexLibraryError';
    this.cause = sanitizePlexLibraryErrorValue(options.cause);
    this.context = sanitizePlexLibraryErrorValue(options.context);
  }
}

export function redactLibraryErrorText(value: string): string {
  return value
    .replace(/([?&][^=]*token[^=]*=)[^&\s]+/giu, '$1[redacted]')
    .replace(/\b(bearer)\s+[a-z0-9._~-]+/giu, '$1 [redacted]')
    .replace(/\b(secret|credential|password)=\S+/giu, '$1=[redacted]');
}

function sanitizePlexLibraryErrorValue(value: unknown): unknown {
  if (value === undefined) {
    return undefined;
  }

  if (value instanceof PlexLibraryError) {
    return {
      name: value.name,
      code: value.code,
      message: value.message,
      ...(value.httpStatus !== undefined ? { httpStatus: value.httpStatus } : {}),
      ...(value.context !== undefined ? { context: value.context } : {}),
    };
  }

  if (value instanceof Error) {
    return {
      name: value.name,
      message: redactLibraryErrorText(value.message),
      ...(typeof value.stack === 'string'
        ? { stack: redactLibraryErrorText(value.stack).slice(0, 8000) }
        : {}),
    };
  }

  if (typeof value === 'string') {
    return redactLibraryErrorText(value);
  }

  if (typeof value === 'object' && value !== null) {
    return { summary: redactLibraryErrorText(JSON.stringify(value).slice(0, 8000)) };
  }

  return value;
}
