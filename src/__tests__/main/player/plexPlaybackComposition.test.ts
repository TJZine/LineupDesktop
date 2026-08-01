import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers';

import type {
  PlayerCommand,
  PlayerEvent,
  PlayerLoadCommandPayload,
} from '../../../contracts/player.js';
import type { PlayerRendererIntentEnvelope } from '../../../contracts/ipc.js';
import type { IChannelScheduler, ScheduledProgram, SchedulerState } from '../../../domain/scheduler/index.js';
import {
  createDesktopPlayerAdapterRuntimePort,
  createPlexPlaybackRuntimeComposition,
  type PlexPlaybackCompositionResolverPort,
} from '../../../main/player/plexPlaybackComposition.js';
import { DesktopPlayerAdapter } from '../../../main/player/desktopPlayerAdapter.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../../../main/plex/streamResolver.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostPort,
} from '../../../main/player/nativePlayerHostPort.js';
import {
  projectPlexPlaybackScheduleSelection,
  type PlexPlaybackPmsSessionLease,
  type PlexPlaybackRuntimeCleanupReason,
  type PlexPlaybackRuntimePmsPort,
} from '../../../main/player/plexPlaybackRuntime.js';
import type { DesktopStreamCapabilityProfile } from '../../../main/player/streamPolicy/types.js';
import { assertPublicSafe } from './playerPublicSafetyAssertions.js';
import type { PrivilegedPlaybackDispatchContext } from '../../../main/player/privilegedPlaybackDispatchContext.js';
import type { PlexPlaybackRecoveryTimerPort } from '../../../main/player/plexPlaybackRecoveryOwner.js';

const rawPrivateValues = [
  ['X', 'Plex', 'Token'].join('-'),
  ['Authorization'].join(''),
  ['Bearer'].join(''),
  ['raw', 'Plex', 'Payload'].join(''),
  ['tokenized', 'Url'].join(''),
  ['native', 'Handle'].join(''),
] as const;

const capabilityProfile: DesktopStreamCapabilityProfile = {
  id: 'rd-12-composition-profile',
  directPlayContainers: ['mp4'],
  directPlayVideoCodecs: ['h264'],
  directPlayAudioCodecs: ['aac'],
  subtitleDeliveryModes: ['embedded', 'sidecar', 'none'],
  headerAuthSetup: 'supported',
  seek: 'supported',
  audioTrackSwitching: 'supported',
  subtitleTrackSwitching: 'supported',
  hdr: 'supported',
  dolbyVision: 'unsupported',
  directStream: {
    containerRemux: 'supported',
    audioTranscode: 'supported',
    subtitleConversion: 'supported',
  },
  transcode: {
    video: 'supported',
    audio: 'supported',
    subtitles: 'supported',
    hdr: 'supported',
  },
};

const loadPayload: PlayerLoadCommandPayload = {
  media: {
    id: 'plex-media-42',
    title: 'Episode 42',
    durationMs: 1_200_000,
    container: 'mp4',
  },
  policy: {
    autoplay: true,
    startPositionMs: 60_000,
    preferredAudioTrackId: 'plex-track-audio-1-1-1',
    preferredSubtitleTrackId: null,
  },
  seekSupport: 'supported',
  capabilityProfileId: capabilityProfile.id,
};

class FakeScheduler implements Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'> {
  current: ScheduledProgram | null = {
    item: {
      ratingKey: '42',
      type: 'episode',
      title: 'Episode 42',
      fullTitle: 'Show Episode 42',
      durationMs: 1_200_000,
      thumb: null,
      year: null,
      scheduledIndex: 0,
    },
    scheduledStartTime: 1_000,
    scheduledEndTime: 1_201_000,
    scheduleIndex: 0,
    loopNumber: 0,
    streamDescriptor: null,
    isCurrent: true,
    elapsedMs: 60_000,
    remainingMs: 1_140_000,
  };

  getCurrentProgram(): ScheduledProgram {
    if (this.current === null) {
      throw new Error('no current program');
    }
    return this.current;
  }

  getState(): SchedulerState {
    return {
      isActive: this.current !== null,
      channelId: 'channel-42',
      currentProgram: this.current,
      nextProgram: null,
      schedulePosition: {
        loopNumber: 0,
        itemIndex: 0,
        offsetMs: this.current?.elapsedMs ?? 0,
      },
      lastSyncTime: 1_000,
    };
  }
}

