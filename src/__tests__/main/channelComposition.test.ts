import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import type { IpcMainInvokeEvent } from 'electron';

import {
  registerChannelComposition,
  sanitizeChannelDiagnosticDetail,
} from '../../main/channel/channelComposition.js';

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
  const localPath = ['/Users/example/Library/Application Support/Lineup/secret.json'].join('');
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
      'file://C:/Users/example/AppData/secret.json',
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
  assert.equal(serialized.includes('file://C:/Users/example'), false);
  assert.equal(serialized.includes('/Users/example'), false);
  assert.match(serialized, /\[redacted\]/u);
  assert.equal(serialized.includes('Authorization'), false);
});

test('channel composition injects a clock into the active channel scheduler', async () => {
  const restoreElectron = replaceElectronIpcMain(new FakeIpcMain());
  const userDataDirectory = await mkdtemp(join(tmpdir(), 'lineup-channel-composition-'));
  try {
    const registration = registerChannelComposition({
      app: {
        getPath: (name) => {
          assert.equal(name, 'userData');
          return userDataDirectory;
        },
      },
      shellMode: 'smoke',
      isAuthorizedEvent: () => true,
      createRequestId: (prefix) => `${prefix}-test`,
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
      } as never,
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
