import assert from 'node:assert/strict';
import test from 'node:test';

import { createDefaultChannelSetupConfig } from '../../domain/channelBuilder/config.js';
import {
  createCandidateIdentity,
  createContentFilterIdentity,
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
} from '../../domain/channelBuilder/planIdentity.js';
import type {
  ChannelBuilderCandidateDraft,
  ChannelBuilderContextBinding,
  ChannelBuilderSafeSourceReference,
  ChannelBuilderStrategyKey,
} from '../../domain/channelBuilder/types.js';
import {
  createChannelBuilderFacetSession,
  DesktopPlexChannelBuilderFacetSource,
  invalidateChannelBuilderFacetSession,
  type ChannelBuilderFacetAccessPort,
  type ChannelBuilderFacetSession,
} from '../../main/plex/desktopPlexChannelBuilderFacetSource.js';
import { DesktopPlexLibraryOperationExecutor } from '../../main/plex/desktopPlexLibraryOperationExecutor.js';
import type { PlexConnection } from '../../main/plex/discovery/types.js';
import type { PlexLibrarySection } from '../../main/plex/library/types.js';
import {
  LivePlexTransport,
  type LivePlexChannelBuilderFacetTransport,
  type LivePlexLibraryTransport,
} from '../../main/plex/livePlexTransport.js';
import { LivePlexTransportError } from '../../main/plex/livePlexTransportError.js';

const connection: PlexConnection = {
  uri: 'https://plex.example.invalid/base',
  protocol: 'https',
  address: 'plex.example.invalid',
  port: 443,
  local: false,
  relay: false,
  latencyMs: null,
};
const signal = new AbortController().signal;
const placeholderCredential = ['placeholder', 'credential'].join('-');

test('live Plex facet transport emits only the three fixed encoded request shapes', async () => {
  const requests: string[] = [];
  const transport = new LivePlexTransport({
    fetch: async (input) => {
      requests.push(String(input));
      return jsonResponse({ MediaContainer: { size: 0 } });
    },
  });
  const facetTransport: LivePlexChannelBuilderFacetTransport = transport;
  const legacyTransport: LivePlexLibraryTransport = transport;

  await facetTransport.listCollectionsPage({
    connection,
    token: placeholderCredential,
    sectionId: 'movies /? value',
    offset: 100,
    limit: 100,
    signal,
  });
  await facetTransport.listServerPlaylistsPage({
    connection,
    token: placeholderCredential,
    offset: 200,
    limit: 100,
    signal,
  });
  await facetTransport.listTagDirectoryPage({
    connection,
    token: placeholderCredential,
    sectionId: 'shows /? value',
    family: 'director',
    mediaType: 4,
    offset: 300,
    limit: 100,
    signal,
  });

  assert.deepEqual(requests, [
    'https://plex.example.invalid/library/sections/movies%20%2F%3F%20value/all?type=18&includeGuids=1&includeMeta=1&X-Plex-Container-Start=100&X-Plex-Container-Size=100',
    'https://plex.example.invalid/playlists?X-Plex-Container-Start=200&X-Plex-Container-Size=100',
    'https://plex.example.invalid/library/sections/shows%20%2F%3F%20value/director?type=4&X-Plex-Container-Start=300&X-Plex-Container-Size=100',
  ]);
  assert.deepEqual(Object.keys(legacyTransport).filter((key) => key.includes('Facet')), []);
});

test('facet session routes facet and item methods through separately named transports', async () => {
  const facetCalls: string[] = [];
  const itemCalls: Array<Record<string, unknown>> = [];
  const facetTransport = createFacetTransport(facetCalls);
  const itemTransport: Pick<LivePlexLibraryTransport, 'listLibraryItems'> = {
    async listLibraryItems(input) {
      itemCalls.push({ ...input, connection: 'main-only', token: 'main-only', signal: 'main-only' });
      return { kind: 'json', data: { MediaContainer: { offset: input.offset, totalSize: 0 } } };
    },
  };
  const session = createChannelBuilderFacetSession(
    { facetTransport, itemTransport },
    { connection, token: placeholderCredential, libraries: [movieLibrary(), showLibrary()] },
  );

  await session.listCollectionsPage({
    sectionId: '1',
    offset: 0,
    limit: 100,
    signal,
  });
  await session.listServerPlaylistsPage({ offset: 0, limit: 100, signal });
  await session.listTagDirectoryPage({
    sectionId: '1',
    family: 'genre',
    mediaType: 1,
    offset: 0,
    limit: 100,
    signal,
  });
  await session.listLibraryItemsPage({
    sectionId: '1',
    query: { kind: 'recently-added', mediaType: 1 },
    offset: 0,
    limit: 100,
    signal,
  });
  await session.listLibraryItemsPage({
    sectionId: '2',
    query: { kind: 'tv-people-index' },
    offset: 0,
    limit: 100,
    signal,
  });
  await session.listLibraryItemsPage({
    sectionId: '1',
    query: {
      kind: 'facet-count',
      mediaType: 1,
      family: 'actor',
      key: 'actor-key',
      tagValue: 'Never a fallback',
      fastKey: '/library/all?actor=fast-actor&type=99',
    },
    offset: 0,
    limit: 100,
    signal,
  });

  assert.deepEqual(facetCalls, ['collections', 'playlists', 'tags']);
  assert.equal(itemCalls.length, 3);
  assert.deepEqual(itemCalls.map(({ filter, sort }) => ({ filter, sort })), [
    { filter: { type: 1 }, sort: 'addedAt:desc' },
    { filter: { type: 4 }, sort: undefined },
    { filter: { actor: 'fast-actor', type: 1 }, sort: undefined },
  ]);
  invalidateChannelBuilderFacetSession(session);
  await assert.rejects(() =>
    session.listServerPlaylistsPage({ offset: 0, limit: 100, signal }));
});

