import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { LINEUP_GUIDE_GET_PRESENTATION_CHANNEL, LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL } from '../../contracts/ipc.js';
import { registerChannelIpcHandlers } from '../../main/channel/channelIpc.js';
import { ChannelPublicReferenceOwner } from '../../main/channel/channelPublicReferenceOwner.js';
import { DesktopGuidePreferencesStore, DesktopGuidePreferencesStoreError } from '../../main/channel/desktopGuidePreferencesStore.js';
import { GuideRuntime } from '../../main/channel/guideRuntime.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import type { ChannelConfig } from '../../domain/channel/types.js';

test('Guide library filter IPC authorizes, validates, dispatches CAS, and removes its handler', async () => {
  const handlers = new Map<string, (event: object, payload: unknown) => Promise<unknown>>();
  const removed: string[] = [];
  let calls = 0;
  const teardown = registerChannelIpcHandlers({
    runtime: { loadPublicReferenceGeneration: async () => ({ lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'one' }) } as never,
    guideRuntime: { isPreferenceScopeCurrent: () => true, setLibraryFilter: async () => { calls += 1; return { scopeToken: 'scope', revision: 2, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' }; } } as never,
    publicReferenceOwner: {} as never,
    isAuthorizedEvent: (event) => event === authorized,
    createRequestId: () => 'fallback',
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: (channel) => removed.push(channel) },
  });
  const authorized = {};
  const handler = handlers.get(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL)!;
  const denied = await handler({}, { requestId: 'request-1', payload: { expectedScopeToken: 'scope', expectedRevision: 1, libraryId: null } }) as { ok: boolean; error: { code: string } };
  assert.equal(denied.error.code, 'GUIDE_UNAUTHORIZED');
  const invalid = await handler(authorized, { requestId: 'request-2', payload: { expectedScopeToken: 'scope', expectedRevision: -1, libraryId: null } }) as { ok: boolean; error: { code: string } };
  assert.equal(invalid.error.code, 'GUIDE_VALIDATION_FAILED');
  const accepted = await handler(authorized, { requestId: 'request-3', payload: { expectedScopeToken: 'scope', expectedRevision: 1, libraryId: null } }) as { ok: boolean; value: { revision: number } };
  assert.equal(accepted.ok, true);
  assert.equal(accepted.value.revision, 2);
  assert.equal(calls, 1);
  await teardown();
  assert.ok(removed.includes(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL));
});

test('Guide filter IPC maps public libraries into the real store and enforces generation currentness', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-ipc-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  const channels: ChannelConfig[] = [guideChannel('channel-a', 1, 'unsafe/library-a'), guideChannel('channel-b', 2, 'library-b')];
  let fingerprint = 'generation-a';
  const generation = () => ({ lineupRevision: 1, channels, currentChannelId: null, fingerprint });
  const owner = new ChannelPublicReferenceOwner();
  const guideRuntime = new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: {
      getLibraryItems: async () => [{ ratingKey: 'item', type: 'movie', title: 'Item', durationMs: 60_000 }],
      getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [], getItem: async () => null,
    } as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 0 } }),
    clock: { now: () => 0 }, preferencesStore: new DesktopGuidePreferencesStore(filePath),
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope-token',
  });
  const handlers = new Map<string, (event: object, payload: unknown) => Promise<unknown>>();
  const authorized = {};
  registerChannelIpcHandlers({
    runtime: { loadPublicReferenceGeneration: async () => generation() } as never,
    guideRuntime, publicReferenceOwner: owner,
    isAuthorizedEvent: (event) => event === authorized, createRequestId: () => 'fallback',
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
  });
  const presentation = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(authorized, {
    requestId: 'presentation', payload: { startTimeMs: 0, durationMs: 60_000 },
  }) as { ok: true; value: { libraryFilter: { scopeToken: string; revision: number; libraries: Array<{ id: string; name: string }> } } };
  assert.equal(presentation.ok, true);
  const unsafeLibrary = presentation.value.libraryFilter.libraries.find((library) => library.name === 'Library 1')!;
  assert.notEqual(unsafeLibrary.id, 'unsafe/library-a');
  const accepted = await handlers.get(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL)!(authorized, {
    requestId: 'set-filter', payload: {
      expectedScopeToken: presentation.value.libraryFilter.scopeToken,
      expectedRevision: presentation.value.libraryFilter.revision,
      libraryId: unsafeLibrary.id,
    },
  }) as { ok: boolean; value: { selectedLibraryId: string } };
  assert.equal(accepted.ok, true);
  assert.equal(accepted.value.selectedLibraryId, unsafeLibrary.id);
  const persisted = JSON.parse(await fs.readFile(filePath, 'utf8')) as { scopes: Array<{ selectedLibraryId: string }> };
  assert.equal(persisted.scopes[0]?.selectedLibraryId, 'unsafe/library-a');
  const beforeUnknown = await fs.readFile(filePath, 'utf8');
  const unknown = await handlers.get(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL)!(authorized, {
    requestId: 'unknown-filter', payload: {
      expectedScopeToken: presentation.value.libraryFilter.scopeToken, expectedRevision: 1, libraryId: 'unknown-library',
    },
  }) as { ok: false; error: { code: string } };
  assert.equal(unknown.error.code, 'GUIDE_VALIDATION_FAILED');
  assert.equal(await fs.readFile(filePath, 'utf8'), beforeUnknown);

  const refreshed = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(authorized, {
    requestId: 'presentation-2', payload: { startTimeMs: 0, durationMs: 60_000 },
  }) as { ok: true; value: { libraryFilter: { scopeToken: string; revision: number } } };
  const originalSet = guideRuntime.setLibraryFilter.bind(guideRuntime);
  guideRuntime.setLibraryFilter = async (input) => {
    const value = await originalSet(input);
    fingerprint = 'generation-b';
    return value;
  };
  const stale = await handlers.get(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL)!(authorized, {
    requestId: 'stale-filter', payload: {
      expectedScopeToken: refreshed.value.libraryFilter.scopeToken,
      expectedRevision: refreshed.value.libraryFilter.revision,
      libraryId: null,
    },
  }) as { ok: false; error: { code: string } };
  assert.equal(stale.error.code, 'GUIDE_FILTER_SCOPE_STALE');
});

