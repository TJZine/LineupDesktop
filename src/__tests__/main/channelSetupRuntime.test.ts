import assert from 'node:assert/strict';
import test from 'node:test';
import { setImmediate } from 'node:timers/promises';

import type { ChannelSetupConfigDraft } from '../../contracts/channel.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import { ChannelPersistenceStore } from '../../domain/channel/channelPersistenceStore.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import type { ChannelSetupFacetSnapshot } from '../../domain/channel/setupPlanning/index.js';
import type { ChannelConfig, StoredChannelData } from '../../domain/channel/types.js';
import { DesktopChannelSetupRuntime } from '../../main/channel/setup/desktopChannelSetupRuntime.js';
import type { ChannelSetupFacetSource } from '../../main/channel/setup/desktopPlexSetupFacetSource.js';
import { GuideRuntime } from '../../main/channel/guideRuntime.js';
import type { PlexLibraryMinimalAdapter } from '../../main/channel/plexLibraryMinimalAdapter.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import type { DesktopChannelSetupRecordStore } from '../../main/persistence/desktopChannelSetupRecordStore.js';

const strategyKeys = ['playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors'] as const;

function draft(strategy: typeof strategyKeys[number], mode: 'append' | 'replace' | 'merge' = 'replace'): ChannelSetupConfigDraft {
  return {
    selectedLibraryIds: ['movies'], maxChannels: 20, buildMode: mode,
    strategyConfig: Object.fromEntries(strategyKeys.map((key, index) => [key, {
      enabled: key === strategy, priority: index + 1, scope: 'per-library',
    }])),
    actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
  };
}

function snapshot(): ChannelSetupFacetSnapshot {
  return {
    libraries: [{ id: 'movies', title: 'Movies', type: 'movie', itemCount: 10 }],
    playlists: [{ key: 'playlist-1', title: 'Playlist', itemCount: 8 }],
    collectionsByLibraryId: new Map([['movies', [{ key: 'collection-1', title: 'Collection', itemCount: 7 }]]]),
    genresByLibraryId: new Map([['movies', [{ key: 'g1', title: 'Drama', itemCount: 6 }]]]),
    directorsByLibraryId: new Map([['movies', [{ key: 'd1', title: 'Director', itemCount: 6 }]]]),
    yearsByLibraryId: new Map([['movies', [{ key: '1995', title: '1995', itemCount: 6 }]]]),
    studiosByLibraryId: new Map([['movies', [{ key: 's1', title: 'Studio', itemCount: 6 }]]]),
    actorsByLibraryId: new Map([['movies', [{ key: 'a1', title: 'Actor', itemCount: 6 }]]]),
    warnings: [],
  };
}

class RepositoryFake {
  public data: StoredChannelData | null = null;
  public writes = 0;
  public beforeWrite: (() => Promise<void>) | null = null;
  async loadNormalized() { return this.data ? { data: this.data, didMutate: false } : null; }
  async saveStoredChannelData(data: StoredChannelData) {
    this.writes += 1;
    if (this.beforeWrite) await this.beforeWrite();
    this.data = data;
  }
}

function createRuntime(input: {
  repository?: RepositoryFake;
  facetSource?: ChannelSetupFacetSource;
  recordFails?: boolean;
  plexRuntime?: DesktopPlexRuntime;
  guideRefresh?: (signal?: AbortSignal) => Promise<{ kind: 'completed' } | { kind: 'interrupted'; message: string }>;
}) {
  const repository = input.repository ?? new RepositoryFake();
  let guideCalls = 0;
  let recordCalls = 0;
  const runtime = new DesktopChannelSetupRuntime({
    repository: repository as unknown as ChannelRepository,
    facetSource: input.facetSource ?? { load: async () => ({ profileId: 'p1', serverId: 's1', snapshot: snapshot() }) },
    recordStore: {
      saveRecord: async () => { recordCalls += 1; if (input.recordFails) throw new Error('record failed'); },
      getRecord: async () => ({ status: 'missing' as const }),
    } as unknown as DesktopChannelSetupRecordStore,
    guideRuntime: { refreshAfterChannelSetupCommit: async (signal?: AbortSignal) => {
      guideCalls += 1;
      return input.guideRefresh ? input.guideRefresh(signal) : { kind: 'completed' as const };
    } } as GuideRuntime,
    plexRuntime: input.plexRuntime ?? ({ withActiveChannelSetupContext: async (run: (value: object) => unknown) => run({ profileId: 'p1', serverId: 's1' }) } as unknown as DesktopPlexRuntime),
    nowMs: () => 1000,
    createChannelId: (() => { let id = 0; return () => `generated-${String(++id)}`; })(),
  });
  return { runtime, repository, guideCalls: () => guideCalls, recordCalls: () => recordCalls };
}

