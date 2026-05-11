import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { setTimeout as sleep } from 'node:timers/promises';

import { auditChannelDomainValueForForbiddenFields } from '../domain/channel/channelSafety.js';
import { ChannelManager } from '../domain/channel/channelManager.js';
import { ChannelPersistenceCoordinator } from '../domain/channel/channelPersistenceCoordinator.js';
import { ChannelPersistenceSaveQueue } from '../domain/channel/channelPersistenceSaveQueue.js';
import {
  ChannelPersistenceStore,
  type ChannelPersistenceStoragePort,
} from '../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../domain/channel/channelRepository.js';
import {
  decodeStoredChannelData,
  encodeStoredChannelData,
} from '../domain/channel/storedChannelDataCodec.js';
import type {
  ChannelClock,
  ChannelPersistencePort,
  ChannelTimerHandle,
  ChannelTimerPort,
} from '../domain/channel/interfaces.js';
import type { StoredChannelData } from '../domain/channel/types.js';
import { DesktopChannelPersistenceStore } from '../main/persistence/desktopChannelPersistenceStore.js';

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

  public async tickAll(): Promise<void> {
    for (const [handle, handler] of [...this.handlers.entries()]) {
      this.handlers.delete(handle);
      handler();
      await Promise.resolve();
    }
  }
}

class MemoryChannelStorage implements ChannelPersistenceStoragePort {
  public storedChannelData: string | null = null;
  public currentChannelId: string | null = null;
  public clearCount = 0;

  public async readStoredChannelData(): Promise<string | null> {
    return this.storedChannelData;
  }

  public async writeStoredChannelData(encoded: string): Promise<void> {
    this.storedChannelData = encoded;
  }

  public async clearStoredChannelData(): Promise<void> {
    this.clearCount++;
    this.storedChannelData = null;
  }

  public async readCurrentChannelId(): Promise<string | null> {
    return this.currentChannelId;
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    this.currentChannelId = channelId;
  }
}

test('channel persistence codec decodes only stored channel data shape', () => {
  const data = storedData({
    channels: [channel('one', 1)],
    channelOrder: ['one'],
    currentChannelId: 'one',
    savedAt: 1_000,
  });

  assert.deepEqual(decodeStoredChannelData(encodeStoredChannelData(data)), data);
  assert.equal(decodeStoredChannelData('{bad-json'), null);
  assert.equal(decodeStoredChannelData(JSON.stringify({ channels: [] })), null);
  assert.equal(decodeStoredChannelData(JSON.stringify({ channelOrder: [] })), null);
});

test('channel persistence store cleans empty and malformed records', async () => {
  const storage = new MemoryChannelStorage();
  const store = new ChannelPersistenceStore(storage);

  storage.storedChannelData = '';
  assert.equal(await store.readStoredChannelData(), null);
  assert.equal(storage.clearCount, 1);

  storage.storedChannelData = '{bad-json';
  assert.equal(await store.readStoredChannelData(), null);
  assert.equal(storage.clearCount, 2);

  storage.currentChannelId = '  channel-1  ';
  assert.equal(await store.readCurrentChannelId(), 'channel-1');
  assert.equal(storage.currentChannelId, 'channel-1');

  storage.currentChannelId = '   ';
  assert.equal(await store.readCurrentChannelId(), null);
  assert.equal(storage.currentChannelId, null);
});

