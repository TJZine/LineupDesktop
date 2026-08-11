import assert from 'node:assert/strict';
import test from 'node:test';

import {
  EPG_WIDE_WINDOW_DURATION_MS,
  EPG_SLOT_DURATION_MS,
  computeProvisionalEpgMinimumStartTimeMs,
  createEpgGuideView,
  createEpgState,
  focusEpgNow,
  moveEpgSelection,
  setEpgPastItemsWindow,
  settleEpgPresentation,
  type EpgPresentationSource,
} from '../../renderer/epg.js';
import { createGuidePresentationPolling } from '../../renderer/guidePresentationPolling.js';
import { REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE } from '../../renderer/guideVirtualization.js';

const BASE = Date.UTC(2026, 6, 8, 12, 0);

function presentation(
  minimumStartTimeMs?: number,
  startsAtMs = BASE,
  endsAtMs = BASE + EPG_SLOT_DURATION_MS,
): EpgPresentationSource {
  return {
    channels: [{
      id: 'channel-1', number: '1', name: 'One', programs: [{
        id: 'program-1', title: 'Program', subtitle: '', description: '', showTitle: '', episodeLabel: '',
        rating: '', quality: [], genres: [], startsAtMs, endsAtMs, artwork: null,
      }],
    }],
    nowWatching: null,
    nowMs: BASE,
    ...(minimumStartTimeMs === undefined ? {} : { minimumStartTimeMs }),
    channelWindow: { offset: 0, total: 1 },
    libraryFilter: { scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
  };
}

function host(): Window {
  const timers = new Map<number, ReturnType<typeof globalThis.setTimeout>>();
  let nextTimer = 0;
  return {
    setTimeout: (callback: TimerHandler, delay?: number) => {
      const handle = ++nextTimer;
      timers.set(handle, globalThis.setTimeout(callback as (...args: never[]) => void, delay));
      return handle;
    },
    clearTimeout: (handle: number) => {
      const timer = timers.get(handle);
      if (timer !== undefined) globalThis.clearTimeout(timer);
      timers.delete(handle);
    },
    setInterval: () => 1,
    clearInterval: () => undefined,
  } as unknown as Window;
}

function deferred<T>(): { promise: Promise<T>; resolve(value: T): void } {
  let resolvePromise: (value: T) => void = () => undefined;
  const promise = new Promise<T>((resolve) => { resolvePromise = resolve; });
  return { promise, resolve: (value) => resolvePromise(value) };
}

type GuideRequest = { startTimeMs: number; durationMs: number; channelOffset?: number; channelLimit?: number };

test('renderer uses conservative Auto 15 provisionally and never moves left of the bound', () => {
  const source = presentation();
  let state = createEpgState(source, 1, 'wide');
  const provisional = computeProvisionalEpgMinimumStartTimeMs(BASE, 'auto');
  state = setEpgPastItemsWindow(state, 'auto', BASE, source);
  assert.equal(state.minimumStartTimeMs, provisional);
  const accepted = presentation(BASE);
  const settled = settleEpgPresentation(state, accepted, 2, null, false, 'wide', BASE);
  assert.equal(settled.state.minimumStartTimeMs, BASE);
  assert.equal(settled.state.windowStartMs, BASE);
  const moved = moveEpgSelection(settled.state, 'left', accepted);
  assert.equal(moved.state.windowStartMs, BASE);
  assert.equal(moved.windowChanged, false);
});

test('renderer provisional bounds follow slot rollover and local midnight under the owned timezone', () => {
  const processValue: unknown = Reflect.get(globalThis, 'process');
  assert.equal(typeof processValue, 'object');
  if (typeof processValue !== 'object' || processValue === null) return;
  const env = (processValue as { env: Record<string, string | undefined> }).env;
  const previousTimezone = env.TZ;
  try {
    env.TZ = 'America/New_York';
    assert.equal(Intl.DateTimeFormat().resolvedOptions().timeZone, 'America/New_York');
    const cases = [
      // 2026-07-08T12:14:00Z / 08:14 EDT -> 2026-07-08T11:30:00Z / 07:30 EDT.
      { nowMs: 1_783_512_840_000, setting: '15' as const, expected: 1_783_510_200_000 },
      // 2026-07-08T12:16:00Z / 08:16 EDT -> 2026-07-08T12:00:00Z / 08:00 EDT.
      { nowMs: 1_783_512_960_000, setting: '15' as const, expected: 1_783_512_000_000 },
      // 2026-07-08T04:10:00Z / 00:10 EDT -> local midnight 2026-07-08T04:00:00Z.
      { nowMs: 1_783_483_800_000, setting: '30' as const, expected: 1_783_483_200_000 },
    ] as const;
    for (const { nowMs, setting, expected } of cases) {
      assert.equal(computeProvisionalEpgMinimumStartTimeMs(nowMs, setting), expected);
    }
  } finally {
    if (previousTimezone === undefined) delete env.TZ;
    else env.TZ = previousTimezone;
  }
});

test('renderer keeps epoch-zero bounds nonnegative in Asia/Tokyo', () => {
  const processValue: unknown = Reflect.get(globalThis, 'process');
  assert.equal(typeof processValue, 'object');
  if (typeof processValue !== 'object' || processValue === null) return;
  const env = (processValue as { env: Record<string, string | undefined> }).env;
  const previousTimezone = env.TZ;
  try {
    env.TZ = 'Asia/Tokyo';
    assert.equal(Intl.DateTimeFormat().resolvedOptions().timeZone, 'Asia/Tokyo');
    assert.equal(new Date(0).getHours(), 9);
    assert.equal(computeProvisionalEpgMinimumStartTimeMs(0, '30'), 0);
  } finally {
    if (previousTimezone === undefined) delete env.TZ;
    else env.TZ = previousTimezone;
  }
});

test('renderer clamps every left/window/focus path while retaining an overlapping adjacent selection', () => {
  const bound = BASE;
  const source: EpgPresentationSource = {
    channels: [
      {
        id: 'channel-1', number: '1', name: 'One', programs: [
          { ...presentation().channels[0]!.programs[0]!, id: 'before', startsAtMs: bound - EPG_SLOT_DURATION_MS, endsAtMs: bound },
          { ...presentation().channels[0]!.programs[0]!, id: 'current', startsAtMs: bound, endsAtMs: bound + EPG_SLOT_DURATION_MS },
        ],
      },
      {
        id: 'channel-2', number: '2', name: 'Two', programs: [
          { ...presentation().channels[0]!.programs[0]!, id: 'overlap', startsAtMs: bound + EPG_SLOT_DURATION_MS / 2, endsAtMs: bound + EPG_SLOT_DURATION_MS * 2 },
        ],
      },
    ],
    nowWatching: null,
    nowMs: bound + EPG_SLOT_DURATION_MS,
    minimumStartTimeMs: bound,
    channelWindow: { offset: 0, total: 2 },
    libraryFilter: { scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
  };
  const initial = createEpgState(source, 3, 'wide');
  const movedLeft = moveEpgSelection({ ...initial, windowStartMs: bound + EPG_SLOT_DURATION_MS }, 'left', source);
  assert.equal(movedLeft.state.windowStartMs, bound);
  assert.equal(movedLeft.state.windowStartMs >= bound, true);
  const focused = focusEpgNow({ ...initial, windowStartMs: bound + EPG_SLOT_DURATION_MS }, source, bound - EPG_SLOT_DURATION_MS);
  assert.equal(focused.windowStartMs, bound);
  const overlapped = moveEpgSelection(initial, 'down', source);
  assert.equal(overlapped.state.selectedProgramId, 'overlap');
  assert.equal(overlapped.state.windowStartMs, bound);
});

test('polling adopts the main-clamped effective start and full duration without a corrective request', async () => {
  const pending = deferred<unknown>();
  const requests: Array<{ startTimeMs: number; durationMs: number }> = [];
  const applied: Array<{ effectiveStartTimeMs: number | undefined }> = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (request: GuideRequest) => {
        requests.push(request);
        return await pending.promise as never;
      },
      cancelPresentation: async () => undefined,
    } as never,
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => BASE - EPG_SLOT_DURATION_MS,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => undefined,
    applyPresentation: (_value, _generation, _target, effectiveStartTimeMs) => {
      applied.push({ effectiveStartTimeMs });
    },
    handleFailure: () => undefined,
  });
  const refresh = polling.refresh('past-window');
  await Promise.resolve();
  assert.deepEqual(requests, [{
    startTimeMs: BASE - EPG_SLOT_DURATION_MS - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
    durationMs: EPG_WIDE_WINDOW_DURATION_MS + REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs * 2,
    channelOffset: 0,
    channelLimit: REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.channelLimit,
  }]);
  pending.resolve({
    ok: true,
    requestId: 'guide-request',
    value: presentation(BASE),
  });
  await refresh;
  assert.equal(requests.length, 1);
  assert.deepEqual(applied, [{ effectiveStartTimeMs: BASE }]);
});

