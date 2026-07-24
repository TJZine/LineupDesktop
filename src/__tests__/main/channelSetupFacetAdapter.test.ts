import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeChannelSetupConfig } from '../../domain/channel/setupPlanning/index.js';
import { DesktopPlexSetupFacetSource } from '../../main/channel/setup/desktopPlexSetupFacetSource.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';

test('private Plex setup facet source narrows video playlists, collections, counts, and media type policy', async () => {
  const tagCalls: Array<{ family: string; type: number }> = [];
  const transport = {
    listLibrarySections: async () => container('Directory', [
      { key: 'movies', title: 'Movies', type: 'movie' },
      { key: 'shows', title: 'Shows', type: 'show' },
      { key: 'music', title: 'Music', type: 'artist' },
    ]),
    listVideoPlaylists: async () => container('Metadata', [
      { ratingKey: 'p1', title: 'Video', playlistType: 'video', leafCount: 4 },
      { ratingKey: 'p2', title: 'Audio', playlistType: 'audio', leafCount: 9 },
    ]),
    listLibraryItems: async (input: { filter?: Record<string, number> }) => input.filter?.type === 18
      ? container('Metadata', [{ ratingKey: 'c1', title: 'Collection', childCount: 3 }])
      : { kind: 'json', data: { MediaContainer: { totalSize: 12, Metadata: [] } } },
    listLibraryTagDirectory: async (input: { family: string; type: number }) => {
      tagCalls.push({ family: input.family, type: input.type });
      return container('Directory', [{ key: 'tag-1', title: 'Tag', count: '6' }]);
    },
  };
  const plexRuntime = {
    withActiveChannelSetupContext: async (run: (context: object) => unknown) => run({
      profileId: 'profile', serverId: 'server', connection: {}, token: 'private', transport,
    }),
  } as unknown as DesktopPlexRuntime;
  const source = new DesktopPlexSetupFacetSource(plexRuntime);
  const config = normalizeChannelSetupConfig({
    selectedLibraryIds: ['movies', 'shows'], maxChannels: 50, buildMode: 'merge', strategyConfig: {},
    actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
  });
  const progress: Array<{ task: string; current: number; total: number | null }> = [];
  const result = await source.load(config, new AbortController().signal, (value) => progress.push(value));

  assert.deepEqual(result.snapshot.libraries.map((library) => [library.id, library.itemCount]), [['movies', 12], ['shows', 12]]);
  assert.deepEqual(result.snapshot.playlists, [{ key: 'p1', title: 'Video', itemCount: 4 }]);
  assert.deepEqual(result.snapshot.collectionsByLibraryId.get('movies'), [{ key: 'c1', title: 'Collection', itemCount: 3 }]);
  assert.equal(tagCalls.some((call) => call.family === 'studio' && call.type === 4), false);
  assert.equal(tagCalls.some((call) => call.family === 'genre' && call.type === 2), true);
  assert.equal(tagCalls.some((call) => call.family === 'actor' && call.type === 4), true);
  const ranks = new Map([['fetch_playlists', 0], ['fetch_collections', 1], ['fetch_facets', 2], ['scan_library_items', 3]]);
  const observedRanks = progress.map((value) => ranks.get(value.task) ?? -1);
  assert.deepEqual(observedRanks, [...observedRanks].sort((left, right) => left - right));
  for (const task of ranks.keys()) {
    const values = progress.filter((value) => value.task === task);
    assert.deepEqual(values.map((value) => value.current), [...values.map((value) => value.current)].sort((a, b) => a - b));
    assert.equal(values.every((value) => value.total !== null && value.current <= value.total), true);
  }
});

test('private Plex setup facet source rejects malformed required facet fields', async () => {
  const transport = {
    listLibrarySections: async () => container('Directory', [{ key: 'movies', type: 'movie' }]),
  };
  const plexRuntime = {
    withActiveChannelSetupContext: async (run: (context: object) => unknown) => run({
      profileId: 'profile', serverId: 'server', connection: {}, token: 'private', transport,
    }),
  } as unknown as DesktopPlexRuntime;
  const source = new DesktopPlexSetupFacetSource(plexRuntime);
  const config = normalizeChannelSetupConfig({
    selectedLibraryIds: ['movies'], maxChannels: 10, buildMode: 'replace', strategyConfig: {},
    actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
  });
  await assert.rejects(source.load(config, new AbortController().signal), /library title/u);
});

