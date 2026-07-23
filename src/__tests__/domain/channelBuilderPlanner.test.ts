import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  buildChannelSetupPlan,
  createContentFilterIdentity,
  createDefaultChannelSetupConfig,
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
  createSourceIdentity,
  createTagSemanticGroupIdentity,
  isValidChannelBuilderCandidateContentFilterPlan,
  type ChannelBuilderCandidateContentFilterPlan,
  type ChannelBuilderFacetSnapshot,
  type ChannelBuilderPlannerInput,
  type NormalizedChannelSetupConfig,
} from '../../domain/channelBuilder/index.js';

const profileBinding = createProfileBinding('profile-1');
const serverBinding = createServerBinding('server-1');
const librarySetBinding = createLibrarySetBinding([
  { libraryId: 'library-1', libraryUuid: 'uuid-1' },
]);
const librarySourceIdentity = createSourceIdentity({
  type: 'library',
  libraryId: 'library-1',
  libraryType: 'show',
  includeWatched: true,
});
const playlistSourceIdentity = createSourceIdentity({
  type: 'playlist',
  playlistKey: 'playlist-1',
  playlistName: 'Playlist',
});
const secondLibrarySourceIdentity = createSourceIdentity({
  type: 'library',
  libraryId: 'library-2',
  libraryType: 'movie',
  includeWatched: true,
});

function baseConfig(): NormalizedChannelSetupConfig {
  const result = createDefaultChannelSetupConfig({
    serverId: 'server-1',
    selectedLibraryIds: ['library-1'],
  });
  assert.equal(result.ok, true);
  if (!result.ok) throw new Error('fixture config failed');
  return result.config;
}

function onlyStrategy(
  config: NormalizedChannelSetupConfig,
  strategy: keyof NormalizedChannelSetupConfig['strategyConfig'],
): NormalizedChannelSetupConfig {
  return {
    ...config,
    strategyConfig: Object.fromEntries(
      Object.entries(config.strategyConfig).map(([key, value]) => [
        key,
        { ...value, enabled: key === strategy },
      ]),
    ) as NormalizedChannelSetupConfig['strategyConfig'],
  };
}

function configForLibraries(
  selectedLibraryIds: readonly string[],
): NormalizedChannelSetupConfig {
  const result = createDefaultChannelSetupConfig({
    serverId: 'server-1',
    selectedLibraryIds,
  });
  assert.equal(result.ok, true);
  if (!result.ok) throw new Error('fixture config failed');
  return result.config;
}

function facetSnapshot(): ChannelBuilderFacetSnapshot {
  const libraryFacetId = `library:${'1'.repeat(64)}` as const;
  const groupIdentity = (
    family: 'genre' | 'director' | 'studio' | 'actor',
    tagValue: string,
  ) =>
    createTagSemanticGroupIdentity({
      profileBinding,
      serverBinding,
      family,
      tagValue,
    });
  const directorFilterIdentity = createContentFilterIdentity({
    profileBinding,
    serverBinding,
    filters: [{ field: 'director', operator: 'eq', value: 'Director' }],
  });
  assert.notEqual(directorFilterIdentity, null);
  if (directorFilterIdentity === null) throw new Error('fixture identity failed');
  return {
    context: {
      contextEpoch: 4,
      profileBinding,
      serverBinding,
      librarySetBinding,
    },
    libraries: [
      {
        facetId: libraryFacetId,
        sourceIdentity: librarySourceIdentity,
        title: 'TV',
        mediaType: 'show',
        contentCount: 100,
      },
    ],
    playlists: [
      {
        facetId: `playlist:${'2'.repeat(64)}`,
        sourceIdentity: playlistSourceIdentity,
        title: 'Playlist',
        itemCount: 10,
        durationMs: 100,
      },
    ],
    collections: [
      {
        facetId: `collection:${'3'.repeat(64)}`,
        sourceIdentity: `source:${'3'.repeat(64)}`,
        libraryFacetId,
        title: 'Collection',
        itemCount: 12,
      },
    ],
    tags: [
      {
        facetId: `genre:${'4'.repeat(64)}`,
        sourceIdentity: `source:${'4'.repeat(64)}`,
        libraryFacetId,
        family: 'genre',
        displayTitle: 'Drama',
        itemCount: 10,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: groupIdentity('genre', 'Drama'),
        contentFilterIdentity: null,
        yearValue: null,
      },
      {
        facetId: `director:${'5'.repeat(64)}`,
        sourceIdentity: `source:${'5'.repeat(64)}`,
        libraryFacetId,
        family: 'director',
        displayTitle: 'Director',
        itemCount: 10,
        episodeCount: 10,
        distinctSeriesCount: 4,
        semanticGroupIdentity: groupIdentity('director', 'Director'),
        contentFilterIdentity: directorFilterIdentity,
        yearValue: null,
      },
      {
        facetId: `year:${'6'.repeat(64)}`,
        sourceIdentity: `source:${'6'.repeat(64)}`,
        libraryFacetId,
        family: 'year',
        displayTitle: '1994',
        itemCount: 10,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: null,
        contentFilterIdentity: null,
        yearValue: 1994,
      },
      {
        facetId: `studio:${'7'.repeat(64)}`,
        sourceIdentity: `source:${'7'.repeat(64)}`,
        libraryFacetId,
        family: 'studio',
        displayTitle: 'Studio',
        itemCount: 10,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: groupIdentity('studio', 'Studio'),
        contentFilterIdentity: null,
        yearValue: null,
      },
      {
        facetId: `actor:${'8'.repeat(64)}`,
        sourceIdentity: `source:${'8'.repeat(64)}`,
        libraryFacetId,
        family: 'actor',
        displayTitle: 'Actor',
        itemCount: 10,
        episodeCount: 10,
        distinctSeriesCount: 4,
        semanticGroupIdentity: groupIdentity('actor', 'Actor'),
        contentFilterIdentity: null,
        yearValue: null,
      },
    ],
    recentlyAdded: [
      {
        facetId: `recently-added:${'9'.repeat(64)}`,
        sourceIdentity: librarySourceIdentity,
        libraryFacetId,
        itemCount: 100,
      },
    ],
    aggregate: {
      status: 'ready',
      warningCodes: [],
      omittedMalformedCount: 0,
      omittedCappedCount: 0,
    },
  };
}

