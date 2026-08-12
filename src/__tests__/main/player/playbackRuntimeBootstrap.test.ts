import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlayerCommand, PlayerEvent } from '../../../contracts/player.js';
import type { IChannelScheduler, ScheduledProgram, SchedulerState } from '../../../domain/scheduler/index.js';
import {
  bootstrapPlaybackRuntime,
  getProductionCapabilityProfile,
} from '../../../main/player/playbackRuntimeBootstrap.js';
import { DesktopPlayerAdapter } from '../../../main/player/desktopPlayerAdapter.js';
import type { NativePlayerHostPort } from '../../../main/player/nativePlayerHostPort.js';
import type { PrivilegedPlaybackDispatchContext } from '../../../main/player/privilegedPlaybackDispatchContext.js';

function createActiveScheduler(ratingKey = 'bootstrap-rating-key'): Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'> {
  const program: ScheduledProgram = {
    item: {
      ratingKey,
      type: 'episode',
      title: 'Bootstrap Episode',
      fullTitle: 'Bootstrap Episode',
      durationMs: 120_000,
      thumb: null,
      year: null,
      scheduledIndex: 0,
    },
    scheduledStartTime: 1_000,
    scheduledEndTime: 121_000,
    scheduleIndex: 0,
    loopNumber: 0,
    streamDescriptor: null,
    isCurrent: true,
    elapsedMs: 5_000,
    remainingMs: 115_000,
  };
  return {
    getCurrentProgram: () => program,
    getState: (): SchedulerState => ({
      isActive: true,
      channelId: 'bootstrap-channel',
      currentProgram: program,
      nextProgram: null,
      schedulePosition: { loopNumber: 0, itemIndex: 0, offsetMs: 5_000 },
      lastSyncTime: 1_000,
    }),
  };
}

const SMOKE_PRIVATE_VALUES = [
  'privatePlayback',
  'credentialHeader',
  'X-Plex-Token',
  'mock-token',
  'https://mock.plex.invalid/file.mp4',
  '/library/metadata/mock',
  '/library/parts/mock/file.mp4',
  'smoke-private-key',
] as const;

function assertSmokePrivateValuesAbsent(value: unknown): void {
  const serialized = JSON.stringify(value);
  for (const privateValue of SMOKE_PRIVATE_VALUES) {
    assert.equal(serialized.includes(privateValue), false, `exposed smoke private value: ${privateValue}`);
  }
}

class CapturingHost implements NativePlayerHostPort {
  readonly contexts: Array<PrivilegedPlaybackDispatchContext | null | undefined> = [];

  async execute(
    _command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ) {
    this.contexts.push(context);
    return { ok: true as const };
  }

  async cleanup() {}
  async queryAudioOutputs() { return { ok: true as const, outputs: [] }; }
}

test('production playback capability profile advertises only proven conservative native-helper behaviors', () => {
  const profile = getProductionCapabilityProfile();

  assert.equal(profile.id, 'windows-native-production-conservative');
  assert.deepEqual(profile.directPlayContainers, ['mp4']);
  assert.deepEqual(profile.directPlayVideoCodecs, ['h264']);
  assert.deepEqual(profile.directPlayAudioCodecs, ['aac']);
  assert.deepEqual(profile.subtitleDeliveryModes, ['none']);
  assert.equal(profile.headerAuthSetup, 'supported');
  assert.equal(profile.seek, 'supported');
  assert.equal(profile.audioTrackSwitching, 'unsupported');
  assert.equal(profile.subtitleTrackSwitching, 'unsupported');
  assert.equal(profile.hdr, 'unsupported');
  assert.equal(profile.dolbyVision, 'unsupported');
  assert.equal(profile.directStream.containerRemux, 'unsupported');
  assert.equal(profile.directStream.audioTranscode, 'unsupported');
  assert.equal(profile.directStream.subtitleConversion, 'unsupported');
  assert.equal(profile.transcode.video, 'unsupported');
  assert.equal(profile.transcode.audio, 'unsupported');
  assert.equal(profile.transcode.subtitles, 'unsupported');
  assert.equal(profile.transcode.hdr, 'unsupported');
});

test('playback bootstrap wires runtime events in smoke and production modes', async () => {
  for (const shellMode of ['smoke', 'production'] as const) {
    const emitted: PlayerEvent[] = [];
    const result = bootstrapPlaybackRuntime({
      shellMode,
      scheduler: {
        getCurrentProgram() {
          throw new Error('no current program');
        },
        getState() {
          throw new Error('inactive scheduler');
        },
      },
      adapter: null,
      createRequestId: (prefix) => `${prefix}-${shellMode}`,
      onEvents: (events) => emitted.push(...events),
    });

    const start = await result.runtime.startCurrentPlayback('startup');

    assert.equal(start.accepted, false);
    assert.equal(emitted.length, 1);
    assert.equal(emitted[0]?.event, 'warning');
  }
});

