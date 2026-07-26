import test from 'node:test';
import assert from 'node:assert/strict';
import { constants as fsConstants } from 'node:fs';
import path from 'node:path';

import {
  ChannelPersistenceBootstrapOwner,
  type ChannelPersistenceReadyCapability,
} from '../../main/persistence/channelPersistenceBootstrapOwner.js';
import {
  DesktopChannelPersistenceStore,
  type DesktopChannelPersistenceFileHandle,
  type DesktopChannelPersistenceFileStat,
} from '../../main/persistence/desktopChannelPersistenceStore.js';

const regularStat = (ino: number, mode = 0o100600): DesktopChannelPersistenceFileStat => ({
  dev: 1,
  ino,
  mode,
  isFile: () => true,
  isSymbolicLink: () => false,
});

test('cancel barrier follows existing destination read and precedes every write-capable open', async () => {
  const capability = await capabilityFor('linux');
  const calls: string[] = [];
  const destination = JSON.stringify({
    schemaVersion: 1,
    storedChannelData: null,
    currentChannelId: null,
    lineupRevision: 0,
  });
  const store = new DesktopChannelPersistenceStore({
    readyCapability: capability,
    fileSystem: {
      lstat: async () => {
        calls.push('lstat-destination');
        return regularStat(1);
      },
      open: async (_filePath, flags) => {
        calls.push(`open:${String(flags)}`);
        assert.equal(flags, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
        return readHandle(destination, calls);
      },
      rename: async () => {
        calls.push('rename');
      },
      unlink: async () => {
        calls.push('unlink');
      },
    },
    randomHex128: () => 'c'.repeat(32),
  });

  const result = await store.mutateChannelAggregate({
    kind: 'builder-lineup',
    expectedLineupRevision: 0,
    mutate: (current) => current as typeof current,
    onCommitBarrier: () => {
      calls.push('barrier-cancel');
      return 'cancel';
    },
  });

  assert.deepEqual(result, { status: 'canceled' });
  assert.deepEqual(calls, [
    'lstat-destination',
    `open:${String(fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW)}`,
    'handle-stat',
    'handle-read',
    'handle-close',
    'barrier-cancel',
  ]);
});

test('POSIX and Windows use their exact distinct exclusive temporary open flags', async () => {
  for (const platform of ['linux', 'win32'] as const) {
    const capability = await capabilityFor(platform);
    const opens: Array<{ flags: number; mode: number | undefined }> = [];
    let destinationPresent = false;
    const store = new DesktopChannelPersistenceStore({
      readyCapability: capability,
      fileSystem: {
        lstat: async (filePath) => {
          if (filePath === capability.persistenceFilePath) {
            if (!destinationPresent) throw nodeError('ENOENT');
            return regularStat(9);
          }
          return regularStat(7);
        },
        open: async (_filePath, flags, mode) => {
          opens.push({ flags, mode });
          return writeHandle(platform, regularStat(7));
        },
        rename: async () => {
          destinationPresent = true;
        },
        unlink: async () => undefined,
      },
      randomHex128: () => 'd'.repeat(32),
    });
    const result = await store.mutateChannelAggregate({
      kind: 'custom-lineup',
      expectedLineupRevision: null,
      mutate: (current) => current as typeof current,
      onCommitBarrier: () => 'proceed',
    });
    assert.equal(result.status, 'committed');
    assert.deepEqual(opens, [
      platform === 'win32'
        ? {
            flags: fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY,
            mode: undefined,
          }
        : {
            flags:
              fsConstants.O_CREAT |
              fsConstants.O_EXCL |
              fsConstants.O_WRONLY |
              fsConstants.O_NOFOLLOW,
            mode: 0o600,
          },
    ]);
  }
});

test('destination close failure is unavailable and prevents the commit barrier', async () => {
  const capability = await capabilityFor('linux');
  let barrierCalls = 0;
  const handle = readHandle(JSON.stringify({
    schemaVersion: 1,
    storedChannelData: null,
    currentChannelId: null,
    lineupRevision: 0,
  }), []);
  handle.close = async () => {
    throw new Error('close failed');
  };
  const store = new DesktopChannelPersistenceStore({
    readyCapability: capability,
    fileSystem: {
      lstat: async () => regularStat(1),
      open: async () => handle,
      rename: async () => assert.fail('rename must not run'),
      unlink: async () => assert.fail('unlink must not run'),
    },
    randomHex128: () => 'e'.repeat(32),
  });

  await assert.rejects(
    store.mutateChannelAggregate({
      kind: 'custom-lineup',
      expectedLineupRevision: null,
      mutate: (current) => current as typeof current,
      onCommitBarrier: () => {
        barrierCalls += 1;
        return 'proceed';
      },
    }),
    /unavailable/iu,
  );
  assert.equal(barrierCalls, 0);
});

test('temporary close failure is unavailable, cleans up, and never renames', async () => {
  const capability = await capabilityFor('linux');
  const calls: string[] = [];
  const handle = writeHandle('linux', regularStat(7));
  handle.close = async () => {
    calls.push('close');
    throw new Error('close failed');
  };
  const store = new DesktopChannelPersistenceStore({
    readyCapability: capability,
    fileSystem: {
      lstat: async (filePath) => {
        calls.push(`lstat:${filePath}`);
        if (filePath === capability.persistenceFilePath) throw nodeError('ENOENT');
        return regularStat(7, 0o100600);
      },
      open: async () => handle,
      rename: async () => {
        calls.push('rename');
      },
      unlink: async () => {
        calls.push('unlink');
      },
    },
    randomHex128: () => 'f'.repeat(32),
  });

  await assert.rejects(
    store.mutateChannelAggregate({
      kind: 'custom-lineup',
      expectedLineupRevision: null,
      mutate: (current) => current as typeof current,
      onCommitBarrier: () => 'proceed',
    }),
    /unavailable/iu,
  );
  assert.equal(calls.includes('rename'), false);
  assert.equal(calls.includes('unlink'), true);
});

async function capabilityFor(platform: string): Promise<ChannelPersistenceReadyCapability> {
  const userData = path.resolve('/validated-user-data');
  const result = await new ChannelPersistenceBootstrapOwner({
    app: { getPath: () => userData },
    platform,
    fileSystem: {
      realpath: async (value) => value,
      mkdir: async () => undefined,
      lstat: async () => ({
        isDirectory: () => true,
        isSymbolicLink: () => false,
      }),
    },
  }).bootstrap();
  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') throw new Error('bootstrap failed');
  return result.capability;
}

function readHandle(
  content: string,
  calls: string[],
): DesktopChannelPersistenceFileHandle {
  return {
    stat: async () => {
      calls.push('handle-stat');
      return regularStat(1);
    },
    readFile: async () => {
      calls.push('handle-read');
      return content;
    },
    writeFile: async () => {
      calls.push('handle-write');
    },
    chmod: async () => {
      calls.push('handle-chmod');
    },
    sync: async () => {
      calls.push('handle-sync');
    },
    close: async () => {
      calls.push('handle-close');
    },
  };
}

function writeHandle(
  platform: 'linux' | 'win32',
  stat: DesktopChannelPersistenceFileStat,
): DesktopChannelPersistenceFileHandle {
  let mode = stat.mode;
  return {
    stat: async () => ({ ...stat, mode }),
    readFile: async () => '',
    writeFile: async () => undefined,
    chmod: async (nextMode) => {
      assert.equal(platform, 'linux');
      mode = 0o100000 | nextMode;
    },
    sync: async () => undefined,
    close: async () => undefined,
  };
}

function nodeError(code: string): Error & { code: string } {
  return Object.assign(new Error(code), { code });
}
