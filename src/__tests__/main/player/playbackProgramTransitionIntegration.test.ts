import test from 'node:test';
import assert from 'node:assert/strict';

import { ChannelScheduler } from '../../../domain/scheduler/channelScheduler.js';
import type { ChannelConfig } from '../../../domain/channel/types.js';
import type { ChannelRepository } from '../../../domain/channel/channelRepository.js';
import type { PlexMediaItemMinimal } from '../../../domain/channel/interfaces.js';
import type {
  PlexIpcResult,
  PlexRuntimeSnapshot,
  PlexSelectServerValue,
  PlexSwitchHomeUserValue,
} from '../../../contracts/plex.js';
import type { PlexLibraryMinimalAdapter } from '../../../main/channel/plexLibraryMinimalAdapter.js';
import { GuideRuntime } from '../../../main/channel/guideRuntime.js';
import { PlaybackProgramTransitionOwner } from '../../../main/player/playbackProgramTransitionOwner.js';
import {
  wirePlexPlaybackCleanup,
  type PlaybackCleanupPlexRuntime,
} from '../../../main/player/plexPlaybackCleanupWiring.js';
import {
  PlexPlaybackRuntime,
  projectPlexPlaybackScheduleSelection,
} from '../../../main/player/plexPlaybackRuntime.js';
import type { PlayerCommand } from '../../../contracts/player.js';

test('real guide and scheduler produce one runtime start for initialize, tune, natural transition, and skip', async () => {
  let nowMs = 1_000;
  const scheduler = new ChannelScheduler({
    clock: { now: () => nowMs },
    timers: {
      setInterval: () => 1,
      clearInterval: () => undefined,
    },
  });
  const repository = {
    async loadNormalized() {
      return {
        data: {
          channels: [channelConfig()],
          currentChannelId: 'channel-1',
        },
        didMutate: false,
      };
    },
    async saveCurrentChannelId() {},
  };
  const library = {
    async getLibraryItems(): Promise<PlexMediaItemMinimal[]> {
      return [media('one'), media('two'), media('three')];
    },
    async getCollectionItems(): Promise<PlexMediaItemMinimal[]> {
      return [];
    },
    async getShowEpisodes(): Promise<PlexMediaItemMinimal[]> {
      return [];
    },
    async getPlaylistItems(): Promise<PlexMediaItemMinimal[]> {
      return [];
    },
    async getItem(): Promise<PlexMediaItemMinimal | null> {
      return null;
    },
  };
  const guide = new GuideRuntime({
    repository: repository as unknown as ChannelRepository,
    plexLibraryAdapter: library as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: scheduler,
    clock: { now: () => nowMs },
  });
  const starts: string[] = [];
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      async startCurrentPlayback() {
        starts.push(scheduler.getCurrentProgram().item.ratingKey);
        return {
          accepted: true,
          epoch: starts.length,
          requestId: `request-${starts.length}`,
          events: [],
        };
      },
      async retryCurrentPlayback() {
        return true;
      },
    },
  });

  await guide.initializeActiveChannel();
  await flush();
  assert.deepEqual(starts, ['one']);

  await guide.tuneChannel('channel-1');
  await flush();
  assert.deepEqual(starts, ['one', 'one']);

  nowMs = 2_100;
  scheduler.syncToCurrentTime();
  await flush();
  assert.deepEqual(starts, ['one', 'one', 'two']);

  assert.deepEqual(await owner.skipNext(), { accepted: true });
  assert.deepEqual(starts, ['one', 'one', 'two', 'three']);
  owner.dispose();
});

