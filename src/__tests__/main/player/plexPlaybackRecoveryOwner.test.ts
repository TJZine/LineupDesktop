import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlayerEvent, PlayerSnapshot } from '../../../contracts/player.js';
import {
  PlexPlaybackRecoveryOwner,
  type PlexPlaybackRecoveryAttemptResult,
  type PlexPlaybackRecoveryIdentity,
  type PlexPlaybackRecoveryTimerPort,
} from '../../../main/player/plexPlaybackRecoveryOwner.js';

const identity: PlexPlaybackRecoveryIdentity = {
  channelId: 'channel-1',
  programId: 'program-1',
  startedAtMs: 1_000,
};

class FakeTimer implements PlexPlaybackRecoveryTimerPort {
  readonly delays: number[] = [];
  readonly cleared: unknown[] = [];
  readonly pending = new Map<number, () => void>();
  #nextHandle = 1;

  set(delayMs: number, callback: () => void): unknown {
    const handle = this.#nextHandle;
    this.#nextHandle += 1;
    this.delays.push(delayMs);
    this.pending.set(handle, callback);
    return handle;
  }

  clear(handle: unknown): void {
    this.cleared.push(handle);
    if (typeof handle === 'number') {
      this.pending.delete(handle);
    }
  }

  async runNext(): Promise<void> {
    const entry = this.pending.entries().next().value as [number, () => void] | undefined;
    assert.ok(entry, 'expected a pending recovery timer');
    this.pending.delete(entry[0]);
    entry[1]();
    await Promise.resolve();
    await Promise.resolve();
  }
}

function eligibleError(
  requestId = 'request-1',
): Extract<PlayerEvent, { event: 'error' }> {
  return {
    event: 'error',
    requestId,
    error: {
      code: 'PLAYER_HOST_ENGINE_FAILURE',
      category: 'engine-failure',
      message: 'The player engine failed.',
      recoverable: true,
      retryable: true,
      requestId,
    },
  };
}

function playingEvent(requestId = 'request-1'): PlayerEvent {
  const snapshot: PlayerSnapshot = {
    requestId,
    status: 'playing',
    media: { id: 'media-1', title: 'Episode 1' },
    capabilityProfileId: 'desktop-test',
    seekSupport: 'supported',
    positionMs: 0,
    durationMs: 60_000,
    bufferedRanges: [],
    playing: true,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    quality: {
      mode: 'unknown',
      sourceDynamicRange: 'unknown',
      outputDynamicRangeStatus: 'unknown',
    },
    lastError: null,
  };
  return { event: 'state.changed', requestId, snapshot };
}

test('playback recovery uses one identity budget with exact delays and no fourth attempt', async () => {
  const timer = new FakeTimer();
  const attempts: PlexPlaybackRecoveryIdentity[] = [];
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: async (nextIdentity) => {
      attempts.push(nextIdentity);
      return 'failed';
    },
  });
  owner.activate(identity);
  owner.observeAcceptedEvent(identity, eligibleError());

  await timer.runNext();
  await timer.runNext();
  await timer.runNext();

  assert.deepEqual(timer.delays, [1_000, 2_000, 4_000]);
  assert.equal(attempts.length, 3);
  assert.equal(owner.getAttemptCount(), 3);
  assert.equal(timer.pending.size, 0);

  owner.observeAcceptedEvent(identity, eligibleError());
  assert.equal(timer.pending.size, 0);
});

test('playback recovery resets the same identity budget after authoritative playing', async () => {
  const timer = new FakeTimer();
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: async () => 'started',
  });
  owner.activate(identity);
  owner.observeAcceptedEvent(identity, eligibleError());
  await timer.runNext();
  assert.equal(owner.getAttemptCount(), 1);

  owner.observeAcceptedEvent(identity, playingEvent());
  assert.equal(owner.getAttemptCount(), 0);
  owner.observeAcceptedEvent(identity, eligibleError('request-2'));

  assert.deepEqual(timer.delays, [1_000, 1_000]);
});

