import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import type { ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import { encodeStoredChannelData } from '../../domain/channel/storedChannelDataCodec.js';
import {
  LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
} from '../../contracts/ipc.js';
import type { PlexRuntimeSnapshot } from '../../contracts/plex.js';
import { ChannelRuntime, type ChannelRuntimeOptions } from '../../main/channel/channelRuntime.js';
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
    channels: [],
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
    channels: [
      {
        id: 'one',
        number: 101,
        name: 'Channel one',
        sourceLibraryId: null,
        sourceLibraryName: null,
        itemCount: 1,
      },
      {
        id: 'two',
        number: 204,
        name: 'Channel two',
        sourceLibraryId: null,
        sourceLibraryName: null,
        itemCount: 1,
      },
    ],
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
  assert.deepEqual(removed, [
    LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
    LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL,
  ]);
});

test('channel runtime commits selected Plex libraries as persisted channel summaries', async () => {
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 1_000 },
    generateId: createIdGenerator('live-channel'),
    plexRuntime: createPlexRuntimeFixture(),
  });

  const result = await runtime.commit('channel-commit-live', {
    mode: 'append',
    sectionIds: ['movies'],
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value.channels : null, [
    {
      id: 'live-channel-1',
      number: 1,
      name: 'Movies',
      sourceLibraryId: 'movies',
      sourceLibraryName: 'Movies',
      itemCount: 2,
    },
  ]);
  assert.equal(result.ok ? result.value.currentChannelId : null, 'live-channel-1');
  assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
});

test('channel runtime serializes concurrent commits against the latest persisted state', async () => {
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 1_000 },
    generateId: createIdGenerator('serialized-channel'),
    plexRuntime: createPlexRuntimeFixture(),
  });

  const [movies, shows] = await Promise.all([
    runtime.commit('channel-commit-concurrent-movies', {
      mode: 'append',
      sectionIds: ['movies'],
    }),
    runtime.commit('channel-commit-concurrent-shows', {
      mode: 'append',
      sectionIds: ['shows'],
    }),
  ]);
  const status = await runtime.getStatus('channel-status-after-concurrent-commit');

  assert.equal(movies.ok, true);
  assert.equal(shows.ok, true);
  assert.equal(status.ok, true);
  assert.deepEqual(status.ok ? status.value.channels.map((channel) => ({
    id: channel.id,
    number: channel.number,
    name: channel.name,
    itemCount: channel.itemCount,
  })) : [], [
    { id: 'serialized-channel-1', number: 1, name: 'Movies', itemCount: 2 },
    { id: 'serialized-channel-2', number: 2, name: 'Shows', itemCount: 1 },
  ]);
  assert.doesNotMatch(JSON.stringify(status), /rawPayload|token|serverUri|https?:/u);
});

test('channel runtime rejects mixed invalid or unknown section ids without partial save', async () => {
  for (const sectionIds of [
    ['movies', 'bad id!'],
    ['movies', 'unknown-section'],
  ]) {
    const storage = createTrackedMemoryStorage(null);
    const runtime = new ChannelRuntime({
      storage,
      clock: { now: () => 1_000 },
      generateId: createIdGenerator('blocked-live-channel'),
      plexRuntime: createPlexRuntimeFixture(),
    });

    const result = await runtime.commit(`channel-commit-invalid-${sectionIds[1]}`, {
      mode: 'append',
      sectionIds,
    });

    assert.equal(result.ok, false);
    assert.equal(result.ok ? null : result.error.code, 'CHANNEL_VALIDATION_FAILED');
    assert.equal(result.ok ? null : result.error.operation, 'commit');
    assert.equal(storage.writeStoredCalls, 0);
    assert.equal(storage.writeCurrentCalls, 0);
    assert.equal(await storage.readStoredChannelData(), null);
    assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
  }
});

