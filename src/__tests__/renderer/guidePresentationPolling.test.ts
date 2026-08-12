import assert from 'node:assert/strict';
import test from 'node:test';
import {
  EPG_DETAILED_WINDOW_DURATION_MS,
  EPG_WIDE_WINDOW_DURATION_MS,
  EPG_SLOT_DURATION_MS,
  type EpgGuideTimeRange,
} from '../../renderer/epg.js';
import {
  createGuidePresentationPolling,
  GUIDE_VIEWPORT_REFRESH_SOURCE,
} from '../../renderer/guidePresentationPolling.js';
import { GuideChannelWindow } from '../../renderer/guideChannelWindow.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import {
  AUTO_GUIDE_PRELOAD_PROFILE,
  GUIDE_DOM_ROW_CAP,
  REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE,
} from '../../renderer/guideVirtualization.js';

const bufferedDuration = (durationMs: number): number =>
  durationMs + REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs * 2;

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
  getGuideTimeRange: () => EpgGuideTimeRange,
  applyPresentation: () => void,
) {
  return {
    guide,
    host: host(),
    getActiveRoute: () => 'guide' as const,
    getWindowStartMs: () => 0,
    getGuideTimeRange,
    getGuidePerformanceProfile: () => 'reduced-resource' as const,
    setLoading: () => undefined,
    applyPresentation: () => { applyPresentation(); return true; },
    handleFailure: () => undefined,
  };
}

test('Guide polling requests exactly the time-range duration', async () => {
  let timeRange: EpgGuideTimeRange = 'detailed';
  const durations: number[] = [];
  const guide = {
    getPresentation: async (input: { durationMs: number; startTimeMs: number }) => {
      durations.push(input.durationMs);
      return result(`request-${String(durations.length)}`);
    },
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  } satisfies LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => timeRange,
    () => undefined,
  ));

  await polling.refresh('time-range-detailed');
  timeRange = 'wide';
  await polling.refresh('time-range-wide');
  assert.deepEqual(durations, [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS), bufferedDuration(EPG_WIDE_WINDOW_DURATION_MS)]);
});

test('foreground channel limits follow complete viewport rows plus bounded overscan and clamp at the DOM row cap', async () => {
  let completeVisibleRows = 7;
  const limits: number[] = [];
  const guide = {
    getPresentation: async (input: { channelLimit?: number }) => {
      limits.push(input.channelLimit ?? -1);
      return result(`viewport-${String(limits.length)}`);
    },
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  } satisfies LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling({
    ...createOptions(guide, () => 'detailed', () => undefined),
    getCompleteVisibleRowCount: () => completeVisibleRows,
  });
  await polling.refresh('visible-seven');
  completeVisibleRows = 30;
  await polling.refresh('visible-clamped');
  assert.deepEqual(limits, [11, GUIDE_DOM_ROW_CAP]);
});

test('polling does not coalesce an active request when the visible-row channel limit changes', async () => {
  let completeVisibleRows = 5;
  const requests: Array<Deferred<ReturnType<typeof result>>> = [];
  const appliedLimits: number[] = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        const request = deferred<ReturnType<typeof result>>();
        requests.push(request);
        return request.promise;
      },
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'detailed',
    getGuidePerformanceProfile: () => 'auto',
    getCompleteVisibleRowCount: () => completeVisibleRows,
    setLoading: () => undefined,
    applyPresentation: (_value, _generation, _target, _effectiveStart, requestWindow) => {
      if (requestWindow !== undefined) appliedLimits.push(requestWindow.channelLimit);
      return true;
    },
    handleFailure: () => undefined,
  });

  const first = polling.refresh('poll-interval');
  completeVisibleRows = 8;
  const latest = polling.refresh('poll-interval');
  requests[0]?.resolve(result('obsolete-limit'));
  await first;
  assert.deepEqual(appliedLimits, []);
  assert.equal(requests.length, 2);
  requests[1]?.resolve(result('current-limit'));
  await latest;
  assert.deepEqual(appliedLimits, [12]);
});

