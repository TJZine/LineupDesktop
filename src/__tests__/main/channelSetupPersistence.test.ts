import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeChannelSetupConfig } from '../../domain/channel/setupPlanning/index.js';
import {
  DesktopChannelSetupRecordStore,
  type DesktopChannelSetupRecordFileSystem,
} from '../../main/persistence/desktopChannelSetupRecordStore.js';

const draft = {
  selectedLibraryIds: ['movies'], maxChannels: 20, buildMode: 'merge' as const,
  strategyConfig: {}, actorStudioCombineMode: 'separate' as const, minItemsPerChannel: 5,
};

class MemoryFileSystem implements DesktopChannelSetupRecordFileSystem {
  public content: string | null = null;
  public modes: number[] = [];
  public unavailable = false;
  async readFile(): Promise<string> {
    if (this.unavailable) throw Object.assign(new Error('denied'), { code: 'EACCES' });
    if (this.content === null) throw Object.assign(new Error('missing'), { code: 'ENOENT' });
    return this.content;
  }
  async mkdir(): Promise<void> {}
  async writeFile(_path: string, content: string, options: { mode: number }): Promise<void> {
    this.content = content; this.modes.push(options.mode);
  }
  async rename(): Promise<void> {}
  async chmod(_path: string, mode: number): Promise<void> { this.modes.push(mode); }
}

test('channel setup record store scopes records by profile and server and preserves creation time', async () => {
  const fileSystem = new MemoryFileSystem();
  const store = new DesktopChannelSetupRecordStore({ persistenceFilePath: 'C:/data/setup.json', fileSystem });
  const config = normalizeChannelSetupConfig(draft);
  await store.saveRecord({ profileId: 'p1', serverId: 's1', config, nowMs: 10 });
  await store.saveRecord({ profileId: 'p2', serverId: 's1', config, nowMs: 20 });
  await store.saveRecord({ profileId: 'p1', serverId: 's1', config, nowMs: 30 });

  assert.deepEqual(await store.getRecord('p1', 'missing'), { status: 'missing' });
  const record = await store.getRecord('p1', 's1');
  assert.equal(record.status, 'ready');
  if (record.status === 'ready') assert.deepEqual([record.createdAtMs, record.updatedAtMs], [10, 30]);
  assert.deepEqual(fileSystem.modes, [0o600, 0o600, 0o600, 0o600, 0o600, 0o600]);
});

test('channel setup record store reports missing, corrupt, unsupported, and unavailable without overwriting', async () => {
  const fileSystem = new MemoryFileSystem();
  const store = new DesktopChannelSetupRecordStore({ persistenceFilePath: 'C:/data/setup.json', fileSystem });
  assert.deepEqual(await store.getRecord('p', 's'), { status: 'missing' });
  fileSystem.content = '{bad';
  assert.deepEqual(await store.getRecord('p', 's'), { status: 'corrupt' });
  await assert.rejects(store.saveRecord({ profileId: 'p', serverId: 's', config: normalizeChannelSetupConfig(draft), nowMs: 1 }));
  assert.equal(fileSystem.content, '{bad');
  fileSystem.content = JSON.stringify({ schemaVersion: 2, records: [] });
  assert.deepEqual(await store.getRecord('p', 's'), { status: 'unsupported-version' });
  const config = normalizeChannelSetupConfig(draft);
  const validRecord = { profileId: 'p', serverId: 's', config, createdAtMs: 1, updatedAtMs: 2 };
  const corruptFiles = [
    { schemaVersion: 1 },
    { schemaVersion: 1, records: [], extra: true },
    { schemaVersion: 1, records: [{ ...validRecord, extra: true }] },
    { schemaVersion: 1, records: [{ ...validRecord, config: { ...config, extra: true } }] },
    { schemaVersion: 1, records: [{ ...validRecord, config: { ...config, selectedLibraryIds: ['movies', 'movies'] } }] },
    { schemaVersion: 1, records: [{ ...validRecord, config: { ...config, strategyConfig: { ...config.strategyConfig, genres: { enabled: true } } } }] },
    { schemaVersion: 1, records: [{ ...validRecord, config: { ...config, channelExpansion: { ...config.channelExpansion, mystery: true } } }] },
    { schemaVersion: 1, records: [validRecord, validRecord] },
  ];
  for (const corruptFile of corruptFiles) {
    fileSystem.content = JSON.stringify(corruptFile);
    assert.deepEqual(await store.getRecord('p', 's'), { status: 'corrupt' });
  }
  fileSystem.unavailable = true;
  assert.deepEqual(await store.getRecord('p', 's'), { status: 'unavailable' });
});