test('channel persistence repository normalizes malformed persisted channel state', async () => {
  const storage = new MemoryChannelStorage();
  const clock = new FakeClock(9_000);
  const repository = new ChannelRepository({
    store: new ChannelPersistenceStore(storage),
    clock,
  });
  storage.storedChannelData = JSON.stringify({
    channels: [
      { ...channel('alpha', 9), shuffleSeed: Number.NaN, phaseSeed: undefined },
      channel('beta', 9),
      { ...channel('drop-invalid-source', 10), contentSource: { type: 'library' } },
      { ...channel('alpha', 11), name: 'Duplicate id' },
      null,
    ],
    channelOrder: ['missing', 'beta', 'beta', 'alpha'],
    currentChannelId: 'missing',
  });
  storage.currentChannelId = ' alpha ';

  const loaded = await repository.loadNormalized();

  assert.ok(loaded);
  assert.equal(loaded.didMutate, true);
  assert.deepEqual(loaded.data.channels.map((entry) => entry.id), ['alpha', 'beta']);
  assert.deepEqual(loaded.data.channels.map((entry) => entry.number), [9, 1]);
  assert.deepEqual(loaded.data.channelOrder, ['beta', 'alpha']);
  assert.equal(loaded.data.currentChannelId, 'alpha');
  assert.equal(loaded.data.savedAt, 9_000);
  assert.equal(Number.isFinite(loaded.data.channels[0]?.shuffleSeed), true);
  assert.equal(Number.isFinite(loaded.data.channels[0]?.phaseSeed), true);
});

test('channel persistence coordinator repairs invalid separate current-channel pointers', async () => {
  const storage = new MemoryChannelStorage();
  const clock = new FakeClock(9_500);
  const coordinator = new ChannelPersistenceCoordinator({
    repository: new ChannelRepository({
      store: new ChannelPersistenceStore(storage),
      clock,
    }),
    clock,
    timers: new FakeTimers(),
    debounceMs: 50,
  });
  storage.storedChannelData = JSON.stringify({
    channels: [channel('alpha', 1), channel('beta', 2)],
    channelOrder: ['alpha', 'beta'],
    currentChannelId: 'alpha',
    savedAt: 9_000,
  });
  storage.currentChannelId = 'missing';

  const loaded = await coordinator.load();

  assert.ok(loaded);
  assert.equal(loaded.currentChannelId, 'alpha');
  assert.equal(storage.currentChannelId, 'alpha');
});

test('channel persistence queue debounces flushes and rejects pending saves on dispose', async () => {
  const clock = new FakeClock(1_000);
  const timers = new FakeTimers();
  let saves = 0;
  const queue = new ChannelPersistenceSaveQueue({
    runSave: async () => {
      saves++;
    },
    createDisposedError: () => new Error('disposed'),
    emitPersistenceWarning: () => undefined,
    clock,
    timers,
    debounceMs: 25,
  });

  const first = queue.save();
  const second = queue.save();
  assert.equal(first, second);
  assert.equal(timers.handlers.size, 1);
  assert.equal(timers.clearCount, 1);

  await queue.flush();
  await second;
  assert.equal(saves, 1);
  assert.equal(timers.handlers.size, 0);

  const pending = queue.save();
  queue.dispose();
  await assert.rejects(pending, /disposed/);
  await assert.rejects(() => queue.save(), /disposed/);
});

test('channel persistence queue serializes saves queued while a write is in flight', async () => {
  const clock = new FakeClock(1_000);
  const timers = new FakeTimers();
  const first = createDeferred<void>();
  const second = createDeferred<void>();
  const writes: string[] = [];
  const queue = new ChannelPersistenceSaveQueue({
    runSave: async () => undefined,
    createDisposedError: () => new Error('disposed'),
    emitPersistenceWarning: () => undefined,
    clock,
    timers,
    debounceMs: 25,
  });

  queue.queueWithSnapshot(async () => {
    writes.push('first:start');
    await first.promise;
    writes.push('first:end');
  });
  await timers.tickAll();
  assert.deepEqual(writes, ['first:start']);

  queue.queueWithSnapshot(async () => {
    writes.push('second:start');
    await second.promise;
    writes.push('second:end');
  });
  await timers.tickAll();
  assert.deepEqual(writes, ['first:start']);

  first.resolve();
  await sleep(0);
  assert.deepEqual(writes, ['first:start', 'first:end', 'second:start']);

  second.resolve();
  await queue.flush();
  assert.deepEqual(writes, ['first:start', 'first:end', 'second:start', 'second:end']);
});