class FakeResolver implements PlexPlaybackCompositionResolverPort {
  readonly inputs: PlexStreamResolverInput[] = [];
  result: PlexStreamResolverResult = {
    ok: true,
    privatePlayback: {
      requestId: 'request-from-runtime',
      decisionKind: 'direct-play',
      playbackUrl: 'https://plex.example.invalid/library/parts/42/file.mp4',
      credentialHeader: { name: rawPrivateValues[0], value: rawPrivateValues[1] },
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
        mediaPath: '/library/metadata/42',
        variantId: 'plex-variant-1',
        partPath: '/library/parts/42/file.mp4',
        selectedTrackIds: {
          video: 'plex-track-video-1-1-1',
          audio: 'plex-track-audio-1-1-1',
          subtitle: null,
        },
        selectedPrivateTrackIds: {
          video: 'private-video-stream',
          audio: 'private-audio-stream',
          subtitle: null,
        },
        trackMap: {
          video: [
            {
              publicTrackId: 'plex-track-video-1-1-1',
              privateTrackId: 'private-video-stream',
              codec: 'h264',
              dynamicRange: 'sdr',
            },
          ],
          audio: [
            {
              publicTrackId: 'plex-track-audio-1-1-1',
              privateTrackId: 'private-audio-stream',
              label: 'AAC',
              codec: 'aac',
            },
          ],
          subtitle: [],
        },
        audioOutputNativeKey: null,
        dtsPassthroughEnabled: false,
      },
    },
    load: loadPayload,
    decision: {
      kind: 'direct-play',
      candidateId: 'plex-candidate-1-1',
      selectedTrackIds: {
        video: 'plex-track-video-1-1-1',
        audio: 'plex-track-audio-1-1-1',
        subtitle: null,
      },
      summary: {
        media: { id: loadPayload.media.id, title: loadPayload.media.title },
        container: 'mp4',
        videoCodec: 'h264',
        audioCodec: 'aac',
        audioLanguage: null,
        subtitleDelivery: null,
        subtitleLanguage: null,
        dynamicRange: 'sdr',
        action: 'direct-play',
      },
      reasonCodes: ['direct-play-supported'],
      unknowns: [],
    },
    pmsSession: { id: 'pms-request-from-runtime', requestId: 'request-from-runtime' },
    diagnostics: [],
  };

  async resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult> {
    this.inputs.push(input);
    if (this.result.ok) {
      return {
        ...this.result,
        privatePlayback: {
          ...this.result.privatePlayback,
          requestId: input.requestId,
        },
        pmsSession: this.result.pmsSession === null
          ? null
          : { ...this.result.pmsSession, requestId: input.requestId },
      };
    }
    return this.result;
  }
}

class FakePlayerPort {
  readonly commands: PlayerCommand[] = [];
  readonly contexts: Array<PrivilegedPlaybackDispatchContext | null | undefined> = [];
  readonly cleanupRequestIds: Array<string | null> = [];

  async dispatch(
    command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<{ ok: true; events: readonly PlayerEvent[] }> {
    this.commands.push(command);
    this.contexts.push(context);
    return { ok: true, events: [] };
  }

  async cleanup(requestId: string | null): Promise<void> {
    this.cleanupRequestIds.push(requestId);
  }
}

class FakePmsPort implements PlexPlaybackRuntimePmsPort {
  readonly releases: Array<{
    session: PlexPlaybackPmsSessionLease;
    reason: PlexPlaybackRuntimeCleanupReason | 'stale';
    requestId: string;
  }> = [];

