import assert from 'node:assert/strict';
import test from 'node:test';

import type { PlayerEvent, PlayerSnapshot } from '../../../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../../../contracts/shell.js';
import { DesktopPlayerAdapter } from '../../../main/player/desktopPlayerAdapter.js';
import { createDesktopPlayerAdapterRuntimePort } from '../../../main/player/plexPlaybackComposition.js';
import {
  PlexPlaybackRuntime,
  PlexPlaybackRuntimeCandidateResolutionError,
  type PlexPlaybackRuntimeCandidate,
} from '../../../main/player/plexPlaybackRuntime.js';
// This reviewed integration regression intentionally crosses the main/renderer test-owner boundary.
// eslint-disable-next-line no-restricted-imports
import { createPlayerOverlayController, type PlayerOverlayTimerHost } from '../../../renderer/playerOverlayController.js';
// eslint-disable-next-line no-restricted-imports
import { subscribePlayerBridge } from '../../../renderer/playerBridgeSubscription.js';
// eslint-disable-next-line no-restricted-imports
import { createPlayerOverlayState } from '../../../renderer/overlays.js';
// eslint-disable-next-line no-restricted-imports
import { createPlayerOverlayView } from '../../../renderer/overlayViewModels.js';
// eslint-disable-next-line no-restricted-imports
import {
  createEmptyPlayerSnapshot,
  type PlayerOverlayPresentationSource,
} from '../../../renderer/playerOverlayPresentation.js';
import type { NativePlayerHostPort } from '../../../main/player/nativePlayerHostPort.js';

test('real runtime and adapter failure clears an active subscribed transition into recovery UI', async () => {
  const adapter = new DesktopPlayerAdapter(new InertNativePlayerHost());
  const playerPort = createDesktopPlayerAdapterRuntimePort(adapter);
  const harness = createRendererHarness(adapter);
  const runtime = new PlexPlaybackRuntime({
    scheduler: {
      getCurrentPlayback: async () => ({
        channelId: 'channel-two',
        programId: 'program-two',
        startedAtMs: 1_000,
        endsAtMs: 121_000,
      }),
    },
    channel: {
      resolvePlaybackCandidate: async () => {
        throw new PlexPlaybackRuntimeCandidateResolutionError({
          code: 'PLAYER_PLAYBACK_CANDIDATE_UNAVAILABLE',
          category: 'source',
          message: 'The scheduled media could not be resolved.',
          recoverable: true,
          retryable: true,
          diagnostic: {
            component: 'plex-playback-bridge',
            operation: 'stream.resolve',
            status: 'failed',
            reason: 'media detail unavailable',
          },
        });
      },
    },
    player: playerPort,
    pms: { releaseSession: async () => undefined },
    clock: { now: () => 2_000 },
    onEvents: (events) => {
      for (const event of events) harness.emitPlayerEvent(event);
    },
  });

  void harness.controller.tune('two', 'miniGuide');
  harness.timers.advance(175);
  assert.equal(harness.getState().transitionChannelId, 'two');
  assert.equal(harness.getState().transitionVisible, true);

  const result = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(result.accepted, false);
  assert.deepEqual(result.events.map((event) => event.event), ['error', 'state.changed']);
  assert.equal(harness.getSnapshot().status, 'error');
  assert.deepEqual(harness.getSnapshot(), adapter.getSnapshot());
  assert.equal(harness.getState().transitionChannelId, null);
  assert.equal(harness.getState().transitionVisible, false);
  const view = createPlayerOverlayView(harness.getState(), createPresentation(harness.getSnapshot()));
  assert.equal(view.visibleOverlays.transition, false);
  assert.equal(view.visibleOverlays.playerError, true);
  assert.equal(view.retryVisible, true);

  harness.dispose();
});

