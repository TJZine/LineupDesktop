import test from 'node:test';
import assert from 'node:assert/strict';

import {
  auditChannelDomainValueForForbiddenFields,
  ChannelError,
  ChannelManager,
  ChannelResolutionCache,
  ContentSelectionPolicy,
  ContentResolver,
  isValidContentSource,
  SourceResolutionCache,
} from '../domain/channel/index.js';
import { applyPlaybackOrdering } from '../domain/scheduler/shared/playbackOrdering.js';
import { shuffleWithSeed } from '../domain/scheduler/shared/prng.js';
import type {
  ChannelAbortSignal,
  ChannelClock,
  ChannelTimerHandle,
  ChannelTimerPort,
  ChannelPersistencePort,
  IPlexLibraryMinimal,
  PlexMediaItemMinimal,
} from '../domain/channel/index.js';
import type {
  ChannelConfig,
  ChannelContentSource,
  ResolvedContentItem,
} from '../domain/channel/index.js';

class FakeClock implements ChannelClock {
  public currentTime: number;

  public constructor(initialTime: number) {
    this.currentTime = initialTime;
  }

  public now(): number {
    return this.currentTime;
  }
}

class FakeTimers implements ChannelTimerPort {
  public readonly handlers = new Map<ChannelTimerHandle, () => void>();
  public clearCount = 0;
  private nextHandle = 1;

  public setTimeout(handler: () => void): ChannelTimerHandle {
    const handle = this.nextHandle;
    this.nextHandle++;
    this.handlers.set(handle, handler);
    return handle;
  }

  public clearTimeout(handle: ChannelTimerHandle): void {
    this.handlers.delete(handle);
    this.clearCount++;
  }

  public tickAll(): void {
    for (const handler of [...this.handlers.values()]) {
      handler();
    }
  }
}

class FakeLibrary implements IPlexLibraryMinimal {
  public libraryItems = new Map<string, PlexMediaItemMinimal[]>();
  public collectionItems = new Map<string, PlexMediaItemMinimal[]>();
  public showEpisodes = new Map<string, PlexMediaItemMinimal[]>();
  public playlistItems = new Map<string, PlexMediaItemMinimal[]>();
  public libraryCalls = 0;
  public failure: unknown = null;

  public async getLibraryItems(
    libraryId: string,
    options?: { filter?: Record<string, string | number> },
  ): Promise<PlexMediaItemMinimal[]> {
    this.libraryCalls++;
    if (this.failure) throw this.failure;
    if (options?.filter?.type === 'episode') {
      return this.showEpisodes.get(libraryId) ?? [];
    }
    return this.libraryItems.get(libraryId) ?? [];
  }

  public async getCollectionItems(collectionKey: string): Promise<PlexMediaItemMinimal[]> {
    if (this.failure) throw this.failure;
    return this.collectionItems.get(collectionKey) ?? [];
  }

  public async getShowEpisodes(showKey: string): Promise<PlexMediaItemMinimal[]> {
    if (this.failure) throw this.failure;
    return this.showEpisodes.get(showKey) ?? [];
  }

  public async getPlaylistItems(playlistKey: string): Promise<PlexMediaItemMinimal[]> {
    if (this.failure) throw this.failure;
    return this.playlistItems.get(playlistKey) ?? [];
  }

  public async getItem(): Promise<PlexMediaItemMinimal | null> {
    return null;
  }
}

class Deferred<T> {
  public readonly promise: Promise<T>;
  private resolveValue: ((value: T) => void) | null = null;
  private rejectValue: ((error: unknown) => void) | null = null;

  public constructor() {
    this.promise = new Promise<T>((resolve, reject) => {
      this.resolveValue = resolve;
      this.rejectValue = reject;
    });
  }

  public resolve(value: T): void {
    assert.ok(this.resolveValue, 'deferred already settled');
    this.resolveValue(value);
    this.resolveValue = null;
    this.rejectValue = null;
  }