test('merge-rejected pages are failed without cache promotion, replay, or idle warming', async (context) => {
  const idle: Array<() => void> = [];
  const busy: boolean[] = [];
  const failures: Array<{ retain: boolean; offset: number | undefined }> = [];
  const marks: Array<Record<string, unknown>> = [];
  let requests = 0;
  context.mock.method(globalThis.performance, 'mark',
    (_name: string, options?: PerformanceMarkOptions) => {
      if (options?.detail !== undefined) marks.push(options.detail as Record<string, unknown>);
      return {} as PerformanceMark;
    });
  context.mock.method(globalThis.performance, 'clearMarks', () => undefined);
  const pageResult = (): ReturnType<typeof result> => ({
    ok: true,
    requestId: `rejected-${String(++requests)}`,
    value: {
      channels: [{
        id: 'channel-0',
        number: '1',
        name: 'Channel 1',
        programs: [],
      }],
      nowWatching: null,
      minimumStartTimeMs: 0,
      channelWindow: { offset: 0, total: 1 },
      libraryFilter: {
        scopeToken: 'scope',
        revision: 0,
        libraries: [],
        selectedLibraryId: null,
        persistenceStatus: 'ready',
      },
    },
  });
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => pageResult(),
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'auto',
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope',
    setLoading: () => undefined,
    setPagingBusy: (value) => { busy.push(value); },
    applyPresentation: () => false,
    handleFailure: (_source, _message, _generation, retain, requestWindow) => {
      failures.push({ retain, offset: requestWindow?.channelOffset });
    },
  });

  await polling.requestPage({ targetGlobalIndex: 0, scopeToken: 'scope', channelOffset: 0, channelLimit: 1 });
  assert.equal(polling.getLastValidPresentation(), null);
  assert.equal(polling.getPendingPageTarget(), null);
  assert.deepEqual(busy, [true, false]);
  assert.deepEqual(failures, [{ retain: false, offset: 0 }]);
  assert.equal(idle.length, 0);

  await polling.requestPage({ targetGlobalIndex: 0, scopeToken: 'scope', channelOffset: 0, channelLimit: 1 });
  assert.equal(requests, 2, 'the rejected response was not cached or replayed');
  assert.deepEqual(busy, [true, false, true, false]);
  assert.equal(idle.length, 0, 'rejected pages do not seed idle warming');
  assert.deepEqual(
    marks.filter((detail) => detail.requestClass === 'rejected').map((detail) => detail.accepted),
    [false, false],
  );
});

test('foreground scope mismatch settles a loading Guide through the rejection path', async () => {
  let presentationState: 'ready' | 'loading' | 'error' = 'ready';
  let applied = 0;
  const failures: Array<{
    source: string;
    retainLastValid: boolean;
    channelOffset: number | undefined;
    channelLimit: number | undefined;
  }> = [];
  const mismatched = result('scope-mismatch');
  if (!mismatched.ok) throw new Error('Expected successful Guide fixture.');
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => ({
        ...mismatched,
        value: {
          ...mismatched.value,
          libraryFilter: {
            ...mismatched.value.libraryFilter,
            scopeToken: 'scope:stale',
          },
        },
      }),
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope:current',
    setLoading: () => { presentationState = 'loading'; },
    applyPresentation: () => { applied += 1; return true; },
    handleFailure: (source, _message, _generation, retainLastValid, requestWindow) => {
      presentationState = 'error';
      failures.push({
        source,
        retainLastValid,
        channelOffset: requestWindow?.channelOffset,
        channelLimit: requestWindow?.channelLimit,
      });
    },
  });

  await controller.refresh('scope-mismatch', {
    showLoading: true,
    channelOffset: 24,
    channelLimit: 12,
  });

  assert.equal(presentationState, 'error');
  assert.equal(applied, 0);
  assert.deepEqual(failures, [{
    source: 'scope-mismatch',
    retainLastValid: false,
    channelOffset: 24,
    channelLimit: 12,
  }]);
});

