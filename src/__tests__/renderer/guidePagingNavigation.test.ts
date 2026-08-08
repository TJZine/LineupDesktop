import assert from 'node:assert/strict';
import test from 'node:test';

import {
  EPG_CHANNEL_PAGE_SIZE,
  createEpgState,
  resolveEpgPageNavigation,
  selectEpgPageTarget,
  updateEpgState,
} from '../../renderer/epg.js';
import {
  createGuidePresentationPolling,
  type GuidePresentationPollingOptions,
} from '../../renderer/guidePresentationPolling.js';
import type { GuideIpcResult, GuidePresentationSource } from '../../contracts/guide.js';

test('Guide Page navigation keeps ±5 local, crosses pages, replaces one target, and clamps boundaries', () => {
  const pageOffset = 10;
  const total = pageOffset + EPG_CHANNEL_PAGE_SIZE * 3;
  const page = presentation(EPG_CHANNEL_PAGE_SIZE, pageOffset, total);
  let state = { ...createEpgState(page, 0, 'compact'), selectedChannelId: `channel-${String(pageOffset + 2)}`, selectedProgramId: `program-${String(pageOffset + 2)}` };
  const inside = resolveEpgPageNavigation(state, page, 5);
  assert.deepEqual(inside, {
    targetGlobalIndex: pageOffset + 7, sourceLocalIndex: 2, channelOffset: pageOffset, targetLocalIndex: 7,
    fetchRequired: false, boundaryClamped: false,
  });
  state = selectEpgPageTarget(state, inside!.targetLocalIndex!, page);
  assert.equal(state.selectedChannelId, `channel-${String(pageOffset + 7)}`);

  const cross = resolveEpgPageNavigation(state, page, 5);
  assert.equal(cross?.fetchRequired, true);
  assert.equal(cross?.targetGlobalIndex, pageOffset + 12);
  assert.equal(cross?.channelOffset, pageOffset + 5);
  const trailing = resolveEpgPageNavigation(state, page, 5, cross!.targetGlobalIndex);
  assert.equal(trailing?.targetGlobalIndex, pageOffset + 17);
  assert.equal(trailing?.channelOffset, pageOffset + 10);

  const first = presentation(EPG_CHANNEL_PAGE_SIZE, 0, total);
  const firstState = { ...createEpgState(first, 0, 'compact'), selectedChannelId: 'channel-0', selectedProgramId: 'program-0' };
  const clamped = resolveEpgPageNavigation(firstState, first, -5);
  assert.equal(clamped?.boundaryClamped, true);
  assert.equal(clamped?.fetchRequired, false);

  const last = presentation(3, total - 3, total);
  const lastState = { ...createEpgState(last, 0, 'compact'), selectedChannelId: `channel-${String(total - 1)}`, selectedProgramId: `program-${String(total - 1)}` };
  const lastClamped = resolveEpgPageNavigation(lastState, last, 5);
  assert.equal(lastClamped?.targetGlobalIndex, total - 1);
  assert.equal(lastClamped?.boundaryClamped, true);
  assert.equal(lastClamped?.fetchRequired, false);
});

