import test from 'node:test';
import assert from 'node:assert/strict';

import {
  allocateChannelSetupNumbers,
  buildChannelSetupPlan,
  createChannelSetupIdentity,
  diffChannelSetupPlan,
  mergeChannelSetupMatch,
  normalizeChannelSetupConfig,
  type ChannelSetupConfigDraft,
  type ChannelSetupFacetSnapshot,
  type ChannelSetupNamedFacet,
  type ChannelSetupPlannedChannel,
  type ChannelSetupStrategyKey,
} from '../../domain/channel/setupPlanning/index.js';
import type { ChannelConfig } from '../../domain/channel/types.js';

test('setup config normalization freezes defaults, bounds, scopes, and selected library identity', () => {
  const normalized = normalizeChannelSetupConfig({
    selectedLibraryIds: [' shows ', '', 'movies', 'shows', 'movies'],
    maxChannels: 999,
    minItemsPerChannel: 0.9,
    buildMode: 'merge',
    actorStudioCombineMode: 'combined',
    strategyConfig: {
      playlists: { enabled: false, priority: Number.NaN, scope: 'cross-library' },
      genres: { priority: 0.9, scope: 'cross-library' },
      collections: { scope: 'cross-library' },
    },
    channelExpansion: { addAlternateLineups: true, alternateLineupCopies: 8, variantType: 'block', variantBlockSize: 99 },
    seriesOrdering: { basePlaybackMode: 'block', baseBlockSize: 1 },
  });

  assert.deepEqual(normalized.selectedLibraryIds, ['shows', 'movies']);
  assert.equal(normalized.maxChannels, 500);
  assert.equal(normalized.minItemsPerChannel, 1);
  assert.equal(normalized.strategyConfig.playlists.enabled, false);
  assert.equal(normalized.strategyConfig.playlists.priority, 1);
  assert.equal(normalized.strategyConfig.playlists.scope, 'per-library');
  assert.equal(normalized.strategyConfig.genres.priority, 1);
  assert.equal(normalized.strategyConfig.genres.scope, 'cross-library');
  assert.equal(normalized.strategyConfig.collections.scope, 'per-library');
  assert.equal(normalized.strategyConfig.directors.enabled, true);
  assert.deepEqual(normalized.channelExpansion, {
    addAlternateLineups: true, alternateLineupCopies: 3, variantType: 'block', variantBlockSize: 5,
  });
  assert.deepEqual(normalized.seriesOrdering, { basePlaybackMode: 'block', baseBlockSize: 2 });

  const defaults = normalizeChannelSetupConfig({
    selectedLibraryIds: [], maxChannels: Number.NaN, minItemsPerChannel: Number.NaN,
    buildMode: 'replace', actorStudioCombineMode: 'separate', strategyConfig: {},
    channelExpansion: { alternateLineupCopies: Number.NaN },
  });
  assert.equal(defaults.maxChannels, 200);
  assert.equal(defaults.minItemsPerChannel, 5);
  assert.equal(defaults.channelExpansion.alternateLineupCopies, 1);
  assert.equal(defaults.channelExpansion.variantType, 'none');
  assert.equal(defaults.seriesOrdering.basePlaybackMode, 'shuffle');
});