test('an invalid response for a new identity preserves the accepted owner and polling presentation', async () => {
  const owner = new GuideChannelWindow();
  let cacheIdentity = 'cache:stable';
  let requests = 0;
  const response = (requestId: string, scopeToken: string, offset: number) => ({
    ok: true as const,
    requestId,
    value: {
      channels: [{ id: `channel-${scopeToken}`, number: '1', name: scopeToken, programs: [] }],
      nowWatching: null,
      minimumStartTimeMs: 0,
      channelWindow: { offset, total: 1 },
      libraryFilter: {
        scopeToken,
        revision: 0,
        libraries: [],
        selectedLibraryId: null,
        persistenceStatus: 'ready' as const,
      },
    },
  });
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => {
        requests += 1;
        return requests === 1
          ? response('accepted', 'scope:stable', 0)
          : response(`rejected-${String(requests)}`, 'scope:new', 1);
      },
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'auto',
    getCacheIdentity: () => cacheIdentity,
    setLoading: () => undefined,
    applyPresentation: (presentation, generation, _target, _effectiveStart, requestWindow) =>
      owner.mergePresentation(
        presentation.libraryFilter?.scopeToken ?? 'unscoped',
        'auto',
        generation,
        requestWindow?.channelOffset ?? 0,
        requestWindow?.channelLimit ?? GUIDE_DOM_ROW_CAP,
        presentation,
      ),
    handleFailure: () => undefined,
  });

  await polling.refresh('accepted');
  const identity = owner.identity;
  const epoch = owner.epoch;
  const ownerPresentation = owner.presentation();
  const lastValid = polling.getLastValidPresentation();
  assert.ok(lastValid !== null);

  cacheIdentity = 'cache:new';
  await polling.refresh('invalid-transition');
  assert.equal(owner.identity, identity);
  assert.equal(owner.epoch, epoch);
  assert.deepEqual(owner.presentation(), ownerPresentation);
  assert.equal(polling.getLastValidPresentation(), lastValid);

  await polling.refresh('invalid-transition-retry');
  assert.equal(requests, 3, 'the rejected identity transition was neither cached nor replayed');
  assert.equal(polling.getLastValidPresentation(), lastValid);
});

test('Guide polling emits one honest terminal mark for runtime, cache, and cancellation', async (context) => {
  const marks: Array<{ name: string; detail: Record<string, unknown> }> = [];
  context.mock.method(globalThis.performance, 'mark',
    (name: string, { detail }: { detail: Record<string, unknown> }) => {
      marks.push({ name, detail });
      return {} as PerformanceMark;
    });
  context.mock.method(globalThis.performance, 'clearMarks', () => undefined);
  const pending = deferred<ReturnType<typeof result>>();
  let requests = 0;
  const polling = createGuidePresentationPolling({ ...createOptions({
    getPresentation: async () => ++requests === 1 ? result('runtime') : pending.promise,
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  }, () => 'detailed', () => undefined),
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope',
  });

  await polling.refresh('epg-window-change');
  await polling.refresh('epg-window-change');
  const cancelled = polling.refresh('foreground', { invalidateCache: true });
  await Promise.resolve();
  polling.stop();
  await cancelled;

  const settled = marks.filter(({ name }) => name === 'lineup-guide-v1:request-settled');
  assert.deepEqual(settled.map(({ detail }) => [
    detail.requestClass, detail.accepted, detail.requestOrigin,
  ]), [
    ['runtime', true, 'foreground'],
    ['renderer-cache', true, 'foreground'],
    ['rejected', false, 'foreground'],
  ]);
  const starts = marks.filter(({ name }) => name === 'lineup-guide-v1:request-start');
  assert.deepEqual(starts.map(({ detail }) => detail.sequence), settled.map(({ detail }) => detail.sequence));
});

