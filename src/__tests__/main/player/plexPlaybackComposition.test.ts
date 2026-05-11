import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlayerCommand, PlayerEvent } from '../../../contracts/player.js';
import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerLoadCommandPayload,
} from '../../../contracts/player.js';
import type { PlayerRendererIntentEnvelope } from '../../../contracts/ipc.js';
import type { IChannelScheduler, ScheduledProgram, SchedulerState } from '../../../domain/scheduler/index.js';
import {
  createDesktopPlayerAdapterRuntimePort,
  createPlexPlaybackRuntimeComposition,
  type PlexPlaybackCompositionResolverPort,
} from '../../../main/player/plexPlaybackComposition.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from '../../../main/plex/streamResolver.js';
import type {
  PlexPlaybackPmsSessionLease,
  PlexPlaybackRuntimeCleanupReason,
  PlexPlaybackRuntimePmsPort,
} from '../../../main/player/plexPlaybackRuntime.js';
import type { DesktopStreamCapabilityProfile } from '../../../main/player/streamPolicy/types.js';

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
        subtitleDelivery: null,
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
  readonly cleanupRequestIds: Array<string | null> = [];

  async dispatch(command: PlayerCommand): Promise<{ ok: true; events: readonly PlayerEvent[] }> {
    this.commands.push(command);
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

class FakeDesktopPlayerAdapter {
  readonly envelopes: PlayerRendererIntentEnvelope[] = [];
  cleanupAccepted = true;

  async dispatchRendererIntent(envelope: PlayerRendererIntentEnvelope): Promise<{
    accepted: boolean;
    events: readonly PlayerEvent[];
  }> {
    this.envelopes.push(envelope);
    return { accepted: true, events: [] };
  }

  async cleanup(): Promise<{ accepted: boolean; events: readonly PlayerEvent[] }> {
    return { accepted: this.cleanupAccepted, events: [] };
  }
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

test('RD-12 desktop adapter runtime port reports cleanup rejection to runtime cleanup owner', async () => {
  const adapter = new FakeDesktopPlayerAdapter();
  adapter.cleanupAccepted = false;
  const player = createDesktopPlayerAdapterRuntimePort(adapter);

  await assert.rejects(() => player.cleanup('request-from-runtime'), {
    message: 'Desktop player adapter cleanup failed.',
  });
});

function assertPublicSafe(value: unknown, forbiddenValues: readonly string[]): void {
  const text = JSON.stringify(value);
  for (const key of PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS) {
    assert.equal(text.includes(key), false, `public value included forbidden key ${key}`);
  }
  for (const forbiddenValue of forbiddenValues) {
    assert.equal(
      text.includes(forbiddenValue),
      false,
      `public value included private value ${forbiddenValue}`,
    );
  }
}
