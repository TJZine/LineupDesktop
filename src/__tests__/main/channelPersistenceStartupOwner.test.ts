import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

import { ChannelPersistenceBootstrapOwner } from '../../main/persistence/channelPersistenceBootstrapOwner.js';
import { ChannelPersistenceStartupOwner } from '../../main/persistence/channelPersistenceStartupOwner.js';
import { DesktopChannelPersistenceStore } from '../../main/persistence/desktopChannelPersistenceStore.js';

test('startup owner performs the sole repair write without losing lineup data', async () => {
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-startup-'));
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
  if (bootstrap.status !== 'ready') return;
  const legacy = JSON.parse(
    await fs.readFile(
      new URL('../fixtures/channel-persistence-v1-legacy.json', import.meta.url),
      'utf8',
    ),
  ) as Record<string, unknown>;
  legacy.currentChannelId = ' missing-channel ';
  await fs.writeFile(bootstrap.capability.persistenceFilePath, JSON.stringify(legacy));
  const store = new DesktopChannelPersistenceStore({
    readyCapability: bootstrap.capability,
    randomHex128: () => 'b'.repeat(32),
  });
  const result = await new ChannelPersistenceStartupOwner({
    store,
    clock: { now: () => 10 },
  }).loadAndRepair();

  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.equal(result.repaired, true);
  assert.equal(result.aggregate.lineupRevision, 0);
  assert.equal(result.aggregate.channelBuilderState, null);
  assert.equal(result.aggregate.currentChannelId, 'legacy-channel');
  assert.deepEqual(result.aggregate.storedChannelData?.channelOrder, ['legacy-channel']);
  assert.equal(result.aggregate.storedChannelData?.channels.length, 1);
});

test('startup owner leaves corrupt bytes untouched and returns a fixed safe failure', async () => {
  const userData = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-startup-'));
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
  if (bootstrap.status !== 'ready') return;
  const corrupt = '{private-path:/do/not/expose';
  await fs.writeFile(bootstrap.capability.persistenceFilePath, corrupt);
  const result = await new ChannelPersistenceStartupOwner({
    store: new DesktopChannelPersistenceStore({
      readyCapability: bootstrap.capability,
    }),
    clock: { now: () => 10 },
  }).loadAndRepair();
  assert.deepEqual(result, {
    ok: false,
    error: {
      code: 'CHANNEL_STORAGE_CORRUPT',
      message: 'Channel storage could not be loaded.',
    },
  });
  assert.equal(await fs.readFile(bootstrap.capability.persistenceFilePath, 'utf8'), corrupt);
});