test('Desktop preload profiles use exact row/time bounds and auto idle warming starts with the next channel page', async () => {
  const windowStartMs = 10 * 60 * 60_000;
  const foregroundRequests: Array<{ startTimeMs: number; durationMs: number; channelLimit?: number }> = [];
  for (const [auto, expected] of [
    [false, {
      startTimeMs: windowStartMs - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
      durationMs: EPG_WIDE_WINDOW_DURATION_MS + REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs * 2,
      channelLimit: REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.channelLimit,
    }],
    [true, {
      startTimeMs: windowStartMs - AUTO_GUIDE_PRELOAD_PROFILE.timeBufferMs,
      durationMs: EPG_WIDE_WINDOW_DURATION_MS + AUTO_GUIDE_PRELOAD_PROFILE.timeBufferMs * 2,
      channelLimit: AUTO_GUIDE_PRELOAD_PROFILE.channelLimit,
    }],
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
        cancelPresentation: async () => undefined,
        setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
      },
      host: {
        setTimeout: (callback: TimerHandler, delay?: number) => globalThis.setTimeout(callback, delay) as unknown as number,
        clearTimeout: (handle: number) => globalThis.clearTimeout(handle),
        requestIdleCallback: (callback: IdleRequestCallback) => { idle.push(() => callback({ didTimeout: false, timeRemaining: () => 50 })); return idle.length; },
        cancelIdleCallback: () => undefined,
      } as unknown as Window,
      getActiveRoute: () => 'guide', getWindowStartMs: () => windowStartMs,
      getGuideTimeRange: () => 'wide', getGuidePerformanceProfile: () => auto ? 'auto' : 'reduced-resource',
      setLoading: () => undefined, applyPresentation: () => true, handleFailure: () => undefined,
    });
    await controller.refresh('profile-proof');
    assert.deepEqual(requests[0], { ...expected, channelOffset: 0 });
    foregroundRequests.push({
      startTimeMs: requests[0]?.startTimeMs ?? 0,
      durationMs: requests[0]?.durationMs ?? 0,
      channelLimit: requests[0]?.channelLimit,
    });
    if (auto) {
      assert.equal(idle.length, 1);
      idle.shift()?.();
      await new Promise((resolve) => globalThis.setTimeout(resolve, 0));
      assert.equal(requests[1]?.channelOffset, AUTO_GUIDE_PRELOAD_PROFILE.channelLimit);
      assert.equal(requests.length, 2);
    } else {
      assert.equal(idle.length, 0);
    }
    controller.stop();
  }
  assert.deepEqual(foregroundRequests[0], foregroundRequests[1]);
});

test('auto warm failures remain cache misses without applying foreground failure state', async () => {
  for (const failureMode of ['rejection', 'error-result', 'scope-mismatch'] as const) {
    const idle: Array<() => void> = [];
    const failures: string[] = [];
    let requestCount = 0;
    let applied = 0;
    const controller = createGuidePresentationPolling({
      guide: {
        getPresentation: async (input) => {
          requestCount += 1;
          if (requestCount === 1) {
            const response = result(`${failureMode}-foreground`);
            if (!response.ok) throw new Error('Expected foreground fixture success.');
            return {
              ...response,
              value: {
                ...response.value,
                channelWindow: { offset: input.channelOffset ?? 0, total: 300 },
              },
            };
          }
          if (failureMode === 'rejection') throw new Error('private warm failure');
          if (failureMode === 'scope-mismatch') {
            const response = result(`${failureMode}-warm`);
            if (!response.ok) throw new Error('Expected warm scope-mismatch fixture success.');
            return {
              ...response,
              value: {
                ...response.value,
                libraryFilter: {
                  ...response.value.libraryFilter,
                  scopeToken: 'scope:stale',
                },
              },
            };
          }
          return {
            ok: false as const,
            requestId: `${failureMode}-warm`,
            error: {
              code: 'GUIDE_TRANSPORT_ERROR',
              message: 'Guide is unavailable.',
              retryable: true,
              recoverable: true,
              operation: 'getPresentation',
            },
          };
        },
        cancelPresentation: async () => undefined,
        setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
      },
      host: idleHost(idle),
      getActiveRoute: () => 'guide',
      getWindowStartMs: () => 0,
      getGuideTimeRange: () => 'wide',
      getGuidePerformanceProfile: () => 'auto',
      getCacheIdentity: () => 'identity',
      getCacheScopeToken: () => 'scope',
      setLoading: () => undefined,
      applyPresentation: () => { applied += 1; return true; },
      handleFailure: (source) => { failures.push(`guide:${source}`); },
      handlePlayerFailure: (source) => { failures.push(`player:${source}`); },
    });

    await controller.refresh('foreground');
    assert.equal(applied, 1, `${failureMode} applies the foreground result`);
    assert.equal(idle.length, 1, `${failureMode} schedules an auto warm`);

    idle.shift()?.();
    await tick();

    assert.equal(requestCount, 2, `${failureMode} executes the warm request`);
    assert.equal(applied, 1, `${failureMode} does not apply a warm result`);
    assert.deepEqual(failures, [], `${failureMode} does not apply foreground failure state`);
    controller.stop();
  }
});

