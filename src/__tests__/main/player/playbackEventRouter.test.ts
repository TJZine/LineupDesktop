import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlayerEvent } from '../../../contracts/player.js';
import {
  createPlaybackEventRouter,
  type PlaybackEventRouterSchedulePort,
} from '../../../main/player/playbackEventRouter.js';
import { PlexPlaybackRuntime } from '../../../main/player/plexPlaybackRuntime.js';

class FakeScheduler implements PlaybackEventRouterSchedulePort {
  readonly callbacks = new Map<number, () => void>();
  readonly canceled: number[] = [];
  #nextHandle = 1;

  schedule(callback: () => void): unknown {
    const handle = this.#nextHandle;
    this.#nextHandle += 1;
    this.callbacks.set(handle, callback);
    return handle;
  }

  cancel(handle: unknown): void {
    if (typeof handle === 'number') {
      this.canceled.push(handle);
      this.callbacks.delete(handle);
    }
  }

  runNext(): void {
    const entry = this.callbacks.entries().next().value as [number, () => void] | undefined;
    assert.ok(entry, 'expected a scheduled router drain');
    this.callbacks.delete(entry[0]);
    entry[1]();
  }
}

function createRuntime(
  emitted: PlayerEvent[],
  requestId = 'request-1',
): PlexPlaybackRuntime {
  return new PlexPlaybackRuntime({
    scheduler: {
      async getCurrentPlayback() {
        return { channelId: 'channel-1', programId: 'program-1', startedAtMs: 1_000 };
      },
    },
    channel: {
      async resolvePlaybackCandidate() {
        return {
          requestId,
          load: {
            media: { id: 'media-1', title: 'Episode 1' },
            policy: { autoplay: true },
          },
        };
      },
    },
    player: {
      async dispatch() {
        return { ok: true };
      },
      async cleanup() {},
    },
    pms: {
      async releaseSession() {},
    },
    onEvents: (events) => emitted.push(...events),
  });
}

function timeEvent(positionMs: number, requestId = 'request-1'): PlayerEvent {
  return {
    event: 'time.updated',
    requestId,
    positionMs,
    durationMs: 60_000,
  };
}

test('playback event router defers async batches to preserve synchronous causal order', async () => {
  const emitted: PlayerEvent[] = [];
  const runtime = createRuntime(emitted);
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  const scheduler = new FakeScheduler();
  const router = createPlaybackEventRouter({
    getRuntime: () => runtime,
    scheduler,
  });
  const synchronous = timeEvent(1_000);
  emitted.push(synchronous);

  router.route([timeEvent(2_000)]);
  await Promise.resolve();

  assert.deepEqual(emitted, [synchronous]);
  assert.equal(scheduler.callbacks.size, 1);

  scheduler.runNext();
  assert.deepEqual(emitted, [synchronous, timeEvent(2_000)]);
  assert.equal(scheduler.callbacks.size, 0);
});

test('playback event router drains queued batches once in FIFO order', async () => {
  const emitted: PlayerEvent[] = [];
  const runtime = createRuntime(emitted);
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  const scheduler = new FakeScheduler();
  const router = createPlaybackEventRouter({
    getRuntime: () => runtime,
    scheduler,
  });

  router.route([timeEvent(1_000)]);
  router.route([timeEvent(2_000), timeEvent(3_000)]);
  assert.equal(scheduler.callbacks.size, 1);

  scheduler.runNext();

  assert.deepEqual(emitted, [
    timeEvent(1_000),
    timeEvent(2_000),
    timeEvent(3_000),
  ]);
});

test('playback event router drops entries captured for a replaced runtime', async () => {
  const firstEvents: PlayerEvent[] = [];
  const secondEvents: PlayerEvent[] = [];
  const first = createRuntime(firstEvents, 'request-1');
  const second = createRuntime(secondEvents, 'request-2');
  await first.startCurrentPlayback('startup');
  await second.startCurrentPlayback('startup');
  firstEvents.length = 0;
  secondEvents.length = 0;
  let current: PlexPlaybackRuntime | null = first;
  const diagnostics: string[] = [];
  const scheduler = new FakeScheduler();
  const router = createPlaybackEventRouter({
    getRuntime: () => current,
    scheduler,
    reportDiagnostic: (message) => diagnostics.push(message),
  });
  router.route([timeEvent(1_000)]);
  current = second;

  scheduler.runNext();

  assert.deepEqual(firstEvents, []);
  assert.deepEqual(secondEvents, []);
  assert.deepEqual(diagnostics, [
    'Asynchronous player events targeted a replaced playback runtime',
  ]);
});

test('playback event router leaves stale request rejection to current runtime custody', async () => {
  const emitted: PlayerEvent[] = [];
  const runtime = createRuntime(emitted);
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  const scheduler = new FakeScheduler();
  const router = createPlaybackEventRouter({
    getRuntime: () => runtime,
    scheduler,
  });

  router.route([timeEvent(1_000, 'request-stale')]);
  scheduler.runNext();

  assert.equal(emitted.length, 1);
  assert.equal(emitted[0]?.event, 'warning');
});

test('playback event router flushes current runtime synchronously and exactly once', async () => {
  const emitted: PlayerEvent[] = [];
  const runtime = createRuntime(emitted);
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  const scheduler = new FakeScheduler();
  const router = createPlaybackEventRouter({
    getRuntime: () => runtime,
    scheduler,
  });
  router.route([timeEvent(4_000)]);

  router.flushCurrentRuntime();

  assert.deepEqual(emitted, [timeEvent(4_000)]);
  assert.equal(scheduler.callbacks.size, 0);
  assert.deepEqual(scheduler.canceled, [1]);
  router.flushCurrentRuntime();
  assert.deepEqual(emitted, [timeEvent(4_000)]);
});

test('playback event router dispose is idempotent and prevents future delivery', async () => {
  const emitted: PlayerEvent[] = [];
  const runtime = createRuntime(emitted);
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  const scheduler = new FakeScheduler();
  const diagnostics: string[] = [];
  const router = createPlaybackEventRouter({
    getRuntime: () => runtime,
    scheduler,
    reportDiagnostic: (message) => diagnostics.push(message),
  });
  router.route([timeEvent(1_000)]);

  router.dispose();
  router.dispose();
  router.route([timeEvent(2_000)]);
  router.flushCurrentRuntime();

  assert.deepEqual(emitted, []);
  assert.equal(scheduler.callbacks.size, 0);
  assert.deepEqual(scheduler.canceled, [1]);
  assert.deepEqual(diagnostics, [
    'Asynchronous player events arrived after router disposal',
  ]);
});

test('playback event router drops early batches with a safe diagnostic', () => {
  const diagnostics: Array<{ message: string; error: unknown }> = [];
  const router = createPlaybackEventRouter({
    getRuntime: () => null,
    scheduler: new FakeScheduler(),
    reportDiagnostic: (message, error) => diagnostics.push({ message, error }),
  });

  router.route([{ event: 'ended', requestId: 'request-early' }]);

  assert.equal(diagnostics.length, 1);
  assert.equal(
    diagnostics[0]?.message,
    'Asynchronous player events arrived before playback runtime composition',
  );
  assert.equal(
    (diagnostics[0]?.error as Error).message,
    'Playback event batch dropped',
  );
});