test('actor and studio malformed fast keys fall back only to the raw key', async () => {
  const itemCalls: Array<Record<string, unknown>> = [];
  const session = createChannelBuilderFacetSession(
    {
      facetTransport: createFacetTransport([]),
      itemTransport: {
        async listLibraryItems(input) {
          itemCalls.push(input.filter ?? {});
          return { kind: 'json', data: { MediaContainer: { offset: 0, totalSize: 0 } } };
        },
      },
    },
    { connection, token: placeholderCredential, libraries: [movieLibrary()] },
  );
  const unsafeKey = ['authorization', 'header'].join('-');
  for (const [family, fastKey] of [
    ['actor', `/all?actor=allowed&${unsafeKey}=not-allowed`],
    ['studio', '/all?actor=wrong-family'],
    ['studio', '/all?studio='],
    ['actor', '/all?X-Plex-Container-Start=1&actor=allowed'],
  ] as const) {
    await session.listLibraryItemsPage({
      sectionId: '1',
      query: {
        kind: 'facet-count',
        mediaType: 1,
        family,
        key: `${family}-raw-key`,
        tagValue: 'Not used',
        fastKey,
      },
      offset: 0,
      limit: 100,
      signal,
    });
  }
  assert.deepEqual(itemCalls, [
    { actor: 'actor-raw-key', type: 1 },
    { studio: 'studio-raw-key', type: 1 },
    { studio: 'studio-raw-key', type: 1 },
    { actor: 'actor-raw-key', type: 1 },
  ]);
});

test('discovery keeps raw tag semantics main-only and materializes exact runtime values', async () => {
  const rawTitle = ['token', 'semantic'].join('-');
  const itemQueries: unknown[] = [];
  const session = createDiscoverySession(rawTitle, itemQueries);
  const accessPort: ChannelBuilderFacetAccessPort = {
    async withSession(_input, run) {
      try {
        return await run(session);
      } finally {
        invalidateChannelBuilderFacetSession(session);
      }
    },
  };
  const source = new DesktopPlexChannelBuilderFacetSource(accessPort);
  const config = configWithOnly('genres');
  const context = builderContext();
  const result = await source.discover({
    normalizedConfig: config,
    context,
    deadlineAtMs: Date.now() + 60_000,
    signal,
  });

  assert.equal(result.kind, 'ready');
  assert.equal(result.snapshot.tags.length, 1);
  const tag = result.snapshot.tags[0]!;
  assert.equal(tag.family, 'genre');
  assert.equal(tag.displayTitle, '[redacted]');
  assert.equal(JSON.stringify(result.snapshot).includes(rawTitle), false);
  assert.equal(JSON.stringify(result.snapshot).includes('genre-raw-key'), false);
  assert.deepEqual(itemQueries, [{
    kind: 'facet-count',
    mediaType: 1,
    family: 'genre',
    key: 'genre-raw-key',
    tagValue: rawTitle,
    fastKey: null,
  }]);

  const sourceReference = {
    kind: 'facet' as const,
    facetId: tag.facetId,
    sourceIdentity: tag.sourceIdentity,
  };
  const origin = {
    profileBinding: context.profileBinding,
    serverBinding: context.serverBinding,
    librarySetBinding: context.librarySetBinding,
  };
  const candidate = {
    candidateId: `candidate:${'a'.repeat(64)}` as const,
    candidateIdentity: createCandidateIdentity({
      origin,
      sourceReference,
      contentFilterIdentity: null,
      sortOrder: null,
      lineupReplicaIndex: 0,
      isPlaybackModeVariant: false,
      playbackMode: 'shuffle',
      blockSize: null,
    }),
    origin,
    strategy: 'genres' as const,
    displayName: 'Genre channel',
    sourceReference,
    estimatedItemCount: 12,
    playbackMode: 'shuffle' as const,
    shuffleSeed: 42,
    contentFilterPlan: { kind: 'none' as const, contentFilterIdentity: null },
    sortOrder: null,
    blockSize: null,
    buildStrategy: 'genres' as const,
    sourceLibraryId: '1',
    sourceLibraryName: 'Movies',
    lineupReplicaIndex: 0 as const,
    isPlaybackModeVariant: false,
  };
  const materialized = await result.materializationIndex.materialize({
    candidate,
    expectedContext: context,
    signal,
  });
  assert.equal(materialized.status, 'ready');
  if (materialized.status === 'ready') {
    assert.deepEqual(materialized.createInput.contentSource, {
      type: 'library',
      libraryId: '1',
      libraryType: 'movie',
      includeWatched: true,
      libraryFilter: { genre: rawTitle },
    });
    assert.deepEqual(Object.keys(materialized.createInput).sort(), [
      'buildStrategy',
      'contentSource',
      'isAutoGenerated',
      'isPlaybackModeVariant',
      'lineupReplicaIndex',
      'name',
      'playbackMode',
      'shuffleSeed',
      'sourceLibraryId',
      'sourceLibraryName',
    ]);
  }
  result.materializationIndex.dispose();
  assert.equal(
    (await result.materializationIndex.materialize({
      candidate,
      expectedContext: context,
      signal,
    })).status,
    'failed',
  );
});

test('main section listing derives safe sections and UUID pairs from one catalog fetch', async () => {
  let sectionFetches = 0;
  const transport = createLegacyTransport({
    async listLibrarySections() {
      sectionFetches += 1;
      return {
        kind: 'json',
        data: {
          MediaContainer: {
            Directory: [
              rawLibrary('2', 'uuid-b', 'Shows', 'show'),
              rawLibrary('1', 'uuid-a', 'Movies', 'movie'),
            ],
          },
        },
      };
    },
  });
  const executor = new DesktopPlexLibraryOperationExecutor(transport);
  const result = await executor.listSectionsForMain({
    connection,
    token: placeholderCredential,
    signal,
  });

  assert.equal(sectionFetches, 1);
  assert.deepEqual(result.libraryPairs, [
    { libraryId: '1', libraryUuid: 'uuid-a' },
    { libraryId: '2', libraryUuid: 'uuid-b' },
  ]);
  assert.deepEqual(result.sections.map(({ id }) => id), ['2', '1']);
  assert.equal(JSON.stringify(result.sections).includes('uuid-'), false);
});

