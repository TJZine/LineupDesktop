import type { ChannelErrorCode } from './channelError.js';

export const CACHE_TTL_MS = 60 * 60 * 1000;

export const SOURCE_CACHE_TTL_MS = 5 * 60 * 1000;

export const SHOW_CACHE_TTL_MS = SOURCE_CACHE_TTL_MS;

export const SOURCE_CACHE_MAX_ENTRIES = 24;

export const CHANNEL_RETRY_DELAY_MS = 30 * 1000;

export const DEFAULT_CHANNEL_SETUP_MAX = 200;

export const MAX_CHANNELS = 500;

export const MIN_CHANNEL_NUMBER = 1;

export const MAX_CHANNEL_NUMBER = 500;

export const PLEX_MEDIA_TYPES = {
  MOVIE: 'movie',
  SHOW: 'show',
  EPISODE: 'episode',
} as const;

export const CHANNEL_ERROR_MESSAGES = {
  CHANNEL_NOT_FOUND: 'Channel not found',
  CHANNEL_CONTENT_SOURCE_REQUIRED: 'Content source is required',
  CHANNEL_CONTENT_SOURCE_INVALID: 'Content source is invalid',
  MAX_CHANNELS_REACHED: 'Maximum number of channels reached',
  INVALID_CHANNEL_NUMBER: 'Channel number must be an integer between 1 and 500',
  DUPLICATE_CHANNEL_NUMBER: 'Channel number already in use',
  INVALID_IMPORT_DATA: 'Import file is invalid',
  SCHEDULER_EMPTY_CHANNEL: 'No playable content found after filtering',
  CONTENT_UNAVAILABLE: 'Content source is unavailable',
  ACCESS_DENIED: 'Profile does not have access to this content',
  RESOURCE_NOT_FOUND: 'Content resource was not found',
  NETWORK_TIMEOUT: 'Network request timed out',
  NETWORK_OFFLINE: 'Network is offline',
  SERVER_UNREACHABLE: 'Server is unreachable',
  NETWORK_UNAVAILABLE: 'Network is unavailable',
  STORAGE_VALIDATION_FAILED: 'Channel storage validation failed',
} as const satisfies Record<ChannelErrorCode, string>;