function input(
  config: NormalizedChannelSetupConfig,
  existingLineup: ChannelBuilderPlannerInput['existingLineup'] = [],
): ChannelBuilderPlannerInput {
  return {
    normalizedConfig: config,
    facetSnapshot: facetSnapshot(),
    existingLineup,
    clock: { nowMs: 123 },
    seed: 'seed-1',
  };
}

function twoLibraryGenreSnapshot(
  displayTitles: readonly [string, string, string],
): ChannelBuilderFacetSnapshot {
  const firstLibraryFacetId = `library:${'1'.repeat(64)}` as const;
  const secondLibraryFacetId = `library:${'a'.repeat(64)}` as const;
  const sharedGroup = createTagSemanticGroupIdentity({
    profileBinding,
    serverBinding,
    family: 'genre',
    tagValue: 'shared-semantic-value',
  });
  const distinctGroup = createTagSemanticGroupIdentity({
    profileBinding,
    serverBinding,
    family: 'genre',
    tagValue: 'distinct-semantic-value',
  });
  return {
    ...facetSnapshot(),
    context: {
      contextEpoch: 4,
      profileBinding,
      serverBinding,
      librarySetBinding: createLibrarySetBinding([
        { libraryId: 'library-1', libraryUuid: 'uuid-1' },
        { libraryId: 'library-2', libraryUuid: 'uuid-2' },
      ]),
    },
    libraries: [
      {
        facetId: firstLibraryFacetId,
        sourceIdentity: librarySourceIdentity,
        title: 'First library',
        mediaType: 'show',
        contentCount: 100,
      },
      {
        facetId: secondLibraryFacetId,
        sourceIdentity: secondLibrarySourceIdentity,
        title: 'Second library',
        mediaType: 'movie',
        contentCount: 100,
      },
    ],
    playlists: [],
    collections: [],
    tags: [
      {
        facetId: `genre:${'b'.repeat(64)}`,
        sourceIdentity: `source:${'b'.repeat(64)}`,
        libraryFacetId: firstLibraryFacetId,
        family: 'genre',
        displayTitle: displayTitles[0],
        itemCount: 10,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: sharedGroup,
        contentFilterIdentity: null,
        yearValue: null,
      },
      {
        facetId: `genre:${'c'.repeat(64)}`,
        sourceIdentity: `source:${'c'.repeat(64)}`,
        libraryFacetId: secondLibraryFacetId,
        family: 'genre',
        displayTitle: displayTitles[1],
        itemCount: 10,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: sharedGroup,
        contentFilterIdentity: null,
        yearValue: null,
      },
      {
        facetId: `genre:${'d'.repeat(64)}`,
        sourceIdentity: `source:${'d'.repeat(64)}`,
        libraryFacetId: firstLibraryFacetId,
        family: 'genre',
        displayTitle: displayTitles[2],
        itemCount: 10,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: distinctGroup,
        contentFilterIdentity: null,
        yearValue: null,
      },
    ],
    recentlyAdded: [],
  };
}

