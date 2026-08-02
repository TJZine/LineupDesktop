import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import {
  DesktopGuidePreferencesStore,
  DesktopGuidePreferencesStoreError,
  type DesktopGuidePreferencesFileSystem,
} from '../../main/channel/desktopGuidePreferencesStore.js';

test('Guide preferences v1 owns missing, CAS, tombstone, corruption recovery, and scope isolation', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-preferences-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  const store = new DesktopGuidePreferencesStore(filePath, { processId: 7 });
  const first = await store.activateScope({ serverId: 'server-a', profileId: 'profile-a', scopeToken: 'scope-a' });
  assert.deepEqual(first, { scopeToken: 'scope-a', revision: 0, selectedLibraryId: null, persistenceStatus: 'missing' });
  const selected = await store.setLibraryFilter('scope-a', 0, 'library-a');
  assert.equal(selected.revision, 1);
  assert.equal(selected.selectedLibraryId, 'library-a');
  await assert.rejects(store.setLibraryFilter('scope-a', 0, null), (error: unknown) =>
    error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_REVISION_CONFLICT');
  const all = await store.setLibraryFilter('scope-a', 1, null);
  assert.equal(all.revision, 2);
  const persisted = JSON.parse(await fs.readFile(filePath, 'utf8')) as { scopes: Array<{ selectedLibraryId: string | null; revision: number }> };
  assert.deepEqual(persisted.scopes[0], { serverId: 'server-a', profileId: 'profile-a', selectedLibraryId: null, revision: 2 });

  const second = await store.activateScope({ serverId: 'server-a', profileId: 'profile-b', scopeToken: 'scope-b' });
  assert.equal(second.revision, 0);
  assert.equal(second.persistenceStatus, 'ready');
  await assert.rejects(store.setLibraryFilter('scope-a', 2, null), (error: unknown) =>
    error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_SCOPE_STALE');

  await fs.writeFile(filePath, '{bad json', 'utf8');
  const recovering = new DesktopGuidePreferencesStore(filePath);
  const corrupt = await recovering.activateScope({ serverId: 'server-c', profileId: 'profile-c', scopeToken: 'scope-c' });
  assert.equal(corrupt.persistenceStatus, 'corrupt');
  const recovered = await recovering.setLibraryFilter('scope-c', 0, null);
  assert.equal(recovered.revision, 1);
  assert.equal(recovered.persistenceStatus, 'ready');
});

test('Guide preferences v1 blocks future schema and rejects input above one MiB', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-preferences-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  await fs.writeFile(filePath, JSON.stringify({ schemaVersion: 2, scopes: [] }), 'utf8');
  const future = new DesktopGuidePreferencesStore(filePath);
  const snapshot = await future.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope' });
  assert.equal(snapshot.persistenceStatus, 'unsupported-version');
  await assert.rejects(future.setLibraryFilter('scope', 0, null), (error: unknown) =>
    error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_UNSUPPORTED_VERSION');

  await fs.writeFile(filePath, ' '.repeat(1024 * 1024 + 1), 'utf8');
  const oversized = new DesktopGuidePreferencesStore(filePath);
  assert.equal((await oversized.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'next-scope' })).persistenceStatus, 'corrupt');

  await fs.writeFile(filePath, JSON.stringify({ schemaVersion: 0, scopes: [] }), 'utf8');
  const priorVersion = new DesktopGuidePreferencesStore(filePath);
  assert.equal((await priorVersion.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'prior-scope' })).persistenceStatus, 'corrupt');

  await fs.writeFile(filePath, JSON.stringify({
    schemaVersion: 1,
    scopes: [{ serverId: '😀'.repeat(257), profileId: 'profile', selectedLibraryId: null, revision: 1 }],
  }), 'utf8');
  const oversizedUtf16Id = new DesktopGuidePreferencesStore(filePath);
  assert.equal((await oversizedUtf16Id.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'utf16-scope' })).persistenceStatus, 'corrupt');
});

test('Guide preferences v1 rechecks scope at the commit barrier and removes its temporary file', async () => {
  let releaseWrite!: () => void;
  const writeStarted = new Promise<void>((resolve) => { releaseWrite = resolve; });
  let continueWrite!: () => void;
  const writeBlocked = new Promise<void>((resolve) => { continueWrite = resolve; });
  let renamed = false;
  let unlinked = false;
  const fileSystem: DesktopGuidePreferencesFileSystem = {
    readFile: async () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); },
    mkdir: async () => undefined,
    writeFile: async () => { releaseWrite(); await writeBlocked; },
    chmod: async () => undefined,
    rename: async () => { renamed = true; },
    unlink: async () => { unlinked = true; },
  };
  const store = new DesktopGuidePreferencesStore('guide-preferences.json', { fileSystem, processId: 9 });
  await store.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope-a' });
  const pending = store.setLibraryFilter('scope-a', 0, 'library');
  await writeStarted;
  store.clearActiveScope();
  continueWrite();
  await assert.rejects(pending, (error: unknown) =>
    error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_SCOPE_STALE');
  assert.equal(renamed, false);
  assert.equal(unlinked, true);
});

