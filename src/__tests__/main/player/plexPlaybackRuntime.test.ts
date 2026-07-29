import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers';

import {
  PlexPlaybackRuntime,
  type PlexPlaybackPmsSessionLease,
  type PlexPlaybackRuntimeCandidate,
  type PlexPlaybackRuntimeChannelPort,
  type PlexPlaybackRuntimeCleanupReason,
  type PlexPlaybackRuntimePlayerDispatchResult,
  type PlexPlaybackRuntimePlayerPort,
  type PlexPlaybackRuntimeSchedulerPort,
  type PlexPlaybackRuntimeStartResult,
  type PlexPlaybackScheduleSelection,
} from '../../../main/player/plexPlaybackRuntime.js';
import type { PlexPlaybackRecoveryTimerPort } from '../../../main/player/plexPlaybackRecoveryOwner.js';
import { createPlaybackEventRouter } from '../../../main/player/playbackEventRouter.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import {
  isRendererSafePlayerEvent,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
} from '../../../contracts/player.js';

const selection: PlexPlaybackScheduleSelection = {
  channelId: 'channel-1',
  programId: 'program-1',
  startedAtMs: 1_000,
  endsAtMs: 121_000,
};

const loadPayload: PlayerLoadCommandPayload = {
  media: {
    id: 'media-1',
    title: 'Episode 1',
    durationMs: 120_000,
    container: 'mkv',
  },
  policy: {
    autoplay: true,
    startPositionMs: 5_000,
    preferredAudioTrackId: 'audio-ui-1',
    preferredSubtitleTrackId: null,
  },
  capabilityProfileId: 'desktop-safe',
};

class FakeSchedulerPort implements PlexPlaybackRuntimeSchedulerPort {
  current: PlexPlaybackScheduleSelection | null = selection;
  currentPromise: Promise<PlexPlaybackScheduleSelection | null> | null = null;
  failure: Error | null = null;
  readonly calls: Array<{ nowMs: number; reason: string }> = [];

  async getCurrentPlayback(input: {
    nowMs: number;
    reason: 'startup' | 'schedule-tick' | 'manual-switch';
  }): Promise<PlexPlaybackScheduleSelection | null> {
    this.calls.push(input);
    if (this.failure !== null) {
      throw this.failure;
    }
    return this.currentPromise ?? this.current;
  }
}

class FakeChannelPort implements PlexPlaybackRuntimeChannelPort {
  candidate: PlexPlaybackRuntimeCandidate = {
    requestId: 'request-1',
    load: loadPayload,
    pmsSession: { id: 'pms-1', requestId: 'request-1' },
  };
  candidatePromise: Promise<PlexPlaybackRuntimeCandidate> | null = null;
  onResolvePlaybackCandidate: (() => void) | null = null;
  readonly selections: PlexPlaybackScheduleSelection[] = [];

  async resolvePlaybackCandidate(
    nextSelection: PlexPlaybackScheduleSelection,
  ): Promise<PlexPlaybackRuntimeCandidate> {
    this.selections.push(nextSelection);
    this.onResolvePlaybackCandidate?.();
    return this.candidatePromise ?? this.candidate;
  }
}

class FakePlayerPort implements PlexPlaybackRuntimePlayerPort {
  readonly commands: PlayerCommand[] = [];
  readonly cleanupRequestIds: Array<string | null> = [];
  dispatchResult: PlexPlaybackRuntimePlayerDispatchResult = { ok: true };
  stopDispatchPromise: Promise<PlexPlaybackRuntimePlayerDispatchResult> | null = null;
  cleanupPromise: Promise<void> | null = null;
  dispatchFailure: Error | null = null;
  cleanupFailure: Error | null = null;

  async dispatch(command: PlayerCommand): Promise<PlexPlaybackRuntimePlayerDispatchResult> {
    this.commands.push(command);
    if (command.command === 'stop' && this.stopDispatchPromise !== null) {
      return this.stopDispatchPromise;
    }
    if (this.dispatchFailure !== null) {
      throw this.dispatchFailure;
    }
    return this.dispatchResult;
  }

  async cleanup(requestId: string | null): Promise<void> {
    this.cleanupRequestIds.push(requestId);
    if (this.cleanupPromise !== null) {
      await this.cleanupPromise;
    }
    if (this.cleanupFailure !== null) {
      throw this.cleanupFailure;
    }
  }
}

class FakePmsPort {
  readonly releases: Array<{
    session: PlexPlaybackPmsSessionLease;
    reason: PlexPlaybackRuntimeCleanupReason;
    requestId: string;
  }> = [];
  releasePromise: Promise<void> | null = null;
  failure: Error | null = null;

  async releaseSession(
    session: PlexPlaybackPmsSessionLease,
    input: { reason: PlexPlaybackRuntimeCleanupReason; requestId: string },
  ): Promise<void> {
    this.releases.push({ session, reason: input.reason, requestId: input.requestId });
    if (this.releasePromise !== null) {
      await this.releasePromise;
    }
    if (this.failure !== null) {
      throw this.failure;
    }
  }
}