test('Guide filter IPC maps every store error and rejects unknown public libraries without a write', async () => {
  const handlers = new Map<string, (event: object, payload: unknown) => Promise<unknown>>();
  const authorized = {};
  let thrown: DesktopGuidePreferencesStoreError | null = null;
  const runtime = {
    isPreferenceScopeCurrent: () => true,
    setLibraryFilter: async () => {
      if (thrown !== null) throw thrown;
      throw new Error('unknown public library');
    },
  };
  registerChannelIpcHandlers({
    runtime: { loadPublicReferenceGeneration: async () => ({ lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'one' }) } as never,
    guideRuntime: runtime as never, publicReferenceOwner: {} as never,
    isAuthorizedEvent: (event) => event === authorized, createRequestId: () => 'fallback',
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
  });
  const handler = handlers.get(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL)!;
  for (const code of [
    'GUIDE_FILTER_SCOPE_STALE', 'GUIDE_FILTER_REVISION_CONFLICT', 'GUIDE_FILTER_STORAGE_UNAVAILABLE',
    'GUIDE_FILTER_UNSUPPORTED_VERSION', 'GUIDE_FILTER_REVISION_EXHAUSTED',
  ] as const) {
    thrown = new DesktopGuidePreferencesStoreError(code);
    const result = await handler(authorized, {
      requestId: `request-${code}`, payload: { expectedScopeToken: 'scope', expectedRevision: 0, libraryId: null },
    }) as { ok: false; error: { code: string; operation: string; retryable: boolean; recoverable: boolean } };
    assert.equal(result.error.code, code);
    assert.equal(result.error.operation, 'setLibraryFilter');
    const terminal = code === 'GUIDE_FILTER_UNSUPPORTED_VERSION' || code === 'GUIDE_FILTER_REVISION_EXHAUSTED';
    assert.equal(result.error.retryable, !terminal);
    assert.equal(result.error.recoverable, !terminal);
  }
  thrown = null;
  const unknown = await handler(authorized, {
    requestId: 'unknown-library', payload: { expectedScopeToken: 'scope', expectedRevision: 0, libraryId: 'unknown' },
  }) as { ok: false; error: { code: string } };
  assert.equal(unknown.error.code, 'GUIDE_VALIDATION_FAILED');
});

