import {
  CHANNEL_SETUP_STRATEGY_KEYS,
  type ChannelSetupConfig,
  type ChannelSetupEstimates,
  type ChannelSetupStrategyKey,
} from '../../../contracts/channel.js';
import type { ChannelContentSource, ContentFilter } from '../types.js';
import { createChannelSetupIdentity } from './identity.js';
import type {
  ChannelSetupFacetSnapshot,
  ChannelSetupLibraryFacet,
  ChannelSetupNamedFacet,
  ChannelSetupPlan,
  ChannelSetupPlannedChannel,
} from './types.js';

type CandidateBuckets = Record<ChannelSetupStrategyKey, ChannelSetupPlannedChannel[]>;

export function buildChannelSetupPlan(
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
): ChannelSetupPlan {
  const libraries = snapshot.libraries
    .filter((library) => config.selectedLibraryIds.includes(library.id))
    .sort(compareLibraries);
  const buckets = createBuckets();
  buildPlaylistCandidates(buckets, config, snapshot);
  for (const library of libraries) {
    buildCollectionCandidates(buckets, config, snapshot, library);
    buildRecentlyAddedCandidate(buckets, config, library);
    buildFacetCandidates(buckets, config, snapshot, library, 'genres');
    buildFacetCandidates(buckets, config, snapshot, library, 'directors');
    buildDecadeCandidates(buckets, config, snapshot, library);
  }
  buildCrossLibraryFacetCandidates(buckets, config, snapshot, libraries, 'genres');
  buildCrossLibraryFacetCandidates(buckets, config, snapshot, libraries, 'directors');
  buildActorStudioCandidates(buckets, config, snapshot, libraries, 'studios');
  buildActorStudioCandidates(buckets, config, snapshot, libraries, 'actors');

  const orderedBase = orderedStrategies(config).flatMap((strategy) => buckets[strategy]);
  const normalizedBase = normalizeSeriesPlayback(orderedBase, libraries, config);
  const expandedAlternates = expandAlternateLineups(normalizedBase, config);
  const expanded = expandSeriesVariants(expandedAlternates, libraries, config);
  const afterMin = expanded.filter((channel) => (
    channel.eligibleItemCount === null || channel.eligibleItemCount >= config.minItemsPerChannel
  ));
  const channels = allocateByPriority(afterMin, config);
  const droppedByPlanCapCount = afterMin.length - channels.length;
  return {
    config,
    channels,
    estimates: estimate(channels),
    eligibleGeneratedCount: afterMin.length,
    selectedGeneratedCount: channels.length,
    droppedByMinItemsCount: expanded.length - afterMin.length,
    droppedByPlanCapCount,
    reachedMaxChannels: droppedByPlanCapCount > 0,
    warnings: [...snapshot.warnings],
  };
}

function buildPlaylistCandidates(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
): void {
  if (!config.strategyConfig.playlists.enabled) return;
  const seenPlaylistKeys = new Set<string>();
  for (const playlist of sortFacets(snapshot.playlists)) {
    if (seenPlaylistKeys.has(playlist.key)) continue;
    seenPlaylistKeys.add(playlist.key);
    addCandidate(buckets, {
      name: playlist.title,
      buildStrategy: 'playlists',
      contentSource: { type: 'playlist', playlistKey: playlist.key, playlistName: playlist.title },
      playbackMode: 'shuffle',
      eligibleItemCount: playlist.itemCount,
      seedKey: `playlist:${playlist.key}`,
    });
  }
}

function buildCollectionCandidates(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
  library: ChannelSetupLibraryFacet,
): void {
  if (!config.strategyConfig.collections.enabled) return;
  for (const collection of sortFacets(snapshot.collectionsByLibraryId.get(library.id) ?? [])) {
    addCandidate(buckets, {
      name: collection.title,
      buildStrategy: 'collections',
      contentSource: { type: 'collection', collectionKey: collection.key, collectionName: collection.title },
      playbackMode: 'shuffle',
      sourceLibraryId: library.id,
      sourceLibraryName: library.title,
      eligibleItemCount: collection.itemCount,
      seedKey: `collection:${collection.key}`,
    });
  }
}