test('paging honors totalSize, empty and short pages, offsets, and the five-page family cap', async () => {
  const scenarios = [
    {
      name: 'known total',
      pages: [playlistPage(0, 100, 150), playlistPage(100, 50, 150)],
      offsets: [0, 100],
      omitted: 0,
    },
    {
      name: 'empty first page',
      pages: [playlistPage(0, 0, null)],
      offsets: [0],
      omitted: 0,
    },
    {
      name: 'short unknown-total page',
      pages: [playlistPage(0, 20, null)],
      offsets: [0],
      omitted: 0,
    },
    {
      name: 'five full pages with known remainder',
      pages: [
        playlistPage(0, 100, 501),
        playlistPage(100, 100, 501),
        playlistPage(200, 100, 501),
        playlistPage(300, 100, 501),
        playlistPage(400, 100, 501),
      ],
      offsets: [0, 100, 200, 300, 400],
      omitted: 1,
    },
  ] as const;

  for (const scenario of scenarios) {
    const offsets: number[] = [];
    const session = emptySession([movieLibrary()]);
    session.listServerPlaylistsPage = async (request) => {
      offsets.push(request.offset);
      return scenario.pages[offsets.length - 1]!;
    };
    const result = await discoverWithSession(session, configWithOnly('playlists'));
    assert.notEqual(result.kind, 'failed', scenario.name);
    assert.notEqual(result.kind, 'canceled', scenario.name);
    if (result.kind === 'failed' || result.kind === 'canceled') continue;
    assert.deepEqual(offsets, scenario.offsets, scenario.name);
    assert.equal(result.snapshot.playlists.length, scenario.pages.reduce(
      (count, page) => count + page.entries.length,
      0,
    ), scenario.name);
    assert.equal(result.snapshot.aggregate.omittedCappedCount, scenario.omitted, scenario.name);
    assert.equal(
      result.snapshot.aggregate.warningCodes.includes('FACET_CAP_REACHED'),
      scenario.omitted > 0,
      scenario.name,
    );
  }
});

test('family and global caps preserve exact and unknown omission accounting including libraries', async () => {
  const unknownSession = emptySession([movieLibrary()]);
  unknownSession.listServerPlaylistsPage = async (request) =>
    playlistPage(request.offset, 100, null);
  const unknown = await discoverWithSession(unknownSession, configWithOnly('playlists'));
  assert.equal(unknown.kind, 'slow');
  if (unknown.kind === 'slow') {
    assert.equal(unknown.snapshot.playlists.length, 500);
    assert.equal(unknown.snapshot.aggregate.omittedCappedCount, null);
    assert.ok(unknown.snapshot.aggregate.warningCodes.includes('FACET_CAP_REACHED'));
  }

  const libraries = Array.from({ length: 24 }, (_, index) =>
    movieLibraryWith(String(index + 1), `uuid-${index + 1}`));
  const createGlobalSession = (reverse: boolean): ChannelBuilderFacetSession => {
    const session = emptySession(libraries);
    session.listTagDirectoryPage = async (request) => {
      const entries = Array.from({ length: 100 }, (_, pageIndex) => ({
        key: `${request.sectionId}-${request.family}-${request.offset + pageIndex}`,
        title: pageIndex === 98
          ? `Bearer ${request.sectionId}-${request.family}-${request.offset}`
          : pageIndex === 99
            ? `token=${request.sectionId}-${request.family}-${request.offset}`
            : `${request.family}-${request.sectionId}-${request.offset + pageIndex}`,
        count: 1,
      }));
      return {
        entries: reverse ? entries.reverse() : entries,
        offset: request.offset,
        totalSize: 500,
      };
    };
    return session;
  };
  const global = await discoverWithSession(
    createGlobalSession(false),
    configWithEnabled(['genres', 'directors', 'decades', 'studios', 'actors'], libraries),
  );
  assert.equal(global.kind, 'slow');
  if (global.kind === 'slow') {
    assert.equal(global.snapshot.libraries.length, 24);
    assert.equal(global.snapshot.tags.length, 49_976);
    assert.equal(
      global.snapshot.libraries.length +
        global.snapshot.playlists.length +
        global.snapshot.collections.length +
        global.snapshot.tags.length +
        global.snapshot.recentlyAdded.length,
      50_000,
    );
    assert.equal(global.snapshot.aggregate.omittedCappedCount, 10_024);
    assert.ok(global.snapshot.aggregate.warningCodes.includes('FACET_CAP_REACHED'));
    const reversed = await discoverWithSession(
      createGlobalSession(true),
      configWithEnabled(['genres', 'directors', 'decades', 'studios', 'actors'], libraries),
    );
    assert.equal(reversed.kind, 'slow');
    if (reversed.kind === 'slow') {
      assert.deepEqual(
        reversed.snapshot.tags.map((tag) => tag.facetId),
        global.snapshot.tags.map((tag) => tag.facetId),
      );
      assert.ok(reversed.snapshot.tags.some((tag) => tag.displayTitle === '[redacted]'));
      assert.equal(JSON.stringify(reversed.snapshot).includes('Bearer '), false);
      assert.equal(JSON.stringify(reversed.snapshot).includes('token='), false);
    }
  }
});

