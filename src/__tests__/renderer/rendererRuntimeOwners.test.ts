import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  createDesktopSettingsView,
  desktopSettingsFailure,
  desktopSettingsSuccess,
  normalizeDesktopSettingsReplaceValues,
} from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import type { GuidePresentationSource } from '../../contracts/guide.js';
import type { PlayerEvent, PlayerSnapshot } from '../../contracts/player.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import {
  DEFAULT_EPG_PRESENTATION_SOURCE,
  EPG_SLOT_DURATION_MS,
  createGuideProgramFocusId,
  createEpgState,
  settleEpgPresentation,
  type EpgPresentationSource,
} from '../../renderer/epg.js';
import { captureGuideProgramFocusIntent, renderRendererFocus, syncRendererFocusTargets } from '../../renderer/focusDom.js';
import { createFullscreenTransportCoordinator } from '../../renderer/fullscreenTransport.js';
import { createEmptyPlayerSnapshot } from '../../renderer/playerOverlayPresentation.js';
import { createGuidePresentationPolling } from '../../renderer/guidePresentationPolling.js';
import { REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE } from '../../renderer/guideVirtualization.js';
import { FocusRegistry, type FocusState } from '../../renderer/navigation.js';
import { dispatchPlexRuntimeAction } from '../../renderer/plexRuntimeActionDispatch.js';
import { subscribePlayerBridge } from '../../renderer/playerBridgeSubscription.js';
import type { PlexRuntimeController } from '../../renderer/plexRuntimeActions.js';
import { createShellController } from '../../renderer/shell/shellController.js';
import { createRendererShellState, type RendererShellState } from '../../renderer/shell/shellState.js';
import { createSettingsRuntime } from '../../renderer/settings/settingsRuntime.js';
import { createSettingsGuideSettingsSettlementOwner } from '../../renderer/settings/guideSettingsSettlement.js';

test('player bridge subscription owns event projection and unsubscribe cleanup', async () => {
  const initialSnapshot = { ...createEmptyPlayerSnapshot(), requestId: 'playback-1', status: 'playing' as const, playing: true };
  let snapshot: PlayerSnapshot = initialSnapshot;
  let renderCount = 0;
  let progressRenderCount = 0;
  let emitPlayerEvent = (_event: PlayerEvent): void => {
    throw new Error('player event listener was not registered');
  };
  let unsubscribed = false;

  const subscription = subscribePlayerBridge({
    player: {
      onEvent(callback) {
        emitPlayerEvent = callback;
        return () => {
          unsubscribed = true;
        };
      },
      async getSnapshot() {
        return {
          ok: true,
          value: {
            ...initialSnapshot,
            positionMs: 42,
          },
        };
      },
    } as LineupDesktopPreloadApi['player'],
    diagnostics: {
      recordRendererEvent: async () => ({ ok: true, value: undefined }),
      getSummary: async () => ({ ok: true, value: { events: [] } }),
      exportSupportBundle: async () => ({
        ok: true,
        value: {
          fileName: 'support-bundle.zip',
          redactionCounts: {},
          sizeBytes: 1,
        },
      }),
    } as unknown as LineupDesktopPreloadApi['diagnostics'],
    getSnapshot: () => snapshot,
    setSnapshot(nextSnapshot: PlayerSnapshot) {
      snapshot = nextSnapshot;
    },
    render() {
      renderCount += 1;
    },
    renderProgress() {
      progressRenderCount += 1;
    },
  });

  await subscription.initializeSnapshot();
  assert.equal(snapshot.positionMs, 42);
  assert.equal(renderCount, 1);

  emitPlayerEvent({ event: 'time.updated', requestId: 'playback-1', positionMs: 90, durationMs: 120 });
  assert.equal(snapshot.positionMs, 90);
  assert.equal(snapshot.durationMs, 120);
  assert.equal(renderCount, 1);
  assert.equal(progressRenderCount, 1);

  emitPlayerEvent({ event: 'state.changed', requestId: 'playback-1', snapshot: { ...snapshot, status: 'paused', playing: false } });
  assert.equal(renderCount, 2);
  assert.equal(progressRenderCount, 1);

  subscription.unsubscribe();
  assert.equal(unsubscribed, true);
});

test('player bridge filters request-scoped events, keeps settlement separate, and rejects late init/unsubscribe', async () => {
  const initial = { ...createEmptyPlayerSnapshot(), requestId: 'current', status: 'playing' as const, playing: true };
  let snapshot: PlayerSnapshot = initial;
  let emit = (_event: PlayerEvent): void => undefined;
  const init = createDeferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['getSnapshot']>>>();
  const observedEvents: PlayerEvent[] = [];
  let renders = 0;
  const subscription = subscribePlayerBridge({
    player: {
      onEvent(listener) { emit = listener; return () => undefined; },
      getSnapshot: () => init.promise,
    } as LineupDesktopPreloadApi['player'],
    diagnostics: {
      recordRendererEvent: async () => ({ ok: true, value: undefined }),
    } as unknown as LineupDesktopPreloadApi['diagnostics'],
    getSnapshot: () => snapshot,
    setSnapshot: (next) => { snapshot = next; },
    onEvent: (event) => { observedEvents.push(event); },
    render: () => { renders += 1; },
    renderProgress: () => undefined,
  });

  const pendingInit = subscription.initializeSnapshot();
  emit({ event: 'time.updated', requestId: 'stale', positionMs: 99, durationMs: 100 });
  assert.equal(snapshot.positionMs, 0);
  emit({ event: 'quality.changed', requestId: 'current', quality: { mode: 'direct-play', sourceDynamicRange: 'sdr', outputDynamicRangeStatus: 'sdr' } });
  assert.equal(snapshot.quality.mode, 'direct-play');
  emit({ event: 'command.settled', requestId: 'command-1', command: 'pause', ok: true });
  assert.equal(observedEvents.at(-1)?.event, 'command.settled');
  assert.equal(renders, 1);

  emit({ event: 'state.changed', requestId: 'new', snapshot: { ...initial, requestId: 'new', status: 'paused', playing: false } });
  init.resolve({ ok: true, requestId: 'init', value: { ...initial, status: 'idle', requestId: null } });
  await pendingInit;
  assert.equal(snapshot.status, 'paused');
  subscription.unsubscribe();
  emit({ event: 'state.changed', requestId: 'late', snapshot: { ...initial, requestId: 'late' } });
  assert.equal(snapshot.requestId, 'new');
});

