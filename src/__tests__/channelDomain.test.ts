import test from 'node:test';
import assert from 'node:assert/strict';

import {
  auditChannelDomainValueForForbiddenFields,
  ChannelError,
  ChannelImportNormalizer,
  ChannelManager,
  ChannelResolutionCache,
  ContentSelectionPolicy,
  ContentResolver,
  isValidChannelConfig,
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
  ChannelLogger,
  ChannelPersistencePort,
  IPlexLibraryMinimal,
  PlexMediaItemMinimal,
} from '../domain/channel/index.js';
import type {
  ChannelConfig,
  ChannelContentSource,
  ResolvedContentItem,
  StoredChannelData,
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
    for (const [handle, handler] of [...this.handlers.entries()]) {
      this.handlers.delete(handle);
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
  logger?: ChannelLogger;
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
    logger: options.logger,
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
  assert.equal(isValidContentSource({ ...librarySource(), tokenizedUrl: 'blocked' }), false);
  assert.equal(isValidContentSource({ ...librarySource(), authHeaders: { value: 'blocked' } }), false);
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10, rawPlexPayload: 'blocked' }],
    }),
    false,
  );
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10, authHeaders: 'blocked' }],
    }),
    false,
  );
  assert.equal(
    isValidContentSource({
      type: 'mixed',
      mixMode: 'sequential',
      sources: [{ ...librarySource(), tokenizedUrl: 'blocked' }],
    }),
    false,
  );
  assert.equal(isValidContentSource([librarySource()]), false);
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [['not-an-item']],
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
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10.5 }],
    }),
    false,
  );
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [{ ratingKey: '   ', title: 'Manual', durationMs: 10 }],
    }),
    false,
  );
  assert.equal(isValidContentSource({ type: 'library', libraryId: 'undefined' }), false);
  assert.equal(isValidContentSource({ ...librarySource(), libraryId: '   ' }), false);
  assert.equal(isValidContentSource({ ...librarySource(), extra: 'unexpected' }), false);
  assert.equal(
    isValidContentSource({
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10, extra: 'unexpected' }],
    }),
    false,
  );
  assert.equal(
    isValidContentSource({
      type: 'mixed',
      mixMode: 'sequential',
      sources: [{ ...librarySource(), extra: 'unexpected' }],
    }),
    false,
  );

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

test('channel domain sets the first created channel current and preserves it on later creates', async () => {
  const { manager } = createManager();

  const first = await manager.createChannel(
    { name: 'First', contentSource: librarySource('first') },
    { initialContent: [resolvedItem('first')] },
  );
  assert.equal(manager.getCurrentChannel()?.id, first.id);

  const second = await manager.createChannel(
    { name: 'Second', contentSource: librarySource('second') },
    { initialContent: [resolvedItem('second')] },
  );
  assert.equal(manager.getCurrentChannel()?.id, first.id);
  assert.notEqual(second.id, first.id);
});

test('channel manager isolates event handler failures after committed create state', async () => {
  const errors: Array<{ message: string; detail?: unknown }> = [];
  const { manager } = createManager({
    logger: {
      warn: () => undefined,
      error: (message, detail) => errors.push({ message, detail }),
    },
  });
  const events: string[] = [];
  manager.on('channelCreated', () => {
    throw new Error('listener failed');
  });
  manager.on('channelCreated', (channel) => {
    events.push(channel.id);
  });

  const channel = await manager.createChannel(
    { contentSource: librarySource() },
    { initialContent: [resolvedItem('created')] },
  );

  assert.equal(manager.getChannel(channel.id)?.id, channel.id);
  assert.deepEqual(events, [channel.id]);
  assert.equal(errors.length, 1);
  assert.equal(errors[0]?.message, 'Channel event handler failed for channelCreated');
});

test('channel domain normalizes imports and replaces duplicate channel numbers', async () => {
  const { manager, library } = createManager();
  library.libraryItems.set('lib', [movie('m1')]);

  await manager.createChannel({ number: 1, name: 'Existing', contentSource: librarySource() });
  const result = await manager.importChannels(JSON.stringify([
    { number: 1, name: 'Imported duplicate', contentSource: librarySource() },
    { name: 'Imported next', contentSource: librarySource() },
    { name: 'Invalid source', contentSource: { type: 'library' } },
    {
      number: 501,
      name: 'Invalid number ignored',
      playbackMode: 'block',
      blockSize: 1.5,
      minEpisodeRunTimeMs: 0,
      maxEpisodeRunTimeMs: Number.NaN,
      contentSource: librarySource(),
    },
  ]));

  assert.equal(result.success, true);
  assert.equal(result.importedCount, 3);
  assert.equal(result.skippedCount, 1);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.number), [1, 2, 3, 4]);
  assert.deepEqual(
    manager.getAllChannels().map((channel) => channel.name),
    ['Existing', 'Imported duplicate', 'Imported next', 'Invalid number ignored'],
  );
  const numericImport = manager.getAllChannels().find((channel) => channel.name === 'Invalid number ignored');
  assert.ok(numericImport);
  assert.equal(numericImport.blockSize, undefined);
  assert.equal(numericImport.minEpisodeRunTimeMs, undefined);
  assert.equal(numericImport.maxEpisodeRunTimeMs, undefined);

  const invalid = await manager.importChannels('{not-json');
  assert.equal(invalid.success, false);
  assert.deepEqual(invalid.errors, ['Import file is invalid']);
});

