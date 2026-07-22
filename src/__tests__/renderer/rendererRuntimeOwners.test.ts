import test from 'node:test';
import assert from 'node:assert/strict';

import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import type { PlayerEvent, PlayerSnapshot } from '../../contracts/player.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { DEFAULT_EPG_PRESENTATION_SOURCE, type EpgPresentationSource } from '../../renderer/epg.js';
import { renderRendererFocus, syncRendererFocusTargets } from '../../renderer/focusDom.js';
import { createFullscreenTransportCoordinator } from '../../renderer/fullscreenTransport.js';
import { createEmptyPlayerSnapshot } from '../../renderer/playerOverlayPresentation.js';
import { createGuidePresentationPolling } from '../../renderer/guidePresentationPolling.js';
import { FocusRegistry, type FocusState } from '../../renderer/navigation.js';
import { dispatchPlexRuntimeAction } from '../../renderer/plexRuntimeActionDispatch.js';
import { subscribePlayerBridge } from '../../renderer/playerBridgeSubscription.js';
import type { PlexRuntimeController } from '../../renderer/plexRuntimeActions.js';
import { createShellController } from '../../renderer/shell/shellController.js';
import { createRendererShellState, type RendererShellState } from '../../renderer/shell/shellState.js';

test('player bridge subscription owns event projection and unsubscribe cleanup', async () => {
  const initialSnapshot = { ...createEmptyPlayerSnapshot(), requestId: 'playback-1', status: 'playing' as const, playing: true };
  let snapshot: PlayerSnapshot = initialSnapshot;
  let renderCount = 0;
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
  });

  await subscription.initializeSnapshot();
  assert.equal(snapshot.positionMs, 42);
  assert.equal(renderCount, 1);

  emitPlayerEvent({ event: 'time.updated', requestId: 'playback-1', positionMs: 90, durationMs: 120 });
  assert.equal(snapshot.positionMs, 90);
  assert.equal(snapshot.durationMs, 120);
  assert.equal(renderCount, 2);

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
  let windowStartMs = 1_778_619_600_000;

  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (request: { startTimeMs: number; durationMs: number }) => {
        requestedWindows.push(request.startTimeMs);
        const pendingRequest = createDeferred<{ ok: true; value: EpgPresentationSource }>();
        requests.push(pendingRequest);
        const result = await pendingRequest.promise;
        return { ...result, requestId: `guide-${requests.length}` };
      },
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: createNoopIntervalHost(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => windowStartMs,
    setLoading: () => {
      loadingCount += 1;
    },
    applyPresentation: (presentation) => {
      applied.push(presentation);
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
  assert.deepEqual(requestedWindows, [1_778_619_600_000, 1_778_623_200_000]);
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
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: {
      setInterval: (callback: TimerHandler) => { intervalCallbacks.push(callback as () => void); return 11; },
      clearInterval: () => undefined,
      setTimeout: () => 12,
      clearTimeout: () => undefined,
    } as unknown as Window,
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 1_778_619_600_000,
    setLoading: () => undefined,
    applyPresentation: (_presentation, generation) => { appliedGenerations.push(generation); },
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
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        const request = createDeferred<{ ok: true; value: EpgPresentationSource }>();
        requests.push(request);
        const result = await request.promise;
        return { ...result, requestId: `timed-guide-${requests.length}` };
      },
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
    setLoading: () => undefined,
    applyPresentation: () => { applied += 1; },
    handleFailure: (_source, message) => { failureMessages.push(message); },
  });

  const first = polling.refresh('manual');
  const trailing = polling.refresh('poll-interval');
  assert.equal(requests.length, 1);
  assert.equal(timeoutCallbacks.length, 1);

  timeoutCallbacks[0]?.();
  await first;
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

test('guide presentation polling schedules Player and Guide with route-owned windows and cleanup', async () => {
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
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: {
      setInterval: (callback: TimerHandler) => { intervalCallbacks.push(callback as () => void); return 7; },
      clearInterval: () => { clearCount += 1; },
      setTimeout: () => 8,
      clearTimeout: () => undefined,
    } as unknown as Window,
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => 1_700_000_000_000,
    getNowMs: () => nowMs,
    setLoading: () => { loadingCount += 1; },
    applyPresentation: () => undefined,
    applyPlayerPresentation: () => { playerApplyCount += 1; },
    handleFailure: () => undefined,
  });

  polling.start();
  await settleAsyncWork();
  assert.equal(windows[0], Math.floor(nowMs / 1_800_000) * 1_800_000);
  assert.equal(loadingCount, 0);
  assert.equal(playerApplyCount, 1);
  intervalCallbacks[0]?.();
  await settleAsyncWork();
  assert.equal(windows.length, 2);

  activeRoute = 'guide';
  polling.reconcile('player', 'guide');
  await settleAsyncWork();
  assert.equal(windows.at(-1), 1_700_000_000_000);
  assert.equal(loadingCount, 1);
  activeRoute = 'settings';
  polling.reconcile('guide', 'settings');
  assert.equal(clearCount, 2);
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
      shell: { getCapabilities: async () => { throw new Error('unused'); }, onStatusChanged: () => () => undefined },
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
    shell: { getCapabilities: async () => { throw new Error('unused'); }, onStatusChanged: () => () => undefined },
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
