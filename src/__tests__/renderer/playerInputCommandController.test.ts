import assert from 'node:assert/strict';
import test from 'node:test';

import type {
  PlayerEvent,
  PlayerSnapshot,
} from '../../contracts/player.js';
import type { PlayerRendererIntentEnvelope } from '../../contracts/ipc.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import {
  createPlayerInputCommandController,
  type PlayerInputCommandTimerHost,
} from '../../renderer/playerInputCommandController.js';
import {
  createSleepTimerController,
  createSleepTimerProjection,
  type SleepTimerProjection,
} from '../../renderer/sleepTimerController.js';

test('direct input dispatches only guarded current-request commands with exact payloads', async () => {
  const harness = createHarness(playingSnapshot());

  assert.equal(harness.controller.handleInput('space'), true);
  await flush();
  assertEnvelope(harness.envelopes[0], 'player.pauseIfCurrent', {
    snapshotRequestId: 'playback-1',
  });
  settleCurrent(harness, 'pause');

  harness.setSnapshot({ ...playingSnapshot(), status: 'paused', playing: false });
  harness.controller.handleInput('mediaPlayPause');
  await flush();
  assertEnvelope(harness.envelopes[1], 'player.playIfCurrent', {
    snapshotRequestId: 'playback-1',
  });
  settleCurrent(harness, 'play');

  harness.controller.handleInput('mediaRewind');
  await flush();
  assertEnvelope(harness.envelopes[2], 'player.seekRelativeIfCurrent', {
    snapshotRequestId: 'playback-1',
    deltaMs: -10_000,
  });
  settleCurrent(harness, 'seek.relative');

  harness.controller.handleInput('mediaFastForward');
  await flush();
  assert.deepEqual(harness.envelopes[3]?.payload, {
    snapshotRequestId: 'playback-1',
    deltaMs: 10_000,
  });
  settleCurrent(harness, 'seek.relative');

  harness.controller.handleInput('mediaStop');
  await flush();
  assertEnvelope(harness.envelopes[4], 'player.stopIfCurrent', {
    snapshotRequestId: 'playback-1',
  });
  assert.equal(harness.envelopes.some((envelope) =>
    envelope.intent === 'player.stop' || envelope.intent === 'player.seekRelative'), false);
});

test('seek requires exact supported projection and blocked or ineligible input is inert', async () => {
  for (const seekSupport of ['unsupported', 'unknown', 'unproven'] as const) {
    const harness = createHarness({ ...playingSnapshot(), seekSupport });
    assert.equal(harness.controller.handleInput('mediaFastForward'), true);
    await flush();
    assert.deepEqual(harness.envelopes, []);
  }

  const blocked = createHarness(playingSnapshot());
  assert.equal(blocked.controller.handleInput('mediaStop', true), true);
  assert.equal(blocked.controller.handleInput('info'), false);
  await flush();
  assert.deepEqual(blocked.envelopes, []);

  blocked.setSnapshot({ ...playingSnapshot(), requestId: null });
  blocked.controller.handleInput('mediaPlay');
  blocked.controller.handleInput('mediaStop');
  await flush();
  assert.deepEqual(blocked.envelopes, []);
});

test('one pending command ignores mismatches and releases on timeout, stale snapshot, route leave, and cleanup', async () => {
  const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
  harness.controller.handleInput('space');
  harness.controller.handleInput('mediaStop');
  await flush();
  assert.equal(harness.envelopes.length, 1);

  harness.controller.handlePlayerEvent({
    event: 'command.settled',
    requestId: 'unmatched',
    command: 'pause',
    ok: true,
  });
  harness.controller.handleInput('mediaStop');
  assert.equal(harness.envelopes.length, 1);

  harness.timers.advance(30_000);
  assert.deepEqual(harness.diagnostics, ['Player command timed out.']);
  harness.controller.handleInput('mediaStop');
  await flush();
  assert.equal(harness.envelopes.length, 2);

  harness.controller.reconcileSnapshot({ ...playingSnapshot(), requestId: 'playback-2' }, true);
  harness.controller.handleInput('mediaStop');
  await flush();
  assert.equal(harness.envelopes.length, 3);

  harness.controller.routeLeave();
  harness.controller.handleInput('mediaStop');
  await flush();
  assert.equal(harness.envelopes.length, 4);

  harness.controller.cleanup();
  harness.timers.advance(30_000);
  assert.equal(harness.controller.handleInput('mediaStop'), false);
  assert.deepEqual(harness.diagnostics, ['Player command timed out.']);
});

