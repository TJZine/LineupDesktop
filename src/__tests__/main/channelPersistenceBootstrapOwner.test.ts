import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';

import {
  ChannelPersistenceBootstrapOwner,
  type ChannelPersistenceBootstrapFileSystem,
} from '../../main/persistence/channelPersistenceBootstrapOwner.js';

test('channel persistence bootstrap creates and binds the canonical persistence parent', async () => {
  const userData = path.resolve('/safe/user-data');
  const calls: string[] = [];
  const fileSystem: ChannelPersistenceBootstrapFileSystem = {
    realpath: async (value) => value,
    mkdir: async (value) => {
      calls.push(`mkdir:${value}`);
    },
    lstat: async () => ({
      isDirectory: () => true,
      isSymbolicLink: () => false,
    }),
  };
  const result = await new ChannelPersistenceBootstrapOwner({
    app: { getPath: () => userData },
    fileSystem,
    platform: 'linux',
  }).bootstrap();

  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') return;
  assert.equal(result.capability.canonicalParentPath, path.join(userData, 'persistence'));
  assert.equal(result.capability.protectionPolicy, 'posix-0600');
  assert.deepEqual(calls, [`mkdir:${path.join(userData, 'persistence')}`]);
});

test('channel persistence bootstrap fails closed for symlink and path failures', async () => {
  for (const fileSystem of [
    {
      realpath: async (value: string) => value,
      mkdir: async () => undefined,
      lstat: async () => ({
        isDirectory: () => true,
        isSymbolicLink: () => true,
      }),
    },
    {
      realpath: async () => {
        throw new Error('raw path detail');
      },
      mkdir: async () => undefined,
      lstat: async () => ({
        isDirectory: () => true,
        isSymbolicLink: () => false,
      }),
    },
  ] satisfies ChannelPersistenceBootstrapFileSystem[]) {
    const result = await new ChannelPersistenceBootstrapOwner({
      app: { getPath: () => path.resolve('/safe/user-data') },
      fileSystem,
      platform: 'win32',
    }).bootstrap();
    assert.deepEqual(result, {
      status: 'failed',
      error: {
        code: 'CHANNEL_STORAGE_UNAVAILABLE',
        message: 'Channel storage is unavailable.',
      },
    });
  }
});