  public reject(error: unknown): void {
    assert.ok(this.rejectValue, 'deferred already settled');
    this.rejectValue(error);
    this.resolveValue = null;
    this.rejectValue = null;
  }
}

function movie(ratingKey: string, title = ratingKey, durationMs = 60_000): PlexMediaItemMinimal {
  return {
    ratingKey,
    type: 'movie',
    title,
    year: 2024,
    durationMs,
    thumb: null,
    genres: ['Drama'],
    directors: ['Director'],
    addedAtMs: 10,
  };
}

function episode(
  ratingKey: string,
  showTitle: string,
  seasonNumber: number,
  episodeNumber: number,
): PlexMediaItemMinimal {
  return {
    ratingKey,
    type: 'episode',
    title: `Episode ${String(episodeNumber)}`,
    year: 2024,
    durationMs: 30_000,
    thumb: null,
    grandparentTitle: showTitle,
    seasonNumber,
    episodeNumber,
  };
}

function librarySource(libraryId = 'lib'): ChannelContentSource {
  return {
    type: 'library',
    libraryId,
    libraryType: 'movie',
    includeWatched: true,
  };
}

function createManager(options: {
  clock?: FakeClock;
  timers?: FakeTimers;
  library?: FakeLibrary;
  persistence?: ChannelPersistencePort;
} = {}): { manager: ChannelManager; clock: FakeClock; library: FakeLibrary; timers?: FakeTimers } {
  const clock = options.clock ?? new FakeClock(1_000);
  const library = options.library ?? new FakeLibrary();
  const timers = options.timers;
  let nextId = 1;
  const manager = new ChannelManager({
    plexLibrary: library,
    clock,
    timers,
    generateId: () => `channel-${String(nextId++)}`,
    persistence: options.persistence,
  });
  return { manager, clock, library, timers };
}

test('channel domain validates content sources and rejects malformed channel authoring input', async () => {
  assert.equal(isValidContentSource(librarySource()), true);
  assert.equal(
    isValidContentSource({
      ...librarySource(),
      libraryFilter: { authHeaders: 'blocked' },
    }),
    false,
  );
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10 }],
    }),
    true,
  );
  assert.equal(isValidContentSource({ type: 'library', libraryId: 'undefined' }), false);

  const { manager, library } = createManager();
  library.libraryItems.set('lib', [movie('m1')]);

  const first = await manager.createChannel({
    number: 7,
    name: 'Movies',
    contentSource: librarySource(),
  });
  assert.equal(first.number, 7);
  assert.equal(first.itemCount, 1);
  assert.equal(first.totalDurationMs, 60_000);

  await assert.rejects(
    () => manager.createChannel({ number: 7, contentSource: librarySource() }),
    { name: 'ChannelError', code: 'DUPLICATE_CHANNEL_NUMBER' },
  );
  await assert.rejects(
    () => manager.createChannel({ number: 0, contentSource: librarySource() }),
    { name: 'ChannelError', code: 'INVALID_CHANNEL_NUMBER' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: { type: 'library' } as ChannelContentSource }),
    { name: 'ChannelError', code: 'CHANNEL_CONTENT_SOURCE_INVALID' },
  );
});

test('channel domain preserves current next previous lookup and transactional reorder/update behavior', async () => {
  const saves: unknown[] = [];
  const { manager, library } = createManager({
    persistence: {
      load: async () => null,
      save: async (data: unknown) => {
        saves.push(data);
      },
    },
  });
  library.libraryItems.set('lib', [movie('m1')]);

  const one = await manager.createChannel({ number: 1, name: 'One', contentSource: librarySource() });
  const two = await manager.createChannel({ number: 2, name: 'Two', contentSource: librarySource() });
  const three = await manager.createChannel({ number: 3, name: 'Three', contentSource: librarySource() });

  manager.setCurrentChannel(two.id);
  assert.equal(manager.getCurrentChannel()?.id, two.id);
  assert.equal(manager.getNextChannel()?.id, three.id);
  assert.equal(manager.getPreviousChannel()?.id, one.id);

  await assert.rejects(
    () => manager.reorderChannels([three.id, two.id]),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), [one.id, two.id, three.id]);

  await manager.reorderChannels([three.id, two.id, one.id]);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), [three.id, two.id, one.id]);

  await assert.rejects(
    () => manager.updateChannel(two.id, { number: three.number }),
    { name: 'ChannelError', code: 'DUPLICATE_CHANNEL_NUMBER' },
  );
  assert.equal(manager.getChannel(two.id)?.number, 2);
  assert.ok(saves.length >= 4);
});

