import assert from 'node:assert/strict';
import test from 'node:test';
import type { PlayerSnapshot } from '../../contracts/player.js';
import {
  createSleepTimerController,
  createSleepTimerProjection,
  type SleepTimerProjection,
} from '../../renderer/sleepTimerController.js';
import type {
  DeferredPauseResult,
  PauseCurrentResult,
} from '../../renderer/playerInputCommandController.js';

test('sleep presets cycle Off through 15/30/60/120 and back to Off', () => {
  const harness = createHarness();
  assert.deepEqual(
    [
      harness.controller.cyclePreset(),
      harness.controller.cyclePreset(),
      harness.controller.cyclePreset(),
      harness.controller.cyclePreset(),
      harness.controller.cyclePreset(),
    ],
    [15, 30, 60, 120, null],
  );
  assert.deepEqual(harness.projection(), createSleepTimerProjection());
  assert.equal(harness.pendingTimers(), 0);
});

test('replacement resets the deadline and countdown stays deadline-derived and monotonic', () => {
  const harness = createHarness();
  harness.controller.cyclePreset();
  harness.advance(5_000);
  assert.equal(harness.projection().remainingMs, 15 * 60_000 - 5_000);

  harness.controller.cyclePreset();
  assert.equal(harness.projection().remainingMs, 30 * 60_000);
  harness.setNow(harness.now() - 10_000);
  harness.fireNext();
  assert.equal(harness.projection().remainingMs, 30 * 60_000);
});

test('one-minute warning occurs once and expiry pauses only the current playing request', () => {
  const harness = createHarness();
  harness.controller.cyclePreset();
  harness.advance(14 * 60_000);
  assert.equal(harness.projection().status, 'warning');
  assert.match(harness.projection().message, /under 1 minute/u);
  const warningRenders = harness.renders();
  harness.advance(30_000);
  assert.equal(harness.projection().status, 'warning');
  assert.ok(harness.renders() > warningRenders);
  harness.advance(30_000);
  assert.deepEqual(harness.pauses(), ['request-one']);
  assert.equal(harness.projection().status, 'expired');
  assert.equal(harness.pendingTimers(), 0);
});

test('stale or already-paused playback is never paused at expiry', () => {
  const paused = createHarness({ requestId: 'request-one', status: 'paused', playing: false });
  paused.controller.cyclePreset();
  paused.advance(15 * 60_000);
  assert.deepEqual(paused.pauses(), []);

  const missing = createHarness({ requestId: null, status: 'playing', playing: true });
  missing.controller.cyclePreset();
  missing.advance(15 * 60_000);
  assert.deepEqual(missing.pauses(), []);
});

test('rejected guarded pause reports bounded feedback without retry or timer resurrection', () => {
  const harness = createHarness(undefined, 'rejected');
  harness.controller.cyclePreset();
  harness.advance(15 * 60_000);
  assert.equal(harness.projection().status, 'failed');
  assert.deepEqual(harness.diagnostics(), ['player.sleep-timer:Sleep timer pause was not accepted.']);
  assert.equal(harness.pendingTimers(), 0);
});

test('deferred guarded pause remains pending and ignores a resolution after cancellation', () => {
  const harness = createHarness(undefined, 'deferred');
  harness.controller.cyclePreset();
  harness.advance(15 * 60_000);
  assert.equal(harness.projection().status, 'expiring');
  assert.deepEqual(harness.diagnostics(), []);

  harness.controller.cancel();
  harness.resolveDeferred('started');
  assert.equal(harness.projection().status, 'off');
  assert.deepEqual(harness.diagnostics(), []);
});

test('cancel and cleanup remove the owned timeout and cleanup is terminal', () => {
  const harness = createHarness();
  harness.controller.cyclePreset();
  harness.controller.cancel();
  assert.equal(harness.pendingTimers(), 0);
  harness.controller.cyclePreset();
  harness.controller.cleanup();
  assert.equal(harness.pendingTimers(), 0);
  assert.equal(harness.controller.cyclePreset(), null);
  harness.advance(20 * 60_000);
  assert.deepEqual(harness.pauses(), []);
});

function createHarness(
  playback: Pick<PlayerSnapshot, 'requestId' | 'status' | 'playing'> = {
    requestId: 'request-one', status: 'playing', playing: true,
  },
  pauseResult: PauseCurrentResult = 'started',
) {
  let nowMs = 1_000_000;
  let projection: SleepTimerProjection = createSleepTimerProjection();
  let timerId = 0;
  const timers = new Map<number, { callback: () => void; dueAt: number }>();
  const pauses: string[] = [];
  const diagnostics: string[] = [];
  let deferredResolution: ((result: DeferredPauseResult) => void) | null = null;
  let renderCount = 0;
  const controller = createSleepTimerController({
    host: {
      setTimeout(callback, delayMs) {
        const id = ++timerId;
        timers.set(id, { callback, dueAt: nowMs + delayMs });
        return id;
      },
      clearTimeout(id) { timers.delete(id); },
    },
    now: () => nowMs,
    getProjection: () => projection,
    setProjection: (next) => { projection = next; },
    render: () => { renderCount += 1; },
    getCurrentPlayback: () => playback,
    pauseCurrent: (requestId, onDeferredResolved) => {
      pauses.push(requestId);
      if (pauseResult === 'deferred') {
        assert.ok(onDeferredResolved);
        deferredResolution = onDeferredResolved;
      }
      return pauseResult;
    },
    cancelDeferredPause: () => {
      deferredResolution = null;
    },
    recordDiagnostic: (operation, message) => { diagnostics.push(`${operation}:${message}`); },
  });

  return {
    controller,
    projection: () => projection,
    pauses: () => pauses,
    diagnostics: () => diagnostics,
    renders: () => renderCount,
    pendingTimers: () => timers.size,
    now: () => nowMs,
    setNow: (value: number) => { nowMs = value; },
    fireNext: () => {
      const next = [...timers.entries()].sort((left, right) => left[1].dueAt - right[1].dueAt)[0];
      if (next !== undefined) {
        timers.delete(next[0]);
        next[1].callback();
      }
    },
    resolveDeferred: (result: DeferredPauseResult) => {
      const resolve = deferredResolution;
      deferredResolution = null;
      resolve?.(result);
    },
    advance: (deltaMs: number) => {
      const target = nowMs + deltaMs;
      while (true) {
        const next = [...timers.entries()]
          .filter(([, item]) => item.dueAt <= target)
          .sort((left, right) => left[1].dueAt - right[1].dueAt)[0];
        if (next === undefined) break;
        nowMs = next[1].dueAt;
        timers.delete(next[0]);
        next[1].callback();
      }
      nowMs = target;
    },
  };
}