class FakeRecoveryTimer implements PlexPlaybackRecoveryTimerPort {
  readonly delays: number[] = [];
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
    if (typeof handle === 'number') {
      this.pending.delete(handle);
    }
  }

  runNext(): void {
    const entry = this.pending.entries().next().value as [number, () => void] | undefined;
    assert.ok(entry, 'expected a pending recovery timer');
    this.pending.delete(entry[0]);
    entry[1]();
  }
}

function createRuntime(): {
  runtime: PlexPlaybackRuntime;
  scheduler: FakeSchedulerPort;
  channel: FakeChannelPort;
  player: FakePlayerPort;
  pms: FakePmsPort;
  emitted: PlayerEvent[];
  diagnostics: DiagnosticEventStore;
  recoveryTimer: FakeRecoveryTimer;
  eventObserver: {
    current: ((events: readonly PlayerEvent[]) => void) | null;
  };
} {
  const scheduler = new FakeSchedulerPort();
  const channel = new FakeChannelPort();
  const player = new FakePlayerPort();
  const pms = new FakePmsPort();
  const emitted: PlayerEvent[] = [];
  const diagnostics = new DiagnosticEventStore({
    clock: () => 1_000,
    idGenerator: () => 'runtime-diagnostic',
  });
  const recoveryTimer = new FakeRecoveryTimer();
  const eventObserver = {
    current: null as ((events: readonly PlayerEvent[]) => void) | null,
  };
  const runtime = new PlexPlaybackRuntime({
    scheduler,
    channel,
    player,
    pms,
    clock: { now: () => 42_000 },
    createRequestId: (prefix) => `${prefix}-generated`,
    onEvents: (events) => {
      emitted.push(...events);
      eventObserver.current?.(events);
    },
    diagnosticEventStore: diagnostics,
    recoveryTimer,
  });
  return {
    runtime,
    scheduler,
    channel,
    player,
    pms,
    emitted,
    diagnostics,
    recoveryTimer,
    eventObserver,
  };
}

function assertNoForbiddenKeys(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) {
      assertNoForbiddenKeys(item);
    }
    return;
  }
  if (value === null || typeof value !== 'object') {
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    assert.equal(
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ),
      false,
      `renderer-facing runtime value contains forbidden key ${key}`,
    );
    assertNoForbiddenKeys(child);
  }
}

function assertTextAbsent(value: unknown, text: string): void {
  assert.equal(JSON.stringify(value).includes(text), false, `unexpected renderer-facing text ${text}`);
}

function assertRendererSafePlayerEvents(events: readonly PlayerEvent[]): void {
  for (const event of events) {
    assert.equal(isRendererSafePlayerEvent(event), true, `runtime emitted unsafe ${event.event} event`);
  }
}

function createDeferred<T>(): {
  promise: Promise<T>;
  resolve(value: T): void;
  reject(error: unknown): void;
} {
  let resolvePromise = (_value: T): void => {
    throw new Error('Deferred promise was not initialized.');
  };
  let rejectPromise = (_error: unknown): void => {
    throw new Error('Deferred promise was not initialized.');
  };
  const promise = new Promise<T>((resolve, reject) => {
    resolvePromise = resolve;
    rejectPromise = reject;
  });
  return {
    promise,
    resolve: resolvePromise,
    reject: rejectPromise,
  };
}

function eligibleEngineError(requestId: string): PlayerEvent {
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

async function waitFor(
  predicate: () => boolean,
  message: string,
): Promise<void> {
  for (let index = 0; index < 20; index += 1) {
    if (predicate()) {
      return;
    }
    await new Promise<void>((resolve) => setImmediate(resolve));
  }
  assert.fail(message);
}

test('RD-12 plex playback runtime starts current scheduled media through fakeable ports', async () => {
  const { runtime, scheduler, channel, player, emitted } = createRuntime();
  player.dispatchResult = {
    ok: true,
    events: [
      {
        event: 'media.loaded',
        requestId: 'request-1',
        media: loadPayload.media,
        durationMs: 120_000,
      },
    ],
  };

  const result = await runtime.startCurrentPlayback('startup');

  assert.equal(result.accepted, true);
  assert.equal(result.epoch, 1);
  assert.equal(result.requestId, 'request-1');
  assert.equal(runtime.getActiveRequestId(), 'request-1');
  assert.deepEqual(scheduler.calls, [{ nowMs: 42_000, reason: 'startup' }]);
  assert.deepEqual(channel.selections, [selection]);
  assert.equal(player.commands[0]?.command, 'load');
  assert.deepEqual(player.commands[0]?.payload, loadPayload);
  assert.equal(emitted.some((event) => event.event === 'media.loaded'), true);
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});

test('playback runtime ingests one eligible async error and retries the exact current identity', async () => {
  const {
    runtime,
    scheduler,
    player,
    pms,
    emitted,
    recoveryTimer,
  } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;

  const accepted = runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);

  assert.deepEqual(accepted, [eligibleEngineError('request-1')]);
  assert.deepEqual(emitted, [eligibleEngineError('request-1')]);
  assert.deepEqual(recoveryTimer.delays, [1_000]);

  recoveryTimer.runNext();
  await waitFor(() => player.commands.length === 2, 'recovery load did not dispatch');

  assert.equal(scheduler.calls.length, 2);
  assert.deepEqual(
    scheduler.calls.map((call) => call.reason),
    ['startup', 'schedule-tick'],
  );
  assert.deepEqual(player.cleanupRequestIds, ['request-1']);
  assert.deepEqual(
    pms.releases.map((release) => release.reason),
    ['switch'],
  );
  assert.equal(runtime.getActiveRequestId(), 'request-1');
});