  async releaseSession(
    session: PlexPlaybackPmsSessionLease,
    input: { reason: PlexPlaybackRuntimeCleanupReason | 'stale'; requestId: string },
  ): Promise<void> {
    this.releases.push({ session, reason: input.reason, requestId: input.requestId });
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
    assert.ok(entry, 'expected pending recovery timer');
    this.pending.delete(entry[0]);
    entry[1]();
  }
}

class RejectingPlaybackHost implements NativePlayerHostPort {
  loadCount = 0;

  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    if (command.command === 'load') {
      this.loadCount += 1;
    }
    return {
      ok: false,
      error: {
        code: 'PLAYER_HELPER_PLAYBACK_ENDED_WITH_ERROR',
        category: 'engine-failure',
        message: 'private helper detail',
        recoverable: true,
        retryable: true,
      },
    };
  }

  async cleanup(): Promise<void> {}
  async queryAudioOutputs() { return { ok: true as const, outputs: [] }; }
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

class FakeDesktopPlayerAdapter {
  readonly envelopes: PlayerRendererIntentEnvelope[] = [];
  cleanupAccepted = true;
  runtimeAccepted = true;
  runtimeEvents:
    | ((command: PlayerCommand) => readonly PlayerEvent[])
    | null = null;

  async dispatchRendererIntent(envelope: PlayerRendererIntentEnvelope): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }> {
    this.envelopes.push(envelope);
    return { accepted: true, events: [] };
  }

  async dispatchRuntimeCommand(
    command: PlayerCommand,
    _context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }> {
    const toRendererIntentEnvelope = (cmd: PlayerCommand): PlayerRendererIntentEnvelope => {
      switch (cmd.command) {
        case 'load':
          return { intent: 'player.load', requestId: cmd.requestId, payload: cmd.payload };
        case 'play':
          return { intent: 'player.play', requestId: cmd.requestId, payload: {} };
        case 'pause':
          return { intent: 'player.pause', requestId: cmd.requestId, payload: {} };
        case 'stop':
          return { intent: 'player.stop', requestId: cmd.requestId, payload: {} };
        default:
          return assertUnhandledRendererIntentCommand(cmd);
      }
    };
    this.envelopes.push(toRendererIntentEnvelope(command));
    return {
      accepted: this.runtimeAccepted,
      events: this.runtimeEvents?.(command) ?? [
        {
          event: 'command.settled',
          requestId: command.requestId,
          command: command.command,
          ok: true,
        },
      ],
    };
  }

  async cleanup(): Promise<{ accepted: boolean; events: readonly PlayerEvent[] }> {
    return { accepted: this.cleanupAccepted, events: [] };
  }
}

class DeferredStopNativePlayerHost implements NativePlayerHostPort {
  readonly cleanupRequestIds: Array<string | null> = [];
  readonly stopStarted: Promise<void>;
  #resolveStopStarted: () => void = () => undefined;
  #resolveStop: (result: NativePlayerHostCommandResult) => void = () => undefined;

  constructor() {
    this.stopStarted = new Promise<void>((resolve) => {
      this.#resolveStopStarted = resolve;
    });
  }

  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    if (command.command !== 'stop') {
      return { ok: true };
    }
    this.#resolveStopStarted();
    return new Promise<NativePlayerHostCommandResult>((resolve) => {
      this.#resolveStop = resolve;
    });
  }

  async cleanup(requestId: string | null): Promise<void> {
    this.cleanupRequestIds.push(requestId);
  }

  async queryAudioOutputs() { return { ok: true as const, outputs: [] }; }

  resolveStop(): void {
    this.#resolveStop({ ok: true });
  }
}

function assertUnhandledRendererIntentCommand(command: PlayerCommand): never {
  throw new Error(`Unhandled PlayerCommand in composition test fake: ${command.command}`);
}

