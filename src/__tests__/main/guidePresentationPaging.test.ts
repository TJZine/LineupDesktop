import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import type { ChannelConfig } from '../../domain/channel/types.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import { ChannelPublicReferenceOwner, type ChannelPublicReferenceGeneration } from '../../main/channel/channelPublicReferenceOwner.js';
import {
  DesktopGuidePreferencesStore,
  DesktopGuidePreferencesStoreError,
  type DesktopGuidePreferencesFileSystem,
} from '../../main/channel/desktopGuidePreferencesStore.js';
import { deferred } from '../helpers/deferred.js';
import { GuideRuntime } from '../../main/channel/guideRuntime.js';

test('Guide pages numeric order before resolving across 300 channels at 9, 21, and 24 rows', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-paging-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const channels = Array.from({ length: 300 }, (_, index) => channel(`channel-${String(index).padStart(3, '0')}`, 300 - index));
  let resolutions = 0;
  const adapter = {
    getLibraryItems: async (libraryId: string) => {
      resolutions += 1;
      return [{ ratingKey: `${libraryId}-item`, type: 'movie', title: libraryId, durationMs: 30 * 60 * 1000 }];
    },
    getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [], getItem: async () => null,
  };
  const owner = new ChannelPublicReferenceOwner();
  const generation: ChannelPublicReferenceGeneration = Object.freeze({
    lineupRevision: 1, channels, currentChannelId: null, fingerprint: 'generation-1',
  });
  const runtime = new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: adapter as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 0 } }),
    clock: { now: () => 0 },
    preferencesStore: new DesktopGuidePreferencesStore(path.join(directory, 'lineup-desktop-guide-preferences.json')),
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope-token',
  });

  for (const limit of [9, 21, 24]) {
    const before = resolutions;
    const result = await runtime.getPagedPresentation({
      startTimeMs: 0, durationMs: 3 * 60 * 60 * 1000, channelOffset: 295, channelLimit: limit,
      generation, publicReferenceOwner: owner,
    });
    assert.equal(result.channelWindow.total, 300);
    assert.equal(result.channelWindow.offset, 300 - limit);
    assert.equal(result.channels.length, limit);
    assert.ok(resolutions - before <= limit);
    assert.deepEqual(result.channels.map((row) => Number(row.number)),
      Array.from({ length: limit }, (_, index) => 300 - limit + index + 1));
  }
});

test('Guide filtering uses raw membership, includes custom channels only in All, and normalizes removed selection', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-paging-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'lineup-desktop-guide-preferences.json');
  const channels = [
    channel('channel-a', 10, 'library-a'),
    channel('channel-b', 20, 'library-b'),
    { ...channel('channel-hidden', 5, 'library-a'), hidden: true },
    { ...channel('channel-custom', 15, 'library-custom'), sourceLibraryId: undefined, sourceLibraryName: undefined,
      contentSource: { type: 'manual' as const, items: [{ ratingKey: 'manual-item', title: 'Manual', durationMs: 60_000 }] } },
  ];
  const adapter = {
    getLibraryItems: async (libraryId: string) => [{ ratingKey: `${libraryId}-item`, type: 'movie', title: libraryId, durationMs: 60_000 }],
    getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [],
    getItem: async (ratingKey: string) => ({ ratingKey, type: 'movie', title: ratingKey, durationMs: 60_000 }),
  };
  const owner = new ChannelPublicReferenceOwner();
  const store = new DesktopGuidePreferencesStore(filePath);
  const runtime = createRuntime(channels, adapter, store);
  const generation = generationFor(channels, 'generation-filter');
  const all = await page(runtime, generation, owner, 0, 24);
  assert.deepEqual(all.channels.map((row) => row.number), ['10', '15', '20']);
  const libraryA = all.libraryFilter.libraries.find((library) => library.name === 'Library 10')!;
  const selected = await runtime.setLibraryFilter({
    generation, publicReferenceOwner: owner, expectedScopeToken: all.libraryFilter.scopeToken,
    expectedRevision: all.libraryFilter.revision, libraryId: libraryA.id,
    loadCurrentGeneration: async () => generation,
  });
  assert.equal(selected.selectedLibraryId, libraryA.id);
  const filtered = await page(runtime, generation, owner, 0, 24);
  assert.deepEqual(filtered.channels.map((row) => row.number), ['10']);

  const removedChannels = channels.filter((candidate) => candidate.id !== 'channel-a' && candidate.id !== 'channel-hidden');
  const removed = await page(runtime, generationFor(removedChannels, 'generation-removed'), owner, 0, 24);
  assert.equal(removed.libraryFilter.selectedLibraryId, null);
  assert.equal(removed.libraryFilter.revision, 2);
  assert.deepEqual(removed.channels.map((row) => row.number), ['15', '20']);
});

