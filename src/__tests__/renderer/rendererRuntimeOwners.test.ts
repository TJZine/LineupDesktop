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

  requests[0]?.resolve({ ok: true, value: { channels: [], nowWatching: null, nowMs: 0 } });
  await first;
  assert.equal(applied.length, 1);

  const stopped = polling.refresh('stopped');
  polling.stop();
  requests[2]?.resolve({ ok: true, value: { channels: [], nowWatching: null, nowMs: 0 } });
  await stopped;
  assert.equal(applied.length, 1);
  assert.equal(failureCount, 0);

  activeRoute = 'player';
  await polling.refresh('off-route');
  assert.equal(requests.length, 3);
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
