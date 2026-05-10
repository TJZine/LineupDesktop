import type {
  PlexCollectionSummary,
  PlexLibrarySectionSummary,
  PlexMediaItemSummary,
  PlexPlaylistSummary,
  PlexTagDirectorySummary,
} from '../../../contracts/plex.js';
import { PLEX_LIBRARY_CONSTANTS, PLEX_MEDIA_TYPES } from './constants.js';
import type {
  LibraryQueryOptions,
  PlexCollection,
  PlexLibraryRequestIntent,
  PlexLibrarySection,
  PlexMediaItem,
  PlexPlaylist,
  PlexTagDirectoryItem,
} from './types.js';

export type ChannelSetupPlexRequestUseCase = 'preview' | 'build';

export type PlexTagDirectoryMediaTypes = {
  genreType: number;
  detailType: number;
};

export interface PlexPaginationWindow {
  offset: number;
  limit: number;
}

export function getPlexRequestIntentForChannelSetup(
  useCase: ChannelSetupPlexRequestUseCase,
): PlexLibraryRequestIntent {
  return useCase === 'preview' ? 'preview' : 'background';
}

export function getTagDirectoryMediaTypesForLibraryType(
  libraryType: PlexLibrarySection['type'],
): PlexTagDirectoryMediaTypes {
  if (libraryType === 'show') {
    return {
      genreType: PLEX_MEDIA_TYPES.SHOW,
      detailType: PLEX_MEDIA_TYPES.EPISODE,
    };
  }

  return {
    genreType: PLEX_MEDIA_TYPES.MOVIE,
    detailType: PLEX_MEDIA_TYPES.MOVIE,
  };
}

export function normalizeLibraryPagination(options: LibraryQueryOptions = {}): PlexPaginationWindow {
  const offset = normalizeNonNegativeInteger(options.offset, 0);
  const requestedLimit = normalizePositiveInteger(
    options.limit,
    PLEX_LIBRARY_CONSTANTS.DEFAULT_PAGE_SIZE,
  );

  return {
    offset,
    limit: Math.min(requestedLimit, PLEX_LIBRARY_CONSTANTS.ALL_LEAVES_PAGE_SIZE),
  };
}

export function shouldContinueLibraryPagination(input: {
  iterations: number;
  fetchedCount: number;
  totalSize?: number;
  pageSize: number;
}): boolean {
  if (input.iterations >= PLEX_LIBRARY_CONSTANTS.MAX_PAGINATION_ITERATIONS) {
    return false;
  }

  if (input.fetchedCount <= 0) {
    return false;
  }

  if (typeof input.totalSize === 'number' && Number.isFinite(input.totalSize)) {
    return input.fetchedCount < input.totalSize;
  }

  return input.fetchedCount >= input.pageSize;
}

export function toRendererSafeLibrarySectionSummary(
  section: PlexLibrarySection,
): PlexLibrarySectionSummary {
  return {
    id: section.id,
    title: section.title,
    type: section.type,
    contentCount: section.contentCount,
    ...(section.episodeCount !== undefined ? { episodeCount: section.episodeCount } : {}),
    lastScannedAtMs: section.lastScannedAt.getTime(),
  };
}

export function toRendererSafeMediaItemSummary(item: PlexMediaItem): PlexMediaItemSummary {
  return {
    ratingKey: item.ratingKey,
    type: item.type,
    title: item.title,
    sortTitle: item.sortTitle,
    summary: item.summary,
    year: item.year,
    durationMs: item.durationMs,
    addedAtMs: item.addedAt.getTime(),
    updatedAtMs: item.updatedAt.getTime(),
    ...(item.rating !== undefined ? { rating: item.rating } : {}),
    ...(item.audienceRating !== undefined ? { audienceRating: item.audienceRating } : {}),
    ...(item.contentRating !== undefined ? { contentRating: item.contentRating } : {}),
    ...(item.genres !== undefined ? { genres: item.genres } : {}),
    ...(item.directors !== undefined ? { directors: item.directors } : {}),
    ...(item.actors !== undefined ? { actors: item.actors } : {}),
    ...(item.studios !== undefined ? { studios: item.studios } : {}),
    ...(item.grandparentTitle !== undefined ? { grandparentTitle: item.grandparentTitle } : {}),
    ...(item.parentTitle !== undefined ? { parentTitle: item.parentTitle } : {}),
    ...(item.seasonNumber !== undefined ? { seasonNumber: item.seasonNumber } : {}),
    ...(item.episodeNumber !== undefined ? { episodeNumber: item.episodeNumber } : {}),
    ...(item.viewOffset !== undefined ? { viewOffset: item.viewOffset } : {}),
    ...(item.viewCount !== undefined ? { viewCount: item.viewCount } : {}),
    ...(item.lastViewedAt !== undefined ? { lastViewedAtMs: item.lastViewedAt.getTime() } : {}),
  };
}

export function toRendererSafeCollectionSummary(
  collection: PlexCollection,
): PlexCollectionSummary {
  return {
    ratingKey: collection.ratingKey,
    title: collection.title,
    childCount: collection.childCount,
  };
}

export function toRendererSafePlaylistSummary(playlist: PlexPlaylist): PlexPlaylistSummary {
  return {
    ratingKey: playlist.ratingKey,
    title: playlist.title,
    duration: playlist.duration,
    leafCount: playlist.leafCount,
  };
}

export function toRendererSafeTagDirectorySummary(
  tag: PlexTagDirectoryItem,
): PlexTagDirectorySummary {
  return {
    key: tag.key,
    title: tag.title,
    count: tag.count,
  };
}

function normalizeNonNegativeInteger(value: number | undefined, fallback: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return fallback;
  }

  return Math.max(0, Math.floor(value));
}

function normalizePositiveInteger(value: number | undefined, fallback: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    return fallback;
  }

  return Math.floor(value);
}