test('guide presentation polling serializes refreshes and settles coalesced work on stop', async () => {
  const requests: Array<Deferred<{ ok: true; value: EpgPresentationSource }>> = [];
  const applied: EpgPresentationSource[] = [];
  const requestedWindows: number[] = [];
  let loadingCount = 0;
  let failureCount = 0;
  let activeRoute: 'player' | 'guide' = 'guide';
  const initialWindowStartMs = 1_778_619_600_000;
  let windowStartMs = initialWindowStartMs;

  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (request: { startTimeMs: number; durationMs: number }) => {
        requestedWindows.push(request.startTimeMs);
        const pendingRequest = createDeferred<{ ok: true; value: EpgPresentationSource }>();
        requests.push(pendingRequest);
        const result = await pendingRequest.promise;
        return { ...result, requestId: `guide-${requests.length}` };
      },
      cancelPresentation: async () => undefined,
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: createNoopIntervalHost(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => windowStartMs,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => {
      loadingCount += 1;
    },
    applyPresentation: (presentation) => {
      applied.push(presentation);
      return true;
    },
    handleFailure: () => {
      failureCount += 1;
    },
  });

  const first = polling.refresh('first', { showLoading: true });
  windowStartMs += 1_800_000;
  const second = polling.refresh('second');
  windowStartMs += 1_800_000;
  const latest = polling.refresh('latest');
  assert.equal(second, latest);
  assert.equal(requests.length, 1);
  assert.equal(loadingCount, 1);

  requests[0]?.resolve({ ok: true, value: { channels: [], nowWatching: null } });
  await first;
  assert.equal(requests.length, 2);
  assert.deepEqual(requestedWindows, [
    initialWindowStartMs - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
    initialWindowStartMs + EPG_SLOT_DURATION_MS * 2 - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
  ]);
  assert.equal(applied.length, 0);

  requests[1]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await Promise.all([second, latest]);
  assert.equal(applied.length, 1);

  const stoppedActive = polling.refresh('stopped-active');
  const stoppedTrailing = polling.refresh('stopped-trailing');
  assert.equal(requests.length, 3);
  polling.stop();
  await Promise.all([stoppedActive, stoppedTrailing]);
  requests[2]?.resolve({ ok: true, value: { channels: [], nowWatching: null } });
  await Promise.resolve();
  assert.equal(applied.length, 1);
  assert.equal(failureCount, 0);

  activeRoute = 'player';
  await polling.refresh('off-route');
  assert.equal(requests.length, 3);
});

test('guide presentation polling applies sustained slow responses while bounding interval work', async () => {
  const requests: Array<Deferred<{ ok: true; value: EpgPresentationSource }>> = [];
  const intervalCallbacks: Array<() => void> = [];
  const appliedGenerations: number[] = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        const request = createDeferred<{ ok: true; value: EpgPresentationSource }>();
        requests.push(request);
        const result = await request.promise;
        return { ...result, requestId: `slow-guide-${requests.length}` };
      },
      cancelPresentation: async () => undefined,
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: {
      setInterval: (callback: TimerHandler) => { intervalCallbacks.push(callback as () => void); return 11; },
      clearInterval: () => undefined,
      setTimeout: () => 12,
      clearTimeout: () => undefined,
    } as unknown as Window,
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 1_778_619_600_000,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => undefined,
    applyPresentation: (_presentation, generation) => { appliedGenerations.push(generation); return true; },
    handleFailure: () => assert.fail('failure callback was not expected'),
  });

  polling.start();
  intervalCallbacks[0]?.();
  intervalCallbacks[0]?.();
  intervalCallbacks[0]?.();
  assert.equal(requests.length, 1);

  requests[0]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await settleAsyncWork();
  assert.equal(requests.length, 2);
  assert.equal(appliedGenerations.length, 1);

  intervalCallbacks[0]?.();
  intervalCallbacks[0]?.();
  assert.equal(requests.length, 2);
  requests[1]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await settleAsyncWork();
  assert.equal(requests.length, 3);
  assert.equal(appliedGenerations.length, 2);
  assert.ok((appliedGenerations[1] ?? 0) > (appliedGenerations[0] ?? 0));

  intervalCallbacks[0]?.();
  assert.equal(requests.length, 3);
  requests[2]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await settleAsyncWork();
  assert.equal(requests.length, 4);
  assert.equal(appliedGenerations.length, 3);
  assert.ok((appliedGenerations[2] ?? 0) > (appliedGenerations[1] ?? 0));

  polling.stop();
  polling.start();
  assert.equal(requests.length, 5);
  requests[3]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await settleAsyncWork();
  assert.equal(appliedGenerations.length, 3);
  requests[4]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await settleAsyncWork();
  assert.equal(appliedGenerations.length, 4);
  polling.stop();
});