test('planning emits every strategy with global playlists and per-library/cross-library policy', () => {
  const snapshot = richSnapshot();
  const separate = buildChannelSetupPlan(config(), snapshot);
  assert.deepEqual(new Set(separate.channels.map((channel) => channel.buildStrategy)), new Set<ChannelSetupStrategyKey>([
    'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
  ]));
  assert.equal(separate.channels.filter((channel) => channel.buildStrategy === 'playlists').length, 1);
  assert.ok(separate.channels.some((channel) => channel.name === 'Movies - Action'));
  assert.ok(separate.channels.some((channel) => channel.name === 'Shows - Action'));
  assert.ok(separate.channels.some((channel) => channel.name === 'Actor Shared - Movies'));
  assert.ok(separate.channels.some((channel) => channel.name === 'Actor Shared - Shows'));

  const combinedPerLibrary = buildChannelSetupPlan(config({
    actorStudioCombineMode: 'combined',
  }), snapshot);
  const combinedActor = combinedPerLibrary.channels.find((channel) => channel.name === 'Actor Shared');
  assert.equal(combinedActor?.contentSource.type, 'mixed');
  if (combinedActor?.contentSource.type === 'mixed') {
    assert.equal(combinedActor.contentSource.mixMode, 'sequential');
    assert.equal(combinedActor.contentSource.sources.length, 2);
  }
  const soloActor = combinedPerLibrary.channels.find((channel) => channel.name === 'Actor Solo');
  assert.equal(soloActor?.contentSource.type, 'mixed');
  if (soloActor?.contentSource.type === 'mixed') assert.equal(soloActor.contentSource.sources.length, 1);
  const combinedStudio = combinedPerLibrary.channels.find((channel) => channel.name === 'Studio Shared');
  assert.equal(combinedStudio?.contentSource.type, 'mixed');
  if (combinedStudio?.contentSource.type === 'mixed') assert.equal(combinedStudio.contentSource.sources.length, 2);

  const cross = buildChannelSetupPlan(config({
    actorStudioCombineMode: 'combined',
    strategyConfig: strategyOverrides(['genres', 'directors', 'studios', 'actors'], { scope: 'cross-library' }),
  }), snapshot);
  const crossGenre = cross.channels.find((channel) => channel.buildStrategy === 'genres' && channel.name === 'Action');
  assert.equal(crossGenre?.contentSource.type, 'mixed');
  const crossActor = cross.channels.find((channel) => channel.name === 'Actor Shared');
  if (crossActor?.contentSource.type === 'mixed') assert.equal(crossActor.contentSource.mixMode, 'interleave');

  const crossSeparate = buildChannelSetupPlan(config({
    actorStudioCombineMode: 'separate',
    strategyConfig: strategyOverrides(['actors', 'studios'], { scope: 'cross-library' }),
  }), snapshot);
  const crossSeparateActor = crossSeparate.channels.find((channel) => channel.name === 'Actor Shared');
  assert.equal(crossSeparateActor?.contentSource.type, 'mixed');
  if (crossSeparateActor?.contentSource.type === 'mixed') assert.equal(crossSeparateActor.contentSource.mixMode, 'interleave');
  const crossSeparateStudio = crossSeparate.channels.find((channel) => channel.name === 'Studio Shared');
  assert.equal(crossSeparateStudio?.contentSource.type, 'mixed');
  if (crossSeparateStudio?.contentSource.type === 'mixed') assert.equal(crossSeparateStudio.contentSource.mixMode, 'interleave');
});

test('cross-library actor and director movie counts aggregate before min filtering', () => {
  const snapshot = emptySnapshot();
  snapshot.libraries = [
    { id: 'movies-a', title: 'Movies A', type: 'movie', itemCount: 10 },
    { id: 'movies-b', title: 'Movies B', type: 'movie', itemCount: 10 },
  ];
  snapshot.actorsByLibraryId = new Map([
    ['movies-a', [facet('actor-a', 'Shared Actor', 3)]],
    ['movies-b', [facet('actor-b', 'Shared Actor', 3)]],
  ]);
  snapshot.directorsByLibraryId = new Map([
    ['movies-a', [facet('director-a', 'Shared Director', 3)]],
    ['movies-b', [facet('director-b', 'Shared Director', 3)]],
  ]);
  const plan = buildChannelSetupPlan(config({
    selectedLibraryIds: ['movies-a', 'movies-b'],
    minItemsPerChannel: 5,
    actorStudioCombineMode: 'separate',
    strategyConfig: {
      ...onlyStrategies(['actors', 'directors']),
      actors: { enabled: true, scope: 'cross-library' },
      directors: { enabled: true, scope: 'cross-library' },
    },
  }), snapshot);

  const actor = plan.channels.find((channel) => channel.name === 'Shared Actor');
  const director = plan.channels.find((channel) => channel.name === 'Shared Director');
  assert.equal(actor?.eligibleItemCount, 6);
  assert.equal(director?.eligibleItemCount, 6);
  assert.equal(actor?.contentSource.type, 'mixed');
  assert.equal(director?.contentSource.type, 'mixed');
});