async function build(runtime: DesktopChannelSetupRuntime, config: ChannelSetupConfigDraft, buildId: string) {
  return runtime.build({ senderId: 1, requestId: `request-${buildId}`, buildId, draft: config, confirmReplace: true, onProgress: () => undefined });
}

test('channel setup strategies produce materially distinct persisted channel policy', async () => {
  const signatures = new Set<string>();
  for (const strategy of strategyKeys) {
    const owner = createRuntime({});
    assert.equal((await build(owner.runtime, draft(strategy), strategy)).ok, true);
    const channel = owner.repository.data?.channels[0];
    assert.notEqual(channel, undefined);
    signatures.add(JSON.stringify({
      buildStrategy: channel?.buildStrategy,
      contentSource: channel?.contentSource,
      contentFilters: channel?.contentFilters,
      sortOrder: channel?.sortOrder,
    }));
    assert.equal(owner.repository.writes, 1);
  }
  assert.equal(signatures.size, 8);
});

test('append skips an identity match and merge updates a generated channel in place', async () => {
  const repository = new RepositoryFake();
  const first = createRuntime({ repository });
  await build(first.runtime, draft('recentlyAdded', 'replace'), 'first');
  const original = repository.data?.channels[0];
  assert.notEqual(original, undefined);
  const append = createRuntime({ repository });
  const appended = await build(append.runtime, draft('recentlyAdded', 'append'), 'append');
  assert.equal(appended.ok, true);
  if (appended.ok && appended.value.kind !== 'failed') assert.equal(appended.value.counts.createdCount, 0);
  assert.equal(repository.data?.channels.length, 1);

  const baseSnapshot = snapshot();
  const renamedSnapshot: ChannelSetupFacetSnapshot = {
    ...baseSnapshot,
    libraries: [{ ...baseSnapshot.libraries[0]!, title: 'Cinema' }],
  };
  const merge = createRuntime({
    repository,
    facetSource: { load: async () => ({ profileId: 'p1', serverId: 's1', snapshot: renamedSnapshot }) },
  });
  const merged = await build(merge.runtime, draft('recentlyAdded', 'merge'), 'merge');
  assert.equal(merged.ok, true);
  assert.equal(repository.data?.channels[0]?.id, original?.id);
  assert.equal(repository.data?.channels[0]?.number, original?.number);
  assert.equal(repository.data?.channels[0]?.name, 'Cinema - Recently Added');
});

test('channel setup build modes preserve custom channels except confirmed replace', async () => {
  const custom = customChannel();
  for (const mode of ['append', 'merge'] as const) {
    const repository = new RepositoryFake();
    repository.data = stored([custom]);
    const owner = createRuntime({ repository });
    await build(owner.runtime, draft('genres', mode), mode);
    assert.equal(repository.data?.channels.some((channel) => channel.id === custom.id), true);
  }
  const repository = new RepositoryFake();
  repository.data = stored([custom]);
  const owner = createRuntime({ repository });
  await build(owner.runtime, draft('genres', 'replace'), 'replace');
  assert.equal(repository.data?.channels.some((channel) => channel.id === custom.id), false);
});

