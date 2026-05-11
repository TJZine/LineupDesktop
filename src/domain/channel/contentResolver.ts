import { ContentItemMapper } from './contentItemMapper.js';
import { ContentSelectionPolicy } from './contentSelectionPolicy.js';
import { PLEX_MEDIA_TYPES, SHOW_CACHE_TTL_MS } from './constants.js';
import { SourceResolutionCache } from './sourceResolutionCache.js';
import type { ChannelClock, ChannelLogger, ChannelResolveOptions, IPlexLibraryMinimal, PlexMediaItemMinimal } from './interfaces.js';
import type {
  ChannelContentSource,
  CollectionContentSource,
  ContentFilter,
  LibraryContentSource,
  ManualContentSource,
  MixedContentSource,
  PlaybackMode,
  PlaylistContentSource,
  ResolvedContentItem,
  ShowContentSource,
  SortOrder,
} from './types.js';

type ShowCacheEntry = {
  items: PlexMediaItemMinimal[];
  cachedAt: number;
};

export class ContentResolver {
  private readonly library: IPlexLibraryMinimal;
  private readonly logger: ChannelLogger;
  private readonly clock: ChannelClock;
  private readonly showCacheByLibraryId = new Map<string, ShowCacheEntry>();
  private readonly sourceCache: SourceResolutionCache;
  private readonly mapper = new ContentItemMapper();
  private readonly selectionPolicy = new ContentSelectionPolicy();

  public constructor(library: IPlexLibraryMinimal, clock: ChannelClock, logger: ChannelLogger) {
    this.library = library;
    this.clock = clock;
    this.logger = logger;
    this.sourceCache = new SourceResolutionCache(clock);
  }

  public clearCaches(): void {
    this.showCacheByLibraryId.clear();
    this.sourceCache.clear();
  }

  public invalidateSource(source: ChannelContentSource): void {
    this.sourceCache.invalidate(source);
    this.invalidateShowListCache(source);
  }

  public async resolveSource(
    source: ChannelContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    if (options?.signal?.aborted) {
      throw new Error('Aborted');
    }
    return this.sourceCache.resolve(
      source,
      (sourceToResolve, cacheOptions) => this.resolveSourceUncached(sourceToResolve, cacheOptions),
      options,
    );
  }

  public applyFilters(items: ResolvedContentItem[], filters: ContentFilter[]): ResolvedContentItem[] {
    return this.selectionPolicy.applyFilters(items, filters);
  }

  public applySort(items: ResolvedContentItem[], order: SortOrder): ResolvedContentItem[] {
    return this.selectionPolicy.applySort(items, order);
  }

  public applyPlaybackMode(
    items: ResolvedContentItem[],
    mode: PlaybackMode,
    seed: number,
    blockSize?: number,
  ): ResolvedContentItem[] {
    return this.selectionPolicy.applyPlaybackMode(items, mode, seed, blockSize);
  }

  private invalidateShowListCache(source: ChannelContentSource): void {
    if (source.type === 'library' && source.libraryType === 'show') {
      this.showCacheByLibraryId.delete(source.libraryId);
    }
    if (source.type === 'mixed') {
      for (const subSource of source.sources) {
        this.invalidateShowListCache(subSource);
      }
    }
  }

  private async resolveSourceUncached(
    source: ChannelContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    let items: ResolvedContentItem[];

    switch (source.type) {
      case 'library':
        items = await this.resolveLibrarySource(source, options);
        break;
      case 'collection':
        items = await this.resolveCollectionSource(source, options);
        break;
      case 'show':
        items = await this.resolveShowSource(source, options);
        break;
      case 'playlist':
        items = await this.resolvePlaylistSource(source, options);
        break;
      case 'manual':
        items = this.resolveManualSource(source);
        break;
      case 'mixed':
        items = await this.resolveMixedSource(source, options);
        break;
    }

    const expanded = await this.expandShowContainers(items, options);
    const playable = expanded.filter((item) => item.type !== 'show');
    if (playable.length < expanded.length) {
      this.logger.warn(`Filtered out ${expanded.length - playable.length} unexpanded show(s) from resolved content`);
    }
    return playable.map((item, index) => ({ ...item, scheduledIndex: index }));
  }

