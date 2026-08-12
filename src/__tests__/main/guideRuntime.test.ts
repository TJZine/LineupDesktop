import test from 'node:test';
import assert from 'node:assert/strict';
import { GuideRuntime } from '../../main/channel/guideRuntime.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import type { ChannelConfig } from '../../domain/channel/types.js';
import type { ChannelRepository } from '../../domain/channel/channelRepository.js';
import type { PlexMediaItemMinimal } from '../../domain/channel/interfaces.js';
import type { PlexLibraryMinimalAdapter } from '../../main/channel/plexLibraryMinimalAdapter.js';
import { ChannelPublicReferenceOwner, type ChannelPublicReferenceGeneration } from '../../main/channel/channelPublicReferenceOwner.js';

class MockChannelRepository {
  public data = {
    channels: [] as ChannelConfig[],
    currentChannelId: null as string | null,
  };
  public saveError: Error | null = null;
  async loadNormalized() {
    if (this.data.channels.length === 0) {
      return null;
    }
    return { data: this.data, didMutate: false };
  }
  async saveCurrentChannelId(id: string | null) {
    if (this.saveError !== null) {
      throw this.saveError;
    }
    this.data.currentChannelId = id;
  }
}

class MockPlexLibraryAdapter {
  private readonly libraryItems = new Map<string, readonly PlexMediaItemMinimal[]>();
  private readonly libraryErrors = new Map<string, unknown>();

  setLibraryItems(sectionId: string, items: readonly PlexMediaItemMinimal[]): void {
    this.libraryItems.set(sectionId, [...items]);
  }

  setLibraryError(sectionId: string, error: unknown): void {
    this.libraryErrors.set(sectionId, error);
  }

  async getLibraryItems(
    sectionId: string,
    _options?: {
      includeCollections?: boolean;
      filter?: Record<string, string | number>;
      signal?: { aborted?: boolean } | null;
    },
  ): Promise<PlexMediaItemMinimal[]> {
    if (this.libraryErrors.has(sectionId)) {
      throw this.libraryErrors.get(sectionId);
    }
    return [...(this.libraryItems.get(sectionId) ?? [])];
  }

  async getCollectionItems(
    _collectionKey: string,
    _options?: { signal?: { aborted?: boolean } | null },
  ): Promise<PlexMediaItemMinimal[]> {
    return [];
  }

  async getShowEpisodes(
    _showKey: string,
    _options?: { signal?: { aborted?: boolean } | null },
  ): Promise<PlexMediaItemMinimal[]> {
    return [];
  }

  async getPlaylistItems(
    _playlistKey: string,
    _options?: { signal?: { aborted?: boolean } | null },
  ): Promise<PlexMediaItemMinimal[]> {
    return [];
  }

  async getItem(_ratingKey: string): Promise<PlexMediaItemMinimal | null> {
    return null;
  }
}

function createChannelConfig(id: string, num: number, name: string, libraryId = 'lib-1'): ChannelConfig {
  return {
    id,
    number: num,
    name,
    playbackMode: 'sequential',
    startTimeAnchor: 1000,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1000,
    updatedAt: 1000,
    lastContentRefresh: 1000,
    itemCount: 1,
    totalDurationMs: 1_800_000,
    contentSource: {
      type: 'library',
      libraryId,
      libraryType: 'movie',
      includeWatched: true,
    },
  };
}

function createLibraryItem(index: number, durationMs = 1_800_000): PlexMediaItemMinimal {
  return {
    ratingKey: `item-${index}`,
    type: 'movie',
    title: `Movie ${index}`,
    durationMs,
    thumb: 'thumb-key',
    year: 2026,
  };
}

function pagedRuntimeOptions() {
  return {
    preferencesStore: {
      activateScope: async (scope: { scopeToken: string }) => ({
        scopeToken: scope.scopeToken,
        revision: 0,
        selectedLibraryId: null,
        persistenceStatus: 'missing' as const,
      }),
    } as never,
    guideContextSource: {
      getBuilderContextForMain: () => ({
        ok: true as const,
        snapshot: { activeProfileId: 'profile', selectedServerId: 'server' },
      }),
    },
    getPastItemsWindowSnapshot: async () => ({
      revision: 0,
      pastItemsWindow: 'auto' as const,
      libraryTabsEnabled: true,
    }),
  };
}