test('Guide preferences v1 preserves the prior destination when atomic rename fails', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-preferences-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  const prior = JSON.stringify({ schemaVersion: 1, scopes: [] });
  await fs.writeFile(filePath, prior, 'utf8');
  const fileSystem: DesktopGuidePreferencesFileSystem = {
    readFile: (target, encoding) => fs.readFile(target, encoding),
    mkdir: (target, options) => fs.mkdir(target, options),
    writeFile: (target, content, options) => fs.writeFile(target, content, options),
    chmod: (target, mode) => fs.chmod(target, mode),
    rename: async () => { throw new Error('rename failed'); },
    unlink: (target) => fs.unlink(target),
  };
  const store = new DesktopGuidePreferencesStore(filePath, { fileSystem, processId: 10 });
  await store.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope' });
  await assert.rejects(store.setLibraryFilter('scope', 0, 'library'), (error: unknown) =>
    error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_STORAGE_UNAVAILABLE');
  assert.equal(await fs.readFile(filePath, 'utf8'), prior);
  assert.deepEqual((await fs.readdir(directory)).sort(), ['lineup-desktop-guide-preferences.json']);
});

test('Guide preferences v1 rejects exact-shape, duplicate, capacity, and noncanonical records', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-preferences-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  const scope = { serverId: 'server', profileId: 'profile', selectedLibraryId: null, revision: 1 };
  const invalidDocuments = [
    { schemaVersion: 1 },
    { schemaVersion: 1, scopes: [], extra: true },
    { schemaVersion: 1, scopes: [{ ...scope, extra: true }] },
    { schemaVersion: 1, scopes: [scope, { ...scope, revision: 2 }] },
    { schemaVersion: 1, scopes: [{ ...scope, serverId: 'é' }] },
    { schemaVersion: 1, scopes: Array.from({ length: 129 }, (_, index) => ({ ...scope, serverId: `server-${index}` })) },
  ];
  for (const [index, document] of invalidDocuments.entries()) {
    await fs.writeFile(filePath, JSON.stringify(document), 'utf8');
    const store = new DesktopGuidePreferencesStore(filePath);
    const result = await store.activateScope({ serverId: 'current', profileId: 'profile', scopeToken: `scope-${index}` });
    assert.equal(result.persistenceStatus, 'corrupt');
  }
  await fs.writeFile(filePath, JSON.stringify({
    schemaVersion: 1,
    scopes: Array.from({ length: 128 }, (_, index) => ({ ...scope, serverId: `server-${index}` })),
  }), 'utf8');
  const maximum = new DesktopGuidePreferencesStore(filePath);
  assert.equal((await maximum.activateScope({ serverId: 'server-0', profileId: 'profile', scopeToken: 'maximum' })).persistenceStatus, 'ready');
});

test('Guide preferences v1 increments idempotent setters and owner normalization exactly once', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-preferences-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  const store = new DesktopGuidePreferencesStore(filePath);
  await store.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope' });
  assert.equal((await store.setLibraryFilter('scope', 0, 'library')).revision, 1);
  assert.equal((await store.setLibraryFilter('scope', 1, 'library')).revision, 2);
  const normalized = await store.normalizeSelection('scope', 2);
  assert.deepEqual(normalized, {
    scopeToken: 'scope', revision: 3, selectedLibraryId: null, persistenceStatus: 'ready',
  });
  const persisted = JSON.parse(await fs.readFile(filePath, 'utf8')) as { scopes: Array<{ revision: number; selectedLibraryId: string | null }> };
  assert.deepEqual(persisted.scopes.map(({ revision, selectedLibraryId }) => ({ revision, selectedLibraryId })), [
    { revision: 3, selectedLibraryId: null },
  ]);
});

