import test from 'node:test';
import assert from 'node:assert/strict';

import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import type { PlayerEvent, PlayerSnapshot } from '../../contracts/player.js';
import { DEFAULT_EPG_PRESENTATION_SOURCE, type EpgPresentationSource } from '../../renderer/epg.js';
import { createRendererPresentationFixtures } from '../../renderer/presentationFixtures.js';
import { createGuidePresentationPolling } from '../../renderer/guidePresentationPolling.js';
import { dispatchPlexRuntimeAction } from '../../renderer/plexRuntimeActionDispatch.js';
import { subscribePlayerBridge } from '../../renderer/playerBridgeSubscription.js';
import type { PlexRuntimeController } from '../../renderer/plexRuntimeActions.js';
import { createShellController } from '../../renderer/shell/shellController.js';
import { createRendererShellState, type RendererShellState } from '../../renderer/shell/shellState.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';

test('player bridge subscription owns event projection and unsubscribe cleanup', async () => {
  const fixtures = createRendererPresentationFixtures();
  let snapshot = fixtures.playerSnapshot;
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
            ...fixtures.playerSnapshot,
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

  emitPlayerEvent({ event: 'time.updated', requestId: 'time-update', positionMs: 90, durationMs: 120 });
  assert.equal(snapshot.positionMs, 90);
  assert.equal(snapshot.durationMs, 120);
  assert.equal(renderCount, 2);

  subscription.unsubscribe();
  assert.equal(unsubscribed, true);
});

test('guide presentation polling ignores stale and stopped refreshes', async () => {
  const requests: Array<Deferred<{ ok: true; value: EpgPresentationSource }>> = [];
  const applied: EpgPresentationSource[] = [];
  let loadingCount = 0;
  let failureCount = 0;
  let activeRoute: 'player' | 'guide' = 'guide';

  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        const request = createDeferred<{ ok: true; value: EpgPresentationSource }>();
        requests.push(request);
        const result = await request.promise;
        return { ...result, requestId: `guide-${requests.length}` };
      },
    } as unknown as LineupDesktopPreloadApi['guide'],
    host: createNoopIntervalHost(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => 1778619600000,
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
  const second = polling.refresh('second');
  assert.equal(requests.length, 2);
  assert.equal(loadingCount, 1);

  requests[1]?.resolve({ ok: true, value: DEFAULT_EPG_PRESENTATION_SOURCE });
  await second;
  assert.equal(applied.length, 1);

  requests[0]?.resolve({ ok: true, value: { channels: [], nowWatching: null } });
  await first;
  assert.equal(applied.length, 1);

  const stopped = polling.refresh('stopped');
  polling.stop();
  requests[2]?.resolve({ ok: true, value: { channels: [], nowWatching: null } });
  await stopped;
  assert.equal(applied.length, 1);
  assert.equal(failureCount, 0);

  activeRoute = 'player';
  await polling.refresh('off-route');
  assert.equal(requests.length, 3);
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
    applyFullscreen: () => undefined,
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
    applyFullscreen: () => undefined,
    restoreFocus: (id) => focused.push(id),
  });
  await retryController.start();
  assert.equal(retryState.bootstrap, 'error');
  assert.equal(retryState.blockingErrorMessage, 'Lineup could not start.');
  assert.equal(focused.at(-1), 'shell-error-retry');
});

test('shell controller preserves fullscreen focus and owns 5000/200/1500 toast timing', async () => {
  let state = createRendererShellState();
  state = { ...state, bootstrap: 'ready' };
  let enabled = false;
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
    applyFullscreen: (next) => { enabled = next; },
    restoreFocus: (id) => focused.push(id),
    nowMs: () => now,
  });

  await controller.requestFullscreen(true, 'player-osd');
  assert.equal(enabled, true);
  assert.equal(focused.at(-1), 'player-osd');
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

test('fullscreen transport stays serialized across UI invalidation and reconciles a valid late result', async () => {
  const first = createDeferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  let state: RendererShellState = { ...createRendererShellState(), bootstrap: 'ready' };
  const applied: boolean[] = [];
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
    applyFullscreen: (enabled) => applied.push(enabled),
    restoreFocus: () => undefined,
  });

  const pending = controller.requestFullscreen(true, 'player-fullscreen');
  controller.invalidateFullscreenRequest();
  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.equal(calls, 1);
  first.resolve({ ok: true, requestId: 'fullscreen-1', value: { enabled: true } });
  await pending;
  assert.deepEqual(applied, [true]);
  assert.equal(state.fullscreenPending, false);

  await controller.requestFullscreen(false, 'player-fullscreen');
  assert.equal(calls, 2);
  assert.deepEqual(applied, [true, false]);
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
    applyFullscreen: () => undefined,
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

test('shell splash and loading reserve both exact production brand assets', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);
  for (const surface of ['splash', 'loading'] as const) {
    const markup = shellSurfaceMarkup(root.innerHTML, surface);
    assert.equal(markup.match(/src="\.\/assets\/lineup-logo-mark\.png"/gu)?.length, 1, surface);
    assert.equal(markup.match(/src="\.\/assets\/lineup-wordmark\.png"/gu)?.length, 1, surface);
  }
  assert.doesNotMatch(root.innerHTML, /shell-brand-mark|LINE<span>U<\/span>P/u);
});

function shellSurfaceMarkup(markup: string, surface: string): string {
  const marker = `data-shell-surface="${surface}"`;
  const start = markup.indexOf(marker);
  assert.notEqual(start, -1, `missing shell surface ${surface}`);
  const next = markup.indexOf('data-shell-surface="', start + marker.length);
  return markup.slice(start, next === -1 ? markup.length : next);
}

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

function createNoopIntervalHost(): Window {
  return {
    setInterval: () => 1,
    clearInterval: () => undefined,
  } as unknown as Window;
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