function createGeneration(
  repository: MockChannelRepository,
  lineupRevision = 1,
): ChannelPublicReferenceGeneration {
  return Object.freeze({
    lineupRevision,
    channels: repository.data.channels,
    currentChannelId: repository.data.currentChannelId,
    fingerprint: `guide-runtime-${String(lineupRevision)}`,
  });
}

test('GuideRuntime getPagedPresentation returns empty channels list if none configured', async () => {
  const repository = new MockChannelRepository();
  const plexAdapter = new MockPlexLibraryAdapter();
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
    ...pagedRuntimeOptions(),
  });

  const presentation = await runtime.getPagedPresentation({
    startTimeMs: 1000,
    durationMs: 3600 * 1000,
    channelOffset: 0,
    channelLimit: 24,
    generation: createGeneration(repository),
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
  });
  assert.deepEqual(presentation.channels, []);
  assert.equal(presentation.nowWatching, null);
  assert.deepEqual(presentation.channelWindow, { offset: 0, total: 0 });
});

test('GuideRuntime loadChannel emits programStart before optional tune notification', async () => {
  const repository = new MockChannelRepository();
  repository.data.channels = [createChannelConfig('chan-1', 1, 'One')];
  repository.data.currentChannelId = 'chan-1';
  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [createLibraryItem(1)]);
  const activeScheduler = new ChannelScheduler({
    clock: { now: () => 1_000 },
  });
  const trace: string[] = [];
  activeScheduler.on('programStart', () => {
    trace.push('programStart');
  });
  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1_000 },
    onChannelTuned: () => {
      trace.push('onChannelTuned');
    },
  });

  await runtime.tuneChannel('chan-1');

  assert.deepEqual(trace, ['programStart', 'onChannelTuned']);
});

test('GuideRuntime getPagedPresentation generates schedule presentation for channels', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1', 'lib-1');
  const chan2 = createChannelConfig('chan-2', 2, 'Channel 2', 'lib-2');
  repository.data.channels = [chan1, chan2];
  repository.data.currentChannelId = 'chan-1';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [createLibraryItem(0)]);
  plexAdapter.setLibraryItems('lib-2', [createLibraryItem(1)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
    ...pagedRuntimeOptions(),
  });

  const presentation = await runtime.getPagedPresentation({
    startTimeMs: 1000,
    durationMs: 1_800_000,
    channelOffset: 0,
    channelLimit: 24,
    generation: createGeneration(repository),
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
  });

  assert.equal(presentation.channels.length, 2);
  assert.equal(presentation.channels[0]?.id, 'chan-1');
  assert.equal(presentation.channels[0]?.programs.length, 1);
  assert.equal(presentation.channels[0]?.programs[0]?.title, 'Movie 0');

  assert.equal(presentation.channels[1]?.id, 'chan-2');
  assert.equal(presentation.channels[1]?.programs.length, 1);
  assert.equal(presentation.channels[1]?.programs[0]?.title, 'Movie 1');
});

