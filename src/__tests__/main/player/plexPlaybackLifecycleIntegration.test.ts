import test from 'node:test';
import assert from 'node:assert/strict';
import type { DesktopPlexRuntime } from '../../../main/plex/desktopPlexRuntime.js';
import type { PlexPlaybackRuntime } from '../../../main/player/plexPlaybackRuntime.js';
import type { NativePlayerHostPort, NativePlayerHostLifecycleFailure } from '../../../main/player/nativePlayerHostPort.js';
import type { PlexIpcResult, PlexSwitchHomeUserValue, PlexSelectServerValue, PlexRuntimeSnapshot } from '../../../contracts/plex.js';

test('playback cleanup is triggered on switchHomeUser success', async () => {
  let cleanupReason: string | null = null;
  const mockPlaybackRuntime = {
    async cleanup(input: { reason: string }) {
      cleanupReason = input.reason;
      return [];
    },
  } as unknown as PlexPlaybackRuntime;

  const mockPlexRuntime = {
    async switchHomeUser(requestId: string, _input: { userId: string; pin?: string | null }) {
      return {
        ok: true,
        value: {
          profile: {
            accountId: 'user-1',
            username: 'user1',
          },
          snapshot: {} as unknown as PlexRuntimeSnapshot,
        },
        requestId,
      } satisfies PlexIpcResult<PlexSwitchHomeUserValue>;
    },
  } as unknown as DesktopPlexRuntime;

  // Simulate the wrapping behavior from index.ts
  const originalSwitchHomeUser = mockPlexRuntime.switchHomeUser.bind(mockPlexRuntime);
  mockPlexRuntime.switchHomeUser = async (requestId, input) => {
    const result = await originalSwitchHomeUser(requestId, input);
    if (result.ok) {
      if (mockPlaybackRuntime) {
        await mockPlaybackRuntime.cleanup({ reason: 'profile-change' });
      }
    }
    return result;
  };

  const result = await mockPlexRuntime.switchHomeUser('req-123', { userId: 'user-1' });

  assert.equal(result.ok, true);
  assert.equal(cleanupReason, 'profile-change');
});

test('playback cleanup is NOT triggered on switchHomeUser failure', async () => {
  let cleanupCalled = false;
  const mockPlaybackRuntime = {
    async cleanup() {
      cleanupCalled = true;
      return [];
    },
  } as unknown as PlexPlaybackRuntime;

  const mockPlexRuntime = {
    async switchHomeUser(requestId: string, _input: { userId: string; pin?: string | null }) {
      return {
        ok: false,
        error: {
          code: 'AUTH_FAILED',
          message: 'Auth failed',
          retryable: false,
          recoverable: false,
          operation: 'switchHomeUser',
        },
        requestId,
      } as unknown as PlexIpcResult<PlexSwitchHomeUserValue>;
    },
  } as unknown as DesktopPlexRuntime;

  // Simulate the wrapping behavior from index.ts
  const originalSwitchHomeUser = mockPlexRuntime.switchHomeUser.bind(mockPlexRuntime);
  mockPlexRuntime.switchHomeUser = async (requestId, input) => {
    const result = await originalSwitchHomeUser(requestId, input);
    if (result.ok) {
      if (mockPlaybackRuntime) {
        await mockPlaybackRuntime.cleanup({ reason: 'profile-change' });
      }
    }
    return result;
  };

  const result = await mockPlexRuntime.switchHomeUser('req-123', { userId: 'user-1' });

  assert.equal(result.ok, false);
  assert.equal(cleanupCalled, false);
});

