import assert from 'node:assert/strict';
import test from 'node:test';
import {
  EPG_DETAILED_WINDOW_DURATION_MS,
  EPG_WINDOW_DURATION_MS,
  type EpgGuideDensity,
} from '../../renderer/epg.js';
import { createGuidePresentationPolling } from '../../renderer/guidePresentationPolling.js';
import { createGuideDensityRefreshLatch } from '../../renderer/guideDensityRefresh.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { DEFAULT_GUIDE_PRELOAD_PROFILE } from '../../renderer/guideVirtualization.js';

const bufferedDuration = (durationMs: number): number => durationMs + DEFAULT_GUIDE_PRELOAD_PROFILE.timeBufferMs * 2;

interface Deferred<T> {
  promise: Promise<T>;
  resolve(value: T): void;
}

function deferred<T>(): Deferred<T> {
  let resolvePromise: (value: T) => void = () => undefined;
  const promise = new Promise<T>((resolve) => {
    resolvePromise = resolve;
  });
  return { promise, resolve: resolvePromise };
}

function host(): Window {
  return {
    setTimeout: (callback: TimerHandler, delay?: number) => globalThis.setTimeout(callback, delay) as unknown as number,
    clearTimeout: (handle: number) => globalThis.clearTimeout(handle),
  } as unknown as Window;
}

function idleHost(idle: Array<() => void>): Window {
  return {
    ...host(),
    requestIdleCallback: (callback: IdleRequestCallback) => {
      idle.push(() => callback({ didTimeout: false, timeRemaining: () => 50 }));
      return idle.length;
    },
    cancelIdleCallback: () => undefined,
  } as unknown as Window;
}

async function tick(): Promise<void> {
  await new Promise((resolve) => globalThis.setTimeout(resolve, 0));
}

function result(requestId: string): Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>> {
  return {
    ok: true,
    requestId,
    value: {
      channels: [],
      nowWatching: null,
      minimumStartTimeMs: 0,
      channelWindow: { offset: 0, total: 0 },
      libraryFilter: {
        scopeToken: 'scope',
        revision: 0,
        libraries: [],
        selectedLibraryId: null,
        persistenceStatus: 'ready',
      },
    },
  };
}

function createOptions(
  guide: LineupDesktopPreloadApi['guide'],
  getGuideDensity: () => EpgGuideDensity,
  applyPresentation: () => void,
) {
  return {
    guide,
    host: host(),
    getActiveRoute: () => 'guide' as const,
    getWindowStartMs: () => 0,
    getGuideDensity,
    setLoading: () => undefined,
    applyPresentation: () => applyPresentation(),
    handleFailure: () => undefined,
  };
}

test('Guide polling requests exactly the density duration', async () => {
  let density: EpgGuideDensity = 'comfortable';
  const durations: number[] = [];
  const guide = {
    getPresentation: async (input: { durationMs: number; startTimeMs: number }) => {
      durations.push(input.durationMs);
      return result(`request-${String(durations.length)}`);
    },
  } as unknown as LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => density,
    () => undefined,
  ));

  await polling.refresh('density-comfortable');
  density = 'compact';
  await polling.refresh('density-compact');
  assert.deepEqual(durations, [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS), bufferedDuration(EPG_WINDOW_DURATION_MS)]);
});

test('Desktop preload profiles use exact row/time bounds and aggressive idle warming starts with the next channel page', async () => {
  const windowStartMs = 10 * 60 * 60_000;
  for (const [aggressive, expected] of [
    [false, { startTimeMs: windowStartMs - 120 * 60_000, durationMs: EPG_WINDOW_DURATION_MS + 240 * 60_000, channelLimit: 12 }],
    [true, { startTimeMs: windowStartMs - 360 * 60_000, durationMs: EPG_WINDOW_DURATION_MS + 720 * 60_000, channelLimit: 24 }],
  ] as const) {
    const requests: Array<{ startTimeMs: number; durationMs: number; channelOffset?: number; channelLimit?: number }> = [];
    const idle: Array<() => void> = [];
    const controller = createGuidePresentationPolling({
      guide: {
        getPresentation: async (input) => {
          requests.push(input);
          const response = result(`profile-${String(requests.length)}`);
          if (!response.ok) throw new Error('Expected Guide profile fixture success.');
          return { ...response, value: { ...response.value, channelWindow: { offset: input.channelOffset ?? 0, total: 300 } } };
        },
        setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
      },
      host: {
        setTimeout: (callback: TimerHandler, delay?: number) => globalThis.setTimeout(callback, delay) as unknown as number,
        clearTimeout: (handle: number) => globalThis.clearTimeout(handle),
        requestIdleCallback: (callback: IdleRequestCallback) => { idle.push(() => callback({ didTimeout: false, timeRemaining: () => 50 })); return idle.length; },
        cancelIdleCallback: () => undefined,
      } as unknown as Window,
      getActiveRoute: () => 'guide', getWindowStartMs: () => windowStartMs,
      getGuideDensity: () => 'compact', getAggressivePreloadEnabled: () => aggressive,
      setLoading: () => undefined, applyPresentation: () => undefined, handleFailure: () => undefined,
    });
    await controller.refresh('profile-proof');
    assert.deepEqual(requests[0], { ...expected, channelOffset: 0 });
    if (aggressive) {
      assert.equal(idle.length, 1);
      idle.shift()?.();
      await new Promise((resolve) => globalThis.setTimeout(resolve, 0));
      assert.equal(requests[1]?.channelOffset, 24);
      assert.equal(requests.length, 2);
    } else {
      assert.equal(idle.length, 0);
    }
    controller.stop();
  }
});