test('Guide paging owner binds focus to its exact request and retains last valid state on failure', async () => {
  const requests: Array<Deferred<GuideIpcResult<GuidePresentationSource>>> = [];
  const channelLimits: Array<number | undefined> = [];
  const applied: Array<{ offset: number; target: number | null }> = [];
  const failures: Array<{ message: string; retain: boolean }> = [];
  const busy: boolean[] = [];
  let epgState = { ...createEpgState(presentation(9, 0, 30), 0, 'compact'), selectedChannelId: 'channel-2', selectedProgramId: 'program-2' };
  let focusedAfterPaging: string | null = null;
  let route: 'guide' | 'settings' = 'guide';
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (input) => {
        channelLimits.push(input.channelLimit);
        const deferred = createDeferred<GuideIpcResult<GuidePresentationSource>>();
        requests.push(deferred);
        return deferred.promise;
      },
      setLibraryFilter: async (_input) => {
        throw new Error('Unexpected Guide library-filter request.');
      },
    } satisfies GuidePresentationPollingOptions['guide'],
    host: timerHost(), getActiveRoute: () => route, getWindowStartMs: () => 0, getGuideDensity: () => 'compact',
    setLoading: () => undefined,
    setPagingBusy: (value) => busy.push(value),
    applyPresentation: (value, generation, target) => {
      epgState = updateEpgState(epgState, value, generation);
      if (typeof target === 'number') {
        epgState = selectEpgPageTarget(epgState, target - (value.channelWindow?.offset ?? 0), value);
        focusedAfterPaging = epgState.selectedChannelId;
      }
      applied.push({ offset: value.channelWindow?.offset ?? -1, target: target ?? null });
    },
    handleFailure: (_source, message, _generation, retain) => failures.push({ message, retain }),
  });
  const success = polling.requestPage({ targetGlobalIndex: 12, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 10 });
  assert.deepEqual(busy, [true]);
  assert.deepEqual(channelLimits, [EPG_CHANNEL_PAGE_SIZE]);
  requests[0]?.resolve(okPresentation(EPG_CHANNEL_PAGE_SIZE, 10, 30, 'scope'));
  await success;
  assert.deepEqual(applied, [{ offset: 10, target: 12 }]);
  assert.equal(focusedAfterPaging, 'channel-12');
  assert.deepEqual(busy, [true, false]);

  const failed = polling.requestPage({ targetGlobalIndex: 20, sourceLocalIndex: 5, scopeToken: 'scope', channelOffset: 15 });
  requests[1]?.resolve({ ok: false, requestId: 'request', error: {
    code: 'GUIDE_PRESENTATION_FAILED', message: 'Guide page failed.', retryable: true, recoverable: true, operation: 'getPresentation',
  } });
  await failed;
  assert.deepEqual(failures, [{ message: 'Guide page failed.', retain: true }]);
  assert.deepEqual(applied, [{ offset: 10, target: 12 }]);

  const wrongScope = polling.requestPage({ targetGlobalIndex: 20, sourceLocalIndex: 5, scopeToken: 'scope', channelOffset: 15 });
  requests[2]?.resolve(okPresentation(9, 15, 30, 'new-scope'));
  await wrongScope;
  assert.deepEqual(applied.at(-1), { offset: 15, target: null });

  const canceled = polling.requestPage({ targetGlobalIndex: 25, sourceLocalIndex: 5, scopeToken: 'new-scope', channelOffset: 20 });
  route = 'settings';
  polling.reconcile('guide', 'settings');
  await canceled;
  requests[3]?.resolve(okPresentation(9, 20, 30, 'new-scope'));
  await settle();
  assert.equal(applied.length, 2);
  assert.equal(busy.at(-1), false);
});

test('Guide paging owner keeps one active/one trailing target and rejects time-refresh supersession', async () => {
  const requests: Array<Deferred<GuideIpcResult<GuidePresentationSource>>> = [];
  const targets: Array<number | null | undefined> = [];
  const busy: boolean[] = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (_input) => {
        const deferred = createDeferred<GuideIpcResult<GuidePresentationSource>>();
        requests.push(deferred);
        return deferred.promise;
      },
      setLibraryFilter: async (_input) => {
        throw new Error('Unexpected Guide library-filter request.');
      },
    } satisfies GuidePresentationPollingOptions['guide'],
    host: timerHost(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0, getGuideDensity: () => 'compact',
    setLoading: () => undefined, setPagingBusy: (value) => busy.push(value),
    applyPresentation: (_value, _generation, target) => targets.push(target), handleFailure: () => undefined,
  });
  const active = polling.requestPage({ targetGlobalIndex: 12, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 10 });
  const trailing = polling.requestPage({ targetGlobalIndex: 17, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 15 });
  const latest = polling.requestPage({ targetGlobalIndex: 22, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 20 });
  assert.equal(trailing, latest);
  assert.equal(requests.length, 1);
  assert.equal(polling.getPendingPageTarget(), 22);
  requests[0]?.resolve(okPresentation(9, 10, 30, 'scope'));
  await active;
  assert.equal(requests.length, 2);
  assert.deepEqual(targets, []);
  requests[1]?.resolve(okPresentation(9, 20, 30, 'scope'));
  await Promise.all([trailing, latest]);
  assert.deepEqual(targets, [22]);

  const stalePage = polling.requestPage({ targetGlobalIndex: 27, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 21 });
  const timeRefresh = polling.refresh('epg-window-change', { showLoading: true, channelOffset: 0 });
  assert.equal(busy.at(-1), false);
  requests[2]?.resolve(okPresentation(9, 21, 30, 'scope'));
  await stalePage;
  assert.equal(requests.length, 4);
  requests[3]?.resolve(okPresentation(9, 0, 30, 'scope'));
  await timeRefresh;
  assert.deepEqual(targets, [22, undefined]);
});

