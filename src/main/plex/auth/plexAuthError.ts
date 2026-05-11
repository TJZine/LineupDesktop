export type PlexAuthErrorCode =
  | 'parse-error'
  | 'auth-required'
  | 'auth-invalid'
  | 'auth-failed'
  | 'pin-expired'
  | 'pin-timeout'
  | 'rate-limited'
  | 'resource-not-found'
  | 'server-error'
  | 'server-unreachable'
  | 'aborted';

export interface PlexAuthErrorOptions {
  cause?: unknown;
  context?: unknown;
  retryable?: boolean;
}

export class PlexAuthError extends Error {
  public readonly cause: unknown;
  public readonly context: unknown;
  public readonly retryable: boolean;

  constructor(
    public readonly code: PlexAuthErrorCode,
    message: string,
    public readonly httpStatus?: number,
    options: PlexAuthErrorOptions = {},
  ) {
    super(redactAuthErrorText(message));
    this.name = 'PlexAuthError';
    this.retryable = options.retryable ?? false;
    this.cause = sanitizePlexAuthErrorValue(options.cause);
    this.context = sanitizePlexAuthErrorValue(options.context);
  }
}

export function redactAuthErrorText(value: string): string {
  return redactQuotedAuthFields(value)
    .replace(/([?&][^=]*token[^=]*=)[^&\s]+/giu, '$1[redacted]')
    .replace(/\b(bearer)\s+[a-z0-9._~+/-]+/giu, '$1 [redacted]')
    .replace(MULTIPART_AUTH_HEADER_FIELD_PATTERN, '$1=[redacted]')
    .replace(BARE_AUTH_SECRET_FIELD_PATTERN, '$1=[redacted]');
}

const AUTH_SECRET_FIELD_PATTERN =
  'token|authToken|authenticationToken|accountToken|activeToken|plexToken|clientSecret|pin|header|headers|authorization|secret|credential|password|X-Plex-Token';

const ESCAPED_QUOTED_AUTH_SECRET_FIELD_PATTERN = new RegExp(
  `(\\\\")\\s*(${AUTH_SECRET_FIELD_PATTERN})\\s*(\\\\")(\\s*:\\s*)(\\\\")([^\\\\"]*)(\\\\")`,
  'giu',
);

const BARE_AUTH_SECRET_FIELD_PATTERN = new RegExp(
  `\\b(${AUTH_SECRET_FIELD_PATTERN})\\s*[:=]\\s*\\S+`,
  'giu',
);

const MULTIPART_AUTH_HEADER_FIELD_PATTERN =
  /\b(headers?|authorization|x-plex-token)\s*[:=]\s*[^\r\n]+/giu;

const QUOTED_AUTH_SECRET_FIELD_PATTERN = new RegExp(
  `(")\\s*(${AUTH_SECRET_FIELD_PATTERN})\\s*(")(\\s*:\\s*)(")([^"\\\\]*(?:\\\\.[^"\\\\]*)*)(")`,
  'giu',
);

const AUTH_SECRET_FIELD_KEYS = new Set(
  [
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
  ].map((key) => key.toLowerCase()),
);

const REDACTED_AUTH_VALUE = '[redacted]';

function redactQuotedAuthFields(value: string): string {
  return value
    .replace(
      ESCAPED_QUOTED_AUTH_SECRET_FIELD_PATTERN,
      (
        _match,
        openingKeyQuote: string,
        key: string,
        closingKeyQuote: string,
        separator: string,
        openingValueQuote: string,
        _secretValue: string,
        closingValueQuote: string,
      ) =>
        `${openingKeyQuote}${key}${closingKeyQuote}${separator}${openingValueQuote}${REDACTED_AUTH_VALUE}${closingValueQuote}`,
    )
    .replace(
      QUOTED_AUTH_SECRET_FIELD_PATTERN,
      (
        _match,
        openingKeyQuote: string,
        key: string,
        closingKeyQuote: string,
        separator: string,
        openingValueQuote: string,
        _secretValue: string,
        closingValueQuote: string,
      ) =>
        `${openingKeyQuote}${key}${closingKeyQuote}${separator}${openingValueQuote}${REDACTED_AUTH_VALUE}${closingValueQuote}`,
    );
}

export function createPlexAuthHttpError(status: number): PlexAuthError {
  if (status === 401) {
    return new PlexAuthError('auth-required', 'Plex authentication is required', 401);
  }
  if (status === 403) {
    return new PlexAuthError('auth-invalid', 'Plex authentication was rejected', 403);
  }
  if (status === 404) {
    return new PlexAuthError('resource-not-found', 'Plex resource was not found', 404);
  }
  if (status === 429) {
    return new PlexAuthError('rate-limited', 'Plex rate limit reached', 429, { retryable: true });
  }
  if (status >= 500) {
    return new PlexAuthError('server-error', `Plex service error: ${status}`, status, {
      retryable: true,
    });
  }
  return new PlexAuthError('server-error', `Plex request failed: ${status}`, status);
}

function sanitizePlexAuthErrorValue(
  value: unknown,
  seen: WeakSet<object> = new WeakSet<object>(),
): unknown {
  if (value === undefined) {
    return undefined;
  }

  if (value instanceof PlexAuthError) {
    if (seen.has(value)) {
      return '[Circular]';
    }
    seen.add(value);

    return {
      name: value.name,
      code: value.code,
      message: value.message,
      ...(value.httpStatus !== undefined ? { httpStatus: value.httpStatus } : {}),
      ...(value.context !== undefined ? { context: sanitizePlexAuthErrorValue(value.context, seen) } : {}),
    };
  }

  if (value instanceof Error) {
    if (seen.has(value)) {
      return '[Circular]';
    }
    seen.add(value);

    const cause = (value as Error & { cause?: unknown }).cause;
    return {
      name: value.name,
      message: redactAuthErrorText(value.message),
      ...(cause !== undefined ? { cause: sanitizePlexAuthErrorValue(cause, seen) } : {}),
    };
  }

  if (typeof value === 'string') {
    return redactAuthErrorText(value);
  }

  if (Array.isArray(value)) {
    if (seen.has(value)) {
      return '[Circular]';
    }
    seen.add(value);
    return value.map((item) => sanitizePlexAuthErrorValue(item, seen));
  }

  if (typeof value === 'object' && value !== null) {
    if (seen.has(value)) {
      return '[Circular]';
    }
    seen.add(value);

    const sanitized: Record<string, unknown> = {};
    for (const [key, child] of Object.entries(value)) {
      sanitized[key] = isAuthSecretFieldKey(key)
        ? REDACTED_AUTH_VALUE
        : sanitizePlexAuthErrorValue(child, seen);
    }
    return sanitized;
  }

  return value;
}

function isAuthSecretFieldKey(key: string): boolean {
  return AUTH_SECRET_FIELD_KEYS.has(key.toLowerCase());
}
