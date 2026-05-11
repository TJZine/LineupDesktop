import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { ChannelPersistenceStore } from '../../domain/channel/channelPersistenceStore.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import {
  DesktopChannelPersistenceStore,
  type DesktopChannelPersistenceFileSystem,
} from '../../main/persistence/desktopChannelPersistenceStore.js';

function createNodeBackedChannelFileSystem(
  overrides: Partial<DesktopChannelPersistenceFileSystem>,
): DesktopChannelPersistenceFileSystem {
  return {
    readFile: (filePath, encoding) => fs.readFile(filePath, encoding),
    mkdir: async (directoryPath, options) => {
      await fs.mkdir(directoryPath, options);
    },
    writeFile: async (filePath, content, options) => {
      await fs.writeFile(filePath, content, options);
    },
    rename: async (sourcePath, destinationPath) => {
      await fs.rename(sourcePath, destinationPath);
    },
    chmod: async (filePath, mode) => {
      await fs.chmod(filePath, mode);
    },
    ...overrides,
  };
}

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

test('desktop channel persistence store clears separate current-channel pointer with malformed stored data', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const domainStore = new ChannelPersistenceStore(new DesktopChannelPersistenceStore({ persistenceFilePath }));

  await fs.writeFile(
    persistenceFilePath,
    JSON.stringify({
      schemaVersion: 1,
      storedChannelData: {
        channels: [null],
        channelOrder: [],
        currentChannelId: 'one',
        savedAt: 11,
      },
      currentChannelId: 'one',
    }),
  );

  assert.equal(await domainStore.readStoredChannelData(), null);
  assert.equal(await domainStore.readCurrentChannelId(), null);
  const persisted = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    storedChannelData?: unknown;
    currentChannelId?: unknown;
  };
  assert.equal(persisted.storedChannelData, null);
  assert.equal(persisted.currentChannelId, null);
});

test('desktop channel persistence store validates savedAt and currentChannelId metadata', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const domainStore = new ChannelPersistenceStore(new DesktopChannelPersistenceStore({ persistenceFilePath }));

  await fs.writeFile(
    persistenceFilePath,
    JSON.stringify({
      schemaVersion: 1,
      storedChannelData: {
        channels: [],
        channelOrder: [],
        currentChannelId: null,
        savedAt: null,
      },
      currentChannelId: null,
    }),
  );
  assert.equal(await domainStore.readStoredChannelData(), null);

  await fs.writeFile(
    persistenceFilePath,
    JSON.stringify({
      schemaVersion: 1,
      storedChannelData: null,
      currentChannelId: 7,
    }),
  );
  assert.equal(await domainStore.readCurrentChannelId(), null);
});

test('desktop channel persistence store preserves data when top-level current pointer is malformed', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const domainStore = new ChannelPersistenceStore(new DesktopChannelPersistenceStore({ persistenceFilePath }));
  const data = storedData({
    channels: [channel('one', 1)],
    channelOrder: ['one'],
    currentChannelId: 'one',
    savedAt: 11,
  });

  await fs.writeFile(
    persistenceFilePath,
    JSON.stringify({
      schemaVersion: 1,
      storedChannelData: data,
      currentChannelId: 7,
    }),
  );

  assert.deepEqual(await domainStore.readStoredChannelData(), data);
  assert.equal(await domainStore.readCurrentChannelId(), null);
  const persisted = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    storedChannelData?: StoredChannelData | null;
    currentChannelId?: unknown;
  };
  assert.deepEqual(persisted.storedChannelData, data);
  assert.equal(persisted.currentChannelId, null);
});

test('desktop channel persistence store propagates top-level current pointer repair write failures', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const repairFailure = new Error('repair rename failed');
  const adapter = new DesktopChannelPersistenceStore({
    persistenceFilePath,
    fileSystem: createNodeBackedChannelFileSystem({
      rename: async () => {
        throw repairFailure;
      },
    }),
  });
  const data = storedData({
    channels: [channel('one', 1)],
    channelOrder: ['one'],
    currentChannelId: 'one',
    savedAt: 11,
  });
  const originalContent = JSON.stringify({
    schemaVersion: 1,
    storedChannelData: data,
    currentChannelId: 7,
  });

  await fs.writeFile(persistenceFilePath, originalContent);
  await assert.rejects(
    () => adapter.readCurrentChannelId(),
    (error: unknown) => error === repairFailure,
  );
  assert.equal(await fs.readFile(persistenceFilePath, 'utf8'), originalContent);
});

test('desktop channel persistence store preserves explicit null current-channel clears', async () => {
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
  assert.equal(await domainStore.readCurrentChannelId(), 'one');

  await adapter.writeStoredChannelData(JSON.stringify({
    ...data,
    currentChannelId: null,
  }));
  assert.equal(await domainStore.readCurrentChannelId(), null);
});

test('desktop channel persistence store propagates non-missing read errors without rewriting state', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const adapter = new DesktopChannelPersistenceStore({ persistenceFilePath: temporaryDirectory });

  await assert.rejects(() => adapter.readStoredChannelData(), (error: unknown) =>
    error instanceof Error && 'code' in error && error.code === 'EISDIR',
  );
  const stat = await fs.stat(temporaryDirectory);
  assert.equal(stat.isDirectory(), true);
});

test('desktop channel persistence store serializes concurrent mutating cycles', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const adapter = new DesktopChannelPersistenceStore({ persistenceFilePath });
  const data = storedData({
    channels: [channel('one', 1)],
    channelOrder: ['one'],
    currentChannelId: 'one',
    savedAt: 11,
  });

  await Promise.all([
    adapter.writeStoredChannelData(JSON.stringify(data)),
    adapter.writeCurrentChannelId('two'),
  ]);

  const persisted = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    storedChannelData?: StoredChannelData;
    currentChannelId?: unknown;
  };
  assert.deepEqual(persisted.storedChannelData, data);
  assert.equal(persisted.currentChannelId, 'two');
});

test('desktop channel persistence store serializes corrupt repair with concurrent valid writes', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-persistence-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  const adapter = new DesktopChannelPersistenceStore({ persistenceFilePath });
  const data = storedData({
    channels: [channel('valid', 1)],
    channelOrder: ['valid'],
    currentChannelId: 'valid',
    savedAt: 11,
  });

  await fs.writeFile(persistenceFilePath, '{corrupt-json');
  await Promise.all([
    adapter.readStoredChannelData(),
    adapter.writeStoredChannelData(JSON.stringify(data)),
  ]);

  const persisted = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    storedChannelData?: StoredChannelData | null;
    currentChannelId?: unknown;
  };
  assert.deepEqual(persisted.storedChannelData, data);
  assert.equal(persisted.currentChannelId, 'valid');
  assert.deepEqual(JSON.parse(assertPresent(await adapter.readStoredChannelData())), data);
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