test('channel persistence queue flush rejects in-flight write failures', async () => {
  const clock = new FakeClock(1_000);
  const timers = new FakeTimers();
  const write = createDeferred<void>();
  const queue = new ChannelPersistenceSaveQueue({
    runSave: async () => undefined,
    createDisposedError: () => new Error('disposed'),
    emitPersistenceWarning: () => undefined,
    clock,
    timers,
    debounceMs: 25,
  });

  queue.queueWithSnapshot(async () => {
    await write.promise;
  });
  await timers.tickAll();
  const flushed = queue.flush();
  write.reject(new Error('write failed'));

  await assert.rejects(flushed, /write failed/);
});

test('channel persistence queue does not replay settled write failures on no-op flush', async () => {
  const clock = new FakeClock(1_000);
  const timers = new FakeTimers();
  const queue = new ChannelPersistenceSaveQueue({
    runSave: async () => undefined,
    createDisposedError: () => new Error('disposed'),
    emitPersistenceWarning: () => undefined,
    clock,
    timers,
    debounceMs: 25,
  });

  const save = queue.saveWithSnapshot(async () => {
    throw new Error('write failed');
  });
  await timers.tickAll();
  await assert.rejects(save, /write failed/);

  await queue.flush();
});

test('channel persistence queue rejects active save promises on dispose', async () => {
  const clock = new FakeClock(1_000);
  const timers = new FakeTimers();
  const write = createDeferred<void>();
  const queue = new ChannelPersistenceSaveQueue({
    runSave: async () => undefined,
    createDisposedError: () => new Error('disposed'),
    emitPersistenceWarning: () => undefined,
    clock,
    timers,
    debounceMs: 25,
  });

  const pending = queue.saveWithSnapshot(async () => {
    await write.promise;
  });
  await timers.tickAll();
  queue.dispose();

  await assert.rejects(pending, /disposed/);
  write.resolve();
  await sleep(0);
});

test('channel persistence coordinator saves full-lineup snapshots transactionally', async () => {
  const storage = new MemoryChannelStorage();
  const clock = new FakeClock(5_000);
  const timers = new FakeTimers();
  const coordinator = new ChannelPersistenceCoordinator({
    repository: new ChannelRepository({
      store: new ChannelPersistenceStore(storage),
      clock,
    }),
    clock,
    timers,
    debounceMs: 50,
  });

  coordinator.queueSave({
    channels: [channel('old', 1)],
    channelOrder: ['old'],
    currentChannelId: 'old',
  });
  coordinator.queueSave({
    channels: [channel('new', 7)],
    channelOrder: ['new'],
    currentChannelId: 'new',
  });
  await timers.tickAll();
  await coordinator.flush();

  const persisted = decodeStoredChannelData(assertPresent(storage.storedChannelData));
  assert.ok(persisted);
  assert.deepEqual(persisted.channels?.map((entry) => entry.id), ['new']);
  assert.deepEqual(persisted.channelOrder, ['new']);
  assert.equal(persisted.currentChannelId, 'new');
  assert.equal(persisted.savedAt, 5_000);
  assert.equal(storage.currentChannelId, 'new');
});

test('channel manager uses debounced channel persistence when the port supports it', async () => {
  const storage = new MemoryChannelStorage();
  const clock = new FakeClock(5_000);
  const timers = new FakeTimers();
  const coordinator = new ChannelPersistenceCoordinator({
    repository: new ChannelRepository({
      store: new ChannelPersistenceStore(storage),
      clock,
    }),
    clock,
    timers,
    debounceMs: 50,
  });
  const manager = new ChannelManager({
    plexLibrary: createUnusedLibrary(),
    clock,
    timers,
    generateId: () => 'generated',
    persistence: coordinator,
  });

  await manager.createChannel({
    contentSource: {
      type: 'manual',
      items: [{ ratingKey: 'manual-1', title: 'Manual One', durationMs: 60_000 }],
    },
  });

  assert.equal(storage.storedChannelData, null);
  await timers.tickAll();

  const persisted = decodeStoredChannelData(assertPresent(storage.storedChannelData));
  assert.ok(persisted);
  assert.deepEqual(persisted.channels?.map((entry) => entry.id), ['generated']);
  assert.deepEqual(persisted.channelOrder, ['generated']);
});