test('manual recovery resets the exhausted automatic budget and retries the frozen identity once', async () => {
  const {
    runtime,
    player,
    emitted,
    recoveryTimer,
  } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  player.dispatchResult = { ok: false };
  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);

  for (let expectedLoads = 2; expectedLoads <= 4; expectedLoads += 1) {
    recoveryTimer.runNext();
    await waitFor(
      () => player.commands.length === expectedLoads,
      `automatic recovery load ${String(expectedLoads - 1)} did not settle`,
    );
    await new Promise<void>((resolve) => setImmediate(resolve));
  }
  assert.equal(recoveryTimer.pending.size, 0);

  player.dispatchResult = { ok: true };
  const retried = await runtime.retryCurrentPlayback(selection);

  assert.equal(retried, true);
  assert.equal(player.commands.length, 5);
  assert.equal(player.commands.at(-1)?.command, 'load');
  assert.equal(runtime.getActiveRequestId(), 'request-1');

  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);
  assert.deepEqual(recoveryTimer.delays, [1_000, 2_000, 4_000, 1_000]);
  assert.equal(emitted.at(-1)?.event, 'error');
});

test('manual recovery refuses to start when the authoritative schedule identity changed', async () => {
  const { runtime, scheduler, player } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  scheduler.current = {
    ...selection,
    programId: 'program-2',
  };

  const retried = await runtime.retryCurrentPlayback(selection);

  assert.equal(retried, false);
  assert.equal(player.commands.length, 1);
  assert.deepEqual(player.cleanupRequestIds, []);
  assert.equal(runtime.getActiveRequestId(), 'request-1');
});

test('manual recovery re-resolves the exact current selection after helper cleanup', async () => {
  const { runtime, scheduler, player, pms } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  await runtime.handleHelperCrash();

  const retried = await runtime.retryCurrentPlayback(selection);

  assert.equal(retried, true);
  assert.equal(scheduler.calls.length, 2);
  assert.deepEqual(
    player.commands.map((command) => command.command),
    ['load', 'load'],
  );
  assert.deepEqual(player.cleanupRequestIds, ['request-1']);
  assert.deepEqual(
    pms.releases.map((release) => release.reason),
    ['helper-crash'],
  );
  assert.equal(runtime.getActiveRequestId(), 'request-1');
});

test('manual recovery rejects changed end time and cleanup during scheduler revalidation', async () => {
  const { runtime, scheduler, player } = createRuntime();
  await runtime.startCurrentPlayback('startup');

  assert.equal(
    await runtime.retryCurrentPlayback({
      ...selection,
      endsAtMs: 121_001,
    }),
    false,
  );

  const current = createDeferred<PlexPlaybackScheduleSelection | null>();
  scheduler.currentPromise = current.promise;
  const pending = runtime.retryCurrentPlayback(selection);
  await runtime.cleanup({ reason: 'server-change' });
  current.resolve(selection);

  assert.equal(await pending, false);
  assert.equal(player.commands.length, 1);
  assert.equal(runtime.getActiveRequestId(), null);
});

test('playback runtime does not recover an unscoped engine error', async () => {
  const { runtime, recoveryTimer } = createRuntime();
  await runtime.startCurrentPlayback('startup');

  runtime.ingestPlayerEvents([
    {
      event: 'error',
      requestId: null,
      error: {
        code: 'PLAYER_HOST_ENGINE_FAILURE',
        category: 'engine-failure',
        message: 'The player engine failed.',
        recoverable: true,
        retryable: true,
      },
    },
  ]);

  assert.deepEqual(recoveryTimer.delays, []);
});

test('playback runtime charges candidate/load failures to the same three-attempt budget', async () => {
  const {
    runtime,
    channel,
    player,
    emitted,
    recoveryTimer,
  } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  channel.candidate = {
    requestId: 'request-invalid',
    load: loadPayload,
    pmsSession: { id: 'pms-invalid', requestId: 'different-request' },
  };
  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);

  for (let expectedAttempts = 1; expectedAttempts <= 3; expectedAttempts += 1) {
    recoveryTimer.runNext();
    await waitFor(
      () => emitted.filter((event) => event.event === 'error').length >= expectedAttempts + 1,
      `recovery attempt ${expectedAttempts} did not settle`,
    );
  }

  assert.deepEqual(recoveryTimer.delays, [1_000, 2_000, 4_000]);
  assert.equal(recoveryTimer.pending.size, 0);
  assert.equal(player.commands.length, 1);
  assert.equal(
    emitted.filter((event) => (
      event.event === 'error' &&
      event.error.code === 'PLAYER_HOST_ENGINE_FAILURE'
    )).length,
    1,
  );
});