test('foreground visible-window work cancels an active idle warm before it runs', async () => {
  const idle: Array<() => void> = [];
  const warm = deferred<ReturnType<typeof result>>();
  const offsets: number[] = [];
  let cancellations = 0;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async (input) => {
        offsets.push(input.channelOffset ?? 0);
        if (offsets.length === 2) return warm.promise;
        const response = result(`foreground-${String(offsets.length)}`);
        if (!response.ok) throw new Error('Expected successful Guide fixture.');
        return { ...response, value: { ...response.value, channelWindow: { offset: input.channelOffset ?? 0, total: 500 } } };
      },
      cancelPresentation: async () => { cancellations += 1; },
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle), getActiveRoute: () => 'guide', getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'detailed', getGuidePerformanceProfile: () => 'auto',
    setLoading: () => undefined, applyPresentation: () => true, handleFailure: () => undefined,
  });
  await controller.refresh('foreground');
  idle.shift()?.();
  await tick();
  assert.equal(offsets.length, 2, 'idle warm is active');
  await controller.refresh(GUIDE_VIEWPORT_REFRESH_SOURCE, { channelOffset: 250, channelLimit: 11 });
  assert.equal(cancellations, 1);
  assert.deepEqual(offsets, [0, GUIDE_DOM_ROW_CAP, 250]);
  controller.stop();
});

test('superseded foreground windows emit generation-aware settlement and permit bounded refetch', async () => {
  const requests: Array<Deferred<ReturnType<typeof result>>> = [];
  const states: Array<{
    state: 'queued' | 'settled'; generation: number; offset: number; limit: number;
  }> = [];
  const controller = createGuidePresentationPolling({
    ...createOptions({
      getPresentation: async () => {
        const request = deferred<ReturnType<typeof result>>();
        requests.push(request);
        return request.promise;
      },
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    }, () => 'detailed', () => undefined),
    requestWindowState: (state, request) => states.push({
      state, generation: request.generation, offset: request.channelOffset, limit: request.channelLimit,
    }),
  });
  const first = controller.refresh('visible-a', { channelOffset: 100, channelLimit: 10 });
  const replacement = controller.refresh('visible-b', { channelOffset: 200, channelLimit: 10 });
  assert.deepEqual(states.slice(0, 2).map(({ state, offset }) => [state, offset]), [
    ['queued', 100], ['queued', 200],
  ]);
  requests[0]?.resolve(result('stale-a'));
  await tick();
  assert.ok(states.some(({ state, offset }) => state === 'settled' && offset === 100));
  assert.equal(requests.length, 2);
  requests[1]?.resolve(result('current-b'));
  await Promise.all([first, replacement]);

  const refetch = controller.refresh('visible-a-again', { channelOffset: 100, channelLimit: 10 });
  assert.equal(requests.length, 3);
  assert.ok(states.filter(({ state, offset }) => state === 'queued' && offset === 100).length === 2);
  assert.ok(states.every(({ limit }) => limit <= GUIDE_DOM_ROW_CAP));
  requests[2]?.resolve(result('refetch-a'));
  await refetch;
  controller.stop();
});

test('guide-visible-window keeps Guide-scoped rendering through queued, accepted, and settled callbacks', async () => {
  const request = deferred<ReturnType<typeof result>>();
  const lifecycle: Array<{ phase: string; source: string }> = [];
  let guideScopedRenders = 0;
  let unrelatedApplicationRenders = 0;
  let nativePresentationReconciles = 0;
  const renderForSource = (source: string): void => {
    if (source === GUIDE_VIEWPORT_REFRESH_SOURCE) {
      guideScopedRenders += 1;
      return;
    }
    unrelatedApplicationRenders += 1;
    nativePresentationReconciles += 1;
  };
  const controller = createGuidePresentationPolling({
    ...createOptions({
      getPresentation: async () => request.promise,
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    }, () => 'detailed', () => undefined),
    requestWindowState: (state, window) => {
      lifecycle.push({ phase: state, source: window.source });
      renderForSource(window.source);
    },
    applyPresentation: (_presentation, _generation, _target, _effectiveStart, _window, source) => {
      assert.equal(source, GUIDE_VIEWPORT_REFRESH_SOURCE);
      lifecycle.push({ phase: 'accepted', source });
      renderForSource(source);
      return true;
    },
  });

  const refresh = controller.refresh(GUIDE_VIEWPORT_REFRESH_SOURCE, {
    channelOffset: 80,
    channelLimit: 10,
    showLoading: false,
  });
  request.resolve(result(GUIDE_VIEWPORT_REFRESH_SOURCE));
  await refresh;

  assert.deepEqual(lifecycle, [
    { phase: 'queued', source: GUIDE_VIEWPORT_REFRESH_SOURCE },
    { phase: 'accepted', source: GUIDE_VIEWPORT_REFRESH_SOURCE },
    { phase: 'settled', source: GUIDE_VIEWPORT_REFRESH_SOURCE },
  ]);
  assert.equal(guideScopedRenders, 3);
  assert.equal(unrelatedApplicationRenders, 0);
  assert.equal(nativePresentationReconciles, 0);

  renderForSource('poll-interval');
  assert.equal(unrelatedApplicationRenders, 1, 'non-viewport refreshes retain whole-application rendering');
  assert.equal(nativePresentationReconciles, 1);
  controller.stop();
});

