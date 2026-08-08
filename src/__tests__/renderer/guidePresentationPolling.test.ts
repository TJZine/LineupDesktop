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

function result(requestId: string): Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>> {
  return {
    ok: true,
    requestId,
    value: {
      channels: [],
      nowWatching: null,
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
  assert.deepEqual(durations, [EPG_DETAILED_WINDOW_DURATION_MS, EPG_WINDOW_DURATION_MS]);
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
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [EPG_DETAILED_WINDOW_DURATION_MS]);
  density = 'compact';
  densityRefreshLatch.noteChange();
  assert.equal(densityRefreshLatch.consume(true, 'guide'), false);
  assert.equal(densityRefreshLatch.hasPending(), true);

  assert.equal(densityRefreshLatch.consume(false, 'guide'), true);
  const latest = polling.refresh('guide-density-change');
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [EPG_DETAILED_WINDOW_DURATION_MS]);
  requests[0]?.deferred.resolve(result('stale-detailed'));
  await initial;
  assert.equal(applied, 0);
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    EPG_DETAILED_WINDOW_DURATION_MS,
    EPG_WINDOW_DURATION_MS,
  ]);
  requests[1]?.deferred.resolve(result('current-wide'));
  await latest;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    EPG_DETAILED_WINDOW_DURATION_MS,
    EPG_WINDOW_DURATION_MS,
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
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [EPG_DETAILED_WINDOW_DURATION_MS]);

  requests[0]?.deferred.resolve(result('stale-detailed'));
  await initial;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    EPG_DETAILED_WINDOW_DURATION_MS,
    EPG_WINDOW_DURATION_MS,
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
  assert.equal(requests[0]?.durationMs, EPG_WINDOW_DURATION_MS);

  requests[0]?.deferred.resolve(result('stale'));
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(applied, 0);
  assert.equal(requests.length, 2);
  assert.equal(requests[1]?.durationMs, EPG_DETAILED_WINDOW_DURATION_MS);

  requests[1]?.deferred.resolve(result('current'));
  await Promise.all([first, second, latest]);
  assert.equal(applied, 1);
});