test('TV people eligibility requires three series and mixed groups retain available movie sources', () => {
  const snapshot = richSnapshot();
  snapshot.actorsByLibraryId = new Map([
    ['movies', [facet('shared', 'Actor Shared', 7)]],
    ['shows', [facet('shared-tv', 'Actor Shared', 20, 2), facet('tv-only', 'TV Only', 20, 2)]],
  ]);
  snapshot.directorsByLibraryId = snapshot.actorsByLibraryId;
  const plan = buildChannelSetupPlan(config({
    actorStudioCombineMode: 'combined',
    strategyConfig: strategyOverrides(['actors', 'directors'], { scope: 'cross-library' }),
  }), snapshot);
  const actor = plan.channels.find((channel) => channel.buildStrategy === 'actors' && channel.name === 'Actor Shared');
  assert.equal(actor?.contentSource.type, 'mixed');
  if (actor?.contentSource.type === 'mixed') assert.equal(actor.contentSource.sources.length, 1);
  assert.equal(plan.channels.some((channel) => channel.name === 'TV Only'), false);
});

test('planning applies base, alternate, variant, min, balanced allocation, and cap in frozen order', () => {
  const snapshot = emptySnapshot();
  snapshot.libraries = [{ id: 'shows', title: 'Shows', type: 'show', itemCount: 20 }];
  snapshot.collectionsByLibraryId = new Map([['shows', [
    facet('high', 'High', 10),
    facet('low', 'Low', 4),
  ]]]) ;
  const draft = config({
    selectedLibraryIds: ['shows'],
    maxChannels: 3,
    minItemsPerChannel: 5,
    strategyConfig: onlyStrategies(['collections']),
    channelExpansion: { addAlternateLineups: true, alternateLineupCopies: 1, variantType: 'block', variantBlockSize: 4 },
  });
  const plan = buildChannelSetupPlan(draft, snapshot);

  assert.equal(plan.eligibleGeneratedCount, 4);
  assert.equal(plan.droppedByMinItemsCount, 4);
  assert.equal(plan.selectedGeneratedCount, 3);
  assert.equal(plan.droppedByPlanCapCount, 1);
  assert.equal(plan.reachedMaxChannels, true);
  assert.deepEqual(plan.channels.map((channel) => [channel.name, channel.lineupReplicaIndex, channel.isPlaybackModeVariant]), [
    ['High', 0, false],
    ['High (2)', 1, false],
    ['High • Block', 0, true],
  ]);
  assert.deepEqual(plan.channels.map(createChannelSetupIdentity), buildChannelSetupPlan(draft, snapshot).channels.map(createChannelSetupIdentity));

  const balanced = buildChannelSetupPlan(config({
    maxChannels: 2,
    strategyConfig: {
      ...onlyStrategies(['collections', 'genres']),
      genres: { enabled: true, priority: 1 },
      collections: { enabled: true, priority: 2 },
    },
  }), richSnapshot());
  assert.deepEqual(balanced.channels.map((channel) => channel.buildStrategy), ['genres', 'collections']);
});

