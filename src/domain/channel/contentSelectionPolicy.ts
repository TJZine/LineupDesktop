import { applyPlaybackOrdering } from '../scheduler/shared/playbackOrdering.js';
import { shuffleWithSeed } from '../scheduler/shared/prng.js';
import type {
  ContentFilter,
  PlaybackMode,
  ResolvedContentItem,
  SortOrder,
} from './types.js';

export class ContentSelectionPolicy {
  public applyFilters(items: ResolvedContentItem[], filters: ContentFilter[]): ResolvedContentItem[] {
    if (!filters.length) {
      return items;
    }
    return items.filter((item) => filters.every((filter) => this.matchesFilter(item, filter)));
  }

  public applySort(items: ResolvedContentItem[], order: SortOrder): ResolvedContentItem[] {
    const result = [...items];

    switch (order) {
      case 'title_asc':
        result.sort((a, b) => a.title.localeCompare(b.title));
        break;
      case 'title_desc':
        result.sort((a, b) => b.title.localeCompare(a.title));
        break;
      case 'year_asc':
        result.sort((a, b) => a.year - b.year);
        break;
      case 'year_desc':
        result.sort((a, b) => b.year - a.year);
        break;
      case 'duration_asc':
        result.sort((a, b) => a.durationMs - b.durationMs);
        break;
      case 'duration_desc':
        result.sort((a, b) => b.durationMs - a.durationMs);
        break;
      case 'episode_order':
        result.sort((a, b) => {
          const seasonA = a.seasonNumber || 0;
          const seasonB = b.seasonNumber || 0;
          if (seasonA !== seasonB) return seasonA - seasonB;
          const epA = a.episodeNumber || 0;
          const epB = b.episodeNumber || 0;
          return epA - epB;
        });
        break;
      case 'added_asc':
        result.sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0));
        break;
      case 'added_desc':
        result.sort((a, b) => (b.addedAt || 0) - (a.addedAt || 0));
        break;
      default:
        throw new Error(`Unknown content sort order: ${String(order)}`);
    }

    return result;
  }

  public applyPlaybackMode(
    items: ResolvedContentItem[],
    mode: PlaybackMode,
    seed: number,
    blockSize?: number,
  ): ResolvedContentItem[] {
    switch (mode) {
      case 'sequential':
      case 'shuffle':
      case 'block':
        return applyPlaybackOrdering({
          items,
          mode,
          seed,
          blockSize,
          shuffleItems: shuffleWithSeed,
        });
      case 'random':
        return shuffleWithSeed(items, seed).map((item, index) => ({
          ...item,
          scheduledIndex: index,
        }));
      default:
        throw new Error(`Unknown content playback mode: ${String(mode)}`);
    }
  }

  private matchesFilter(item: ResolvedContentItem, filter: ContentFilter): boolean {
    let value: unknown;
    switch (filter.field) {
      case 'year':
        value = item.year;
        break;
      case 'duration':
        value = item.durationMs;
        break;
      case 'rating':
        value = item.rating;
        if (value === undefined) return false;
        break;
      case 'contentRating':
        value = item.contentRating;
        if (value === undefined) return false;
        break;
      case 'genre':
        return matchesStringArrayFilter(item.genres || [], filter);
      case 'director':
        return matchesStringArrayFilter(item.directors || [], filter);
      case 'watched':
        value = item.watched;
        if (value === undefined) return false;
        break;
      case 'addedAt':
        value = item.addedAt;
        if (value === undefined) return false;
        break;
      default:
        return false;
    }

    switch (filter.operator) {
      case 'eq':
        return value === filter.value;
      case 'neq':
        return value !== filter.value;
      case 'gt':
      case 'gte':
      case 'lt':
      case 'lte':
        return compareNumeric(value, filter.value, filter.operator);
      case 'contains':
        return String(value).toLowerCase().includes(String(filter.value).toLowerCase());
      case 'notContains':
        return !String(value).toLowerCase().includes(String(filter.value).toLowerCase());
      default:
        return false;
    }
  }
}

function matchesStringArrayFilter(values: string[], filter: ContentFilter): boolean {
  const expected = String(filter.value).toLowerCase();
  switch (filter.operator) {
    case 'contains':
      return values.some((value) => value.toLowerCase().includes(expected));
    case 'notContains':
      return !values.some((value) => value.toLowerCase().includes(expected));
    case 'eq':
      return values.some((value) => value.toLowerCase() === expected);
    case 'neq':
      return !values.some((value) => value.toLowerCase() === expected);
    default:
      return false;
  }
}

function compareNumeric(value: unknown, filterValue: unknown, operator: ContentFilter['operator']): boolean {
  const numVal = Number(value);
  const numFilter = Number(filterValue);
  if (!Number.isFinite(numVal) || !Number.isFinite(numFilter)) {
    return false;
  }
  if (operator === 'gt') return numVal > numFilter;
  if (operator === 'gte') return numVal >= numFilter;
  if (operator === 'lt') return numVal < numFilter;
  return numVal <= numFilter;
}