test('channel import normalizer clones content sources and skips impossible runtime ranges', () => {
  const normalizer = new ChannelImportNormalizer();
  const contentSource: ChannelContentSource = {
    type: 'mixed',
    mixMode: 'sequential',
    sources: [{
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10_000 }],
    }],
  };

  const channel = normalizer.buildCreateInput({
    name: 'Imported',
    contentSource,
    minEpisodeRunTimeMs: 10_000,
    maxEpisodeRunTimeMs: 20_000,
  });
  assert.ok(channel);
  contentSource.sources[0] = librarySource('mutated');

  assert.deepEqual(channel.contentSource, {
    type: 'mixed',
    mixMode: 'sequential',
    sources: [{
      type: 'manual',
      items: [{ ratingKey: 'm1', title: 'Manual', durationMs: 10_000 }],
    }],
  });

  assert.equal(
    normalizer.buildCreateInput({
      contentSource: librarySource(),
      minEpisodeRunTimeMs: 30_000,
      maxEpisodeRunTimeMs: 20_000,
    }),
    null,
  );
});

test('channel domain validates optional authoring fields strictly on create and update', async () => {
  const { manager } = createManager();

  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), playbackMode: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), description: 1 as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), skipCredits: 'yes' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), buildStrategy: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), contentFilters: [{ field: 'bad' }] as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({
      contentSource: librarySource(),
      contentFilters: [{ field: 'genre', operator: 'contains', value: 'Drama', extra: 'legacy' }] as never,
    }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), sortOrder: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), startTimeAnchor: -1 }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({
      contentSource: librarySource(),
      minEpisodeRunTimeMs: 20_000,
      maxEpisodeRunTimeMs: 10_000,
    }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.createChannel({ contentSource: librarySource(), playbackMode: 'sequential', blockSize: 2 }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );

  const valid = await manager.createChannel({
    contentSource: librarySource(),
    playbackMode: 'block',
    blockSize: 2.8,
    buildStrategy: 'collections',
    contentFilters: [{ field: 'genre', operator: 'contains', value: 'Drama' }],
    sortOrder: 'title_asc',
    startTimeAnchor: 5,
    lineupReplicaIndex: 2.9,
    shuffleSeed: 11,
    phaseSeed: 12,
    minEpisodeRunTimeMs: 10_000,
    maxEpisodeRunTimeMs: 20_000,
  });

  assert.equal(valid.blockSize, 2);
  assert.equal(valid.lineupReplicaIndex, 2);
  assert.equal(valid.playbackMode, 'block');
  assert.equal(valid.startTimeAnchor, 5);

  await assert.rejects(
    () => manager.updateChannel(valid.id, { number: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { name: '' }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { skipIntros: 'yes' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { playbackMode: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { buildStrategy: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { contentFilters: [{ field: 'bad' }] as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, {
      contentFilters: [{ field: 'genre', operator: 'contains', value: 'Drama', extra: 'legacy' }] as never,
    }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { sortOrder: 'bad' as never }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { startTimeAnchor: Number.POSITIVE_INFINITY }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { minEpisodeRunTimeMs: 30_000 }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );
  await assert.rejects(
    () => manager.updateChannel(valid.id, { playbackMode: 'sequential', blockSize: 3 }),
    { name: 'ChannelError', code: 'STORAGE_VALIDATION_FAILED' },
  );

  const updated = await manager.updateChannel(valid.id, {
    playbackMode: 'block',
    blockSize: 3.4,
    minEpisodeRunTimeMs: 12_000,
    maxEpisodeRunTimeMs: 30_000,
    contentFilters: [{ field: 'year', operator: 'gte', value: 2020 }],
  });
  assert.equal(updated.blockSize, 3);
  assert.equal(updated.minEpisodeRunTimeMs, 12_000);
  assert.equal(updated.maxEpisodeRunTimeMs, 30_000);
  assert.deepEqual(updated.contentFilters, [{ field: 'year', operator: 'gte', value: 2020 }]);

  const sequential = await manager.updateChannel(valid.id, { playbackMode: 'sequential' });
  assert.equal(sequential.playbackMode, 'sequential');
  assert.equal(sequential.blockSize, undefined);

  const blockAgain = await manager.updateChannel(valid.id, { playbackMode: 'block', blockSize: 4.9 });
  assert.equal(blockAgain.playbackMode, 'block');
  assert.equal(blockAgain.blockSize, 4);

  const writableFields = await manager.updateChannel(valid.id, {
    number: 8,
    name: 'Strict Updated',
    description: 'Updated description',
    icon: 'icon',
    color: 'blue',
    sourceLibraryId: 'source-lib',
    sourceLibraryName: 'Source Library',
    isAutoGenerated: true,
    isPlaybackModeVariant: true,
    skipIntros: true,
    skipCredits: true,
  });
  assert.equal(writableFields.number, 8);
  assert.equal(writableFields.name, 'Strict Updated');
  assert.equal(writableFields.description, 'Updated description');
  assert.equal(writableFields.icon, 'icon');
  assert.equal(writableFields.color, 'blue');
  assert.equal(writableFields.sourceLibraryId, 'source-lib');
  assert.equal(writableFields.sourceLibraryName, 'Source Library');
  assert.equal(writableFields.isAutoGenerated, true);
  assert.equal(writableFields.isPlaybackModeVariant, true);
  assert.equal(writableFields.skipIntros, true);
  assert.equal(writableFields.skipCredits, true);
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

test('channel domain propagates abort during collection expansion without caching partial results', async () => {
  const clock = new FakeClock(1_000);
  const library = new FakeLibrary();
  const abortError = new Error('aborted');
  abortError.name = 'AbortError';
  library.collectionItems.set('collection-1', [
    { ...movie('show-container', 'Show Container', 0), type: 'show' },
  ]);
  library.getShowEpisodes = async () => {
    throw abortError;
  };
  const resolver = new ContentResolver(library, clock, { warn: () => undefined, error: () => undefined });
  const source: ChannelContentSource = {
    type: 'collection',
    collectionKey: 'collection-1',
    collectionName: 'Collection',
  };

  await assert.rejects(
    () => resolver.resolveSource(source, { signal: { aborted: false } }),
    { name: 'AbortError' },
  );

  library.getShowEpisodes = async () => [episode('e1', 'Recovered Show', 1, 1)];
  const recovered = await resolver.resolveSource(source);
  assert.deepEqual(recovered.map((item) => item.ratingKey), ['e1']);
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

test('channel domain source cache once abort listeners can be removed and fire once', async () => {
  const clock = new FakeClock(10);
  const sourceCache = new SourceResolutionCache(clock);
  const source = librarySource();
  const firstDeferred = new Deferred<ResolvedContentItem[]>();
  let removedCount = 0;

  const firstPending = sourceCache.resolve(source, async (_source, options) => {
    const handler = (): void => {
      removedCount++;
    };
    options.signal.addEventListener?.('abort', handler, { once: true });
    options.signal.removeEventListener?.('abort', handler);
    return firstDeferred.promise;
  });
  const firstRejected = assert.rejects(firstPending, /Source resolution invalidated/);
  await Promise.resolve();
  sourceCache.invalidate(source);
  await firstRejected;
  firstDeferred.resolve([resolvedItem('removed-late')]);
  assert.equal(removedCount, 0);

  const secondDeferred = new Deferred<ResolvedContentItem[]>();
  let onceCount = 0;
  const secondPending = sourceCache.resolve(source, async (_source, options) => {
    options.signal.addEventListener?.('abort', () => {
      onceCount++;
    }, { once: true });
    return secondDeferred.promise;
  });
  const secondRejected = assert.rejects(secondPending, /Source resolution invalidated/);
  await Promise.resolve();
  sourceCache.invalidate(source);
  sourceCache.clear();
  await secondRejected;
  secondDeferred.resolve([resolvedItem('once-late')]);
  assert.equal(onceCount, 1);
});

test('channel domain source cache invalidates cached mixed parents when a child source changes', async () => {
  const clock = new FakeClock(10);
  const sourceCache = new SourceResolutionCache(clock);
  const childSource = librarySource('child');
  const mixedSource: ChannelContentSource = {
    type: 'mixed',
    mixMode: 'sequential',
    sources: [childSource],
  };
  let calls = 0;
  const resolve = async (): Promise<ResolvedContentItem[]> => {
    calls++;
    return [resolvedItem(`mixed-${String(calls)}`)];
  };

  assert.equal((await sourceCache.resolve(mixedSource, resolve))[0]?.ratingKey, 'mixed-1');
  assert.equal((await sourceCache.resolve(mixedSource, resolve))[0]?.ratingKey, 'mixed-1');
  sourceCache.invalidate(childSource);
  assert.equal((await sourceCache.resolve(mixedSource, resolve))[0]?.ratingKey, 'mixed-2');
  assert.equal(calls, 2);
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

test('channel domain serializes same-channel delete after pending update resolution', async () => {
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
  let deleteSettled = false;
  const pendingDelete = manager.deleteChannel(channel.id).then(() => {
    deleteSettled = true;
  });
  await Promise.resolve();

  assert.equal(deleteSettled, false);
  deferred.resolve([movie('late-update')]);

  const updated = await pendingUpdate;
  await pendingDelete;
  assert.equal(updated.id, channel.id);
  assert.equal(deleteSettled, true);
  assert.equal(manager.getChannel(channel.id), null);
  assert.deepEqual(manager.getAllChannels(), []);
});

test('channel manager immediate persistence failures leave state unchanged and suppress events', async () => {
  let shouldFailSave = false;
  const durableSnapshots: StoredSnapshot[] = [];
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      if (shouldFailSave) {
        throw new Error('save failed');
      }
      durableSnapshots.push(snapshotStoredData(data));
    },
  };
  const { manager, library } = createManager({ persistence });
  const events: string[] = [];
  manager.on('channelCreated', (channel) => events.push(`created:${channel.id}`));
  manager.on('channelUpdated', (channel) => events.push(`updated:${channel.id}`));
  manager.on('channelDeleted', (id) => events.push(`deleted:${id}`));
  manager.on('contentResolved', (content) => events.push(`resolved:${content.channelId}:${String(content.items.length)}`));

  const one = await manager.createChannel(
    { number: 1, name: 'One', contentSource: librarySource() },
    { initialContent: [resolvedItem('one')] },
  );
  const two = await manager.createChannel(
    { number: 2, name: 'Two', contentSource: librarySource('lib-two') },
    { initialContent: [resolvedItem('two')] },
  );
  events.length = 0;
  shouldFailSave = true;

  await assert.rejects(
    () => manager.createChannel(
      { number: 3, name: 'Three', contentSource: librarySource('lib-three') },
      { initialContent: [resolvedItem('three')] },
    ),
    /save failed/,
  );
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.name), ['One', 'Two']);
  assert.deepEqual(events, []);

  await assert.rejects(() => manager.updateChannel(one.id, { name: 'One Updated' }), /save failed/);
  assert.equal(manager.getChannel(one.id)?.name, 'One');
  assert.deepEqual(events, []);
  assert.equal(durableSnapshots.at(-1)?.channels.some((channel) => channel.name === 'One Updated'), false);

  await assert.rejects(() => manager.deleteChannel(two.id), /save failed/);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), [one.id, two.id]);
  assert.deepEqual(events, []);

  await assert.rejects(() => manager.reorderChannels([two.id, one.id]), /save failed/);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), [one.id, two.id]);
  assert.deepEqual(events, []);

  library.libraryItems.set('lib', [movie('fresh-one'), movie('fresh-two')]);
  await assert.rejects(() => manager.refreshChannelContent(one.id), /save failed/);
  assert.equal(manager.getChannel(one.id)?.itemCount, 1);
  assert.deepEqual(events, []);
});

test('channel manager includes queued current-channel switches in update persistence', async () => {
  const deferred = new Deferred<PlexMediaItemMinimal[]>();
  const saves: StoredSnapshot[] = [];
  const library = new FakeLibrary();
  let slowResolutionCalls = 0;
  library.getLibraryItems = async (libraryId) => {
    if (libraryId === 'slow-current') {
      slowResolutionCalls++;
      return deferred.promise;
    }
    return [movie(`${libraryId}-item`)];
  };
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      saves.push(snapshotStoredData(data));
    },
  };
  const { manager } = createManager({ library, persistence });
  const one = await manager.createChannel(
    { number: 1, name: 'One', contentSource: librarySource() },
    { initialContent: [resolvedItem('one')] },
  );
  const two = await manager.createChannel(
    { number: 2, name: 'Two', contentSource: librarySource('two') },
    { initialContent: [resolvedItem('two')] },
  );
  manager.setCurrentChannel(one.id);
  await Promise.resolve();
  saves.length = 0;

  const pendingUpdate = manager.updateChannel(one.id, {
    name: 'One Updated',
    contentSource: librarySource('slow-current'),
  });
  await waitForCondition(() => slowResolutionCalls === 1, 'slow current-switch update resolution to start');
  manager.setCurrentChannel(two.id);
  await Promise.resolve();

  assert.equal(manager.getCurrentChannel()?.id, two.id);
  deferred.resolve([movie('slow-current-one')]);
  await pendingUpdate;

  assert.equal(manager.getCurrentChannel()?.id, two.id);
  assert.equal(manager.getChannel(one.id)?.name, 'One Updated');
  const updateSaves = saves.filter((save) =>
    save.channels.some((channel) => channel.id === one.id && channel.name === 'One Updated'),
  );
  assert.ok(updateSaves.length >= 1);
  assert.equal(updateSaves[0]?.currentChannelId, two.id);
  assert.equal(updateSaves.at(-1)?.currentChannelId, two.id);
});

test('channel manager preserves current switch made during delayed update save', async () => {
  const gate = new Deferred<void>();
  const saves: StoredSnapshot[] = [];
  let shouldBlockNextSave = false;
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      saves.push(snapshotStoredData(data));
      if (shouldBlockNextSave) {
        shouldBlockNextSave = false;
        await gate.promise;
      }
    },
  };
  const { manager } = createManager({ persistence });
  const updatedEvents: string[] = [];
  manager.on('channelUpdated', (channel) => {
    updatedEvents.push(channel.name);
  });
  const one = await manager.createChannel(
    { number: 1, name: 'One', contentSource: librarySource() },
    { initialContent: [resolvedItem('one')] },
  );
  const two = await manager.createChannel(
    { number: 2, name: 'Two', contentSource: librarySource('two') },
    { initialContent: [resolvedItem('two')] },
  );
  manager.setCurrentChannel(one.id);
  await waitForSaveCount(saves, 3);
  saves.length = 0;
  updatedEvents.length = 0;

  shouldBlockNextSave = true;
  const pendingUpdate = manager.updateChannel(one.id, { name: 'One Updated' });
  await waitForSaveCount(saves, 1);
  manager.setCurrentChannel(two.id);
  await Promise.resolve();

  assert.equal(manager.getCurrentChannel()?.id, two.id);
  assert.deepEqual(updatedEvents, []);
  gate.resolve();
  await pendingUpdate;
  await waitForSaveCount(saves, 2);

  assert.equal(manager.getCurrentChannel()?.id, two.id);
  assert.equal(manager.getChannel(one.id)?.name, 'One Updated');
  assert.deepEqual(updatedEvents, ['One Updated']);
  const latestSave = saves.at(-1);
  assert.ok(latestSave);
  assert.equal(latestSave.currentChannelId, two.id);
  assert.deepEqual(latestSave.channels.map((channel) => [channel.id, channel.name]), [
    [one.id, 'One Updated'],
    [two.id, 'Two'],
  ]);
});

