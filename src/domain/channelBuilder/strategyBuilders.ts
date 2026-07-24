import type {
  PlaybackMode,
  SortOrder,
} from '../channel/types.js';
import {
  CHANNEL_BUILDER_MAX_CANDIDATES,
  CHANNEL_BUILDER_STRATEGY_KEYS,
} from './constants.js';
import {
  channelBuilderIdentityOperations,
  type ChannelBuilderIdentityOperations,
} from './planIdentity.js';
import {
  projectChannelBuilderSafeDisplayString,
  type ChannelBuilderCandidateContentFilterPlan,
  type ChannelBuilderFacetSnapshot,
  type ChannelBuilderSafeSourceReference,
  type ChannelBuilderStrategyKey,
  type ChannelBuilderTagFacet,
  type NormalizedChannelSetupConfig,
} from './types.js';

export type GeneratedChannelBuilderCandidate = Readonly<{
  strategy: ChannelBuilderStrategyKey;
  displayName: string;
  sourceReference: ChannelBuilderSafeSourceReference;
  estimatedItemCount: number | null;
  playbackMode: PlaybackMode;
  shuffleSeed: number;
  contentFilterPlan: ChannelBuilderCandidateContentFilterPlan;
  sortOrder: SortOrder | null;
  blockSize: number | null;
  buildStrategy: ChannelBuilderStrategyKey | null;
  sourceLibraryId: string | null;
  sourceLibraryName: string | null;
  lineupReplicaIndex: 0 | 1 | 2 | 3 | null;
  isPlaybackModeVariant: boolean | null;
  meetsMinimumItems: boolean;
}>;

type CandidateInput = Omit<
  GeneratedChannelBuilderCandidate,
  'displayName' | 'shuffleSeed' | 'buildStrategy' | 'lineupReplicaIndex' | 'isPlaybackModeVariant'
> & {
  displayName: string;
  seedKey: string;
};

type GroupedTagFacet = Exclude<
  ChannelBuilderTagFacet,
  Readonly<{ family: 'year' }>
>;

function safeName(raw: string): string {
  return projectChannelBuilderSafeDisplayString(raw, {
    fallback: 'Untitled channel',
    maxUtf16Units: 160,
  });
}

function facetLeaf(
  facet: Readonly<{ facetId: string; sourceIdentity: string }>,
): ChannelBuilderSafeSourceReference {
  return {
    kind: 'facet',
    facetId: facet.facetId as never,
    sourceIdentity: facet.sourceIdentity as never,
  };
}

function mixedReference(
  identityOperations: ChannelBuilderIdentityOperations,
  mixMode: 'sequential' | 'interleave',
  sources: readonly ChannelBuilderSafeSourceReference[],
): ChannelBuilderSafeSourceReference {
  return {
    kind: 'mixed',
    sourceIdentity: identityOperations.createMixedSourceIdentity(
      mixMode,
      sources.map((source) => source.sourceIdentity),
    ),
    mixMode,
    sources,
  };
}

