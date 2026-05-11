import type {
  BuildStrategy,
  ContentFilter,
  FilterField,
  FilterOperator,
  PlaybackMode,
  SortOrder,
} from './types.js';

const BUILD_STRATEGIES = [
  'collections',
  'playlists',
  'genres',
  'directors',
  'decades',
  'recentlyAdded',
  'studios',
  'actors',
  'libraryFallback',
] as const satisfies readonly BuildStrategy[];

const PLAYBACK_MODES = [
  'sequential',
  'shuffle',
  'block',
  'random',
] as const satisfies readonly PlaybackMode[];

const SORT_ORDERS = [
  'title_asc',
  'title_desc',
  'year_asc',
  'year_desc',
  'added_asc',
  'added_desc',
  'duration_asc',
  'duration_desc',
  'episode_order',
] as const satisfies readonly SortOrder[];

const FILTER_FIELDS = [
  'year',
  'rating',
  'contentRating',
  'genre',
  'director',
  'duration',
  'watched',
  'addedAt',
] as const satisfies readonly FilterField[];

const FILTER_OPERATORS = [
  'eq',
  'neq',
  'gt',
  'gte',
  'lt',
  'lte',
  'contains',
  'notContains',
] as const satisfies readonly FilterOperator[];

function includesValue<const T extends readonly string[]>(values: T, value: unknown): value is T[number] {
  return typeof value === 'string' && (values as readonly string[]).includes(value);
}

function isValidFilterValue(value: unknown): value is ContentFilter['value'] {
  if (typeof value === 'number') {
    return Number.isFinite(value);
  }
  return typeof value === 'string' || typeof value === 'boolean';
}

export function isValidBuildStrategy(value: unknown): value is BuildStrategy {
  return includesValue(BUILD_STRATEGIES, value);
}

export function isValidPlaybackMode(value: unknown): value is PlaybackMode {
  return includesValue(PLAYBACK_MODES, value);
}

export function isValidSortOrder(value: unknown): value is SortOrder {
  return includesValue(SORT_ORDERS, value);
}

export function isValidFilterField(value: unknown): value is FilterField {
  return includesValue(FILTER_FIELDS, value);
}

export function isValidFilterOperator(value: unknown): value is FilterOperator {
  return includesValue(FILTER_OPERATORS, value);
}

export function isValidContentFilter(value: unknown): value is ContentFilter {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  const filter = value as Record<string, unknown>;
  return (
    isValidFilterField(filter.field) &&
    isValidFilterOperator(filter.operator) &&
    isValidFilterValue(filter.value)
  );
}

export function isValidContentFilterArray(value: unknown): value is ContentFilter[] {
  return Array.isArray(value) && value.every(isValidContentFilter);
}