describe('channel builder planner', () => {
  it('is byte-stable, explicit-input-only, and covers all audited strategy families', () => {
    const first = buildChannelSetupPlan(input(baseConfig()));
    const second = buildChannelSetupPlan(input(baseConfig()));
    assert.deepEqual(second, first);
    assert.equal(first.status, 'ready');
    assert.match(first.planIdentity, /^plan-identity:[a-f0-9]{64}$/u);
    assert.deepEqual(
      [...new Set(first.candidateDrafts.map((candidate) => candidate.strategy))].sort(),
      [
        'actors',
        'collections',
        'decades',
        'directors',
        'genres',
        'playlists',
        'recentlyAdded',
        'studios',
      ],
    );
    assert.equal(
      first.candidateDrafts.every(
        (candidate) =>
          candidate.sourceReference.kind !== 'manual' &&
          (candidate.sourceReference.kind !== 'mixed' ||
            candidate.sourceReference.sources.every((source) => source.kind !== 'manual')),
      ),
      true,
    );
    const changedClock = buildChannelSetupPlan({
      ...input(baseConfig()),
      clock: { nowMs: 124 },
    });
    assert.notEqual(changedClock.planIdentity, first.planIdentity);
  });

  it('produces the sole PLAN_EMPTY blocked output for disabled and skipped plans', () => {
    const disabledConfig = {
      ...baseConfig(),
      strategyConfig: Object.fromEntries(
        Object.entries(baseConfig().strategyConfig).map(([key, value]) => [
          key,
          { ...value, enabled: false },
        ]),
      ) as NormalizedChannelSetupConfig['strategyConfig'],
    };
    const disabled = buildChannelSetupPlan(input(disabledConfig));
    assert.equal(disabled.status, 'blocked');
    assert.deepEqual(disabled.applyCandidateIds, []);
    assert.deepEqual(disabled.retainedMaterializationCandidateIds, []);
    assert.deepEqual(disabled.warnings, [
      {
        code: 'PLAN_EMPTY',
        phase: 'planning',
        strategy: null,
        affectedCount: 0,
      },
    ]);

    const skipped = buildChannelSetupPlan(
      input({
        ...onlyStrategy(baseConfig(), 'playlists'),
        minItemsPerChannel: 500,
      }),
    );
    assert.equal(skipped.status, 'blocked');
    assert.deepEqual(skipped.warnings, disabled.warnings);
    assert.equal(skipped.candidateLedger[0]?.exclusion, 'minimum-items');
  });

  it('keeps hostile persisted IDs/names raw in main-only ledgers and projects diff samples', () => {
    const hostileId = `id\u0000Authorization=secret<${'x'.repeat(520)}`;
    const hostileName = `Authorization: Bearer secret <${'y'.repeat(520)}`;
    const result = buildChannelSetupPlan(
      input(onlyStrategy(baseConfig(), 'playlists'), [
        {
          id: hostileId,
          number: 1,
          name: hostileName,
          sourceDisposition: 'retained-unmatchable',
          sourceReference: null,
          playbackMode: 'shuffle',
          contentFilterIdentity: null,
          builderProvenance: null,
        },
      ]),
    );
    assert.equal(result.existingLedger[0]?.existingChannelId, hostileId);
    assert.equal(result.existingLedger[0]?.disposition, 'replace-remove');
    assert.deepEqual(result.diff.samples.removed, ['[redacted]']);
    assert.deepEqual(
      result.warnings.find((warning) => warning.code === 'EXISTING_SOURCE_UNMATCHABLE'),
      {
        code: 'EXISTING_SOURCE_UNMATCHABLE',
        phase: 'planning',
        strategy: null,
        affectedCount: 1,
      },
    );
  });

  it('matches only valid same-lineage provenance and materializes merge matches', () => {
    const replace = buildChannelSetupPlan(input(onlyStrategy(baseConfig(), 'playlists')));
    const candidate = replace.candidateDrafts[0]!;
    const appendConfig = {
      ...onlyStrategy(baseConfig(), 'playlists'),
      buildMode: 'merge' as const,
    };
    const matched = buildChannelSetupPlan(
      input(appendConfig, [
        {
          id: 'existing-1',
          number: 1,
          name: 'Existing',
          sourceDisposition: 'matchable',
          sourceReference: {
            kind: 'facet',
            facetId: null,
            sourceIdentity: candidate.sourceReference.sourceIdentity,
          },
          playbackMode: candidate.playbackMode,
          contentFilterIdentity:
            candidate.contentFilterPlan.contentFilterIdentity,
          builderProvenance: {
            schemaVersion: 1,
            identityVersion: 1,
            ...candidate.origin,
            sourceIdentity: candidate.sourceReference.sourceIdentity,
            candidateIdentity: candidate.candidateIdentity,
          },
        },
      ]),
    );
    assert.equal(matched.candidateLedger[0]?.classification, 'matched-retained');
    assert.equal(matched.candidateLedger[0]?.retainedChannelId, 'existing-1');
    assert.deepEqual(matched.applyCandidateIds, []);
    assert.deepEqual(matched.retainedMaterializationCandidateIds, [
      candidate.candidateId,
    ]);
    assert.equal(matched.existingLedger.length, 1);
    assert.equal(matched.existingLedger[0]?.disposition, 'matched-retained');
  });

  it('consumes duplicate byte-equal candidates one-to-one in occurrence order', () => {
    const duplicateSnapshot = facetSnapshot();
    const duplicatePlaylist = duplicateSnapshot.playlists[0]!;
    const replace = buildChannelSetupPlan({
      ...input(onlyStrategy(baseConfig(), 'playlists')),
      facetSnapshot: {
        ...duplicateSnapshot,
        playlists: [
          duplicatePlaylist,
          {
            ...duplicatePlaylist,
            facetId: `playlist:${'f'.repeat(64)}`,
          },
        ],
      },
    });
    const [first, second] = replace.candidateDrafts;
    assert.ok(first);
    assert.ok(second);
    assert.equal(first.candidateIdentity, second.candidateIdentity);
    assert.notEqual(first.candidateId, second.candidateId);

    const existingLineup = [first, second].map((candidate, index) => ({
      id: `existing-${index + 1}`,
      number: index + 1,
      name: `Existing ${index + 1}`,
      sourceDisposition: 'matchable' as const,
      sourceReference: {
        kind: 'facet' as const,
        facetId: null,
        sourceIdentity: candidate.sourceReference.sourceIdentity,
      },
      playbackMode: candidate.playbackMode,
      contentFilterIdentity: candidate.contentFilterPlan.contentFilterIdentity,
      builderProvenance: {
        schemaVersion: 1 as const,
        identityVersion: 1 as const,
        ...candidate.origin,
        sourceIdentity: candidate.sourceReference.sourceIdentity,
        candidateIdentity: candidate.candidateIdentity,
      },
    }));
    const merge = buildChannelSetupPlan({
      normalizedConfig: {
        ...onlyStrategy(baseConfig(), 'playlists'),
        buildMode: 'merge',
      },
      facetSnapshot: {
        ...duplicateSnapshot,
        playlists: [
          duplicatePlaylist,
          {
            ...duplicatePlaylist,
            facetId: `playlist:${'f'.repeat(64)}`,
          },
        ],
      },
      existingLineup,
      clock: { nowMs: 123 },
      seed: 'seed-1',
    });
    assert.deepEqual(
      merge.candidateLedger.map((entry) => entry.retainedChannelId),
      ['existing-1', 'existing-2'],
    );
    assert.deepEqual(
      merge.existingLedger.map((entry) => entry.matchedCandidateId),
      merge.candidateDrafts.map((candidate) => candidate.candidateId),
    );
  });

  it('applies exact configured capacity and expansion controls', () => {
    const snapshot = {
      ...facetSnapshot(),
      playlists: Array.from({ length: 500 }, (_, index) => ({
        facetId: `playlist:${index.toString(16).padStart(64, '0')}` as const,
        sourceIdentity: `source:${index.toString(16).padStart(64, '0')}` as const,
        title: `Playlist ${index}`,
        itemCount: 1,
        durationMs: 1,
      })),
    };
    const config = {
      ...onlyStrategy(baseConfig(), 'playlists'),
      maxChannels: 500,
      minItemsPerChannel: 1,
      channelExpansion: {
        addAlternateLineups: true,
        alternateLineupCopies: 1,
        variantType: 'none' as const,
        variantBlockSize: 3,
      },
    };
    const plan = buildChannelSetupPlan({
      ...input(config),
      facetSnapshot: snapshot,
    });
    assert.equal(plan.applyCandidateIds.length, 500);
    assert.equal(plan.capacity.effectiveMaxChannels, 500);
    assert.equal(plan.reachedCap, true);
    assert.equal(
      plan.candidateLedger.filter(
        (entry) => entry.exclusion === 'configured-capacity',
      ).length,
      500,
    );
  });

  it('emits base replica 0 and all three configured alternate copies', () => {
    const config = {
      ...onlyStrategy(baseConfig(), 'collections'),
      channelExpansion: {
        addAlternateLineups: true,
        alternateLineupCopies: 3,
        variantType: 'none' as const,
        variantBlockSize: 3,
      },
    };
    const plan = buildChannelSetupPlan(input(config));
    assert.deepEqual(
      plan.candidateDrafts.map((candidate) => candidate.lineupReplicaIndex),
      [0, 1, 2, 3],
    );
    assert.deepEqual(
      plan.candidateDrafts.map((candidate) => candidate.displayName),
      ['Collection', 'Collection (2)', 'Collection (3)', 'Collection (4)'],
    );
  });

  it('groups cross-library tags only by semantic identity and orders mixed members semantically', () => {
    const config = {
      ...onlyStrategy(
        configForLibraries(['library-1', 'library-2']),
        'genres',
      ),
      strategyConfig: {
        ...onlyStrategy(
          configForLibraries(['library-1', 'library-2']),
          'genres',
        ).strategyConfig,
        genres: {
          enabled: true,
          priority: 4,
          scope: 'cross-library' as const,
        },
      },
    };
    const plan = buildChannelSetupPlan({
      normalizedConfig: config,
      facetSnapshot: twoLibraryGenreSnapshot([
        'First presentation',
        'Different presentation',
        'First presentation',
      ]),
      existingLineup: [],
      clock: { nowMs: 123 },
      seed: 'seed-1',
    });
    assert.equal(plan.candidateDrafts.length, 2);
    assert.equal(
      plan.candidateDrafts.every(
        (candidate) => candidate.sourceReference.kind === 'mixed',
      ),
      true,
    );
    const grouped = plan.candidateDrafts.find(
      (candidate) =>
        candidate.sourceReference.kind === 'mixed' &&
        candidate.sourceReference.sources.length === 2,
    );
    assert.ok(grouped);
    assert.equal(grouped.displayName, 'First presentation');
    assert.deepEqual(
      grouped.sourceReference.kind === 'mixed'
        ? grouped.sourceReference.sources.map((source) => source.sourceIdentity)
        : [],
      [`source:${'b'.repeat(64)}`, `source:${'c'.repeat(64)}`],
    );
    assert.equal(
      plan.candidateDrafts.filter(
        (candidate) => candidate.displayName === 'First presentation',
      ).length,
      2,
    );
  });

  it('keeps cap survivors, seeds, and candidate identities independent of display projection', () => {
    const config = {
      ...onlyStrategy(
        configForLibraries(['library-1', 'library-2']),
        'genres',
      ),
      maxChannels: 1,
    };
    const variants = [
      ['Baseline one', 'Baseline two', 'Baseline three'],
      ['[redacted]', '[redacted]', '[redacted]'],
      ['x'.repeat(160), 'x'.repeat(160), 'x'.repeat(160)],
      ['Diverged three', 'Diverged one', 'Diverged two'],
    ] as const;
    const plans = variants.map((displayTitles) =>
      buildChannelSetupPlan({
        normalizedConfig: config,
        facetSnapshot: twoLibraryGenreSnapshot(displayTitles),
        existingLineup: [],
        clock: { nowMs: 123 },
        seed: 'seed-1',
      }),
    );
    const semanticProjection = (plan: (typeof plans)[number]) => ({
      drafts: plan.candidateDrafts.map((candidate) => ({
        candidateId: candidate.candidateId,
        candidateIdentity: candidate.candidateIdentity,
        sourceReference: candidate.sourceReference,
        shuffleSeed: candidate.shuffleSeed,
      })),
      applyCandidateIds: plan.applyCandidateIds,
      ledger: plan.candidateLedger.map((entry) => ({
        candidateId: entry.candidateId,
        sourceIdentity: entry.sourceIdentity,
        classification: entry.classification,
        exclusion: entry.exclusion,
      })),
    });
    for (const plan of plans.slice(1)) {
      assert.deepEqual(semanticProjection(plan), semanticProjection(plans[0]!));
    }
    assert.equal(plans[0]!.applyCandidateIds.length, 1);
    assert.equal(plans[0]!.reachedCap, true);
  });

  it('keeps director raw filters out of planner DTOs and derives decades only from yearValue', () => {
    const rawDirector = 'raw-director-semantic-sentinel';
    const directorFilterIdentity = createContentFilterIdentity({
      profileBinding,
      serverBinding,
      filters: [{ field: 'director', operator: 'eq', value: rawDirector }],
    });
    assert.notEqual(directorFilterIdentity, null);
    if (directorFilterIdentity === null) throw new Error('fixture identity failed');
    const base = facetSnapshot();
    const directorSnapshot: ChannelBuilderFacetSnapshot = {
      ...base,
      tags: [
        {
          ...base.tags.find((tag) => tag.family === 'director')!,
          displayTitle: 'Safe filmmaker label',
          semanticGroupIdentity: createTagSemanticGroupIdentity({
            profileBinding,
            serverBinding,
            family: 'director',
            tagValue: rawDirector,
          }),
          contentFilterIdentity: directorFilterIdentity,
        },
      ],
    };
    const directorPlan = buildChannelSetupPlan({
      ...input(onlyStrategy(baseConfig(), 'directors')),
      facetSnapshot: directorSnapshot,
    });
    const director = directorPlan.candidateDrafts[0]!;
    assert.deepEqual(director.sourceReference, {
      kind: 'facet',
      facetId: base.libraries[0]!.facetId,
      sourceIdentity: base.libraries[0]!.sourceIdentity,
    });
    assert.deepEqual(director.contentFilterPlan, {
      kind: 'main-index-reference',
      contentFilterIdentity: directorFilterIdentity,
      facetId: directorSnapshot.tags[0]!.facetId,
    });
    assert.equal(JSON.stringify(directorPlan).includes(rawDirector), false);

    const years = base.tags.filter((tag) => tag.family === 'year');
    const yearSnapshot: ChannelBuilderFacetSnapshot = {
      ...base,
      tags: [
        { ...years[0]!, displayTitle: 'not-a-year', yearValue: 1994 },
        {
          ...years[0]!,
          facetId: `year:${'e'.repeat(64)}`,
          sourceIdentity: `source:${'e'.repeat(64)}`,
          displayTitle: '1987',
          yearValue: null,
        },
      ],
    };
    const decadePlan = buildChannelSetupPlan({
      ...input(onlyStrategy(baseConfig(), 'decades')),
      facetSnapshot: yearSnapshot,
    });
    assert.equal(decadePlan.candidateDrafts.length, 1);
    assert.equal(decadePlan.candidateDrafts[0]!.displayName, 'TV - 1990s');
    assert.deepEqual(decadePlan.candidateDrafts[0]!.contentFilterPlan.kind === 'inline'
      ? decadePlan.candidateDrafts[0]!.contentFilterPlan.filters
      : null, [
      { field: 'year', operator: 'gte', value: 1990 },
      { field: 'year', operator: 'lt', value: 2000 },
    ]);
  });

  it('enforces TV actor and director episode and distinct-series breadth', () => {
    const base = facetSnapshot();
    for (const strategy of ['actors', 'directors'] as const) {
      const family = strategy === 'actors' ? 'actor' : 'director';
      const original = base.tags.find((tag) => tag.family === family)!;
      const broad = {
        ...original,
        facetId: `${family}:${'a'.repeat(64)}`,
        sourceIdentity: `source:${'a'.repeat(64)}`,
        displayTitle: `Broad ${family}`,
        itemCount: 100,
        episodeCount: 5,
        distinctSeriesCount: 3,
      } as typeof original;
      const thin = {
        ...original,
        facetId: `${family}:${'b'.repeat(64)}`,
        sourceIdentity: `source:${'b'.repeat(64)}`,
        displayTitle: `Thin ${family}`,
        itemCount: 100,
        episodeCount: 100,
        distinctSeriesCount: 2,
        semanticGroupIdentity: createTagSemanticGroupIdentity({
          profileBinding,
          serverBinding,
          family,
          tagValue: `thin-${family}`,
        }),
        ...(family === 'director'
          ? {
              contentFilterIdentity: createContentFilterIdentity({
                profileBinding,
                serverBinding,
                filters: [
                  {
                    field: 'director',
                    operator: 'eq',
                    value: 'thin-director',
                  },
                ],
              })!,
            }
          : {}),
      } as typeof original;
      const plan = buildChannelSetupPlan({
        ...input(onlyStrategy(baseConfig(), strategy)),
        facetSnapshot: { ...base, tags: [broad, thin] },
      });
      const broadName =
        strategy === 'actors'
          ? `Broad ${family} - TV`
          : `TV - Broad ${family}`;
      const thinName =
        strategy === 'actors'
          ? `Thin ${family} - TV`
          : `TV - Thin ${family}`;
      const broadOrdinal = plan.candidateDrafts.findIndex(
        (candidate) => candidate.displayName === broadName,
      );
      const thinOrdinal = plan.candidateDrafts.findIndex(
        (candidate) => candidate.displayName === thinName,
      );
      assert.notEqual(broadOrdinal, -1);
      assert.notEqual(thinOrdinal, -1);
      assert.equal(
        plan.candidateDrafts[broadOrdinal]!.estimatedItemCount,
        5,
      );
      assert.equal(
        plan.candidateDrafts[thinOrdinal]!.estimatedItemCount,
        100,
      );
      assert.deepEqual(
        [broadOrdinal, thinOrdinal].map((ordinal) => ({
          classification: plan.candidateLedger[ordinal]!.classification,
          exclusion: plan.candidateLedger[ordinal]!.exclusion,
        })),
        [
          { classification: 'new-apply', exclusion: null },
          { classification: 'excluded', exclusion: 'minimum-items' },
        ],
      );
      assert.deepEqual(
        plan.candidateLedger.map((entry) => ({
          classification: entry.classification,
          exclusion: entry.exclusion,
        })).filter((entry) => entry.exclusion === 'minimum-items'),
        [{ classification: 'excluded', exclusion: 'minimum-items' }],
      );
      assert.deepEqual(
        plan.warnings.find(
          (warning) =>
            warning.code === 'MIN_ITEMS_SKIPPED' &&
            warning.strategy === strategy,
        ),
        {
          code: 'MIN_ITEMS_SKIPPED',
          phase: 'planning',
          strategy,
          affectedCount: 1,
        },
      );
    }
  });

  it('filters thin TV people before cross-library aggregation and blocks all-thin groups', () => {
    const snapshot = twoLibraryGenreSnapshot(['Thin', 'Broad', 'Unused']);
    const sharedGroup = createTagSemanticGroupIdentity({
      profileBinding,
      serverBinding,
      family: 'actor',
      tagValue: 'shared-actor',
    });
    const actorTags: ChannelBuilderFacetSnapshot['tags'] = [
      {
        facetId: `actor:${'b'.repeat(64)}`,
        sourceIdentity: `source:${'b'.repeat(64)}`,
        libraryFacetId: snapshot.libraries[0]!.facetId,
        family: 'actor',
        displayTitle: 'Thin',
        itemCount: 100,
        episodeCount: 100,
        distinctSeriesCount: 2,
        semanticGroupIdentity: sharedGroup,
        contentFilterIdentity: null,
        yearValue: null,
      },
      {
        facetId: `actor:${'c'.repeat(64)}`,
        sourceIdentity: `source:${'c'.repeat(64)}`,
        libraryFacetId: snapshot.libraries[1]!.facetId,
        family: 'actor',
        displayTitle: 'Broad',
        itemCount: 5,
        episodeCount: null,
        distinctSeriesCount: null,
        semanticGroupIdentity: sharedGroup,
        contentFilterIdentity: null,
        yearValue: null,
      },
    ];
    const config = {
      ...onlyStrategy(
        configForLibraries(['library-1', 'library-2']),
        'actors',
      ),
      strategyConfig: {
        ...onlyStrategy(
          configForLibraries(['library-1', 'library-2']),
          'actors',
        ).strategyConfig,
        actors: {
          enabled: true,
          priority: 6,
          scope: 'cross-library' as const,
        },
      },
    };
    const aggregatedPlan = buildChannelSetupPlan({
      normalizedConfig: config,
      facetSnapshot: {
        ...snapshot,
        libraries: snapshot.libraries.map((library) => ({
          ...library,
          mediaType: 'show' as const,
        })),
        tags: actorTags.map((tag, index) => ({
          ...tag,
          episodeCount: index === 0 ? 6 : 5,
          distinctSeriesCount: 3,
        })),
      },
      existingLineup: [],
      clock: { nowMs: 123 },
      seed: 'seed-1',
    });
    assert.equal(aggregatedPlan.candidateDrafts[0]!.estimatedItemCount, 11);
    assert.equal(
      aggregatedPlan.candidateDrafts[0]!.sourceReference.kind === 'mixed'
        ? aggregatedPlan.candidateDrafts[0]!.sourceReference.sources.length
        : 0,
      2,
    );
    const broadPlan = buildChannelSetupPlan({
      normalizedConfig: config,
      facetSnapshot: { ...snapshot, tags: actorTags },
      existingLineup: [],
      clock: { nowMs: 123 },
      seed: 'seed-1',
    });
    assert.equal(broadPlan.candidateDrafts.length, 1);
    assert.equal(broadPlan.candidateDrafts[0]!.estimatedItemCount, 5);
    assert.deepEqual(
      broadPlan.candidateDrafts[0]!.sourceReference.kind === 'mixed'
        ? broadPlan.candidateDrafts[0]!.sourceReference.sources.map(
            (source) => source.sourceIdentity,
          )
        : [],
      [`source:${'c'.repeat(64)}`],
    );

    const allThin = buildChannelSetupPlan({
      normalizedConfig: config,
      facetSnapshot: {
        ...snapshot,
        libraries: snapshot.libraries.map((library) => ({
          ...library,
          mediaType: 'show' as const,
        })),
        tags: actorTags.map((tag) => ({
          ...tag,
          episodeCount: 100,
          distinctSeriesCount: 2,
        })),
      },
      existingLineup: [],
      clock: { nowMs: 123 },
      seed: 'seed-1',
    });
    assert.equal(allThin.status, 'blocked');
    assert.deepEqual(allThin.candidateDrafts, []);
    assert.deepEqual(allThin.applyCandidateIds, []);
    assert.deepEqual(allThin.warnings, [
      {
        code: 'PLAN_EMPTY',
        phase: 'planning',
        strategy: null,
        affectedCount: 0,
      },
    ]);
  });

  it('never matches a minimum-item draft and keeps both ledgers reciprocal', () => {
    const lowConfig = {
      ...onlyStrategy(baseConfig(), 'playlists'),
      minItemsPerChannel: 11,
      buildMode: 'merge' as const,
    };
    const excluded = buildChannelSetupPlan(input(lowConfig)).candidateDrafts[0]!;
    const plan = buildChannelSetupPlan(
      input(lowConfig, [
        {
          id: 'existing-low',
          number: 1,
          name: 'Existing low',
          sourceDisposition: 'matchable',
          sourceReference: excluded.sourceReference,
          playbackMode: excluded.playbackMode,
          contentFilterIdentity:
            excluded.contentFilterPlan.contentFilterIdentity,
          builderProvenance: {
            schemaVersion: 1,
            identityVersion: 1,
            ...excluded.origin,
            sourceIdentity: excluded.sourceReference.sourceIdentity,
            candidateIdentity: excluded.candidateIdentity,
          },
        },
      ]),
    );
    assert.equal(plan.status, 'blocked');
    assert.deepEqual(plan.applyCandidateIds, []);
    assert.deepEqual(plan.retainedMaterializationCandidateIds, []);
    assert.equal(plan.candidateLedger[0]?.classification, 'excluded');
    assert.equal(plan.candidateLedger[0]?.retainedChannelId, null);
    assert.deepEqual(plan.existingLedger, [
      {
        ordinal: 0,
        existingChannelId: 'existing-low',
        disposition: 'unmatched-retained',
        matchedCandidateId: null,
      },
    ]);
    assert.deepEqual(plan.warnings, [
      {
        code: 'PLAN_EMPTY',
        phase: 'planning',
        strategy: null,
        affectedCount: 0,
      },
    ]);
  });

  it('accepts only numeric inline content-filter plans at type and runtime boundaries', () => {
    const numericIdentity = createContentFilterIdentity({
      profileBinding,
      serverBinding,
      filters: [{ field: 'year', operator: 'gte', value: 1990 }],
    });
    assert.notEqual(numericIdentity, null);
    if (numericIdentity === null) throw new Error('fixture identity failed');
    const numericPlan: ChannelBuilderCandidateContentFilterPlan = {
      kind: 'inline',
      contentFilterIdentity: numericIdentity,
      filters: [{ field: 'year', operator: 'gte', value: 1990 }],
    };
    assert.equal(
      isValidChannelBuilderCandidateContentFilterPlan(
        numericPlan,
        facetSnapshot(),
      ),
      true,
    );
    const stringPlan: ChannelBuilderCandidateContentFilterPlan = {
      kind: 'inline',
      contentFilterIdentity: numericIdentity,
      filters: [
        {
          field: 'year',
          operator: 'gte',
          // @ts-expect-error planner inline filters are numeric-only
          value: '1990',
        },
      ],
    };
    assert.equal(
      isValidChannelBuilderCandidateContentFilterPlan(
        stringPlan as never,
        facetSnapshot(),
      ),
      false,
    );
    assert.equal(
      isValidChannelBuilderCandidateContentFilterPlan(
        {
          kind: 'inline',
          contentFilterIdentity: numericIdentity,
          filters: [{ field: 'watched', operator: 'eq', value: true }],
        } as never,
        facetSnapshot(),
      ),
      false,
    );
  });
});
