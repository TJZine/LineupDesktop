import test from 'node:test';
import assert from 'node:assert/strict';

import {
  isRendererSafePlayerEvent,
  type PlayerCommand,
  type PlayerError,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
} from '../../../contracts/player.js';
import type { IChannelScheduler, ScheduledProgram, SchedulerState } from '../../../domain/scheduler/index.js';
import {
  PlexPlaybackBridge,
  type PlexPlaybackBridgeResolverPort,
} from '../../../main/player/plexPlaybackBridge.js';
import {
  PlexPlaybackRuntime,
  type PlexPlaybackRuntimePlayerDispatchResult,
  type PlexPlaybackRuntimePlayerPort,
} from '../../../main/player/plexPlaybackRuntime.js';
import type { DesktopStreamCapabilityProfile } from '../../../main/player/streamPolicy/types.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../../../main/plex/streamResolver.js';
import { assertPublicSafe } from './playerPublicSafetyAssertions.js';

const rawPrivateValues = [
  'raw-stream-id-main',
  'https://private.example/library/parts/main',
  'X-Private-Header',
  '/Users/example/Library/Application Support/Lineup',
  'ElectronPrivateObject',
] as const;

const capabilityProfile: DesktopStreamCapabilityProfile = {
  id: 'bridge-capability-profile',
  directPlayContainers: ['mkv'],
  directPlayVideoCodecs: ['h264'],
  directPlayAudioCodecs: ['aac'],
  subtitleDeliveryModes: ['embedded', 'none'],
  headerAuthSetup: 'supported',
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
  unknowns: ['desktop-parity-unproven'],
};

const loadPayload: PlayerLoadCommandPayload = {
  media: {
    id: 'plex-media-rating-1',
    title: 'Bridge Safe Episode',
    durationMs: 1_800_000,
    container: 'mkv',
  },
  policy: {
    autoplay: true,
    startPositionMs: 90_000,
    preferredAudioTrackId: 'plex-track-audio-1',
    preferredSubtitleTrackId: null,
  },
  capabilityProfileId: capabilityProfile.id,
};

class FakeScheduler implements Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'> {
  state: SchedulerState = {
    channelId: 'channel-safe',
    isActive: true,
    currentProgram: createProgram(),
    nextProgram: null,
    schedulePosition: { loopNumber: 0, itemIndex: 0, offsetMs: 90_000 },
    lastSyncTime: 1_090_000,
  };
  current: ScheduledProgram | null = this.state.currentProgram;

  getCurrentProgram(): ScheduledProgram {
    if (this.current === null) {
      throw new Error('no channel loaded');
    }
    return this.current;
  }

  getState(): SchedulerState {
    return this.state;
  }
}

class FakeResolver implements PlexPlaybackBridgeResolverPort {
  readonly inputs: PlexStreamResolverInput[] = [];
  result: PlexStreamResolverResult = {
    ok: true,
    privatePlayback: {
      requestId: 'request-private',
      decisionKind: 'direct-play',
      playbackUrl: rawPrivateValues[1],
      credentialHeader: { name: rawPrivateValues[2], value: 'private-value' },
      selectedConnection: {
        protocol: 'https',
        address: 'private.example',
        port: 443,
        local: false,
        relay: false,
      },
      media: { id: 'plex-media-rating-1', title: 'Bridge Safe Episode' },
      setup: {
        playbackMode: 'direct-play',
        mediaPath: '/library/metadata/rating-1',
        variantId: 'plex-variant-main',
        partPath: '/library/parts/main',
        selectedTrackIds: {
          video: 'plex-track-video-1',
          audio: 'plex-track-audio-1',
          subtitle: null,
        },
        selectedPrivateTrackIds: {
          video: rawPrivateValues[0],
          audio: null,
          subtitle: null,
        },
      },
    },
    load: loadPayload,
    decision: {
      kind: 'direct-play',
      candidateId: 'plex-candidate-main',
      selectedTrackIds: {
        video: 'plex-track-video-1',
        audio: 'plex-track-audio-1',
        subtitle: null,
      },
      summary: {
        media: { id: 'plex-media-rating-1', title: 'Bridge Safe Episode' },
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        audioLanguage: null,
        subtitleDelivery: null,
        subtitleLanguage: null,
        dynamicRange: 'sdr',
        action: 'direct-play',
      },
      reasonCodes: ['direct-play-supported', 'no-subtitle-selected'],
      unknowns: [],
    },
    pmsSession: { id: 'pms-request-bridge', requestId: 'request-bridge' },
    diagnostics: [],
  };