test('playback runtime does not grant a fourth attempt after three rejected recovery loads', async () => {
  const { runtime, player, emitted, recoveryTimer } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  emitted.length = 0;
  player.dispatchResult = { ok: false };
  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);

  for (let expectedAttempts = 1; expectedAttempts <= 3; expectedAttempts += 1) {
    recoveryTimer.runNext();
    await waitFor(
      () => player.commands.length === expectedAttempts + 1,
      `rejected recovery load ${expectedAttempts} did not settle`,
    );
    await new Promise<void>((resolve) => setImmediate(resolve));
  }

  assert.deepEqual(recoveryTimer.delays, [1_000, 2_000, 4_000]);
  assert.equal(recoveryTimer.pending.size, 0);
  assert.equal(player.commands.length, 4);
  assert.equal(
    emitted.filter((event) => (
      event.event === 'error' &&
      event.error.code === 'PLAYER_HOST_ENGINE_FAILURE'
    )).length,
    1,
  );
});

test('playback runtime quarantines a retry when the scheduled identity changes', async () => {
  const { runtime, scheduler, player, pms, recoveryTimer } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);
  scheduler.current = {
    ...selection,
    programId: 'program-2',
  };

  recoveryTimer.runNext();
  await new Promise<void>((resolve) => setImmediate(resolve));

  assert.equal(player.commands.length, 1);
  assert.deepEqual(player.cleanupRequestIds, []);
  assert.deepEqual(pms.releases, []);
  assert.equal(recoveryTimer.pending.size, 0);
  assert.equal(runtime.getActiveRequestId(), 'request-1');
});

test('playback runtime cleanup cancels a pending automatic retry', async () => {
  const { runtime, player, recoveryTimer } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);
  assert.equal(recoveryTimer.pending.size, 1);

  await runtime.cleanup({ reason: 'server-change' });

  assert.equal(recoveryTimer.pending.size, 0);
  assert.equal(runtime.getActiveRequestId(), null);
  assert.deepEqual(player.cleanupRequestIds, ['request-1']);
});

test('playback runtime cleanup custody blocks every start path through nested PMS and player drain', async () => {
  const {
    runtime,
    scheduler,
    channel,
    player,
    pms,
    emitted,
    recoveryTimer,
    eventObserver,
  } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  runtime.ingestPlayerEvents([eligibleEngineError('request-1')]);
  const automaticRetry = [...recoveryTimer.pending.values()][0];
  assert.ok(automaticRetry);

  const pmsRelease = createDeferred<void>();
  const playerCleanup = createDeferred<void>();
  pms.releasePromise = pmsRelease.promise;
  player.cleanupPromise = playerCleanup.promise;
  const startDuringCleanupEvent = {
    current: null as Promise<PlexPlaybackRuntimeStartResult> | null,
  };
  eventObserver.current = (events) => {
    if (events.some((event) => event.event === 'error')) {
      startDuringCleanupEvent.current =
        runtime.startCurrentPlayback('schedule-tick');
    }
  };

  const oldestCleanup = runtime.cleanup({ reason: 'server-change' });
  const newerCleanup = runtime.cleanup({ reason: 'profile-change' });
  await newerCleanup;

  const heldEpoch = runtime.getCurrentEpoch();
  assert.deepEqual(await runtime.startCurrentPlayback('manual-switch'), {
    accepted: false,
    epoch: heldEpoch,
    requestId: null,
    events: [],
  });
  assert.equal(await runtime.retryCurrentPlayback(selection), false);
  automaticRetry();
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(scheduler.calls.length, 1);
  assert.equal(channel.selections.length, 1);
  assert.equal(player.commands.length, 1);

  pmsRelease.resolve();
  await waitFor(
    () => player.cleanupRequestIds.length === 1,
    'player cleanup did not begin after PMS release',
  );
  assert.equal((await runtime.startCurrentPlayback()).accepted, false);
  playerCleanup.reject(new Error('safe cleanup regression fixture'));
  await oldestCleanup;

  const cleanupEventStart = startDuringCleanupEvent.current;
  assert.ok(cleanupEventStart);
  assert.equal((await cleanupEventStart).accepted, false);
  assert.equal(emitted.at(-1)?.event, 'error');

  eventObserver.current = null;
  pms.releasePromise = null;
  player.cleanupPromise = null;
  channel.candidate = {
    requestId: 'request-2',
    load: {
      ...loadPayload,
      media: { ...loadPayload.media, id: 'media-2', title: 'Episode 2' },
    },
    pmsSession: { id: 'pms-2', requestId: 'request-2' },
  };

  assert.equal(await runtime.retryCurrentPlayback(selection), true);
  assert.deepEqual(
    player.commands.map((command) => command.requestId),
    ['request-1', 'request-2'],
  );
  assert.deepEqual(
    pms.releases.map((release) => release.session.requestId),
    ['request-1'],
  );
  assert.equal(runtime.getActiveRequestId(), 'request-2');
});