test('completed helper cleanup can Retry only the canonical current program through the real runtime', async () => {
  const scheduler = new ChannelScheduler({
    clock: { now: () => 1_000 },
    timers: {
      setInterval: () => 1,
      clearInterval: () => undefined,
    },
  });
  const guide = new GuideRuntime({
    repository: {
      async loadNormalized() {
        return {
          data: {
            channels: [channelConfig()],
            currentChannelId: 'channel-1',
          },
          didMutate: false,
        };
      },
      async saveCurrentChannelId() {},
    } as unknown as ChannelRepository,
    plexLibraryAdapter: {
      async getLibraryItems() {
        return [media('one'), media('two')];
      },
      async getCollectionItems() {
        return [];
      },
      async getShowEpisodes() {
        return [];
      },
      async getPlaylistItems() {
        return [];
      },
      async getItem() {
        return null;
      },
    } as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: scheduler,
    clock: { now: () => 1_000 },
  });
  const commands: PlayerCommand[] = [];
  const releasedRequestIds: string[] = [];
  const playerCleanupStarted = deferred<void>();
  const playerCleanupRelease = deferred<void>();
  let currentSelectionPromise: Promise<ReturnType<typeof projectCurrentSelection>> | null = null;
  let requestNumber = 0;
  const runtime = new PlexPlaybackRuntime({
    scheduler: {
      async getCurrentPlayback() {
        if (currentSelectionPromise !== null) {
          return currentSelectionPromise;
        }
        const state = scheduler.getState();
        return projectCurrentSelection(state);
      },
    },
    channel: {
      async resolvePlaybackCandidate(selection) {
        requestNumber += 1;
        const requestId = `request-${String(requestNumber)}`;
        return {
          requestId,
          load: {
            media: {
              id: selection.programId,
              title: 'Scheduled media',
              durationMs: 1_000,
            },
            policy: {
              autoplay: true,
              startPositionMs: 0,
              preferredAudioTrackId: null,
              preferredSubtitleTrackId: null,
            },
            capabilityProfileId: 'desktop-safe',
          },
          pmsSession: { id: `pms-${requestId}`, requestId },
        };
      },
    },
    player: {
      async dispatch(command) {
        commands.push(command);
        return { ok: true };
      },
      async cleanup() {
        playerCleanupStarted.resolve(undefined);
        await playerCleanupRelease.promise;
      },
    },
    pms: {
      async releaseSession(session) {
        releasedRequestIds.push(session.requestId);
      },
    },
    clock: { now: () => 1_000 },
  });
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime,
  });

  await guide.initializeActiveChannel();
  await waitFor(() => commands.length === 1);
  const staleSelection = deferred<ReturnType<typeof projectCurrentSelection>>();
  currentSelectionPromise = staleSelection.promise;
  const pendingRetry = owner.retryCurrent();
  const releaseCleanupHold = owner.acquireCleanupHold();
  owner.invalidate();
  const cleanup = runtime.handleHelperCrash().finally(releaseCleanupHold);
  await playerCleanupStarted.promise;

  assert.deepEqual(await pendingRetry, { accepted: false, reason: 'stale' });
  assert.deepEqual(await owner.retryCurrent(), {
    accepted: false,
    reason: 'busy',
  });
  assert.deepEqual(await owner.skipNext(), {
    accepted: false,
    reason: 'busy',
  });
  scheduler.skipToNext();
  await flush();
  assert.equal(commands.length, 1);

  playerCleanupRelease.resolve(undefined);
  await cleanup;
  assert.equal(commands.length, 1);
  currentSelectionPromise = null;
  staleSelection.resolve(projectCurrentSelection(scheduler.getState()));

  assert.deepEqual(await owner.retryCurrent(), { accepted: true });
  assert.deepEqual(
    commands.map((command) => command.requestId),
    ['request-1', 'request-2'],
  );
  assert.deepEqual(releasedRequestIds, ['request-1']);
  owner.dispose();
  await runtime.teardown();
});

test('real Plex cleanup wiring holds profile and server transitions until cleanup settles', async () => {
  await assertPlexCleanupCustody('profile-change');
  await assertPlexCleanupCustody('server-change');
});

function channelConfig(): ChannelConfig {
  return {
    id: 'channel-1',
    number: 1,
    name: 'One',
    playbackMode: 'sequential',
    startTimeAnchor: 1_000,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1_000,
    updatedAt: 1_000,
    lastContentRefresh: 1_000,
    itemCount: 3,
    totalDurationMs: 3_000,
    contentSource: {
      type: 'library',
      libraryId: 'library-1',
      libraryType: 'movie',
      includeWatched: true,
    },
  };
}

function media(ratingKey: string): PlexMediaItemMinimal {
  return {
    ratingKey,
    type: 'movie',
    title: ratingKey,
    durationMs: 1_000,
    thumb: null,
    year: 2026,
  };
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) {
      return;
    }
    await flush();
  }
  assert.fail('Expected playback work to settle.');
}

function projectCurrentSelection(
  state: ReturnType<ChannelScheduler['getState']>,
) {
  if (!state.isActive || state.currentProgram === null) {
    return null;
  }
  return projectPlexPlaybackScheduleSelection({
    channelId: state.channelId,
    ratingKey: state.currentProgram.item.ratingKey,
    scheduledStartTime: state.currentProgram.scheduledStartTime,
    scheduledEndTime: state.currentProgram.scheduledEndTime,
  });
}