  async resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult> {
    this.inputs.push(input);
    return this.result;
  }
}

class FakePlayer implements PlexPlaybackRuntimePlayerPort {
  readonly commands: PlayerCommand[] = [];

  async dispatch(command: PlayerCommand): Promise<PlexPlaybackRuntimePlayerDispatchResult> {
    this.commands.push(command);
    return { ok: true };
  }

  async cleanup(): Promise<void> {
    return undefined;
  }
}

class FakePms {
  readonly releases: Array<{
    session: { id: string; requestId: string };
    reason: string;
    requestId: string;
  }> = [];

  async releaseSession(
    session: { id: string; requestId: string },
    input: { reason: string; requestId: string },
  ): Promise<void> {
    this.releases.push({ session, reason: input.reason, requestId: input.requestId });
    return undefined;
  }
}

test('RD-12 bridge maps current scheduler program to resolver input and runtime load candidate', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayer();
  const bridge = new PlexPlaybackBridge({
    scheduler,
    resolver,
    capabilityProfile,
    createRequestId: () => 'request-bridge',
  });
  const runtime = new PlexPlaybackRuntime({
    scheduler: bridge,
    channel: bridge,
    player,
    pms: new FakePms(),
  });

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, true);
  assert.equal(result.requestId, 'request-bridge');
  assert.equal(resolver.inputs.length, 1);
  assert.equal(resolver.inputs[0]?.requestId, 'request-bridge');
  assert.equal(resolver.inputs[0]?.mediaId, 'rating-1');
  assert.equal(resolver.inputs[0]?.startPositionMs, 90_000);
  assert.equal(resolver.inputs[0]?.autoplay, true);
  assert.equal(resolver.inputs[0]?.capabilityProfile.id, capabilityProfile.id);
  assert.equal(player.commands.length, 1);
  assert.equal(player.commands[0]?.command, 'load');
  assert.deepEqual(player.commands[0]?.payload, loadPayload);
  assertPublicSafe(result, rawPrivateValues);
  assertPublicSafe(player.commands[0], rawPrivateValues);
});

test('RD-12 bridge returns no selection for inactive or unloaded scheduler state', async () => {
  const scheduler = new FakeScheduler();
  scheduler.current = null;
  scheduler.state = {
    ...scheduler.state,
    isActive: false,
    currentProgram: null,
    channelId: '',
  };
  const resolver = new FakeResolver();
  const player = new FakePlayer();
  const bridge = new PlexPlaybackBridge({ scheduler, resolver, capabilityProfile });
  const runtime = new PlexPlaybackRuntime({
    scheduler: bridge,
    channel: bridge,
    player,
    pms: new FakePms(),
  });

  const result = await runtime.startCurrentPlayback('startup');

  assert.equal(result.accepted, false);
  assert.equal(result.requestId, null);
  assert.equal(resolver.inputs.length, 0);
  assert.equal(player.commands.length, 0);
  assert.equal(result.events[0]?.event, 'warning');
  assertRendererSafePlayerEvents(result.events);
  assertPublicSafe(result, rawPrivateValues);
});