test('RD-25 plex playback runtime rejects invalid privileged descriptors before player dispatch', async () => {
  const { runtime, channel, player, pms, emitted } = createRuntime();
  channel.candidate = {
    requestId: 'request-privileged',
    load: loadPayload,
    pmsSession: { id: 'pms-privileged', requestId: 'request-privileged' },
    privatePlayback: {
      requestId: 'wrong-request',
      decisionKind: 'direct-play',
      playbackUrl: 'https://plex.example.invalid/private.mp4',
      credentialHeader: { name: 'X-Plex-Token', value: 'private-token' },
      selectedConnection: {
        protocol: 'https',
        address: 'plex.example.invalid',
        port: 443,
        local: true,
        relay: false,
      },
      media: { id: loadPayload.media.id, title: loadPayload.media.title },
      setup: {
        playbackMode: 'direct-play',
        mediaPath: '/library/metadata/1',
        variantId: 'variant-1',
        partPath: '/library/parts/1/file.mp4',
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: { video: [], audio: [], subtitle: [] },
        audioOutputNativeKey: null,
        dtsPassthroughEnabled: false,
      },
    },
  };

  const result = await runtime.startCurrentPlayback('startup');

  assert.equal(result.accepted, false);
  assert.equal(player.commands.length, 0);
  assert.deepEqual(pms.releases, [
    {
      session: { id: 'pms-privileged', requestId: 'request-privileged' },
      reason: 'stale',
      requestId: 'request-privileged',
    },
  ]);
  assert.equal(result.events.some((event) => (
    event.event === 'error' &&
    event.error.code === 'PLAYER_PRIVILEGED_DESCRIPTOR_INVALID'
  )), true);
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertTextAbsent(result, 'private-token');
  assertTextAbsent(emitted, 'private-token');
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});

test('RD-12 plex playback runtime cleans PMS and player state for every cleanup input', async () => {
  const cleanupReasons: readonly PlexPlaybackRuntimeCleanupReason[] = [
    'stop',
    'switch',
    'error',
    'helper-crash',
    'logout',
    'server-change',
    'profile-change',
    'teardown',
  ];

  for (const reason of cleanupReasons) {
    const { runtime, channel, player, pms } = createRuntime();
    channel.candidate = {
      requestId: `request-${reason}`,
      load: loadPayload,
      pmsSession: { id: `pms-${reason}`, requestId: `request-${reason}` },
    };

    await runtime.startCurrentPlayback();
    const events = reason === 'stop' ? await runtime.stop() : await runtime.cleanup({ reason });
    const cleanupCommandCount = reason === 'stop' ? 1 : 0;

    assert.equal(runtime.getActiveRequestId(), null);
    assert.equal(pms.releases.length, 1);
    assert.equal(pms.releases[0]?.reason, reason);
    assert.equal(pms.releases[0]?.requestId, `request-${reason}`);
    assert.equal(player.cleanupRequestIds[0], `request-${reason}`);
    assert.equal(player.commands.filter((command) => command.command === 'stop').length, cleanupCommandCount);
    assertNoForbiddenKeys(events);
    assertRendererSafePlayerEvents(events);

    await runtime.cleanup({ reason });
    assert.equal(pms.releases.length, 1, `${reason} cleanup must be idempotent`);
    assert.equal(player.cleanupRequestIds.length, 1, `${reason} player cleanup must be idempotent`);
  }
});

test('RD-12 plex playback runtime cleans the previous PMS session before switching media', async () => {
  const { runtime, channel, player, pms } = createRuntime();

  await runtime.startCurrentPlayback('startup');
  channel.candidate = {
    requestId: 'request-2',
    load: {
      ...loadPayload,
      media: { ...loadPayload.media, id: 'media-2', title: 'Episode 2' },
    },
    pmsSession: { id: 'pms-2', requestId: 'request-2' },
  };

  const result = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(result.accepted, true);
  assert.equal(result.epoch, 2);
  assert.equal(runtime.getActiveRequestId(), 'request-2');
  assert.equal(pms.releases.length, 1);
  assert.equal(pms.releases[0]?.session.id, 'pms-1');
  assert.equal(pms.releases[0]?.reason, 'switch');
  assert.equal(player.cleanupRequestIds[0], 'request-1');
  assert.deepEqual(
    player.commands.map((command) => command.requestId),
    ['request-1', 'request-2'],
  );
  assertNoForbiddenKeys(result);
  assertRendererSafePlayerEvents(result.events);
});

test('plex playback runtime stop holds replacement starts until its complete drain settles', async () => {
  const { runtime, channel, player, pms } = createRuntime();
  await runtime.startCurrentPlayback('startup');
  const stopDispatch = createDeferred<PlexPlaybackRuntimePlayerDispatchResult>();
  player.stopDispatchPromise = stopDispatch.promise;

  const stopping = runtime.stop();
  assert.equal(runtime.getActiveRequestId(), null);

  channel.candidate = {
    requestId: 'request-2',
    load: {
      ...loadPayload,
      media: { ...loadPayload.media, id: 'media-2', title: 'Episode 2' },
    },
    pmsSession: { id: 'pms-2', requestId: 'request-2' },
  };
  const replacement = await runtime.startCurrentPlayback('manual-switch');

  assert.equal(replacement.accepted, false);
  assert.equal(replacement.requestId, null);
  assert.equal(runtime.getActiveRequestId(), null);
  stopDispatch.resolve({ ok: true });
  await stopping;

  const postStop = await runtime.startCurrentPlayback('manual-switch');
  assert.equal(postStop.accepted, true);
  assert.equal(runtime.getActiveRequestId(), 'request-2');
  assert.deepEqual(
    pms.releases.map((release) => ({
      sessionId: release.session.id,
      reason: release.reason,
    })),
    [{ sessionId: 'pms-1', reason: 'stop' }],
  );
  assert.deepEqual(player.cleanupRequestIds, ['request-1']);

  await runtime.cleanup({ reason: 'teardown' });
  assert.deepEqual(
    pms.releases.map((release) => release.session.id),
    ['pms-1', 'pms-2'],
  );
});

