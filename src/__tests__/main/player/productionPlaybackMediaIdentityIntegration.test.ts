import test from 'node:test';
import assert from 'node:assert/strict';

import type { IChannelScheduler, ScheduledProgram, SchedulerState } from '../../../domain/scheduler/index.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import { PlaybackMediaDetailPort } from '../../../main/plex/playbackMediaDetailPort.js';
import type { DesktopPlexRuntime } from '../../../main/plex/desktopPlexRuntime.js';
import { PlexStreamResolver } from '../../../main/plex/streamResolver.js';
import { PlexPlaybackBridge } from '../../../main/player/plexPlaybackBridge.js';
import type { DesktopStreamCapabilityProfile } from '../../../main/player/streamPolicy/types.js';

const ratingKey = 'opaque-scheduled-key-77';
const connection = {
  uri: 'https://media-source.invalid',
  protocol: 'https' as const,
  address: 'media-source.invalid',
  port: 32400,
  local: true,
  relay: false,
  latencyMs: null,
};

const capabilityProfile: DesktopStreamCapabilityProfile = {
  id: 'production-identity-integration',
  directPlayContainers: ['mp4'],
  directPlayVideoCodecs: ['h264'],
  directPlayAudioCodecs: ['aac'],
  subtitleDeliveryModes: ['none'],
  headerAuthSetup: 'supported',
  seek: 'supported',
  audioTrackSwitching: 'unsupported',
  subtitleTrackSwitching: 'unsupported',
  hdr: 'unsupported',
  dolbyVision: 'unsupported',
  directStream: {
    containerRemux: 'unsupported',
    audioTranscode: 'unsupported',
    subtitleConversion: 'unsupported',
  },
  transcode: {
    video: 'unsupported',
    audio: 'unsupported',
    subtitles: 'unsupported',
    hdr: 'unsupported',
  },
};

function createScheduler(): Pick<IChannelScheduler, 'getCurrentProgram' | 'getState'> {
  const program: ScheduledProgram = {
    item: {
      ratingKey,
      type: 'episode',
      title: 'Identity Episode',
      fullTitle: 'Identity Episode',
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
      channelId: 'identity-channel',
      currentProgram: program,
      nextProgram: null,
      schedulePosition: { loopNumber: 0, itemIndex: 0, offsetMs: 5_000 },
      lastSyncTime: 1_000,
    }),
  };
}

function createMetadataPayload() {
  return {
    kind: 'json' as const,
    data: {
      MediaContainer: {
        Metadata: [{
          ratingKey,
          key: `/library/metadata/${ratingKey}`,
          type: 'episode',
          title: 'Identity Episode',
          duration: 120_000,
          Media: [{
            id: 'private-media-variant',
            duration: 120_000,
            videoCodec: 'h264',
            audioCodec: 'aac',
            container: 'mp4',
            Part: [{
              id: 'private-media-part',
              key: '/library/parts/private-file.mp4',
              duration: 120_000,
              container: 'mp4',
              Stream: [
                { id: 'private-video-stream', streamType: 1, codec: 'h264', dynamicRange: 'sdr' },
                { id: 'private-audio-stream', streamType: 2, codec: 'aac', default: true },
              ],
            }],
          }],
        }],
      },
    },
  };
}

test('raw scheduled rating key flows through the real bridge, resolver, and media-detail port', async () => {
  const metadataInputs: Array<{ ratingKey: string }> = [];
  const transport = {
    async getMetadata(input: { ratingKey: string }) {
      metadataInputs.push({ ratingKey: input.ratingKey });
      return createMetadataPayload();
    },
  };
  const runtime = {
    async withActiveLibraryContext(
      _operation: 'getMetadata',
      run: (context: { connection: typeof connection; token: string; transport: typeof transport }) => Promise<unknown>,
    ) {
      return run({ connection, token: 'dummy-private-credential', transport });
    },
  } as unknown as DesktopPlexRuntime;
  const resolver = new PlexStreamResolver({
    selectedConnection: { getSelectedConnection: async () => connection },
    activeCredential: {
      getActiveAuthHeader: async () => ({ name: 'X-Dummy-Credential', value: 'dummy-private-credential' }),
    },
    mediaDetail: new PlaybackMediaDetailPort(runtime),
  });
  const bridge = new PlexPlaybackBridge({
    scheduler: createScheduler(),
    resolver,
    capabilityProfile,
    createRequestId: () => 'identity-request',
  });
  const selection = await bridge.getCurrentPlayback({ nowMs: 6_000, reason: 'startup' });
  assert.ok(selection);

  const candidate = await bridge.resolvePlaybackCandidate(selection);
  const repeatedCandidate = await bridge.resolvePlaybackCandidate(selection);
  const rendererMediaId = candidate.load.media.id;

  assert.deepEqual(metadataInputs, [{ ratingKey }, { ratingKey }]);
  assert.equal(repeatedCandidate.load.media.id, rendererMediaId);
  assert.match(rendererMediaId, /^playback-media-[0-9a-f-]{36}$/u);
  assert.equal(candidate.load.media.id, rendererMediaId);
  assert.equal(candidate.privatePlayback?.media.id, rendererMediaId);
  assert.equal(rendererMediaId.includes(ratingKey), false);
  assert.equal(Object.hasOwn(candidate.load, 'ratingKey'), false);
  assert.equal(Object.hasOwn(candidate.load, 'privatePlayback'), false);
  assert.equal(JSON.stringify(candidate.load).includes('dummy-private-credential'), false);
  assert.equal(JSON.stringify(candidate.load).includes(connection.uri), false);
  assert.equal(JSON.stringify(candidate.load).includes(ratingKey), false);
  assert.ok(candidate.privatePlayback);
  assert.equal(candidate.privatePlayback.playbackUrl, `${connection.uri}/library/parts/private-file.mp4`);
  assert.deepEqual(candidate.privatePlayback.credentialHeader, {
    name: 'X-Dummy-Credential',
    value: 'dummy-private-credential',
  });
});

test('media-detail diagnostics retain only fixed categorical failure context', async () => {
  const diagnostics = new DiagnosticEventStore({
    clock: () => 1_000,
    idGenerator: () => 'media-detail-failure',
  });
  const exceptionName = 'OpaqueMetadataTransportFailure';
  const exceptionMessage = 'opaque dynamic transport detail';
  const runtime = {
    async withActiveLibraryContext(
      _operation: 'getMetadata',
      run: (context: { connection: typeof connection; token: string; transport: { getMetadata(): Promise<never> } }) => Promise<unknown>,
    ) {
      const transport = {
        async getMetadata(): Promise<never> {
          const error = new Error(exceptionMessage);
          error.name = exceptionName;
          throw error;
        },
      };
      return run({ connection, token: 'dummy-private-credential', transport });
    },
  } as unknown as DesktopPlexRuntime;
  const port = new PlaybackMediaDetailPort(runtime, { diagnosticEventStore: diagnostics });

  const result = await port.getMediaDetail({ ratingKey });
  const records = diagnostics.getRecords();
  const serialized = JSON.stringify(records);

  assert.equal(result, null);
  assert.equal(records.length, 1);
  assert.equal(records[0]?.operation, 'playbackMediaDetailPort.getMetadata');
  assert.equal(records[0]?.status, 'failed');
  assert.equal(serialized.includes(ratingKey), false);
  assert.equal(serialized.includes('dummy-private-credential'), false);
  assert.equal(serialized.includes(connection.uri), false);
  assert.equal(serialized.includes(exceptionName), false);
  assert.equal(serialized.includes(exceptionMessage), false);
  assert.equal(serialized.includes('metadata lookup failed'), true);
});