test('channel manager serializes delayed load before later mutations', async () => {
  const loadGate = new Deferred<StoredChannelData | null>();
  const saves: StoredSnapshot[] = [];
  let loadCalls = 0;
  const diskChannel = completeChannel('disk-channel', 1);
  const persistence: ChannelPersistencePort = {
    load: async () => {
      loadCalls++;
      return loadGate.promise;
    },
    save: async (data) => {
      saves.push(snapshotStoredData(data));
    },
  };
  const { manager } = createManager({ persistence });

  const pendingLoad = manager.loadChannels();
  await waitForCondition(() => loadCalls === 1, 'delayed load to start');
  let createSettled = false;
  const pendingCreate = manager.createChannel(
    { number: 2, name: 'Created After Load', contentSource: librarySource('created') },
    { initialContent: [resolvedItem('created')] },
  ).then((channel) => {
    createSettled = true;
    return channel;
  });
  await Promise.resolve();
  await Promise.resolve();

  assert.equal(createSettled, false);
  loadGate.resolve({
    channels: [diskChannel],
    channelOrder: [diskChannel.id],
    currentChannelId: diskChannel.id,
    savedAt: 1_000,
  });
  await pendingLoad;
  const created = await pendingCreate;

  assert.deepEqual(manager.getAllChannels().map((channel) => [channel.id, channel.name]), [
    [diskChannel.id, diskChannel.name],
    [created.id, 'Created After Load'],
  ]);
  assert.deepEqual(saves.at(-1)?.channelOrder, [diskChannel.id, created.id]);
});

