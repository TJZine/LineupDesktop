import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import type { ChannelConfig } from '../../domain/channel/types.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import { ChannelPublicReferenceOwner, type ChannelPublicReferenceGeneration } from '../../main/channel/channelPublicReferenceOwner.js';
import {
  computeGuideMinimumStartTimeMs,
  GuidePresentationCurrentnessError,
  GuideRuntime,
  isGuideShowOnlyScope,
} from '../../main/channel/guideRuntime.js';
import { DesktopGuidePreferencesStore } from '../../main/channel/desktopGuidePreferencesStore.js';

const NOW = Date.UTC(2026, 6, 8, 16, 45);
const AUTO_CLASSIFICATION_NOW = Date.UTC(2026, 6, 8, 16, 31);

function channel(
  id: string,
  source: ChannelConfig['contentSource'],
  sourceLibraryId?: string,
): ChannelConfig {
  return {
    id,
    number: Number(id.replace(/\D/gu, '') || 1),
    name: id,
    ...(sourceLibraryId === undefined ? {} : { sourceLibraryId }),
    contentSource: source,
    playbackMode: 'sequential',
    startTimeAnchor: NOW,
    skipIntros: false,
    skipCredits: false,
    createdAt: NOW,
    updatedAt: NOW,
    lastContentRefresh: NOW,
    itemCount: 1,
    totalDurationMs: 60 * 60 * 1_000,
  };
}

function show(id: string, libraryId = 'shows', sourceLibraryId?: string): ChannelConfig {
  return channel(id, {
    type: 'library', libraryId, libraryType: 'show', includeWatched: true,
  }, sourceLibraryId);
}

function movie(id: string, libraryId = 'movies'): ChannelConfig {
  return channel(id, {
    type: 'library', libraryId, libraryType: 'movie', includeWatched: true,
  });
}

function manual(id: string): ChannelConfig {
  return channel(id, { type: 'manual', items: [{ ratingKey: `${id}-item`, title: id, durationMs: 60 * 60 * 1_000 }] });
}

function mixed(id: string): ChannelConfig {
  return channel(id, {
    type: 'mixed', mixMode: 'sequential', sources: [
      { type: 'library', libraryId: 'shows', libraryType: 'show', includeWatched: true },
      { type: 'library', libraryId: 'movies', libraryType: 'movie', includeWatched: true },
    ],
  });
}

function generation(channels: readonly ChannelConfig[]): ChannelPublicReferenceGeneration {
  return Object.freeze({ lineupRevision: 1, channels, currentChannelId: channels[0]?.id ?? null, fingerprint: 'guide-past-items-window' });
}

test('main Auto classification uses raw source truth for selected and All scopes', () => {
  const showChannel = show('channel-1');
  assert.equal(isGuideShowOnlyScope([showChannel], null), true);
  assert.equal(isGuideShowOnlyScope([showChannel], 'shows'), true);
  assert.equal(isGuideShowOnlyScope([movie('channel-2')], null), false);
  assert.equal(isGuideShowOnlyScope([mixed('channel-3')], null), false);
  assert.equal(isGuideShowOnlyScope([manual('channel-4')], null), false);
  assert.equal(isGuideShowOnlyScope([channel('channel-collection', { type: 'collection', collectionKey: 'collection', collectionName: 'Collection' })], null), false);
  assert.equal(isGuideShowOnlyScope([channel('channel-playlist', { type: 'playlist', playlistKey: 'playlist', playlistName: 'Playlist' })], null), false);
  assert.equal(isGuideShowOnlyScope([channel('channel-show', { type: 'show', showKey: 'show', showName: 'Show' })], null), false);
  assert.equal(isGuideShowOnlyScope([channel('channel-unknown', { type: 'unknown' } as unknown as ChannelConfig['contentSource'])], null), false);
  assert.equal(isGuideShowOnlyScope([showChannel, manual('channel-5')], null), false);
  assert.equal(isGuideShowOnlyScope([show('channel-6', 'shows', 'other-library')], 'shows'), false);

  const processValue: unknown = Reflect.get(globalThis, 'process');
  assert.equal(typeof processValue, 'object');
  if (typeof processValue !== 'object' || processValue === null) return;
  const env = (processValue as { env: Record<string, string | undefined> }).env;
  const previousTimezone = env.TZ;
  try {
    env.TZ = 'America/New_York';
    // 2026-07-08T16:31:00Z / 12:31 EDT: Auto 0 -> 12:30, Auto 15 -> 12:00.
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, 'auto', [showChannel], null), 1_783_528_200_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, 'auto', [movie('channel-2')], null), 1_783_526_400_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, 'auto', [movie('channel-2')], 'movies'), 1_783_526_400_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, 'auto', [mixed('channel-3')], 'shows'), 1_783_526_400_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, 'auto', [showChannel], 'missing'), 1_783_526_400_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, '0', [movie('channel-2')], null), 1_783_528_200_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, '15', [showChannel], null), 1_783_526_400_000);
    assert.equal(computeGuideMinimumStartTimeMs(AUTO_CLASSIFICATION_NOW, '30', [showChannel], null), 1_783_526_400_000);
  } finally {
    if (previousTimezone === undefined) delete env.TZ;
    else env.TZ = previousTimezone;
  }
});