test('plex playback runtime suppresses a superseded candidate resolution failure', async () => {
  const { runtime, channel, pms, emitted } = createRuntime();
  const candidateResolution = createDeferred<PlexPlaybackRuntimeCandidate>();
  const candidateResolutionStarted = createDeferred<void>();
  channel.candidatePromise = candidateResolution.promise;
  channel.onResolvePlaybackCandidate = () => candidateResolutionStarted.resolve();
  const staleStart = runtime.startCurrentPlayback('startup');
  await candidateResolutionStarted.promise;

  channel.candidatePromise = null;
  channel.onResolvePlaybackCandidate = null;
  channel.candidate = {
    requestId: 'request-2',
    load: {
      ...loadPayload,
      media: { ...loadPayload.media, id: 'media-2', title: 'Episode 2' },
    },
    pmsSession: { id: 'pms-2', requestId: 'request-2' },
  };
  const replacement = await runtime.startCurrentPlayback('manual-switch');
  candidateResolution.reject(new Error('stale candidate failure'));
  const staleResult = await staleStart;

  assert.equal(replacement.accepted, true);
  assert.equal(runtime.getActiveRequestId(), 'request-2');
  assert.equal(staleResult.accepted, false);
  assert.equal(staleResult.events.some((event) => event.event === 'error'), false);
  assert.equal(emitted.some((event) => event.event === 'error'), false);

  await runtime.cleanup({ reason: 'teardown' });
  assert.deepEqual(
    pms.releases.map((release) => release.session.id),
    ['pms-2'],
  );
});

test('RD-12 plex playback runtime quarantines stale player events by epoch', async () => {
  const { runtime, channel, pms } = createRuntime();

  const first = await runtime.startCurrentPlayback('startup');
  channel.candidate = {
    requestId: 'request-2',
    load: {
      ...loadPayload,
      media: { ...loadPayload.media, id: 'media-2', title: 'Episode 2' },
    },
    pmsSession: { id: 'pms-2', requestId: 'request-2' },
  };
  await runtime.startCurrentPlayback('manual-switch');

  const staleEvents = runtime.handlePlayerEvent(first.epoch, {
    event: 'time.updated',
    requestId: 'request-1',
    positionMs: 80_000,
    durationMs: 120_000,
  });

  assert.equal(runtime.getActiveRequestId(), 'request-2');
  assert.equal(staleEvents[0]?.event, 'warning');
  if (staleEvents[0]?.event === 'warning') {
    assert.equal(staleEvents[0].requestId, 'request-1');
    assert.equal(staleEvents[0].warning.category, 'stale-request');
    assert.equal(staleEvents[0].warning.requestId, 'request-1');
  }
  await runtime.cleanup({ reason: 'teardown' });
  assert.deepEqual(
    pms.releases.map((release) => release.session.id),
    ['pms-1', 'pms-2'],
  );
  assertNoForbiddenKeys(staleEvents);
  assertRendererSafePlayerEvents(staleEvents);
});

test('RD-12 plex playback runtime reports cleanup failures without privileged detail', async () => {
  const { runtime, pms, player, diagnostics } = createRuntime();
  await runtime.startCurrentPlayback();
  const nativeDetail = ['native', 'handle', 'detail'].join('-');
  pms.failure = new Error(nativeDetail);
  player.cleanupFailure = new Error('player-private-detail');

  const events = await runtime.cleanup({ reason: 'server-change' });

  assert.equal(events.length, 2);
  for (const event of events) {
    assert.equal(event.event, 'error');
    if (event.event === 'error') {
      assert.equal(event.error.category, 'cleanup-failure');
      assert.equal(event.error.message, 'Playback cleanup did not complete safely.');
    }
  }
  assertTextAbsent(events, nativeDetail);
  assertTextAbsent(events, 'player-private-detail');
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 1);
  assert.equal(diagnostics.getCrashRecoverySummary().events.filter((event) => event.category === 'cleanup').length, 2);
  assertTextAbsent(diagnostics.getRecords(), nativeDetail);
  assertTextAbsent(diagnostics.getRecords(), 'player-private-detail');
  assertNoForbiddenKeys(events);
  assertRendererSafePlayerEvents(events);
});

test('RD-17 plex playback runtime helper-crash cleanup records safe diagnostics and releases resources', async () => {
  const { runtime, pms, player, diagnostics, emitted } = createRuntime();
  await runtime.startCurrentPlayback();
  const forbiddenUrl = ['https://', 'secret', '.example'].join('');
  pms.failure = new Error(`tokenizedUrl=${forbiddenUrl}`);

  const events = await runtime.handleHelperCrash();

  assert.equal(runtime.getActiveRequestId(), null);
  assert.equal(pms.releases[0]?.reason, 'helper-crash');
  assert.deepEqual(player.cleanupRequestIds, ['request-1']);
  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 1);
  assertTextAbsent(diagnostics.getRecords(), forbiddenUrl);
  assertNoForbiddenKeys(events);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(events);
});