test('auto page and adjacent-time warm entries are consumed without another bridge request', async () => {
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
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle),
    getActiveRoute: () => 'guide', getWindowStartMs: () => windowStartMs,
    getChannelOffset: () => channelOffset,
    getGuideTimeRange: () => 'wide', getGuidePerformanceProfile: () => 'auto',
    getCacheIdentity: () => 'identity', getCacheScopeToken: () => 'scope',
    setLoading: () => undefined, applyPresentation: (presentation) => {
      applied += 1;
      channelOffset = presentation.channelWindow?.offset ?? channelOffset;
      return true;
    }, handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests.length, 1);
  idle.shift()?.();
  await tick();
  assert.equal(requests[1]?.channelOffset, AUTO_GUIDE_PRELOAD_PROFILE.channelLimit);

  const beforePage = requests.length;
  await controller.requestPage({
    targetGlobalIndex: AUTO_GUIDE_PRELOAD_PROFILE.channelLimit,
    scopeToken: 'scope',
    channelOffset: AUTO_GUIDE_PRELOAD_PROFILE.channelLimit,
  });
  assert.equal(requests.length, beforePage, 'warmed page is applied from cache');

  idle.shift()?.();
  await tick();
  assert.equal(
    requests.at(-1)?.channelOffset,
    AUTO_GUIDE_PRELOAD_PROFILE.channelLimit * 2,
    'cache-hit page reprioritizes the next adjacent page',
  );
  idle.shift()?.();
  await tick();
  assert.equal(requests.at(-1)?.channelOffset, 0, 'cache-hit page then warms the previous adjacent page');
  idle.shift()?.();
  await tick();
  assert.equal(requests.at(-1)?.channelOffset, AUTO_GUIDE_PRELOAD_PROFILE.channelLimit);
  assert.equal(
    requests.at(-1)?.startTimeMs,
    windowStartMs + EPG_SLOT_DURATION_MS - AUTO_GUIDE_PRELOAD_PROFILE.timeBufferMs,
  );
  const beforeWindow = requests.length;
  windowStartMs += EPG_SLOT_DURATION_MS;
  await controller.refresh('epg-window-change');
  assert.equal(requests.length, beforeWindow, 'warmed adjacent time window is applied from cache');
  assert.equal(applied, 3);
  controller.stop();
});

test('past-window and trusted identity changes invalidate cached presentations before lookup', async () => {
  let identity = 'scope:rev1:past-auto:wide:default';
  let requests = 0;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => result(`identity-${String(++requests)}`),
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide', getCacheIdentity: () => identity, getCacheScopeToken: () => 'scope',
    setLoading: () => undefined, applyPresentation: () => true, handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests, 1);
  controller.notePastItemsWindowChange();
  await controller.refresh('epg-window-change');
  assert.equal(requests, 2, 'past-window notification clears a same-window cached page immediately');

  identity = 'scope:rev2:past-30:wide:default';
  await controller.refresh('epg-window-change');
  assert.equal(requests, 3, 'a changed trusted identity cannot read the previous identity key');
  controller.stop();
});

test('cache invalidation requires explicit intent instead of diagnostic source labels', async () => {
  let activeRoute: 'guide' | 'settings' = 'guide';
  let requests = 0;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => result(`invalidation-${String(++requests)}`),
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope',
    setLoading: () => undefined,
    applyPresentation: () => true,
    handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests, 1);

  activeRoute = 'settings';
  await controller.refresh('guide-settings-change');
  activeRoute = 'guide';
  await controller.refresh('epg-window-change');
  assert.equal(requests, 1, 'a diagnostic label does not clear the cache off-route');

  activeRoute = 'settings';
  await controller.refresh('diagnostic-label', { invalidateCache: true });
  activeRoute = 'guide';
  await controller.refresh('epg-window-change');
  assert.equal(requests, 2, 'typed invalidation clears the cache independently of source');
  controller.stop();
});