test('main bound clamps the schedule request before content resolution and preserves duration', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-past-window-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  let resolutions = 0;
  const runtime = new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: {
      getLibraryItems: async () => {
        resolutions += 1;
        return [{ ratingKey: 'item', type: 'movie', title: 'Item', durationMs: 60 * 60 * 1_000 }];
      },
      getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [], getItem: async () => null,
    } as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => NOW } }),
    clock: { now: () => NOW },
    preferencesStore: new DesktopGuidePreferencesStore(path.join(directory, 'preferences.json')),
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope',
    getPastItemsWindowSnapshot: async () => ({ revision: 4, pastItemsWindow: '15' as const, libraryTabsEnabled: true }),
  });
  const owner = new ChannelPublicReferenceOwner();
  const source = movie('channel-1');
  const value = await runtime.getPagedPresentation({
    startTimeMs: 0,
    durationMs: 2 * 60 * 60 * 1_000,
    channelOffset: 0,
    channelLimit: 9,
    generation: generation([source]),
    publicReferenceOwner: owner,
  });
  assert.equal(resolutions, 1);
  // 2026-07-08T16:45:00Z / 12:45 EDT, 15-minute window -> 2026-07-08T16:30:00Z / 12:30 EDT.
  const minimumStartTimeMs = 1_783_528_200_000;
  const windowEndTimeMs = minimumStartTimeMs + 2 * 60 * 60 * 1_000;
  assert.equal(value.minimumStartTimeMs, minimumStartTimeMs);
  assert.equal(value.channelWindow.total, 1);
  assert.ok(value.channels[0]?.programs.every((program) => program.startsAtMs < windowEndTimeMs && program.endsAtMs > minimumStartTimeMs));
  assert.ok((value.channels[0]?.programs.at(-1)?.endsAtMs ?? 0) >= windowEndTimeMs);
});

test('main rejects a Settings revision/value race through the dedicated currentness sentinel', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-past-window-race-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  let snapshot: { revision: number; pastItemsWindow: 'auto' | '0' | '15' | '30'; libraryTabsEnabled: boolean } = {
    revision: 1,
    pastItemsWindow: '15',
    libraryTabsEnabled: true,
  };
  let reads = 0;
  const runtime = new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: {
      getLibraryItems: async () => [{ ratingKey: 'item', type: 'movie', title: 'Item', durationMs: 60 * 60 * 1_000 }],
      getCollectionItems: async () => [], getShowEpisodes: async () => [], getPlaylistItems: async () => [], getItem: async () => null,
    } as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => NOW } }),
    clock: { now: () => NOW },
    preferencesStore: new DesktopGuidePreferencesStore(path.join(directory, 'preferences.json')),
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope',
    getPastItemsWindowSnapshot: async () => {
      reads += 1;
      if (reads === 2) snapshot = { revision: 2, pastItemsWindow: '30', libraryTabsEnabled: true };
      return snapshot;
    },
  });
  await assert.rejects(
    runtime.getPagedPresentation({
      startTimeMs: 0,
      durationMs: 60 * 60 * 1_000,
      channelOffset: 0,
      channelLimit: 9,
      generation: generation([manual('channel-1')]),
      publicReferenceOwner: new ChannelPublicReferenceOwner(),
    }),
    (error: unknown) => error instanceof GuidePresentationCurrentnessError,
  );
});

test('main local-midnight clamp remains calendar-based across spring-forward and fall-back', () => {
  const processValue: unknown = Reflect.get(globalThis, 'process');
  assert.equal(typeof processValue, 'object');
  if (typeof processValue !== 'object' || processValue === null) return;
  const env = (processValue as { env: Record<string, string | undefined> }).env;
  const previous = env.TZ;
  try {
    env.TZ = 'America/New_York';
    // 2024-03-10T05:15:00Z / 00:15 EST -> local midnight 2024-03-10T05:00:00Z.
    assert.equal(
      computeGuideMinimumStartTimeMs(Date.UTC(2024, 2, 10, 5, 15), '30', [movie('channel-1')], null),
      1_710_046_800_000,
    );
    // 2024-11-03T04:15:00Z / 00:15 EDT -> local midnight 2024-11-03T04:00:00Z.
    assert.equal(
      computeGuideMinimumStartTimeMs(Date.UTC(2024, 10, 3, 4, 15), '30', [movie('channel-1')], null),
      1_730_606_400_000,
    );
  } finally {
    if (previous === undefined) delete env.TZ;
    else env.TZ = previous;
  }
});