test('replace never writes when a selected library is missing or planning yields zero generated channels', async () => {
  const repository = new RepositoryFake();
  repository.data = stored([customChannel()]);
  for (const facetSnapshot of [
    { ...snapshot(), libraries: [] },
    { ...snapshot(), genresByLibraryId: new Map([['movies', []]]) },
  ] satisfies ChannelSetupFacetSnapshot[]) {
    const owner = createRuntime({
      repository,
      facetSource: { load: async () => ({ profileId: 'p1', serverId: 's1', snapshot: facetSnapshot }) },
    });
    const result = await build(owner.runtime, draft('genres', 'replace'), `guard-${String(repository.writes)}`);
    assert.equal(result.ok, true);
    if (result.ok) assert.equal(result.value.kind, 'failed');
    assert.equal(repository.writes, 0);
    assert.equal(repository.data?.channels[0]?.id, 'custom');
  }
});

test('channel setup reports record warning after the single authoritative commit and still refreshes Guide', async () => {
  const owner = createRuntime({ recordFails: true });
  const result = await build(owner.runtime, draft('genres'), 'warning');
  assert.equal(result.ok, true);
  if (result.ok) assert.equal(result.value.kind, 'committed-with-record-warning');
  assert.equal(owner.repository.writes, 1);
  assert.equal(owner.recordCalls(), 1);
  assert.equal(owner.guideCalls(), 1);
});

test('channel setup errors and review samples use fixed safe exact renderer shapes', async () => {
  const failedOwner = createRuntime({
    facetSource: { load: async () => { throw new Error('https://private.example path=C:/secret token=private header=value'); } },
  });
  const failed = await build(failedOwner.runtime, draft('genres'), 'unsafe-error');
  assert.equal(failed.ok, true);
  if (failed.ok && failed.value.kind === 'failed') {
    assert.deepEqual(failed.value.error, {
      code: 'CHANNEL_UNKNOWN', message: 'Channel setup could not be completed.', retryable: true,
      recoverable: true, operation: 'build',
    });
  }
  const extraFieldOwner = createRuntime({
    facetSource: { load: async () => { throw {
      code: 'CHANNEL_VALIDATION_FAILED', message: 'unsafe', retryable: false,
      recoverable: true, operation: 'build', extra: 'token=private',
    }; } },
  });
  const extraField = await build(extraFieldOwner.runtime, draft('genres'), 'extra-error');
  if (extraField.ok && extraField.value.kind === 'failed') {
    assert.deepEqual(extraField.value.error, {
      code: 'CHANNEL_UNKNOWN', message: 'Channel setup could not be completed.', retryable: true,
      recoverable: true, operation: 'build',
    });
  } else assert.fail('Expected an exact failed result.');

  const unsafeSnapshot = snapshot();
  const owner = createRuntime({
    facetSource: { load: async () => ({
      profileId: 'p1', serverId: 's1',
      snapshot: {
        ...unsafeSnapshot,
        libraries: [{ ...unsafeSnapshot.libraries[0]!, title: 'https://private.example token=secret' }],
        warnings: ['header=private', 'token=private', 'https://private.example', 'path=C:/secret'],
      },
    }) },
  });
  const review = await owner.runtime.review('review-safe', draft('recentlyAdded'));
  assert.equal(review.ok, true);
  if (review.ok) {
    assert.deepEqual(review.value.diff.samples.created, ['Plex item']);
    assert.deepEqual(review.value.preview.warnings, ['Plex item', 'Plex item', 'Plex item', 'Plex item']);
    assert.equal(JSON.stringify(review.value).includes('private.example'), false);
    assert.equal(JSON.stringify(review.value).includes('secret'), false);
  }
});