test('GuideRuntime paged artwork output becomes an owned renderer-safe projection for hostile titles', async () => {
  const repository = new MockChannelRepository();
  const configured = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [configured];
  repository.data.currentChannelId = configured.id;
  const privateLocatorMarker = ['guide', 'private', 'token', 'marker'].join('-');
  const hostileTitle = 'Bearer secret https://private.invalid/<title>\u0000'.repeat(8);
  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [{
    ...createLibraryItem(0),
    title: hostileTitle,
    thumb: `/library/metadata/1/thumb?private=${privateLocatorMarker}`,
    art: `/library/metadata/1/art?private=${privateLocatorMarker}`,
    clearLogo: '/library/metadata/1/clearLogo',
  }]);
  const createdRefs: object[] = [];
  const createdInputs: Array<{ role: string; locator: string }> = [];
  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 1_000 } }),
    clock: { now: () => 1_000 },
    ...pagedRuntimeOptions(),
    guideArtworkOwner: {
      createRef: (input: { role: 'poster' | 'background'; locator: string; altText: string }) => {
        const ref = Object.freeze({
          id: input.role === 'poster' ? 'artwork-ABCDEFGHIJKLMNOP' : 'artwork-QRSTUVWXYZabcdef',
          kind: input.role, expiresAtMs: 10_000,
          altText: input.altText, status: 'available' as const,
        });
        createdInputs.push({ role: input.role, locator: input.locator });
        createdRefs.push(ref);
        return ref;
      },
    } as never,
  });
  const projected = await runtime.getPagedPresentation({
    startTimeMs: 1_000,
    durationMs: 1_800_000,
    channelOffset: 0,
    channelLimit: 24,
    generation: createGeneration(repository, 2),
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
  });

  assert.equal(projected.channels[0]!.programs[0]!.title, '[redacted]');
  assert.equal(projected.channels[0]!.programs[0]!.artwork.poster?.altText, '[redacted]');
  assert.equal(projected.channels[0]!.programs[0]!.artwork.background?.altText, '[redacted]');
  assert.notEqual(projected.channels[0]!.programs[0]!.artwork.poster, createdRefs[0]);
  assert.notEqual(projected.channels[0]!.programs[0]!.artwork.background, createdRefs[1]);
  const serializedProjection = JSON.stringify(projected);
  assert.equal(serializedProjection.includes(privateLocatorMarker), false);
  assert.equal(createdInputs.some(({ locator }) => locator === privateLocatorMarker), false);
  assert.deepEqual(createdInputs, [
    { role: 'poster', locator: `/library/metadata/1/thumb?private=${privateLocatorMarker}` },
    { role: 'background', locator: `/library/metadata/1/art?private=${privateLocatorMarker}` },
  ]);
  assert.equal((createdRefs[0] as { altText: string }).altText, hostileTitle);
});

test('GuideRuntime tuneChannel configures active scheduler and persists choice', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [createLibraryItem(0)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  await runtime.tuneChannel('chan-1');

  // Verify scheduler is active
  const state = activeScheduler.getState();
  assert.equal(state.isActive, true);
  assert.equal(state.channelId, 'chan-1');
  assert.equal(state.currentProgram?.item.title, 'Movie 0');

  // Verify persisted selection
  assert.equal(repository.data.currentChannelId, 'chan-1');
});

test('GuideRuntime tuneChannel does not mutate active scheduler when persistence fails', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];
  repository.saveError = new Error('persist failed');

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [createLibraryItem(0)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  await assert.rejects(() => runtime.tuneChannel('chan-1'), /persist failed/u);

  assert.equal(activeScheduler.getState().isActive, false);
  assert.equal(repository.data.currentChannelId, null);
});

test('GuideRuntime excludes hidden channels from paged presentation and tuning', async () => {
  const repository = new MockChannelRepository();
  const hidden = createChannelConfig('hidden-chan', 1, 'Hidden Channel', 'lib-hidden');
  hidden.hidden = true;
  const visible = createChannelConfig('visible-chan', 2, 'Visible Channel', 'lib-visible');
  repository.data.channels = [hidden, visible];
  repository.data.currentChannelId = 'hidden-chan';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-hidden', [createLibraryItem(0)]);
  plexAdapter.setLibraryItems('lib-visible', [createLibraryItem(1)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
    ...pagedRuntimeOptions(),
  });

  const presentation = await runtime.getPagedPresentation({
    startTimeMs: 1000,
    durationMs: 1_800_000,
    channelOffset: 0,
    channelLimit: 24,
    generation: createGeneration(repository),
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
  });
  await assert.rejects(() => runtime.tuneChannel('hidden-chan'), /Channel not found/u);

  assert.deepEqual(presentation.channels.map((channel) => channel.id), ['visible-chan']);
  assert.equal(presentation.nowWatching?.channelId ?? null, null);
  assert.equal(activeScheduler.getState().isActive, false);
  assert.equal(repository.data.currentChannelId, 'hidden-chan');
});

