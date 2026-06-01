import type { PlexMediaType } from './types.js';

const SEARCH_HUB_MEDIA_TYPES = new Map<string, PlexMediaType>([
  ['movie', 'movie'],
  ['movies', 'movie'],
  ['show', 'show'],
  ['shows', 'show'],
  ['episode', 'episode'],
  ['episodes', 'episode'],
  ['track', 'track'],
  ['tracks', 'track'],
  ['clip', 'clip'],
  ['clips', 'clip'],
]);

const SAFE_FILTER_KEY_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/u;
const SAFE_LIBRARY_FILTER_KEYS = new Set([
  'actor',
  'audienceRating',
  'collection',
  'contentRating',
  'country',
  'decade',
  'director',
  'episode.unwatched',
  'genre',
  'hdr',
  'producer',
  'rating',
  'resolution',
  'studio',
  'subtitleLanguage',
  'type',
  'unwatched',
  'watched',
  'writer',
  'year',
]);
const SAFE_SEARCH_TYPES = new Set<PlexMediaType>(['movie', 'show', 'episode', 'track', 'clip']);

export function isSafeLibraryFilter(
  value: unknown,
): value is Readonly<Record<string, string | number>> | undefined {
  if (value === undefined) {
    return true;
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  for (const [key, child] of Object.entries(value)) {
    if (!SAFE_FILTER_KEY_PATTERN.test(key) || !SAFE_LIBRARY_FILTER_KEYS.has(key)) {
      return false;
    }
    if (typeof child === 'number' && Number.isFinite(child)) {
      continue;
    }
    if (typeof child === 'string' && child.length > 0 && child.length <= 256) {
      continue;
    }
    return false;
  }
  return true;
}

export function isSafeSearchTypes(value: unknown): value is readonly PlexMediaType[] | undefined {
  return (
    value === undefined ||
    (Array.isArray(value) &&
      value.length <= SAFE_SEARCH_TYPES.size &&
      value.every((type) => SAFE_SEARCH_TYPES.has(type)))
  );
}

export function isSafeSearchLimit(value: unknown): value is number | undefined {
  return value === undefined ||
    (typeof value === 'number' && Number.isFinite(value) && Number.isInteger(value) && value > 0);
}

export function mapSearchHubTypeToMediaType(type: string): PlexMediaType | null {
  return SEARCH_HUB_MEDIA_TYPES.get(type.trim().toLowerCase()) ?? null;
}