test('channel manager resolves update content inside serialized same-channel mutation', async () => {
  const deferred = new Deferred<PlexMediaItemMinimal[]>();
  const saves: StoredSnapshot[] = [];
  const library = new FakeLibrary();
  let slowResolutionCalls = 0;
  library.getLibraryItems = async (libraryId) => {
    if (libraryId === 'slow') {
      slowResolutionCalls++;
      return deferred.promise;
    }
    return [movie(`${libraryId}-item`)];
  };
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      saves.push(snapshotStoredData(data));
    },
  };
  const { manager } = createManager({ library, persistence });
  const events: string[] = [];
  manager.on('contentResolved', (content) => {
    events.push(`resolved:${content.channelId}:${String(content.items.length)}`);
  });
  manager.on('channelUpdated', (channel) => {
    events.push(`updated:${channel.name}`);
  });
  const channel = await manager.createChannel(
    { number: 1, name: 'Base', contentSource: librarySource('base') },
    { initialContent: [resolvedItem('seed')] },
  );
  saves.length = 0;
  events.length = 0;

  let firstSettled = false;
  let secondSettled = false;
  const firstUpdate = manager.updateChannel(channel.id, {
    name: 'Slow Library',
    contentSource: librarySource('slow'),
  }).then((updated) => {
    firstSettled = true;
    return updated;
  });
  await waitForCondition(() => slowResolutionCalls === 1, 'slow update resolution to start');

  const secondUpdate = manager.updateChannel(channel.id, { name: 'Fast Name' }).then((updated) => {
    secondSettled = true;
    return updated;
  });
  await Promise.resolve();
  await Promise.resolve();

  assert.equal(firstSettled, false);
  assert.equal(secondSettled, false);
  assert.equal(saves.length, 0);
  assert.equal(events.length, 0);

  deferred.resolve([movie('slow-one'), movie('slow-two')]);
  const firstResult = await firstUpdate;
  const secondResult = await secondUpdate;

  assert.equal(firstResult.name, 'Slow Library');
  assert.equal(firstResult.itemCount, 2);
  assert.equal(firstResult.contentSource.type, 'library');
  if (firstResult.contentSource.type === 'library') {
    assert.equal(firstResult.contentSource.libraryId, 'slow');
  }
  assert.equal(secondResult.name, 'Fast Name');
  assert.equal(secondResult.itemCount, 2);
  assert.equal(manager.getChannel(channel.id)?.name, 'Fast Name');
  assert.equal(manager.getChannel(channel.id)?.itemCount, 2);
  assert.deepEqual(events, [
    `resolved:${channel.id}:2`,
    'updated:Slow Library',
    'updated:Fast Name',
  ]);
  assert.deepEqual(saves.map((save) => save.channels.map((saved) => [saved.id, saved.name, saved.itemCount])), [
    [[channel.id, 'Slow Library', 2]],
    [[channel.id, 'Fast Name', 2]],
  ]);
});

