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

test('direct input dispatches only guarded current-request commands with exact payloads', async () => {
  const harness = createHarness(playingSnapshot());

  assert.equal(harness.controller.handleInput('space'), true);
  await flush();
  assert.deepEqual(harness.envelopes[0], {
    intent: 'player.pauseIfCurrent',
    requestId: 'renderer-input-pause-1',
    payload: { snapshotRequestId: 'playback-1' },
  });
  settleCurrent(harness, 'pause');

  harness.setSnapshot({ ...playingSnapshot(), status: 'paused', playing: false });
  harness.controller.handleInput('mediaPlayPause');
  await flush();
  assert.deepEqual(harness.envelopes[1], {
    intent: 'player.playIfCurrent',
    requestId: 'renderer-input-play-2',
    payload: { snapshotRequestId: 'playback-1' },
  });
  settleCurrent(harness, 'play');

  harness.controller.handleInput('mediaRewind');
  await flush();
  assert.deepEqual(harness.envelopes[2], {
    intent: 'player.seekRelativeIfCurrent',
    requestId: 'renderer-input-seek-relative-3',
    payload: { snapshotRequestId: 'playback-1', deltaMs: -10_000 },
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
  assert.deepEqual(harness.envelopes[4], {
    intent: 'player.stopIfCurrent',
    requestId: 'renderer-input-stop-5',
    payload: { snapshotRequestId: 'playback-1' },
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

interface Harness {
  controller: ReturnType<typeof createPlayerInputCommandController>;
  envelopes: PlayerRendererIntentEnvelope<unknown>[];
  diagnostics: string[];
  timers: FakeTimers;
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
    const command = envelope.intent.includes('seekRelative') ? 'seek.relative'
      : envelope.intent.includes('pause') ? 'pause'
        : envelope.intent.includes('play') ? 'play'
          : 'stop';
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
    setSnapshot(next) { snapshot = next; },
  };
}

function settleCurrent(
  harness: Harness,
  command: 'play' | 'pause' | 'stop' | 'seek.relative',
): void {
  const requestId = harness.envelopes.at(-1)?.requestId;
  assert.ok(requestId);
  harness.controller.handlePlayerEvent({ event: 'command.settled', requestId, command, ok: true });
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

  advance(deltaMs: number): void {
    this.#now += deltaMs;
    for (const [id, entry] of [...this.#entries].sort((left, right) => left[1].due - right[1].due)) {
      if (entry.due > this.#now) continue;
      this.#entries.delete(id);
      entry.callback();
    }
  }
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}