test('timeouts retain bounded partial snapshots and stop further privileged calls', async () => {
  const timeout = new LivePlexTransportError('timeout', 'fixed timeout', undefined, {
    retryable: true,
  });
  const partialCalls: string[] = [];
  const partialSession = emptySession([movieLibrary()]);
  partialSession.listServerPlaylistsPage = async () => {
    partialCalls.push('playlists');
    return playlistPage(0, 1, 1);
  };
  partialSession.listCollectionsPage = async () => {
    partialCalls.push('collections');
    throw timeout;
  };
  partialSession.listTagDirectoryPage = async () => {
    partialCalls.push('tags');
    throw new Error('must not execute after timeout');
  };
  const partial = await discoverWithSession(
    partialSession,
    configWithEnabled(['playlists', 'collections', 'genres']),
  );
  assert.equal(partial.kind, 'slow');
  if (partial.kind === 'slow') {
    assert.equal(partial.snapshot.playlists.length, 1);
    assert.deepEqual(partial.snapshot.aggregate.warningCodes, [
      'FACET_DISCOVERY_TIMEOUT',
      'FACET_PARTIAL_FAILURE',
    ]);
  }
  assert.deepEqual(partialCalls, ['playlists', 'collections']);

  let expiredCalls = 0;
  const expiredSession = emptySession([movieLibrary()]);
  expiredSession.listServerPlaylistsPage = async () => {
    expiredCalls += 1;
    return playlistPage(0, 1, 1);
  };
  const expired = await discoverWithSession(
    expiredSession,
    configWithOnly('playlists'),
    { deadlineAtMs: Date.now() - 1 },
  );
  assert.equal(expired.kind, 'blocked');
  if (expired.kind === 'blocked') {
    assert.deepEqual(expired.snapshot.aggregate.warningCodes, [
      'FACET_DISCOVERY_TIMEOUT',
      'FACET_EMPTY',
      'FACET_UNAVAILABLE',
    ]);
  }
  assert.equal(expiredCalls, 0);
});

test('facet-count timeout preserves prior tags and never starts later recovery calls', async () => {
  const itemQueries: unknown[] = [];
  const session = emptySession([movieLibrary()]);
  session.listTagDirectoryPage = async (request) => ({
    entries: [
      { key: 'ready', title: 'Ready tag', count: 5 },
      { key: 'times-out', title: 'Timeout tag', count: null },
      { key: 'must-not-run', title: 'Later tag', count: null },
    ],
    offset: request.offset,
    totalSize: 3,
  });
  session.listLibraryItemsPage = async (request) => {
    itemQueries.push(request.query);
    throw new LivePlexTransportError('timeout', 'fixed timeout', undefined, {
      retryable: true,
    });
  };

  const result = await discoverWithSession(session, configWithOnly('genres'));
  assert.equal(result.kind, 'slow');
  if (result.kind === 'slow') {
    assert.deepEqual(result.snapshot.tags.map((tag) => tag.displayTitle), ['Ready tag']);
    assert.deepEqual(result.snapshot.aggregate.warningCodes, [
      'FACET_DISCOVERY_TIMEOUT',
      'FACET_PARTIAL_FAILURE',
    ]);
    assert.equal(result.snapshot.aggregate.omittedMalformedCount, 0);
    assert.equal(result.snapshot.aggregate.omittedCappedCount, 0);
  }
  assert.equal(itemQueries.length, 1);
  assert.deepEqual(itemQueries[0], {
    kind: 'facet-count',
    mediaType: 1,
    family: 'genre',
    key: 'times-out',
    tagValue: 'Timeout tag',
    fastKey: null,
  });
});

test('paging propagates context and Plex-required sentinels to exact failed results', async () => {
  for (const [code, retryable] of [
    ['CHANNEL_CONTEXT_CHANGED', true],
    ['CHANNEL_PLEX_REQUIRED', false],
  ] as const) {
    let calls = 0;
    const session = emptySession([movieLibrary()]);
    session.listServerPlaylistsPage = async () => {
      calls += 1;
      throw Object.assign(new Error('fixed safe sentinel'), { code });
    };
    const result = await discoverWithSession(session, configWithOnly('playlists'));
    assert.deepEqual(result, {
      kind: 'failed',
      snapshot: null,
      materializationIndex: null,
      error: { code, retryable },
    });
    assert.equal(calls, 1);
    assert.equal(JSON.stringify(result).includes('fixed safe sentinel'), false);
  }
});

test('authentication, network, caller abort, malformed source, and aggregate states map safely', async () => {
  for (const code of ['auth-required', 'auth-invalid'] as const) {
    const result = await discoverWithAccessError(
      new LivePlexTransportError(code, 'unsafe detail'),
    );
    assert.deepEqual(result, {
      kind: 'failed',
      snapshot: null,
      materializationIndex: null,
      error: { code: 'CHANNEL_PLEX_REQUIRED', retryable: false },
    });
  }
  const network = await discoverWithAccessError(
    new LivePlexTransportError('server-unreachable', 'unsafe host', undefined, {
      retryable: true,
    }),
  );
  assert.equal(network.kind, 'failed');
  if (network.kind === 'failed') {
    assert.deepEqual(network.error, { code: 'CHANNEL_UNKNOWN', retryable: true });
    assert.equal(JSON.stringify(network).includes('unsafe'), false);
  }

  const controller = new AbortController();
  controller.abort();
  const canceled = await discoverWithSession(
    emptySession([movieLibrary()]),
    configWithOnly('playlists'),
    { signal: controller.signal },
  );
  assert.deepEqual(canceled, {
    kind: 'canceled',
    snapshot: null,
    materializationIndex: null,
  });

  const malformedSession = emptySession([movieLibrary()]);
  malformedSession.listServerPlaylistsPage = async () => ({
    entries: [{ ...playlist(0), ratingKey: '' }],
    offset: 0,
    totalSize: 1,
  });
  const malformed = await discoverWithSession(
    malformedSession,
    configWithOnly('playlists'),
  );
  assert.equal(malformed.kind, 'blocked');
  if (malformed.kind === 'blocked') {
    assert.equal(malformed.snapshot.aggregate.omittedMalformedCount, 1);
    assert.deepEqual(malformed.snapshot.aggregate.warningCodes, [
      'FACET_EMPTY',
      'FACET_MALFORMED_ENTRIES_OMITTED',
    ]);
  }

  const readySession = emptySession([movieLibrary()]);
  readySession.listServerPlaylistsPage = async () => playlistPage(0, 1, 1);
  const ready = await discoverWithSession(readySession, configWithOnly('playlists'));
  assert.equal(ready.kind, 'ready');
  const empty = await discoverWithSession(
    emptySession([movieLibrary()]),
    configWithOnly('playlists'),
  );
  assert.equal(empty.kind, 'blocked');
});