test('RD-12 composition wires scheduler, resolver, runtime, player, and PMS through injected main seams', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayerPort();
  const pms = new FakePmsPort();
  const emitted: PlayerEvent[][] = [];
  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player,
    pms,
    capabilityProfile,
    createRequestId: () => 'request-from-runtime',
    onEvents: (events) => emitted.push([...events]),
  });

  const result = await composition.runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, true);
  assert.equal(result.requestId, 'request-from-runtime');
  assert.equal(resolver.inputs.length, 1);
  assert.equal(resolver.inputs[0]?.mediaId, '42');
  assert.equal(resolver.inputs[0]?.startPositionMs, 60_000);
  assert.equal(resolver.inputs[0]?.capabilityProfile.id, capabilityProfile.id);
  assert.equal(player.commands.length, 1);
  assert.equal(player.commands[0]?.command, 'load');
  assert.deepEqual(player.commands[0]?.payload, loadPayload);
  assert.equal(player.contexts.length, 1);
  assert.equal(player.contexts[0]?.privatePlayback.requestId, 'request-from-runtime');
  assert.equal(
    player.contexts[0]?.privatePlayback.playbackUrl,
    resolver.result.ok ? resolver.result.privatePlayback?.playbackUrl : undefined,
  );
  assert.equal(
    player.contexts[0]?.privatePlayback.credentialHeader.name,
    resolver.result.ok ? resolver.result.privatePlayback?.credentialHeader.name : undefined,
  );
  assertPublicSafe(result, rawPrivateValues);
  assertPublicSafe(emitted, rawPrivateValues);

  const cleanupEvents = await composition.runtime.cleanup({ reason: 'teardown' });

  assert.deepEqual(cleanupEvents, []);
  assert.deepEqual(pms.releases, [
    {
      session: { id: 'pms-request-from-runtime', requestId: 'request-from-runtime' },
      reason: 'teardown',
      requestId: 'request-from-runtime',
    },
  ]);
  assert.deepEqual(player.cleanupRequestIds, ['request-from-runtime']);
});

test('playback composition carries an exact-current manual retry through its runtime port', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayerPort();
  const pms = new FakePmsPort();
  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player,
    pms,
    capabilityProfile,
    createRequestId: () => 'request-from-runtime',
  });
  await composition.runtime.startCurrentPlayback('startup');
  const current = scheduler.getCurrentProgram();

  const retried = await composition.runtime.retryCurrentPlayback(
    projectPlexPlaybackScheduleSelection({
      channelId: scheduler.getState().channelId,
      ratingKey: current.item.ratingKey,
      scheduledStartTime: current.scheduledStartTime,
      scheduledEndTime: current.scheduledEndTime,
    }),
  );

  assert.equal(retried, true);
  assert.equal(resolver.inputs.length, 2);
  assert.deepEqual(
    resolver.inputs.map((input) => input.mediaId),
    ['42', '42'],
  );
  assert.deepEqual(
    player.commands.map((command) => command.command),
    ['load', 'load'],
  );
  assert.deepEqual(player.cleanupRequestIds, ['request-from-runtime']);
  assert.deepEqual(
    pms.releases.map((release) => release.reason),
    ['switch'],
  );
});

test('RD-17 composition passes diagnostics store into playback runtime', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayerPort();
  const pms = new FakePmsPort();
  const diagnostics = new DiagnosticEventStore({
    clock: () => 17_000,
    idGenerator: () => 'composition-diagnostic',
  });
  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player,
    pms,
    capabilityProfile,
    createRequestId: () => 'request-from-runtime',
    diagnosticEventStore: diagnostics,
  });

  await composition.runtime.startCurrentPlayback('schedule-tick');
  await composition.runtime.handleHelperCrash();

  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
  assert.deepEqual(player.cleanupRequestIds, ['request-from-runtime']);
  assertPublicSafe(diagnostics.getRecords(), rawPrivateValues);
});

test('playback composition propagates the recovery timer and runtime event sink', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayerPort();
  const pms = new FakePmsPort();
  const recoveryTimer = new FakeRecoveryTimer();
  const emitted: PlayerEvent[] = [];
  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player,
    pms,
    capabilityProfile,
    createRequestId: () => 'request-from-runtime',
    recoveryTimer,
    onEvents: (events) => emitted.push(...events),
  });
  await composition.runtime.startCurrentPlayback('startup');
  emitted.length = 0;

  composition.runtime.ingestPlayerEvents([
    {
      event: 'error',
      requestId: 'request-from-runtime',
      error: {
        code: 'PLAYER_HOST_ENGINE_FAILURE',
        category: 'engine-failure',
        message: 'The player engine failed.',
        recoverable: true,
        retryable: true,
        requestId: 'request-from-runtime',
      },
    },
  ]);

  assert.equal(emitted.length, 1);
  assert.equal(emitted[0]?.event, 'error');
  assert.deepEqual(recoveryTimer.delays, [1_000]);
});