test('guide presentation polling times out hung work, starts trailing work, and ignores late results', async () => {
  const requests: Array<Deferred<{ ok: true; value: EpgPresentationSource }>> = [];
  const timeoutCallbacks: Array<() => void> = [];
  const clearedTimeouts: number[] = [];
  const failureMessages: string[] = [];
  let applied = 0;
  let cancellations = 0;
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        const request = createDeferred<{ ok: true; value: EpgPresentationSource }>();
        requests.push(request);
        const result = await request.promise;
        return { ...result, requestId: `timed-guide-${requests.length}` };
      },
      cancelPresentation: async () => { cancellations += 1; },
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: {
      setInterval: () => 1,
      clearInterval: () => undefined,
      setTimeout: (callback: TimerHandler) => {
        timeoutCallbacks.push(callback as () => void);
        return timeoutCallbacks.length;
      },
      clearTimeout: (timeoutId: number) => { clearedTimeouts.push(timeoutId); },
    } as unknown as Window,
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 1_778_619_600_000,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => undefined,
    applyPresentation: () => { applied += 1; return true; },
    handleFailure: (_source, message) => { failureMessages.push(message); },
  });

  const first = polling.refresh('manual');
  const trailing = polling.refresh('poll-interval');
  assert.equal(requests.length, 1);
  assert.equal(timeoutCallbacks.length, 1);

  timeoutCallbacks[0]?.();
  await first;
  assert.equal(cancellations, 1);
  assert.deepEqual(failureMessages, ['Guide refresh timed out. Try again.']);
  assert.deepEqual(clearedTimeouts, [1]);
  assert.equal(requests.length, 2);

  requests[0]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await Promise.resolve();
  assert.equal(applied, 0);

  requests[1]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await trailing;
  assert.equal(applied, 1);
  assert.deepEqual(clearedTimeouts, [1, 2]);
  polling.stop();
});

test('guide polling is Guide-route-only while explicit Player refresh remains available', async () => {
  let activeRoute: 'player' | 'guide' | 'settings' = 'player';
  const intervalCallbacks: Array<() => void> = [];
  let clearCount = 0;
  let loadingCount = 0;
  let playerApplyCount = 0;
  const windows: number[] = [];
  const nowMs = 1_778_619_999_999;
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (request: { startTimeMs: number; durationMs: number }) => {
        windows.push(request.startTimeMs);
        return { ok: true, requestId: `guide-${windows.length}`, value: DEFAULT_EPG_PRESENTATION_SOURCE };
      },
      cancelPresentation: async () => undefined,
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: {
      setInterval: (callback: TimerHandler) => { intervalCallbacks.push(callback as () => void); return 7; },
      clearInterval: () => { clearCount += 1; },
      setTimeout: () => 8,
      clearTimeout: () => undefined,
    } as unknown as Window,
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => 1_700_000_000_000,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    getNowMs: () => nowMs,
    setLoading: () => { loadingCount += 1; },
    applyPresentation: () => true,
    applyPlayerPresentation: () => { playerApplyCount += 1; },
    handleFailure: () => undefined,
  });

  polling.start();
  await settleAsyncWork();
  assert.equal(windows.length, 0, 'idle Player startup issues no Guide request');
  assert.equal(intervalCallbacks.length, 0);
  assert.equal(loadingCount, 0);

  await polling.refresh('player-tune-success', { allowPlayerRoute: true });
  assert.equal(
    windows[0],
    Math.floor(nowMs / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
  );
  assert.equal(loadingCount, 0);
  assert.equal(playerApplyCount, 1);

  activeRoute = 'guide';
  polling.reconcile('player', 'guide');
  await settleAsyncWork();
  assert.equal(windows.at(-1), 1_700_000_000_000 - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs);
  assert.equal(loadingCount, 1);
  assert.equal(intervalCallbacks.length, 1);
  const foregroundRequestCount = windows.length;
  await settleAsyncWork();
  assert.equal(windows.length, foregroundRequestCount, 'accepted foreground work schedules no warm request');
  activeRoute = 'settings';
  polling.reconcile('guide', 'settings');
  assert.equal(clearCount, 1);
});

test('Settings-route past-items settlement makes no request; Guide entry recovers once', async () => {
  let activeRoute: 'guide' | 'settings' = 'guide';
  let requests = 0;
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        requests += 1;
        return { ok: true, requestId: `settlement-${requests}`, value: DEFAULT_EPG_PRESENTATION_SOURCE };
      },
      cancelPresentation: async () => undefined,
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: createNoopIntervalHost(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => 1_778_619_600_000,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => undefined,
    applyPresentation: () => true,
    handleFailure: () => undefined,
  });

  polling.notePastItemsWindowChange();
  polling.notePastItemsWindowChange();
  polling.settlePastItemsWindow({ currentValue: '15', acceptedValue: '15', saving: true });
  await settleAsyncWork();
  assert.equal(requests, 0);
  polling.settlePastItemsWindow({ currentValue: '15', acceptedValue: '15', saving: false });
  await settleAsyncWork();
  assert.equal(requests, 1);
  polling.settlePastItemsWindow({ currentValue: '15', acceptedValue: '15', saving: false });
  await settleAsyncWork();
  assert.equal(requests, 1);

  activeRoute = 'settings';
  polling.notePastItemsWindowChange();
  // Off-route settlement is consumed without a request; ordinary Guide entry owns recovery.
  polling.settlePastItemsWindow({ currentValue: '30', acceptedValue: '30', saving: false });
  await settleAsyncWork();
  assert.equal(requests, 1);
  activeRoute = 'guide';
  polling.reconcile('settings', 'guide');
  await settleAsyncWork();
  assert.equal(requests, 2);
});