test('aggressive page and adjacent-time warm entries are consumed without another bridge request', async () => {
  let windowStartMs = 10 * 60 * 60_000;
  const idle: Array<() => void> = [];
  const requests: Array<{ startTimeMs: number; channelOffset?: number }> = [];
  let applied = 0;
  let channelOffset = 0;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async (input) => {
        requests.push(input);
        const response = result(`warm-${String(requests.length)}`);
        if (!response.ok) throw new Error('Expected warm cache fixture success.');
        return { ...response, value: { ...response.value, channelWindow: { offset: input.channelOffset ?? 0, total: 300 } } };
      },
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle),
    getActiveRoute: () => 'guide', getWindowStartMs: () => windowStartMs,
    getChannelOffset: () => channelOffset,
    getGuideDensity: () => 'compact', getAggressivePreloadEnabled: () => true,
    getCacheIdentity: () => 'identity', getCacheScopeToken: () => 'scope',
    setLoading: () => undefined, applyPresentation: (presentation) => {
      applied += 1;
      channelOffset = presentation.channelWindow?.offset ?? channelOffset;
    }, handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests.length, 1);
  idle.shift()?.();
  await tick();
  assert.equal(requests[1]?.channelOffset, 24);

  const beforePage = requests.length;
  await controller.requestPage({ targetGlobalIndex: 24, sourceLocalIndex: 0, scopeToken: 'scope', channelOffset: 24 });
  assert.equal(requests.length, beforePage, 'warmed page is applied from cache');

  idle.shift()?.();
  await tick();
  assert.equal(requests.at(-1)?.channelOffset, 48, 'cache-hit page reprioritizes the next adjacent page');
  idle.shift()?.();
  await tick();
  assert.equal(requests.at(-1)?.channelOffset, 0, 'cache-hit page then warms the previous adjacent page');
  idle.shift()?.();
  await tick();
  assert.equal(requests.at(-1)?.channelOffset, 24);
  assert.equal(requests.at(-1)?.startTimeMs, windowStartMs + EPG_WINDOW_DURATION_MS / 6 - 360 * 60_000);
  const beforeWindow = requests.length;
  windowStartMs += EPG_WINDOW_DURATION_MS / 6;
  await controller.refresh('epg-window-change');
  assert.equal(requests.length, beforeWindow, 'warmed adjacent time window is applied from cache');
  assert.equal(applied, 3);
  controller.stop();
});

test('past-window and trusted identity changes invalidate cached presentations before lookup', async () => {
  let identity = 'scope:rev1:past-auto:compact:default';
  let requests = 0;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => result(`identity-${String(++requests)}`),
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0,
    getGuideDensity: () => 'compact', getCacheIdentity: () => identity, getCacheScopeToken: () => 'scope',
    setLoading: () => undefined, applyPresentation: () => undefined, handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests, 1);
  controller.notePastItemsWindowChange();
  await controller.refresh('epg-window-change');
  assert.equal(requests, 2, 'past-window notification clears a same-window cached page immediately');

  identity = 'scope:rev2:past-30:compact:default';
  await controller.refresh('epg-window-change');
  assert.equal(requests, 3, 'a changed trusted identity cannot read the previous identity key');
  controller.stop();
});

test('a scheduled idle warm cannot displace foreground active and trailing intent', async () => {
  const idle: Array<() => void> = [];
  const requests: Array<{
    input: { channelOffset?: number };
    pending: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>;
  }> = [];
  let immediate = true;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: (input) => {
        if (immediate) {
          immediate = false;
          const response = result('initial');
          if (!response.ok) throw new Error('Expected initial result.');
          return Promise.resolve({ ...response, value: { ...response.value, channelWindow: { offset: 0, total: 300 } } });
        }
        const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
        requests.push({ input, pending });
        return pending.promise;
      },
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle), getActiveRoute: () => 'guide', getWindowStartMs: () => 0,
    getGuideDensity: () => 'compact', getAggressivePreloadEnabled: () => true,
    getCacheIdentity: () => 'identity', getCacheScopeToken: () => 'scope',
    setLoading: () => undefined, applyPresentation: () => undefined, handleFailure: () => undefined,
  });

  await controller.refresh('initial');
  assert.equal(idle.length, 1);
  const active = controller.refresh('ordinary-active');
  const trailing = controller.refresh('ordinary-trailing');
  assert.equal(requests.length, 1);
  idle.shift()?.();
  await Promise.resolve();
  assert.equal(requests.length, 1, 'stale idle callback does not enqueue or overwrite foreground work');
  requests[0]?.pending.resolve(result('active'));
  await tick();
  assert.equal(requests.length, 2);
  assert.equal(requests[1]?.input.channelOffset ?? 0, 0, 'ordinary trailing intent starts before any warm page');
  requests[1]?.pending.resolve(result('trailing'));
  await Promise.all([active, trailing]);
  controller.stop();
});