test('RD-12 bridge trims scheduler channel id before projecting selections', async () => {
  const scheduler = new FakeScheduler();
  scheduler.state = { ...scheduler.state, channelId: '  channel-safe  ' };
  const resolver = new FakeResolver();
  const bridge = new PlexPlaybackBridge({ scheduler, resolver, capabilityProfile });

  const selection = await bridge.getCurrentPlayback({
    nowMs: 1_090_000,
    reason: 'schedule-tick',
  });

  assert.notEqual(selection, null);
  assert.equal(selection?.channelId, 'channel-safe');
  assert.equal(selection?.programId.startsWith('program-channel-safe-'), true);
  assertPublicSafe(selection, rawPrivateValues);
});

test('RD-12 bridge normalizes resolver failure before player dispatch', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayer();
  resolver.result = {
    ok: false,
    error: createSafeResolverError('request-bridge'),
    diagnostics: [
      {
        component: 'plex-stream-resolver',
        operation: 'stream.resolve',
        status: 'failed',
        reason: 'selected connection unavailable',
      },
    ],
  };
  const bridge = new PlexPlaybackBridge({
    scheduler,
    resolver,
    capabilityProfile,
    createRequestId: () => 'request-bridge',
  });
  const runtime = new PlexPlaybackRuntime({
    scheduler: bridge,
    channel: bridge,
    player,
    pms: new FakePms(),
  });

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(player.commands.length, 0);
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0]?.event, 'error');
  if (result.events[0]?.event === 'error') {
    assert.equal(result.events[0].error.code, 'PLEX_STREAM_CONNECTION_UNAVAILABLE');
    assert.equal(result.events[0].error.requestId, 'request-bridge');
  }
  assertRendererSafePlayerEvents(result.events);
  assertPublicSafe(result, rawPrivateValues);
});

test('RD-12 bridge rejects mismatched PMS session lease before player dispatch', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayer();
  const pms = new FakePms();
  if (!resolver.result.ok) {
    throw new Error('expected success resolver fixture');
  }
  resolver.result = {
    ...resolver.result,
    pmsSession: { id: 'pms-request-bridge', requestId: 'request-from-other-runtime' },
  };
  const bridge = new PlexPlaybackBridge({
    scheduler,
    resolver,
    capabilityProfile,
    createRequestId: () => 'request-bridge',
  });
  const runtime = new PlexPlaybackRuntime({
    scheduler: bridge,
    channel: bridge,
    player,
    pms,
  });

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(result.requestId, 'request-bridge');
  assert.equal(runtime.getActiveRequestId(), null);
  assert.equal(player.commands.length, 0);
  assert.deepEqual(pms.releases, [
    {
      session: { id: 'pms-request-bridge', requestId: 'request-from-other-runtime' },
      reason: 'stale',
      requestId: 'request-bridge',
    },
  ]);
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0]?.event, 'error');
  if (result.events[0]?.event === 'error') {
    assert.equal(result.events[0].requestId, 'request-bridge');
    assert.equal(result.events[0].error.code, 'PLAYER_RUNTIME_VALIDATION_FAILED');
    assert.equal(result.events[0].error.category, 'validation-failure');
    assert.equal(result.events[0].error.requestId, 'request-bridge');
    assert.equal(result.events[0].error.diagnostic?.component, 'plex-playback-runtime');
    assert.equal(result.events[0].error.diagnostic?.operation, 'validation');
    assert.equal(result.events[0].error.diagnostic?.status, 'rejected');
  }
  assertRendererSafePlayerEvents(result.events);
  assertPublicSafe(result, [...rawPrivateValues, 'request-from-other-runtime']);
});