test('Settings time-range settlement drives Guide and Player polling through optimistic save and rollback', async () => {
  type Route = 'guide' | 'player' | 'settings';
  const base = 1_783_512_000_000;
  const presentation: EpgPresentationSource = {
    channels: [{
      id: 'channel-1', number: '1', name: 'One', programs: [{
        id: 'program-1', title: 'Program', subtitle: '', description: '', showTitle: '', episodeLabel: '',
        rating: '', quality: [], genres: [], startsAtMs: base, endsAtMs: base + EPG_SLOT_DURATION_MS, artwork: { poster: null, background: null },
      }],
    }],
    nowWatching: null,
    nowMs: base,
    minimumStartTimeMs: base,
  };
  let activeRoute: Route = 'guide';
  let guideTimeRange: 'detailed' | 'wide' = 'detailed';
  const programFocusId = createGuideProgramFocusId('channel-1', 'program-1');
  const focusRegistry = new FocusRegistry();
  focusRegistry.register({ id: programFocusId, route: 'guide', order: 1 });
  let focusState: FocusState = { activeRoute: 'guide', activeId: programFocusId };
  let pendingFocusId: string | null = null;
  let epgState = createEpgState(presentation, 0, guideTimeRange);
  const restoredFocusIds: string[] = [];
  const requests: Array<{ route: Route; durationMs: number; startTimeMs: number }> = [];
  const settlementQueue: Promise<void>[] = [];
  const settlementTrace: string[] = [];
  const states: Array<{
    loading: boolean;
    saving: boolean;
    timeRange: 'detailed' | 'wide';
    errorCode: string | null;
  }> = [];

  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (request: { startTimeMs: number; durationMs: number }) => {
        requests.push({ route: activeRoute, startTimeMs: request.startTimeMs, durationMs: request.durationMs });
        return { ok: true, requestId: `time-range-guide-${String(requests.length)}`, value: presentation };
      },
      cancelPresentation: async () => undefined,
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: createNoopIntervalHost(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => epgState.windowStartMs,
    getGuideTimeRange: () => guideTimeRange,
    getGuidePerformanceProfile: () => 'reduced-resource',
    getNowMs: () => base,
    setLoading: (generation) => {
      epgState = { ...epgState, presentationState: 'loading', presentationGeneration: generation };
    },
    applyPresentation: (value, generation, target, effectiveStartTimeMs) => {
      const capturedFocusId = captureGuideProgramFocusIntent(pendingFocusId, focusState.activeId);
      const settlement = settleEpgPresentation(
        epgState,
        value,
        generation,
        target,
        capturedFocusId !== null,
        guideTimeRange,
        effectiveStartTimeMs,
      );
      epgState = settlement.state;
      if (settlement.pendingFocusId !== undefined) pendingFocusId = settlement.pendingFocusId;
      if (pendingFocusId !== null) {
        restoredFocusIds.push(pendingFocusId);
        pendingFocusId = null;
      }
      return true;
    },
    applyPlayerPresentation: (value, generation, effectiveStartTimeMs) => {
      epgState = settleEpgPresentation(
        epgState,
        value,
        generation,
        null,
        false,
        guideTimeRange,
        effectiveStartTimeMs,
      ).state;
    },
    handleFailure: () => assert.fail('unexpected Guide failure'),
    handlePlayerFailure: () => assert.fail('unexpected Player failure'),
  });
  const guideSettingsSettlementOwner = createSettingsGuideSettingsSettlementOwner({
    getCurrentSettings: () => ({
      guideTimeRange,
      guidePerformanceProfile: 'auto',
      guideRowDensity: 'auto',
      guideLayout: 'classic',
    }),
    getPolling: () => ({
      hasPendingGuideSettingsChange: () => polling.hasPendingGuideSettingsChange(),
      noteGuideSettingsChange: () => {
        settlementTrace.push('note');
        polling.noteGuideSettingsChange();
      },
      settleGuideSettings: (loading) => {
        settlementTrace.push(`settle:${String(loading)}`);
        return polling.settleGuideSettings(loading);
      },
    }),
    retainGuideProgramFocusIntent: () => {
      settlementTrace.push('retain-focus');
      pendingFocusId = captureGuideProgramFocusIntent(pendingFocusId, focusState.activeId);
    },
    restorePendingGuideFocus: () => {
      settlementTrace.push('restore-focus');
      if (pendingFocusId === null || activeRoute !== 'guide') return;
      focusState = focusRegistry.focusTarget(
        { ...focusState, activeRoute: 'guide' },
        pendingFocusId,
      ).state;
      restoredFocusIds.push(focusState.activeId ?? 'missing-focus');
      pendingFocusId = null;
    },
    invalidateViewportLayout: () => undefined,
    reconcileViewport: () => undefined,
  });

  let replacementCount = 0;
  const settings = createSettingsRuntime({
    settings: {
      getAudioOutputs: async ({ requestId }) => desktopSettingsSuccess(requestId, {
        status: 'unavailable',
        reason: 'platform-unsupported',
        outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
      }),
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, settingsSnapshot(1)),
      replace: async (input) => {
        replacementCount += 1;
        if (replacementCount === 2) return desktopSettingsFailure(input.requestId, 'storage-unavailable');
        return desktopSettingsSuccess(input.requestId, settingsSnapshot(
          replacementCount + 1,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: {
      setFullscreen: async (enabled) => ({
        ok: true,
        requestId: `time-range-window-${String(enabled)}`,
        value: { enabled },
      }),
    },
    onStateChanged: (state) => {
      states.push({
        loading: state.loading,
        saving: state.saving,
        timeRange: state.values.guideTimeRange,
        errorCode: state.errorCode,
      });
      const guideSettingsSettlement = guideSettingsSettlementOwner.begin(
        {
          guideTimeRange: state.values.guideTimeRange,
          guidePerformanceProfile: 'auto',
          guideRowDensity: 'auto',
          guideLayout: 'classic',
        },
        () => {
          settlementTrace.push('apply-workflow-values');
          guideTimeRange = state.values.guideTimeRange;
        },
      );
      if (!state.loading) settlementTrace.push('render');
      settlementQueue.push(guideSettingsSettlement.finish(state.loading));
    },
  });
  const settleSettingsCallbacks = async (): Promise<void> => {
    while (settlementQueue.length > 0) {
      const pending = settlementQueue.splice(0);
      await Promise.all(pending);
    }
  };

  await settings.initialize();
  await settleSettingsCallbacks();
  assert.deepEqual(requests, []);
  assert.equal(states[0]?.loading, true);
  assert.equal(states.at(-1)?.loading, false);

  settlementTrace.length = 0;
  await settings.replaceValues((values) => ({ ...values, guideTimeRange: 'wide' }));
  await settleSettingsCallbacks();
  assert.deepEqual(settlementTrace.slice(0, 6), [
    'note',
    'retain-focus',
    'apply-workflow-values',
    'render',
    'restore-focus',
    'settle:false',
  ]);
  await settings.replaceValues((values) => ({ ...values, guideTimeRange: 'detailed' }));
  await settleSettingsCallbacks();
  assert.equal(settings.getState().values.guideTimeRange, 'wide');
  assert.equal(settings.getState().errorCode, 'storage-unavailable');

  activeRoute = 'player';
  focusState = { activeRoute: 'player', activeId: null };
  await settings.replaceValues((values) => ({ ...values, guideTimeRange: 'detailed' }));
  await settleSettingsCallbacks();
  activeRoute = 'settings';
  focusState = { activeRoute: 'settings', activeId: null };
  await settings.replaceValues((values) => ({ ...values, guideTimeRange: 'wide' }));
  await settleSettingsCallbacks();
  assert.equal(requests.length, 4);

  activeRoute = 'guide';
  focusState = { activeRoute: 'guide', activeId: programFocusId };
  polling.reconcile('settings', 'guide');
  await settleAsyncWork();
  polling.stop();

  assert.deepEqual(requests.map(({ route }) => route), ['guide', 'guide', 'guide', 'player', 'guide']);
  const detailedPresentationDurationMs = 2 * 60 * 60_000;
  const widePresentationDurationMs = 3 * 60 * 60_000;
  const preloadBufferEachSideMs = REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    widePresentationDurationMs + preloadBufferEachSideMs * 2,
    detailedPresentationDurationMs + preloadBufferEachSideMs * 2,
    widePresentationDurationMs + preloadBufferEachSideMs * 2,
    detailedPresentationDurationMs + preloadBufferEachSideMs * 2,
    widePresentationDurationMs + preloadBufferEachSideMs * 2,
  ]);
  assert.deepEqual(
    requests.map(({ startTimeMs }) => startTimeMs),
    requests.map(() => base - preloadBufferEachSideMs),
  );
  assert.ok(restoredFocusIds.length > 0, 'Guide time-range settlement restores a retained program focus');
  assert.equal(restoredFocusIds.every((focusId) => focusId === programFocusId), true);
  assert.ok(states.some((state) => state.saving && state.timeRange === 'wide'));
  assert.ok(states.some((state) => state.saving && state.timeRange === 'detailed'));
  assert.ok(states.some((state) => state.errorCode === 'storage-unavailable' && !state.saving));
});