test('Guide filter IPC fails closed when destroyed sender inspection throws at the blocked pre-rename barrier', async () => {
  const writes = new Map<string, string>();
  const removedTemps: string[] = [];
  let renameCount = 0;
  let blockFirstCommit = true;
  const commitEntered = createDeferred<void>();
  const commitRelease = createDeferred<void>();
  const store = new DesktopGuidePreferencesStore('guide-preferences.json', {
    fileSystem: {
      readFile: async () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); },
      mkdir: async () => undefined,
      writeFile: async (filePath, content) => { writes.set(filePath, content); },
      chmod: async () => {
        if (blockFirstCommit) {
          blockFirstCommit = false;
          commitEntered.resolve();
          await commitRelease.promise;
        }
      },
      rename: async (sourcePath, destinationPath) => {
        renameCount += 1;
        writes.set(destinationPath, writes.get(sourcePath)!);
        writes.delete(sourcePath);
      },
      unlink: async (filePath) => { removedTemps.push(filePath); writes.delete(filePath); },
    },
    processId: 17,
  });
  const channels: ChannelConfig[] = [guideChannel('channel-a', 1, 'library-a'), guideChannel('channel-b', 2, 'library-b')];
  const generation = { lineupRevision: 1, channels, currentChannelId: null, fingerprint: 'generation' };
  const owner = new ChannelPublicReferenceOwner();
  const guideRuntime = new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: {
      getLibraryItems: async () => [], getCollectionItems: async () => [], getShowEpisodes: async () => [],
      getPlaylistItems: async () => [], getItem: async () => null,
    } as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 0 } }),
    clock: { now: () => 0 }, preferencesStore: store,
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope-token',
  });
  const handlers = new Map<string, (event: object, payload: unknown) => Promise<unknown>>();
  let senderInspectionThrows = false;
  const mainFrame = { url: 'lineup://shell/index.html' };
  const webContents = {
    isDestroyed: () => {
      if (senderInspectionThrows) throw new Error('destroyed sender is unavailable');
      return false;
    },
    getURL: () => {
      if (senderInspectionThrows) throw new Error('destroyed sender URL is unavailable');
      return 'lineup://shell/index.html';
    },
    mainFrame,
  };
  const sender = { sender: webContents, senderFrame: mainFrame };
  registerChannelIpcHandlers({
    runtime: { loadPublicReferenceGeneration: async () => generation } as never,
    guideRuntime, publicReferenceOwner: owner,
    isAuthorizedEvent: (event) => {
      const candidate = event as unknown as typeof sender;
      return candidate.sender === webContents && !candidate.sender.isDestroyed() &&
        candidate.sender.getURL() === 'lineup://shell/index.html' &&
        candidate.senderFrame === candidate.sender.mainFrame;
    },
    createRequestId: () => 'fallback',
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
  });
  const presentation = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(sender, {
    requestId: 'presentation', payload: { startTimeMs: 0, durationMs: 60_000 },
  }) as { ok: true; value: { libraryFilter: { scopeToken: string; revision: number } } };
  const handler = handlers.get(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL)!;
  const blocked = handler(sender, {
    requestId: 'blocked-filter', payload: {
      expectedScopeToken: presentation.value.libraryFilter.scopeToken,
      expectedRevision: presentation.value.libraryFilter.revision,
      libraryId: null,
    },
  }) as Promise<{ ok: false; error: { code: string } }>;
  await commitEntered.promise;
  senderInspectionThrows = true;
  commitRelease.resolve();
  const rejected = await blocked;
  assert.equal(rejected.error.code, 'GUIDE_UNAUTHORIZED');
  assert.equal(renameCount, 0);
  assert.deepEqual(removedTemps, ['guide-preferences.json.17.1.tmp']);
  assert.equal(writes.size, 0);

  senderInspectionThrows = false;
  const accepted = await handler(sender, {
    requestId: 'accepted-filter', payload: {
      expectedScopeToken: presentation.value.libraryFilter.scopeToken,
      expectedRevision: presentation.value.libraryFilter.revision,
      libraryId: null,
    },
  }) as { ok: true; value: { revision: number } };
  assert.equal(accepted.ok, true);
  assert.equal(accepted.value.revision, 1);
  assert.equal(renameCount, 1);
});

function guideChannel(id: string, number: number, libraryId: string): ChannelConfig {
  return {
    id, number, name: `Channel ${number}`, playbackMode: 'sequential', startTimeAnchor: 0,
    skipIntros: false, skipCredits: false, createdAt: 0, updatedAt: 0, lastContentRefresh: 0,
    itemCount: 1, totalDurationMs: 60_000, sourceLibraryId: libraryId, sourceLibraryName: `Library ${number}`,
    contentSource: { type: 'library', libraryId, libraryType: 'movie', includeWatched: true },
  };
}

interface Deferred<T> { promise: Promise<T>; resolve(value: T): void }
function createDeferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  return { promise: new Promise<T>((done) => { resolve = done; }), resolve };
}