test('Guide interval supersession clears a queued page through its existing settlement path', async () => {
  const requests: Array<Deferred<GuideIpcResult<GuidePresentationSource>>> = [];
  const busy: boolean[] = [];
  const appliedTargets: Array<number | null | undefined> = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (_input) => {
        const deferred = createDeferred<GuideIpcResult<GuidePresentationSource>>();
        requests.push(deferred);
        return deferred.promise;
      },
      setLibraryFilter: async (_input) => {
        throw new Error('Unexpected Guide library-filter request.');
      },
    } satisfies GuidePresentationPollingOptions['guide'],
    host: timerHost(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0, getGuideDensity: () => 'compact',
    setLoading: () => undefined,
    setPagingBusy: (value) => busy.push(value),
    applyPresentation: (_value, _generation, target) => appliedTargets.push(target),
    handleFailure: () => undefined,
  });

  const active = polling.refresh('initial');
  const queuedPage = polling.requestPage({
    targetGlobalIndex: 12,
    sourceLocalIndex: 2,
    scopeToken: 'scope',
    channelOffset: 10,
  });
  assert.equal(polling.getPendingPageTarget(), 12);
  const interval = polling.refresh('poll-interval');
  await queuedPage;
  assert.equal(polling.getPendingPageTarget(), null);
  assert.equal(busy.at(-1), false);

  requests[0]?.resolve(okPresentation(9, 0, 30, 'scope'));
  await active;
  assert.equal(requests.length, 2);
  requests[1]?.resolve(okPresentation(9, 0, 30, 'scope'));
  await interval;
  assert.equal(polling.getPendingPageTarget(), null);
  assert.equal(busy.at(-1), false);
  assert.deepEqual(appliedTargets, [undefined]);
});

test('Guide page cancellation rejects late success and failure without replacing last-valid presentation', async () => {
  const requests: Array<Deferred<GuideIpcResult<GuidePresentationSource>>> = [];
  const applied: number[] = [];
  const failures: string[] = [];
  const busy: boolean[] = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (_input) => {
        const deferred = createDeferred<GuideIpcResult<GuidePresentationSource>>();
        requests.push(deferred);
        return deferred.promise;
      },
      setLibraryFilter: async (_input) => {
        throw new Error('Unexpected Guide library-filter request.');
      },
    } satisfies GuidePresentationPollingOptions['guide'],
    host: timerHost(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0, getGuideDensity: () => 'compact',
    setLoading: () => undefined, setPagingBusy: (value) => busy.push(value),
    applyPresentation: (value) => applied.push(value.channelWindow?.offset ?? -1),
    handleFailure: (_source, message) => failures.push(message),
  });

  const initial = polling.refresh('initial');
  requests[0]?.resolve(okPresentation(9, 0, 30, 'scope'));
  await initial;
  const lastValid = polling.getLastValidPresentation();
  assert.deepEqual(applied, [0]);

  const lateSuccess = polling.requestPage({ targetGlobalIndex: 12, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 10 });
  polling.cancelPage();
  requests[1]?.resolve(okPresentation(9, 10, 30, 'scope'));
  await lateSuccess;
  assert.deepEqual(applied, [0]);
  assert.equal(polling.getLastValidPresentation(), lastValid);

  const lateFailure = polling.requestPage({ targetGlobalIndex: 17, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 15 });
  polling.cancelPage();
  requests[2]?.resolve({ ok: false, requestId: 'request', error: {
    code: 'GUIDE_PRESENTATION_FAILED', message: 'Late page failure.', retryable: true,
    recoverable: true, operation: 'getPresentation',
  } });
  await lateFailure;
  assert.deepEqual(failures, []);
  assert.equal(polling.getLastValidPresentation(), lastValid);
  assert.deepEqual(busy, [true, false, true, false]);
});

test('Guide page cancellation releases the active request before starting the latest page', async () => {
  const requests: Array<Deferred<GuideIpcResult<GuidePresentationSource>>> = [];
  const applied: number[] = [];
  const busy: boolean[] = [];
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (_input) => {
        const deferred = createDeferred<GuideIpcResult<GuidePresentationSource>>();
        requests.push(deferred);
        return deferred.promise;
      },
      setLibraryFilter: async (_input) => {
        throw new Error('Unexpected Guide library-filter request.');
      },
    } satisfies GuidePresentationPollingOptions['guide'],
    host: timerHost(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0, getGuideDensity: () => 'compact',
    setLoading: () => undefined, setPagingBusy: (value) => busy.push(value),
    applyPresentation: (value) => applied.push(value.channelWindow?.offset ?? -1),
    handleFailure: () => undefined,
  });

  const cancelled = polling.requestPage({
    targetGlobalIndex: 12, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 10,
  });
  assert.equal(requests.length, 1);
  polling.cancelPage();
  const latest = polling.requestPage({
    targetGlobalIndex: 17, sourceLocalIndex: 2, scopeToken: 'scope', channelOffset: 15,
  });

  await settle();
  assert.equal(requests.length, 2);
  assert.deepEqual(busy, [true, false, true]);
  requests[1]?.resolve(okPresentation(EPG_CHANNEL_PAGE_SIZE, 15, 30, 'scope'));
  await Promise.all([cancelled, latest]);
  assert.deepEqual(applied, [15]);
  assert.equal(busy.at(-1), false);

  requests[0]?.resolve(okPresentation(EPG_CHANNEL_PAGE_SIZE, 10, 30, 'scope'));
  await settle();
  assert.deepEqual(applied, [15]);
  assert.equal(busy.at(-1), false);
});

