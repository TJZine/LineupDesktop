import assert from 'node:assert/strict';
import test from 'node:test';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createGuideTuneController, type GuideTuneTarget } from '../../renderer/guideTuneController.js';
import type { EpgProgramCellViewModel } from '../../renderer/epg.js';
import { deferred } from '../helpers/deferred.js';

const NOW = 2_000;
const target: GuideTuneTarget = {
  channelId: 'channel',
  programId: 'program',
  focusId: 'guide-program-channel--program',
  presentationGeneration: 4,
};

function cell(startsAtMs = 1_000, endsAtMs = 3_000): EpgProgramCellViewModel {
  return {
    id: 'program', channelId: 'channel', focusId: target.focusId, presentationGeneration: 4,
    title: 'Program', subtitle: '', description: '', showTitle: 'Program', episodeLabel: '',
    rating: '', quality: [], genres: [], startsAtMs, endsAtMs,
    columnStart: 1, columnSpan: 1, isSelected: true, temporalState: 'current',
    progressPercent: 50, widthTier: 'narrow', timeLabel: 'Now',
    artwork: null,
  };
}

test('current Guide activation dispatches exactly one tune while pending', async () => {
  const request = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['tuneChannel']>>>();
  const calls: string[] = [];
  const pending: Array<string | null> = [];
  const accepted: string[] = [];
  const controller = createGuideTuneController({
    player: { tuneChannel: async ({ channelId }) => { calls.push(channelId); return request.promise; } },
    getActiveRoute: () => 'guide', getPresentationGeneration: () => 4, getNowMs: () => NOW,
    findProgram: () => cell(),
    onPendingChanged: (value) => pending.push(value?.focusId ?? null),
    onAccepted: (value) => accepted.push(value.focusId),
    onFailure: () => assert.fail('failure callback was not expected'),
  });

  const first = controller.activate(target);
  assert.equal(await controller.activate(target), false);
  assert.deepEqual(calls, ['channel']);
  assert.equal(controller.isPending(), true);
  assert.deepEqual(controller.getPendingTarget(), target);
  request.resolve({ ok: true, value: undefined as never, requestId: 'tune-1' });
  assert.equal(await first, true);
  assert.equal(controller.getPendingTarget(), null);
  assert.deepEqual(pending, [target.focusId, null]);
  assert.deepEqual(accepted, [target.focusId]);
});

test('dispatched tune keeps custody when the Guide presentation is replaced', async () => {
  const request = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['tuneChannel']>>>();
  const accepted: GuideTuneTarget[] = [];
  let generation = 4;
  let currentCell: EpgProgramCellViewModel | null = cell();
  const controller = createGuideTuneController({
    player: { tuneChannel: async () => request.promise },
    getActiveRoute: () => 'guide',
    getPresentationGeneration: () => generation,
    getNowMs: () => NOW,
    findProgram: () => currentCell,
    onPendingChanged: () => undefined,
    onAccepted: (value) => accepted.push(value),
    onFailure: () => assert.fail('failure callback was not expected'),
  });

  const pending = controller.activate(target);
  generation = 5;
  currentCell = null;
  request.resolve({ ok: true, value: undefined as never, requestId: 'tune-after-refresh' });

  assert.equal(await pending, true);
  assert.deepEqual(accepted, [target]);
  assert.equal(controller.getPendingTarget(), null);
});

test('pending never-settling tune clears and releases activation on stop', async () => {
  const request = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['tuneChannel']>>>();
  let projected: GuideTuneTarget | null = null;
  let controller: ReturnType<typeof createGuideTuneController>;
  const project = (): void => { projected = controller.getPendingTarget(); };
  controller = createGuideTuneController({
    player: { tuneChannel: async () => request.promise },
    getActiveRoute: () => 'guide', getPresentationGeneration: () => 4, getNowMs: () => NOW,
    findProgram: () => cell(),
    onPendingChanged: project,
    onAccepted: () => assert.fail('stopped tune must not be accepted'),
    onFailure: () => assert.fail('stopped tune must not fail visibly'),
  });

  const pending = controller.activate(target);
  assert.deepEqual(projected, target);
  project();
  assert.deepEqual(projected, target);
  controller.stop();
  assert.equal(projected, null);
  assert.equal(controller.getPendingTarget(), null);
  assert.equal(await pending, true);
  assert.equal(projected, null);
});

test('past, future, stale-generation, and off-route activation are explicit no-ops', async () => {
  let calls = 0;
  let route: 'guide' | 'player' = 'guide';
  let generation = 4;
  let currentCell = cell(0, 1_000);
  const controller = createGuideTuneController({
    player: { tuneChannel: async () => { calls += 1; return { ok: true, value: undefined as never, requestId: 'tune' }; } },
    getActiveRoute: () => route, getPresentationGeneration: () => generation, getNowMs: () => NOW,
    findProgram: () => currentCell,
    onPendingChanged: () => undefined, onAccepted: () => undefined, onFailure: () => undefined,
  });
  assert.equal(await controller.activate(target), false);
  currentCell = cell(3_000, 4_000);
  assert.equal(await controller.activate(target), false);
  generation = 5;
  assert.equal(await controller.activate(target), false);
  generation = 4;
  route = 'player';
  assert.equal(await controller.activate(target), false);
  assert.equal(calls, 0);
});

test('safe failure stays current while stop invalidates late completion', async () => {
  const first = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['tuneChannel']>>>();
  const failures: string[] = [];
  let call = 0;
  const controller = createGuideTuneController({
    player: { tuneChannel: async () => { call += 1; return call === 1 ? first.promise : { ok: false, error: { code: 'operation-failed', message: 'Unable to tune.', retryable: true, recoverable: true, operation: 'tuneChannel' }, requestId: 'tune-2' }; } },
    getActiveRoute: () => 'guide', getPresentationGeneration: () => 4, getNowMs: () => NOW,
    findProgram: () => cell(),
    onPendingChanged: () => undefined, onAccepted: () => assert.fail('success was not expected'),
    onFailure: (_value, message) => failures.push(message),
  });
  const stale = controller.activate(target);
  controller.stop();
  first.resolve({ ok: false, error: { code: 'operation-failed', message: 'Late failure.', retryable: true, recoverable: true, operation: 'tuneChannel' }, requestId: 'late' });
  await stale;
  assert.deepEqual(failures, []);
  assert.equal(await controller.activate(target), true);
  assert.deepEqual(failures, ['Unable to tune.']);
});

test('never-settling tune times out safely and permits the next Guide activation', async () => {
  const never = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['tuneChannel']>>>();
  const failures: string[] = [];
  const accepted: string[] = [];
  let calls = 0;
  const controller = createGuideTuneController({
    player: {
      tuneChannel: async () => {
        calls += 1;
        return calls === 1
          ? never.promise
          : { ok: true, value: undefined as never, requestId: 'tune-after-timeout' };
      },
    },
    getActiveRoute: () => 'guide',
    getPresentationGeneration: () => 4,
    getNowMs: () => NOW,
    findProgram: () => cell(),
    onPendingChanged: () => undefined,
    onAccepted: (value) => accepted.push(value.focusId),
    onFailure: (_value, message) => failures.push(message),
    requestTimeoutMs: 0,
  });

  assert.equal(await controller.activate(target), true);
  assert.equal(controller.isPending(), false);
  assert.deepEqual(failures, ['Channel tune timed out.']);
  assert.equal(await controller.activate(target), true);
  assert.deepEqual(accepted, [target.focusId]);
  assert.equal(calls, 2);
});
