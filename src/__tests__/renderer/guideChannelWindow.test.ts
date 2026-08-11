import assert from 'node:assert/strict';
import test from 'node:test';

import { GuideChannelWindow } from '../../renderer/guideChannelWindow.js';
import { moveEpgSelectionAbsolute, createEpgState, type NormalizedEpgPresentationSource } from '../../renderer/epg.js';

const SLOT = 30 * 60_000;

for (const total of [459, 500]) {
  test(`sparse Guide window traverses first, middle, and last rows of ${String(total)} channels`, () => {
    const owner = new GuideChannelWindow();
    owner.reset('scope:1', 'auto');
    owner.setVisible(0, 8);
    mergeVisible(owner, total, 1);
    assert.deepEqual(owner.project().rows.filter((row) => row.state === 'ready').map((row) => row.absoluteIndex),
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

    owner.setVisible(Math.floor(total / 2), 8);
    const middleLoading = owner.project(2);
    assert.ok(middleLoading.rows.every((row) => row.state === 'loading'));
    assert.equal(middleLoading.request?.channelOffset, Math.floor(total / 2) - 2);
    mergeVisible(owner, total, 2);
    assert.ok(owner.project().rows.some((row) => row.state === 'ready' && row.absoluteIndex === Math.floor(total / 2)));

    owner.setVisible(total - 8, 8);
    mergeVisible(owner, total, 3);
    const last = owner.project();
    assert.equal(last.rows.at(-1)?.absoluteIndex, total - 1);
    assert.ok(last.rows.every((row) => row.state === 'ready'));
    assert.ok(last.rows.length <= 24);
  });
}

test('fast jumps expose inert loading/error projections and retry without fabricated row identity', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope:1', 'reduced-resource');
  owner.setVisible(0, 6);
  mergeVisible(owner, 500, 1);
  owner.setVisible(250, 6);
  const loading = owner.project(2);
  const intent = loading.request;
  assert.ok(intent !== null);
  assert.ok(intent.channelLimit <= 24);
  owner.markLoading(intent);
  assert.ok(owner.project().rows.every((row) => row.state === 'loading'));
  owner.fail(intent);
  const failed = owner.project(3);
  assert.ok(failed.rows.every((row) => row.state === 'error'));
  assert.ok(failed.rows.every((row) => !('channel' in row)));
  const retry = owner.retryVisible(3);
  assert.equal(retry?.channelOffset, failed.rows[0]?.absoluteIndex);
  assert.equal(retry?.channelLimit, intent.channelLimit);
  assert.ok(retry !== null);
  owner.markLoading(retry);
  assert.ok(owner.project().rows.every((row) => row.state === 'loading'));
  assert.equal(owner.merge(retry, page(retry.channelOffset, retry.channelLimit, 500)), true);
  assert.ok(owner.project().rows.every((row) => row.state === 'ready'));
});

test('identity epochs reject stale pages and sparse navigation preserves time-column intent', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope:1');
  owner.setVisible(20, 6);
  const stale = owner.beginForeground(1);
  assert.ok(stale !== null);
  owner.reset('scope:2');
  assert.equal(owner.merge(stale, page(20, stale.channelLimit, 100)), false);

  const olderRange = owner.createIntent(2, 20, 10);
  const newerRange = owner.createIntent(3, 20, 10);
  owner.markLoading(olderRange);
  owner.markLoading(newerRange);
  assert.equal(owner.merge(olderRange, page(20, 10, 100)), false, 'older same-range generation cannot merge');
  assert.equal(owner.merge(newerRange, page(20, 10, 100)), true);

  owner.setVisible(20, 6);
  const presentation = owner.presentation();
  const selectedChannel = presentation.channels[2];
  assert.ok(selectedChannel !== undefined);
  const state = {
    ...createEpgState(presentation, 2, 'detailed'),
    selectedChannelId: selectedChannel.id,
    selectedProgramId: selectedChannel.programs[1]?.id ?? '',
  };
  const moved = moveEpgSelectionAbsolute(state, 1, presentation);
  assert.equal(moved?.loaded, true);
  assert.equal(moved?.targetAbsoluteIndex, 23);
  assert.equal(moved?.state.selectedProgramId.endsWith('-1'), true);
});