test('startup density change during loading latches one Wide refetch after stale Detailed work', async () => {
  let density: EpgGuideDensity = 'comfortable';
  const requests: Array<{ durationMs: number; deferred: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>> }> = [];
  let applied = 0;
  const guide = {
    getPresentation: (input: { durationMs: number; startTimeMs: number }) => {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
      requests.push({ durationMs: input.durationMs, deferred: pending });
      return pending.promise;
    },
  } as unknown as LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => density,
    () => { applied += 1; },
  ));
  const densityRefreshLatch = createGuideDensityRefreshLatch();

  const initial = polling.refresh('poll-start');
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS)]);
  density = 'compact';
  densityRefreshLatch.noteChange();
  assert.equal(densityRefreshLatch.consume(true, 'guide'), false);
  assert.equal(densityRefreshLatch.hasPending(), true);

  assert.equal(densityRefreshLatch.consume(false, 'guide'), true);
  const latest = polling.refresh('guide-density-change');
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS)]);
  requests[0]?.deferred.resolve(result('stale-detailed'));
  await initial;
  assert.equal(applied, 0);
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS),
    bufferedDuration(EPG_WINDOW_DURATION_MS),
  ]);
  requests[1]?.deferred.resolve(result('current-wide'));
  await latest;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS),
    bufferedDuration(EPG_WINDOW_DURATION_MS),
  ]);
  assert.equal(applied, 1);
  assert.equal(densityRefreshLatch.consume(false, 'guide'), false);
});

test('repeated loading density changes coalesce to one latest refetch', async () => {
  let density: EpgGuideDensity = 'comfortable';
  const requests: Array<{ durationMs: number; deferred: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>> }> = [];
  let applied = 0;
  const guide = {
    getPresentation: (input: { durationMs: number; startTimeMs: number }) => {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
      requests.push({ durationMs: input.durationMs, deferred: pending });
      return pending.promise;
    },
  } as unknown as LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => density,
    () => { applied += 1; },
  ));
  const densityRefreshLatch = createGuideDensityRefreshLatch();

  const initial = polling.refresh('poll-start');
  for (const nextDensity of ['compact', 'comfortable', 'compact'] as const) {
    density = nextDensity;
    densityRefreshLatch.noteChange();
    assert.equal(densityRefreshLatch.consume(true, 'guide'), false);
  }
  assert.equal(densityRefreshLatch.hasPending(), true);
  assert.equal(densityRefreshLatch.consume(false, 'guide'), true);
  const latest = polling.refresh('guide-density-change');
  assert.equal(densityRefreshLatch.consume(false, 'guide'), false);
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS)]);

  requests[0]?.deferred.resolve(result('stale-detailed'));
  await initial;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS),
    bufferedDuration(EPG_WINDOW_DURATION_MS),
  ]);
  requests[1]?.deferred.resolve(result('current-wide'));
  await latest;
  assert.equal(applied, 1);
});

test('density churn keeps one active request and applies only the latest current duration', async () => {
  let density: EpgGuideDensity = 'compact';
  const requests: Array<{ durationMs: number; deferred: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>> }> = [];
  let applied = 0;
  const guide = {
    getPresentation: (input: { durationMs: number; startTimeMs: number }) => {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
      requests.push({ durationMs: input.durationMs, deferred: pending });
      return pending.promise;
    },
  } as unknown as LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => density,
    () => { applied += 1; },
  ));

  const first = polling.refresh('initial');
  await Promise.resolve();
  density = 'comfortable';
  const second = polling.refresh('density-comfortable');
  const latest = polling.refresh('density-comfortable-latest');
  assert.equal(requests.length, 1);
  assert.equal(requests[0]?.durationMs, bufferedDuration(EPG_WINDOW_DURATION_MS));

  requests[0]?.deferred.resolve(result('stale'));
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(applied, 0);
  assert.equal(requests.length, 2);
  assert.equal(requests[1]?.durationMs, bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS));

  requests[1]?.deferred.resolve(result('current'));
  await Promise.all([first, second, latest]);
  assert.equal(applied, 1);
});