function compareText(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function compareCandidateFacet(
  left: Readonly<{ itemCount: number | null; sourceIdentity: string; facetId: string }>,
  right: Readonly<{ itemCount: number | null; sourceIdentity: string; facetId: string }>,
): number {
  const count = (right.itemCount ?? 0) - (left.itemCount ?? 0);
  if (count !== 0) return count;
  const source = compareText(left.sourceIdentity, right.sourceIdentity);
  return source !== 0 ? source : compareText(left.facetId, right.facetId);
}

function compareTagFacet(
  left: ChannelBuilderTagFacet,
  right: ChannelBuilderTagFacet,
): number {
  const count = (right.itemCount ?? 0) - (left.itemCount ?? 0);
  if (count !== 0) return count;
  if (left.family === 'year' && right.family === 'year') {
    const leftNullRank = left.yearValue === null ? 1 : 0;
    const rightNullRank = right.yearValue === null ? 1 : 0;
    if (leftNullRank !== rightNullRank) return leftNullRank - rightNullRank;
    if (left.yearValue !== right.yearValue) {
      return (left.yearValue ?? 0) - (right.yearValue ?? 0);
    }
  } else if (left.family !== 'year' && right.family !== 'year') {
    const group = compareText(
      left.semanticGroupIdentity,
      right.semanticGroupIdentity,
    );
    if (group !== 0) return group;
    if (left.family === 'director' && right.family === 'director') {
      const filter = compareText(
        left.contentFilterIdentity,
        right.contentFilterIdentity,
      );
      if (filter !== 0) return filter;
    }
  }
  const source = compareText(left.sourceIdentity, right.sourceIdentity);
  return source !== 0 ? source : compareText(left.facetId, right.facetId);
}

function isTvPeopleFacet(
  tag: ChannelBuilderTagFacet,
  library: Readonly<{ mediaType: 'movie' | 'show' }> | undefined,
): boolean {
  return (
    library?.mediaType === 'show' &&
    (tag.family === 'actor' || tag.family === 'director')
  );
}

function tagEstimatedItemCount(
  tag: ChannelBuilderTagFacet,
  library: Readonly<{ mediaType: 'movie' | 'show' }> | undefined,
): number | null {
  return isTvPeopleFacet(tag, library) ? tag.episodeCount : tag.itemCount;
}

function tagMeetsEligibility(
  tag: ChannelBuilderTagFacet,
  library: Readonly<{ mediaType: 'movie' | 'show' }> | undefined,
  minItems: number,
): boolean {
  if (isTvPeopleFacet(tag, library)) {
    return (
      tag.episodeCount !== null &&
      tag.episodeCount >= minItems &&
      tag.distinctSeriesCount !== null &&
      tag.distinctSeriesCount >= 3
    );
  }
  return tag.itemCount === null || tag.itemCount >= minItems;
}

function seedTuple(
  identityOperations: ChannelBuilderIdentityOperations,
  values: readonly unknown[],
): string {
  return identityOperations.canonicalJsonV1(values);
}

function createCandidate(
  identityOperations: ChannelBuilderIdentityOperations,
  input: CandidateInput,
  seed: string,
): GeneratedChannelBuilderCandidate {
  return {
    strategy: input.strategy,
    displayName: safeName(input.displayName),
    sourceReference: input.sourceReference,
    estimatedItemCount: input.estimatedItemCount,
    playbackMode: input.playbackMode,
    shuffleSeed: identityOperations.createDeterministicShuffleSeed(seed, input.seedKey),
    contentFilterPlan: input.contentFilterPlan,
    sortOrder: input.sortOrder,
    blockSize: input.blockSize,
    buildStrategy: input.strategy,
    sourceLibraryId: input.sourceLibraryId,
    sourceLibraryName:
      input.sourceLibraryName === null ? null : safeName(input.sourceLibraryName),
    lineupReplicaIndex: 0,
    isPlaybackModeVariant: false,
    meetsMinimumItems: input.meetsMinimumItems,
  };
}

function isSeriesSource(
  source: ChannelBuilderSafeSourceReference,
  seriesFacetIds: ReadonlySet<string>,
): boolean {
  if (source.kind === 'facet') return source.facetId !== null && seriesFacetIds.has(source.facetId);
  if (source.kind === 'manual') return false;
  return source.sources.length > 0 && source.sources.every((child) => isSeriesSource(child, seriesFacetIds));
}

function applySeriesOrdering(
  candidates: readonly GeneratedChannelBuilderCandidate[],
  config: NormalizedChannelSetupConfig,
  seriesFacetIds: ReadonlySet<string>,
): GeneratedChannelBuilderCandidate[] {
  if (config.seriesOrdering.basePlaybackMode === 'shuffle') return [...candidates];
  return candidates.map((candidate) => {
    if (
      candidate.playbackMode !== 'shuffle' ||
      !isSeriesSource(candidate.sourceReference, seriesFacetIds)
    ) {
      return candidate;
    }
    return {
      ...candidate,
      playbackMode: config.seriesOrdering.basePlaybackMode,
      blockSize:
        config.seriesOrdering.basePlaybackMode === 'block'
          ? config.seriesOrdering.baseBlockSize
          : null,
    };
  });
}

function expandCandidates(
  identityOperations: ChannelBuilderIdentityOperations,
  candidates: readonly GeneratedChannelBuilderCandidate[],
  config: NormalizedChannelSetupConfig,
  seriesFacetIds: ReadonlySet<string>,
  seed: string,
): GeneratedChannelBuilderCandidate[] {
  const expanded: GeneratedChannelBuilderCandidate[] = [];
  for (const candidate of candidates) {
    expanded.push(candidate);
    if (
      config.channelExpansion.addAlternateLineups &&
      candidate.playbackMode !== 'sequential' &&
      candidate.strategy !== 'actors' &&
      candidate.strategy !== 'directors'
    ) {
      for (
        let replicaIndex = 1;
        replicaIndex <= config.channelExpansion.alternateLineupCopies;
        replicaIndex += 1
      ) {
        expanded.push({
          ...candidate,
          displayName: safeName(`${candidate.displayName} (${replicaIndex + 1})`),
          shuffleSeed: identityOperations.createDeterministicShuffleSeed(
            seed,
            seedTuple(identityOperations, [
              candidate.sourceReference.sourceIdentity,
              'replica',
              replicaIndex,
            ]),
          ),
          lineupReplicaIndex: replicaIndex as 1 | 2 | 3,
        });
      }
    }
  }
  if (config.channelExpansion.variantType === 'none') return expanded;
  const withVariants = [...expanded];
  for (const candidate of expanded) {
    if (
      (config.channelExpansion.variantType === 'sequential' &&
        (candidate.lineupReplicaIndex ?? 0) > 0) ||
      !isSeriesSource(candidate.sourceReference, seriesFacetIds)
    ) {
      continue;
    }
    const playbackMode = config.channelExpansion.variantType;
    const blockSize =
      playbackMode === 'block' ? config.channelExpansion.variantBlockSize : null;
    if (candidate.playbackMode === playbackMode && candidate.blockSize === blockSize) continue;
    withVariants.push({
      ...candidate,
      displayName: safeName(
        `${candidate.displayName} • ${playbackMode === 'block' ? 'Block' : 'Sequential'}`,
      ),
      playbackMode,
      blockSize,
      shuffleSeed: identityOperations.createDeterministicShuffleSeed(
        seed,
        seedTuple(identityOperations, [
          candidate.sourceReference.sourceIdentity,
          'variant',
          playbackMode,
        ]),
      ),
      isPlaybackModeVariant: true,
    });
  }
  return withVariants;
}

type BuildStrategyCandidatesInput = Readonly<{
  normalizedConfig: NormalizedChannelSetupConfig;
  facetSnapshot: ChannelBuilderFacetSnapshot;
  seed: string;
}>;

export function buildStrategyCandidatesWithIdentityOperations(
  identityOperations: ChannelBuilderIdentityOperations,
  input: BuildStrategyCandidatesInput,
): readonly GeneratedChannelBuilderCandidate[] {
  const { normalizedConfig: config, facetSnapshot: snapshot, seed } = input;
  const libraries = snapshot.libraries.slice(0, config.selectedLibraryIds.length);
  const libraryByFacetId = new Map(libraries.map((library) => [library.facetId, library]));
  const seriesLibraryFacetIds = new Set(
    libraries
      .filter((library) => library.mediaType === 'show')
      .map((library) => library.facetId),
  );
  const seriesFacetIds = new Set<string>(seriesLibraryFacetIds);
  for (const facet of [
    ...snapshot.collections,
    ...snapshot.tags,
    ...snapshot.recentlyAdded,
  ]) {
    if (seriesLibraryFacetIds.has(facet.libraryFacetId)) {
      seriesFacetIds.add(facet.facetId);
    }
  }
  const buckets = Object.fromEntries(
    CHANNEL_BUILDER_STRATEGY_KEYS.map((strategy) => [
      strategy,
      [] as GeneratedChannelBuilderCandidate[],
    ]),
  ) as Record<ChannelBuilderStrategyKey, GeneratedChannelBuilderCandidate[]>;
  const excludedBuckets = Object.fromEntries(
    CHANNEL_BUILDER_STRATEGY_KEYS.map((strategy) => [
      strategy,
      [] as GeneratedChannelBuilderCandidate[],
    ]),
  ) as Record<ChannelBuilderStrategyKey, GeneratedChannelBuilderCandidate[]>;

  const push = (candidate: CandidateInput): void => {
    const target = candidate.meetsMinimumItems
      ? buckets[candidate.strategy]
      : excludedBuckets[candidate.strategy];
    if (target.length >= CHANNEL_BUILDER_MAX_CANDIDATES) return;
    target.push(createCandidate(identityOperations, candidate, seed));
  };

  if (config.strategyConfig.playlists.enabled) {
    for (const playlist of [...snapshot.playlists].sort((left, right) =>
      compareCandidateFacet(
        {
          itemCount: left.itemCount,
          sourceIdentity: left.sourceIdentity,
          facetId: left.facetId,
        },
        {
          itemCount: right.itemCount,
          sourceIdentity: right.sourceIdentity,
          facetId: right.facetId,
        },
      ),
    )) {
      push({
        strategy: 'playlists',
        displayName: playlist.title,
        seedKey: seedTuple(identityOperations, [
          'playlists',
          playlist.sourceIdentity,
          playlist.facetId,
        ]),
        sourceReference: facetLeaf(playlist),
        estimatedItemCount: playlist.itemCount,
        playbackMode: 'shuffle',
        contentFilterPlan: { kind: 'none', contentFilterIdentity: null },
        sortOrder: null,
        blockSize: null,
        sourceLibraryId: null,
        sourceLibraryName: null,
        meetsMinimumItems: playlist.itemCount >= config.minItemsPerChannel,
      });
    }
  }

  for (const library of libraries) {
    const sourceLibraryId =
      config.selectedLibraryIds[libraries.indexOf(library)] ?? config.selectedLibraryIds[0]!;
    if (config.strategyConfig.collections.enabled) {
      const collections = snapshot.collections
        .filter((collection) => collection.libraryFacetId === library.facetId)
        .sort((left, right) =>
          compareCandidateFacet(
            {
              itemCount: left.itemCount,
              sourceIdentity: left.sourceIdentity,
              facetId: left.facetId,
            },
            {
              itemCount: right.itemCount,
              sourceIdentity: right.sourceIdentity,
              facetId: right.facetId,
            },
          ),
        );
      for (const collection of collections) {
        push({
          strategy: 'collections',
          displayName: collection.title,
          seedKey: seedTuple(identityOperations, [
            'collections',
            library.sourceIdentity,
            collection.sourceIdentity,
            collection.facetId,
          ]),
          sourceReference: facetLeaf(collection),
          estimatedItemCount: collection.itemCount,
          playbackMode: 'shuffle',
          contentFilterPlan: { kind: 'none', contentFilterIdentity: null },
          sortOrder: null,
          blockSize: null,
          sourceLibraryId,
          sourceLibraryName: library.title,
          meetsMinimumItems: collection.itemCount >= config.minItemsPerChannel,
        });
      }
    }
    if (config.strategyConfig.recentlyAdded.enabled) {
      const recentlyAdded = snapshot.recentlyAdded.find(
        (facet) => facet.libraryFacetId === library.facetId,
      );
      if (recentlyAdded) {
        push({
          strategy: 'recentlyAdded',
          displayName: `${library.title} - Recently Added`,
          seedKey: seedTuple(identityOperations, [
            'recentlyAdded',
            library.sourceIdentity,
            recentlyAdded.sourceIdentity,
          ]),
          sourceReference: facetLeaf(recentlyAdded),
          estimatedItemCount: recentlyAdded.itemCount,
          playbackMode: 'sequential',
          contentFilterPlan: { kind: 'none', contentFilterIdentity: null },
          sortOrder: 'added_desc',
          blockSize: null,
          sourceLibraryId,
          sourceLibraryName: library.title,
          meetsMinimumItems: recentlyAdded.itemCount >= config.minItemsPerChannel,
        });
      }
    }
  }

  for (const strategy of ['genres', 'directors', 'studios', 'actors'] as const) {
    if (!config.strategyConfig[strategy].enabled) continue;
    const family = strategy.slice(0, -1) as 'genre' | 'director' | 'studio' | 'actor';
    const allTags = snapshot.tags.filter(
      (tag): tag is GroupedTagFacet => tag.family === family,
    );
    const crossLibrary =
      config.strategyConfig[strategy].scope === 'cross-library' ||
      ((strategy === 'studios' || strategy === 'actors') &&
        config.actorStudioCombineMode === 'combined');
    if (crossLibrary) {
      const groups = new Map<string, GroupedTagFacet[]>();
      for (const tag of allTags) {
        const library = libraryByFacetId.get(tag.libraryFacetId);
        if (
          isTvPeopleFacet(tag, library) &&
          !tagMeetsEligibility(tag, library, config.minItemsPerChannel)
        ) {
          continue;
        }
        const current = groups.get(tag.semanticGroupIdentity) ?? [];
        current.push(tag);
        groups.set(tag.semanticGroupIdentity, current);
      }
      const orderedGroups = [...groups.entries()]
        .map(([semanticGroupIdentity, group]) => ({
          semanticGroupIdentity,
          group,
          aggregateSortCount: group.reduce(
            (total, tag) =>
              total +
              (tagEstimatedItemCount(
                tag,
                libraryByFacetId.get(tag.libraryFacetId),
              ) ?? 0),
            0,
          ),
        }))
        .sort(
          (left, right) =>
            right.aggregateSortCount - left.aggregateSortCount ||
            compareText(
              left.semanticGroupIdentity,
              right.semanticGroupIdentity,
            ),
        );
      for (const {
        semanticGroupIdentity,
        group,
      } of orderedGroups) {
        const sorted = [...group].sort((left, right) => {
          const leftOrdinal =
            libraries.findIndex(
              (library) => library.facetId === left.libraryFacetId,
            );
          const rightOrdinal =
            libraries.findIndex(
              (library) => library.facetId === right.libraryFacetId,
            );
          return leftOrdinal - rightOrdinal || compareTagFacet(left, right);
        });
        const known = sorted.every(
          (tag) =>
            tagEstimatedItemCount(
              tag,
              libraryByFacetId.get(tag.libraryFacetId),
            ) !== null,
        );
        const count = known
          ? sorted.reduce(
              (total, tag) =>
                total +
                (tagEstimatedItemCount(
                  tag,
                  libraryByFacetId.get(tag.libraryFacetId),
                ) ?? 0),
              0,
            )
          : null;
        const sources = sorted.map(facetLeaf);
        const mixMode =
          config.strategyConfig[strategy].scope === 'cross-library'
            ? 'interleave'
            : 'sequential';
        push({
          strategy,
          displayName: sorted[0]?.displayTitle ?? 'Untitled channel',
          seedKey: seedTuple(identityOperations, [
            strategy,
            semanticGroupIdentity,
            sorted.map((tag) => tag.sourceIdentity),
            mixMode,
          ]),
          sourceReference: mixedReference(identityOperations, mixMode, sources),
          estimatedItemCount: count,
          playbackMode: 'shuffle',
          contentFilterPlan: { kind: 'none', contentFilterIdentity: null },
          sortOrder: null,
          blockSize: null,
          sourceLibraryId: null,
          sourceLibraryName: null,
          meetsMinimumItems: count === null || count >= config.minItemsPerChannel,
        });
      }
    } else {
      for (const tag of [...allTags].sort((left, right) => {
        const leftOrdinal = libraries.findIndex(
          (library) => library.facetId === left.libraryFacetId,
        );
        const rightOrdinal = libraries.findIndex(
          (library) => library.facetId === right.libraryFacetId,
        );
        return leftOrdinal - rightOrdinal || compareTagFacet(left, right);
      })) {
        const library = libraryByFacetId.get(tag.libraryFacetId);
        if (!library) continue;
        const sourceLibraryId =
          config.selectedLibraryIds[libraries.indexOf(library)] ??
          config.selectedLibraryIds[0]!;
        push({
          strategy,
          displayName:
            strategy === 'studios' || strategy === 'actors'
              ? `${tag.displayTitle} - ${library.title}`
              : `${library.title} - ${tag.displayTitle}`,
          seedKey:
            tag.family === 'director'
              ? seedTuple(identityOperations, [
                  'directors',
                  library.sourceIdentity,
                  tag.contentFilterIdentity,
                ])
              : seedTuple(identityOperations, [
                  strategy,
                  library.sourceIdentity,
                  tag.sourceIdentity,
                ]),
          sourceReference:
            strategy === 'directors' ? facetLeaf(library) : facetLeaf(tag),
          estimatedItemCount: tagEstimatedItemCount(tag, library),
          playbackMode: 'shuffle',
          contentFilterPlan:
            tag.family === 'director'
              ? {
                  kind: 'main-index-reference',
                  facetId: tag.facetId,
                  contentFilterIdentity: tag.contentFilterIdentity,
                }
              : { kind: 'none', contentFilterIdentity: null },
          sortOrder: null,
          blockSize: null,
          sourceLibraryId,
          sourceLibraryName: library.title,
          meetsMinimumItems: tagMeetsEligibility(
            tag,
            library,
            config.minItemsPerChannel,
          ),
        });
      }
    }
  }

  if (config.strategyConfig.decades.enabled) {
    for (const library of libraries) {
      const sourceLibraryId =
        config.selectedLibraryIds[libraries.indexOf(library)] ?? config.selectedLibraryIds[0]!;
      const decades = new Map<number, { count: number; unknown: boolean }>();
      for (const tag of snapshot.tags) {
        if (tag.family !== 'year' || tag.libraryFacetId !== library.facetId) continue;
        if (tag.yearValue === null) continue;
        const decade = Math.floor(tag.yearValue / 10) * 10;
        const entry = decades.get(decade) ?? { count: 0, unknown: false };
        if (tag.itemCount === null) entry.unknown = true;
        else entry.count += tag.itemCount;
        decades.set(decade, entry);
      }
      for (const [decade, summary] of [...decades.entries()].sort(
        ([left], [right]) => left - right,
      )) {
        const filters = [
          { field: 'year' as const, operator: 'gte' as const, value: decade },
          { field: 'year' as const, operator: 'lt' as const, value: decade + 10 },
        ];
        const contentFilterIdentity =
          identityOperations.createContentFilterIdentity({
            profileBinding: snapshot.context.profileBinding,
            serverBinding: snapshot.context.serverBinding,
            filters,
          });
        if (contentFilterIdentity === null) {
          throw new Error('Inline decade filter identity invariant failed.');
        }
        push({
          strategy: 'decades',
          displayName: `${library.title} - ${decade}s`,
          seedKey: seedTuple(identityOperations, [
            'decades',
            library.sourceIdentity,
            decade,
          ]),
          sourceReference: facetLeaf(library),
          estimatedItemCount: summary.unknown ? null : summary.count,
          playbackMode: 'shuffle',
          contentFilterPlan: {
            kind: 'inline',
            contentFilterIdentity,
            filters,
          },
          sortOrder: null,
          blockSize: null,
          sourceLibraryId,
          sourceLibraryName: library.title,
          meetsMinimumItems:
            summary.unknown || summary.count >= config.minItemsPerChannel,
        });
      }
    }
  }

  const orderedStrategies = [...CHANNEL_BUILDER_STRATEGY_KEYS].sort((left, right) => {
    const priority =
      config.strategyConfig[left].priority - config.strategyConfig[right].priority;
    return priority !== 0 ? priority : compareText(left, right);
  });
  const base = orderedStrategies.flatMap((strategy) => [
    ...buckets[strategy],
    ...excludedBuckets[strategy],
  ]);
  return expandCandidates(
    identityOperations,
    applySeriesOrdering(base, config, seriesFacetIds),
    config,
    seriesFacetIds,
    seed,
  ).slice(0, CHANNEL_BUILDER_MAX_CANDIDATES);
}

export function buildStrategyCandidates(
  input: BuildStrategyCandidatesInput,
): readonly GeneratedChannelBuilderCandidate[] {
  return buildStrategyCandidatesWithIdentityOperations(
    channelBuilderIdentityOperations,
    input,
  );
}
