import type {
  ChannelConfig,
  ChannelContentSource,
  ContentFilter,
  ManualContentItem,
  ResolvedChannelContent,
  ResolvedContentItem,
} from './types.js';

export function cloneChannelForOwnership(channel: ChannelConfig): ChannelConfig {
  return {
    ...channel,
    contentSource: cloneContentSource(channel.contentSource),
    ...(channel.contentFilters ? { contentFilters: cloneContentFilters(channel.contentFilters) } : {}),
  };
}

export function cloneContentFilters(filters: ContentFilter[]): ContentFilter[] {
  return filters.map((filter) => ({ ...filter }));
}

export function cloneContentSource(source: ChannelContentSource): ChannelContentSource {
  switch (source.type) {
    case 'library':
      return {
        ...source,
        ...(source.libraryFilter ? { libraryFilter: { ...source.libraryFilter } } : {}),
      };
    case 'manual':
      return {
        ...source,
        items: source.items.map(cloneManualContentItem),
      };
    case 'mixed':
      return {
        ...source,
        sources: source.sources.map(cloneContentSource),
      };
    case 'show':
      return {
        ...source,
        ...(source.seasonFilter ? { seasonFilter: [...source.seasonFilter] } : {}),
      };
    case 'collection':
    case 'playlist':
      return { ...source };
  }
}

export function cloneResolvedItem(
  item: ResolvedContentItem,
  scheduledIndex = item.scheduledIndex,
): ResolvedContentItem {
  const cloned: ResolvedContentItem = {
    ...item,
    scheduledIndex,
  };
  if (item.genres) {
    cloned.genres = [...item.genres];
  }
  if (item.directors) {
    cloned.directors = [...item.directors];
  }
  if (item.mediaInfo) {
    cloned.mediaInfo = { ...item.mediaInfo };
  }
  return cloned;
}

export function cloneResolvedItems(items: ReadonlyArray<ResolvedContentItem>): ResolvedContentItem[] {
  return items.map((item, index) => cloneResolvedItem(item, item.scheduledIndex ?? index));
}

export function cloneResolvedContent(
  content: ResolvedChannelContent,
  overrides?: Partial<Pick<ResolvedChannelContent, 'fromCache' | 'isStale' | 'cacheReason'>>,
): ResolvedChannelContent {
  const cloned: ResolvedChannelContent = {
    ...content,
    items: cloneResolvedItems(content.items),
    orderedItems: cloneResolvedItems(content.orderedItems),
  };
  const fromCache = overrides?.fromCache ?? content.fromCache;
  const isStale = overrides?.isStale ?? content.isStale;
  const cacheReason = overrides?.cacheReason ?? content.cacheReason;
  if (fromCache !== undefined) {
    cloned.fromCache = fromCache;
  }
  if (isStale !== undefined) {
    cloned.isStale = isStale;
  }
  if (cacheReason !== undefined) {
    cloned.cacheReason = cacheReason;
  }
  return cloned;
}

function cloneManualContentItem(item: ManualContentItem): ManualContentItem {
  return { ...item };
}