test('real transport and parser preserve 401, 403, and malformed listing distinctions', async () => {
  for (const [status, code] of [
    [401, 'auth-required'],
    [403, 'auth-invalid'],
  ] as const) {
    const transport = new LivePlexTransport({
      fetch: async () => new Response('', { status }),
    });
    await assert.rejects(
      () => transport.listServerPlaylistsPage({
        connection,
        token: placeholderCredential,
        offset: 0,
        limit: 100,
        signal,
      }),
      (error: unknown) =>
        error instanceof LivePlexTransportError &&
        error.code === code &&
        error.httpStatus === status,
    );
  }

  const session = createChannelBuilderFacetSession(
    {
      facetTransport: {
        ...createFacetTransport([]),
        async listServerPlaylistsPage() {
          return {
            kind: 'json',
            data: { MediaContainer: { Metadata: [], offset: -1, totalSize: 0 } },
          };
        },
      },
      itemTransport: createLegacyTransport(),
    },
    { connection, token: placeholderCredential, libraries: [movieLibrary()] },
  );
  await assert.rejects(
    () => session.listServerPlaylistsPage({ offset: 0, limit: 100, signal }),
    (error: unknown) =>
      error instanceof Error &&
      error.message === 'Invalid channel builder playlists offset',
  );
});

test('discovery applies exact tag family and media-type mappings for movie and show libraries', async () => {
  const libraries = [movieLibrary(), showLibrary()];
  const requests: Array<{ sectionId: string; family: string; mediaType: number }> = [];
  const session = emptySession(libraries);
  session.listTagDirectoryPage = async (request) => {
    requests.push({
      sectionId: request.sectionId,
      family: request.family,
      mediaType: request.mediaType,
    });
    return { entries: [], offset: request.offset, totalSize: 0 };
  };
  const result = await discoverWithSession(
    session,
    configWithEnabled(['genres', 'directors', 'decades', 'studios', 'actors'], libraries),
  );
  assert.equal(result.kind, 'blocked');
  assert.deepEqual(requests, [
    { sectionId: '1', family: 'genre', mediaType: 1 },
    { sectionId: '1', family: 'director', mediaType: 1 },
    { sectionId: '1', family: 'year', mediaType: 1 },
    { sectionId: '1', family: 'studio', mediaType: 1 },
    { sectionId: '1', family: 'actor', mediaType: 1 },
    { sectionId: '2', family: 'genre', mediaType: 2 },
    { sectionId: '2', family: 'director', mediaType: 4 },
    { sectionId: '2', family: 'year', mediaType: 4 },
    { sectionId: '2', family: 'actor', mediaType: 4 },
  ]);
});

test('session boundary rejects unknown keys, invalid media mappings, and caller-controlled request data', async () => {
  const session = createChannelBuilderFacetSession(
    {
      facetTransport: createFacetTransport([]),
      itemTransport: createLegacyTransport(),
    },
    { connection, token: placeholderCredential, libraries: [movieLibrary(), showLibrary()] },
  );
  assert.deepEqual(Object.keys(session).sort(), [
    'libraries',
    'listCollectionsPage',
    'listLibraryItemsPage',
    'listServerPlaylistsPage',
    'listTagDirectoryPage',
  ]);
  assert.equal('request' in session, false);
  assert.equal('headers' in session, false);
  assert.equal('path' in session, false);

  await assert.rejects(() => session.listCollectionsPage({
    sectionId: '1',
    offset: 0,
    limit: 100,
    signal,
    path: '/caller-controlled',
  } as never));
  await assert.rejects(() => session.listTagDirectoryPage({
    sectionId: '2',
    family: 'genre',
    mediaType: 4,
    offset: 0,
    limit: 100,
    signal,
  }));
  await assert.rejects(() => session.listLibraryItemsPage({
    sectionId: '1',
    query: { kind: 'recently-added', mediaType: 2 },
    offset: 0,
    limit: 100,
    signal,
  }));
  await assert.rejects(() => session.listLibraryItemsPage({
    sectionId: '1',
    query: { kind: 'tv-people-index', sort: 'caller:desc' },
    offset: 0,
    limit: 100,
    signal,
  } as never));
  await assert.rejects(() => session.listLibraryItemsPage({
    sectionId: 'missing',
    query: { kind: 'facet-count', mediaType: 1, family: 'genre', key: 'k', tagValue: 'v', fastKey: null },
    offset: 0,
    limit: 100,
    signal,
  }));
});

test('tag semantics, mapping, and cap survivors are invariant across display projection', async () => {
  const calls: unknown[] = [];
  const session = emptySession([movieLibrary()]);
  session.listTagDirectoryPage = async (request) => ({
    entries: [
      { key: 'b', title: 'Authorization: Bearer hidden', count: 5 },
      { key: 'a', title: 'Visible', count: 10 },
    ],
    offset: request.offset,
    totalSize: 2,
  });
  session.listLibraryItemsPage = async (request) => {
    calls.push(request.query);
    return { entries: [], offset: request.offset, totalSize: 10 };
  };
  const result = await discoverWithSession(session, configWithOnly('genres'));
  assert.equal(result.kind, 'ready');
  if (result.kind === 'ready') {
    assert.deepEqual(result.snapshot.tags.map((tag) => tag.itemCount), [10, 5]);
    assert.deepEqual(result.snapshot.tags.map((tag) => tag.displayTitle), [
      'Visible',
      '[redacted]',
    ]);
    const serialized = JSON.stringify(result.snapshot);
    assert.equal(serialized.includes('Bearer hidden'), false);
    assert.equal(serialized.includes('"key"'), false);
    assert.equal(serialized.includes('uuid-'), false);
    assert.equal(serialized.includes(placeholderCredential), false);
  }
  assert.equal(calls.length, 0);
});