test('channel domain normalizes imports and replaces duplicate channel numbers', async () => {
  const { manager, library } = createManager();
  library.libraryItems.set('lib', [movie('m1')]);

  await manager.createChannel({ number: 1, name: 'Existing', contentSource: librarySource() });
  const result = await manager.importChannels(JSON.stringify([
    { number: 1, name: 'Imported duplicate', contentSource: librarySource() },
    { name: 'Imported next', contentSource: librarySource() },
    { name: 'Invalid source', contentSource: { type: 'library' } },
  ]));

  assert.equal(result.success, true);
  assert.equal(result.importedCount, 2);
  assert.equal(result.skippedCount, 1);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.number), [1, 2, 3]);
  assert.deepEqual(
    manager.getAllChannels().map((channel) => channel.name),
    ['Existing', 'Imported duplicate', 'Imported next'],
  );

  const invalid = await manager.importChannels('{not-json');
  assert.equal(invalid.success, false);
  assert.deepEqual(invalid.errors, ['Import file is invalid']);
});

test('channel domain resolves content through injected library port and applies filters sorting and playback order', async () => {
  const { manager, library } = createManager();
  library.libraryItems.set('lib', [
    movie('short', 'Short', 10_000),
    movie('long', 'Long', 90_000),
    movie('middle', 'Middle', 45_000),
  ]);

  const channel = await manager.createChannel({
    contentSource: librarySource(),
    sortOrder: 'duration_desc',
    minEpisodeRunTimeMs: 20_000,
    playbackMode: 'sequential',
  });
  const content = await manager.resolveChannelContent(channel.id);

  assert.deepEqual(content.items.map((item) => item.ratingKey), ['long', 'middle']);
  assert.deepEqual(content.orderedItems.map((item) => item.ratingKey), ['long', 'middle']);
  assert.equal(content.fromCache, true);
  assert.equal(library.libraryCalls, 1);

  const cached = await manager.resolveChannelContent(channel.id);
  assert.equal(cached.fromCache, true);
  cached.items[0]!.genres?.push('mutated');
  const cachedAgain = await manager.resolveChannelContent(channel.id);
  assert.deepEqual(cachedAgain.items[0]!.genres, ['Drama']);
  assert.equal(library.libraryCalls, 1);
});

test('channel domain block playback follows shared scheduler grouping', () => {
  const items: ResolvedContentItem[] = [
    resolvedItem('dup-a', 'Duplicate'),
    resolvedItem('other', 'Other'),
    resolvedItem('dup-b', 'Duplicate'),
    {
      ...resolvedItem('ep1', 'Episode 1'),
      type: 'episode',
      fullTitle: 'Show A - Episode 1',
      showTitle: 'Show A',
      showThumb: 'thumb-a',
      seasonNumber: 1,
      episodeNumber: 1,
    },
    {
      ...resolvedItem('ep2', 'Episode 2'),
      type: 'episode',
      fullTitle: 'Show A - Episode 2',
      showTitle: 'Show A',
      showThumb: 'thumb-b',
      seasonNumber: 1,
      episodeNumber: 2,
    },
  ];

  const channelOrder = new ContentSelectionPolicy()
    .applyPlaybackMode(items, 'block', 1, 2)
    .map((item) => [item.ratingKey, item.scheduledIndex]);
  const schedulerOrder = applyPlaybackOrdering({
    items,
    mode: 'block',
    seed: 1,
    blockSize: 2,
    shuffleItems: shuffleWithSeed,
  }).map((item) => [item.ratingKey, item.scheduledIndex]);

  assert.deepEqual(channelOrder, schedulerOrder);
  assert.deepEqual(channelOrder, [
    ['ep2', 0],
    ['dup-b', 1],
    ['other', 2],
    ['dup-a', 3],
    ['ep1', 4],
  ]);
});