test('channel manager preserves newer current selection for a queued current-channel delete', async () => {
  const deferred = new Deferred<PlexMediaItemMinimal[]>();
  const library = new FakeLibrary();
  let slowResolutionCalls = 0;
  library.getLibraryItems = async (libraryId) => {
    if (libraryId === 'slow-before-delete') {
      slowResolutionCalls++;
      return deferred.promise;
    }
    return [movie(`${libraryId}-item`)];
  };
  const saves: Array<{ currentChannelId: string | null }> = [];
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      saves.push({ currentChannelId: data.currentChannelId });
    },
  };
  const { manager } = createManager({ library, persistence });
  const one = await manager.createChannel(
    { number: 1, name: 'One', contentSource: librarySource() },
    { initialContent: [resolvedItem('one')] },
  );
  const two = await manager.createChannel(
    { number: 2, name: 'Two', contentSource: librarySource('two') },
    { initialContent: [resolvedItem('two')] },
  );
  const three = await manager.createChannel(
    { number: 3, name: 'Three', contentSource: librarySource('three') },
    { initialContent: [resolvedItem('three')] },
  );
  manager.setCurrentChannel(two.id);
  await Promise.resolve();
  saves.length = 0;

  const pendingUpdate = manager.updateChannel(one.id, { contentSource: librarySource('slow-before-delete') });
  await waitForCondition(() => slowResolutionCalls === 1, 'pre-delete update resolution to start');
  const pendingDelete = manager.deleteChannel(two.id);
  manager.setCurrentChannel(three.id);
  await Promise.resolve();

  assert.equal(manager.getCurrentChannel()?.id, three.id);
  deferred.resolve([movie('slow-before-delete-one')]);
  await pendingUpdate;
  await pendingDelete;

  assert.equal(manager.getChannel(two.id), null);
  assert.equal(manager.getCurrentChannel()?.id, three.id);
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.id), [one.id, three.id]);
  assert.equal(saves.at(-1)?.currentChannelId, three.id);
});