test('director references and inline decade filters materialize only against matching retained facets', async () => {
  const session = emptySession([movieLibrary()]);
  session.listTagDirectoryPage = async (request) => ({
    entries: [{
      key: `${request.family}-locator`,
      title: request.family === 'director' ? 'Jane Director' : '1994',
      count: 20,
    }],
    offset: request.offset,
    totalSize: 1,
  });
  const result = await discoverWithSession(
    session,
    configWithEnabled(['directors', 'decades']),
  );
  assert.equal(result.kind, 'ready');
  if (result.kind !== 'ready') return;
  const library = result.snapshot.libraries[0]!;
  const director = result.snapshot.tags.find((tag) => tag.family === 'director')!;
  const year = result.snapshot.tags.find((tag) => tag.family === 'year')!;

  const directorCandidate = candidateFor(
    {
      kind: 'facet',
      facetId: library.facetId,
      sourceIdentity: library.sourceIdentity,
    },
    result.snapshot.context,
    'directors',
    {
      kind: 'main-index-reference',
      facetId: director.facetId,
      contentFilterIdentity: director.contentFilterIdentity,
    },
  );
  const directorResult = await result.materializationIndex.materialize({
    candidate: directorCandidate,
    expectedContext: result.snapshot.context,
    signal,
  });
  assert.equal(directorResult.status, 'ready');
  if (directorResult.status === 'ready') {
    assert.deepEqual(directorResult.createInput.contentSource, {
      type: 'library',
      libraryId: '1',
      libraryType: 'movie',
      includeWatched: true,
    });
    assert.deepEqual(directorResult.createInput.contentFilters, [{
      field: 'director',
      operator: 'eq',
      value: 'Jane Director',
    }]);
  }

  const decadeFilters = [
    { field: 'year' as const, operator: 'gte' as const, value: 1990 },
    { field: 'year' as const, operator: 'lte' as const, value: 1999 },
  ];
  const decadeIdentity = createContentFilterIdentity({
    profileBinding: result.snapshot.context.profileBinding,
    serverBinding: result.snapshot.context.serverBinding,
    filters: decadeFilters,
  })!;
  const decadeCandidate = candidateFor(
    { kind: 'facet', facetId: year.facetId, sourceIdentity: year.sourceIdentity },
    result.snapshot.context,
    'decades',
    { kind: 'inline', contentFilterIdentity: decadeIdentity, filters: decadeFilters },
  );
  const decadeResult = await result.materializationIndex.materialize({
    candidate: decadeCandidate,
    expectedContext: result.snapshot.context,
    signal,
  });
  assert.equal(decadeResult.status, 'ready');
  if (decadeResult.status === 'ready') {
    assert.deepEqual(decadeResult.createInput.contentFilters, decadeFilters);
  }

  const missing = candidateFor(
    { kind: 'facet', facetId: `year:${'f'.repeat(64)}`, sourceIdentity: year.sourceIdentity },
    result.snapshot.context,
    'decades',
  );
  assert.equal((await result.materializationIndex.materialize({
    candidate: missing,
    expectedContext: result.snapshot.context,
    signal,
  })).status, 'skipped');
  const mismatched = candidateFor(
    { kind: 'facet', facetId: year.facetId, sourceIdentity: director.sourceIdentity },
    result.snapshot.context,
    'decades',
  );
  const mismatchResult = await result.materializationIndex.materialize({
    candidate: mismatched,
    expectedContext: result.snapshot.context,
    signal,
  });
  assert.equal(mismatchResult.status, 'failed');
  if (mismatchResult.status === 'failed') {
    assert.equal(mismatchResult.reason, 'source-member-mismatch');
  }
  const wrongFamilyReference = candidateFor(
    { kind: 'facet', facetId: library.facetId, sourceIdentity: library.sourceIdentity },
    result.snapshot.context,
    'directors',
    {
      kind: 'main-index-reference',
      facetId: year.facetId,
      contentFilterIdentity: director.contentFilterIdentity,
    },
  );
  const wrongFamily = await result.materializationIndex.materialize({
    candidate: wrongFamilyReference,
    expectedContext: result.snapshot.context,
    signal,
  });
  assert.equal(wrongFamily.status, 'failed');
  if (wrongFamily.status === 'failed') assert.equal(wrongFamily.reason, 'invalid-materialization');
});

