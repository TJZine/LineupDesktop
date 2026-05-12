export type ChannelErrorCode =
  | 'CHANNEL_NOT_FOUND'
  | 'CHANNEL_CONTENT_SOURCE_REQUIRED'
  | 'CHANNEL_CONTENT_SOURCE_INVALID'
  | 'MAX_CHANNELS_REACHED'
  | 'INVALID_CHANNEL_NUMBER'
  | 'DUPLICATE_CHANNEL_NUMBER'
  | 'INVALID_IMPORT_DATA'
  | 'SCHEDULER_EMPTY_CHANNEL'
  | 'CONTENT_UNAVAILABLE'
  | 'ACCESS_DENIED'
  | 'RESOURCE_NOT_FOUND'
  | 'NETWORK_TIMEOUT'
  | 'NETWORK_OFFLINE'
  | 'SERVER_UNREACHABLE'
  | 'NETWORK_UNAVAILABLE'
  | 'STORAGE_VALIDATION_FAILED';

export class ChannelError extends Error {
  public readonly code: ChannelErrorCode;
  public readonly recoverable: boolean;
  public readonly status: number | undefined;

  public constructor(
    code: ChannelErrorCode,
    message: string,
    recoverable = false,
    status?: number,
  ) {
    super(message);
    this.name = 'ChannelError';
    this.code = code;
    this.recoverable = recoverable;
    this.status = status;
  }
}

export function getChannelErrorCode(error: unknown): ChannelErrorCode | null {
  if (!error || typeof error !== 'object' || !('code' in error)) {
    return null;
  }
  const code = (error as { code?: unknown }).code;
  return typeof code === 'string' && isChannelErrorCode(code) ? code : null;
}

function isChannelErrorCode(value: string): value is ChannelErrorCode {
  switch (value) {
    case 'CHANNEL_NOT_FOUND':
    case 'CHANNEL_CONTENT_SOURCE_REQUIRED':
    case 'CHANNEL_CONTENT_SOURCE_INVALID':
    case 'MAX_CHANNELS_REACHED':
    case 'INVALID_CHANNEL_NUMBER':
    case 'DUPLICATE_CHANNEL_NUMBER':
    case 'INVALID_IMPORT_DATA':
    case 'SCHEDULER_EMPTY_CHANNEL':
    case 'CONTENT_UNAVAILABLE':
    case 'ACCESS_DENIED':
    case 'RESOURCE_NOT_FOUND':
    case 'NETWORK_TIMEOUT':
    case 'NETWORK_OFFLINE':
    case 'SERVER_UNREACHABLE':
    case 'NETWORK_UNAVAILABLE':
    case 'STORAGE_VALIDATION_FAILED':
      return true;
    default:
      return false;
  }
}
