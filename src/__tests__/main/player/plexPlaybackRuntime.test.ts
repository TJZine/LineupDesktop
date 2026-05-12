import test from 'node:test';
import assert from 'node:assert/strict';

import {
  PlexPlaybackRuntime,
  type PlexPlaybackPmsSessionLease,
  type PlexPlaybackRuntimeCandidate,
  type PlexPlaybackRuntimeChannelPort,
  type PlexPlaybackRuntimeCleanupReason,
  type PlexPlaybackRuntimePlayerDispatchResult,
  type PlexPlaybackRuntimePlayerPort,
  type PlexPlaybackRuntimeSchedulerPort,
  type PlexPlaybackScheduleSelection,
} from '../../../main/player/plexPlaybackRuntime.js';
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
    return this.current;
  }
}

class FakeChannelPort implements PlexPlaybackRuntimeChannelPort {
  candidate: PlexPlaybackRuntimeCandidate = {
    requestId: 'request-1',
    load: loadPayload,
    pmsSession: { id: 'pms-1', requestId: 'request-1' },
  };
  readonly selections: PlexPlaybackScheduleSelection[] = [];

  async resolvePlaybackCandidate(
    nextSelection: PlexPlaybackScheduleSelection,
  ): Promise<PlexPlaybackRuntimeCandidate> {
    this.selections.push(nextSelection);
    return this.candidate;
  }
}

class FakePlayerPort implements PlexPlaybackRuntimePlayerPort {
  readonly commands: PlayerCommand[] = [];
  readonly cleanupRequestIds: Array<string | null> = [];
  dispatchResult: PlexPlaybackRuntimePlayerDispatchResult = { ok: true };
  dispatchFailure: Error | null = null;
  cleanupFailure: Error | null = null;

  async dispatch(command: PlayerCommand): Promise<PlexPlaybackRuntimePlayerDispatchResult> {
    this.commands.push(command);
    if (this.dispatchFailure !== null) {
      throw this.dispatchFailure;
    }
    return this.dispatchResult;
  }

  async cleanup(requestId: string | null): Promise<void> {
    this.cleanupRequestIds.push(requestId);
    if (this.cleanupFailure !== null) {
      throw this.cleanupFailure;
    }
  }
}

class FakePmsPort {
  readonly releases: Array<{
    session: PlexPlaybackPmsSessionLease;
    reason: PlexPlaybackRuntimeCleanupReason | 'stale';
    requestId: string;
  }> = [];
  failure: Error | null = null;

  async releaseSession(
    session: PlexPlaybackPmsSessionLease,
    input: { reason: PlexPlaybackRuntimeCleanupReason | 'stale'; requestId: string },
  ): Promise<void> {
    this.releases.push({ session, reason: input.reason, requestId: input.requestId });
    if (this.failure !== null) {
      throw this.failure;
    }
  }
}

function createRuntime(): {
  runtime: PlexPlaybackRuntime;
  scheduler: FakeSchedulerPort;
  channel: FakeChannelPort;
  player: FakePlayerPort;
  pms: FakePmsPort;
  emitted: PlayerEvent[];
} {
  const scheduler = new FakeSchedulerPort();
  const channel = new FakeChannelPort();
  const player = new FakePlayerPort();
  const pms = new FakePmsPort();
  const emitted: PlayerEvent[] = [];
  const runtime = new PlexPlaybackRuntime({
    scheduler,
    channel,
    player,
    pms,
    clock: { now: () => 42_000 },
    createRequestId: (prefix) => `${prefix}-generated`,
    onEvents: (events) => emitted.push(...events),
  });
  return { runtime, scheduler, channel, player, pms, emitted };
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
  const { runtime, pms, player } = createRuntime();
  await runtime.startCurrentPlayback();
  pms.failure = new Error('native-handle-detail');
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
  assertTextAbsent(events, 'native-handle-detail');
  assertTextAbsent(events, 'player-private-detail');
  assertNoForbiddenKeys(events);
  assertRendererSafePlayerEvents(events);
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
  const { runtime, channel, player, pms } = createRuntime();
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
  assertNoForbiddenKeys(result);
  assertRendererSafePlayerEvents(result.events);
});