test('playlist and collection materialization uses ratingKey rather than locator key and excludes manual/item facets', async () => {
  const session = emptySession([movieLibrary()]);
  session.listServerPlaylistsPage = async () => ({
    entries: [{
      ratingKey: 'playlist-rating',
      key: '/playlist/locator',
      title: 'Playlist',
      thumb: null,
      duration: 100,
      leafCount: 4,
    }],
    offset: 0,
    totalSize: 1,
  });
  session.listCollectionsPage = async () => ({
    entries: [{
      ratingKey: 'collection-rating',
      key: '/collection/locator',
      title: 'Collection',
      thumb: null,
      childCount: 4,
    }],
    offset: 0,
    totalSize: 1,
  });
  const result = await discoverWithSession(
    session,
    configWithEnabled(['playlists', 'collections']),
  );
  assert.equal(result.kind, 'ready');
  if (result.kind !== 'ready') return;
  assert.equal('items' in result.snapshot, false);
  for (const [facet, expected] of [
    [result.snapshot.playlists[0]!, { type: 'playlist', playlistKey: 'playlist-rating', playlistName: 'Playlist' }],
    [result.snapshot.collections[0]!, { type: 'collection', collectionKey: 'collection-rating', collectionName: 'Collection' }],
  ] as const) {
    const candidate = candidateFor(
      { kind: 'facet', facetId: facet.facetId, sourceIdentity: facet.sourceIdentity },
      result.snapshot.context,
      facet === result.snapshot.playlists[0] ? 'playlists' : 'collections',
    );
    const materialized = await result.materializationIndex.materialize({
      candidate,
      expectedContext: result.snapshot.context,
      signal,
    });
    assert.equal(materialized.status, 'ready');
    if (materialized.status === 'ready') {
      assert.deepEqual(materialized.createInput.contentSource, expected);
    }
  }
  const manual = candidateFor(
    {
      kind: 'manual',
      sourceIdentity: result.snapshot.libraries[0]!.sourceIdentity,
      items: [{
        kind: 'facet',
        facetId: null,
        sourceIdentity: result.snapshot.libraries[0]!.sourceIdentity,
      }],
    },
    result.snapshot.context,
    'playlists',
  );
  const manualResult = await result.materializationIndex.materialize({
    candidate: manual,
    expectedContext: result.snapshot.context,
    signal,
  });
  assert.equal(manualResult.status, 'failed');
});

test('section listing rejects missing UUID and duplicate ID/pair ownership and listSections delegates once', async () => {
  for (const directories of [
    [rawLibrary('1', '', 'Movies', 'movie')],
    [
      rawLibrary('1', 'uuid-a', 'Movies', 'movie'),
      rawLibrary('1', 'uuid-b', 'Other', 'movie'),
    ],
  ]) {
    let calls = 0;
    const executor = new DesktopPlexLibraryOperationExecutor(createLegacyTransport({
      async listLibrarySections() {
        calls += 1;
        return { kind: 'json', data: { MediaContainer: { Directory: directories } } };
      },
    }));
    await assert.rejects(() => executor.listSectionsForMain({
      connection,
      token: placeholderCredential,
      signal,
    }));
    assert.equal(calls, 1);
  }

  let delegateCalls = 0;
  const executor = new DesktopPlexLibraryOperationExecutor(createLegacyTransport({
    async listLibrarySections() {
      delegateCalls += 1;
      return {
        kind: 'json',
        data: { MediaContainer: { Directory: [rawLibrary('1', 'uuid-a', 'Movies', 'movie')] } },
      };
    },
  }));
  const sections = await executor.listSections({ connection, token: placeholderCredential, signal });
  assert.equal(delegateCalls, 1);
  assert.equal(sections.length, 1);
  assert.equal(JSON.stringify(sections).includes('uuid-a'), false);

  const sharedUuidExecutor = new DesktopPlexLibraryOperationExecutor(createLegacyTransport({
    async listLibrarySections() {
      return {
        kind: 'json',
        data: {
          MediaContainer: {
            Directory: [
              rawLibrary('1', 'shared-uuid', 'Movies', 'movie'),
              rawLibrary('2', 'shared-uuid', 'Other', 'movie'),
            ],
          },
        },
      };
    },
  }));
  const sharedUuid = await sharedUuidExecutor.listSectionsForMain({
    connection,
    token: placeholderCredential,
    signal,
  });
  assert.deepEqual(sharedUuid.libraryPairs, [
    { libraryId: '1', libraryUuid: 'shared-uuid' },
    { libraryId: '2', libraryUuid: 'shared-uuid' },
  ]);
});

function emptySession(libraries: readonly PlexLibrarySection[]): ChannelBuilderFacetSession {
  return {
    libraries,
    async listCollectionsPage(request) {
      return { entries: [], offset: request.offset, totalSize: 0 };
    },
    async listServerPlaylistsPage(request) {
      return { entries: [], offset: request.offset, totalSize: 0 };
    },
    async listTagDirectoryPage(request) {
      return { entries: [], offset: request.offset, totalSize: 0 };
    },
    async listLibraryItemsPage(request) {
      return { entries: [], offset: request.offset, totalSize: 0 };
    },
  };
}

async function discoverWithSession(
  session: ChannelBuilderFacetSession,
  config: ReturnType<typeof configWithOnly>,
  overrides: Partial<{
    deadlineAtMs: number;
    signal: AbortSignal;
  }> = {},
) {
  const accessPort: ChannelBuilderFacetAccessPort = {
    async withSession(_input, run) {
      try {
        return await run(session);
      } finally {
        invalidateChannelBuilderFacetSession(session);
      }
    },
  };
  return new DesktopPlexChannelBuilderFacetSource(accessPort).discover({
    normalizedConfig: config,
    context: contextForLibraries(session.libraries),
    deadlineAtMs: overrides.deadlineAtMs ?? Date.now() + 60_000,
    signal: overrides.signal ?? signal,
  });
}

async function discoverWithAccessError(error: Error) {
  const accessPort: ChannelBuilderFacetAccessPort = {
    async withSession() {
      throw error;
    },
  };
  return new DesktopPlexChannelBuilderFacetSource(accessPort).discover({
    normalizedConfig: configWithOnly('playlists'),
    context: builderContext(),
    deadlineAtMs: Date.now() + 60_000,
    signal,
  });
}

function playlistPage(offset: number, count: number, totalSize: number | null) {
  return {
    entries: Array.from({ length: count }, (_, index) => playlist(offset + index)),
    offset,
    totalSize,
  };
}

function playlist(index: number) {
  return {
    ratingKey: `playlist-rating-${index}`,
    key: `/playlist/locator/${index}`,
    title: `Playlist ${index}`,
    thumb: null,
    duration: 1_000,
    leafCount: 10,
  };
}