test('series ordering and variants honor replica rules and duplicate suppression', () => {
  const snapshot = emptySnapshot();
  snapshot.libraries = [{ id: 'shows', title: 'Shows', type: 'show', itemCount: 20 }];
  snapshot.collectionsByLibraryId = new Map([['shows', [facet('series', 'Series', 20)]]]);
  const sequential = buildChannelSetupPlan(config({
    selectedLibraryIds: ['shows'], strategyConfig: onlyStrategies(['collections']),
    seriesOrdering: { basePlaybackMode: 'shuffle', baseBlockSize: 3 },
    channelExpansion: { addAlternateLineups: true, alternateLineupCopies: 2, variantType: 'sequential', variantBlockSize: 3 },
  }), snapshot);
  assert.equal(sequential.channels.filter((channel) => channel.isPlaybackModeVariant).length, 1);
  assert.equal(sequential.channels.find((channel) => channel.isPlaybackModeVariant)?.lineupReplicaIndex, 0);

  const block = buildChannelSetupPlan(config({
    selectedLibraryIds: ['shows'], strategyConfig: onlyStrategies(['collections']),
    seriesOrdering: { basePlaybackMode: 'block', baseBlockSize: 4 },
    channelExpansion: { addAlternateLineups: true, alternateLineupCopies: 1, variantType: 'block', variantBlockSize: 4 },
  }), snapshot);
  assert.equal(block.channels.filter((channel) => channel.isPlaybackModeVariant).length, 0);
  assert.ok(block.channels.every((channel) => channel.playbackMode === 'block' && channel.blockSize === 4));

  const blockVariants = buildChannelSetupPlan(config({
    selectedLibraryIds: ['shows'], strategyConfig: onlyStrategies(['collections']),
    channelExpansion: { addAlternateLineups: true, alternateLineupCopies: 1, variantType: 'block', variantBlockSize: 4 },
  }), snapshot);
  assert.deepEqual(
    blockVariants.channels.filter((channel) => channel.isPlaybackModeVariant).map((channel) => channel.lineupReplicaIndex),
    [0, 1],
  );
});

test('alternate expansion excludes actor, director, and sequential base strategies', () => {
  const plan = buildChannelSetupPlan(config({
    strategyConfig: onlyStrategies(['actors', 'directors', 'recentlyAdded']),
    channelExpansion: { addAlternateLineups: true, alternateLineupCopies: 3, variantType: 'none', variantBlockSize: 3 },
  }), richSnapshot());
  assert.ok(plan.channels.length > 0);
  assert.ok(plan.channels.every((channel) => channel.lineupReplicaIndex === 0));
});

test('canonical identity is stable, ignores rename/base playback, and distinguishes replicas and variants', () => {
  const base = planned('Original');
  const renamed = { ...base, name: 'Renamed', playbackMode: 'sequential' as const, blockSize: 5 };
  assert.equal(createChannelSetupIdentity(base), createChannelSetupIdentity(renamed));
  assert.notEqual(createChannelSetupIdentity(base), createChannelSetupIdentity({ ...base, lineupReplicaIndex: 1 }));
  assert.notEqual(createChannelSetupIdentity(base), createChannelSetupIdentity({ ...base, isPlaybackModeVariant: true, playbackMode: 'sequential' }));
  assert.notEqual(
    createChannelSetupIdentity({ ...base, isPlaybackModeVariant: true, playbackMode: 'block', blockSize: 2 }),
    createChannelSetupIdentity({ ...base, isPlaybackModeVariant: true, playbackMode: 'block', blockSize: 3 }),
  );

  const sourceA = { ...base, contentFilters: [
    { field: 'year' as const, operator: 'lt' as const, value: 2000 },
    { field: 'genre' as const, operator: 'eq' as const, value: 'Drama' },
  ] };
  const sourceB = { ...base, contentFilters: [...sourceA.contentFilters].reverse() };
  assert.equal(createChannelSetupIdentity(sourceA), createChannelSetupIdentity(sourceB));

  const movieSource = { type: 'library' as const, libraryId: 'movies', libraryType: 'movie' as const, includeWatched: true };
  const showSource = { type: 'library' as const, libraryId: 'shows', libraryType: 'show' as const, includeWatched: true };
  assert.equal(
    createChannelSetupIdentity({ ...base, contentSource: { type: 'mixed', mixMode: 'sequential', sources: [movieSource, showSource] } }),
    createChannelSetupIdentity({ ...base, contentSource: { type: 'mixed', mixMode: 'sequential', sources: [showSource, movieSource] } }),
  );
});