function buildRecentlyAddedCandidate(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  library: ChannelSetupLibraryFacet,
): void {
  if (!config.strategyConfig.recentlyAdded.enabled) return;
  addCandidate(buckets, {
    name: `${library.title} - Recently Added`,
    buildStrategy: 'recentlyAdded',
    contentSource: librarySource(library),
    playbackMode: 'sequential',
    sortOrder: 'added_desc',
    sourceLibraryId: library.id,
    sourceLibraryName: library.title,
    eligibleItemCount: library.itemCount,
    seedKey: `recentlyAdded:${library.id}`,
  });
}

function buildFacetCandidates(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
  library: ChannelSetupLibraryFacet,
  strategy: 'genres' | 'directors',
): void {
  if (!config.strategyConfig[strategy].enabled || config.strategyConfig[strategy].scope !== 'per-library') return;
  const facets = strategy === 'genres' ? snapshot.genresByLibraryId : snapshot.directorsByLibraryId;
  for (const facet of sortFacets(facets.get(library.id) ?? [])) {
    addCandidate(buckets, {
      name: `${library.title} - ${facet.title}`,
      buildStrategy: strategy,
      contentSource: strategy === 'genres'
        ? librarySource(library, { genre: facet.title })
        : librarySource(library),
      ...(strategy === 'directors' ? { contentFilters: [tagFilter('director', facet.title)] } : {}),
      playbackMode: 'shuffle',
      sourceLibraryId: library.id,
      sourceLibraryName: library.title,
      eligibleItemCount: strategy === 'directors' && !peopleFacetCanContribute(library, facet, config.minItemsPerChannel)
        ? 0
        : facet.itemCount,
      seedKey: `${strategy === 'genres' ? 'genre' : 'director'}:${library.id}:${facet.key}`,
    });
  }
}

function buildCrossLibraryFacetCandidates(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
  libraries: readonly ChannelSetupLibraryFacet[],
  strategy: 'genres' | 'directors',
): void {
  if (!config.strategyConfig[strategy].enabled || config.strategyConfig[strategy].scope !== 'cross-library') return;
  const facets = strategy === 'genres' ? snapshot.genresByLibraryId : snapshot.directorsByLibraryId;
  const groups = groupFacets(libraries, facets);
  for (const group of groups) {
    const entries = strategy === 'directors'
      ? group.entries.filter(({ library, facet }) => peopleFacetCanContributeCrossLibrary(library, facet, config.minItemsPerChannel))
      : group.entries;
    if (entries.length === 0) continue;
    const sources = entries.map(({ library, facet }) => librarySource(library, { [strategy === 'genres' ? 'genre' : 'director']: facet.title }));
    addCandidate(buckets, {
      name: group.title,
      buildStrategy: strategy,
      contentSource: sources.length === 1 ? sources[0]! : { type: 'mixed', mixMode: 'interleave', sources },
      playbackMode: 'shuffle',
      eligibleItemCount: combinedCount(entries.map(({ facet }) => facet.itemCount)),
      seedKey: `${strategy === 'genres' ? 'genre' : 'director'}:cross:${group.key}`,
    });
  }
}

function buildDecadeCandidates(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
  library: ChannelSetupLibraryFacet,
): void {
  if (!config.strategyConfig.decades.enabled) return;
  const decades = new Map<number, Array<number | null>>();
  for (const year of snapshot.yearsByLibraryId.get(library.id) ?? []) {
    const numericYear = Number.parseInt(year.title, 10);
    if (!Number.isFinite(numericYear)) continue;
    const decade = Math.floor(numericYear / 10) * 10;
    decades.set(decade, [...(decades.get(decade) ?? []), year.itemCount]);
  }
  for (const decade of [...decades.keys()].sort((left, right) => left - right)) {
    addCandidate(buckets, {
      name: `${library.title} - ${decade}s`,
      buildStrategy: 'decades',
      contentSource: librarySource(library),
      contentFilters: [
        { field: 'year', operator: 'gte', value: decade },
        { field: 'year', operator: 'lt', value: decade + 10 },
      ],
      playbackMode: 'shuffle',
      sourceLibraryId: library.id,
      sourceLibraryName: library.title,
      eligibleItemCount: combinedCount(decades.get(decade) ?? []),
      seedKey: `decade:${library.id}:${decade}`,
    });
  }
}