test('RD-12 desktop adapter runtime port maps main-owned player commands without exposing Plex setup', async () => {
  const adapter = new FakeDesktopPlayerAdapter();
  const player = createDesktopPlayerAdapterRuntimePort(adapter);

  const loadResult = await player.dispatch({
    command: 'load',
    requestId: 'request-from-runtime',
    payload: loadPayload,
  });
  const playResult = await player.dispatch({
    command: 'play',
    requestId: 'request-from-runtime',
    payload: {},
  });

  assert.equal(loadResult.ok, true);
  assert.equal(playResult.ok, true);
  assert.deepEqual(adapter.envelopes.map((envelope) => envelope.intent), ['player.load', 'player.play']);
  assert.deepEqual(adapter.envelopes[0], {
    intent: 'player.load',
    requestId: 'request-from-runtime',
    payload: loadPayload,
  });
  assert.deepEqual(adapter.envelopes[1], {
    intent: 'player.play',
    requestId: 'request-from-runtime',
    payload: {},
  });
  assertPublicSafe(adapter.envelopes, rawPrivateValues);
});

test('desktop adapter runtime port requires one exact successful command settlement', async () => {
  const cases: Array<{
    name: string;
    events(command: PlayerCommand): readonly PlayerEvent[];
  }> = [
    {
      name: 'missing',
      events: () => [],
    },
    {
      name: 'mismatched request',
      events: (command) => [{
        event: 'command.settled',
        requestId: `${command.requestId}-other`,
        command: command.command,
        ok: true,
      }],
    },
    {
      name: 'failed',
      events: (command) => [{
        event: 'command.settled',
        requestId: command.requestId,
        command: command.command,
        ok: false,
      }],
    },
    {
      name: 'conflicting',
      events: (command) => [
        {
          event: 'command.settled',
          requestId: command.requestId,
          command: command.command,
          ok: true,
        },
        {
          event: 'command.settled',
          requestId: command.requestId,
          command: command.command,
          ok: false,
        },
      ],
    },
    {
      name: 'matching plus mismatched',
      events: (command) => [
        {
          event: 'command.settled',
          requestId: command.requestId,
          command: command.command,
          ok: true,
        },
        {
          event: 'command.settled',
          requestId: `${command.requestId}-other`,
          command: command.command,
          ok: true,
        },
      ],
    },
  ];

  for (const entry of cases) {
    const adapter = new FakeDesktopPlayerAdapter();
    adapter.runtimeEvents = entry.events;
    const player = createDesktopPlayerAdapterRuntimePort(adapter);
    const command: PlayerCommand = {
      command: 'load',
      requestId: `request-${entry.name}`,
      payload: loadPayload,
    };

    const result = await player.dispatch(command);

    assert.equal(result.ok, false, entry.name);
    assert.deepEqual(result.events, entry.events(command), entry.name);
  }
});

