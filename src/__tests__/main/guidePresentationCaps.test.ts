import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import type { ChannelConfig } from '../../domain/channel/types.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import { ChannelPublicReferenceOwner, type ChannelPublicReferenceGeneration } from '../../main/channel/channelPublicReferenceOwner.js';
import { DesktopGuidePreferencesStore } from '../../main/channel/desktopGuidePreferencesStore.js';
import { GuideRuntime } from '../../main/channel/guideRuntime.js';

test('300-by-48 Guide fixture resolves 24 rows and applies chronological fair 1,000 cap', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-guide-caps-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const channels = Array.from({ length: 300 }, (_, index) => channel(index));
  let resolutions = 0;
  const runtime = new GuideRuntime({
    repository: { loadNormalized: async () => null } as never,
    plexLibraryAdapter: {
      getLibraryItems: async (libraryId: string) => {
        resolutions += 1;
        return Array.from({ length: 48 }, (_, index) => ({
          ratingKey: `${libraryId}-${String(index).padStart(2, '0')}`,
          type: 'movie',
          title: `${libraryId}-${String(index).padStart(2, '0')}`,
          durationMs: 30 * 60_000,
        }));
      },
      getCollectionItems: async () => [], getShowEpisodes: async () => [],
      getPlaylistItems: async () => [], getItem: async () => null,
    } as never,
    activeChannelScheduler: new ChannelScheduler({ clock: { now: () => 0 } }),
    clock: { now: () => 0 },
    preferencesStore: new DesktopGuidePreferencesStore(path.join(directory, 'guide.json')),
    guideContextSource: { getBuilderContextForMain: () => ({ ok: true, snapshot: { activeProfileId: 'profile', selectedServerId: 'server' } }) },
    createScopeToken: () => 'scope-token',
  });
  const generation: ChannelPublicReferenceGeneration = Object.freeze({
    lineupRevision: 1, channels, currentChannelId: null, fingerprint: 'caps-generation',
  });
  const result = await runtime.getPagedPresentation({
    startTimeMs: 0,
    durationMs: 24 * 60 * 60_000,
    channelOffset: 0,
    channelLimit: 24,
    generation,
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
  });

  assert.equal(result.channelWindow.total, 300);
  assert.equal(result.channels.length, 24);
  assert.equal(resolutions, 24);
  assert.equal(result.channels.reduce((total, row) => total + row.programs.length, 0), 1_000);
  assert.deepEqual(result.channels.map((row) => row.programs.length), [
    ...Array.from({ length: 16 }, () => 42),
    ...Array.from({ length: 8 }, () => 41),
  ]);
  for (const row of result.channels) {
    assert.ok(row.programs.length <= 200);
    assert.deepEqual(row.programs.map((program) => program.startsAtMs),
      [...row.programs.map((program) => program.startsAtMs)].sort((left, right) => left - right));
  }
});

function channel(index: number): ChannelConfig {
  const id = `channel-${String(index).padStart(3, '0')}`;
  const libraryId = `library-${String(index).padStart(3, '0')}`;
  return {
    id, number: index + 1, name: `Channel ${String(index + 1)}`, playbackMode: 'sequential',
    startTimeAnchor: 0, skipIntros: false, skipCredits: false, createdAt: 0, updatedAt: 0,
    lastContentRefresh: 0, itemCount: 48, totalDurationMs: 24 * 60 * 60_000,
    sourceLibraryId: libraryId, sourceLibraryName: `Library ${String(index + 1)}`,
    contentSource: { type: 'library', libraryId, libraryType: 'movie', includeWatched: true },
  };
}