test('playback cleanup is triggered on selectServer success', async () => {
  let cleanupReason: string | null = null;
  const mockPlaybackRuntime = {
    async cleanup(input: { reason: string }) {
      cleanupReason = input.reason;
      return [];
    },
  } as unknown as PlexPlaybackRuntime;

  const mockPlexRuntime = {
    async selectServer(requestId: string, _serverId: string) {
      return {
        ok: true,
        value: {
          selection: {
            kind: 'selected',
            server: {
              serverId: 'server-1',
              name: 'server1',
              owned: true,
              connectionCount: 1,
              hasLocalConnection: true,
              hasRemoteConnection: false,
              hasRelayConnection: false,
              selected: true,
            },
            persisted: true,
          },
          snapshot: {} as unknown as PlexRuntimeSnapshot,
        },
        requestId,
      } satisfies PlexIpcResult<PlexSelectServerValue>;
    },
  } as unknown as DesktopPlexRuntime;

  // Simulate the wrapping behavior from index.ts
  const originalSelectServer = mockPlexRuntime.selectServer.bind(mockPlexRuntime);
  mockPlexRuntime.selectServer = async (requestId, serverId) => {
    const result = await originalSelectServer(requestId, serverId);
    if (result.ok) {
      if (mockPlaybackRuntime) {
        await mockPlaybackRuntime.cleanup({ reason: 'server-change' });
      }
    }
    return result;
  };

  const result = await mockPlexRuntime.selectServer('req-123', 'server-1');

  assert.equal(result.ok, true);
  assert.equal(cleanupReason, 'server-change');
});

test('playback cleanup is NOT triggered on selectServer failure', async () => {
  let cleanupCalled = false;
  const mockPlaybackRuntime = {
    async cleanup() {
      cleanupCalled = true;
      return [];
    },
  } as unknown as PlexPlaybackRuntime;

  const mockPlexRuntime = {
    async selectServer(requestId: string, _serverId: string) {
      return {
        ok: false,
        error: {
          code: 'SERVER_UNREACHABLE',
          message: 'Server unreachable',
          retryable: false,
          recoverable: false,
          operation: 'selectServer',
        },
        requestId,
      } as unknown as PlexIpcResult<PlexSelectServerValue>;
    },
  } as unknown as DesktopPlexRuntime;

  // Simulate the wrapping behavior from index.ts
  const originalSelectServer = mockPlexRuntime.selectServer.bind(mockPlexRuntime);
  mockPlexRuntime.selectServer = async (requestId, serverId) => {
    const result = await originalSelectServer(requestId, serverId);
    if (result.ok) {
      if (mockPlaybackRuntime) {
        await mockPlaybackRuntime.cleanup({ reason: 'server-change' });
      }
    }
    return result;
  };

  const result = await mockPlexRuntime.selectServer('req-123', 'server-1');

  assert.equal(result.ok, false);
  assert.equal(cleanupCalled, false);
});

test('helper crash is wired to playbackRuntime handleHelperCrash via host onLifecycleFailure', async () => {
  let handleHelperCrashCalled = false;
  const mockPlaybackRuntime = {
    async handleHelperCrash() {
      handleHelperCrashCalled = true;
      return [];
    },
  } as unknown as PlexPlaybackRuntime;

  let lifecycleListener: ((failure: NativePlayerHostLifecycleFailure) => void) | null = null;
  const mockHost = {
    onLifecycleFailure(listener: (failure: NativePlayerHostLifecycleFailure) => void) {
      lifecycleListener = listener;
      return () => {
        lifecycleListener = null;
      };
    },
  } as unknown as NativePlayerHostPort;

  const originalNativeHostFactory = () => mockHost;

  // Simulate the wrapping behavior from index.ts
  const nativeHostFactory = () => {
    const host = originalNativeHostFactory();
    host.onLifecycleFailure?.(() => {
      if (mockPlaybackRuntime) {
        void mockPlaybackRuntime.handleHelperCrash();
      }
    });
    return host;
  };

  const hostInstance = nativeHostFactory();
  assert.equal(hostInstance, mockHost);

  const callback = lifecycleListener as unknown as ((failure: NativePlayerHostLifecycleFailure) => void) | null;
  if (callback) {
    callback({
      requestId: 'req-1',
      error: {
        code: 'PLAYER_HELPER_CRASHED',
        message: 'Helper crashed',
        category: 'helper-failure',
        recoverable: false,
        retryable: false,
      },
    });
  }

  assert.equal(handleHelperCrashCalled, true);
});