test('GuideRuntime logs and isolates onChannelTuned callback failures', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [createLibraryItem(0)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });
  const errors: unknown[] = [];

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
    onChannelTuned: () => {
      throw new Error('callback failed');
    },
    logger: {
      warn: () => undefined,
      error: (_message, detail) => errors.push(detail),
    },
  });

  await runtime.tuneChannel('chan-1');

  assert.equal(activeScheduler.getState().isActive, true);
  assert.equal(repository.data.currentChannelId, 'chan-1');
  assert.equal(errors.length, 1);
  assert.match(JSON.stringify(errors[0]), /callback failed/u);
});

test('GuideRuntime paged presentation logs content resolution failures while returning empty channel programs', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];
  repository.data.currentChannelId = 'chan-1';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryError('lib-1', new Error('library unavailable'));
  const errors: unknown[] = [];

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 1000 } }),
    clock: { now: () => 1000 },
    ...pagedRuntimeOptions(),
    logger: {
      warn: () => undefined,
      error: (_message, detail) => errors.push(detail),
    },
  });

  const presentation = await runtime.getPagedPresentation({
    startTimeMs: 1000,
    durationMs: 1_800_000,
    channelOffset: 0,
    channelLimit: 24,
    generation: createGeneration(repository),
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
  });

  assert.equal(presentation.channels[0]?.programs.length, 0);
  assert.equal(errors.length, 1);
  assert.match(JSON.stringify(errors[0]), /library unavailable/u);
});

test('GuideRuntime initializeActiveChannel tunes to last active channel', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];
  repository.data.currentChannelId = 'chan-1';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-1', [createLibraryItem(0)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  await runtime.initializeActiveChannel();

  const state = activeScheduler.getState();
  assert.equal(state.isActive, true);
  assert.equal(state.channelId, 'chan-1');
});

test('GuideRuntime initializeActiveChannel skips hidden stored current channel', async () => {
  const repository = new MockChannelRepository();
  const hidden = createChannelConfig('hidden-chan', 1, 'Hidden Channel', 'lib-hidden');
  hidden.hidden = true;
  const visible = createChannelConfig('visible-chan', 2, 'Visible Channel', 'lib-visible');
  repository.data.channels = [hidden, visible];
  repository.data.currentChannelId = 'hidden-chan';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-hidden', [createLibraryItem(0)]);
  plexAdapter.setLibraryItems('lib-visible', [createLibraryItem(1)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  await runtime.initializeActiveChannel();

  const state = activeScheduler.getState();
  assert.equal(state.isActive, true);
  assert.equal(state.channelId, 'visible-chan');
  assert.equal(repository.data.currentChannelId, 'visible-chan');
});

test('GuideRuntime refreshActiveChannelSelection retunes to a visible fallback before unloading', async () => {
  const repository = new MockChannelRepository();
  const hidden = createChannelConfig('hidden-chan', 1, 'Hidden Channel', 'lib-hidden');
  hidden.hidden = true;
  const visible = createChannelConfig('visible-chan', 2, 'Visible Channel', 'lib-visible');
  repository.data.channels = [hidden, visible];
  repository.data.currentChannelId = 'hidden-chan';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryItems('lib-hidden', [createLibraryItem(0)]);
  plexAdapter.setLibraryItems('lib-visible', [createLibraryItem(1)]);
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  await runtime.refreshActiveChannelSelection();

  const state = activeScheduler.getState();
  assert.equal(state.isActive, true);
  assert.equal(state.channelId, 'visible-chan');
  assert.equal(repository.data.currentChannelId, 'visible-chan');
});

test('GuideRuntime logs initializeActiveChannel tuning failures without throwing', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];
  repository.data.currentChannelId = 'chan-1';

  const plexAdapter = new MockPlexLibraryAdapter();
  plexAdapter.setLibraryError('lib-1', new Error('startup tune failed'));
  const errors: unknown[] = [];

  const runtime = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: plexAdapter as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 1000 } }),
    clock: { now: () => 1000 },
    logger: {
      warn: () => undefined,
      error: (_message, detail) => errors.push(detail),
    },
  });

  await runtime.initializeActiveChannel();

  assert.equal(errors.length, 1);
  assert.match(JSON.stringify(errors[0]), /startup tune failed/u);
});
