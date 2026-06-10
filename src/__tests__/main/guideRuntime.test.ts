import test from 'node:test';
import assert from 'node:assert/strict';
import { GuideRuntime } from '../../main/channel/guideRuntime.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import type { ChannelConfig, ResolvedContentItem } from '../../domain/channel/types.js';

class MockChannelRepository {
  public data = {
    channels: [] as ChannelConfig[],
    currentChannelId: null as string | null,
  };
  async loadNormalized() {
    if (this.data.channels.length === 0) {
      return null;
    }
    return { data: this.data, didMutate: false };
  }
  async saveCurrentChannelId(id: string | null) {
    this.data.currentChannelId = id;
  }
}

class MockPlexLibraryAdapter {
  // Not used directly in these tests since we stub contentResolver.resolveSource
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

function createResolvedItem(index: number, durationMs = 1_800_000): ResolvedContentItem {
  return {
    ratingKey: `item-${index}`,
    type: 'movie',
    title: `Movie ${index}`,
    fullTitle: `Movie ${index}`,
    durationMs,
    thumb: 'thumb-key',
    year: 2026,
    scheduledIndex: index,
  };
}

test('GuideRuntime getPresentation returns empty channels list if none configured', async () => {
  const repository = new MockChannelRepository();
  const plexAdapter = new MockPlexLibraryAdapter();
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as any,
    plexLibraryAdapter: plexAdapter as any,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  const presentation = await runtime.getPresentation(1000, 3600 * 1000);
  assert.deepEqual(presentation, {
    channels: [],
    nowWatching: null,
  });
});

test('GuideRuntime getPresentation generates schedule presentation for channels', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1', 'lib-1');
  const chan2 = createChannelConfig('chan-2', 2, 'Channel 2', 'lib-2');
  repository.data.channels = [chan1, chan2];
  repository.data.currentChannelId = 'chan-1';

  const plexAdapter = new MockPlexLibraryAdapter();
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  // Resolve items: Movie 1 for Channel 1, Movie 2 for Channel 2
  const runtime = new GuideRuntime({
    repository: repository as any,
    plexLibraryAdapter: plexAdapter as any,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  // Stub contentResolver.resolveSource internally
  (runtime as any).contentResolver.resolveSource = async (source: any) => {
    if (source.libraryId === 'lib-1') {
      return [createResolvedItem(0)];
    }
    return [createResolvedItem(1)];
  };

  const presentation = await runtime.getPresentation(1000, 1_800_000);

  assert.equal(presentation.channels.length, 2);
  assert.equal(presentation.channels[0]?.id, 'chan-1');
  assert.equal(presentation.channels[0]?.programs.length, 1);
  assert.equal(presentation.channels[0]?.programs[0]?.title, 'Movie 0');

  assert.equal(presentation.channels[1]?.id, 'chan-2');
  assert.equal(presentation.channels[1]?.programs.length, 1);
  assert.equal(presentation.channels[1]?.programs[0]?.title, 'Movie 1');
});

test('GuideRuntime tuneChannel configures active scheduler and persists choice', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];

  const plexAdapter = new MockPlexLibraryAdapter();
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as any,
    plexLibraryAdapter: plexAdapter as any,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  (runtime as any).contentResolver.resolveSource = async () => {
    return [createResolvedItem(0)];
  };

  await runtime.tuneChannel('chan-1');

  // Verify scheduler is active
  const state = activeScheduler.getState();
  assert.equal(state.isActive, true);
  assert.equal(state.channelId, 'chan-1');
  assert.equal(state.currentProgram?.item.title, 'Movie 0');

  // Verify persisted selection
  assert.equal(repository.data.currentChannelId, 'chan-1');
});

test('GuideRuntime initializeActiveChannel tunes to last active channel', async () => {
  const repository = new MockChannelRepository();
  const chan1 = createChannelConfig('chan-1', 1, 'Channel 1');
  repository.data.channels = [chan1];
  repository.data.currentChannelId = 'chan-1';

  const plexAdapter = new MockPlexLibraryAdapter();
  const activeScheduler = new ChannelScheduler({ clock: { now: () => 1000 } });

  const runtime = new GuideRuntime({
    repository: repository as any,
    plexLibraryAdapter: plexAdapter as any,
    activeChannelScheduler: activeScheduler,
    clock: { now: () => 1000 },
  });

  (runtime as any).contentResolver.resolveSource = async () => {
    return [createResolvedItem(0)];
  };

  await runtime.initializeActiveChannel();

  const state = activeScheduler.getState();
  assert.equal(state.isActive, true);
  assert.equal(state.channelId, 'chan-1');
});