test('adapter-less production bootstrap publishes one candidate error with no snapshot claim', async () => {
  const emittedBatches: Array<readonly PlayerEvent[]> = [];
  const result = bootstrapPlaybackRuntime({
    shellMode: 'production',
    scheduler: createActiveScheduler(),
    adapter: null,
    createRequestId: (prefix) => `${prefix}-fallback`,
    onEvents: (events) => emittedBatches.push(events),
  });

  const start = await result.runtime.startCurrentPlayback('startup');

  assert.equal(start.accepted, false);
  assert.equal(emittedBatches.length, 1);
  assert.equal(start.events.length, 1);
  assert.equal(start.events[0]?.event, 'error');
  assert.equal(start.events.some((event) => event.event === 'state.changed'), false);
  assert.equal(emittedBatches[0]?.[0], start.events[0]);
});

test('adapter-backed production bootstrap settles candidate failure through the adapter snapshot owner', async () => {
  const emitted: PlayerEvent[] = [];
  const adapter = new DesktopPlayerAdapter(new CapturingHost());
  const result = bootstrapPlaybackRuntime({
    shellMode: 'production',
    scheduler: createActiveScheduler(),
    adapter,
    createRequestId: (prefix) => `${prefix}-adapter`,
    onEvents: (events) => emitted.push(...events),
  });

  const start = await result.runtime.startCurrentPlayback('startup');

  assert.equal(start.accepted, false);
  assert.deepEqual(emitted.map((event) => event.event), ['error', 'state.changed']);
  const changed = emitted[1];
  assert.equal(changed?.event, 'state.changed');
  assert.deepEqual(changed?.event === 'state.changed' ? changed.snapshot : null, adapter.getSnapshot());
});

test('adapter-backed smoke bootstrap passes private playback only to privileged dispatch context', async () => {
  const host = new CapturingHost();
  const adapter = new DesktopPlayerAdapter(host);
  const emitted: PlayerEvent[] = [];
  const result = bootstrapPlaybackRuntime({
    shellMode: 'smoke',
    scheduler: createActiveScheduler('smoke-private-key'),
    adapter,
    createRequestId: (prefix) => `${prefix}-private-context`,
    onEvents: (events) => emitted.push(...events),
  });

  const start = await result.runtime.startCurrentPlayback('startup');

  assert.equal(start.accepted, true);
  assert.equal(host.contexts.length, 1);
  const privatePlayback = host.contexts[0]?.privatePlayback;
  assert.ok(privatePlayback);
  assert.equal(Object.hasOwn(host.contexts[0] ?? {}, 'privatePlayback'), true);
  assert.equal(privatePlayback.requestId, 'plex-playback-private-context');
  assert.equal(privatePlayback.decisionKind, 'direct-play');
  assert.equal(privatePlayback.playbackUrl, 'https://mock.plex.invalid/file.mp4');
  assert.deepEqual(privatePlayback.credentialHeader, {
    name: 'X-Plex-Token',
    value: 'mock-token',
  });
  assert.deepEqual(privatePlayback.selectedConnection, {
    protocol: 'https',
    address: 'mock.plex.invalid',
    port: 443,
    local: true,
    relay: false,
  });
  assert.deepEqual(privatePlayback.setup, {
    playbackMode: 'direct-play',
    mediaPath: '/library/metadata/mock',
    variantId: 'mock-variant',
    partPath: '/library/parts/mock/file.mp4',
    selectedTrackIds: { video: null, audio: null, subtitle: null },
    selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
    trackMap: { video: [], audio: [], subtitle: [] },
    audioOutputNativeKey: null,
    dtsPassthroughEnabled: false,
  });
  assertSmokePrivateValuesAbsent(start.events);
  assertSmokePrivateValuesAbsent(emitted);
  assertSmokePrivateValuesAbsent(adapter.getSnapshot());
  assert.equal(Object.hasOwn(adapter.getSnapshot(), 'privatePlayback'), false);
});

test('smoke bootstrap identifies an empty Plex rating key before deriving fake media fields', async () => {
  const result = bootstrapPlaybackRuntime({
    shellMode: 'smoke',
    scheduler: createActiveScheduler(''),
    adapter: null,
    createRequestId: (prefix) => `${prefix}-missing-rating-key`,
    onEvents: () => undefined,
  });

  const start = await result.runtime.startCurrentPlayback('startup');

  assert.equal(start.accepted, false);
  const error = start.events.find((event) => event.event === 'error');
  assert.equal(error?.event === 'error' ? error.error.message : null, 'Missing Plex rating key');
});

test('smoke bootstrap rejects a whitespace-only Plex rating key as resource missing', async () => {
  const result = bootstrapPlaybackRuntime({
    shellMode: 'smoke',
    scheduler: createActiveScheduler('  \t  '),
    adapter: null,
    createRequestId: (prefix) => `${prefix}-whitespace-rating-key`,
    onEvents: () => undefined,
  });

  const start = await result.runtime.startCurrentPlayback('startup');
  const error = start.events.find((event) => event.event === 'error');

  assert.equal(start.accepted, false);
  assert.deepEqual(error?.event === 'error' ? {
    code: error.error.code,
    category: error.error.category,
    message: error.error.message,
    retryable: error.error.retryable,
    recoverable: error.error.recoverable,
  } : null, {
    code: 'resource-missing',
    category: 'source',
    message: 'Missing Plex rating key',
    retryable: false,
    recoverable: false,
  });
});