test('finite LRU retains visible rows and eventually evicts old unpinned pages', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope:1', 'reduced-resource');
  for (let pageIndex = 0; pageIndex < 8; pageIndex += 1) {
    owner.setVisible(pageIndex * 10, 6);
    mergeVisible(owner, 500, pageIndex + 1);
  }
  owner.setVisible(0, 6);
  assert.ok(owner.project(20).request !== null, 'old unpinned page is evicted');
  owner.setVisible(70, 6);
  assert.equal(owner.project(21).request, null, 'current visible page remains retained');
});

test('absolute arrow and viewport-Page movement cross a loaded boundary and clamp at the 500-row end', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope');
  const first = owner.createIntent(1, 0, 10);
  owner.markLoading(first);
  owner.merge(first, page(0, 10, 500));
  owner.setVisible(4, 6, 9);
  let presentation = owner.presentation();
  let state = {
    ...createEpgState(presentation, 1, 'detailed'),
    selectedChannelId: 'channel-9',
    selectedProgramId: 'program-9-1',
  };
  const boundaryArrow = moveEpgSelectionAbsolute(state, 1, presentation);
  assert.deepEqual({ loaded: boundaryArrow?.loaded, target: boundaryArrow?.targetAbsoluteIndex }, { loaded: false, target: 10 });

  const next = owner.beginForeground(2);
  assert.ok(next !== null);
  owner.markLoading(next);
  owner.merge(next, page(next.channelOffset, next.channelLimit, 500));
  presentation = owner.presentation();
  const loadedArrow = moveEpgSelectionAbsolute(state, 1, presentation);
  assert.equal(loadedArrow?.state.selectedChannelId, 'channel-10');
  state = loadedArrow?.state ?? state;
  const viewportPage = moveEpgSelectionAbsolute(state, owner.completeVisibleRowCount, presentation);
  assert.equal(viewportPage?.targetAbsoluteIndex, 16);

  owner.setVisible(494, 6, 499);
  const lastIntent = owner.beginForeground(3);
  assert.ok(lastIntent !== null);
  owner.markLoading(lastIntent);
  owner.merge(lastIntent, page(lastIntent.channelOffset, lastIntent.channelLimit, 500));
  presentation = owner.presentation();
  state = { ...state, selectedChannelId: 'channel-499', selectedProgramId: 'program-499-1' };
  assert.equal(moveEpgSelectionAbsolute(state, 6, presentation)?.targetAbsoluteIndex, 499);
});

test('20 complete visible rows trade one overscan row for the offscreen focused row within the 24-row cap', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope');
  const first = owner.createIntent(1, 0, 24);
  owner.markLoading(first);
  owner.merge(first, page(0, 24, 500));

  owner.setVisible(200, 20, 0);
  const target = owner.beginForeground(2);
  assert.ok(target !== null);
  owner.markLoading(target);
  owner.merge(target, page(target.channelOffset, target.channelLimit, 500));
  const projected = owner.project().rows;
  assert.equal(projected.length, 24);
  assert.ok(projected.some((row) => row.absoluteIndex === 0 && row.state === 'ready'));
  for (let index = 200; index < 220; index += 1) {
    assert.ok(projected.some((row) => row.absoluteIndex === index), `complete visible row ${String(index)} remains mounted`);
  }

  owner.setVisible(300, 24, 0);
  const fullViewport = owner.beginForeground(3);
  assert.ok(fullViewport !== null);
  owner.markLoading(fullViewport);
  owner.merge(fullViewport, page(fullViewport.channelOffset, fullViewport.channelLimit, 500));
  const fullProjection = owner.project().rows;
  assert.equal(fullProjection.length, 24);
  assert.deepEqual(fullProjection.map((row) => row.absoluteIndex), Array.from({ length: 24 }, (_, index) => 300 + index));
});

test('superseded pending foreground ranges release only their generation and become requestable again', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope');
  const initial = owner.createIntent(1, 0, 10);
  owner.markLoading(initial);
  owner.merge(initial, page(0, 10, 500));
  owner.setVisible(100, 6);
  const first = owner.beginForeground(2);
  assert.ok(first !== null);
  owner.markLoading(first);
  owner.setVisible(200, 6);
  const replacement = owner.beginForeground(3);
  assert.ok(replacement !== null);
  owner.markLoading(replacement);

  assert.equal(owner.release(first), true);
  owner.setVisible(100, 6);
  const refetch = owner.beginForeground(4);
  assert.equal(refetch?.channelOffset, first.channelOffset);
  assert.ok((refetch?.channelLimit ?? 25) <= 24);
  assert.ok(refetch !== null);
  owner.markLoading(refetch);
  assert.equal(owner.release(first), false, 'late settlement cannot clear the replacement generation');
  assert.equal(owner.beginForeground(5), null, 'the bounded replacement remains pending');
});