test('private Plex setup facet source derives TV people counts and distinct series breadth from episodes', async () => {
  const transport = {
    listLibrarySections: async () => container('Directory', [{ key: 'shows', title: 'Shows', type: 'show' }]),
    listVideoPlaylists: async () => container('Metadata', []),
    listLibraryTagDirectory: async (input: { family: string }) => input.family === 'actor'
      ? container('Directory', [{ key: 'actor-1', title: 'Person' }])
      : input.family === 'director'
        ? container('Directory', [{ key: 'director-1', title: 'Person' }])
        : container('Directory', []),
    listLibraryItems: async (input: { filter?: Record<string, number> }) => input.filter?.type === 4
      ? { kind: 'json', data: { MediaContainer: { totalSize: 3, Metadata: [
          { grandparentRatingKey: 'show-1', Role: [{ tag: 'Person' }], Director: [{ tag: 'Person' }] },
          { grandparentRatingKey: 'show-1', Role: [{ tag: 'Person' }], Director: [{ tag: 'Person' }] },
          { grandparentTitle: 'Second Show', Role: [{ tag: 'Person' }], Director: [{ tag: 'Person' }] },
        ] } } }
      : { kind: 'json', data: { MediaContainer: { totalSize: 3, Metadata: [] } } },
  };
  const source = new DesktopPlexSetupFacetSource({
    withActiveChannelSetupContext: async (run: (context: object) => unknown) => run({
      profileId: 'profile', serverId: 'server', connection: {}, token: 'private', transport,
    }),
  } as unknown as DesktopPlexRuntime);
  const config = normalizeChannelSetupConfig({
    selectedLibraryIds: ['shows'], maxChannels: 10, buildMode: 'merge', strategyConfig: {},
    actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
  });
  const result = await source.load(config, new AbortController().signal);
  assert.deepEqual(result.snapshot.actorsByLibraryId.get('shows'), [
    { key: 'actor-1', title: 'Person', itemCount: 3, seriesCount: 2 },
  ]);
  assert.deepEqual(result.snapshot.directorsByLibraryId.get('shows'), [
    { key: 'director-1', title: 'Person', itemCount: 3, seriesCount: 2 },
  ]);
});

test('private Plex setup facet source bounds repeated full TV pages and reports truncation', async () => {
  let scanCalls = 0;
  const repeatedPage = Array.from({ length: 500 }, (_value, index) => ({
    grandparentRatingKey: `show-${String(index % 4)}`,
    Role: [{ tag: 'Person' }],
  }));
  const transport = {
    listLibrarySections: async () => container('Directory', [{ key: 'shows', title: 'Shows', type: 'show' }]),
    listVideoPlaylists: async () => container('Metadata', []),
    listLibraryTagDirectory: async (input: { family: string }) => input.family === 'actor'
      ? container('Directory', [{ key: 'actor-1', title: 'Person' }])
      : container('Directory', []),
    listLibraryItems: async (input: { filter?: Record<string, number> }) => {
      if (input.filter?.type === 4) {
        scanCalls += 1;
        return { kind: 'json', data: { MediaContainer: { Metadata: repeatedPage } } };
      }
      return { kind: 'json', data: { MediaContainer: { totalSize: 1, Metadata: [] } } };
    },
  };
  const source = new DesktopPlexSetupFacetSource({
    withActiveChannelSetupContext: async (run: (context: object) => unknown) => run({
      profileId: 'profile', serverId: 'server', connection: {}, token: 'private', transport,
    }),
  } as unknown as DesktopPlexRuntime);
  const strategyConfig = Object.fromEntries([
    'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
  ].map((key) => [key, { enabled: key === 'actors' }]));
  const config = normalizeChannelSetupConfig({
    selectedLibraryIds: ['shows'], maxChannels: 10, buildMode: 'merge', strategyConfig,
    actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
  });
  const result = await source.load(config, new AbortController().signal);
  assert.equal(scanCalls, 20);
  assert.deepEqual(result.snapshot.warnings, ['A TV people scan reached its safety limit.']);
  assert.deepEqual(result.snapshot.actorsByLibraryId.get('shows'), [
    { key: 'actor-1', title: 'Person', itemCount: 10_000, seriesCount: 4 },
  ]);
});

function container(field: 'Directory' | 'Metadata', values: unknown[]) {
  return { kind: 'json', data: { MediaContainer: { [field]: values } } };
}