test('candidate failure settles renderer state when failed cleanup retains the active adapter request', async () => {
  const host = new FailingCleanupNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  const harness = createRendererHarness(adapter);
  let resolutionCount = 0;
  const runtime = new PlexPlaybackRuntime({
    scheduler: {
      getCurrentPlayback: async () => ({
        channelId: 'channel-two',
        programId: 'program-two',
        startedAtMs: 1_000,
        endsAtMs: 121_000,
      }),
    },
    channel: {
      resolvePlaybackCandidate: async () => {
        resolutionCount += 1;
        if (resolutionCount === 1) return createCandidate('active-request');
        throw new PlexPlaybackRuntimeCandidateResolutionError({
          code: 'PLAYER_PLAYBACK_CANDIDATE_UNAVAILABLE',
          category: 'source',
          message: 'The scheduled media could not be resolved.',
          recoverable: true,
          retryable: true,
        });
      },
    },
    player: createDesktopPlayerAdapterRuntimePort(adapter),
    pms: { releaseSession: async () => undefined },
    clock: { now: () => 2_000 },
    onEvents: (events) => {
      for (const event of events) harness.emitPlayerEvent(event);
    },
  });

  const started = await runtime.startCurrentPlayback('startup');
  assert.equal(started.accepted, true);
  assert.equal(adapter.getSnapshot().requestId, 'active-request');
  host.failCleanup = true;

  void harness.controller.tune('two', 'miniGuide');
  harness.timers.advance(175);
  const failed = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(failed.accepted, false);
  assert.deepEqual(failed.events.map((event) => event.event), [
    'error',
    'state.changed',
    'error',
    'state.changed',
  ]);
  assert.equal(harness.getSnapshot().requestId, 'active-request');
  assert.equal(harness.getSnapshot().status, 'error');
  assert.deepEqual(harness.getSnapshot(), adapter.getSnapshot());
  assert.equal(harness.getState().transitionChannelId, null);
  assert.equal(createPlayerOverlayView(
    harness.getState(),
    createPresentation(harness.getSnapshot()),
  ).visibleOverlays.playerError, true);

  harness.dispose();
});

class InertNativePlayerHost implements NativePlayerHostPort {
  async execute() { return { ok: true as const }; }
  async cleanup() {}
  async queryAudioOutputs() { return { ok: true as const, outputs: [] }; }
}

class FailingCleanupNativePlayerHost extends InertNativePlayerHost {
  failCleanup = false;

  override async cleanup(): Promise<void> {
    if (this.failCleanup) throw new Error('native cleanup failed');
  }
}

function createCandidate(requestId: string): PlexPlaybackRuntimeCandidate {
  const media = { id: 'media-one', title: 'Program one' };
  return {
    requestId,
    load: {
      media: { ...media, durationMs: 120_000, container: 'mp4' },
      policy: {
        autoplay: true,
        startPositionMs: 1_000,
        preferredAudioTrackId: null,
        preferredSubtitleTrackId: null,
      },
      seekSupport: 'supported',
      capabilityProfileId: 'desktop-safe',
    },
    privatePlayback: {
      requestId,
      decisionKind: 'direct-play',
      playbackUrl: 'https://plex.example.invalid/library/parts/one/file.mp4',
      credentialHeader: { name: 'X-Plex-Token', value: 'private-test-value' },
      selectedConnection: {
        protocol: 'https',
        address: 'plex.example.invalid',
        port: 443,
        local: true,
        relay: false,
      },
      media,
      setup: {
        playbackMode: 'direct-play',
        mediaPath: '/library/metadata/one',
        variantId: 'variant-one',
        partPath: '/library/parts/one/file.mp4',
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: { video: [], audio: [], subtitle: [] },
        audioOutputNativeKey: null,
        dtsPassthroughEnabled: false,
      },
    },
    pmsSession: { id: 'pms-one', requestId },
  };
}