test('Guide preferences v1 preserves an exhausted revision and serializes concurrent CAS in FIFO order', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-preferences-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  await fs.writeFile(filePath, JSON.stringify({ schemaVersion: 1, scopes: [{
    serverId: 'server', profileId: 'profile', selectedLibraryId: null, revision: Number.MAX_SAFE_INTEGER,
  }] }), 'utf8');
  const exhausted = new DesktopGuidePreferencesStore(filePath);
  await exhausted.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'exhausted' });
  await assert.rejects(exhausted.setLibraryFilter('exhausted', Number.MAX_SAFE_INTEGER, 'library'), (error: unknown) =>
    error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_REVISION_EXHAUSTED');
  assert.equal((JSON.parse(await fs.readFile(filePath, 'utf8')) as { scopes: Array<{ revision: number }> }).scopes[0]?.revision,
    Number.MAX_SAFE_INTEGER);

  await fs.rm(filePath);
  const queued = new DesktopGuidePreferencesStore(filePath);
  await queued.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'queued' });
  const results = await Promise.allSettled([
    queued.setLibraryFilter('queued', 0, 'library-a'),
    queued.setLibraryFilter('queued', 0, 'library-b'),
  ]);
  assert.equal(results[0]?.status, 'fulfilled');
  assert.equal(results[1]?.status, 'rejected');
  assert.ok(results[1]?.status === 'rejected' && results[1].reason instanceof DesktopGuidePreferencesStoreError &&
    results[1].reason.code === 'GUIDE_FILTER_REVISION_CONFLICT');
  assert.equal((JSON.parse(await fs.readFile(filePath, 'utf8')) as { scopes: Array<{ selectedLibraryId: string }> }).scopes[0]?.selectedLibraryId,
    'library-a');
});

test('Guide preferences v1 uses exact atomic temp naming and private file modes', async () => {
  const calls: Array<readonly unknown[]> = [];
  const fileSystem: DesktopGuidePreferencesFileSystem = {
    readFile: async () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); },
    mkdir: async (...args) => { calls.push(['mkdir', ...args]); },
    writeFile: async (...args) => { calls.push(['writeFile', ...args]); },
    chmod: async (...args) => { calls.push(['chmod', ...args]); },
    rename: async (...args) => { calls.push(['rename', ...args]); },
    unlink: async (...args) => { calls.push(['unlink', ...args]); },
  };
  const store = new DesktopGuidePreferencesStore('guide-preferences.json', { fileSystem, processId: 41 });
  await store.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope' });
  await store.setLibraryFilter('scope', 0, null);
  assert.deepEqual(calls.map((call) => call[0]), ['mkdir', 'writeFile', 'chmod', 'rename']);
  assert.deepEqual(calls[0], ['mkdir', '.', { recursive: true }]);
  assert.equal(calls[1]?.[1], 'guide-preferences.json.41.1.tmp');
  assert.deepEqual(calls[1]?.[3], { encoding: 'utf8', mode: 0o600 });
  assert.deepEqual(calls[2], ['chmod', 'guide-preferences.json.41.1.tmp', 0o600]);
  assert.deepEqual(calls[3], ['rename', 'guide-preferences.json.41.1.tmp', 'guide-preferences.json']);
});

test('Guide preferences v1 maps every filesystem boundary failure without exposing causes', async () => {
  const stages = ['readFile', 'mkdir', 'writeFile', 'chmod', 'rename'] as const;
  for (const stage of stages) {
    const fileSystem: DesktopGuidePreferencesFileSystem = {
      readFile: async () => {
        if (stage === 'readFile') throw new Error('private read cause');
        throw Object.assign(new Error('missing'), { code: 'ENOENT' });
      },
      mkdir: async () => { if (stage === 'mkdir') throw new Error('private mkdir cause'); },
      writeFile: async () => { if (stage === 'writeFile') throw new Error('private write cause'); },
      chmod: async () => { if (stage === 'chmod') throw new Error('private chmod cause'); },
      rename: async () => { if (stage === 'rename') throw new Error('private rename cause'); },
      unlink: async () => undefined,
    };
    const store = new DesktopGuidePreferencesStore('guide-preferences.json', { fileSystem });
    if (stage === 'readFile') {
      await assert.rejects(store.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope' }), assertUnavailable);
      continue;
    }
    await store.activateScope({ serverId: 'server', profileId: 'profile', scopeToken: 'scope' });
    await assert.rejects(store.setLibraryFilter('scope', 0, null), assertUnavailable);
  }
});

function assertUnavailable(error: unknown): boolean {
  return error instanceof DesktopGuidePreferencesStoreError &&
    error.code === 'GUIDE_FILTER_STORAGE_UNAVAILABLE' &&
    error.message === 'Guide preference operation failed.';
}