  private async expandShowContainers(
    items: ResolvedContentItem[],
    options?: ChannelResolveOptions & { strict?: boolean },
  ): Promise<ResolvedContentItem[]> {
    const expanded: ResolvedContentItem[] = [];

    for (const item of items) {
      if (item.type !== 'show') {
        expanded.push(item);
        continue;
      }

      try {
        const episodes = await this.library.getShowEpisodes(item.ratingKey, {
          signal: options?.signal ?? null,
        });
        if (episodes.length === 0) {
          if (options?.strict) {
            throw new Error(`Show item returned no episodes during strict expansion (${item.ratingKey})`);
          }
          this.logger.warn('Show item returned no episodes during expansion', item.ratingKey);
          continue;
        }
        for (const episode of episodes) {
          const showThumb = item.showThumb ?? item.thumb ?? null;
          const merged = this.mapper.decorateEpisodeFromParent(episode, {
            genres: item.genres,
            directors: item.directors,
            contentRating: item.contentRating,
            rating: item.rating,
            year: item.year,
            grandparentTitle: item.title,
            grandparentThumb: showThumb,
            art: item.art,
            clearLogo: item.clearLogo,
          });
          expanded.push(this.mapper.toResolvedItem(merged, 0));
        }
      } catch (error) {
        if (options?.strict || isAbortLike(error, options?.signal ?? undefined)) {
          throw error;
        }
        this.logger.warn('Failed to expand show item', { ratingKey: item.ratingKey, error: summarizeError(error) });
      }
    }

    return expanded;
  }

  private async resolveLibrarySource(
    source: LibraryContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    if (source.libraryType !== 'show') {
      const optionsWithFilter = source.libraryFilter
        ? { ...options, filter: source.libraryFilter }
        : options;
      const items = await this.library.getLibraryItems(source.libraryId, optionsWithFilter);
      return items.map((item, index) => this.mapper.toResolvedItem(item, index));
    }

    const hasGenreLibraryFilter = source.libraryFilter && 'genre' in source.libraryFilter;
    if (hasGenreLibraryFilter) {
      const items = await this.library.getLibraryItems(source.libraryId, {
        ...options,
        filter: { ...source.libraryFilter, type: PLEX_MEDIA_TYPES.SHOW },
      });
      const resolvedShows = items.map((item, index) => this.mapper.toResolvedItem(item, index));
      return this.expandShowContainers(resolvedShows, { signal: options?.signal ?? null, strict: true });
    }

    const episodeItems = await this.library.getLibraryItems(source.libraryId, {
      ...options,
      filter: { ...(source.libraryFilter ?? {}), type: PLEX_MEDIA_TYPES.EPISODE },
    });

    const now = this.clock.now();
    const cached = this.showCacheByLibraryId.get(source.libraryId);
    let shows: PlexMediaItemMinimal[] | null = null;
    if (cached && now - cached.cachedAt < SHOW_CACHE_TTL_MS) {
      shows = cached.items;
    } else {
      try {
        shows = await this.library.getLibraryItems(source.libraryId, options);
        this.showCacheByLibraryId.set(source.libraryId, { items: shows, cachedAt: now });
      } catch (error) {
        if (isAbortLike(error, options?.signal ?? undefined)) throw error;
        if (cached) {
          this.logger.warn('Show list fetch failed, using cached show list', summarizeError(error));
          shows = cached.items;
          this.showCacheByLibraryId.set(source.libraryId, { items: cached.items, cachedAt: now });
        } else {
          this.logger.warn('Show list fetch failed, continuing without decoration', summarizeError(error));
        }
      }
    }

    const parentMap = new Map<string, PlexMediaItemMinimal>();
    for (const show of shows ?? []) {
      parentMap.set(show.ratingKey, show);
    }

    const decorated: PlexMediaItemMinimal[] = [];
    for (const episode of episodeItems) {
      if (episode.durationMs <= 0) continue;
      const parentKey = episode.grandparentRatingKey || episode.parentRatingKey;
      const parent = parentKey ? parentMap.get(parentKey) : null;
      decorated.push(
        parent
          ? this.mapper.decorateEpisodeFromParent(episode, {
              genres: parent.genres,
              directors: parent.directors,
              contentRating: parent.contentRating,
              rating: parent.rating,
              year: parent.year,
              grandparentTitle: parent.title,
              grandparentThumb: parent.thumb,
              art: parent.art,
              clearLogo: parent.clearLogo,
            })
          : episode,
      );
    }

    return decorated.map((item, index) => this.mapper.toResolvedItem(item, index));
  }

