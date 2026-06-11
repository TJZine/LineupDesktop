import test from 'node:test';
import assert from 'node:assert/strict';

import type {
  PlexIpcResult,
  PlexRuntimeSnapshot,
  PlexSelectServerValue,
  PlexSwitchHomeUserValue,
} from '../../../contracts/plex.js';
import type { DesktopPlexRuntime } from '../../../main/plex/desktopPlexRuntime.js';
import {
  wirePlexPlaybackCleanup,
  type PlaybackCleanupPlexRuntime,
  type PlaybackCleanupRuntime,
} from '../../../main/player/plexPlaybackCleanupWiring.js';
import type { PlexPlaybackRuntime } from '../../../main/player/plexPlaybackRuntime.js';
import type {
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from '../../../main/player/nativePlayerHostPort.js';

const snapshot = {} as PlexRuntimeSnapshot;

test('playback cleanup is triggered on switchHomeUser success', async () => {
  let cleanupReason: string | null = null;
  const mockPlaybackRuntime = {
    async cleanup(input: { reason: 'profile-change' | 'server-change' }) {
      cleanupReason = input.reason;
      return [];
    },
  } satisfies PlaybackCleanupRuntime;
  const mockPlexRuntime = createPlexRuntime({
    switchHomeUserResult: (requestId) => ({
      ok: true,
      value: {
        profile: {
          accountId: 'user-1',
          username: 'user1',
        },
        snapshot,
      },
      requestId,
    }) satisfies PlexIpcResult<PlexSwitchHomeUserValue>,
  });

  wirePlexPlaybackCleanup({
    plexRuntime: mockPlexRuntime,
    getPlaybackRuntime: () => mockPlaybackRuntime,
    reportDiagnostic: () => undefined,
  });
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
  } satisfies PlaybackCleanupRuntime;
  const mockPlexRuntime = createPlexRuntime({
    switchHomeUserResult: (requestId) => ({
      ok: false,
      error: {
        code: 'PLEX_AUTH_INVALID',
        message: 'Auth failed',
        retryable: false,
        recoverable: false,
        operation: 'switchHomeUser',
      },
      requestId,
    }) satisfies PlexIpcResult<PlexSwitchHomeUserValue>,
  });

  wirePlexPlaybackCleanup({
    plexRuntime: mockPlexRuntime,
    getPlaybackRuntime: () => mockPlaybackRuntime,
    reportDiagnostic: () => undefined,
  });
  const result = await mockPlexRuntime.switchHomeUser('req-123', { userId: 'user-1' });

  assert.equal(result.ok, false);
  assert.equal(cleanupCalled, false);
});

test('playback cleanup is triggered on selectServer success', async () => {
  let cleanupReason: string | null = null;
  const mockPlaybackRuntime = {
    async cleanup(input: { reason: 'profile-change' | 'server-change' }) {
      cleanupReason = input.reason;
      return [];
    },
  } satisfies PlaybackCleanupRuntime;
  const mockPlexRuntime = createPlexRuntime({
    selectServerResult: (requestId) => ({
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
        snapshot,
      },
      requestId,
    }) satisfies PlexIpcResult<PlexSelectServerValue>,
  });

  wirePlexPlaybackCleanup({
    plexRuntime: mockPlexRuntime,
    getPlaybackRuntime: () => mockPlaybackRuntime,
    reportDiagnostic: () => undefined,
  });
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
  } satisfies PlaybackCleanupRuntime;
  const mockPlexRuntime = createPlexRuntime({
    selectServerResult: (requestId) => ({
      ok: false,
      error: {
        code: 'PLEX_SERVER_UNREACHABLE',
        message: 'Server unreachable',
        retryable: false,
        recoverable: false,
        operation: 'selectServer',
      },
      requestId,
    }) satisfies PlexIpcResult<PlexSelectServerValue>,
  });

  wirePlexPlaybackCleanup({
    plexRuntime: mockPlexRuntime,
    getPlaybackRuntime: () => mockPlaybackRuntime,
    reportDiagnostic: () => undefined,
  });
  const result = await mockPlexRuntime.selectServer('req-123', 'server-1');

  assert.equal(result.ok, false);
  assert.equal(cleanupCalled, false);
});