test('inconsistent authoritative playback state fails safely without mutating semantic focus', async () => {
  for (const input of [
    'space',
    'mediaPlay',
    'mediaPause',
    'mediaPlayPause',
    'mediaRewind',
    'mediaFastForward',
    'mediaStop',
  ] as const) {
    const inconsistent = createHarness(
      { ...playingSnapshot(), status: 'playing', playing: false },
      { settleInDispatch: false },
    );
    assert.equal(inconsistent.controller.handleInput(input), true);
    await flush();
    assert.deepEqual(inconsistent.envelopes, [], `${input} dispatched from inconsistent state`);
    assert.deepEqual(inconsistent.diagnostics, ['Inconsistent player state ignored.']);
  }

  const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
  harness.setSnapshot(playingSnapshot());
  harness.controller.handleInput('space');
  await flush();
  harness.controller.reconcileSnapshot({ ...playingSnapshot(), playing: false }, true);
  assert.deepEqual(harness.diagnostics, ['Inconsistent player state ignored.']);
});

test('pauseCurrent starts exactly one guarded pause only for the exact current playing request', async () => {
  const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
  assert.equal(harness.controller.pauseCurrent('stale-request'), 'rejected');
  assert.equal(harness.controller.pauseCurrent('playback-1'), 'started');
  assert.equal(harness.controller.pauseCurrent('playback-1'), 'rejected');
  await flush();
  assertEnvelope(harness.envelopes[0], 'player.pauseIfCurrent', {
    snapshotRequestId: 'playback-1',
  });

  settleCurrent(harness, 'pause');
  harness.setSnapshot({ ...playingSnapshot(), status: 'paused', playing: false });
  assert.equal(harness.controller.pauseCurrent('playback-1'), 'rejected');
  harness.setSnapshot({ ...playingSnapshot(), playing: false });
  assert.equal(harness.controller.pauseCurrent('playback-1'), 'rejected');
  harness.setSnapshot({ ...playingSnapshot(), requestId: null });
  assert.equal(harness.controller.pauseCurrent('playback-1'), 'rejected');
  harness.controller.cleanup();
  harness.setSnapshot(playingSnapshot());
  assert.equal(harness.controller.pauseCurrent('playback-1'), 'rejected');
  assert.equal(harness.envelopes.length, 1);
});

test('sleep expiry defers once behind play or seek and pauses after settlement', async () => {
  for (const pending of ['play', 'seek'] as const) {
    const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
    const sleep = createSleepHarness(harness);
    sleep.controller.cyclePreset();
    harness.timers.advance(15 * 60_000 - 1_000);

    if (pending === 'play') {
      harness.setSnapshot({ ...playingSnapshot(), status: 'paused', playing: false });
      harness.controller.handleInput('mediaPlay');
      harness.setSnapshot(playingSnapshot());
    } else {
      harness.controller.handleInput('mediaFastForward');
    }
    await flush();
    assert.equal(harness.envelopes.length, 1, `${pending} initial custody`);

    harness.timers.advance(1_000);
    assert.equal(sleep.projection().status, 'expiring', `${pending} expiry status`);
    assert.deepEqual(sleep.diagnostics(), []);

    settleCurrent(harness, pending === 'play' ? 'play' : 'seek.relative');
    await flush();
    assert.equal(sleep.projection().status, 'expired', `${pending} settled expiry`);
    assert.equal(harness.envelopes.length, 2, `${pending} issued one deferred pause`);
    assertEnvelope(harness.envelopes[1], 'player.pauseIfCurrent', {
      snapshotRequestId: 'playback-1',
    });

    settleCurrent(harness, 'pause');
    await flush();
    assert.equal(harness.envelopes.length, 2, `${pending} pause was not retried`);
  }
});

test('sleep expiry defers behind play that began paused before playback becomes playing', async () => {
  const harness = createHarness(
    { ...playingSnapshot(), status: 'paused', playing: false },
    { settleInDispatch: false },
  );
  const sleep = createSleepHarness(harness);
  sleep.controller.cyclePreset();
  harness.timers.advance(15 * 60_000 - 1_000);
  harness.controller.handleInput('mediaPlay');
  await flush();

  harness.timers.advance(1_000);
  assert.equal(sleep.projection().status, 'expiring');
  assert.equal(harness.envelopes.length, 1);

  harness.setSnapshot(playingSnapshot());
  settleCurrent(harness, 'play');
  await flush();
  assert.equal(sleep.projection().status, 'expired');
  assertEnvelope(harness.envelopes[1], 'player.pauseIfCurrent', {
    snapshotRequestId: 'playback-1',
  });
});