test('channel manager flush persists the latest channel state over a pending queued save', async () => {
  const storage = new MemoryChannelStorage();
  const clock = new FakeClock(6_000);
  const timers = new FakeTimers();
  const coordinator = new ChannelPersistenceCoordinator({
    repository: new ChannelRepository({
      store: new ChannelPersistenceStore(storage),
      clock,
    }),
    clock,
    timers,
    debounceMs: 50,
  });
  const manager = new ChannelManager({
    plexLibrary: createUnusedLibrary(),
    clock,
    timers,
    generateId: createSequentialIds(['first', 'second']),
    persistence: coordinator,
  });

  await manager.createChannel({
    contentSource: {
      type: 'manual',
      items: [{ ratingKey: 'manual-1', title: 'Manual One', durationMs: 60_000 }],
    },
  });
  await manager.createChannel({
    contentSource: {
      type: 'manual',
      items: [{ ratingKey: 'manual-2', title: 'Manual Two', durationMs: 60_000 }],
    },
  });
  await manager.flushSaves();

  const persisted = decodeStoredChannelData(assertPresent(storage.storedChannelData));
  assert.ok(persisted);
  assert.deepEqual(persisted.channels?.map((entry) => entry.id), ['first', 'second']);
  assert.deepEqual(persisted.channelOrder, ['first', 'second']);
  assert.equal(timers.handlers.size, 0);
});

test('channel manager preserves persisted channel order on load', async () => {
  const manager = new ChannelManager({
    plexLibrary: createUnusedLibrary(),
    clock: new FakeClock(7_000),
    generateId: () => 'unused',
    persistence: {
      load: async () => storedData({
        channels: [channel('alpha', 1), channel('beta', 2)],
        channelOrder: ['beta', 'alpha'],
        currentChannelId: 'beta',
        savedAt: 6_000,
      }),
      save: async () => undefined,
    },
  });

  await manager.loadChannels();

  assert.deepEqual(manager.getAllChannels().map((entry) => entry.id), ['beta', 'alpha']);
  assert.equal(manager.getCurrentChannel()?.id, 'beta');
  assert.equal(manager.getNextChannel()?.id, 'alpha');
});

test('channel manager handles best-effort current-channel persistence failures', async () => {
  const loggedErrors: unknown[] = [];
  const unhandled: unknown[] = [];
  const onUnhandled = (reason: unknown): void => {
    unhandled.push(reason);
  };
  process.on('unhandledRejection', onUnhandled);
  try {
    const persistence: ChannelPersistencePort = {
      load: async () => storedData({
        channels: [channel('alpha', 1), channel('beta', 2)],
        channelOrder: ['alpha', 'beta'],
        currentChannelId: 'alpha',
        savedAt: 6_000,
      }),
      save: async () => {
        throw new Error('save unavailable');
      },
    };
    const manager = new ChannelManager({
      plexLibrary: createUnusedLibrary(),
      clock: new FakeClock(7_000),
      generateId: () => 'unused',
      logger: {
        warn: () => undefined,
        error: (_message, detail) => {
          loggedErrors.push(detail);
        },
      },
      persistence,
    });

    await manager.loadChannels();
    manager.setCurrentChannel('beta');
    await sleep(0);

    assert.equal(unhandled.length, 0);
    assert.equal(loggedErrors.length, 1);
    assert.equal(manager.getCurrentChannel()?.id, 'beta');
  } finally {
    process.off('unhandledRejection', onUnhandled);
  }
});