test('Guide paging uses public-id tie breaks, empty bounds, and fair 200/1000 program truncation', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-paging-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const owner = new ChannelPublicReferenceOwner();
  const tied = [channel('z-channel', 7, 'library-z'), channel('a-channel', 7, 'library-a')];
  const adapter = {
    getLibraryItems: async (libraryId: string) => Array.from({ length: 250 }, (_, index) => ({
      ratingKey: `${libraryId}-${index}`, type: 'movie', title: `${libraryId}-${index}`, durationMs: 60_000,
    })),
    getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [], getItem: async () => null,
  };
  const tiedRuntime = createRuntime(tied, adapter, new DesktopGuidePreferencesStore(path.join(directory, 'tied.json')));
  const tiedGeneration = generationFor(tied, 'generation-tied');
  const tiedResult = await page(tiedRuntime, tiedGeneration, owner, 0, 24);
  assert.deepEqual(tiedResult.channels.map((row) => row.id),
    [...tiedResult.channels.map((row) => row.id)].sort());

  const emptyRuntime = createRuntime([], adapter, new DesktopGuidePreferencesStore(path.join(directory, 'empty.json')));
  const empty = await page(emptyRuntime, generationFor([], 'generation-empty'), owner, 99, 9);
  assert.deepEqual(empty.channelWindow, { offset: 0, total: 0 });
  assert.deepEqual(empty.channels, []);

  const cappedChannels = Array.from({ length: 6 }, (_, index) => channel(`cap-${index}`, index + 1, `cap-library-${index}`));
  const cappedRuntime = createRuntime(cappedChannels, adapter, new DesktopGuidePreferencesStore(path.join(directory, 'capped.json')));
  const capped = await cappedRuntime.getPagedPresentation({
    startTimeMs: 0, durationMs: 250 * 60_000, channelOffset: 0, channelLimit: 24,
    generation: generationFor(cappedChannels, 'generation-capped'), publicReferenceOwner: owner,
  });
  assert.deepEqual(capped.channels.map((row) => row.programs.length), [167, 167, 167, 167, 166, 166]);
  assert.equal(capped.channels.reduce((total, row) => total + row.programs.length, 0), 1_000);
});

test('Guide disabled and single-library states act as All and persist one normalization tombstone', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-paging-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const filePath = path.join(directory, 'preferences.json');
  const channels = [channel('channel-a', 1, 'library-a'), channel('channel-b', 2, 'library-b')];
  const adapter = {
    getLibraryItems: async (libraryId: string) => [{ ratingKey: libraryId, type: 'movie', title: libraryId, durationMs: 60_000 }],
    getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [], getItem: async () => null,
  };
  const owner = new ChannelPublicReferenceOwner();
  const store = new DesktopGuidePreferencesStore(filePath);
  const enabled = createRuntime(channels, adapter, store);
  const generation = generationFor(channels, 'generation-tabs');
  const initial = await page(enabled, generation, owner, 0, 24);
  const selectedId = initial.libraryFilter.libraries[0]!.id;
  await enabled.setLibraryFilter({
    generation, publicReferenceOwner: owner, expectedScopeToken: initial.libraryFilter.scopeToken,
    expectedRevision: 0, libraryId: selectedId, loadCurrentGeneration: async () => generation,
  });
  const disabled = createRuntime(channels, adapter, store, false);
  const disabledResult = await page(disabled, generation, owner, 0, 24);
  assert.equal(disabledResult.libraryFilter.selectedLibraryId, null);
  assert.equal(disabledResult.libraryFilter.revision, 2);
  assert.equal(disabledResult.channels.length, 2);

  const singleStore = new DesktopGuidePreferencesStore(path.join(directory, 'single.json'));
  const singleEnabled = createRuntime(channels, adapter, singleStore);
  const singleInitial = await page(singleEnabled, generation, owner, 0, 24);
  await singleEnabled.setLibraryFilter({
    generation, publicReferenceOwner: owner, expectedScopeToken: singleInitial.libraryFilter.scopeToken,
    expectedRevision: 0, libraryId: singleInitial.libraryFilter.libraries[0]!.id,
    loadCurrentGeneration: async () => generation,
  });
  const oneChannel = channels.slice(0, 1);
  const singleResult = await page(singleEnabled, generationFor(oneChannel, 'generation-single'), owner, 0, 24);
  assert.equal(singleResult.libraryFilter.selectedLibraryId, null);
  assert.equal(singleResult.libraryFilter.revision, 2);
  assert.equal(singleResult.channels.length, 1);
});