test('sleep expiry rejects failed play and seek settlements without dispatching pause', async () => {
  for (const pending of ['play', 'seek'] as const) {
    const initial = pending === 'play'
      ? { ...playingSnapshot(), status: 'paused' as const, playing: false }
      : playingSnapshot();
    const harness = createHarness(initial, { settleInDispatch: false });
    const sleep = createSleepHarness(harness);
    sleep.controller.cyclePreset();
    harness.timers.advance(15 * 60_000 - 1_000);
    harness.controller.handleInput(pending === 'play' ? 'mediaPlay' : 'mediaFastForward');
    await flush();

    harness.timers.advance(1_000);
    assert.equal(sleep.projection().status, 'expiring');
    settleCurrent(harness, pending === 'play' ? 'play' : 'seek.relative', false);
    await flush();

    assert.equal(sleep.projection().status, 'failed');
    assert.equal(harness.envelopes.length, 1);
    assert.deepEqual(sleep.diagnostics(), ['Sleep timer pause was not accepted.']);
  }
});

test('sleep deferral requires the pending command snapshot to match the expiry request', async () => {
  const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
  harness.controller.handleInput('mediaFastForward');
  await flush();

  assert.equal(
    harness.controller.pauseCurrent('playback-2', () => assert.fail('must not defer')),
    'rejected',
  );
  settleCurrent(harness, 'seek.relative');
  await flush();
  assert.equal(harness.envelopes.length, 1);
});

test('sleep expiry rejects pending stop and invalidates deferred pause on route leave', async () => {
  for (const pending of ['play', 'seek', 'stop'] as const) {
    const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
    const sleep = createSleepHarness(harness);
    sleep.controller.cyclePreset();
    harness.timers.advance(15 * 60_000 - 1_000);

    if (pending === 'play') {
      harness.setSnapshot({ ...playingSnapshot(), status: 'paused', playing: false });
      harness.controller.handleInput('mediaPlay');
      harness.setSnapshot(playingSnapshot());
    } else {
      harness.controller.handleInput(pending === 'seek' ? 'mediaFastForward' : 'mediaStop');
    }
    await flush();
    assert.equal(harness.envelopes.length, 1, `${pending} initial custody`);

    harness.timers.advance(1_000);
    assert.equal(
      sleep.projection().status,
      pending === 'stop' ? 'failed' : 'expiring',
      `${pending} expiry status`,
    );
    assert.equal(harness.envelopes.length, 1, `${pending} no extra pause custody`);
    assert.deepEqual(
      sleep.diagnostics(),
      pending === 'stop' ? ['Sleep timer pause was not accepted.'] : [],
    );

    if (pending === 'stop') {
      settleCurrent(harness, 'stop');
    } else {
      harness.controller.routeLeave();
    }
    await flush();
    assert.equal(sleep.projection().status, 'failed', `${pending} late settlement`);
    assert.equal(harness.envelopes.length, 1, `${pending} no late retry`);
  }
});

test('canceling an expiring sleep timer prevents a later pause after command settlement', async () => {
  const harness = createHarness(playingSnapshot(), { settleInDispatch: false });
  const sleep = createSleepHarness(harness);
  sleep.controller.cyclePreset();
  harness.timers.advance(15 * 60_000 - 1_000);
  harness.controller.handleInput('mediaFastForward');
  await flush();
  harness.timers.advance(1_000);
  assert.equal(sleep.projection().status, 'expiring');

  sleep.controller.cancel();
  settleCurrent(harness, 'seek.relative');
  await flush();
  assert.equal(sleep.projection().status, 'off');
  assert.equal(harness.envelopes.length, 1);
});

interface Harness {
  controller: ReturnType<typeof createPlayerInputCommandController>;
  envelopes: PlayerRendererIntentEnvelope<unknown>[];
  diagnostics: string[];
  timers: FakeTimers;
  snapshot(): PlayerSnapshot;
  setSnapshot(snapshot: PlayerSnapshot): void;
}