test('Player first result clamps only to a newer bound and otherwise preserves the Guide window before route refresh', async () => {
  const base = 1_778_619_600_000;
  const scenarios = [
    { label: 'clamp', initialWindowStartMs: base - EPG_SLOT_DURATION_MS, programDurationSlots: 1, expectedWindowStartMs: base },
    { label: 'preserve', initialWindowStartMs: base + EPG_SLOT_DURATION_MS, programDurationSlots: 8, expectedWindowStartMs: base + EPG_SLOT_DURATION_MS },
  ] as const;

  for (const scenario of scenarios) {
    const authoritative: EpgPresentationSource & GuidePresentationSource = {
      channels: [{
        id: 'channel-1', number: '1', name: 'One', programs: [{
          id: 'program-1', title: 'Program', subtitle: '', description: '', showTitle: '', episodeLabel: '',
          rating: '', quality: [], genres: [], startsAtMs: base,
          endsAtMs: base + scenario.programDurationSlots * EPG_SLOT_DURATION_MS, artwork: { poster: null, background: null },
        }],
      }],
      nowWatching: null,
      nowMs: base,
      minimumStartTimeMs: base,
      channelWindow: { offset: 0, total: 1 },
      libraryFilter: { scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
    };
    let activeRoute: 'player' | 'guide' = 'player';
    let state = createEpgState({ channels: [], nowWatching: null, nowMs: scenario.initialWindowStartMs }, 0, 'wide');
    const requestStarts: number[] = [];
    const guide = {
      getPresentation: async (request: { startTimeMs: number }) => {
        requestStarts.push(request.startTimeMs);
        return { ok: true, requestId: `player-guide-${scenario.label}-${requestStarts.length}`, value: authoritative };
      },
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    } satisfies LineupDesktopPreloadApi['guide'];
    const polling = createGuidePresentationPolling({
      guide,
      host: createNoopIntervalHost(),
      getActiveRoute: () => activeRoute,
      getWindowStartMs: () => state.windowStartMs,
      getGuideTimeRange: () => state.guideTimeRange,
      getGuidePerformanceProfile: () => 'reduced-resource',
      getNowMs: () => base - EPG_SLOT_DURATION_MS,
      setLoading: (generation) => { state = { ...state, presentationState: 'loading', presentationGeneration: generation }; },
      applyPresentation: (presentation, generation, _target, effectiveStartTimeMs) => {
        state = settleEpgPresentation(state, presentation, generation, _target, false, 'wide', effectiveStartTimeMs).state;
        return true;
      },
      applyPlayerPresentation: (presentation, generation, effectiveStartTimeMs) => {
        state = settleEpgPresentation(state, presentation, generation, null, false, 'wide', effectiveStartTimeMs).state;
      },
      handleFailure: () => undefined,
    });

    await polling.refresh('player-first-result', { allowPlayerRoute: true });
    assert.deepEqual(requestStarts, [base - EPG_SLOT_DURATION_MS - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs], scenario.label);
    assert.equal(state.minimumStartTimeMs, base, scenario.label);
    assert.equal(state.windowStartMs, scenario.expectedWindowStartMs, scenario.label);

    activeRoute = 'guide';
    polling.reconcile('player', 'guide');
    await settleAsyncWork();
    assert.deepEqual(requestStarts, [
      base - EPG_SLOT_DURATION_MS - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
      scenario.expectedWindowStartMs - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
    ], scenario.label);
    assert.equal(state.minimumStartTimeMs, base, scenario.label);
    assert.equal(state.windowStartMs, scenario.expectedWindowStartMs, scenario.label);
    polling.stop();
  }
});

test('shell controller rejects stale capabilities and exposes recoverable safe startup failure', async () => {
  const requests: Array<Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['shell']['getCapabilities']>>>> = [];
  let state = createRendererShellState();
  const focused: string[] = [];
  const controller = createShellController({
    shell: {
      getCapabilities: () => {
        const request = createDeferred<Awaited<ReturnType<LineupDesktopPreloadApi['shell']['getCapabilities']>>>();
        requests.push(request);
        return request.promise;
      },
      onStatusChanged: () => () => undefined,
      onMediaInput: () => () => undefined,
    },
    windowBridge: { setFullscreen: async () => { throw new Error('unused'); } },
    host: { setTimeout: () => 1, clearTimeout: () => undefined },
    getState: () => state,
    setState: (next) => { state = next; },
    render: () => undefined,
    applyCapabilities: () => undefined,
    restoreFocus: (id) => focused.push(id),
  });

  const first = controller.start();
  controller.cleanup();
  requests[0]?.resolve({
    ok: true,
    requestId: 'late',
    value: {
      appName: 'Lineup Desktop',
      appVersion: '1.0.0',
      platform: 'darwin',
      shellMode: 'development',
      protocolOrigin: 'lineup://shell',
    },
  });
  await first;
  assert.equal(state.bootstrap, 'splash');

  let retryState = createRendererShellState();
  const retryController = createShellController({
    shell: {
      getCapabilities: async () => { throw new Error('private bridge detail'); },
      onStatusChanged: () => () => undefined,
      onMediaInput: () => () => undefined,
    },
    windowBridge: { setFullscreen: async () => { throw new Error('unused'); } },
    host: { setTimeout: () => 1, clearTimeout: () => undefined },
    getState: () => retryState,
    setState: (next) => { retryState = next; },
    render: () => undefined,
    applyCapabilities: () => undefined,
    restoreFocus: (id) => focused.push(id),
  });
  await retryController.start();
  assert.equal(retryState.bootstrap, 'error');
  assert.equal(retryState.blockingErrorMessage, 'Lineup could not start.');
  assert.equal(focused.at(-1), 'shell-error-retry');
});

test('shell controller forwards fullscreen focus intent and owns 5000/200/1500 toast timing', async () => {
  let state = createRendererShellState();
  state = { ...state, bootstrap: 'ready' };
  let now = 2000;
  let nextTimer = 1;
  const timers = new Map<number, { callback: () => void; delay: number }>();
  const focused: string[] = [];
  const controller = createShellController({
    shell: {
      getCapabilities: async () => { throw new Error('unused'); },
      onStatusChanged: () => () => undefined,
      onMediaInput: () => () => undefined,
    },
    windowBridge: {
      setFullscreen: async (desired) => ({
        ok: true,
        requestId: `fullscreen-${desired}`,
        value: { enabled: desired },
      }),
    },
    host: {
      setTimeout: (callback, delay) => {
        const id = nextTimer++;
        timers.set(id, { callback, delay });
        return id;
      },
      clearTimeout: (id) => { timers.delete(id); },
    },
    getState: () => state,
    setState: (next) => { state = next; },
    render: () => undefined,
    applyCapabilities: () => undefined,
    restoreFocus: (id) => focused.push(id),
    nowMs: () => now,
  });

  await controller.requestFullscreen(true, 'overlay-osd-audio');
  assert.equal(focused.at(-1), 'overlay-osd-audio');
  assert.equal(state.toast?.message, 'Entered fullscreen');
  assert.deepEqual([...timers.values()].map((timer) => timer.delay), [5000]);
  const visibleTimer = [...timers.entries()][0];
  if (visibleTimer) timers.delete(visibleTimer[0]);
  visibleTimer?.[1].callback();
  assert.equal(state.toast?.phase, 'fading');
  assert.deepEqual([...timers.values()].map((timer) => timer.delay), [200]);

  now = 2500;
  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.equal(state.toast?.message, 'Exited fullscreen');
  assert.deepEqual([...timers.values()].map((timer) => timer.delay), [5000]);
  const oppositeTransitionTimerId = [...timers.keys()][0];
  now = 3000;
  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.deepEqual([...timers.values()].map((timer) => timer.delay), [5000]);
  assert.equal([...timers.keys()][0], oppositeTransitionTimerId);
  now = 4000;
  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.deepEqual([...timers.values()].map((timer) => timer.delay), [5000]);
  assert.notEqual([...timers.keys()][0], oppositeTransitionTimerId);
});

test('fullscreen transport preserves a live visible overlay focus target through entry and exit', async () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const owner = { hidden: false, ariaHidden: 'false', dataset: { overlay: 'playerOsd' } };
  const control = new FullscreenOverlayFocusElement('overlay-osd-audio', owner);
  const documentDouble = {
    activeElement: null as FullscreenOverlayFocusElement | null,
    querySelectorAll: () => [control],
  };
  Object.defineProperty(globalThis, 'document', { value: documentDouble, configurable: true });
  try {
    const dom = createFullscreenFocusDom(control);
    const registry = new FocusRegistry();
    syncRendererFocusTargets(registry, dom);
    let focusState: FocusState = { activeRoute: 'player', activeId: null };
    const restoreFocus = (focusId: string): void => {
      syncRendererFocusTargets(registry, dom);
      focusState = registry.focusTarget(focusState, focusId).state;
      renderRendererFocus(focusState, dom);
    };
    restoreFocus(control.dataset.focusId ?? '');
    const acceptedFocusId = focusState.activeId;
    assert.equal(acceptedFocusId, 'overlay-osd-audio');
    assert.equal(owner.hidden, false);
    assert.equal(owner.ariaHidden, 'false');
    assert.equal(control.closest('[data-overlay]'), owner);
    assert.equal(documentDouble.activeElement, control);

    const reconciled: boolean[] = [];
    const transport = createFullscreenTransportCoordinator({
      bridge: {
        setFullscreen: async (desired) => {
          documentDouble.activeElement = null;
          control.tabIndex = -1;
          return { ok: true, requestId: `fullscreen-${String(desired)}`, value: { enabled: desired } };
        },
      },
      reconcile: (enabled) => { reconciled.push(enabled); },
    });
    let shellState: RendererShellState = { ...createRendererShellState(), bootstrap: 'ready' };
    const controller = createShellController({
      shell: {
        getCapabilities: async () => { throw new Error('unused'); },
        onStatusChanged: () => () => undefined,
        onMediaInput: () => () => undefined,
      },
      windowBridge: transport,
      host: { setTimeout: () => 1, clearTimeout: () => undefined },
      getState: () => shellState,
      setState: (next) => { shellState = next; },
      render: () => undefined,
      applyCapabilities: () => undefined,
      restoreFocus,
    });

    await controller.requestFullscreen(true, acceptedFocusId ?? '');
    assert.equal(focusState.activeId, 'overlay-osd-audio');
    assert.equal(documentDouble.activeElement, control);
    assert.equal(control.tabIndex, 0);
    await controller.requestFullscreen(false, acceptedFocusId ?? '');
    assert.equal(focusState.activeId, 'overlay-osd-audio');
    assert.equal(documentDouble.activeElement, control);
    assert.equal(control.tabIndex, 0);
    assert.deepEqual(reconciled, [true, false]);
    assert.equal(control.focusCount, 3);
  } finally {
    if (originalDocument === undefined) Reflect.deleteProperty(globalThis, 'document');
    else Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
  }
});