function candidateFor(
  sourceReference: ChannelBuilderSafeSourceReference,
  context: ChannelBuilderContextBinding,
  strategy: ChannelBuilderStrategyKey,
  contentFilterPlan: ChannelBuilderCandidateDraft['contentFilterPlan'] = {
    kind: 'none',
    contentFilterIdentity: null,
  },
): ChannelBuilderCandidateDraft {
  const origin = {
    profileBinding: context.profileBinding,
    serverBinding: context.serverBinding,
    librarySetBinding: context.librarySetBinding,
  };
  return {
    candidateId: `candidate:${'c'.repeat(64)}`,
    candidateIdentity: createCandidateIdentity({
      origin,
      sourceReference,
      contentFilterIdentity: contentFilterPlan.contentFilterIdentity,
      sortOrder: null,
      lineupReplicaIndex: 0,
      isPlaybackModeVariant: false,
      playbackMode: 'shuffle',
      blockSize: null,
    }),
    origin,
    strategy,
    displayName: 'Generated channel',
    sourceReference,
    estimatedItemCount: 10,
    playbackMode: 'shuffle',
    shuffleSeed: 42,
    contentFilterPlan,
    sortOrder: null,
    blockSize: null,
    buildStrategy: strategy,
    sourceLibraryId: null,
    sourceLibraryName: null,
    lineupReplicaIndex: 0,
    isPlaybackModeVariant: false,
  };
}

function createDiscoverySession(
  rawTitle: string,
  itemQueries: unknown[],
): ChannelBuilderFacetSession {
  return {
    libraries: [movieLibrary()],
    async listCollectionsPage() {
      return { entries: [], offset: 0, totalSize: 0 };
    },
    async listServerPlaylistsPage() {
      return { entries: [], offset: 0, totalSize: 0 };
    },
    async listTagDirectoryPage(request) {
      assert.equal(request.family, 'genre');
      assert.equal(request.mediaType, 1);
      return {
        entries: [{
          key: 'genre-raw-key',
          title: rawTitle,
          count: null,
        }],
        offset: 0,
        totalSize: 1,
      };
    },
    async listLibraryItemsPage(request) {
      itemQueries.push(request.query);
      return { entries: [], offset: request.offset, totalSize: 12 };
    },
  };
}

function builderContext(): ChannelBuilderContextBinding {
  return contextForLibraries([movieLibrary()]);
}

function contextForLibraries(
  libraries: readonly PlexLibrarySection[],
): ChannelBuilderContextBinding {
  return {
    contextEpoch: 4,
    profileBinding: createProfileBinding('profile-1'),
    serverBinding: createServerBinding('server-1'),
    librarySetBinding: createLibrarySetBinding(libraries.map((library) => ({
      libraryId: library.id,
      libraryUuid: library.uuid,
    }))),
  };
}

function configWithOnly(enabled: ChannelBuilderStrategyKey) {
  return configWithEnabled([enabled]);
}

function configWithEnabled(
  enabled: readonly ChannelBuilderStrategyKey[],
  libraries: readonly PlexLibrarySection[] = [movieLibrary()],
) {
  const created = createDefaultChannelSetupConfig({
    serverId: 'server-1',
    selectedLibraryIds: libraries.map((library) => library.id),
  });
  assert.equal(created.ok, true);
  if (!created.ok) throw new Error('fixture config failed');
  return {
    ...created.config,
    strategyConfig: Object.fromEntries(
      Object.entries(created.config.strategyConfig).map(([key, value]) => [
        key,
        { ...value, enabled: enabled.includes(key as ChannelBuilderStrategyKey) },
      ]),
    ) as typeof created.config.strategyConfig,
  };
}

function movieLibrary(): PlexLibrarySection {
  return movieLibraryWith('1', 'library-uuid-1');
}

function movieLibraryWith(id: string, uuid: string): PlexLibrarySection {
  return {
    id,
    uuid,
    title: `Movies ${id}`,
    type: 'movie',
    agent: 'agent',
    scanner: 'scanner',
    contentCount: 25,
    lastScannedAt: new Date(0),
    art: null,
    thumb: null,
  };
}

function showLibrary(): PlexLibrarySection {
  return {
    ...movieLibrary(),
    id: '2',
    uuid: 'library-uuid-2',
    title: 'Shows',
    type: 'show',
  };
}

function createFacetTransport(calls: string[]): LivePlexChannelBuilderFacetTransport {
  return {
    async listCollectionsPage(input) {
      calls.push('collections');
      return { kind: 'json', data: { MediaContainer: { offset: input.offset, totalSize: 0 } } };
    },
    async listServerPlaylistsPage(input) {
      calls.push('playlists');
      return { kind: 'json', data: { MediaContainer: { offset: input.offset, totalSize: 0 } } };
    },
    async listTagDirectoryPage(input) {
      calls.push('tags');
      return { kind: 'json', data: { MediaContainer: { offset: input.offset, totalSize: 0 } } };
    },
  };
}

function createLegacyTransport(
  overrides: Partial<LivePlexLibraryTransport> = {},
): LivePlexLibraryTransport {
  const payload = async () => ({ kind: 'json' as const, data: { MediaContainer: {} } });
  return {
    listLibrarySections: payload,
    async listLibraryItems(input) {
      return {
        kind: 'json',
        data: { MediaContainer: { totalSize: 0, offset: input.offset, Metadata: [] } },
      };
    },
    searchLibrary: payload,
    getMetadata: payload,
    getCollectionItems: payload,
    getShowEpisodes: payload,
    getPlaylistItems: payload,
    async stopTranscodeSession() {},
    ...overrides,
  };
}

function rawLibrary(id: string, uuid: string, title: string, type: 'movie' | 'show') {
  return {
    key: id,
    uuid,
    title,
    type,
    agent: 'agent',
    scanner: 'scanner',
  };
}

function jsonResponse(data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}