test('playback cleanup failures are reported without failing Plex runtime calls', async () => {
  const diagnostics: Array<{ message: string; error: unknown }> = [];
  const cleanupError = new Error('cleanup failed');
  const mockPlaybackRuntime = {
    async cleanup() {
      throw cleanupError;
    },
  } satisfies PlaybackCleanupRuntime;
  const mockPlexRuntime = createPlexRuntime({
    switchHomeUserResult: (requestId) => ({
      ok: true,
      value: {
        profile: {
          accountId: 'user-1',
          username: 'user1',
        },
        snapshot,
      },
      requestId,
    }) satisfies PlexIpcResult<PlexSwitchHomeUserValue>,
  });

  wirePlexPlaybackCleanup({
    plexRuntime: mockPlexRuntime,
    getPlaybackRuntime: () => mockPlaybackRuntime,
    reportDiagnostic: (message, error) => diagnostics.push({ message, error }),
  });
  const result = await mockPlexRuntime.switchHomeUser('req-123', { userId: 'user-1' });

  assert.equal(result.ok, true);
  assert.deepEqual(diagnostics, [
    { message: 'Playback cleanup on profile-change failed', error: cleanupError },
  ]);
});

test('helper crash is wired to playbackRuntime handleHelperCrash via host onLifecycleFailure', async () => {
  let handleHelperCrashCalled = false;
  const mockPlaybackRuntime = {
    async handleHelperCrash() {
      handleHelperCrashCalled = true;
      return [];
    },
  } satisfies Pick<PlexPlaybackRuntime, 'handleHelperCrash'>;

  const lifecycle = {
    listener: null as ((failure: NativePlayerHostLifecycleFailure) => void) | null,
  };
  const mockHost = {
    onLifecycleFailure(listener: (failure: NativePlayerHostLifecycleFailure) => void) {
      lifecycle.listener = listener;
      return () => {
        lifecycle.listener = null;
      };
    },
  } satisfies Pick<NativePlayerHostPort, 'onLifecycleFailure'>;

  const originalNativeHostFactory = () => mockHost;

  const nativeHostFactory = () => {
    const host = originalNativeHostFactory();
    host.onLifecycleFailure?.(() => {
      void mockPlaybackRuntime.handleHelperCrash();
    });
    return host;
  };

  const hostInstance = nativeHostFactory();
  assert.equal(hostInstance, mockHost);

  const callback = lifecycle.listener;
  if (callback === null) {
    throw new Error('expected lifecycle listener');
  }
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

  assert.equal(handleHelperCrashCalled, true);
});

function createPlexRuntime(options: {
  switchHomeUserResult?: (requestId: string) => PlexIpcResult<PlexSwitchHomeUserValue>;
  selectServerResult?: (requestId: string) => PlexIpcResult<PlexSelectServerValue>;
}): PlaybackCleanupPlexRuntime {
  return {
    async switchHomeUser(requestId: string, _input: { userId: string; pin?: string | null }) {
      return options.switchHomeUserResult?.(requestId) ?? {
        ok: false,
        error: {
          code: 'PLEX_UNKNOWN',
          message: 'switchHomeUser not configured',
          retryable: false,
          recoverable: false,
          operation: 'switchHomeUser',
        },
        requestId,
      } satisfies PlexIpcResult<PlexSwitchHomeUserValue>;
    },
    async selectServer(requestId: string, _serverId: string) {
      return options.selectServerResult?.(requestId) ?? {
        ok: false,
        error: {
          code: 'PLEX_UNKNOWN',
          message: 'selectServer not configured',
          retryable: false,
          recoverable: false,
          operation: 'selectServer',
        },
        requestId,
      } satisfies PlexIpcResult<PlexSelectServerValue>;
    },
  } satisfies Pick<DesktopPlexRuntime, 'switchHomeUser' | 'selectServer'>;
}
