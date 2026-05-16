import { redactAuthErrorText } from '../auth/plexAuthError.js';

export type PlexDiscoveryErrorCode =
  | 'parse-error'
  | 'auth-required'
  | 'auth-invalid'
  | 'resource-not-found'
  | 'rate-limited'
  | 'server-unreachable'
  | 'server-error'
  | 'aborted';

export interface PlexDiscoveryErrorOptions {
  cause?: unknown;
  context?: unknown;
  retryable?: boolean;
}

export class PlexDiscoveryError extends Error {
  public readonly cause: unknown;
  public readonly context: unknown;
  public readonly retryable: boolean;

  constructor(
    public readonly code: PlexDiscoveryErrorCode,
    message: string,
    public readonly httpStatus?: number,
    options: PlexDiscoveryErrorOptions = {},
  ) {
    super(redactAuthErrorText(message));
    this.name = 'PlexDiscoveryError';
    this.retryable = options.retryable ?? false;
    this.cause = sanitizeDiscoveryErrorValue(options.cause);
    this.context = sanitizeDiscoveryErrorValue(options.context);
  }
}

function sanitizeDiscoveryErrorValue(value: unknown): unknown {
  if (value === undefined) {
    return undefined;
  }

  if (value instanceof PlexDiscoveryError) {
    return {
      name: value.name,
      code: value.code,
      message: value.message,
      ...(value.httpStatus !== undefined ? { httpStatus: value.httpStatus } : {}),
    };
  }

  if (value instanceof Error) {
    return {
      name: value.name,
      message: redactAuthErrorText(value.message),
    };
  }

  if (typeof value === 'string') {
    return redactAuthErrorText(value);
  }

  if (typeof value === 'object' && value !== null) {
    return { summary: summarizeDiscoveryErrorObject(value) };
  }

  return value;
}

function summarizeDiscoveryErrorObject(value: object): string {
  try {
    return redactAuthErrorText(JSON.stringify(value).slice(0, 8000));
  } catch (error) {
    const reason = describeSanitizerFailure(error);
    return redactAuthErrorText(`unserializable object: ${reason}`).slice(0, 8000);
  }
}

function describeSanitizerFailure(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  try {
    return String(error);
  } catch {
    return 'unknown serialization failure';
  }
}