test('channel domain expands show content and mixed sources through injected ports only', async () => {
  const clock = new FakeClock(1_000);
  const library = new FakeLibrary();
  library.showEpisodes.set('show-1', [
    episode('e1', 'The Show', 1, 1),
    episode('e2', 'The Show', 1, 2),
  ]);
  const resolver = new ContentResolver(library, clock, { warn: () => undefined, error: () => undefined });

  const items = await resolver.resolveSource({
    type: 'mixed',
    mixMode: 'interleave',
    sources: [
      { type: 'manual', items: [{ ratingKey: 'manual', title: 'Manual', durationMs: 10_000 }] },
      { type: 'show', showKey: 'show-1', showName: 'The Show' },
    ],
  });

  assert.deepEqual(
    items.map((item) => item.fullTitle),
    ['Manual', 'The Show - S01E01 - Episode 1', 'The Show - S01E02 - Episode 2'],
  );
});

test('channel domain uses stale fallback for network errors and never falls back for access denied', async () => {
  const timers = new FakeTimers();
  const clock = new FakeClock(1_000);
  const { manager, library } = createManager({ clock, timers });
  library.libraryItems.set('lib', [movie('m1')]);

  const channel = await manager.createChannel({ contentSource: librarySource() });
  const initial = await manager.resolveChannelContent(channel.id);
  assert.equal(initial.fromCache, true);

  clock.currentTime += 2 * 60 * 60 * 1000;
  library.failure = new ChannelError('NETWORK_TIMEOUT', 'network timeout', true);
  const stale = await manager.resolveChannelContent(channel.id);
  assert.equal(stale.fromCache, true);
  assert.equal(stale.isStale, true);
  assert.equal(stale.cacheReason, 'network_error');
  assert.equal(timers.handlers.size, 1);

  library.failure = null;
  timers.tickAll();
  await Promise.resolve();
  await Promise.resolve();

  await manager.refreshChannelContent(channel.id);
  library.failure = new ChannelError('ACCESS_DENIED', 'forbidden', false, 403);
  await assert.rejects(
    () => manager.refreshChannelContent(channel.id),
    { name: 'ChannelError', code: 'ACCESS_DENIED' },
  );
  library.failure = new ChannelError('NETWORK_TIMEOUT', 'network timeout', true);
  await assert.rejects(
    () => manager.resolveChannelContent(channel.id),
    { name: 'ChannelError', code: 'NETWORK_TIMEOUT' },
  );
});

test('channel domain cache helpers clone entries and honor TTL through injected clock', async () => {
  const clock = new FakeClock(10);
  const channelCache = new ChannelResolutionCache(clock);
  channelCache.set({
    channelId: 'channel',
    resolvedAt: 10,
    items: [{
      ratingKey: 'm1',
      type: 'movie',
      title: 'Movie',
      fullTitle: 'Movie',
      durationMs: 10,
      thumb: null,
      year: 2024,
      scheduledIndex: 0,
      genres: ['Drama'],
    }],
    orderedItems: [],
    totalDurationMs: 10,
  });

  const clone = channelCache.get('channel');
  assert.ok(clone);
  clone.items[0]!.genres?.push('Changed');
  assert.deepEqual(channelCache.get('channel')?.items[0]?.genres, ['Drama']);
  assert.equal(channelCache.isFresh('channel'), true);
  clock.currentTime += 61 * 60 * 1000;
  assert.equal(channelCache.isFresh('channel'), false);

  const sourceCache = new SourceResolutionCache(clock);
  const source = librarySource();
  let calls = 0;
  const first = await sourceCache.resolve(source, async () => {
    calls++;
    return [{
      ratingKey: 'm2',
      type: 'movie',
      title: 'Movie 2',
      fullTitle: 'Movie 2',
      durationMs: 10,
      thumb: null,
      year: 2024,
      scheduledIndex: 0,
    }];
  });
  first[0]!.title = 'Mutated';
  const second = await sourceCache.resolve(source, async () => {
    calls++;
    return [];
  });
  assert.equal(calls, 1);
  assert.equal(second[0]?.title, 'Movie 2');
});