test('sequential polling settlements advance the bound and retain a program crossing it without duplicate requests', async () => {
  const firstBound = BASE;
  const secondBound = BASE + EPG_SLOT_DURATION_MS;
  const results = [
    presentation(firstBound, firstBound, secondBound),
    presentation(secondBound, secondBound - EPG_SLOT_DURATION_MS / 2, secondBound + EPG_SLOT_DURATION_MS),
  ];
  const requests: number[] = [];
  const renderedProgramIds: string[] = [];
  let state = createEpgState(presentation(), 1, 'wide');
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (request: GuideRequest) => {
        requests.push(request.startTimeMs);
        return { ok: true, requestId: `rollover-${requests.length}`, value: results.shift()! };
      },
      cancelPresentation: async () => undefined,
    } as never,
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => state.windowStartMs,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => undefined,
    applyPresentation: (value, generation, target, effectiveStartTimeMs) => {
      state = settleEpgPresentation(state, value, generation, target, false, 'wide', effectiveStartTimeMs).state;
      renderedProgramIds.push(createEpgGuideView(state, value).selectedProgram?.id ?? '');
    },
    handleFailure: () => undefined,
  });

  await polling.refresh('poll-slot-one');
  assert.equal(state.minimumStartTimeMs, firstBound);
  assert.equal(state.windowStartMs, firstBound);
  await polling.refresh('poll-slot-two');
  assert.equal(state.minimumStartTimeMs, secondBound);
  assert.equal(state.windowStartMs, secondBound);
  assert.deepEqual(requests, [
    firstBound - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
    firstBound - REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE.timeBufferMs,
  ]);
  assert.deepEqual(renderedProgramIds, ['program-1', 'program-1']);
  await Promise.resolve();
  assert.equal(requests.length, 2);
});

test('polling rejects a stale pre-settlement result after optimistic policy invalidation', async () => {
  const pending = deferred<unknown>();
  let applied = 0;
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async () => await pending.promise as never,
      cancelPresentation: async () => undefined,
    } as never,
    host: host(),
    getActiveRoute: () => 'guide',
    getWindowStartMs: () => BASE,
    getGuideTimeRange: () => 'wide',
    getGuidePerformanceProfile: () => 'reduced-resource',
    setLoading: () => undefined,
    applyPresentation: () => { applied += 1; },
    handleFailure: () => undefined,
  });
  const refresh = polling.refresh('past-window');
  await Promise.resolve();
  polling.notePastItemsWindowChange();
  pending.resolve({ ok: true, requestId: 'guide-request', value: presentation(BASE) });
  await refresh;
  assert.equal(applied, 0);
});