test('desktop channel persistence store writes a separate versioned temp-file-backed state', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const adapter = new DesktopChannelPersistenceStore({ persistenceFilePath });
  const domainStore = new ChannelPersistenceStore(adapter);
  const data = storedData({
    channels: [channel('one', 1)],
    channelOrder: ['one'],
    currentChannelId: 'one',
    savedAt: 11,
  });

  await domainStore.writeStoredChannelData(data);
  const persisted = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    schemaVersion?: unknown;
    storedChannelData?: StoredChannelData;
    currentChannelId?: unknown;
    credentials?: unknown;
    selectedServer?: unknown;
  };

  assert.equal(persisted.schemaVersion, 1);
  assert.deepEqual(persisted.storedChannelData, data);
  assert.equal(persisted.currentChannelId, 'one');
  assert.equal(persisted.credentials, undefined);
  assert.equal(persisted.selectedServer, undefined);
  assert.deepEqual(await domainStore.readStoredChannelData(), data);
  assert.equal(await domainStore.readCurrentChannelId(), 'one');

  await fs.writeFile(persistenceFilePath, '{"schemaVersion":1,"storedChannelData":"bad"}\n');
  assert.equal(await domainStore.readStoredChannelData(), null);
});

test('channel persistence persisted state contains no forbidden renderer or secret-bearing fields', async () => {
  const storage = new MemoryChannelStorage();
  const store = new ChannelPersistenceStore(storage);
  const data = storedData({
    channels: [channel('safe', 3)],
    channelOrder: ['safe'],
    currentChannelId: 'safe',
    savedAt: 123,
  });

  await store.writeStoredChannelData(data);
  await store.writeCurrentChannelId('safe');
  const persistedState = {
    storedChannelData: decodeStoredChannelData(assertPresent(storage.storedChannelData)),
    currentChannelId: storage.currentChannelId,
  };

  assert.deepEqual(auditChannelDomainValueForForbiddenFields(persistedState), []);
  assert.equal(JSON.stringify(persistedState).includes('credentials'), false);
  assert.equal(JSON.stringify(persistedState).includes('selectedServer'), false);
  assert.deepEqual(auditChannelDomainValueForForbiddenFields({ authHeaders: { value: 'blocked' } }), [
    { path: '$', key: 'authHeaders' },
  ]);
});

function channel(id: string, number: number) {
  return {
    id,
    number,
    name: `Channel ${id}`,
    contentSource: {
      type: 'manual' as const,
      items: [{ ratingKey: `item-${id}`, title: `Item ${id}`, durationMs: 60_000 }],
    },
    playbackMode: 'sequential' as const,
    startTimeAnchor: 1_000,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1_000,
    updatedAt: 1_000,
    lastContentRefresh: 0,
    itemCount: 1,
    totalDurationMs: 60_000,
  };
}

function storedData(data: StoredChannelData): StoredChannelData {
  return data;
}

function assertPresent(value: string | null): string {
  if (value === null) {
    assert.fail('Expected value to be present');
  }
  return value;
}

function createUnusedLibrary() {
  return {
    getLibraryItems: async () => {
      assert.fail('Library lookup should not be used by manual channel persistence tests');
    },
    getCollectionItems: async () => {
      assert.fail('Collection lookup should not be used by manual channel persistence tests');
    },
    getShowEpisodes: async () => {
      assert.fail('Show lookup should not be used by manual channel persistence tests');
    },
    getPlaylistItems: async () => {
      assert.fail('Playlist lookup should not be used by manual channel persistence tests');
    },
    getItem: async () => {
      assert.fail('Item lookup should not be used by manual channel persistence tests');
    },
  };
}

function createSequentialIds(ids: string[]): () => string {
  let index = 0;
  return () => {
    const id = ids[index];
    if (!id) {
      assert.fail('No generated id configured for test');
    }
    index++;
    return id;
  };
}

function createDeferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T | PromiseLike<T>) => void;
  reject: (error: unknown) => void;
} {
  let resolve: (value: T | PromiseLike<T>) => void = () => undefined;
  let reject: (error: unknown) => void = () => undefined;
  const promise = new Promise<T>((innerResolve, innerReject) => {
    resolve = innerResolve;
    reject = innerReject;
  });
  return { promise, resolve, reject };
}