test('page/window cache entries expire at the poll interval and refetch on a stale miss', async () => {
  let nowMs = 1_000;
  let requests = 0;
  let applied = 0;
  const guide = {
    getPresentation: async () => {
      requests += 1;
      return result(`freshness-${String(requests)}`);
    },
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  } satisfies LineupDesktopPreloadApi['guide'];
  const controller = createGuidePresentationPolling({
    guide,
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope',
    getNowMs: () => nowMs,
    setLoading: () => undefined,
    applyPresentation: () => { applied += 1; return true; },
    handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests, 1);

  nowMs += 14_999;
  await controller.refresh('epg-window-change');
  assert.equal(requests, 1, 'an entry younger than one poll interval is reused');
  assert.equal(applied, 2);

  nowMs += 1;
  await controller.refresh('epg-window-change');
  assert.equal(requests, 2, 'an entry at the poll interval is removed and refetched');
  assert.equal(applied, 3);
  controller.stop();
});

test('preload profile replacement swaps the cache and discards stale warm candidates', async () => {
  let auto = true;
  const idle: Array<() => void> = [];
  const requests: Array<{ channelLimit?: number }> = [];
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async (input) => {
        requests.push(input);
        return result(`profile-switch-${String(requests.length)}`);
      },
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => auto ? 'auto' : 'reduced-resource',
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope',
    setLoading: () => undefined,
    applyPresentation: () => true,
    handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(requests.length, 1);
  assert.equal(idle.length, 1);

  auto = false;
  await controller.refresh('epg-window-change');
  assert.equal(requests.length, 2, 'the new profile starts with an empty LRU');
  assert.equal(requests[1]?.channelLimit, REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.channelLimit);
  idle.shift()?.();
  await tick();
  assert.equal(requests.length, 2, 'warm candidates from the discarded profile are not requested');
  controller.stop();
});

test('undefined cache identity matches null for lookup, insertion, and currentness', async () => {
  for (const initialIdentity of [null, undefined] as const) {
    const identity: string | null | undefined = initialIdentity;
    let requests = 0;
    let applied = 0;
    const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
    const controller = createGuidePresentationPolling({
      guide: {
        getPresentation: async () => {
          requests += 1;
          return pending.promise;
        },
        cancelPresentation: async () => undefined,
        setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
      },
      host: host(),
      getActiveRoute: () => 'guide',
      getWindowStartMs: () => 0,
      getGuideTimeRange: () => 'wide',
      getCacheIdentity: () => identity as string | null,
      getCacheScopeToken: () => 'scope',
      setLoading: () => undefined,
      applyPresentation: () => { applied += 1; return true; },
      handleFailure: () => undefined,
    });

    const first = controller.refresh('foreground');
    await Promise.resolve();
    pending.resolve(result(`identity-${String(initialIdentity)}`));
    await first;
    await controller.refresh('epg-window-change');
    assert.equal(requests, 2, `identity ${String(initialIdentity)} does not create a cache entry`);
    assert.equal(applied, 2, `identity ${String(initialIdentity)} remains current after normalization`);
    controller.stop();
  }
});

test('cache hits cross one async boundary before currentness is rechecked', async () => {
  let activeRoute: 'guide' | 'settings' = 'guide';
  let applied = 0;
  const controller = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => result('microtask'),
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: host(),
    getActiveRoute: () => activeRoute,
    getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide',
    getCacheIdentity: () => 'identity',
    getCacheScopeToken: () => 'scope',
    setLoading: () => undefined,
    applyPresentation: () => { applied += 1; return true; },
    handleFailure: () => undefined,
  });

  await controller.refresh('foreground');
  assert.equal(applied, 1);
  const cacheHit = controller.refresh('epg-window-change');
  activeRoute = 'settings';
  await cacheHit;
  assert.equal(applied, 1, 'the cache hit yields before applying stale presentation');
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
      cancelPresentation: async () => undefined,
      setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
    },
    host: idleHost(idle), getActiveRoute: () => 'guide', getWindowStartMs: () => 0,
    getGuideTimeRange: () => 'wide', getGuidePerformanceProfile: () => 'auto',
    getCacheIdentity: () => 'identity', getCacheScopeToken: () => 'scope',
    setLoading: () => undefined, applyPresentation: () => true, handleFailure: () => undefined,
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

