import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import type { ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import { encodeStoredChannelData } from '../../domain/channel/storedChannelDataCodec.js';
import { LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL } from '../../contracts/ipc.js';
import { ChannelRuntime } from '../../main/channel/channelRuntime.js';
import { registerChannelIpcHandlers } from '../../main/channel/channelIpc.js';
import { DesktopChannelPersistenceStore } from '../../main/persistence/desktopChannelPersistenceStore.js';

test('channel runtime exposes renderer-safe not-configured status when no channels are persisted', async () => {
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 123 },
  });

  const result = await runtime.getStatus('channel-status-1');

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value : null, {
    status: 'not-configured',
    channelCount: 0,
    currentChannelId: null,
    currentChannelNumber: null,
    currentChannelName: null,
    channelNumbers: [],
    updatedAtMs: 123,
    recovery: { loaded: false, repaired: false },
  });
  assert.doesNotMatch(JSON.stringify(result), /storedChannelData|persistenceFilePath|serverUri|token/u);
});

test('channel runtime recovers persisted channel summaries without raw persisted state', async () => {
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('one', 101), channel('two', 204)],
      channelOrder: ['one', 'two'],
      currentChannelId: 'two',
      savedAt: 11,
    })),
    clock: { now: () => 456 },
  });

  const result = await runtime.getStatus('channel-status-2');

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value : null, {
    status: 'configured',
    channelCount: 2,
    currentChannelId: 'two',
    currentChannelNumber: 204,
    currentChannelName: 'Channel two',
    channelNumbers: [101, 204],
    updatedAtMs: 456,
    recovery: { loaded: true, repaired: true },
  });
  assert.doesNotMatch(JSON.stringify(result), /manual-item|storedChannelData|rawPayload/u);
});

test('channel runtime reports corrupt persistence distinctly from not-configured state', async () => {
  const storage = createRawStorage('{not valid json');
  const runtime = new ChannelRuntime({
    storage,
    clock: { now: () => 789 },
  });

  const result = await runtime.getStatus('channel-status-corrupt');

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CHANNEL_STORAGE_CORRUPT');
  assert.equal(result.ok ? null : result.error.message, 'Channel setup data could not be recovered.');
  assert.equal(storage.raw, null);
  assert.doesNotMatch(JSON.stringify(result), /not valid json|storedChannelData|persistenceFilePath|token/u);
});

test('channel runtime reports top-level corrupt desktop persistence after safe repair', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-runtime-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  await fs.writeFile(persistenceFilePath, '{corrupt-json');
  const runtime = new ChannelRuntime({
    storage: new DesktopChannelPersistenceStore({ persistenceFilePath }),
    clock: { now: () => 789 },
  });

  const result = await runtime.getStatus('channel-status-top-level-corrupt');

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CHANNEL_STORAGE_CORRUPT');
  assert.equal(result.ok ? null : result.error.message, 'Channel setup data could not be recovered.');
  assert.doesNotMatch(JSON.stringify(result), /corrupt-json|storedChannelData|persistenceFilePath|token/u);

  const repaired = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    storedChannelData?: unknown;
    currentChannelId?: unknown;
  };
  assert.equal(repaired.storedChannelData, null);
  assert.equal(repaired.currentChannelId, null);
});

test('channel runtime reports top-level schema-invalid desktop persistence after safe repair', async () => {
  const temporaryDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-channel-runtime-'));
  const persistenceFilePath = path.join(temporaryDirectory, 'channels.json');
  await fs.writeFile(
    persistenceFilePath,
    '{"schemaVersion":1,"storedChannelData":"bad","currentChannelId":null}\n',
  );
  const runtime = new ChannelRuntime({
    storage: new DesktopChannelPersistenceStore({ persistenceFilePath }),
    clock: { now: () => 789 },
  });

  const result = await runtime.getStatus('channel-status-schema-invalid');

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CHANNEL_STORAGE_CORRUPT');
  assert.equal(result.ok ? null : result.error.message, 'Channel setup data could not be recovered.');
  assert.doesNotMatch(JSON.stringify(result), /storedChannelData|persistenceFilePath|token|bad/u);

  const repaired = JSON.parse(await fs.readFile(persistenceFilePath, 'utf8')) as {
    storedChannelData?: unknown;
    currentChannelId?: unknown;
  };
  assert.equal(repaired.storedChannelData, null);
  assert.equal(repaired.currentChannelId, null);
});