test('shell fullscreen mutex survives UI invalidation until transport settlement', async () => {
  const first = createDeferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  let state: RendererShellState = { ...createRendererShellState(), bootstrap: 'ready' };
  let calls = 0;
  const controller = createShellController({
    shell: {
      getCapabilities: async () => { throw new Error('unused'); },
      onStatusChanged: () => () => undefined,
      onMediaInput: () => () => undefined,
    },
    windowBridge: {
      setFullscreen: async (desired) => {
        calls += 1;
        if (calls === 1) return first.promise;
        return { ok: true, requestId: `fullscreen-${calls}`, value: { enabled: desired } };
      },
    },
    host: { setTimeout: () => 1, clearTimeout: () => undefined },
    getState: () => state,
    setState: (next) => { state = next; },
    render: () => undefined,
    applyCapabilities: () => undefined,
    restoreFocus: () => undefined,
  });

  const pending = controller.requestFullscreen(true, 'player-fullscreen');
  controller.invalidateFullscreenRequest();
  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.equal(calls, 1);
  first.resolve({ ok: true, requestId: 'fullscreen-1', value: { enabled: true } });
  await pending;
  assert.equal(state.fullscreenPending, false);

  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.equal(calls, 2);
});

test('fullscreen retry keeps inline owner pending and restores retry focus after rejection', async () => {
  const request = createDeferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  let calls = 0;
  let state: RendererShellState = {
    ...createRendererShellState(),
    bootstrap: 'ready' as const,
    inlineError: { desiredFullscreen: true, message: 'Try the fullscreen action again.' },
  };
  const focused: string[] = [];
  const controller = createShellController({
    shell: {
      getCapabilities: async () => { throw new Error('unused'); },
      onStatusChanged: () => () => undefined,
      onMediaInput: () => () => undefined,
    },
    windowBridge: {
      setFullscreen: () => {
        calls += 1;
        return request.promise;
      },
    },
    host: { setTimeout: () => 1, clearTimeout: () => undefined },
    getState: () => state,
    setState: (next) => { state = next; },
    render: () => undefined,
    applyCapabilities: () => undefined,
    restoreFocus: (id) => focused.push(id),
  });

  const retry = controller.retryFullscreen();
  const duplicate = controller.retryFullscreen();
  assert.equal(calls, 1);
  assert.equal(state.fullscreenPending, true);
  assert.equal(state.inlineError?.desiredFullscreen, true);
  await duplicate;

  request.resolve({
    ok: false,
    requestId: 'fullscreen-retry-failed',
    error: { code: 'operation-failed', message: 'private detail must not render' },
  });
  await retry;
  assert.equal(state.fullscreenPending, false);
  assert.equal(state.inlineError?.message, 'Try the fullscreen action again.');
  assert.equal(focused.at(-1), 'shell-inline-retry');
});

