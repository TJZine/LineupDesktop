import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import fs from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import process from 'node:process';
import type { IpcMainInvokeEvent } from 'electron';

import { LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL } from '../../contracts/ipc.js';
import {
  createChannelComposition,
  registerChannelCompositionIpc,
  sanitizeChannelDiagnosticDetail,
} from '../../main/channel/channelComposition.js';
import { ChannelPersistenceBootstrapOwner } from '../../main/persistence/channelPersistenceBootstrapOwner.js';

type Handler = (event: IpcMainInvokeEvent, payload?: unknown) => unknown;

class FakeIpcMain {
  readonly handlers = new Map<string, Handler>();

  handle(channel: string, handler: Handler): void {
    this.handlers.set(channel, handler);
  }

  removeHandler(channel: string): void {
    this.handlers.delete(channel);
  }
}

test('channel diagnostic sanitization redacts string primitives inside arrays', () => {
  const tokenQueryUrl = [
    'https://plex.example.invalid/library',
    '?',
    'X-Plex-',
    'Token',
    '=secret-token',
  ].join('');
  const authorizationHeader = ['Author', 'ization', ': ', 'Bearer', ' secret-token'].join('');
  const rawHeaderMap = ['headers={X-Plex-', 'Token: secret-token}'].join('');
  const localPath = ['', 'Users', 'example', 'Library', 'Application Support', 'Lineup', 'secret.json'].join('/');
  const windowsFileUrl = ['file://C:', 'Users', 'example', 'AppData', 'secret.json'].join('/');
  const unixUserPathPrefix = ['', 'Users', 'example'].join('/');
  const nestedTokenUrl = [
    'https://nested.example.invalid/path',
    '?',
    'to',
    'ken',
    '=nested-secret',
  ].join('');
  const sanitized = sanitizeChannelDiagnosticDetail({
    values: [
      tokenQueryUrl,
      authorizationHeader,
      windowsFileUrl,
      rawHeaderMap,
      localPath,
      {
        nestedUrl: nestedTokenUrl,
      },
    ],
  });
  const serialized = JSON.stringify(sanitized);

  assert.equal(serialized.includes('secret-token'), false);
  assert.equal(serialized.includes('nested-secret'), false);
  assert.equal(serialized.includes('https://plex.example.invalid'), false);
  assert.equal(serialized.includes(['file://C:', 'Users', 'example'].join('/')), false);
  assert.equal(serialized.includes(unixUserPathPrefix), false);
  assert.match(serialized, /\[redacted\]/u);
  assert.equal(serialized.includes('Authorization'), false);
});

test('channel composition injects a clock into the active channel scheduler', async () => {
  const restoreElectron = replaceElectronIpcMain(new FakeIpcMain());
  const userDataDirectory = await mkdtemp(join(tmpdir(), 'lineup-channel-composition-'));
  try {
    const readyCapability = await bootstrapChannelPersistence(userDataDirectory);
    const composition = createChannelComposition({
      persistence: { kind: 'disk', readyCapability },
      plexRuntime: {
        getSnapshot: (requestId: string) => ({
          ok: true,
          requestId,
          value: { updatedAtMs: 1 },
        }),
        listLibraryItems: () => ({
          ok: true,
          requestId: 'channel-composition-test',
          value: { sectionId: '1', offset: 0, limit: 0, items: [], snapshot: { updatedAtMs: 1 } },
        }),
        getBuilderContextForMain: () => null,
        subscribeBuilderContextForMain: () => () => undefined,
        withChannelBuilderFacetSession: async () => assert.fail('unexpected builder session'),
      } as never,
    });
    const registration = registerChannelCompositionIpc(composition, {
      shellMode: 'smoke',
      isAuthorizedEvent: () => true,
      createRequestId: (prefix: string) => `${prefix}-test`,
    });

    registration.activeChannelScheduler.loadChannel({
      channelId: 'channel-1',
      anchorTime: Date.now() - 1_000,
      content: [
        {
          ratingKey: 'movie-1',
          type: 'movie',
          title: 'Movie 1',
          fullTitle: 'Movie 1',
          durationMs: 60_000,
          thumb: null,
          year: 2026,
          scheduledIndex: 0,
        },
      ],
      playbackMode: 'sequential',
      shuffleSeed: 0,
    });

    const state = registration.activeChannelScheduler.getState();
    assert.equal(state.isActive, true);
    assert.equal(state.channelId, 'channel-1');
    assert.equal(typeof state.lastSyncTime, 'number');

    await registration.teardown();
  } finally {
    restoreElectron();
    await rm(userDataDirectory, { recursive: true, force: true });
  }
});