test('startup time-range change during loading latches one wide refetch after stale detailed work', async () => {
  let timeRange: EpgGuideTimeRange = 'detailed';
  const requests: Array<{ durationMs: number; deferred: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>> }> = [];
  let applied = 0;
  const guide = {
    getPresentation: (input: { durationMs: number; startTimeMs: number }) => {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
      requests.push({ durationMs: input.durationMs, deferred: pending });
      return pending.promise;
    },
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  } satisfies LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => timeRange,
    () => { applied += 1; },
  ));

  const initial = polling.refresh('poll-start');
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS)]);
  timeRange = 'wide';
  polling.noteGuideSettingsChange();
  await polling.settleGuideSettings(true);
  assert.equal(polling.hasPendingGuideSettingsChange(), true);

  const latest = polling.settleGuideSettings(false);
  assert.equal(polling.hasPendingGuideSettingsChange(), false);
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS)]);
  requests[0]?.deferred.resolve(result('stale-detailed'));
  await initial;
  assert.equal(applied, 0);
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS),
    bufferedDuration(EPG_WIDE_WINDOW_DURATION_MS),
  ]);
  requests[1]?.deferred.resolve(result('current-wide'));
  await latest;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS),
    bufferedDuration(EPG_WIDE_WINDOW_DURATION_MS),
  ]);
  assert.equal(applied, 1);
});

test('repeated loading time-range changes coalesce to one latest refetch', async () => {
  let timeRange: EpgGuideTimeRange = 'detailed';
  const requests: Array<{ durationMs: number; deferred: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>> }> = [];
  let applied = 0;
  const guide = {
    getPresentation: (input: { durationMs: number; startTimeMs: number }) => {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
      requests.push({ durationMs: input.durationMs, deferred: pending });
      return pending.promise;
    },
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  } satisfies LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => timeRange,
    () => { applied += 1; },
  ));

  const initial = polling.refresh('poll-start');
  for (const nextTimeRange of ['wide', 'detailed', 'wide'] as const) {
    timeRange = nextTimeRange;
    polling.noteGuideSettingsChange();
    await polling.settleGuideSettings(true);
  }
  assert.equal(polling.hasPendingGuideSettingsChange(), true);
  const latest = polling.settleGuideSettings(false);
  assert.equal(polling.hasPendingGuideSettingsChange(), false);
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS)]);

  requests[0]?.deferred.resolve(result('stale-detailed'));
  await initial;
  assert.deepEqual(requests.map(({ durationMs }) => durationMs), [
    bufferedDuration(EPG_DETAILED_WINDOW_DURATION_MS),
    bufferedDuration(EPG_WIDE_WINDOW_DURATION_MS),
  ]);
  requests[1]?.deferred.resolve(result('current-wide'));
  await latest;
  assert.equal(applied, 1);
});

test('time-range churn keeps one active request and applies only the latest current duration', async () => {
  let timeRange: EpgGuideTimeRange = 'wide';
  const requests: Array<{ durationMs: number; deferred: Deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>> }> = [];
  let applied = 0;
  const guide = {
    getPresentation: (input: { durationMs: number; startTimeMs: number }) => {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['guide']['getPresentation']>>>();
      requests.push({ durationMs: input.durationMs, deferred: pending });
      return pending.promise;
    },
    cancelPresentation: async () => undefined,
    setLibraryFilter: async () => { throw new Error('Unexpected filter request.'); },
  } satisfies LineupDesktopPreloadApi['guide'];
  const polling = createGuidePresentationPolling(createOptions(
    guide,
    () => timeRange,
    () => { applied += 1; },
  ));

  const first = polling.refresh('initial');
  await Promise.resolve();
  timeRange = 'detailed';
  const second = polling.refresh('time-range-detailed');
  const latest = polling.refresh('time-range-detailed-latest');
  assert.equal(requests.length, 1);
  assert.equal(requests[0]?.durationMs, bufferedDuration(EPG_WIDE_WINDOW_DURATION_MS));

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