test('channel manager recomputes a pending update after unrelated update delete and reorder commits', async () => {
  const gate = new Deferred<void>();
  const saves: StoredSnapshot[] = [];
  let shouldBlockNextSave = false;
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      saves.push(snapshotStoredData(data));
      if (shouldBlockNextSave) {
        shouldBlockNextSave = false;
        await gate.promise;
      }
    },
  };
  const { manager } = createManager({ persistence });
  const channelA = await manager.createChannel(
    { number: 1, name: 'A', contentSource: librarySource('a') },
    { initialContent: [resolvedItem('a-seed')] },
  );
  const channelB = await manager.createChannel(
    { number: 2, name: 'B', contentSource: librarySource('b') },
    { initialContent: [resolvedItem('b-seed')] },
  );
  const channelC = await manager.createChannel(
    { number: 3, name: 'C', contentSource: librarySource('c') },
    { initialContent: [resolvedItem('c-seed')] },
  );
  saves.length = 0;

  shouldBlockNextSave = true;
  const pendingUpdate = manager.updateChannel(channelA.id, { name: 'A Updated' });
  await waitForSaveCount(saves, 1);
  const pendingBUpdate = manager.updateChannel(channelB.id, { name: 'B Updated' });
  const pendingDelete = manager.deleteChannel(channelC.id);
  const pendingReorder = manager.reorderChannels([channelB.id, channelA.id]);
  gate.resolve();
  await Promise.all([pendingUpdate, pendingBUpdate, pendingDelete, pendingReorder]);

  assert.deepEqual(
    manager.getAllChannels().map((channel) => [channel.id, channel.name]),
    [
      [channelB.id, 'B Updated'],
      [channelA.id, 'A Updated'],
    ],
  );
  const latestSave = saves.at(-1);
  assert.ok(latestSave);
  assert.deepEqual(latestSave.channelOrder, [channelB.id, channelA.id]);
  assert.deepEqual(latestSave.channels.map((channel) => [channel.id, channel.name]), [
    [channelA.id, 'A Updated'],
    [channelB.id, 'B Updated'],
  ]);
});

