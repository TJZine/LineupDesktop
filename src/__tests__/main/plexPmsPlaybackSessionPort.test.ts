import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PmsPlaybackSessionPort,
  type PmsPlaybackSessionRuntimePort,
} from '../../main/plex/pmsPlaybackSessionPort.js';
import { LivePlexTransportError } from '../../main/plex/livePlexTransportError.js';

test('PmsPlaybackSessionPort startSession returns lease and stores details', async () => {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };
  const operations: string[] = [];
  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>(
      operation: Parameters<PmsPlaybackSessionRuntimePort['withActivePlexToken']>[0],
      run: (token: string) => Promise<T>,
    ) {
      operations.push(operation);
      return run('token');
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);
  const lease = await port.startSession({
    requestId: 'req-1',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection,
  });

  assert.ok(lease);
  assert.equal(lease.id, 'req-1');
  assert.equal(lease.requestId, 'req-1');
  assert.deepEqual(operations, ['startPlayback']);
});

test('PmsPlaybackSessionPort startSession returns null if token is missing', async () => {
  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>(
      _operation: Parameters<PmsPlaybackSessionRuntimePort['withActivePlexToken']>[0],
      _run: (token: string) => Promise<T>,
    ): Promise<T> {
      throw new LivePlexTransportError(
        'auth-required',
        'startPlayback requires Plex authentication',
      );
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);
  const lease = await port.startSession({
    requestId: 'req-1',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection: {
      uri: 'https://plex.local',
      protocol: 'https',
      address: 'plex.local',
      port: 32400,
      local: true,
      relay: false,
      latencyMs: null,
    },
  });

  assert.equal(lease, null);
});

test('PmsPlaybackSessionPort startSession rethrows unexpected credential failures', async () => {
  const unexpectedFailure = new Error('unexpected credential runtime failure');
  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>(): Promise<T> {
      throw unexpectedFailure;
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);

  await assert.rejects(
    () => port.startSession({
      requestId: 'req-unexpected-credential-failure',
      media: { id: 'media-1', title: 'Test' },
      decisionKind: 'transcode',
      connection: {
        uri: 'https://plex.local',
        protocol: 'https',
        address: 'plex.local',
        port: 32400,
        local: true,
        relay: false,
        latencyMs: null,
      },
    }),
    (error: unknown) => error === unexpectedFailure,
  );
});

test('PmsPlaybackSessionPort startSession returns null for invalid input connection', async () => {
  let tokenRead = false;
  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>() {
      tokenRead = true;
      return 'unexpected-token' as T;
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);
  const lease = await port.startSession({
    requestId: 'req-invalid-connection',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection: {
      uri: '',
      protocol: 'https',
      address: '',
      port: 0,
      local: true,
      relay: false,
      latencyMs: null,
    },
  });

  assert.equal(lease, null);
  assert.equal(tokenRead, false);
});

test('PmsPlaybackSessionPort releaseSession invokes stopTranscodeSession for transcode and direct-stream', async () => {
  const playbackConnection = {
    uri: 'http://playback-connection.example:32400',
    protocol: 'http' as const,
    address: 'playback-connection.example',
    port: 32400,
    local: false,
    relay: true,
    latencyMs: 25,
  };

  let stopSessionId: string | null = null;
  let stopToken: string | null = null;
  let stopConnection: unknown = null;
  const operations: string[] = [];
  const mockTransport = {
    async stopTranscodeSession(input: { connection: unknown; sessionId: string; token: string }) {
      stopSessionId = input.sessionId;
      stopToken = input.token;
      stopConnection = input.connection;
    },
  };

  const tokens = ['start-token-1', 'start-token-2'];
  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>(
      operation: Parameters<PmsPlaybackSessionRuntimePort['withActivePlexToken']>[0],
      run: (token: string) => Promise<T>,
    ) {
      operations.push(operation);
      return run(tokens.shift() ?? 'unexpected-token');
    },
    getLibraryTransport() {
      return mockTransport;
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);

  // Start transcode session
  await port.startSession({
    requestId: 'req-transcode',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection: playbackConnection,
  });

  // Release it
  await port.releaseSession(
    { id: 'req-transcode', requestId: 'req-transcode' },
    { reason: 'stop', requestId: 'req-transcode' },
  );

  assert.equal(stopSessionId, 'req-transcode');
  assert.equal(stopToken, 'start-token-1');
  assert.deepEqual(stopConnection, playbackConnection);
  assert.deepEqual(operations, ['startPlayback']);

  // Start direct-stream session
  await port.startSession({
    requestId: 'req-direct-stream',
    media: { id: 'media-2', title: 'Test 2' },
    decisionKind: 'direct-stream',
    connection: playbackConnection,
  });

  // Release it
  await port.releaseSession(
    { id: 'req-direct-stream', requestId: 'req-direct-stream' },
    { reason: 'switch', requestId: 'req-direct-stream' },
  );

  assert.equal(stopSessionId, 'req-direct-stream');
  assert.equal(stopToken, 'start-token-2');
  assert.deepEqual(stopConnection, playbackConnection);
  assert.deepEqual(operations, ['startPlayback', 'startPlayback']);
});

test('PmsPlaybackSessionPort releaseSession does NOT invoke stopTranscodeSession for direct-play', async () => {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };

  let stopCalled = false;
  const mockTransport = {
    async stopTranscodeSession() {
      stopCalled = true;
    },
  };

  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>(
      _operation: Parameters<PmsPlaybackSessionRuntimePort['withActivePlexToken']>[0],
      run: (token: string) => Promise<T>,
    ) {
      return run('token');
    },
    getLibraryTransport() {
      return mockTransport;
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);

  await port.startSession({
    requestId: 'req-direct-play',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'direct-play',
    connection,
  });

  await port.releaseSession(
    { id: 'req-direct-play', requestId: 'req-direct-play' },
    { reason: 'stop', requestId: 'req-direct-play' },
  );

  assert.equal(stopCalled, false);
});

test('PmsPlaybackSessionPort rejects duplicate request IDs before replacing active session state', async () => {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };

  let stopCalled = false;
  const mockRuntime = createRuntimePort({
    async withActivePlexToken<T>(
      _operation: Parameters<PmsPlaybackSessionRuntimePort['withActivePlexToken']>[0],
      run: (token: string) => Promise<T>,
    ) {
      return run('token');
    },
    getLibraryTransport() {
      return {
        async stopTranscodeSession() {
          stopCalled = true;
        },
      };
    },
  });

  const port = new PmsPlaybackSessionPort(mockRuntime);
  await port.startSession({
    requestId: 'req-duplicate',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection,
  });

  await assert.rejects(
    () => port.startSession({
      requestId: 'req-duplicate',
      media: { id: 'media-2', title: 'Replacement' },
      decisionKind: 'direct-play',
      connection,
    }),
    /already active/u,
  );

  await port.releaseSession(
    { id: 'req-duplicate', requestId: 'req-duplicate' },
    { reason: 'stop', requestId: 'req-duplicate' },
  );
  assert.equal(stopCalled, true);
});

function createRuntimePort(
  overrides: Partial<PmsPlaybackSessionRuntimePort> = {},
): PmsPlaybackSessionRuntimePort {
  return {
    async withActivePlexToken(_operation, run) {
      return run('token');
    },
    getLibraryTransport() {
      return {
        async stopTranscodeSession() {
          return undefined;
        },
      };
    },
    ...overrides,
  } satisfies PmsPlaybackSessionRuntimePort;
}
