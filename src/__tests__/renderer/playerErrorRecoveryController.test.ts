import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlayerRecoveryIpcResult } from '../../contracts/shell.js';
import { createEmptyPlayerSnapshot } from '../../renderer/playerOverlayPresentation.js';
import { createPlayerErrorRecoveryController } from '../../renderer/playerErrorRecoveryController.js';
import { createPlayerOverlayState } from '../../renderer/overlays.js';

test('renderer recovery owner serializes actions and applies accepted snapshot', async () => {
  const pending = deferred<PlayerRecoveryIpcResult>();
  let state = createPlayerOverlayState();
  let acceptedStatus = 'error';
  const acceptedSnapshots: string[] = [];
  const settlementTrace: string[] = [];
  const timers = new FakeTimers();
  const controller = createPlayerErrorRecoveryController({
    bridge: { recover: () => pending.promise },
    host: timers,
    getState: () => state,
    setState: (next) => {
      state = next;
      settlementTrace.push('state');
    },
    acceptSnapshot: (snapshot) => {
      acceptedSnapshots.push(snapshot.status);
      acceptedStatus = snapshot.status;
      settlementTrace.push(`snapshot:${snapshot.status}`);
    },
    render: () => {
      settlementTrace.push(`render:${acceptedStatus}`);
    },
    focus: (focusId) => {
      settlementTrace.push(`focus:${String(focusId)}`);
    },
  });

  assert.equal(controller.retry(), true);
  assert.equal(controller.skip(), false);
  assert.equal(state.recoveryPendingAction, 'retry-current');
  settlementTrace.length = 0;

  pending.resolve({
    ok: true,
    requestId: 'recovery-1',
    value: {
      status: 'accepted',
      snapshot: { ...createEmptyPlayerSnapshot(), status: 'loading' },
    },
  });
  await flush();

  assert.equal(state.recoveryPendingAction, null);
  assert.equal(state.retryTransitionActive, true);
  assert.deepEqual(acceptedSnapshots, ['loading']);
  assert.deepEqual(settlementTrace, [
    'state',
    'snapshot:loading',
    'render:loading',
    'focus:null',
  ]);
  controller.dispose();
});

test('renderer recovery owner sanitizes failure, restores focus, and times out', async () => {
  let state = createPlayerOverlayState();
  const focus: Array<string | null> = [];
  const timers = new FakeTimers();
  const controller = createPlayerErrorRecoveryController({
    bridge: { recover: () => new Promise(() => undefined) },
    host: timers,
    getState: () => state,
    setState: (next) => {
      state = next;
    },
    acceptSnapshot: () => undefined,
    render: () => undefined,
    focus: (focusId) => {
      focus.push(focusId);
    },
  });

  assert.equal(controller.skip(), true);
  assert.equal(controller.retry(), false);
  timers.runAll();

  assert.equal(state.retryError, 'Player recovery timed out.');
  assert.equal(state.recoveryPendingAction, null);
  assert.equal(focus.at(-1), 'overlay-player-skip');
  controller.dispose();
});

test('timed-out recovery settlements cannot resurrect state, snapshot, focus, or render', async () => {
  for (const lateResult of [
    {
      ok: true,
      requestId: 'late-accepted',
      value: {
        status: 'accepted',
        snapshot: { ...createEmptyPlayerSnapshot(), status: 'loading' },
      },
    },
    {
      ok: false,
      requestId: 'late-failed',
      value: {
        status: 'failed',
        snapshot: createEmptyPlayerSnapshot(),
      },
      error: {
        code: 'PLAYER_RECOVERY_UNAVAILABLE',
        category: 'unknown',
        message: 'Late failure.',
        recoverable: true,
        retryable: true,
        requestId: 'late-failed',
      },
    },
  ] satisfies PlayerRecoveryIpcResult[]) {
    const pending = deferred<PlayerRecoveryIpcResult>();
    let state = createPlayerOverlayState();
    let acceptedSnapshots = 0;
    let renders = 0;
    const focus: Array<string | null> = [];
    const timers = new FakeTimers();
    const controller = createPlayerErrorRecoveryController({
      bridge: { recover: () => pending.promise },
      host: timers,
      getState: () => state,
      setState: (next) => {
        state = next;
      },
      acceptSnapshot: () => {
        acceptedSnapshots += 1;
      },
      render: () => {
        renders += 1;
      },
      focus: (focusId) => {
        focus.push(focusId);
      },
    });

    assert.equal(controller.retry(), true);
    timers.runAll();
    const terminalState = state;
    const terminalRenders = renders;
    const terminalFocus = [...focus];

    pending.resolve(lateResult);
    await flush();

    assert.equal(state, terminalState);
    assert.equal(state.retryError, 'Player recovery timed out.');
    assert.equal(acceptedSnapshots, 0);
    assert.equal(renders, terminalRenders);
    assert.deepEqual(focus, terminalFocus);
    controller.dispose();
  }
});

class FakeTimers {
  readonly callbacks = new Map<number, () => void>();
  #next = 1;
  setTimeout(callback: () => void): number {
    const handle = this.#next;
    this.#next += 1;
    this.callbacks.set(handle, callback);
    return handle;
  }
  clearTimeout(handle: number): void {
    this.callbacks.delete(handle);
  }
  runAll(): void {
    for (const callback of [...this.callbacks.values()]) {
      callback();
    }
    this.callbacks.clear();
  }
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve(value: T): void;
} {
  let resolve = (_value: T): void => undefined;
  const promise = new Promise<T>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}