test('channel domain source cache aborts in-flight waiters and transport after invalidation', async () => {
  const clock = new FakeClock(10);
  const sourceCache = new SourceResolutionCache(clock);
  const source = librarySource();
  const deferred = new Deferred<ResolvedContentItem[]>();
  let transportSignal: ChannelAbortSignal | null = null;

  const pending = sourceCache.resolve(source, async (_source, options) => {
    transportSignal = options.signal;
    return deferred.promise;
  });
  const rejected = assert.rejects(pending, /Source resolution invalidated/);
  await Promise.resolve();
  const signal = assertPresentSignal(transportSignal);
  assert.equal(signal.aborted, false);
  sourceCache.invalidate(source);
  assert.equal(signal.aborted, true);
  await rejected;

  deferred.resolve([{
    ratingKey: 'late',
    type: 'movie',
    title: 'Late',
    fullTitle: 'Late',
    durationMs: 10,
    thumb: null,
    year: 2024,
    scheduledIndex: 0,
  }]);

  const fresh = await sourceCache.resolve(source, async () => [{
    ratingKey: 'fresh',
    type: 'movie',
    title: 'Fresh',
    fullTitle: 'Fresh',
    durationMs: 10,
    thumb: null,
    year: 2024,
    scheduledIndex: 0,
  }]);
  assert.equal(fresh[0]?.ratingKey, 'fresh');
});

test('channel domain source cache keeps caller abort local to shared in-flight waiters', async () => {
  const clock = new FakeClock(10);
  const sourceCache = new SourceResolutionCache(clock);
  const source = librarySource();
  const callerController = new AbortController();
  const deferred = new Deferred<ResolvedContentItem[]>();
  let calls = 0;
  let transportSignal: ChannelAbortSignal | null = null;

  const first = sourceCache.resolve(
    source,
    async (_source, options) => {
      calls++;
      transportSignal = options.signal;
      options.signal.addEventListener?.('abort', () => deferred.reject(new Error('transport aborted')));
      return deferred.promise;
    },
    { signal: callerController.signal },
  );
  const second = sourceCache.resolve(source, async () => {
    calls++;
    return [resolvedItem('unexpected')];
  });

  const firstRejected = assert.rejects(first, /Aborted/);
  await Promise.resolve();
  const signal = assertPresentSignal(transportSignal);
  callerController.abort();

  await firstRejected;
  assert.equal(signal.aborted, false);
  assert.equal(calls, 1);

  deferred.resolve([resolvedItem('shared')]);
  const secondItems = await second;
  assert.deepEqual(secondItems.map((item) => item.ratingKey), ['shared']);
  assert.equal(calls, 1);
});

test('channel domain source cache clear aborts in-flight waiters and transport', async () => {
  const clock = new FakeClock(10);
  const sourceCache = new SourceResolutionCache(clock);
  const deferred = new Deferred<ResolvedContentItem[]>();
  let transportSignal: ChannelAbortSignal | null = null;

  const pending = sourceCache.resolve(librarySource(), async (_source, options) => {
    transportSignal = options.signal;
    return deferred.promise;
  });
  const rejected = assert.rejects(pending, /Source resolution invalidated/);
  await Promise.resolve();
  const signal = assertPresentSignal(transportSignal);
  sourceCache.clear();

  assert.equal(signal.aborted, true);
  await rejected;
  deferred.resolve([resolvedItem('late')]);
});