function buildActorStudioCandidates(
  buckets: CandidateBuckets,
  config: ChannelSetupConfig,
  snapshot: ChannelSetupFacetSnapshot,
  libraries: readonly ChannelSetupLibraryFacet[],
  strategy: 'actors' | 'studios',
): void {
  if (!config.strategyConfig[strategy].enabled) return;
  const facets = strategy === 'actors' ? snapshot.actorsByLibraryId : snapshot.studiosByLibraryId;
  const filterKey = strategy === 'actors' ? 'actor' : 'studio';
  const scope = config.strategyConfig[strategy].scope;
  if (config.actorStudioCombineMode === 'separate' && scope === 'per-library') {
    for (const library of libraries) {
      for (const facet of sortFacets(facets.get(library.id) ?? [])) {
        addCandidate(buckets, {
          name: `${facet.title} - ${library.title}`,
          buildStrategy: strategy,
          contentSource: librarySource(library, { [filterKey]: facet.title }),
          playbackMode: 'shuffle',
          sourceLibraryId: library.id,
          sourceLibraryName: library.title,
          eligibleItemCount: strategy === 'actors' && !peopleFacetCanContribute(library, facet, config.minItemsPerChannel)
            ? 0
            : facet.itemCount,
          seedKey: `${filterKey}:${library.id}:${facet.key}`,
        });
      }
    }
    return;
  }

  const mixMode = scope === 'cross-library' ? 'interleave' : 'sequential';
  for (const group of groupFacets(libraries, facets)) {
    const entries = strategy === 'actors'
      ? group.entries.filter(({ library, facet }) => peopleFacetCanContributeCrossLibrary(library, facet, config.minItemsPerChannel))
      : group.entries;
    if (entries.length === 0) continue;
    const sources = entries.map(({ library, facet }) => librarySource(library, { [filterKey]: facet.title }));
    addCandidate(buckets, {
      name: group.title,
      buildStrategy: strategy,
      contentSource: { type: 'mixed', mixMode, sources },
      playbackMode: 'shuffle',
      eligibleItemCount: combinedCount(entries.map(({ facet }) => facet.itemCount)),
      seedKey: `${filterKey}:${group.key}`,
    });
  }
}

function normalizeSeriesPlayback(
  channels: readonly ChannelSetupPlannedChannel[],
  libraries: readonly ChannelSetupLibraryFacet[],
  config: ChannelSetupConfig,
): ChannelSetupPlannedChannel[] {
  const showLibraryIds = new Set(libraries.filter((library) => library.type === 'show').map((library) => library.id));
  return channels.map((channel) => {
    if (!isSeriesChannel(channel, showLibraryIds) || channel.playbackMode !== 'shuffle' || config.seriesOrdering.basePlaybackMode === 'shuffle') {
      return channel;
    }
    return {
      ...channel,
      playbackMode: config.seriesOrdering.basePlaybackMode,
      ...(config.seriesOrdering.basePlaybackMode === 'block' ? { blockSize: config.seriesOrdering.baseBlockSize } : { blockSize: undefined }),
    };
  });
}

function expandAlternateLineups(
  channels: readonly ChannelSetupPlannedChannel[],
  config: ChannelSetupConfig,
): ChannelSetupPlannedChannel[] {
  const expanded: ChannelSetupPlannedChannel[] = [];
  for (const channel of channels) {
    const base = { ...channel, lineupReplicaIndex: 0, isPlaybackModeVariant: false };
    expanded.push(base);
    if (!config.channelExpansion.addAlternateLineups || channel.playbackMode === 'sequential' || channel.buildStrategy === 'actors' || channel.buildStrategy === 'directors') continue;
    for (let index = 1; index <= config.channelExpansion.alternateLineupCopies; index += 1) {
      expanded.push({
        ...base,
        name: `${base.name} (${index + 1})`,
        lineupReplicaIndex: index,
        shuffleSeed: seedFor(`${createChannelSetupIdentity(base)}:replica:${index}`),
      });
    }
  }
  return expanded;
}