test('Arrow, viewport Page, and gamepad-equivalent movement skip loaded rows without visible programs', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope');
  const intent = owner.createIntent(1, 0, 12);
  owner.markLoading(intent);
  owner.merge(intent, page(0, 12, 100, new Set([3, 8])));
  owner.setVisible(0, 8, 2);
  const presentation = owner.presentation();
  const state = {
    ...createEpgState(presentation, 1, 'detailed'),
    selectedChannelId: 'channel-2',
    selectedProgramId: 'program-2-1',
  };
  assert.equal(moveEpgSelectionAbsolute(state, 1, presentation)?.state.selectedChannelId, 'channel-4');
  assert.equal(moveEpgSelectionAbsolute(state, 6, presentation)?.state.selectedChannelId, 'channel-9');
  const gamepadDown = moveEpgSelectionAbsolute(state, 1, presentation);
  assert.deepEqual(
    { channel: gamepadDown?.state.selectedChannelId, rowState: gamepadDown?.rowState },
    { channel: 'channel-4', rowState: 'ready' },
  );
});

test('directional error targets produce one exact failed-range retry and recover', () => {
  const owner = new GuideChannelWindow();
  owner.reset('scope');
  const initial = owner.createIntent(1, 0, 10);
  owner.markLoading(initial);
  owner.merge(initial, page(0, 10, 100));
  owner.setVisible(6, 6, 9);
  const failedRange = owner.beginForeground(2);
  assert.ok(failedRange !== null);
  owner.markLoading(failedRange);
  owner.fail(failedRange);
  let presentation = owner.presentation();
  const state = {
    ...createEpgState(presentation, 1, 'detailed'),
    selectedChannelId: 'channel-9',
    selectedProgramId: 'program-9-1',
  };
  const target = moveEpgSelectionAbsolute(state, 1, presentation);
  assert.deepEqual(
    { loaded: target?.loaded, rowState: target?.rowState, target: target?.targetAbsoluteIndex },
    { loaded: false, rowState: 'error', target: 10 },
  );
  const retry = owner.retryAt(10, 3);
  assert.deepEqual(
    { offset: retry?.channelOffset, limit: retry?.channelLimit },
    { offset: failedRange.channelOffset, limit: failedRange.channelLimit },
  );
  assert.ok(retry !== null);
  owner.markLoading(retry);
  owner.merge(retry, page(retry.channelOffset, retry.channelLimit, 100));
  presentation = owner.presentation();
  assert.equal(moveEpgSelectionAbsolute(state, 1, presentation)?.state.selectedChannelId, 'channel-10');
});

function mergeVisible(owner: GuideChannelWindow, total: number, generation: number): void {
  const intent = owner.beginForeground(generation);
  assert.ok(intent !== null);
  owner.markLoading(intent);
  assert.equal(owner.merge(intent, page(intent.channelOffset, intent.channelLimit, total)), true);
}

function page(
  offset: number,
  count: number,
  total: number,
  withoutPrograms: ReadonlySet<number> = new Set(),
): NormalizedEpgPresentationSource {
  return {
    channels: Array.from({ length: Math.min(count, total - offset) }, (_, localIndex) => {
      const index = offset + localIndex;
      return {
        id: `channel-${String(index)}`,
        number: String(index + 1),
        name: `Channel ${String(index + 1)}`,
        programs: (withoutPrograms.has(index) ? [] : [0, 1, 2]).map((programIndex) => ({
          id: `program-${String(index)}-${String(programIndex)}`,
          title: `Program ${String(programIndex)}`,
          subtitle: '', description: '', showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [], artwork: null,
          startsAtMs: programIndex * SLOT,
          endsAtMs: (programIndex + 1) * SLOT,
        })),
      };
    }),
    nowWatching: null,
    nowMs: SLOT / 2,
    minimumStartTimeMs: 0,
    channelWindow: { offset, total },
    libraryFilter: { scopeToken: 'scope', revision: 1, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
  };
}