test('channel manager keeps in-flight refresh applicable after unrelated commits', async () => {
  const deferred = new Deferred<PlexMediaItemMinimal[]>();
  const library = new FakeLibrary();
  const { manager } = createManager({
    library,
    persistence: {
      load: async () => null,
      save: async () => undefined,
    },
  });
  const resolvedEvents: string[] = [];
  manager.on('contentResolved', (content) => {
    resolvedEvents.push(content.channelId);
  });
  const channelA = await manager.createChannel(
    { number: 1, name: 'A', contentSource: librarySource('a') },
    { initialContent: [resolvedItem('a-seed')] },
  );
  const channelB = await manager.createChannel(
    { number: 2, name: 'B', contentSource: librarySource('b') },
    { initialContent: [resolvedItem('b-seed')] },
  );
  resolvedEvents.length = 0;
  library.getLibraryItems = async (libraryId) => {
    if (libraryId === 'a') {
      return deferred.promise;
    }
    return [movie('b-updated')];
  };

  const pendingRefresh = manager.refreshChannelContent(channelA.id);
  await Promise.resolve();
  await manager.updateChannel(channelB.id, { name: 'B Updated' });
  await manager.reorderChannels([channelB.id, channelA.id]);
  deferred.resolve([movie('a-one'), movie('a-two')]);
  const refreshed = await pendingRefresh;

  assert.deepEqual(refreshed.items.map((item) => item.ratingKey), ['a-one', 'a-two']);
  assert.equal(manager.getChannel(channelA.id)?.itemCount, 2);
  assert.equal(manager.getChannel(channelB.id)?.name, 'B Updated');
  assert.deepEqual(resolvedEvents, [channelA.id]);
});

test('channel manager recomputes a pending refresh metadata commit after unrelated update commits', async () => {
  const gate = new Deferred<void>();
  const saves: StoredSnapshot[] = [];
  let shouldBlockNextSave = false;
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async (data) => {
      saves.push(snapshotStoredData(data));
      if (shouldBlockNextSave) {
        shouldBlockNextSave = false;
        await gate.promise;
      }
    },
  };
  const library = new FakeLibrary();
  const { manager } = createManager({ library, persistence });
  const resolvedEvents: string[] = [];
  manager.on('contentResolved', (content) => {
    resolvedEvents.push(content.channelId);
  });
  const channelA = await manager.createChannel(
    { number: 1, name: 'A', contentSource: librarySource('a') },
    { initialContent: [resolvedItem('a-seed')] },
  );
  const channelB = await manager.createChannel(
    { number: 2, name: 'B', contentSource: librarySource('b') },
    { initialContent: [resolvedItem('b-seed')] },
  );
  resolvedEvents.length = 0;
  saves.length = 0;
  library.libraryItems.set('a', [movie('a-one'), movie('a-two')]);

  shouldBlockNextSave = true;
  const pendingRefresh = manager.refreshChannelContent(channelA.id);
  await waitForSaveCount(saves, 1);
  const pendingUpdate = manager.updateChannel(channelB.id, { name: 'B Updated' });
  gate.resolve();
  const [refreshed] = await Promise.all([pendingRefresh, pendingUpdate]);

  assert.deepEqual(refreshed.items.map((item) => item.ratingKey), ['a-one', 'a-two']);
  assert.equal(manager.getChannel(channelA.id)?.itemCount, 2);
  assert.equal(manager.getChannel(channelB.id)?.name, 'B Updated');
  assert.deepEqual(resolvedEvents, [channelA.id]);
  const latestSave = saves.at(-1);
  assert.ok(latestSave);
  assert.deepEqual(latestSave.channels.map((channel) => [channel.id, channel.name, channel.itemCount]), [
    [channelA.id, 'A', 2],
    [channelB.id, 'B Updated', 1],
  ]);
});

test('channel manager serializes concurrent creates with duplicate explicit numbers', async () => {
  const { manager } = createManager();

  const [first, second] = await Promise.allSettled([
    manager.createChannel(
      { number: 7, name: 'First', contentSource: librarySource('first') },
      { initialContent: [resolvedItem('first')] },
    ),
    manager.createChannel(
      { number: 7, name: 'Second', contentSource: librarySource('second') },
      { initialContent: [resolvedItem('second')] },
    ),
  ]);

  assert.equal(first.status, 'fulfilled');
  assert.equal(second.status, 'rejected');
  if (second.status === 'rejected') {
    assert.equal(second.reason?.code, 'DUPLICATE_CHANNEL_NUMBER');
  }
  assert.deepEqual(manager.getAllChannels().map((channel) => channel.number), [7]);
});