test('RD-17 helper lifecycle flush delivers queued engine failure before crash custody cleanup', async () => {
  const { runtime, emitted } = createRuntime();
  await runtime.startCurrentPlayback();
  emitted.length = 0;
  const router = createPlaybackEventRouter({
    getRuntime: () => runtime,
  });

  router.route([eligibleEngineError('request-1')]);
  router.flushCurrentRuntime();
  await runtime.handleHelperCrash();

  assert.equal(emitted[0]?.event, 'error');
  if (emitted[0]?.event === 'error') {
    assert.equal(emitted[0].error.code, 'PLAYER_HOST_ENGINE_FAILURE');
  }
  assert.equal(
    emitted.some(
      (event) =>
        event.event === 'warning' &&
        event.warning.category === 'stale-request',
    ),
    false,
  );
  assert.equal(runtime.getActiveRequestId(), null);
  router.dispose();
});

test('RD-12 plex playback runtime normalizes rejecting player dispatch and cleans active state', async () => {
  const { runtime, player, pms, emitted } = createRuntime();
  player.dispatchFailure = new Error('raw native helper failure tokenizedUrl=https://secret.example');

  const result = await runtime.startCurrentPlayback('startup');

  assert.equal(result.accepted, false);
  assert.equal(result.epoch, 1);
  assert.equal(result.requestId, 'request-1');
  assert.equal(runtime.getActiveRequestId(), null);
  assert.equal(runtime.getCurrentEpoch(), 2);
  assert.equal(player.commands.length, 1);
  assert.equal(player.commands[0]?.command, 'load');
  assert.deepEqual(player.cleanupRequestIds, ['request-1']);
  assert.equal(pms.releases.length, 1);
  assert.equal(pms.releases[0]?.session.id, 'pms-1');
  assert.equal(pms.releases[0]?.reason, 'error');
  assert.equal(pms.releases[0]?.requestId, 'request-1');

  assert.equal(result.events.length, 1);
  const loadFailedEvent = result.events[0];
  assert.equal(loadFailedEvent?.event, 'error');
  if (loadFailedEvent?.event === 'error') {
    assert.equal(loadFailedEvent.error.code, 'PLAYER_PLAYBACK_LOAD_FAILED');
    assert.equal(loadFailedEvent.error.message, 'The player could not load the scheduled media.');
    assert.deepEqual(loadFailedEvent.error.diagnostic?.media, {
      id: 'media-1',
      title: 'Episode 1',
    });
  }
  assertTextAbsent(result, 'raw native helper failure');
  assertTextAbsent(result, 'https://secret.example');
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});

test('RD-12 plex playback runtime normalizes scheduler selection failures', async () => {
  const { runtime, scheduler, channel, player, pms, emitted } = createRuntime();
  scheduler.failure = new Error('rawPlexPayload tokenizedUrl=https://secret.example');

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(result.epoch, 1);
  assert.equal(result.requestId, null);
  assert.equal(runtime.getActiveRequestId(), null);
  assert.deepEqual(scheduler.calls, [{ nowMs: 42_000, reason: 'schedule-tick' }]);
  assert.equal(channel.selections.length, 0);
  assert.equal(player.commands.length, 0);
  assert.equal(pms.releases.length, 0);
  assert.equal(result.events.length, 1);
  const event = result.events[0];
  assert.equal(event?.event, 'error');
  if (event?.event === 'error') {
    assert.equal(event.requestId, null);
    assert.equal(event.error.code, 'PLAYER_PLAYBACK_SELECTION_UNAVAILABLE');
    assert.equal(event.error.category, 'source');
    assert.equal(event.error.requestId, undefined);
    assert.equal(event.error.diagnostic?.component, 'plex-playback-runtime');
    assert.equal(event.error.diagnostic?.operation, 'schedule.resolve');
    assert.equal(event.error.diagnostic?.status, 'failed');
    assert.equal(event.error.diagnostic?.reason, 'scheduler selection failed');
  }
  assertTextAbsent(result, 'rawPlexPayload');
  assertTextAbsent(result, 'https://secret.example');
  assertTextAbsent(emitted, 'rawPlexPayload');
  assertTextAbsent(emitted, 'https://secret.example');
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});

test('RD-12 plex playback runtime rejects unsafe schedule and channel payloads before player dispatch', async () => {
  const { runtime, scheduler, channel, player, pms } = createRuntime();

  scheduler.current = {
    ...selection,
    rawPlexPayload: { hidden: true },
  } as unknown as PlexPlaybackScheduleSelection;
  const unsafeSchedule = await runtime.startCurrentPlayback();

  assert.equal(unsafeSchedule.accepted, false);
  assert.equal(player.commands.length, 0);
  assert.equal(pms.releases.length, 0);
  assertTextAbsent(unsafeSchedule, 'hidden');
  assertNoForbiddenKeys(unsafeSchedule);
  assertRendererSafePlayerEvents(unsafeSchedule.events);

  scheduler.current = selection;
  channel.candidate = {
    requestId: 'request-unsafe',
    load: {
      ...loadPayload,
      media: {
        ...loadPayload.media,
        tokenizedUrl: 'https://secret.example/media',
      },
    },
    pmsSession: { id: 'pms-unsafe', requestId: 'request-unsafe' },
  } as unknown as PlexPlaybackRuntimeCandidate;
  const unsafeCandidate = await runtime.startCurrentPlayback();

  assert.equal(unsafeCandidate.accepted, false);
  assert.equal(player.commands.length, 0);
  assert.deepEqual(pms.releases, [
    {
      session: { id: 'pms-unsafe', requestId: 'request-unsafe' },
      reason: 'stale',
      requestId: 'unsafe-candidate',
    },
  ]);
  assertTextAbsent(unsafeCandidate, 'https://secret.example/media');
  assertNoForbiddenKeys(unsafeCandidate);
  assertRendererSafePlayerEvents(unsafeCandidate.events);
});