test('Plex runtime action dispatch preserves source cleanup ownership', async () => {
  const calls: string[] = [];
  const controller = createPlexControllerStub(calls);
  const options = {
    controller,
    clearSourceActionState: () => calls.push('clearSourceActionState'),
  };

  await dispatchPlexRuntimeAction('clearSelectedServer', options);
  await dispatchPlexRuntimeAction('restoreSelectedServer', options);
  await dispatchPlexRuntimeAction('clearMetadata', options);

  assert.deepEqual(calls, [
    'clearSourceActionState',
    'clearSelectedServer',
    'clearSourceActionState',
    'restoreSelectedServer',
    'clearMetadata',
  ]);
});

interface Deferred<TValue> {
  promise: Promise<TValue>;
  resolve(value: TValue): void;
}

function createDeferred<TValue>(): Deferred<TValue> {
  let resolve!: (value: TValue) => void;
  const promise = new Promise<TValue>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise, resolve };
}

function settleAsyncWork(): Promise<void> {
  return new Promise((resolve) => globalThis.setTimeout(resolve, 0));
}

function createNoopIntervalHost(): Window {
  return {
    setInterval: () => 1,
    clearInterval: () => undefined,
    setTimeout: () => 2,
    clearTimeout: () => undefined,
  } as unknown as Window;
}