test('RD-12 bridge rejects stale selections without resolver or player dispatch', async () => {
  const scheduler = new FakeScheduler();
  const resolver = new FakeResolver();
  const player = new FakePlayer();
  const bridge = new PlexPlaybackBridge({
    scheduler,
    resolver,
    capabilityProfile,
    createRequestId: () => 'request-bridge',
  });
  const selection = await bridge.getCurrentPlayback({
    nowMs: 1_090_000,
    reason: 'schedule-tick',
  });
  assert.notEqual(selection, null);
  scheduler.current = createProgram({ ratingKey: 'rating-2', scheduledStartTime: 1_100_000 });
  scheduler.state = {
    ...scheduler.state,
    currentProgram: scheduler.current,
  };
  const runtime = new PlexPlaybackRuntime({
    scheduler: {
      async getCurrentPlayback() {
        return selection;
      },
    },
    channel: bridge,
    player,
    pms: new FakePms(),
  });

  const result = await runtime.startCurrentPlayback('schedule-tick');

  assert.equal(result.accepted, false);
  assert.equal(resolver.inputs.length, 0);
  assert.equal(player.commands.length, 0);
  assert.equal(result.events[0]?.event, 'error');
  if (result.events[0]?.event === 'error') {
    assert.equal(result.events[0].error.category, 'stale-request');
    assert.equal(result.events[0].error.code, 'PLEX_PLAYBACK_PROGRAM_STALE');
  }
  assertRendererSafePlayerEvents(result.events);
  assertPublicSafe(result, rawPrivateValues);
});

test('RD-12 bridge keeps streamDescriptor private and public outputs redacted', async () => {
  const scheduler = new FakeScheduler();
  scheduler.current = createProgram({
    streamDescriptor: {
      rawPlexPayload: { id: rawPrivateValues[0] },
      tokenizedUrl: rawPrivateValues[1],
      runtimePath: rawPrivateValues[3],
      electronApi: rawPrivateValues[4],
    },
  });
  scheduler.state = { ...scheduler.state, currentProgram: scheduler.current };
  const resolver = new FakeResolver();
  const bridge = new PlexPlaybackBridge({
    scheduler,
    resolver,
    capabilityProfile,
    createRequestId: () => 'request-bridge',
  });

  const selection = await bridge.getCurrentPlayback({
    nowMs: 1_090_000,
    reason: 'schedule-tick',
  });
  assert.notEqual(selection, null);
  if (selection === null) {
    throw new Error('expected current playback selection');
  }
  const candidate = await bridge.resolvePlaybackCandidate(selection);

  assert.equal(resolver.inputs[0]?.mediaId, 'rating-1');
  assertPublicSafe(selection, rawPrivateValues);
  assertPublicSafe(candidate, rawPrivateValues);
  assertPublicSafe(resolver.inputs[0], rawPrivateValues);
});

function createProgram(options: {
  ratingKey?: string;
  scheduledStartTime?: number;
  streamDescriptor?: unknown;
} = {}): ScheduledProgram {
  const scheduledStartTime = options.scheduledStartTime ?? 1_000_000;
  return {
    item: {
      ratingKey: options.ratingKey ?? 'rating-1',
      type: 'episode',
      title: 'Bridge Safe Episode',
      fullTitle: 'Bridge Safe Show - Bridge Safe Episode',
      durationMs: 1_800_000,
      thumb: null,
      year: 2026,
      scheduledIndex: 0,
      showTitle: 'Bridge Safe Show',
      seasonNumber: 1,
      episodeNumber: 1,
    },
    scheduledStartTime,
    scheduledEndTime: scheduledStartTime + 1_800_000,
    elapsedMs: 90_000,
    remainingMs: 1_710_000,
    scheduleIndex: 0,
    loopNumber: 0,
    streamDescriptor: options.streamDescriptor ?? null,
    isCurrent: true,
  };
}

function createSafeResolverError(requestId: string): PlayerError {
  return {
    code: 'PLEX_STREAM_CONNECTION_UNAVAILABLE',
    category: 'source',
    message: 'The Plex stream resolver could not prepare media for playback.',
    recoverable: true,
    retryable: true,
    requestId,
    diagnostic: {
      component: 'plex-stream-resolver',
      operation: 'stream.resolve',
      status: 'failed',
      reason: 'selected connection unavailable',
    },
  };
}

function assertRendererSafePlayerEvents(events: readonly PlayerEvent[]): void {
  for (const event of events) {
    assert.equal(isRendererSafePlayerEvent(event), true, `unsafe player event ${event.event}`);
  }
}
