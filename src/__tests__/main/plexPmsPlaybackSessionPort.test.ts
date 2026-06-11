import test from 'node:test';
import assert from 'node:assert/strict';
import { PmsPlaybackSessionPort } from '../../main/plex/pmsPlaybackSessionPort.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';

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
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
    async withActivePlexToken(
      operation: string,
      run: (token: string) => Promise<unknown>,
    ) {
      operations.push(operation);
      return run('token');
    },
  } as unknown as DesktopPlexRuntime;

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

test('PmsPlaybackSessionPort startSession returns null if connection or token is missing', async () => {
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return null;
    },
    async withActivePlexToken() {
      throw new Error('missing token');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PmsPlaybackSessionPort(mockRuntime);
  const lease = await port.startSession({
    requestId: 'req-1',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection: {
      protocol: 'https',
      address: 'plex.local',
      port: 32400,
      local: true,
      relay: false,
    },
  });

  assert.equal(lease, null);
});

test('PmsPlaybackSessionPort releaseSession invokes stopTranscodeSession for transcode and direct-stream', async () => {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };

  let stopSessionId: string | null = null;
  let stopToken: string | null = null;
  const operations: string[] = [];
  const mockTransport = {
    async stopTranscodeSession(input: { sessionId: string; token: string }) {
      stopSessionId = input.sessionId;
      stopToken = input.token;
    },
  };

  const tokens = ['start-token-1', 'start-token-2'];
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
    async withActivePlexToken(
      operation: string,
      run: (token: string) => Promise<unknown>,
    ) {
      operations.push(operation);
      return run(tokens.shift() ?? 'unexpected-token');
    },
    getLibraryTransport() {
      return mockTransport;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PmsPlaybackSessionPort(mockRuntime);

  // Start transcode session
  await port.startSession({
    requestId: 'req-transcode',
    media: { id: 'media-1', title: 'Test' },
    decisionKind: 'transcode',
    connection,
  });

  // Release it
  await port.releaseSession(
    { id: 'req-transcode', requestId: 'req-transcode' },
    { reason: 'stop', requestId: 'req-transcode' },
  );

  assert.equal(stopSessionId, 'req-transcode');
  assert.equal(stopToken, 'start-token-1');
  assert.deepEqual(operations, ['startPlayback']);

  // Start direct-stream session
  await port.startSession({
    requestId: 'req-direct-stream',
    media: { id: 'media-2', title: 'Test 2' },
    decisionKind: 'direct-stream',
    connection,
  });

  // Release it
  await port.releaseSession(
    { id: 'req-direct-stream', requestId: 'req-direct-stream' },
    { reason: 'switch', requestId: 'req-direct-stream' },
  );

  assert.equal(stopSessionId, 'req-direct-stream');
  assert.equal(stopToken, 'start-token-2');
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

  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
    async withActivePlexToken(
      _operation: 'getMetadata',
      run: (token: string) => Promise<unknown>,
    ) {
      return run('token');
    },
    getLibraryTransport() {
      return mockTransport;
    },
  } as unknown as DesktopPlexRuntime;

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
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
    async withActivePlexToken(
      _operation: string,
      run: (token: string) => Promise<unknown>,
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
  } as unknown as DesktopPlexRuntime;

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