async function assertPlexCleanupCustody(
  reason: 'profile-change' | 'server-change',
): Promise<void> {
  const scheduler = new ChannelScheduler({
    clock: { now: () => 1_000 },
    timers: {
      setInterval: () => 1,
      clearInterval: () => undefined,
    },
  });
  const guide = new GuideRuntime({
    repository: {
      async loadNormalized() {
        return {
          data: {
            channels: [channelConfig()],
            currentChannelId: 'channel-1',
          },
          didMutate: false,
        };
      },
      async saveCurrentChannelId() {},
    } as unknown as ChannelRepository,
    plexLibraryAdapter: {
      async getLibraryItems() {
        return [media('one'), media('two'), media('three')];
      },
      async getCollectionItems() {
        return [];
      },
      async getShowEpisodes() {
        return [];
      },
      async getPlaylistItems() {
        return [];
      },
      async getItem() {
        return null;
      },
    } as unknown as PlexLibraryMinimalAdapter,
    activeChannelScheduler: scheduler,
    clock: { now: () => 1_000 },
  });
  const pendingRetry = deferred<boolean>();
  const cleanupStarted = deferred<void>();
  const cleanupRelease = deferred<void>();
  let deferRetry = false;
  let starts = 0;
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      async startCurrentPlayback() {
        starts += 1;
        return {
          accepted: true,
          epoch: starts,
          requestId: `request-${String(starts)}`,
          events: [],
        };
      },
      retryCurrentPlayback() {
        return deferRetry ? pendingRetry.promise : Promise.resolve(true);
      },
    },
  });
  const plexRuntime = createSuccessfulPlexRuntime();
  wirePlexPlaybackCleanup({
    plexRuntime,
    getPlaybackRuntime: () => ({
      cleanup: async (input) => {
        assert.equal(input.reason, reason);
        const releaseCleanupHold = owner.acquireCleanupHold();
        owner.invalidate();
        cleanupStarted.resolve(undefined);
        try {
          await cleanupRelease.promise;
          return [];
        } finally {
          releaseCleanupHold();
        }
      },
    }),
    reportDiagnostic: () => undefined,
  });

  await guide.initializeActiveChannel();
  await flush();
  assert.equal(starts, 1);

  deferRetry = true;
  const staleRetry = owner.retryCurrent();
  const plexCall = reason === 'profile-change'
    ? plexRuntime.switchHomeUser('profile-request', { userId: 'user-1' })
    : plexRuntime.selectServer('server-request', 'server-1');
  await cleanupStarted.promise;

  assert.deepEqual(await staleRetry, { accepted: false, reason: 'stale' });
  assert.deepEqual(await owner.retryCurrent(), {
    accepted: false,
    reason: 'busy',
  });
  const currentBeforeSkip = scheduler.getCurrentProgram().item.ratingKey;
  assert.deepEqual(await owner.skipNext(), {
    accepted: false,
    reason: 'busy',
  });
  assert.equal(scheduler.getCurrentProgram().item.ratingKey, currentBeforeSkip);
  scheduler.skipToNext();
  await flush();
  assert.equal(starts, 1);

  cleanupRelease.resolve(undefined);
  await plexCall;
  assert.equal(starts, 1);
  deferRetry = false;
  pendingRetry.resolve(true);
  assert.deepEqual(await owner.retryCurrent(), { accepted: true });
  scheduler.skipToNext();
  await flush();
  assert.equal(starts, 2);
  owner.dispose();
}

function createSuccessfulPlexRuntime(): PlaybackCleanupPlexRuntime {
  const snapshot = {} as PlexRuntimeSnapshot;
  return {
    async switchHomeUser(requestId) {
      return {
        ok: true,
        value: {
          profile: {
            accountId: 'user-1',
            username: 'user1',
          },
          snapshot,
        },
        requestId,
      } satisfies PlexIpcResult<PlexSwitchHomeUserValue>;
    },
    async selectServer(requestId) {
      return {
        ok: true,
        value: {
          selection: {
            kind: 'selected',
            server: {
              serverId: 'server-1',
              name: 'server1',
              owned: true,
              connectionCount: 1,
              hasLocalConnection: true,
              hasRemoteConnection: false,
              hasRelayConnection: false,
              selected: true,
            },
            persisted: true,
          },
          snapshot,
        },
        requestId,
      } satisfies PlexIpcResult<PlexSelectServerValue>;
    },
  };
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve(value: T): void;
} {
  let resolve = (_value: T): void => undefined;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