test('channel manager rejects pending update number when serialized create takes it first', async () => {
  const gate = new Deferred<void>();
  let shouldBlockNextSave = false;
  const persistence: ChannelPersistencePort = {
    load: async () => null,
    save: async () => {
      if (shouldBlockNextSave) {
        shouldBlockNextSave = false;
        await gate.promise;
      }
    },
  };
  const { manager } = createManager({ persistence });
  const one = await manager.createChannel(
    { number: 1, name: 'One', contentSource: librarySource('one') },
    { initialContent: [resolvedItem('one')] },
  );
  const two = await manager.createChannel(
    { number: 2, name: 'Two', contentSource: librarySource('two') },
    { initialContent: [resolvedItem('two')] },
  );

  shouldBlockNextSave = true;
  const pendingCreate = manager.createChannel(
    { number: 3, name: 'Three', contentSource: librarySource('three') },
    { initialContent: [resolvedItem('three')] },
  );
  await Promise.resolve();
  const pendingUpdate = manager.updateChannel(two.id, { number: 3 });
  gate.resolve();

  await pendingCreate;
  await assert.rejects(pendingUpdate, { name: 'ChannelError', code: 'DUPLICATE_CHANNEL_NUMBER' });
  assert.deepEqual(manager.getAllChannels().map((channel) => [channel.id, channel.number]), [
    [one.id, 1],
    [two.id, 2],
    ['channel-3', 3],
  ]);
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

test('channel domain validates complete channel config numeric fields strictly', () => {
  const valid = completeChannel('valid', 1);
  assert.equal(isValidChannelConfig(valid), true);
  assert.equal(isValidChannelConfig({ ...valid, number: 0 }), false);
  assert.equal(isValidChannelConfig({ ...valid, number: 501 }), false);
  assert.equal(isValidChannelConfig({ ...valid, number: 1.5 }), false);
  assert.equal(isValidChannelConfig({ ...valid, playbackMode: 'bad' as never }), false);
  assert.equal(isValidChannelConfig({ ...valid, sortOrder: 'bad' as never }), false);
  assert.equal(isValidChannelConfig({ ...valid, buildStrategy: 'bad' as never }), false);
  assert.equal(isValidChannelConfig({ ...valid, contentFilters: { field: 'genre' } as never }), false);
  assert.equal(isValidChannelConfig({ ...valid, contentFilters: [{ field: 'bad' }] as never }), false);
  assert.equal(
    isValidChannelConfig({
      ...valid,
      contentFilters: [{ field: 'genre', operator: 'contains', value: 'Drama', extra: 'legacy' }] as never,
    }),
    false,
  );
  assert.equal(
    isValidChannelConfig({
      ...valid,
      contentFilters: [{ field: 'genre', operator: 'contains', value: 'Drama' }],
    }),
    true,
  );

  for (const field of [
    'startTimeAnchor',
    'createdAt',
    'updatedAt',
    'lastContentRefresh',
    'itemCount',
    'totalDurationMs',
  ] as const) {
    assert.equal(isValidChannelConfig({ ...valid, [field]: Number.NaN }), false);
    assert.equal(isValidChannelConfig({ ...valid, [field]: Number.POSITIVE_INFINITY }), false);
    assert.equal(isValidChannelConfig({ ...valid, [field]: -1 }), false);
  }

  for (const field of ['minEpisodeRunTimeMs', 'maxEpisodeRunTimeMs'] as const) {
    for (const value of [0, 1.5, Number.NaN, -1, Number.POSITIVE_INFINITY]) {
      assert.equal(isValidChannelConfig({ ...valid, [field]: value }), false);
    }
  }
  assert.equal(
    isValidChannelConfig({ ...valid, minEpisodeRunTimeMs: 20_000, maxEpisodeRunTimeMs: 10_000 }),
    false,
  );
  assert.equal(
    isValidChannelConfig({ ...valid, minEpisodeRunTimeMs: 10_000, maxEpisodeRunTimeMs: 20_000 }),
    true,
  );
  assert.equal(isValidChannelConfig({ ...valid, playbackMode: 'sequential', blockSize: 2 }), false);
  assert.equal(isValidChannelConfig({ ...valid, playbackMode: 'block', blockSize: 2 }), true);
  assert.equal(isValidChannelConfig({ ...valid, playbackMode: 'block', blockSize: 2.5 }), false);
  assert.equal(isValidChannelConfig({ ...valid, shuffleSeed: Number.NaN }), false);
  assert.equal(isValidChannelConfig({ ...valid, phaseSeed: Number.POSITIVE_INFINITY }), false);
  assert.equal(isValidChannelConfig({ ...valid, lineupReplicaIndex: -1 }), false);
  assert.equal(isValidChannelConfig({ ...valid, lineupReplicaIndex: 1.5 }), true);
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
      }],
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

type StoredSnapshot = Pick<StoredChannelData, 'channelOrder' | 'currentChannelId'> & {
  channels: Array<Pick<ChannelConfig, 'id' | 'name' | 'itemCount'>>;
};

function snapshotStoredData(data: StoredChannelData): StoredSnapshot {
  return {
    channels: data.channels.map((channel) => ({
      id: channel.id,
      name: channel.name,
      itemCount: channel.itemCount,
    })),
    channelOrder: [...data.channelOrder],
    currentChannelId: data.currentChannelId,
  };
}

async function waitForSaveCount(saves: readonly unknown[], count: number): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (saves.length >= count) {
      return;
    }
    await Promise.resolve();
  }
  assert.fail(`Expected at least ${String(count)} save(s), saw ${String(saves.length)}`);
}

async function waitForCondition(predicate: () => boolean, description: string): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (predicate()) {
      return;
    }
    await Promise.resolve();
  }
  assert.fail(`Expected ${description}`);
}

function assertPresentSignal(signal: ChannelAbortSignal | null): ChannelAbortSignal {
  assert.ok(signal, 'expected source cache to pass a transport signal');
  return signal;
}