  private async resolveCollectionSource(
    source: CollectionContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    const items = await this.library.getCollectionItems(source.collectionKey, options);
    const expanded: PlexMediaItemMinimal[] = [];

    for (const item of items) {
      if (item.durationMs <= 0 && item.episodeNumber === undefined && item.seasonNumber === undefined) {
        try {
          const episodes = await this.library.getShowEpisodes(item.ratingKey, options);
          if (episodes.length > 0) {
            expanded.push(
              ...episodes.map((episode) =>
                this.mapper.decorateEpisodeFromParent(episode, {
                  genres: item.genres,
                  directors: item.directors,
                  contentRating: item.contentRating,
                  rating: item.rating,
                  year: item.year,
                  grandparentTitle: item.title,
                  grandparentThumb: item.thumb,
                  art: item.art,
                  clearLogo: item.clearLogo,
                })),
            );
            continue;
          }
        } catch (error) {
          this.logger.warn('Failed to expand show collection item', { ratingKey: item.ratingKey, error: summarizeError(error) });
        }
      }
      expanded.push(item);
    }

    return expanded.map((item, index) => this.mapper.toResolvedItem(item, index));
  }

  private async resolveShowSource(
    source: ShowContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    const items = await this.library.getShowEpisodes(source.showKey, options);
    const seasonFilter = source.seasonFilter;
    const filtered =
      seasonFilter && seasonFilter.length
        ? items.filter((episode) => typeof episode.seasonNumber === 'number' && seasonFilter.includes(episode.seasonNumber))
        : items;
    return filtered.map((item, index) => this.mapper.toResolvedItem(item, index));
  }

  private async resolvePlaylistSource(
    source: PlaylistContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    const items = await this.library.getPlaylistItems(source.playlistKey, options);
    return items.map((item, index) => this.mapper.toResolvedItem(item, index));
  }

  private resolveManualSource(source: ManualContentSource): ResolvedContentItem[] {
    const results: ResolvedContentItem[] = [];
    for (let index = 0; index < source.items.length; index++) {
      const manualItem = source.items[index];
      if (
        !manualItem ||
        typeof manualItem.ratingKey !== 'string' ||
        manualItem.ratingKey.length === 0 ||
        typeof manualItem.title !== 'string' ||
        manualItem.title.length === 0 ||
        typeof manualItem.durationMs !== 'number' ||
        !Number.isFinite(manualItem.durationMs) ||
        manualItem.durationMs <= 0
      ) {
        continue;
      }
      results.push({
        ratingKey: manualItem.ratingKey,
        type: 'movie',
        title: manualItem.title,
        fullTitle: manualItem.title,
        durationMs: manualItem.durationMs,
        thumb: null,
        year: 0,
        scheduledIndex: index,
      });
    }
    return results;
  }

  private async resolveMixedSource(
    source: MixedContentSource,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    const allResolved = await Promise.all(
      source.sources.map((subSource) => this.resolveSource(subSource, options)),
    );
    if (source.mixMode === 'sequential') {
      return allResolved.flat().map((item, index) => ({ ...item, scheduledIndex: index }));
    }
    return interleave(allResolved);
  }
}

function interleave(arrays: ResolvedContentItem[][]): ResolvedContentItem[] {
  const result: ResolvedContentItem[] = [];
  const maxLen = Math.max(...arrays.map((arr) => arr.length));

  for (let index = 0; index < maxLen; index++) {
    for (const arr of arrays) {
      const item = arr[index];
      if (item) {
        result.push({ ...item, scheduledIndex: result.length });
      }
    }
  }
  return result;
}

function isAbortLike(error: unknown, signal?: { aborted: boolean }): boolean {
  if (signal?.aborted) return true;
  if (error && typeof error === 'object' && 'name' in error) {
    return (error as { name?: unknown }).name === 'AbortError';
  }
  return false;
}

function summarizeError(error: unknown): unknown {
  if (error instanceof Error) {
    return { name: error.name, message: error.message };
  }
  return error;
}