test('FIFO diff preserves custom channels and applies append, merge, and replace policy', () => {
  const first = channel('generated-1', 11, 'Old One', true);
  const second = channel('generated-2', 12, 'Old Two', true);
  const custom = channel('custom', 13, 'Custom', false);
  const plannedRows = [planned('Rename One'), planned('Rename Two'), planned('New Third')];

  const append = diffChannelSetupPlan([first, second, custom], plannedRows, 'append');
  assert.deepEqual(append.matched.map(({ existing }) => existing.id), ['generated-1', 'generated-2']);
  assert.deepEqual(append.created.map((candidate) => candidate.name), ['New Third']);
  assert.deepEqual(append.preserved.map((candidate) => candidate.id), ['generated-1', 'generated-2', 'custom']);

  const merge = diffChannelSetupPlan([first, second, custom], plannedRows, 'merge');
  assert.deepEqual(merge.matched.map(({ existing }) => existing.id), ['generated-1', 'generated-2']);
  assert.deepEqual(merge.preserved.map((candidate) => candidate.id), ['custom']);
  const updated = mergeChannelSetupMatch(first, merge.matched[0]!.planned, 99);
  assert.equal(updated.id, first.id);
  assert.equal(updated.number, first.number);
  assert.equal(updated.name, 'Rename One');
  assert.equal(updated.updatedAt, 99);

  const replace = diffChannelSetupPlan([first, custom], plannedRows, 'replace');
  assert.deepEqual(replace.removed.map((candidate) => candidate.id), ['generated-1', 'custom']);
  assert.equal(replace.created.length, 3);
});

test('channel number allocation separates generated cap from number exhaustion', () => {
  const append = allocateChannelSetupNumbers([{ number: 1 }, { number: 3 }], 3, 'append');
  assert.deepEqual(append.numbers, [2, 4, 5]);
  assert.equal(append.exhausted, false);
  const replace = allocateChannelSetupNumbers([{ number: 1 }], 2, 'replace');
  assert.deepEqual(replace.numbers, [1, 2]);
  const full = allocateChannelSetupNumbers(Array.from({ length: 500 }, (_, index) => ({ number: index + 1 })), 1, 'merge');
  assert.equal(full.exhausted, true);
  assert.deepEqual(full.numbers, []);
  assert.deepEqual(allocateChannelSetupNumbers([], -2, 'append'), { numbers: [], exhausted: false });
});

function config(overrides: Partial<ChannelSetupConfigDraft> = {}) {
  return normalizeChannelSetupConfig({
    selectedLibraryIds: ['movies', 'shows'],
    maxChannels: 200,
    buildMode: 'replace',
    strategyConfig: {},
    actorStudioCombineMode: 'separate',
    minItemsPerChannel: 5,
    ...overrides,
  });
}

function onlyStrategies(enabled: readonly ChannelSetupStrategyKey[]): ChannelSetupConfigDraft['strategyConfig'] {
  return Object.fromEntries(([
    'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
  ] as const).map((strategy) => [strategy, { enabled: enabled.includes(strategy) }]));
}

function strategyOverrides(
  strategies: readonly ChannelSetupStrategyKey[],
  value: ChannelSetupConfigDraft['strategyConfig'][ChannelSetupStrategyKey],
): ChannelSetupConfigDraft['strategyConfig'] {
  return Object.fromEntries(strategies.map((strategy) => [strategy, value]));
}