test('channel domain does not reinsert stale resolved channels after replacement', async () => {
  const deferred = new Deferred<PlexMediaItemMinimal[]>();
  const library = new FakeLibrary();
  library.getLibraryItems = async () => deferred.promise;
  const { manager } = createManager({ library });
  const oldChannel = await manager.createChannel(
    { contentSource: librarySource() },
    { initialContent: [resolvedItem('seed')] },
  );

  const pendingRefresh = manager.refreshChannelContent(oldChannel.id);
  await manager.replaceAllChannels([completeChannel('replacement', 3)], {
    currentChannelId: 'replacement',
  });
  await assert.rejects(pendingRefresh, /Source resolution invalidated/);
  deferred.resolve([movie('late')]);

  assert.equal(manager.getChannel(oldChannel.id), null);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), ['replacement']);
});

test('channel domain does not reinsert a deleted channel after pending update resolution', async () => {
  const deferred = new Deferred<PlexMediaItemMinimal[]>();
  const library = new FakeLibrary();
  const { manager } = createManager({ library });
  const channel = await manager.createChannel(
    { contentSource: librarySource() },
    { initialContent: [resolvedItem('seed')] },
  );

  library.getLibraryItems = async () => deferred.promise;
  const pendingUpdate = manager.updateChannel(channel.id, {
    contentSource: librarySource('updated-lib'),
  });
  await manager.deleteChannel(channel.id);
  deferred.resolve([movie('late-update')]);

  const updated = await pendingUpdate;
  assert.equal(updated.id, channel.id);
  assert.equal(manager.getChannel(channel.id), null);
  assert.deepEqual(manager.getAllChannels(), []);
});

test('channel domain replaceAllChannels normalizes duplicate numbers and current selection atomically', async () => {
  const { manager } = createManager();
  const channelA = completeChannel('a', 9);
  const channelB = completeChannel('b', 9);
  const invalid = { ...completeChannel('bad', 10), contentSource: { type: 'library' } as ChannelContentSource };

  await manager.replaceAllChannels([channelA, channelB, invalid], { currentChannelId: 'b' });

  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), ['a', 'b']);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.number), [9, 1]);
  assert.equal(manager.getCurrentChannel()?.id, 'b');
});

test('channel domain safety audit catches forbidden renderer persistence fields in outputs and fixtures', async () => {
  const { manager, library } = createManager();
  library.libraryItems.set('lib', [movie('m1')]);
  const channel = await manager.createChannel({
    contentSource: {
      type: 'manual',
      items: [{
        ratingKey: 'manual-safe',
        title: 'Manual Safe',
        durationMs: 60_000,
        rawMediaUrl: 'blocked',
      }],
      tokenizedUrl: 'blocked',
    } as unknown as ChannelContentSource,
  });
  const content = await manager.resolveChannelContent(channel.id);

  assert.deepEqual(auditChannelDomainValueForForbiddenFields(channel), []);
  assert.deepEqual(auditChannelDomainValueForForbiddenFields(content), []);
  assert.deepEqual(auditChannelDomainValueForForbiddenFields({
    rawMediaUrl: 'blocked',
    nested: { localStorage: 'blocked' },
  }), [
    { path: '$', key: 'rawMediaUrl' },
    { path: '$.nested', key: 'localStorage' },
  ]);
});

function completeChannel(id: string, number: number): ChannelConfig {
  return {
    id,
    number,
    name: `Channel ${id}`,
    contentSource: librarySource(),
    playbackMode: 'sequential',
    startTimeAnchor: 1_000,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1_000,
    updatedAt: 1_000,
    lastContentRefresh: 0,
    itemCount: 0,
    totalDurationMs: 0,
  };
}

function resolvedItem(ratingKey: string, title = ratingKey): ResolvedContentItem {
  return {
    ratingKey,
    type: 'movie',
    title,
    fullTitle: title,
    durationMs: 10,
    thumb: null,
    year: 2024,
    scheduledIndex: 0,
  };
}

function assertPresentSignal(signal: ChannelAbortSignal | null): ChannelAbortSignal {
  assert.ok(signal, 'expected source cache to pass a transport signal');
  return signal;
}