function expandSeriesVariants(
  channels: readonly ChannelSetupPlannedChannel[],
  libraries: readonly ChannelSetupLibraryFacet[],
  config: ChannelSetupConfig,
): ChannelSetupPlannedChannel[] {
  if (config.channelExpansion.variantType === 'none') return [...channels];
  const showLibraryIds = new Set(libraries.filter((library) => library.type === 'show').map((library) => library.id));
  const variants: ChannelSetupPlannedChannel[] = [];
  for (const channel of channels) {
    if (!isSeriesChannel(channel, showLibraryIds)) continue;
    if (config.channelExpansion.variantType === 'sequential' && channel.lineupReplicaIndex > 0) continue;
    const sameMode = channel.playbackMode === config.channelExpansion.variantType;
    const sameBlock = config.channelExpansion.variantType !== 'block' || channel.blockSize === config.channelExpansion.variantBlockSize;
    if (sameMode && sameBlock) continue;
    const blockSize = config.channelExpansion.variantType === 'block'
      ? config.channelExpansion.variantBlockSize
      : undefined;
    variants.push({
      ...channel,
      name: `${channel.name} • ${config.channelExpansion.variantType === 'block' ? 'Block' : 'Sequential'}`,
      playbackMode: config.channelExpansion.variantType,
      blockSize,
      isPlaybackModeVariant: true,
      shuffleSeed: seedFor(`${createChannelSetupIdentity(channel)}:variant:${config.channelExpansion.variantType}:${blockSize ?? 0}`),
    });
  }
  return [...channels, ...variants];
}

function allocateByPriority(
  channels: readonly ChannelSetupPlannedChannel[],
  config: ChannelSetupConfig,
): ChannelSetupPlannedChannel[] {
  if (channels.length <= config.maxChannels) return [...channels];
  const buckets = createBuckets();
  for (const channel of channels) buckets[channel.buildStrategy].push(channel);
  const strategies = orderedStrategies(config).filter((strategy) => buckets[strategy].length > 0);
  const cursors = new Map<ChannelSetupStrategyKey, number>();
  const selected: ChannelSetupPlannedChannel[] = [];
  while (selected.length < config.maxChannels) {
    let added = false;
    for (const strategy of strategies) {
      const cursor = cursors.get(strategy) ?? 0;
      const channel = buckets[strategy][cursor];
      if (!channel) continue;
      selected.push(channel);
      cursors.set(strategy, cursor + 1);
      added = true;
      if (selected.length === config.maxChannels) break;
    }
    if (!added) break;
  }
  return selected;
}

function addCandidate(
  buckets: CandidateBuckets,
  input: Omit<ChannelSetupPlannedChannel, 'shuffleSeed' | 'isAutoGenerated' | 'lineupReplicaIndex' | 'isPlaybackModeVariant'> & { seedKey: string },
): void {
  const { seedKey, ...channel } = input;
  const candidate: ChannelSetupPlannedChannel = {
    ...channel,
    shuffleSeed: seedFor(seedKey),
    isAutoGenerated: true,
    lineupReplicaIndex: 0,
    isPlaybackModeVariant: false,
  };
  buckets[channel.buildStrategy].push(candidate);
}

function groupFacets(
  libraries: readonly ChannelSetupLibraryFacet[],
  facetsByLibraryId: ReadonlyMap<string, readonly ChannelSetupNamedFacet[]>,
): Array<{ key: string; title: string; entries: Array<{ library: ChannelSetupLibraryFacet; facet: ChannelSetupNamedFacet }> }> {
  const groups = new Map<string, { key: string; title: string; entries: Array<{ library: ChannelSetupLibraryFacet; facet: ChannelSetupNamedFacet }> }>();
  for (const library of libraries) {
    for (const facet of sortFacets(facetsByLibraryId.get(library.id) ?? [])) {
      const key = facet.title.trim().toLocaleLowerCase();
      if (!key) continue;
      const group = groups.get(key) ?? { key, title: facet.title, entries: [] };
      group.entries.push({ library, facet });
      groups.set(key, group);
    }
  }
  return [...groups.values()].sort((left, right) => {
    const countDiff = (combinedCount(right.entries.map(({ facet }) => facet.itemCount)) ?? -1)
      - (combinedCount(left.entries.map(({ facet }) => facet.itemCount)) ?? -1);
    return countDiff || left.title.localeCompare(right.title);
  });
}