test('channel runtime pages all selected library items before saving channel totals', async () => {
  const storage = createMemoryStorage(null);
  const requests: Array<{ offset?: number; limit?: number }> = [];
  const runtime = new ChannelRuntime({
    storage,
    clock: { now: () => 1_000 },
    generateId: createIdGenerator('paged-live-channel'),
    plexRuntime: createPlexRuntimeFixture({}, async (requestId, payload) => {
      requests.push({ offset: payload.offset, limit: payload.limit });
      const pageIndex = Math.floor((payload.offset ?? 0) / 100);
      const items = pageIndex === 0
        ? Array.from({ length: 100 }, (_, index) => plexItem(`movie-${index}`, `Feature ${index}`, 'movie'))
        : [plexItem('movie-100', 'Feature 100', 'movie')];
      return {
        ok: true,
        requestId,
        value: {
          sectionId: payload.sectionId,
          offset: payload.offset ?? 0,
          limit: payload.limit ?? 100,
          items,
          snapshot: createSnapshot(),
        },
      };
    }),
  });

  const result = await runtime.commit('channel-commit-paged-section', {
    mode: 'append',
    sectionIds: ['movies'],
  });

  assert.equal(result.ok, true);
  assert.equal(requests.length, 2);
  assert.equal(requests[0]?.offset, 0);
  assert.ok(requests.every((request) => (request.limit ?? 0) > 0));
  for (let index = 1; index < requests.length; index += 1) {
    const previous = requests[index - 1];
    const current = requests[index];
    assert.equal(
      current?.offset,
      (previous?.offset ?? 0) + (previous?.limit ?? 0),
    );
  }
  assert.deepEqual(result.ok ? result.value.channels.map((channel) => ({
    id: channel.id,
    itemCount: channel.itemCount,
  })) : [], [
    { id: 'paged-live-channel-1', itemCount: 101 },
  ]);
  assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
});

test('channel runtime commits from positive section summary when Plex item listing is empty or retryable', async () => {
  for (const listMode of ['retryable-failed', 'empty'] as const) {
    const storage = createMemoryStorage(null);
    const runtime = new ChannelRuntime({
      storage,
      clock: { now: () => 1_000 },
      generateId: createIdGenerator(`fallback-${listMode}`),
      plexRuntime: createPlexRuntimeFixture({}, async (requestId, payload) => {
        if (listMode === 'retryable-failed') {
          return {
            ok: false,
            requestId,
            error: {
              code: 'PLEX_LIBRARY_FAILED',
              message: 'Library request failed.',
              retryable: true,
              recoverable: true,
              operation: 'listLibraryItems',
            },
          };
        }
        return {
          ok: true,
          requestId,
          value: {
            sectionId: payload.sectionId,
            offset: 0,
            limit: 100,
            items: [],
            snapshot: createSnapshot(),
          },
        };
      }),
    });

    const result = await runtime.commit(`channel-commit-fallback-${listMode}`, {
      mode: 'append',
      sectionIds: ['movies'],
    });

    assert.equal(result.ok, true);
    assert.deepEqual(result.ok ? result.value.channels : null, [
      {
        id: `fallback-${listMode}-1`,
        number: 1,
        name: 'Movies',
        sourceLibraryId: 'movies',
        sourceLibraryName: 'Movies',
        itemCount: 2,
      },
    ]);
    assert.equal(result.ok ? result.value.currentChannelId : null, `fallback-${listMode}-1`);
    assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
  }
});

test('channel runtime does not fall back for hard Plex item listing failures', async () => {
  for (const code of [
    'PLEX_AUTH_REQUIRED',
    'PLEX_RESOURCE_NOT_FOUND',
    'PLEX_VALIDATION_FAILED',
    'PLEX_PARSE_FAILED',
  ] as const) {
    const storage = createTrackedMemoryStorage(null);
    const runtime = new ChannelRuntime({
      storage,
      clock: { now: () => 1_000 },
      generateId: createIdGenerator(`hard-${code}`),
      plexRuntime: createPlexRuntimeFixture({}, async (requestId) => ({
        ok: false,
        requestId,
        error: {
          code,
          message: 'Library request failed.',
          retryable: false,
          recoverable: true,
          operation: 'listLibraryItems',
        },
      })),
    });

    const result = await runtime.commit(`channel-commit-hard-${code}`, {
      mode: 'append',
      sectionIds: ['movies'],
    });

    assert.equal(result.ok, false);
    assert.equal(result.ok ? null : result.error.code, 'CHANNEL_VALIDATION_FAILED');
    assert.equal(result.ok ? null : result.error.operation, 'commit');
    assert.equal(storage.writeStoredCalls, 0);
    assert.equal(storage.writeCurrentCalls, 0);
    assert.equal(await storage.readStoredChannelData(), null);
    assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
  }
});

test('channel runtime does not save truly empty selected sections without usable items', async () => {
  const emptySnapshot = createSnapshot();
  const storage = createTrackedMemoryStorage(null);
  const runtime = new ChannelRuntime({
    storage,
    clock: { now: () => 1_000 },
    generateId: createIdGenerator('empty-live-channel'),
    plexRuntime: createPlexRuntimeFixture({
      library: {
        ...emptySnapshot.library,
        sections: [
          { id: 'movies', title: 'Movies', type: 'movie', contentCount: 0, lastScannedAtMs: 1 },
        ],
      },
    }, async (requestId, payload) => ({
      ok: true,
      requestId,
      value: {
        sectionId: payload.sectionId,
        offset: 0,
        limit: 100,
        items: [],
        snapshot: emptySnapshot,
      },
    })),
  });

  const result = await runtime.commit('channel-commit-empty-selected-section', {
    mode: 'append',
    sectionIds: ['movies'],
  });

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CHANNEL_VALIDATION_FAILED');
  assert.equal(result.ok ? null : result.error.operation, 'commit');
  assert.equal(storage.writeStoredCalls, 0);
  assert.equal(storage.writeCurrentCalls, 0);
  assert.equal(await storage.readStoredChannelData(), null);
  assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
});