test('Guide +5,+5,-5,-5 reversal discards its queued page and focuses the loaded row without fetching', async () => {
  const requests: Array<Deferred<GuideIpcResult<GuidePresentationSource>>> = [];
  const applied: number[] = [];
  const busy: boolean[] = [];
  const current = presentation(9, 10, 30);
  let state = { ...createEpgState(current, 0, 'compact'), selectedChannelId: 'channel-17', selectedProgramId: 'program-17' };
  const polling = createGuidePresentationPolling({
    guide: {
      getPresentation: async (_input) => {
        const deferred = createDeferred<GuideIpcResult<GuidePresentationSource>>();
        requests.push(deferred);
        return deferred.promise;
      },
      setLibraryFilter: async (_input) => {
        throw new Error('Unexpected Guide library-filter request.');
      },
    } satisfies GuidePresentationPollingOptions['guide'],
    host: timerHost(), getActiveRoute: () => 'guide', getWindowStartMs: () => 0, getGuideDensity: () => 'compact',
    setLoading: () => undefined, setPagingBusy: (value) => busy.push(value),
    applyPresentation: (value) => applied.push(value.channelWindow?.offset ?? -1),
    handleFailure: () => undefined,
  });
  assert.deepEqual(
    polling.navigatePage({ state, presentation: current, offset: 5, scopeToken: 'scope' }),
    { handled: true, targetLocalIndex: null },
  );
  assert.deepEqual(
    polling.navigatePage({ state, presentation: current, offset: 5, scopeToken: 'scope' }),
    { handled: true, targetLocalIndex: null },
  );
  assert.deepEqual(
    polling.navigatePage({ state, presentation: current, offset: -5, scopeToken: 'scope' }),
    { handled: true, targetLocalIndex: null },
  );
  assert.equal(requests.length, 1);
  const reversed = polling.navigatePage({ state, presentation: current, offset: -5, scopeToken: 'scope' });
  assert.deepEqual(reversed, { handled: true, targetLocalIndex: 7 });
  assert.equal(requests.length, 1);
  assert.equal(polling.getPendingPageTarget(), null);
  state = selectEpgPageTarget(state, reversed.targetLocalIndex!, current);
  assert.equal(state.selectedChannelId, 'channel-17');
  assert.deepEqual(busy, [true, true, true, false]);

  requests[0]?.resolve(okPresentation(9, 15, 30, 'scope'));
  await settle();
  assert.equal(requests.length, 1);
  assert.deepEqual(applied, []);
});

function presentation(count: number, offset: number, total: number): GuidePresentationSource {
  return {
    nowWatching: null,
    minimumStartTimeMs: 0,
    channelWindow: { offset, total },
    libraryFilter: { scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'missing' },
    channels: Array.from({ length: count }, (_, local) => {
      const index = offset + local;
      return { id: `channel-${index}`, number: String(index), name: `Channel ${index}`, programs: [{
        id: `program-${index}`, title: `Program ${index}`, subtitle: '', description: '', showTitle: '', episodeLabel: '',
        rating: '', quality: [], genres: [], startsAtMs: 0, endsAtMs: 60_000, artwork: null,
      }] };
    }),
  };
}

function okPresentation(count: number, offset: number, total: number, scopeToken: string): GuideIpcResult<GuidePresentationSource> {
  const value = presentation(count, offset, total);
  return {
    ok: true,
    requestId: 'request',
    value: { ...value, libraryFilter: { ...value.libraryFilter, scopeToken } },
  };
}

interface Deferred<T> { promise: Promise<T>; resolve(value: T): void }
function createDeferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  return { promise: new Promise<T>((done) => { resolve = done; }), resolve };
}
function timerHost(): Window {
  return {
    setInterval: () => 1, clearInterval: () => undefined,
    setTimeout: () => 2, clearTimeout: () => undefined,
  } as unknown as Window;
}
async function settle(): Promise<void> { await Promise.resolve(); await Promise.resolve(); }