test('RD-12 plex playback runtime does not echo unsafe rejected candidate ids when PMS release fails', async () => {
  const { runtime, channel, player, pms, emitted } = createRuntime();
  pms.failure = new Error('private cleanup failure tokenizedUrl=https://secret.example');
  channel.candidate = {
    requestId: 'private-rejected-request',
    load: {
      ...loadPayload,
      media: {
        ...loadPayload.media,
        tokenizedUrl: 'https://secret.example/media',
      },
    },
    pmsSession: { id: 'pms-private', requestId: 'private-rejected-request' },
  } as unknown as PlexPlaybackRuntimeCandidate;

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(result.requestId, null);
  assert.equal(runtime.getActiveRequestId(), null);
  assert.equal(player.commands.length, 0);
  assert.deepEqual(pms.releases, [
    {
      session: { id: 'pms-private', requestId: 'private-rejected-request' },
      reason: 'stale',
      requestId: 'unsafe-candidate',
    },
  ]);
  assert.equal(result.events.length, 2);
  assert.equal(result.events[0]?.event, 'error');
  if (result.events[0]?.event === 'error') {
    assert.equal(result.events[0].requestId, null);
    assert.equal(result.events[0].error.code, 'PLAYER_PLAYBACK_CLEANUP_FAILED');
    assert.equal(result.events[0].error.requestId, undefined);
  }
  assertTextAbsent(result, 'private-rejected-request');
  assertTextAbsent(result, 'pms-private');
  assertTextAbsent(result, 'https://secret.example');
  assertTextAbsent(result, 'private cleanup failure');
  assertTextAbsent(emitted, 'private-rejected-request');
  assertTextAbsent(emitted, 'pms-private');
  assertTextAbsent(emitted, 'https://secret.example');
  assertTextAbsent(emitted, 'private cleanup failure');
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});

test('RD-12 plex playback runtime releases rejected mismatched PMS lease before player dispatch', async () => {
  const { runtime, channel, player, pms, emitted } = createRuntime();
  channel.candidate = {
    ...channel.candidate,
    requestId: 'request-1',
    pmsSession: { id: 'pms-other-request', requestId: 'request-from-other-runtime' },
  };

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(result.requestId, 'request-1');
  assert.equal(runtime.getActiveRequestId(), null);
  assert.equal(player.commands.length, 0);
  assert.deepEqual(pms.releases, [
    {
      session: { id: 'pms-other-request', requestId: 'request-from-other-runtime' },
      reason: 'stale',
      requestId: 'request-1',
    },
  ]);
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0]?.event, 'error');
  if (result.events[0]?.event === 'error') {
    assert.equal(result.events[0].error.code, 'PLAYER_RUNTIME_VALIDATION_FAILED');
    assert.equal(result.events[0].error.requestId, 'request-1');
  }
  assertTextAbsent(result, 'request-from-other-runtime');
  assertTextAbsent(emitted, 'request-from-other-runtime');
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});

test('RD-12 plex playback runtime reports rejected PMS release failures as stale cleanup', async () => {
  const { runtime, channel, player, pms, emitted } = createRuntime();
  pms.failure = new Error('private stale cleanup tokenizedUrl=https://secret.example');
  channel.candidate = {
    ...channel.candidate,
    requestId: 'request-1',
    pmsSession: { id: 'pms-other-request', requestId: 'request-from-other-runtime' },
  };

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(result.requestId, 'request-1');
  assert.equal(player.commands.length, 0);
  assert.equal(result.events.length, 2);
  const cleanupFailure = result.events[0];
  assert.equal(cleanupFailure?.event, 'error');
  if (cleanupFailure?.event === 'error') {
    assert.equal(cleanupFailure.error.code, 'PLAYER_PLAYBACK_CLEANUP_FAILED');
    assert.equal(cleanupFailure.error.diagnostic?.operation, 'cleanup');
    assert.deepEqual(cleanupFailure.error.diagnostic?.counts, { stale: 1 });
  }
  assert.equal(result.events[1]?.event, 'error');
  assertTextAbsent(result, 'request-from-other-runtime');
  assertTextAbsent(result, 'tokenizedUrl=https://secret.example');
  assertTextAbsent(emitted, 'request-from-other-runtime');
  assertTextAbsent(emitted, 'tokenizedUrl=https://secret.example');
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(emitted);
  assertRendererSafePlayerEvents(result.events);
  assertRendererSafePlayerEvents(emitted);
});