test('channel runtime preserves a valid current channel id when appending', async () => {
  const storage = createMemoryStorage(storedData({
    channels: [channel('one', 101), channel('two', 204)],
    channelOrder: ['one', 'two'],
    currentChannelId: 'two',
    savedAt: 11,
  }));
  const runtime = new ChannelRuntime({
    storage,
    clock: { now: () => 1_000 },
    generateId: createIdGenerator('appended'),
    plexRuntime: createPlexRuntimeFixture(),
  });

  const result = await runtime.commit('channel-append-preserve-current', {
    mode: 'append',
    sectionIds: ['movies'],
  });

  assert.equal(result.ok, true);
  assert.equal(result.ok ? result.value.currentChannelId : null, 'two');
  assert.equal(result.ok ? result.value.currentChannelNumber : null, 204);
  assert.deepEqual(
    result.ok ? result.value.channels.map((entry) => entry.id) : [],
    ['one', 'two', 'appended-1'],
  );
});

test('channel runtime requires explicit confirmation before replacing persisted channels', async () => {
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('existing', 101)],
      channelOrder: ['existing'],
      currentChannelId: 'existing',
      savedAt: 11,
    })),
    clock: { now: () => 2_000 },
    generateId: createIdGenerator('replacement'),
    plexRuntime: createPlexRuntimeFixture(),
  });

  const blocked = await runtime.commit('channel-replace-blocked', {
    mode: 'replace',
    sectionIds: ['shows'],
  });

  assert.equal(blocked.ok, false);
  assert.equal(blocked.ok ? null : blocked.error.code, 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED');

  const confirmed = await runtime.commit('channel-replace-confirmed', {
    mode: 'replace',
    sectionIds: ['shows'],
    confirmReplace: true,
  });

  assert.equal(confirmed.ok, true);
  assert.deepEqual(confirmed.ok ? confirmed.value.channels.map((entry) => entry.name) : [], ['Shows']);
  assert.equal(confirmed.ok ? confirmed.value.channelNumbers[0] : null, 1);
});

test('channel runtime fails live commit safely when Plex profile, server, or library is missing', async () => {
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 3_000 },
    plexRuntime: createPlexRuntimeFixture({
      auth: { ...createSnapshot().auth, profile: null },
    }),
  });

  const result = await runtime.commit('channel-commit-missing-plex', {
    mode: 'append',
    sectionIds: ['movies'],
  });

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CHANNEL_PLEX_REQUIRED');
  assert.doesNotMatch(JSON.stringify(result), /rawPayload|token|serverUri|https?:/u);
});

test('channel IPC authorizes and validates commit request envelopes', async () => {
  const handled = new Map<string, (event: unknown, payload: unknown) => unknown>();
  const runtime = new ChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 123 },
    generateId: createIdGenerator('ipc-channel'),
    plexRuntime: createPlexRuntimeFixture(),
  });
  registerChannelIpcHandlers({
    runtime,
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'fallback-request',
    ipcMain: {
      handle: (channelName, handler) => {
        handled.set(channelName, handler as (event: unknown, payload: unknown) => unknown);
      },
      removeHandler: () => undefined,
    },
  });
  const handler = handled.get(LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL);
  assert.ok(handler);

  const success = await handler('authorized', {
    requestId: 'channel-commit-valid',
    payload: { mode: 'append', sectionIds: ['movies'] },
  });
  assert.equal((success as { ok: boolean }).ok, true);

  const unauthorized = await handler('other', {
    requestId: 'channel-commit-valid',
    payload: { mode: 'append', sectionIds: ['movies'] },
  });
  assert.equal((unauthorized as { error: { code: string; operation: string } }).error.code, 'CHANNEL_UNAUTHORIZED');
  assert.equal((unauthorized as { error: { code: string; operation: string } }).error.operation, 'commit');

  const invalid = await handler('authorized', {
    requestId: 'channel-commit-valid',
    payload: { mode: 'append', sectionIds: ['movies'], rawPayload: true },
  });
  assert.equal((invalid as { error: { code: string; operation: string } }).error.code, 'CHANNEL_VALIDATION_FAILED');
  assert.equal((invalid as { error: { code: string; operation: string } }).error.operation, 'commit');

  const mixedInvalid = await handler('authorized', {
    requestId: 'channel-commit-valid',
    payload: { mode: 'append', sectionIds: ['movies', 'bad id!'] },
  });
  assert.equal((mixedInvalid as { error: { code: string; operation: string } }).error.code, 'CHANNEL_VALIDATION_FAILED');
  assert.equal((mixedInvalid as { error: { code: string; operation: string } }).error.operation, 'commit');
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

