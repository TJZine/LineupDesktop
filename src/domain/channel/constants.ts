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
  CONTENT_SOURCE_REQUIRED: 'Content source is required',
  CONTENT_SOURCE_INVALID: 'Content source is invalid',
  MAX_CHANNELS_REACHED: 'Maximum number of channels reached',
  INVALID_CHANNEL_NUMBER: 'Channel number must be an integer between 1 and 500',
  DUPLICATE_CHANNEL_NUMBER: 'Channel number already in use',
  INVALID_IMPORT_DATA: 'Import file is invalid',
  EMPTY_CONTENT: 'No playable content found after filtering',
} as const;