function createHarness(
  initialSnapshot: PlayerSnapshot,
  options: { settleInDispatch?: boolean } = {},
): Harness {
  let snapshot = initialSnapshot;
  const envelopes: PlayerRendererIntentEnvelope<unknown>[] = [];
  const diagnostics: string[] = [];
  const timers = new FakeTimers();
  const dispatch: LineupDesktopPreloadApi['player']['dispatch'] = async (envelope) => {
    envelopes.push(envelope);
    const commandByIntent = {
      'player.playIfCurrent': 'play',
      'player.pauseIfCurrent': 'pause',
      'player.stopIfCurrent': 'stop',
      'player.seekRelativeIfCurrent': 'seek.relative',
    } as const;
    const command = commandByIntent[envelope.intent as keyof typeof commandByIntent];
    assert.ok(command, `unexpected direct input intent: ${envelope.intent}`);
    const events: PlayerEvent[] = options.settleInDispatch === false ? [] : [{
      event: 'command.settled',
      requestId: envelope.requestId,
      command,
      ok: true,
    }];
    return {
      ok: true,
      requestId: envelope.requestId,
      value: {
        accepted: true,
        events,
        snapshot,
      },
    };
  };
  const controller = createPlayerInputCommandController({
    player: { dispatch },
    host: timers,
    getSnapshot: () => snapshot,
    recordDiagnostic: (_operation, message) => diagnostics.push(message),
  });
  return {
    controller,
    envelopes,
    diagnostics,
    timers,
    snapshot: () => snapshot,
    setSnapshot(next) { snapshot = next; },
  };
}

function createSleepHarness(harness: Harness) {
  let projection: SleepTimerProjection = createSleepTimerProjection();
  const diagnostics: string[] = [];
  const controller = createSleepTimerController({
    host: harness.timers,
    now: () => harness.timers.nowMs(),
    getProjection: () => projection,
    setProjection: (next) => { projection = next; },
    render: () => undefined,
    getCurrentPlayback: () => harness.snapshot(),
    pauseCurrent: (requestId, onDeferredResolved) =>
      harness.controller.pauseCurrent(requestId, onDeferredResolved),
    cancelDeferredPause: () => harness.controller.cancelDeferredPause(),
    recordDiagnostic: (_operation, message) => { diagnostics.push(message); },
  });
  return { controller, projection: () => projection, diagnostics: () => diagnostics };
}

function settleCurrent(
  harness: Harness,
  command: 'play' | 'pause' | 'stop' | 'seek.relative',
  ok = true,
): void {
  const requestId = harness.envelopes.at(-1)?.requestId;
  assert.ok(requestId);
  harness.controller.handlePlayerEvent({
    event: 'command.settled',
    requestId,
    command,
    ok,
    ...(ok ? {} : {
      error: {
        code: 'PLAYER_COMMAND_FAILED',
        category: 'unknown' as const,
        message: 'Command failed.',
        recoverable: true,
        retryable: true,
        requestId,
      },
    }),
  });
}

function assertEnvelope(
  envelope: PlayerRendererIntentEnvelope<unknown> | undefined,
  intent: PlayerRendererIntentEnvelope<unknown>['intent'],
  payload: unknown,
): void {
  assert.ok(envelope);
  assert.equal(envelope.intent, intent);
  assert.deepEqual(envelope.payload, payload);
  assert.match(envelope.requestId, /^renderer-input-/u);
}

function playingSnapshot(): PlayerSnapshot {
  return {
    requestId: 'playback-1',
    status: 'playing',
    media: { id: 'media-1', title: 'Media' },
    capabilityProfileId: 'desktop-safe',
    seekSupport: 'supported',
    positionMs: 1_000,
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
    quality: { mode: 'unknown', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unknown' },
    lastError: null,
  };
}

class FakeTimers implements PlayerInputCommandTimerHost {
  #now = 0;
  #next = 1;
  #entries = new Map<number, { due: number; callback: () => void }>();

  setTimeout(callback: () => void, delayMs: number): number {
    const id = this.#next++;
    this.#entries.set(id, { due: this.#now + delayMs, callback });
    return id;
  }

  clearTimeout(handle: number): void {
    this.#entries.delete(handle);
  }

  nowMs(): number {
    return this.#now;
  }

  advance(deltaMs: number): void {
    const target = this.#now + deltaMs;
    while (true) {
      const next = [...this.#entries.entries()]
        .filter(([, entry]) => entry.due <= target)
        .sort((left, right) => left[1].due - right[1].due)[0];
      if (next === undefined) break;
      const [id, entry] = next;
      this.#now = entry.due;
      this.#entries.delete(id);
      entry.callback();
    }
    this.#now = target;
  }
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}