test('channel setup cancellation is idempotent before apply and produces no snapshot write', async () => {
  const facetSource: ChannelSetupFacetSource = {
    load: async (_config, signal) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true });
    }),
  };
  const owner = createRuntime({ facetSource });
  const pending = build(owner.runtime, draft('genres'), 'cancel-me');
  await setImmediate();
  const overlapping = await build(owner.runtime, draft('genres'), 'overlap');
  assert.equal(overlapping.ok, false);
  if (!overlapping.ok) assert.equal(overlapping.error.code, 'CHANNEL_BUILD_ACTIVE');
  assert.deepEqual(owner.runtime.cancelBuild(1, 'cancel-me'), { buildId: 'cancel-me', status: 'accepted' });
  assert.deepEqual(owner.runtime.cancelBuild(1, 'cancel-me'), { buildId: 'cancel-me', status: 'accepted' });
  const result = await pending;
  assert.equal(result.ok && result.value.kind, 'canceled');
  assert.equal(owner.repository.writes, 0);
  const reused = await build(owner.runtime, draft('genres'), 'cancel-me');
  assert.equal(reused.ok, false);
  if (!reused.ok) assert.equal(reused.error.code, 'CHANNEL_BUILD_ID_REUSED');
});

test('channel setup distinguishes plan cap from exhausted persisted channel numbers', async () => {
  const repository = new RepositoryFake();
  const channels = Array.from({ length: 500 }, (_value, index) => ({
    ...customChannel(), id: `existing-${String(index + 1)}`, number: index + 1,
  }));
  repository.data = stored(channels);
  const owner = createRuntime({ repository });
  const result = await build(owner.runtime, draft('genres', 'append'), 'capacity');
  assert.equal(result.ok, true);
  if (result.ok && result.value.kind !== 'failed') {
    assert.equal(result.value.counts.channelNumberCapacityExhausted, true);
    assert.equal(result.value.counts.reachedMaxChannels, false);
    assert.equal(result.value.counts.createdCount, 0);
  }
});

test('channel setup aborts active work and removes context invalidation ownership on shutdown', async () => {
  let invalidate: (() => void) | null = null;
  let unsubscribed = false;
  const plexRuntime = {
    subscribeChannelSetupContextInvalidation: (listener: () => void) => {
      invalidate = listener;
      return () => { unsubscribed = true; };
    },
  } as unknown as DesktopPlexRuntime;
  const facetSource: ChannelSetupFacetSource = {
    load: async (_config, signal) => new Promise((_resolve, reject) => {
      signal.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), { once: true });
    }),
  };
  const owner = createRuntime({ facetSource, plexRuntime });
  const pending = build(owner.runtime, draft('genres'), 'context-change');
  await setImmediate();
  assert.notEqual(invalidate, null);
  (invalidate as unknown as () => void)();
  assert.equal((await pending).ok, true);
  assert.equal(owner.repository.writes, 0);
  owner.runtime.shutdown();
  assert.equal(unsubscribed, true);
});

