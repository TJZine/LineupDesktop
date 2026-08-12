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

const PRIVATE_FIXTURE_PLAYBACK_URL = 'https://plex.example.invalid/library/parts/one/file.mp4';
const PRIVATE_FIXTURE_CREDENTIAL_VALUE = 'private-test-value';

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
      invalidatePlaybackMediaIdentity() {},
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
  const emittedBatches: Array<readonly PlayerEvent[]> = [];
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
      invalidatePlaybackMediaIdentity() {},
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
      emittedBatches.push(events);
      for (const event of events) harness.emitPlayerEvent(event);
    },
  });

  const started = await runtime.startCurrentPlayback('startup');
  assert.equal(started.accepted, true);
  assert.equal(adapter.getSnapshot().requestId, 'active-request');
  emittedBatches.length = 0;
  host.failCleanup = true;

  void harness.controller.tune('two', 'miniGuide');
  harness.timers.advance(175);
  const failed = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(failed.accepted, false);
  assert.equal(emittedBatches.length, 1);
  assert.deepEqual(emittedBatches[0], failed.events);
  assert.deepEqual(failed.events.map((event) => event.event), [
    'error',
    'state.changed',
    'error',
    'state.changed',
  ]);
  assert.equal(failed.events.filter((event) => (
    event.event === 'error' && event.error.code === 'PLAYER_PLAYBACK_CANDIDATE_UNAVAILABLE'
  )).length, 1);
  assert.deepEqual(failed.events.slice(-2).map((event) => event.event), ['error', 'state.changed']);
  assert.equal(harness.getSnapshot().requestId, 'active-request');
  assert.equal(harness.getSnapshot().status, 'error');
  assert.deepEqual(harness.getSnapshot(), adapter.getSnapshot());
  assert.equal(harness.getState().transitionChannelId, null);
  assert.equal(createPlayerOverlayView(
    harness.getState(),
    createPresentation(harness.getSnapshot()),
  ).visibleOverlays.playerError, true);
  assertNoPrivateFixtureValues(failed.events, 'failed.events');
  assertNoPrivateFixtureValues(emittedBatches, 'emitted batches');

  harness.dispose();
});

test('candidate failure settles a cleared adapter snapshot after successful scoped cleanup', async () => {
  const adapter = new DesktopPlayerAdapter(new InertNativePlayerHost());
  let resolutionCount = 0;
  const emittedBatches: Array<readonly PlayerEvent[]> = [];
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
      invalidatePlaybackMediaIdentity() {},
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
    onEvents: (events) => emittedBatches.push(events),
  });

  const started = await runtime.startCurrentPlayback('startup');
  assert.equal(started.accepted, true);
  assert.equal(adapter.getSnapshot().requestId, 'active-request');
  emittedBatches.length = 0;

  const failed = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(failed.accepted, false);
  assert.equal(emittedBatches.length, 1);
  assert.deepEqual(emittedBatches[0], failed.events);
  assert.deepEqual(failed.events.map((event) => event.event), [
    'state.changed',
    'error',
    'state.changed',
  ]);
  assert.equal(failed.events.filter((event) => event.event === 'error').length, 1);
  assert.deepEqual(failed.events.slice(-2).map((event) => event.event), ['error', 'state.changed']);
  const finalState = failed.events.at(-1);
  assert.equal(finalState?.event, 'state.changed');
  assert.equal(finalState?.event === 'state.changed' ? finalState.snapshot.requestId : 'not-state', null);
  assert.deepEqual(finalState?.event === 'state.changed' ? finalState.snapshot : null, adapter.getSnapshot());
  assert.equal(adapter.getSnapshot().requestId, null);
  assert.equal(adapter.getSnapshot().status, 'error');
  assertNoPrivateFixtureValues(failed.events, 'failed.events');
  assertNoPrivateFixtureValues(emittedBatches, 'emitted batches');
});

test('candidate failure emits a safe renderer error without overwriting an unrelated adapter request', async () => {
  const adapter = new DesktopPlayerAdapter(new InertNativePlayerHost());
  const playerPort = createDesktopPlayerAdapterRuntimePort(adapter);
  let resolutionCount = 0;
  const emittedBatches: Array<readonly PlayerEvent[]> = [];
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
      invalidatePlaybackMediaIdentity() {},
      resolvePlaybackCandidate: async () => {
        resolutionCount += 1;
        if (resolutionCount === 1) return createCandidate('active-request');
        const unrelatedResult = await adapter.dispatchRendererIntent({
          intent: 'player.load',
          requestId: 'unrelated-request',
          payload: createCandidate('unrelated-request').load,
        });
        assert.equal(unrelatedResult.accepted, true);
        throw new PlexPlaybackRuntimeCandidateResolutionError({
          code: 'PLAYER_PLAYBACK_CANDIDATE_UNAVAILABLE',
          category: 'source',
          message: 'The scheduled media could not be resolved.',
          recoverable: true,
          retryable: true,
        });
      },
    },
    player: playerPort,
    pms: { releaseSession: async () => undefined },
    clock: { now: () => 2_000 },
    onEvents: (events) => emittedBatches.push(events),
  });

  const started = await runtime.startCurrentPlayback('startup');
  assert.equal(started.accepted, true);
  emittedBatches.length = 0;

  const failed = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(failed.accepted, false);
  assert.deepEqual(failed.events.map((event) => event.event), ['state.changed', 'error']);
  const terminalEvent = failed.events.at(-1);
  assert.equal(terminalEvent?.event, 'error');
  assert.equal(
    terminalEvent?.event === 'error'
      ? terminalEvent.error.code
      : null,
    'PLAYER_PLAYBACK_CANDIDATE_UNAVAILABLE',
  );
  assert.deepEqual(emittedBatches, [failed.events]);
  assertNoPrivateFixtureValues(failed.events, 'failed.events');
  assertNoPrivateFixtureValues(emittedBatches, 'emitted batches');
  assert.equal(adapter.getSnapshot().requestId, 'unrelated-request');
  assert.equal(adapter.getSnapshot().status, 'loading');
  assert.equal(adapter.getSnapshot().media?.id, 'media-one');
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
      playbackUrl: PRIVATE_FIXTURE_PLAYBACK_URL,
      credentialHeader: { name: 'X-Plex-Token', value: PRIVATE_FIXTURE_CREDENTIAL_VALUE },
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

function assertNoPrivateFixtureValues(value: unknown, path: string): void {
  const serialized = JSON.stringify(value);
  assert.equal(serialized.includes(PRIVATE_FIXTURE_PLAYBACK_URL), false, `${path} leaked private fixture URL`);
  assert.equal(serialized.includes(PRIVATE_FIXTURE_CREDENTIAL_VALUE), false, `${path} leaked private fixture credential`);
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