function settingsSnapshot(
  revision: number,
  values: typeof DEFAULT_DESKTOP_SETTINGS_VALUES = DEFAULT_DESKTOP_SETTINGS_VALUES,
) {
  return createDesktopSettingsView({
    schemaVersion: 3,
    revision,
    status: 'ready',
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, ...values },
  });
}

class FullscreenOverlayFocusElement {
  tabIndex = -1;
  disabled = false;
  focusCount = 0;
  className = '';
  readonly dataset: Record<string, string>;
  readonly classList = {
    toggle: (name: string, enabled: boolean): void => {
      const names = new Set(this.className.split(' ').filter(Boolean));
      if (enabled) names.add(name);
      else names.delete(name);
      this.className = [...names].join(' ');
    },
  };

  constructor(
    focusId: string,
    private readonly owner: { hidden: boolean; ariaHidden: string; dataset: { overlay: string } },
  ) {
    this.dataset = { focusId };
  }

  closest(selector: string): object | null {
    if (selector === '.profile-pin-modal') return null;
    if (selector === '[data-screen]') return { dataset: { screen: 'player' } };
    if (selector === '[data-overlay]') return this.owner;
    if (selector.includes('[hidden]')) return this.owner.hidden || this.owner.ariaHidden === 'true' ? {} : null;
    return null;
  }

  getAttribute(name: string): string | null {
    return name === 'aria-disabled' ? 'false' : null;
  }

  focus(): void {
    this.focusCount += 1;
    (Reflect.get(globalThis, 'document') as { activeElement: FullscreenOverlayFocusElement | null }).activeElement = this;
  }
}

function createFullscreenFocusDom(control: FullscreenOverlayFocusElement): RendererDomBindings {
  return {
    fullscreenButton: null,
    routeActionButtons: [],
    epgActionButtons: [],
    settingsActionButtons: [],
    setupActionButtons: [],
    plexActionButtons: [],
    channelCommitButtons: [],
    focusableElements: [control as unknown as HTMLElement],
    overlayActionButtons: [control as unknown as HTMLButtonElement],
  } as unknown as RendererDomBindings;
}

function createPlexControllerStub(calls: string[]): PlexRuntimeController {
  const record = (name: string) => {
    calls.push(name);
  };
  const recordAsync = async (name: string) => {
    calls.push(name);
  };
  return {
    getState: () => {
      throw new Error('not used');
    },
    setSearchQuery: (query) => record(`setSearchQuery:${query}`),
    setHomeUserPin: (pin) => record(`setHomeUserPin:${pin}`),
    setSelectedSection: (sectionId) => record(`setSelectedSection:${sectionId}`),
    clearMetadata: () => record('clearMetadata'),
    clearSearch: () => record('clearSearch'),
    clearItems: () => record('clearItems'),
    clearSelectedSection: () => record('clearSelectedSection'),
    clearSelectedServer: () => record('clearSelectedServer'),
    clearPinSubflow: () => recordAsync('clearPinSubflow'),
    dismissPinError: () => recordAsync('dismissPinError'),
    invalidateProfileSwitch: () => record('invalidateProfileSwitch'),
    invalidateOnboardingOperations: () => record('invalidateOnboardingOperations'),
    handleBack: async () => false,
    loadSnapshot: () => recordAsync('loadSnapshot'),
    requestPin: () => recordAsync('requestPin'),
    pollPin: () => recordAsync('pollPin'),
    cancelPin: () => recordAsync('cancelPin'),
    getHomeUsers: () => recordAsync('getHomeUsers'),
    switchHomeUser: (userId) => recordAsync(`switchHomeUser:${userId}`),
    restoreSelectedServer: () => recordAsync('restoreSelectedServer'),
    refreshServers: () => recordAsync('refreshServers'),
    selectServer: (serverId) => recordAsync(`selectServer:${serverId}`),
    listLibrarySections: () => recordAsync('listLibrarySections'),
    listLibraryItems: (sectionId) => recordAsync(`listLibraryItems:${sectionId ?? ''}`),
    searchLibrary: () => recordAsync('searchLibrary'),
    getMetadata: (ratingKey) => recordAsync(`getMetadata:${ratingKey}`),
    cleanup: () => recordAsync('cleanup'),
  };
}