function richSnapshot(): ChannelSetupFacetSnapshot {
  const snapshot = emptySnapshot();
  snapshot.libraries = [
    { id: 'movies', title: 'Movies', type: 'movie', itemCount: 50 },
    { id: 'shows', title: 'Shows', type: 'show', itemCount: 60 },
  ];
  snapshot.playlists = [facet('playlist', 'Playlist', 10), facet('playlist', 'Playlist duplicate', 9)];
  snapshot.collectionsByLibraryId = new Map([
    ['movies', [facet('movie-collection', 'Movie Collection', 10)]],
    ['shows', [facet('show-collection', 'Show Collection', 10)]],
  ]);
  snapshot.genresByLibraryId = sharedFacets('action', 'Action', 10);
  snapshot.directorsByLibraryId = new Map([
    ['movies', [facet('director-movie', 'Director Shared', 10)]],
    ['shows', [facet('director-show', 'Director Shared', 12, 3)]],
  ]);
  snapshot.yearsByLibraryId = new Map([
    ['movies', [facet('1991', '1991', 3), facet('1995', '1995', 4)]],
    ['shows', [facet('2001', '2001', 8)]],
  ]);
  snapshot.studiosByLibraryId = sharedFacets('studio', 'Studio Shared', 10);
  snapshot.actorsByLibraryId = new Map([
    ['movies', [facet('actor-movie', 'Actor Shared', 10), facet('solo', 'Actor Solo', 8)]],
    ['shows', [facet('actor-show', 'Actor Shared', 12, 3)]],
  ]);
  return snapshot;
}

function emptySnapshot(): ChannelSetupFacetSnapshot & {
  libraries: ChannelSetupFacetSnapshot['libraries'];
  playlists: ChannelSetupFacetSnapshot['playlists'];
  collectionsByLibraryId: ChannelSetupFacetSnapshot['collectionsByLibraryId'];
  genresByLibraryId: ChannelSetupFacetSnapshot['genresByLibraryId'];
  directorsByLibraryId: ChannelSetupFacetSnapshot['directorsByLibraryId'];
  yearsByLibraryId: ChannelSetupFacetSnapshot['yearsByLibraryId'];
  studiosByLibraryId: ChannelSetupFacetSnapshot['studiosByLibraryId'];
  actorsByLibraryId: ChannelSetupFacetSnapshot['actorsByLibraryId'];
} {
  return {
    libraries: [], playlists: [], collectionsByLibraryId: new Map(), genresByLibraryId: new Map(),
    directorsByLibraryId: new Map(), yearsByLibraryId: new Map(), studiosByLibraryId: new Map(),
    actorsByLibraryId: new Map(), warnings: [],
  };
}

function sharedFacets(key: string, title: string, count: number) {
  return new Map([
    ['movies', [facet(`${key}-movie`, title, count)]],
    ['shows', [facet(`${key}-show`, title, count)]],
  ]);
}

function facet(key: string, title: string, itemCount: number | null, seriesCount?: number): ChannelSetupNamedFacet {
  return { key, title, itemCount, ...(seriesCount === undefined ? {} : { seriesCount }) };
}

function planned(name: string): ChannelSetupPlannedChannel {
  return {
    name,
    buildStrategy: 'genres',
    contentSource: { type: 'library', libraryId: 'movies', libraryType: 'movie', includeWatched: true, libraryFilter: { genre: 'Drama' } },
    playbackMode: 'shuffle',
    shuffleSeed: 1,
    isAutoGenerated: true,
    lineupReplicaIndex: 0,
    isPlaybackModeVariant: false,
    eligibleItemCount: 10,
  };
}

function channel(id: string, number: number, name: string, generated: boolean): ChannelConfig {
  return {
    id, number, name, isAutoGenerated: generated,
    contentSource: { type: 'library', libraryId: 'movies', libraryType: 'movie', includeWatched: true, libraryFilter: { genre: 'Drama' } },
    playbackMode: 'shuffle', startTimeAnchor: 0, skipIntros: false, skipCredits: false,
    createdAt: 1, updatedAt: 1, lastContentRefresh: 1, itemCount: 10, totalDurationMs: 100,
  };
}