function peopleFacetCanContribute(
  library: ChannelSetupLibraryFacet,
  facet: ChannelSetupNamedFacet,
  minItems: number,
): boolean {
  if (library.type !== 'show') return facet.itemCount === null || facet.itemCount >= minItems;
  return (facet.itemCount === null || facet.itemCount >= minItems)
    && facet.seriesCount !== null
    && (facet.seriesCount ?? 0) >= 3;
}

function peopleFacetCanContributeCrossLibrary(
  library: ChannelSetupLibraryFacet,
  facet: ChannelSetupNamedFacet,
  minItems: number,
): boolean {
  if (library.type === 'movie') return true;
  return peopleFacetCanContribute(library, facet, minItems);
}

function librarySource(library: ChannelSetupLibraryFacet, libraryFilter?: Record<string, string | number>): ChannelContentSource {
  return {
    type: 'library',
    libraryId: library.id,
    libraryType: library.type,
    includeWatched: true,
    ...(libraryFilter ? { libraryFilter } : {}),
  };
}

function tagFilter(field: 'director', value: string): ContentFilter {
  return { field, operator: 'eq', value };
}

function combinedCount(counts: readonly (number | null)[]): number | null {
  return counts.some((count) => count === null) ? null : counts.reduce<number>((sum, count) => sum + (count ?? 0), 0);
}

function isSeriesChannel(channel: ChannelSetupPlannedChannel, showLibraryIds: ReadonlySet<string>): boolean {
  return (channel.sourceLibraryId !== undefined && showLibraryIds.has(channel.sourceLibraryId)) || isSeriesSource(channel.contentSource);
}

function isSeriesSource(source: ChannelContentSource): boolean {
  if (source.type === 'show') return true;
  if (source.type === 'library') return source.libraryType === 'show';
  return source.type === 'mixed' && source.sources.length > 0 && source.sources.every(isSeriesSource);
}

function orderedStrategies(config: ChannelSetupConfig): ChannelSetupStrategyKey[] {
  return [...CHANNEL_SETUP_STRATEGY_KEYS].sort((left, right) => (
    config.strategyConfig[left].priority - config.strategyConfig[right].priority || left.localeCompare(right)
  ));
}

function sortFacets<T extends ChannelSetupNamedFacet>(facets: readonly T[]): T[] {
  return [...facets].sort((left, right) => (
    (right.itemCount ?? -1) - (left.itemCount ?? -1)
    || left.title.localeCompare(right.title)
    || left.key.localeCompare(right.key)
  ));
}

function compareLibraries(left: ChannelSetupLibraryFacet, right: ChannelSetupLibraryFacet): number {
  return left.title.localeCompare(right.title) || left.id.localeCompare(right.id);
}

function createBuckets(): CandidateBuckets {
  return CHANNEL_SETUP_STRATEGY_KEYS.reduce<CandidateBuckets>((buckets, strategy) => {
    buckets[strategy] = [];
    return buckets;
  }, {} as CandidateBuckets);
}

function estimate(channels: readonly ChannelSetupPlannedChannel[]): ChannelSetupEstimates {
  const estimates: ChannelSetupEstimates = {
    total: 0,
    playlists: 0,
    collections: 0,
    recentlyAdded: 0,
    genres: 0,
    studios: 0,
    actors: 0,
    decades: 0,
    directors: 0,
  };
  for (const channel of channels) {
    estimates.total += 1;
    estimates[channel.buildStrategy] += 1;
  }
  return estimates;
}

function seedFor(value: string): number {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}
