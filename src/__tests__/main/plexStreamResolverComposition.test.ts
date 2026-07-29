import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PlaybackSelectedConnectionPort,
  PlaybackActiveCredentialPort,
  createLivePlexStreamResolverComposition,
} from '../../main/plex/streamResolverComposition.js';
import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import type { DesktopStreamCapabilityProfile } from '../../main/player/streamPolicy/types.js';

test('PlaybackSelectedConnectionPort returns connection from runtime', async () => {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackSelectedConnectionPort(mockRuntime);
  const result = await port.getSelectedConnection();
  assert.deepEqual(result, connection);
});

test('PlaybackSelectedConnectionPort returns null if no connection', async () => {
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return null;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackSelectedConnectionPort(mockRuntime);
  const result = await port.getSelectedConnection();
  assert.equal(result, null);
});

test('PlaybackActiveCredentialPort returns credentials from runtime', async () => {
  const mockRuntime = {
    async withActivePlexToken(
      _operation: 'getMetadata',
      run: (token: string) => Promise<unknown>,
    ) {
      return run('secret-token');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackActiveCredentialPort(mockRuntime);
  const result = await port.getActiveAuthHeader();
  assert.deepEqual(result, {
    name: 'X-Plex-Token',
    value: 'secret-token',
  });
});

test('PlaybackActiveCredentialPort returns null if no token', async () => {
  const mockRuntime = {
    async withActivePlexToken() {
      throw new Error('missing token');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackActiveCredentialPort(mockRuntime);
  const result = await port.getActiveAuthHeader();
  assert.equal(result, null);
});

test('createLivePlexStreamResolverComposition instantiates resolver and pms session port', () => {
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return null;
    },
    async withActivePlexToken() {
      throw new Error('missing token');
    },
    async withActiveLibraryContext() {
      throw new Error('missing context');
    },
    getLibraryTransport() {
      return {};
    },
  } as unknown as DesktopPlexRuntime;

  const composition = createLivePlexStreamResolverComposition(mockRuntime);
  assert.ok(composition.resolver);
  assert.ok(composition.pmsSessionPort);
});

test('createLivePlexStreamResolverComposition injects the existing diagnostic store into the resolver', async () => {
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
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
    async withActivePlexToken(
      _operation: 'getMetadata' | 'listLibraryItems' | 'startPlayback',
      run: (token: string) => Promise<unknown>,
    ) {
      return run('private-token');
    },
    async withActiveLibraryContext(
      _operation: 'getMetadata',
      run: (context: {
        connection: typeof connection;
        token: string;
        transport: typeof transport;
      }) => Promise<unknown>,
    ) {
      return run({ connection, token: 'private-token', transport });
    },
    getLibraryTransport() {
      return transport;
    },
  } as unknown as DesktopPlexRuntime;
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
    mediaId: 'plex-media-123',
    capabilityProfile: directPlayProfile,
  });

  assert.equal(result.ok, true);
  assert.equal(
    diagnostics.getRecords().some((record) => (
      record.operation === 'settings.subtitle-policy'
    )),
    true,
  );
});

const directPlayProfile: DesktopStreamCapabilityProfile = {
  id: 'composition-profile',
  directPlayContainers: ['mkv'],
  directPlayVideoCodecs: ['h264'],
  directPlayAudioCodecs: ['aac'],
  subtitleDeliveryModes: ['embedded'],
  headerAuthSetup: 'supported',
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