test('channel runtime reports unavailable persistence without leaking storage details', async () => {
  const runtime = new ChannelRuntime({
    storage: {
      readStoredChannelData: async () => {
        throw new Error('EACCES C:\\Users\\private\\channels.json token=private');
      },
      writeStoredChannelData: async () => undefined,
      clearStoredChannelData: async () => undefined,
      readCurrentChannelId: async () => null,
      writeCurrentChannelId: async () => undefined,
    },
    clock: { now: () => 789 },
  });

  const result = await runtime.getStatus('channel-status-unavailable');

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CHANNEL_STORAGE_UNAVAILABLE');
  assert.equal(result.ok ? null : result.error.message, 'Channel setup storage is unavailable.');
  assert.doesNotMatch(JSON.stringify(result), /EACCES|Users|channels\.json|token/u);
});

test('channel IPC authorizes and validates the status request envelope', async () => {
  const handled = new Map<string, (event: unknown, payload: unknown) => unknown>();
  const removed: string[] = [];
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 123 },
  });
  const teardown = registerChannelIpcHandlers({
    runtime,
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'fallback-request',
    ipcMain: {
      handle: (channelName, handler) => {
        handled.set(channelName, handler as (event: unknown, payload: unknown) => unknown);
      },
      removeHandler: (channelName) => {
        removed.push(channelName);
      },
    },
  });
  const handler = handled.get(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL);
  assert.ok(handler);

  const success = await handler('authorized', {
    requestId: 'channel-status-valid',
    payload: {},
  });
  assert.equal((success as { ok: boolean }).ok, true);

  const unauthorized = handler('other', { requestId: 'channel-status-valid', payload: {} });
  assert.equal((unauthorized as { ok: boolean }).ok, false);
  assert.equal((unauthorized as { error: { code: string } }).error.code, 'CHANNEL_UNAUTHORIZED');

  const invalid = handler('authorized', { requestId: 'channel-status-valid', payload: { extra: true } });
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal((invalid as { error: { code: string } }).error.code, 'CHANNEL_VALIDATION_FAILED');

  await teardown();
  assert.deepEqual(removed, [LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL]);
});

function createMemoryStorage(initial: StoredChannelData | null): ChannelPersistenceStoragePort {
  let data = initial === null ? null : encodeStoredChannelData(initial);
  let currentChannelId = initial?.currentChannelId ?? null;
  return {
    readStoredChannelData: async () => data,
    writeStoredChannelData: async (encoded) => {
      data = encoded;
      currentChannelId = JSON.parse(encoded).currentChannelId as string | null;
    },
    clearStoredChannelData: async () => {
      data = null;
      currentChannelId = null;
    },
    readCurrentChannelId: async () => currentChannelId,
    writeCurrentChannelId: async (channelId) => {
      currentChannelId = channelId;
    },
  };
}

function createRawStorage(initial: string | null): ChannelPersistenceStoragePort & { raw: string | null } {
  let raw = initial;
  return {
    get raw() {
      return raw;
    },
    set raw(value: string | null) {
      raw = value;
    },
    readStoredChannelData: async () => raw,
    writeStoredChannelData: async (encoded) => {
      raw = encoded;
    },
    clearStoredChannelData: async () => {
      raw = null;
    },
    readCurrentChannelId: async () => null,
    writeCurrentChannelId: async () => undefined,
  };
}

function storedData(data: StoredChannelData): StoredChannelData {
  return data;
}

function channel(id: string, number: number) {
  return {
    id,
    number,
    name: `Channel ${id}`,
    contentSource: {
      type: 'manual' as const,
      items: [{ ratingKey: `manual-item-${id}`, title: `Item ${id}`, durationMs: 60_000 }],
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