test('channel composition refreshes active scheduler after custom channel save', async () => {
  const fakeIpcMain = new FakeIpcMain();
  const restoreElectron = replaceElectronIpcMain(fakeIpcMain);
  const userDataDirectory = await mkdtemp(join(tmpdir(), 'lineup-custom-channel-composition-'));
  try {
    const readyCapability = await bootstrapChannelPersistence(userDataDirectory);
    const composition = createChannelComposition({
      persistence: { kind: 'disk', readyCapability },
      plexRuntime: {
        getSnapshot: (requestId: string) => ({
          ok: true,
          requestId,
          value: { updatedAtMs: 1 },
        }),
        listLibraryItems: () => ({
          ok: true,
          requestId: 'channel-composition-test',
          value: { sectionId: '1', offset: 0, limit: 0, items: [], snapshot: { updatedAtMs: 1 } },
        }),
        getBuilderContextForMain: () => null,
        subscribeBuilderContextForMain: () => () => undefined,
        withChannelBuilderFacetSession: async () => assert.fail('unexpected builder session'),
      } as never,
    });
    const registration = registerChannelCompositionIpc(composition, {
      shellMode: 'smoke',
      isAuthorizedEvent: () => true,
      createRequestId: (prefix: string) => `${prefix}-test`,
    });
    const saveHandler = fakeIpcMain.handlers.get(LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL);
    assert.ok(saveHandler);

    const result = await saveHandler({} as IpcMainInvokeEvent, {
      requestId: 'custom-save-composition',
      payload: {
        number: 101,
        name: 'Manual Custom',
        hidden: false,
        content: [{
          type: 'manualItem',
          ratingKey: 'movie-1',
          title: 'Movie 1',
          durationMs: 60_000,
          mediaType: 'movie',
        }],
        playbackMode: 'sequential',
      },
    });

    assert.equal((result as { ok: boolean }).ok, true);
    const currentChannelId = (result as { value: { currentChannelId: string | null } }).value.currentChannelId;
    assert.equal(typeof currentChannelId, 'string');
    const schedulerState = registration.activeChannelScheduler.getState();
    assert.equal(schedulerState.isActive, true);
    assert.equal(schedulerState.channelId, currentChannelId);

    await registration.teardown();
  } finally {
    restoreElectron();
    await rm(userDataDirectory, { recursive: true, force: true });
  }
});

async function bootstrapChannelPersistence(userDataDirectory: string) {
  const result = await new ChannelPersistenceBootstrapOwner({
    app: { getPath: () => userDataDirectory },
    platform: process.platform,
    fileSystem: {
      realpath: (value) => fs.realpath(value),
      lstat: (value) => fs.lstat(value),
      mkdir: async (value, options) => {
        await fs.mkdir(value, options);
      },
    },
  }).bootstrap();
  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') throw new Error('channel bootstrap failed');
  return result.capability;
}

function replaceElectronIpcMain(ipcMain: FakeIpcMain): () => void {
  const require = createRequire(import.meta.url);
  const electronModulePath = require.resolve('electron');
  require('electron');
  const cacheEntry = require.cache[electronModulePath];
  assert.ok(cacheEntry, 'electron module cache entry was not available');
  const previousExports = cacheEntry.exports;
  cacheEntry.exports = { ipcMain };
  return () => {
    cacheEntry.exports = previousExports;
  };
}