test('Guide filter commit barrier rejects stale lineup generation and preference scope before rename', async () => {
  const channels = [channel('channel-a', 1, 'library-a'), channel('channel-b', 2, 'library-b')];
  const adapter = {
    getLibraryItems: async () => [], getCollectionItems: async () => [], getShowEpisodes: async () => [],
    getPlaylistItems: async () => [], getItem: async () => null,
  };
  const owner = new ChannelPublicReferenceOwner();
  const generation = generationFor(channels, 'generation-current');

  for (const staleKind of ['generation', 'scope'] as const) {
    let renames = 0;
    let unlinks = 0;
    const fileSystem: DesktopGuidePreferencesFileSystem = {
      readFile: async () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); },
      mkdir: async () => undefined,
      writeFile: async () => undefined,
      chmod: async () => undefined,
      rename: async () => { renames += 1; },
      unlink: async () => { unlinks += 1; },
    };
    const runtime = createRuntime(channels, adapter, new DesktopGuidePreferencesStore('guide.json', { fileSystem }));
    const initial = await page(runtime, generation, owner, 0, 24);
    const selectedId = initial.libraryFilter.libraries[0]!.id;
    const barrier = deferred<void>();
    const barrierStarted = deferred<void>();
    const pending = runtime.setLibraryFilter({
      generation,
      publicReferenceOwner: owner,
      expectedScopeToken: initial.libraryFilter.scopeToken,
      expectedRevision: 0,
      libraryId: selectedId,
      loadCurrentGeneration: async () => {
        barrierStarted.resolve();
        await barrier.promise;
        return staleKind === 'generation'
          ? generationFor(channels, 'generation-stale')
          : generation;
      },
    });
    await barrierStarted.promise;
    if (staleKind === 'scope') runtime.invalidatePreferenceScope();
    barrier.resolve();
    await assert.rejects(pending, (error: unknown) =>
      error instanceof DesktopGuidePreferencesStoreError && error.code === 'GUIDE_FILTER_SCOPE_STALE');
    assert.equal(renames, 0, staleKind);
    assert.equal(unlinks, 1, staleKind);
  }
});

function channel(id: string, number: number, libraryId = `library-${id}`): ChannelConfig {
  return {
    id, number, name: `Channel ${number}`, playbackMode: 'sequential', startTimeAnchor: 0,
    skipIntros: false, skipCredits: false, createdAt: 0, updatedAt: 0, lastContentRefresh: 0,
    itemCount: 1, totalDurationMs: 30 * 60 * 1000, sourceLibraryId: libraryId,
    sourceLibraryName: `Library ${number}`,
    contentSource: { type: 'library', libraryId, libraryType: 'movie', includeWatched: true },
  };
}

function generationFor(channels: readonly ChannelConfig[], fingerprint: string): ChannelPublicReferenceGeneration {
  return Object.freeze({ lineupRevision: 1, channels, currentChannelId: null, fingerprint });
}

function createRuntime(
  channels: readonly ChannelConfig[],
  adapter: object,
  preferencesStore: DesktopGuidePreferencesStore,
  libraryTabsEnabled = true,
): GuideRuntime {
  return new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: adapter as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 0 } }),
    clock: { now: () => 0 }, preferencesStore,
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope-token',
    getLibraryTabsEnabled: () => libraryTabsEnabled,
  });
}

function page(
  runtime: GuideRuntime,
  generation: ChannelPublicReferenceGeneration,
  owner: ChannelPublicReferenceOwner,
  channelOffset: number,
  channelLimit: number,
) {
  return runtime.getPagedPresentation({
    startTimeMs: 0, durationMs: 60_000, channelOffset, channelLimit, generation, publicReferenceOwner: owner,
  });
}