function createRendererHarness(adapter: DesktopPlayerAdapter) {
  let emitPlayerEvent = (_event: PlayerEvent): void => {
    throw new Error('player subscription was not registered');
  };
  let snapshot: PlayerSnapshot = {
    ...createEmptyPlayerSnapshot(),
    requestId: 'previous-playback',
    status: 'playing',
    playing: true,
  };
  let state = createPlayerOverlayState(createPresentation(snapshot));
  const timers = new FakeTimers();
  const controller = createPlayerOverlayController({
    player: {
      dispatch: async (envelope) => ({
        ok: true,
        requestId: envelope.requestId,
        value: { accepted: true, events: [], snapshot },
      }),
      tuneChannel: async () => new Promise<never>(() => undefined),
    },
    host: timers,
    getState: () => state,
    setState: (next) => { state = next; },
    getPresentation: () => createPresentation(snapshot),
    render: () => undefined,
    focus: () => undefined,
    openGuide: () => undefined,
    refreshChannelStatus: async () => undefined,
    refreshGuidePresentation: async () => undefined,
    recordDiagnostic: () => undefined,
    nowPlayingAutoHideMs: 0,
    recovery: {
      retry: () => false,
      skip: () => false,
      reconcileSnapshot: () => false,
      invalidate: () => undefined,
      dispose: () => undefined,
    },
  });
  const playerBridge = {
    onEvent(listener: (event: PlayerEvent) => void) {
      emitPlayerEvent = listener;
      return () => { emitPlayerEvent = () => undefined; };
    },
    getSnapshot: async () => ({ ok: true as const, value: adapter.getSnapshot() }),
  } as LineupDesktopPreloadApi['player'];
  const subscription = subscribePlayerBridge({
    player: playerBridge,
    diagnostics: {
      recordRendererEvent: async () => ({ ok: true, value: undefined }),
    } as unknown as LineupDesktopPreloadApi['diagnostics'],
    getSnapshot: () => snapshot,
    setSnapshot: (next) => { snapshot = next; },
    onSnapshot: (next, authoritative, explicitTrackList) => {
      controller.reconcileSnapshot(next, authoritative, explicitTrackList);
    },
    onEvent: (event) => controller.handlePlayerEvent(event),
    render: () => undefined,
  });
  return {
    controller,
    timers,
    emitPlayerEvent: (event: PlayerEvent) => emitPlayerEvent(event),
    getSnapshot: () => snapshot,
    getState: () => state,
    dispose: () => {
      subscription.unsubscribe();
      controller.dispose();
    },
  };
}

class FakeTimers implements PlayerOverlayTimerHost {
  #now = 0;
  #next = 1;
  readonly #timers = new Map<number, { at: number; callback: () => void }>();

  setTimeout(callback: () => void, delayMs: number): number {
    const id = this.#next++;
    this.#timers.set(id, { at: this.#now + delayMs, callback });
    return id;
  }

  clearTimeout(id: number): void { this.#timers.delete(id); }

  advance(deltaMs: number): void {
    const target = this.#now + deltaMs;
    while (true) {
      const due = [...this.#timers.entries()]
        .filter(([, timer]) => timer.at <= target)
        .sort((left, right) => left[1].at - right[1].at)[0];
      if (due === undefined) break;
      this.#timers.delete(due[0]);
      this.#now = due[1].at;
      due[1].callback();
    }
    this.#now = target;
  }
}

function createPresentation(playerSnapshot: PlayerSnapshot): PlayerOverlayPresentationSource {
  return {
    playerSnapshot,
    currentChannelId: 'one',
    nowMs: 2_000,
    channels: [
      {
        id: 'one',
        number: '1',
        name: 'One',
        currentProgram: { id: 'one-current', title: 'One now', startsAtMs: 1_000, endsAtMs: 121_000 },
        nextProgram: { id: 'one-next', title: 'One next', startsAtMs: 121_000, endsAtMs: 241_000 },
      },
      {
        id: 'two',
        number: '2',
        name: 'Two',
        currentProgram: { id: 'two-current', title: 'Two now', startsAtMs: 1_000, endsAtMs: 121_000 },
      },
    ],
  };
}
