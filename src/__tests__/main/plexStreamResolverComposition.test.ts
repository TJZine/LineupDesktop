import test from 'node:test';
import assert from 'node:assert/strict';
import { createLivePlexStreamResolverComposition } from '../../main/plex/streamResolverComposition.js';
import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import { LivePlexTransportError } from '../../main/plex/livePlexTransportError.js';
import type { DesktopStreamCapabilityProfile } from '../../main/player/streamPolicy/types.js';

test('createLivePlexStreamResolverComposition injects the existing diagnostic store into the resolver', async () => {
  const mockRuntime = createPlayableRuntime();
  const diagnostics = new DiagnosticEventStore();
  diagnostics.setSettingsAdmission({
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: true,
  });

  const composition = createLivePlexStreamResolverComposition(mockRuntime, {
    diagnosticEventStore: diagnostics,
  });
  const result = await composition.resolver.resolve({
    requestId: 'composition-diagnostic',
    mediaId: 'playback-media-composition',
    ratingKey: '123',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, true);
  assert.equal(result.ok ? result.load.seekSupport : null, 'supported');
  assert.equal(result.ok ? Object.hasOwn(result.load, 'capabilityProfile') : true, false);
  assert.deepEqual(result.ok ? result.privatePlayback.credentialHeader : null, {
    name: 'X-Plex-Token',
    value: 'private-token',
  });
  assert.equal(
    diagnostics.getRecords().some((record) => (
      record.operation === 'settings.subtitle-policy'
    )),
    true,
  );
});

test('createLivePlexStreamResolverComposition preserves unsupported seek without exposing the profile', async () => {
  const mockRuntime = createPlayableRuntime();
  const result = await createLivePlexStreamResolverComposition(mockRuntime).resolver.resolve({
    requestId: 'composition-no-seek',
    mediaId: 'playback-media-composition',
    ratingKey: '123',
    capabilityProfile: { ...directPlayProfile, id: 'composition-no-seek', seek: 'unsupported' },
  });

  assert.equal(result.ok, true);
  assert.equal(result.ok ? result.load.seekSupport : null, 'unsupported');
  assert.equal(result.ok ? Object.hasOwn(result.load, 'capabilityProfile') : true, false);
});

test('createLivePlexStreamResolverComposition normalizes missing credentials through the resolver', async () => {
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return {
        uri: 'https://plex.local',
        protocol: 'https',
        address: 'plex.local',
        port: 32400,
        local: true,
        relay: false,
        latencyMs: null,
      };
    },
    async withActivePlexToken() {
      throw new LivePlexTransportError(
        'auth-required',
        'getMetadata requires Plex authentication',
      );
    },
  } as unknown as DesktopPlexRuntime;

  const result = await createLivePlexStreamResolverComposition(mockRuntime).resolver.resolve({
    requestId: 'composition-missing-credential',
    mediaId: 'playback-media-composition',
    ratingKey: '123',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.ok ? '' : result.error.code, 'PLEX_STREAM_CREDENTIAL_UNAVAILABLE');
  assert.equal(
    result.diagnostics.some((diagnostic) => diagnostic.operation === 'active-credential.read'),
    false,
  );
});

test('createLivePlexStreamResolverComposition preserves unexpected credential failure diagnostics', async () => {
  const unexpectedFailure = new Error('unexpected private credential failure');
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return {
        uri: 'https://plex.local',
        protocol: 'https',
        address: 'plex.local',
        port: 32400,
        local: true,
        relay: false,
        latencyMs: null,
      };
    },
    async withActivePlexToken() {
      throw unexpectedFailure;
    },
  } as unknown as DesktopPlexRuntime;

  const result = await createLivePlexStreamResolverComposition(mockRuntime).resolver.resolve({
    requestId: 'composition-unexpected-credential-failure',
    mediaId: 'playback-media-composition',
    ratingKey: '123',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, false);
  assert.equal(result.ok ? '' : result.error.code, 'PLEX_STREAM_CREDENTIAL_UNAVAILABLE');
  assert.equal(
    result.diagnostics.some((diagnostic) => (
      diagnostic.operation === 'active-credential.read' &&
      diagnostic.status === 'failed'
    )),
    true,
  );
  assert.equal(JSON.stringify(result).includes(unexpectedFailure.message), false);
});

const directPlayProfile: DesktopStreamCapabilityProfile = {
  id: 'composition-profile',
  directPlayContainers: ['mkv'],
  directPlayVideoCodecs: ['h264'],
  directPlayAudioCodecs: ['aac'],
  subtitleDeliveryModes: ['embedded'],
  headerAuthSetup: 'supported',
  seek: 'supported',
  audioTrackSwitching: 'supported',
  subtitleTrackSwitching: 'supported',
  hdr: 'supported',
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

function createPlayableRuntime(): DesktopPlexRuntime {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };
  const transport = {
    async getMetadata() {
      return {
        kind: 'json' as const,
        data: {
          MediaContainer: {
            Metadata: [{
              ratingKey: '123',
              key: '/library/metadata/123',
              type: 'episode',
              title: 'Composition Episode',
              duration: 1_800_000,
              Media: [{
                id: 'media-1',
                duration: 1_800_000,
                videoCodec: 'h264',
                audioCodec: 'aac',
                container: 'mkv',
                Part: [{
                  id: 'part-1',
                  key: '/library/parts/123',
                  duration: 1_800_000,
                  container: 'mkv',
                  Stream: [
                    { id: 'video-1', streamType: 1, codec: 'h264', dynamicRange: 'sdr' },
                    { id: 'audio-1', streamType: 2, codec: 'aac', default: true },
                    { id: 'subtitle-1', streamType: 3, codec: 'srt', default: true },
                  ],
                }],
              }],
            }],
          },
        },
      };
    },
    async stopTranscodeSession() {},
  };
  return {
    getSelectedConnectionForMain: () => connection,
    withActivePlexToken: async (
      _operation: 'getMetadata' | 'listLibraryItems' | 'startPlayback',
      run: (token: string) => Promise<unknown>,
    ) => run('private-token'),
    withActiveLibraryContext: async (
      _operation: 'getMetadata',
      run: (context: {
        connection: typeof connection;
        token: string;
        transport: typeof transport;
      }) => Promise<unknown>,
    ) => run({
      connection,
      token: 'private-token',
      transport,
    }),
    getLibraryTransport: () => transport,
  } as unknown as DesktopPlexRuntime;
}