test('real desktop adapter host rejection consumes exactly three recovery attempts', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const pms = new FakePmsPort();
  const recoveryTimer = new FakeRecoveryTimer();
  const host = new RejectingPlaybackHost();
  const adapter = new DesktopPlayerAdapter(host);
  let requestCounter = 0;
  const emitted: PlayerEvent[] = [];
  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player: createDesktopPlayerAdapterRuntimePort(adapter),
    pms,
    capabilityProfile,
    recoveryTimer,
    createRequestId: () => {
      requestCounter += 1;
      return `recovery-request-${requestCounter}`;
    },
    onEvents: (events) => emitted.push(...events),
  });

  const initial = await composition.runtime.startCurrentPlayback('startup');
  assert.equal(initial.accepted, false);
  assert.deepEqual(recoveryTimer.delays, [1_000]);

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    recoveryTimer.runNext();
    await waitFor(
      () => host.loadCount === attempt + 1,
      `recovery load ${attempt} did not settle`,
    );
    await new Promise<void>((resolve) => setImmediate(resolve));
  }

  assert.equal(host.loadCount, 4);
  assert.deepEqual(recoveryTimer.delays, [1_000, 2_000, 4_000]);
  assert.equal(recoveryTimer.pending.size, 0);
  assert.equal(
    emitted.filter((event) => (
      event.event === 'error' &&
      event.error.code === 'PLAYER_HOST_ENGINE_FAILURE'
    )).length,
    4,
  );
  assert.equal(
    emitted.some((event) => (
      event.event === 'command.settled' &&
      event.ok === false
    )),
    true,
  );
  assertPublicSafe(emitted, [...rawPrivateValues, 'private helper detail']);
});

test('RD-12 desktop adapter runtime port reports cleanup rejection to runtime cleanup owner', async () => {
  const adapter = new FakeDesktopPlayerAdapter();
  adapter.cleanupAccepted = false;
  const player = createDesktopPlayerAdapterRuntimePort(adapter);

  await assert.rejects(() => player.cleanup('request-from-runtime'), {
    message: 'Desktop player adapter cleanup failed.',
  });
});

test('desktop adapter runtime port starts a fresh replacement only after prior stop cleanup settles', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const pms = new FakePmsPort();
  const host = new DeferredStopNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  const requestIds = ['request-a', 'request-b'];
  const composition = createPlexPlaybackRuntimeComposition({
    scheduler,
    resolver,
    player: createDesktopPlayerAdapterRuntimePort(adapter),
    pms,
    capabilityProfile,
    createRequestId: () => {
      const requestId = requestIds.shift();
      assert.ok(requestId, 'expected a playback request id');
      return requestId;
    },
  });
  const first = await composition.runtime.startCurrentPlayback('startup');
  assert.equal(first.requestId, 'request-a');

  const stopping = composition.runtime.stop();
  await host.stopStarted;
  const blockedReplacement =
    await composition.runtime.startCurrentPlayback('manual-switch');

  assert.deepEqual(blockedReplacement, {
    accepted: false,
    epoch: composition.runtime.getCurrentEpoch(),
    requestId: null,
    events: [],
  });
  assert.deepEqual(requestIds, ['request-b']);
  assert.equal(resolver.inputs.length, 1);
  assert.notEqual(adapter.getSnapshot().requestId, 'request-b');
  assert.equal(pms.releases.length, 0);

  host.resolveStop();
  await stopping;

  assert.equal(composition.runtime.getActiveRequestId(), null);
  assert.equal(adapter.getSnapshot().requestId, null);
  assert.deepEqual(
    pms.releases.map((release) => ({
      requestId: release.requestId,
      reason: release.reason,
    })),
    [{ requestId: 'request-a', reason: 'stop' }],
  );

  const replacement =
    await composition.runtime.startCurrentPlayback('manual-switch');
  assert.equal(replacement.accepted, true);
  assert.equal(replacement.requestId, 'request-b');
  assert.deepEqual(requestIds, []);
  assert.equal(resolver.inputs.length, 2);
  assert.equal(composition.runtime.getActiveRequestId(), 'request-b');
  assert.equal(adapter.getSnapshot().requestId, 'request-b');
  assert.deepEqual(host.cleanupRequestIds, ['request-a']);

  await composition.runtime.teardown();
  assert.deepEqual(host.cleanupRequestIds, ['request-a', 'request-b']);
  assert.equal(adapter.getSnapshot().requestId, null);
  assert.deepEqual(
    pms.releases.map((release) => ({
      requestId: release.requestId,
      reason: release.reason,
    })),
    [
      { requestId: 'request-a', reason: 'stop' },
      { requestId: 'request-b', reason: 'teardown' },
    ],
  );
});
