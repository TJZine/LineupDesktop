import test from 'node:test';
import assert from 'node:assert/strict';

import type {
  ScheduledProgram,
  SchedulerState,
} from '../../../domain/scheduler/index.js';
import {
  PlaybackProgramTransitionOwner,
} from '../../../main/player/playbackProgramTransitionOwner.js';
import type { PlexPlaybackRuntimeStartResult } from '../../../main/player/plexPlaybackRuntime.js';

class FakeScheduler {
  readonly listeners = new Set<(program: ScheduledProgram) => void>();
  readonly first = program('first', 0);
  readonly second = program('second', 10_000);
  current = this.first;
  next = this.second;
  emitOnSkip = true;
  skipCalls = 0;

  getState(): SchedulerState {
    return {
      channelId: 'channel-1',
      isActive: true,
      currentProgram: this.current,
      nextProgram: this.next,
      schedulePosition: {
        loopNumber: this.current.loopNumber,
        itemIndex: this.current.scheduleIndex,
        offsetMs: 0,
      },
      lastSyncTime: 0,
    };
  }

  getNextProgram(): ScheduledProgram {
    return this.next;
  }

  skipToNext(): void {
    this.skipCalls += 1;
    if (!this.emitOnSkip) {
      return;
    }
    const previous = this.current;
    this.current = this.next;
    this.next = previous;
    for (const listener of [...this.listeners]) {
      listener(this.current);
    }
  }

  on(
    _event: 'programStart',
    listener: (program: ScheduledProgram) => void,
  ): void {
    this.listeners.add(listener);
  }

  off(
    _event: 'programStart',
    listener: (program: ScheduledProgram) => void,
  ): void {
    this.listeners.delete(listener);
  }

  emit(programValue = this.current): void {
    for (const listener of [...this.listeners]) {
      listener(programValue);
    }
  }
}

test('skip registers pending before synchronous emission and awaits one runtime start', async () => {
  const scheduler = new FakeScheduler();
  const start = deferred<PlexPlaybackRuntimeStartResult>();
  let starts = 0;
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: () => {
        starts += 1;
        return start.promise;
      },
      retryCurrentPlayback: async () => true,
    },
  });

  const result = owner.skipNext();
  await Promise.resolve();

  assert.equal(scheduler.skipCalls, 1);
  assert.equal(starts, 1);
  let settled = false;
  void result.then(() => {
    settled = true;
  });
  await Promise.resolve();
  assert.equal(settled, false);

  start.resolve(startResult(true));
  assert.deepEqual(await result, { accepted: true });
  assert.equal(starts, 1);
  owner.dispose();
});

test('skip fails when no program event occurs and concurrent work is busy', async () => {
  const scheduler = new FakeScheduler();
  scheduler.emitOnSkip = false;
  const retry = deferred<boolean>();
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: async () => startResult(true),
      retryCurrentPlayback: () => retry.promise,
    },
  });

  const pendingRetry = owner.retryCurrent();
  assert.deepEqual(await owner.skipNext(), {
    accepted: false,
    reason: 'busy',
  });
  retry.resolve(true);
  assert.deepEqual(await pendingRetry, { accepted: true });

  assert.deepEqual(await owner.skipNext(), {
    accepted: false,
    reason: 'stale',
  });
  owner.dispose();
});

test('new program event invalidates retry and starts authoritative playback once', async () => {
  const scheduler = new FakeScheduler();
  const retry = deferred<boolean>();
  let starts = 0;
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: async () => {
        starts += 1;
        return startResult(true);
      },
      retryCurrentPlayback: () => retry.promise,
    },
  });
  const pending = owner.retryCurrent();
  scheduler.current = scheduler.second;
  scheduler.emit();

  assert.deepEqual(await pending, { accepted: false, reason: 'stale' });
  await Promise.resolve();
  assert.equal(starts, 1);
  retry.resolve(true);
  owner.dispose();
  assert.equal(scheduler.listeners.size, 0);
});

test('invalidation settles Retry stale and releases custody for a later action', async () => {
  const scheduler = new FakeScheduler();
  const firstRetry = deferred<boolean>();
  const expectedSelections: unknown[] = [];
  let retryCalls = 0;
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: async () => startResult(true),
      retryCurrentPlayback: async (expectedSelection) => {
        expectedSelections.push(expectedSelection);
        retryCalls += 1;
        return retryCalls === 1 ? firstRetry.promise : true;
      },
    },
  });

  const pending = owner.retryCurrent();
  owner.invalidate();

  assert.deepEqual(await pending, { accepted: false, reason: 'stale' });
  assert.deepEqual(expectedSelections[0], {
    channelId: 'channel-1',
    programId: 'program-channel-1-first-0-10000',
    startedAtMs: 0,
    endsAtMs: 10_000,
  });
  assert.deepEqual(await owner.retryCurrent(), { accepted: true });
  firstRetry.resolve(true);
  owner.dispose();
});