test('playback recovery cancels stale timers and ignores stale completions', async () => {
  const timer = new FakeTimer();
  let settleAttempt = (_result: PlexPlaybackRecoveryAttemptResult): void => {
    throw new Error('Recovery attempt was not started.');
  };
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: () => new Promise((resolve) => {
      settleAttempt = resolve;
    }),
  });
  owner.activate(identity);
  owner.observeAcceptedEvent(identity, eligibleError());
  const staleTimerHandle = [...timer.pending.keys()][0];

  owner.activate({ ...identity, programId: 'program-2' });
  assert.deepEqual(timer.cleared, [staleTimerHandle]);
  assert.equal(timer.pending.size, 0);

  const replacement = { ...identity, programId: 'program-3' };
  owner.activate(replacement);
  owner.observeAcceptedEvent(replacement, eligibleError('request-3'));
  const running = timer.runNext();
  await Promise.resolve();
  owner.cancel();
  const latest = { ...identity, programId: 'program-4' };
  owner.activate(latest);
  owner.observeAcceptedEvent(latest, eligibleError('request-4'));
  assert.equal(timer.pending.size, 1);
  settleAttempt('failed');
  await running;
  await Promise.resolve();

  assert.equal(timer.pending.size, 1);
  owner.cancel();
  assert.equal(timer.pending.size, 0);
  assert.equal(owner.getAttemptCount(), 0);
});

test('playback recovery ignores errors outside the exact safe eligibility gate', () => {
  const timer = new FakeTimer();
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: async () => 'started',
  });
  owner.activate(identity);

  for (const event of [
    {
      ...eligibleError(),
      error: { ...eligibleError().error, retryable: false },
    },
    {
      ...eligibleError(),
      error: {
        ...eligibleError().error,
        code: 'PLAYER_HOST_NETWORK_FAILURE',
        category: 'network' as const,
      },
    },
  ] satisfies PlayerEvent[]) {
    owner.observeAcceptedEvent(identity, event);
  }

  assert.deepEqual(timer.delays, []);
});

test('playback recovery latches an eligible error during a provisional started attempt', async () => {
  const timer = new FakeTimer();
  let settle = (_result: PlexPlaybackRecoveryAttemptResult): void => {
    throw new Error('retry was not started');
  };
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: () => new Promise((resolve) => {
      settle = resolve;
    }),
  });
  owner.activate(identity);
  owner.observeAcceptedEvent(identity, eligibleError());
  await timer.runNext();

  owner.observeAcceptedEvent(identity, eligibleError('request-retry'));
  settle('started');
  await Promise.resolve();
  await Promise.resolve();

  assert.deepEqual(timer.delays, [1_000, 2_000]);
  assert.equal(timer.pending.size, 1);
});

test('playback recovery playing observation clears an in-flight failure latch', async () => {
  const timer = new FakeTimer();
  let settle = (_result: PlexPlaybackRecoveryAttemptResult): void => {
    throw new Error('retry was not started');
  };
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: () => new Promise((resolve) => {
      settle = resolve;
    }),
  });
  owner.activate(identity);
  owner.observeAcceptedEvent(identity, eligibleError());
  await timer.runNext();

  owner.observeAcceptedEvent(identity, eligibleError('request-retry'));
  owner.observeAcceptedEvent(identity, playingEvent('request-retry'));
  settle('failed');
  await Promise.resolve();
  await Promise.resolve();

  assert.deepEqual(timer.delays, [1_000]);
  assert.equal(timer.pending.size, 0);
  assert.equal(owner.getAttemptCount(), 0);
});

test('playback recovery failed result plus latched error schedules only one next delay', async () => {
  const timer = new FakeTimer();
  let settle = (_result: PlexPlaybackRecoveryAttemptResult): void => {
    throw new Error('retry was not started');
  };
  const owner = new PlexPlaybackRecoveryOwner({
    timer,
    retry: () => new Promise((resolve) => {
      settle = resolve;
    }),
  });
  owner.activate(identity);
  owner.observeAcceptedEvent(identity, eligibleError());
  await timer.runNext();

  owner.observeAcceptedEvent(identity, eligibleError('request-retry'));
  settle('failed');
  await Promise.resolve();
  await Promise.resolve();

  assert.deepEqual(timer.delays, [1_000, 2_000]);
  assert.equal(timer.pending.size, 1);
});
