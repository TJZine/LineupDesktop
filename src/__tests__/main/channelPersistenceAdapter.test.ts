import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

import {
  ChannelPersistenceStore,
  type ChannelAggregate,
} from '../../domain/channel/channelPersistenceStore.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import {
  ChannelPersistenceBootstrapOwner,
  type ChannelPersistenceReadyCapability,
} from '../../main/persistence/channelPersistenceBootstrapOwner.js';
import {
  CorruptChannelPersistenceFileError,
  DesktopChannelPersistenceStore,
} from '../../main/persistence/desktopChannelPersistenceStore.js';

test('desktop channel persistence stores one versioned aggregate and preserves legacy readability', async () => {
  const { store, capability } = await createStore();
  const aggregate = aggregateWith(storedData());
  const result = await store.mutateChannelAggregate({
    kind: 'builder-lineup',
    expectedLineupRevision: 0,
    mutate: () => aggregate,
    onCommitBarrier: () => 'proceed',
  });
  assert.equal(result.status, 'committed');
  const persisted = JSON.parse(
    await fs.readFile(capability.persistenceFilePath, 'utf8'),
  ) as Record<string, unknown>;
  assert.equal(persisted.schemaVersion, 1);
  assert.equal(persisted.lineupRevision, 1);
  assert.deepEqual(persisted.storedChannelData, aggregate.storedChannelData);
  assert.equal(persisted.currentChannelId, 'legacy-channel');

  const legacyRewrite = {
    schemaVersion: persisted.schemaVersion,
    storedChannelData: persisted.storedChannelData,
    currentChannelId: persisted.currentChannelId,
  };
  await fs.writeFile(
    capability.persistenceFilePath,
    `${JSON.stringify(legacyRewrite, null, 2)}\n`,
  );
  const reloaded = await store.loadForStartup();
  assert.equal(reloaded.aggregate.lineupRevision, 0);
  assert.equal(reloaded.aggregate.channelBuilderState, null);
  assert.deepEqual(
    reloaded.aggregate.storedChannelData?.channelOrder,
    ['legacy-channel'],
  );
});

test('ordinary channel persistence reads never repair corrupt or legacy bytes', async () => {
  const { store, capability } = await createStore();
  const corrupt = '{corrupt-json';
  await fs.writeFile(capability.persistenceFilePath, corrupt);
  await assert.rejects(() => store.readChannelAggregate(), CorruptChannelPersistenceFileError);
  assert.equal(await fs.readFile(capability.persistenceFilePath, 'utf8'), corrupt);

  const legacy = JSON.stringify({
    schemaVersion: 1,
    storedChannelData: storedData(),
    currentChannelId: ' legacy-channel ',
  });
  await fs.writeFile(capability.persistenceFilePath, legacy);
  await assert.rejects(() => store.readChannelAggregate(), CorruptChannelPersistenceFileError);
  assert.equal(await fs.readFile(capability.persistenceFilePath, 'utf8'), legacy);
});

test('aggregate mutation enforces CAS and cancel-before-barrier byte preservation', async () => {
  const { store, capability } = await createStore();
  const initial = aggregateWith(storedData());
  const committed = await store.mutateChannelAggregate({
    kind: 'custom-lineup',
    expectedLineupRevision: null,
    mutate: () => initial,
    onCommitBarrier: () => 'proceed',
  });
  assert.equal(committed.status, 'committed');
  const before = await fs.readFile(capability.persistenceFilePath, 'utf8');

  const conflict = await store.mutateChannelAggregate({
    kind: 'builder-lineup',
    expectedLineupRevision: 0,
    mutate: (current) => current as ChannelAggregate,
    onCommitBarrier: () => 'proceed',
  });
  assert.deepEqual(conflict, { status: 'conflict', actualLineupRevision: 1 });

  const canceled = await store.mutateChannelAggregate({
    kind: 'builder-lineup',
    expectedLineupRevision: 1,
    mutate: (current) => ({
      ...current,
      currentChannelId: null,
      storedChannelData:
        current.storedChannelData === null
          ? null
          : { ...current.storedChannelData, currentChannelId: null },
    }),
    onCommitBarrier: () => 'cancel',
  });
  assert.deepEqual(canceled, { status: 'canceled' });
  assert.equal(await fs.readFile(capability.persistenceFilePath, 'utf8'), before);
});

test('domain channel persistence delegates aggregate reads and writes', async () => {
  const { store } = await createStore();
  const domainStore = new ChannelPersistenceStore(store);
  await domainStore.writeStoredChannelData(storedData());
  assert.deepEqual(await domainStore.readStoredChannelData(), storedData());
  assert.equal(await domainStore.readCurrentChannelId(), 'legacy-channel');
});

async function createStore(): Promise<{
  store: DesktopChannelPersistenceStore;
  capability: ChannelPersistenceReadyCapability;
}> {
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-store-'));
  const bootstrap = await new ChannelPersistenceBootstrapOwner({
    app: { getPath: () => userData },
    platform: process.platform,
    fileSystem: {
      realpath: (value) => fs.realpath(value),
      lstat: (value) => fs.lstat(value),
      mkdir: async (value, options) => {
        await fs.mkdir(value, options);
      },
    },
  }).bootstrap();
  assert.equal(bootstrap.status, 'ready');
  if (bootstrap.status !== 'ready') throw new Error('bootstrap failed');
  return {
    capability: bootstrap.capability,
    store: new DesktopChannelPersistenceStore({
      readyCapability: bootstrap.capability,
      randomHex128: () => 'a'.repeat(32),
    }),
  };
}

function aggregateWith(data: StoredChannelData): ChannelAggregate {
  return {
    storedChannelData: data,
    currentChannelId: data.currentChannelId,
    lineupRevision: 0,
    channelBuilderState: null,
  };
}

function storedData(): StoredChannelData {
  return {
    channels: [
      {
        id: 'legacy-channel',
        number: 1,
        name: 'Legacy Channel',
        contentSource: {
          type: 'library',
          libraryId: 'legacy-library',
          libraryType: 'movie',
          includeWatched: true,
        },
        playbackMode: 'sequential',
        startTimeAnchor: 0,
        skipIntros: false,
        skipCredits: false,
        createdAt: 0,
        updatedAt: 0,
        lastContentRefresh: 0,
        itemCount: 1,
        totalDurationMs: 60_000,
      },
    ],
    channelOrder: ['legacy-channel'],
    currentChannelId: 'legacy-channel',
    savedAt: 0,
  };
}