test('invalidation settles an attached Skip stale and releases busy custody', async () => {
  const scheduler = new FakeScheduler();
  const start = deferred<PlexPlaybackRuntimeStartResult>();
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: () => start.promise,
      retryCurrentPlayback: async () => true,
    },
  });

  const pending = owner.skipNext();
  await Promise.resolve();
  owner.invalidate();

  assert.deepEqual(await pending, { accepted: false, reason: 'stale' });
  assert.deepEqual(await owner.retryCurrent(), { accepted: true });
  start.resolve(startResult(true));
  owner.dispose();
});

test('nested cleanup holds reject actions, drop program starts, and reopen only after final release', async () => {
  const scheduler = new FakeScheduler();
  const firstRetry = deferred<boolean>();
  const diagnostics: string[] = [];
  let retryCalls = 0;
  let starts = 0;
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: async () => {
        starts += 1;
        return startResult(true);
      },
      retryCurrentPlayback: () => {
        retryCalls += 1;
        return retryCalls === 1 ? firstRetry.promise : Promise.resolve(true);
      },
    },
    reportDiagnostic: (message) => diagnostics.push(message),
  });

  const pendingRetry = owner.retryCurrent();
  const releaseOldest = owner.acquireCleanupHold();
  owner.invalidate();
  const releaseNewest = owner.acquireCleanupHold();

  assert.deepEqual(await pendingRetry, { accepted: false, reason: 'stale' });
  assert.deepEqual(await owner.retryCurrent(), {
    accepted: false,
    reason: 'busy',
  });
  assert.deepEqual(await owner.skipNext(), {
    accepted: false,
    reason: 'busy',
  });
  assert.equal(scheduler.skipCalls, 0);

  scheduler.current = scheduler.second;
  scheduler.emit();
  assert.equal(starts, 0);
  assert.deepEqual(diagnostics, [
    'Scheduler playback transition was dropped during cleanup',
  ]);

  releaseNewest();
  releaseNewest();
  assert.deepEqual(await owner.retryCurrent(), {
    accepted: false,
    reason: 'busy',
  });
  releaseOldest();
  assert.equal(starts, 0);

  assert.deepEqual(await owner.retryCurrent(), { accepted: true });
  assert.equal(retryCalls, 2);
  scheduler.emit();
  await Promise.resolve();
  assert.equal(starts, 1);

  firstRetry.resolve(true);
  owner.dispose();
});

test('cleanup hold settles attached Skip stale and disposal remains terminal after release', async () => {
  const scheduler = new FakeScheduler();
  const start = deferred<PlexPlaybackRuntimeStartResult>();
  const owner = new PlaybackProgramTransitionOwner({
    scheduler,
    runtime: {
      startCurrentPlayback: () => start.promise,
      retryCurrentPlayback: async () => true,
    },
  });

  const pendingSkip = owner.skipNext();
  await Promise.resolve();
  const releaseCleanupHold = owner.acquireCleanupHold();
  owner.invalidate();

  assert.deepEqual(await pendingSkip, { accepted: false, reason: 'stale' });
  assert.deepEqual(await owner.skipNext(), {
    accepted: false,
    reason: 'busy',
  });
  owner.dispose();
  releaseCleanupHold();
  releaseCleanupHold();
  owner.acquireCleanupHold()();
  assert.deepEqual(await owner.retryCurrent(), {
    accepted: false,
    reason: 'unavailable',
  });

  start.resolve(startResult(true));
});

function program(ratingKey: string, start: number): ScheduledProgram {
  return {
    item: {
      ratingKey,
      type: 'movie',
      title: ratingKey,
      fullTitle: ratingKey,
      durationMs: 10_000,
      thumb: null,
      year: null,
      scheduledIndex: start / 10_000,
    },
    scheduledStartTime: start,
    scheduledEndTime: start + 10_000,
    elapsedMs: 0,
    remainingMs: 10_000,
    scheduleIndex: start / 10_000,
    loopNumber: 0,
    streamDescriptor: null,
    isCurrent: true,
  };
}

function startResult(accepted: boolean): PlexPlaybackRuntimeStartResult {
  return {
    accepted,
    epoch: 1,
    requestId: accepted ? 'request-1' : null,
    events: [],
  };
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