function createTrackedMemoryStorage(
  initial: StoredChannelData | null,
): ChannelPersistenceStoragePort & {
  readonly writeStoredCalls: number;
  readonly writeCurrentCalls: number;
} {
  let data = initial === null ? null : encodeStoredChannelData(initial);
  let currentChannelId = initial?.currentChannelId ?? null;
  let writeStoredCalls = 0;
  let writeCurrentCalls = 0;
  return {
    get writeStoredCalls() {
      return writeStoredCalls;
    },
    get writeCurrentCalls() {
      return writeCurrentCalls;
    },
    readStoredChannelData: async () => data,
    writeStoredChannelData: async (encoded) => {
      writeStoredCalls += 1;
      data = encoded;
      currentChannelId = JSON.parse(encoded).currentChannelId as string | null;
    },
    clearStoredChannelData: async () => {
      data = null;
      currentChannelId = null;
    },
    readCurrentChannelId: async () => currentChannelId,
    writeCurrentChannelId: async (channelId) => {
      writeCurrentCalls += 1;
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

function createIdGenerator(prefix: string): () => string {
  let counter = 0;
  return () => `${prefix}-${++counter}`;
}

function createPlexRuntimeFixture(
  snapshotPatch: Partial<PlexRuntimeSnapshot> = {},
  listLibraryItems?: (
    requestId: string,
    payload: { sectionId: string; offset?: number; limit?: number },
  ) => ReturnType<NonNullable<ChannelRuntimeOptionsPlexRuntime['listLibraryItems']>>,
): ChannelRuntimeOptionsPlexRuntime {
  return {
    getSnapshot: (requestId) => ({
      ok: true,
      requestId,
      value: { ...createSnapshot(), ...snapshotPatch },
    }),
    listLibraryItems: listLibraryItems ?? (async (requestId, payload) => ({
      ok: true,
      requestId,
      value: {
        sectionId: payload.sectionId,
        offset: 0,
        limit: 100,
        items: payload.sectionId === 'shows'
          ? [plexItem('episode-1', 'Pilot', 'episode')]
          : [
              plexItem('movie-1', 'Feature One', 'movie'),
              plexItem('movie-2', 'Feature Two', 'movie'),
            ],
        snapshot: createSnapshot(),
      },
    })),
  };
}

type ChannelRuntimeOptionsPlexRuntime = NonNullable<
  ChannelRuntimeOptions['plexRuntime']
>;

function createSnapshot(): PlexRuntimeSnapshot {
  return {
    auth: {
      state: 'signed-in',
      pin: null,
      profile: { accountId: 'account-safe', displayName: 'Profile' },
      homeUsers: [],
      credentialStatus: 'present',
    },
    servers: {
      status: 'ready',
      selected: {
        serverId: 'server-safe',
        name: 'Selected server',
        owned: true,
        connectionCount: 1,
        hasLocalConnection: true,
        hasRemoteConnection: false,
        hasRelayConnection: false,
        selected: true,
      },
      items: [],
      lastSelection: null,
    },
    library: {
      status: 'ready',
      sections: [
        { id: 'movies', title: 'Movies', type: 'movie', contentCount: 2, lastScannedAtMs: 1 },
        { id: 'shows', title: 'Shows', type: 'show', contentCount: 1, lastScannedAtMs: 1 },
        { id: 'photos', title: 'Photos', type: 'photo', contentCount: 1, lastScannedAtMs: 1 },
      ],
      selectedSectionId: 'movies',
      items: [],
      search: null,
      metadata: null,
    },
    lastError: null,
    updatedAtMs: 1,
  };
}

function plexItem(
  ratingKey: string,
  title: string,
  type: 'movie' | 'episode',
) {
  return {
    ratingKey,
    type,
    title,
    sortTitle: title,
    summary: '',
    year: 2020,
    durationMs: 1_800_000,
    addedAtMs: 1,
    updatedAtMs: 1,
    ...(type === 'episode' ? { grandparentTitle: 'Shows', seasonNumber: 1, episodeNumber: 1 } : {}),
  };
}