test('build identifier history is sender-local, capacity bounded, and reset on sender destruction', async () => {
  const owner = createRuntime({});
  const rejected = (senderId: number, buildId: string) => owner.runtime.build({
    senderId, requestId: `request-${buildId}-${String(senderId)}`, buildId,
    draft: draft('genres', 'replace'), confirmReplace: false, onProgress: () => undefined,
  });
  assert.equal((await rejected(1, 'shared')).ok, false);
  const crossSender = await rejected(2, 'shared');
  assert.equal(crossSender.ok, false);
  if (!crossSender.ok) assert.equal(crossSender.error.code, 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED');
  const reused = await rejected(1, 'shared');
  assert.equal(reused.ok, false);
  if (!reused.ok) assert.equal(reused.error.code, 'CHANNEL_BUILD_ID_REUSED');
  owner.runtime.releaseSender(1);
  const reset = await rejected(1, 'shared');
  assert.equal(reset.ok, false);
  if (!reset.ok) assert.equal(reset.error.code, 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED');

  const capacityOwner = createRuntime({});
  for (let index = 0; index < 1024; index += 1) {
    await capacityOwner.runtime.build({
      senderId: 9, requestId: `r-${String(index)}`, buildId: `id-${String(index)}`,
      draft: draft('genres', 'replace'), confirmReplace: false, onProgress: () => undefined,
    });
  }
  const capacity = await capacityOwner.runtime.build({
    senderId: 9, requestId: 'r-cap', buildId: 'id-cap',
    draft: draft('genres', 'replace'), confirmReplace: false, onProgress: () => undefined,
  });
  assert.equal(capacity.ok, false);
  if (!capacity.ok) assert.equal(capacity.error.code, 'CHANNEL_BUILD_ID_CAPACITY');
});

test('channel setup cancel becomes too late at apply and progress sequences are monotonic', async () => {
  const repository = new RepositoryFake();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  let applying!: () => void;
  const entered = new Promise<void>((resolve) => { applying = resolve; });
  repository.beforeWrite = async () => { applying(); await gate; };
  const owner = createRuntime({ repository });
  const sequences: number[] = [];
  const pending = owner.runtime.build({ senderId: 1, requestId: 'req', buildId: 'late', draft: draft('genres'), confirmReplace: true, onProgress: (_p, sequence) => sequences.push(sequence) });
  await entered;
  assert.deepEqual(owner.runtime.cancelBuild(1, 'late'), { buildId: 'late', status: 'too-late' });
  release();
  assert.equal((await pending).ok, true);
  assert.deepEqual(sequences, sequences.map((_value, index) => index + 1));
});

test('channel setup build progress preserves the exact monotonic stage order and totals', async () => {
  const source: ChannelSetupFacetSource = {
    load: async (_config, _signal, onProgress) => {
      for (const task of ['fetch_playlists', 'fetch_collections', 'fetch_facets', 'scan_library_items'] as const) {
        onProgress?.({ task, current: 0, total: 1, label: task, detail: task });
        onProgress?.({ task, current: 1, total: 1, label: task, detail: task });
      }
      return { profileId: 'p1', serverId: 's1', snapshot: snapshot() };
    },
  };
  const owner = createRuntime({ facetSource: source });
  const progressValues: Array<{ task: string; current: number; total: number | null; sequence: number }> = [];
  const result = await owner.runtime.build({
    senderId: 1, requestId: 'progress-request', buildId: 'progress-build', draft: draft('genres'),
    confirmReplace: true,
    onProgress: (value, sequence) => progressValues.push({ ...value, sequence }),
  });
  assert.equal(result.ok, true);
  assert.deepEqual(progressValues.map((value) => value.sequence), progressValues.map((_value, index) => index + 1));
  assert.deepEqual([...new Set(progressValues.map((value) => value.task))], [
    'fetch_playlists', 'fetch_collections', 'fetch_facets', 'scan_library_items',
    'build_pending', 'create_channels', 'apply_channels', 'refresh_guide', 'done',
  ]);
  assert.equal(progressValues.every((value) => value.total === null || value.current <= value.total), true);
});

test('progress observer failure cannot reclassify a committed build or skip post-commit work', async () => {
  const owner = createRuntime({});
  const result = await owner.runtime.build({
    senderId: 1, requestId: 'observer-request', buildId: 'observer-build', draft: draft('genres'),
    confirmReplace: true, onProgress: () => { throw new Error('detached sender'); },
  });
  assert.equal(result.ok && result.value.kind, 'committed');
  assert.equal(owner.repository.writes, 1);
  assert.equal(owner.recordCalls(), 1);
  assert.equal(owner.guideCalls(), 1);
});

test('sender destruction after apply detaches custody without skipping record or Guide refresh', async () => {
  const repository = new RepositoryFake();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  let applying!: () => void;
  const entered = new Promise<void>((resolve) => { applying = resolve; });
  repository.beforeWrite = async () => { applying(); await gate; };
  const owner = createRuntime({ repository });
  const pending = build(owner.runtime, draft('genres'), 'detached');
  await entered;
  owner.runtime.releaseSender(1);
  release();
  const result = await pending;
  assert.equal(result.ok && result.value.kind, 'committed');
  assert.equal(owner.recordCalls(), 1);
  assert.equal(owner.guideCalls(), 1);
});

test('context invalidation after commit starts still records and reports interrupted Guide refresh', async () => {
  const repository = new RepositoryFake();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => { release = resolve; });
  let applying!: () => void;
  const entered = new Promise<void>((resolve) => { applying = resolve; });
  repository.beforeWrite = async () => { applying(); await gate; };
  let invalidate!: () => void;
  const plexRuntime = {
    subscribeChannelSetupContextInvalidation: (listener: () => void) => { invalidate = listener; return () => undefined; },
  } as unknown as DesktopPlexRuntime;
  const owner = createRuntime({
    repository,
    plexRuntime,
    guideRefresh: async (signal) => signal?.aborted
      ? { kind: 'interrupted', message: 'Guide refresh was interrupted.' }
      : { kind: 'completed' },
  });
  const pending = build(owner.runtime, draft('genres'), 'context-after-apply');
  await entered;
  invalidate();
  release();
  const result = await pending;
  assert.equal(result.ok, true);
  if (result.ok && result.value.kind !== 'failed' && result.value.kind !== 'canceled') {
    assert.deepEqual(result.value.guideRefresh, { kind: 'interrupted', message: 'Guide refresh was interrupted.' });
  }
  assert.equal(owner.recordCalls(), 1);
  assert.equal(owner.guideCalls(), 1);
});

test('real repository and Guide integration performs one snapshot write and zero current-id writes', async () => {
  let encoded: string | null = null;
  let snapshotWrites = 0;
  let currentIdWrites = 0;
  const store = new ChannelPersistenceStore({
    readStoredChannelData: async () => encoded,
    writeStoredChannelData: async (value) => { snapshotWrites += 1; encoded = value; },
    clearStoredChannelData: async () => { encoded = null; },
    readCurrentChannelId: async () => null,
    writeCurrentChannelId: async () => { currentIdWrites += 1; },
  });
  const repository = new ChannelRepository({ store, clock: { now: () => 1000 } });
  const scheduler = new ChannelScheduler({ clock: { now: () => 1000 } });
  const guideRuntime = new GuideRuntime({
    repository,
    plexLibraryAdapter: {
      getLibraryItems: async () => [{ ratingKey: 'movie-1', type: 'movie', title: 'Movie', durationMs: 1000 }],
    } as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: scheduler,
    clock: { now: () => 1000 },
  });
  const runtime = new DesktopChannelSetupRuntime({
    repository,
    facetSource: { load: async () => ({ profileId: 'p1', serverId: 's1', snapshot: snapshot() }) },
    recordStore: { saveRecord: async () => undefined } as unknown as DesktopChannelSetupRecordStore,
    guideRuntime,
    plexRuntime: {} as DesktopPlexRuntime,
    nowMs: () => 1000,
    createChannelId: () => 'generated-real',
  });
  const result = await build(runtime, draft('recentlyAdded'), 'real-integration');
  assert.equal(result.ok && result.value.kind, 'committed');
  assert.equal(snapshotWrites, 1);
  assert.equal(currentIdWrites, 0);
  assert.equal(scheduler.getState().channelId, 'generated-real');
});

function customChannel(): ChannelConfig {
  return {
    id: 'custom', number: 10, name: 'Custom', contentSource: { type: 'manual', items: [] }, playbackMode: 'sequential',
    startTimeAnchor: 1, skipIntros: false, skipCredits: false, createdAt: 1, updatedAt: 1,
    lastContentRefresh: 1, itemCount: 0, totalDurationMs: 0,
  };
}
function stored(channels: ChannelConfig[]): StoredChannelData {
  return { channels, channelOrder: channels.map((channel) => channel.id), currentChannelId: channels[0]?.id ?? null, savedAt: 1 };
}
