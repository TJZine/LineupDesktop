import test from 'node:test';
import assert from 'node:assert/strict';
import type { IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
} from '../contracts/ipc.js';
import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerEvent,
} from '../contracts/player.js';
import { registerPlayerIpcHandlers } from '../main/player/playerIpc.js';
import { redactMainProcessError } from '../main/redactedDiagnostics.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostFailure,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from '../main/player/nativePlayerHostPort.js';

type Handler = (event: IpcMainInvokeEvent, payload?: unknown) => unknown;

class FakeIpcMain {
  readonly handlers = new Map<string, Handler>();

  handle(channel: string, handler: Handler): void {
    this.handlers.set(channel, handler);
  }

  removeHandler(channel: string): void {
    this.handlers.delete(channel);
  }

  async invoke(channel: string, event: unknown, payload?: unknown): Promise<unknown> {
    const handler = this.handlers.get(channel);
    assert.ok(handler, `missing handler for ${channel}`);
    return handler(event as IpcMainInvokeEvent, payload);
  }
}

class ConfigurableNativeHost implements NativePlayerHostPort {
  readonly commands: PlayerCommand[] = [];
  executeResult: NativePlayerHostCommandResult = { ok: true };
  cleanupError: Error | null = null;

  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    this.commands.push(command);
    return this.executeResult;
  }

  async cleanup(): Promise<void> {
    if (this.cleanupError !== null) {
      throw this.cleanupError;
    }
    return undefined;
  }
}

class LifecycleNativeHost extends ConfigurableNativeHost {
  private readonly listeners = new Set<(failure: NativePlayerHostLifecycleFailure) => void>();

  onLifecycleFailure(listener: (failure: NativePlayerHostLifecycleFailure) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  emitLifecycleFailure(failure: NativePlayerHostLifecycleFailure): void {
    for (const listener of [...this.listeners]) {
      listener(failure);
    }
  }
}

function authorizedEvent(): unknown {
  return { authorized: true };
}

function unauthorizedEvent(): unknown {
  return { authorized: false };
}

function isAuthorizedEvent(event: unknown): boolean {
  return (
    typeof event === 'object' &&
    event !== null &&
    'authorized' in event &&
    event.authorized === true
  );
}

function createRequestId(prefix: string): string {
  return `${prefix}-generated`;
}

function loadEnvelope(requestId = 'player-load-1'): unknown {
  return {
    intent: 'player.load',
    requestId,
    payload: {
      media: {
        id: 'media-1',
        title: 'Episode 1',
        durationMs: 1_000,
        container: 'mkv',
      },
      policy: {
        autoplay: true,
        startPositionMs: 0,
        preferredAudioTrackId: null,
        preferredSubtitleTrackId: null,
      },
      capabilityProfileId: 'desktop-ipc-test',
    },
  };
}

function helperFailure(): NativePlayerHostFailure {
  return {
    code: 'PLAYER_HELPER_EXITED',
    category: 'helper-failure',
    message: 'raw process exit 123',
    recoverable: true,
    retryable: true,
  };
}

function assertNoForbiddenKeys(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) {
      assertNoForbiddenKeys(item);
    }
    return;
  }

  if (value === null || typeof value !== 'object') {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    assert.equal(
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ),
      false,
      `renderer-facing player IPC value contains forbidden key ${key}`,
    );
    assertNoForbiddenKeys(child);
  }
}

test('player IPC registers closed handlers and tears them down', async () => {
  const ipcMain = new FakeIpcMain();
  const teardown = registerPlayerIpcHandlers({
    shellMode: 'smoke',
    isAuthorizedEvent,
    sendPlayerEvent: () => undefined,
    createRequestId,
    ipcMain,
  });

  assert.deepEqual([...ipcMain.handlers.keys()].sort(), [
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    LINEUP_PLAYER_COMMAND_CHANNEL,
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  ]);

  await teardown();

  assert.deepEqual([...ipcMain.handlers.keys()], []);
});

test('player IPC reports cleanup failures and still removes handlers', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new ConfigurableNativeHost();
  const diagnostics: Array<{ message: string; error: unknown }> = [];
  host.cleanupError = new Error('nativeHandle=secret');
  const teardown = registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendPlayerEvent: () => undefined,
    createRequestId,
    nativeHostFactory: () => host,
    reportDiagnostic: (message, error) => diagnostics.push({ message, error }),
    ipcMain,
  });

  assert.deepEqual([...ipcMain.handlers.keys()].sort(), [
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    LINEUP_PLAYER_COMMAND_CHANNEL,
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  ]);

  await teardown();

  assert.deepEqual([...ipcMain.handlers.keys()], []);
  assert.equal(diagnostics.length, 1);
  assert.equal(diagnostics[0]?.message, 'Player IPC cleanup failed');
  assert.equal((diagnostics[0]?.error as { category?: string }).category, 'cleanup-failure');
  assert.equal(JSON.stringify(diagnostics[0]?.error).includes('nativeHandle'), false);
});

test('main process diagnostics redact privileged key-value pairs and URLs', () => {
  const plexTokenHeader = ['X-Plex', 'Token'].join('-');
  const authorizationHeader = ['Authorization'].join('');
  const bearerScheme = ['Bearer'].join('');
  const message = redactMainProcessError(
    new Error(
      [
        'nativeHandle=secret',
        'tokenizedUrl=http://secret.example/media',
        '"authHeaders":"json-secret"',
        'rawPlexPayload: bare-secret',
        'token=raw-token',
        'authToken: raw-auth-token',
        'authenticationToken=raw-authentication-token',
        'accountToken=raw-account-token',
        'activeToken=raw-active-token',
        'plexToken=raw-plex-token',
        'clientSecret=raw-client-secret',
        'pin=raw-pin',
        'header=raw-header',
        'headers=raw-headers',
        `${authorizationHeader}=raw-authorization`,
        'secret=raw-secret',
        'credential=raw-credential',
        'password=raw-password',
        `${plexTokenHeader}=raw-plex-header-token`,
        `${authorizationHeader}: ${bearerScheme} rawbearertoken12345`,
        `https://server.example/video?${plexTokenHeader}=raw-query-token&other=1`,
        '\\"authToken\\":\\"raw-escaped-auth-token\\"',
        'standalone nativeHandle rawMediaUrl rawPlexPayload',
      ].join(' '),
    ),
  );

  assert.equal(message.includes('nativeHandle'), false);
  assert.equal(message.includes('tokenizedUrl'), false);
  assert.equal(message.includes('authHeaders'), false);
  assert.equal(message.includes('rawPlexPayload'), false);
  assert.equal(message.includes('secret'), false);
  assert.equal(message.includes('json-secret'), false);
  assert.equal(message.includes('bare-secret'), false);
  assert.equal(message.includes('secret.example'), false);
  assert.equal(message.includes('raw-token'), false);
  assert.equal(message.includes('raw-auth-token'), false);
  assert.equal(message.includes('raw-authentication-token'), false);
  assert.equal(message.includes('raw-account-token'), false);
  assert.equal(message.includes('raw-active-token'), false);
  assert.equal(message.includes('raw-plex-token'), false);
  assert.equal(message.includes('raw-client-secret'), false);
  assert.equal(message.includes('raw-pin'), false);
  assert.equal(message.includes('raw-header'), false);
  assert.equal(message.includes('raw-headers'), false);
  assert.equal(message.includes('raw-authorization'), false);
  assert.equal(message.includes('raw-credential'), false);
  assert.equal(message.includes('raw-password'), false);
  assert.equal(message.includes('raw-plex-header-token'), false);
  assert.equal(message.includes('raw-query-token'), false);
  assert.equal(message.includes('raw-escaped-auth-token'), false);
  assert.equal(message.includes('rawbearertoken12345'), false);
});

test('development and smoke player IPC dispatches through fake host and emits safe events', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    ipcMain,
  });

  const result = await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-load-1'),
  );
  const snapshot = await ipcMain.invoke(
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
    authorizedEvent(),
    { requestId: 'snapshot-wrapper-1' },
  );

  assert.deepEqual(result, {
    ok: true,
    requestId: 'player-load-1',
    value: {
      accepted: true,
      events: (result as { value: { events: unknown } }).value.events,
      snapshot: (result as { value: { snapshot: unknown } }).value.snapshot,
    },
  });
  assert.equal((result as { value: { snapshot: { status: string } } }).value.snapshot.status, 'playing');
  assert.equal(Object.hasOwn((result as { value: object }).value, 'command'), false);
  assert.equal((snapshot as { ok: boolean }).ok, true);
  assert.equal((snapshot as { value: { media: { id: string } | null } }).value.media?.id, 'media-1');
  assert.equal(events.some((event) => event.event === 'state.changed'), true);
  assert.equal(events.some((event) => event.event === 'command.settled'), true);
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(snapshot);
  assertNoForbiddenKeys(events);
});

test('player IPC emits renderer-safe error when helper lifecycle fails asynchronously', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new LifecycleNativeHost();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    nativeHostFactory: () => host,
    ipcMain,
  });

  await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-load-lifecycle'),
  );

  host.emitLifecycleFailure({
    requestId: null,
    error: helperFailure(),
  });

  const snapshot = await ipcMain.invoke(
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
    authorizedEvent(),
    { requestId: 'snapshot-after-lifecycle' },
  );
  const errorEvent = [...events].reverse().find((event) => event.event === 'error');

  assert.ok(errorEvent);
  assert.equal(errorEvent.error.category, 'helper-failure');
  assert.equal(errorEvent.error.message, 'The player helper stopped unexpectedly.');
  assert.equal((snapshot as { value: { status: string } }).value.status, 'error');
  assert.equal(
    (snapshot as { value: { lastError: { category: string } | null } }).value.lastError?.category,
    'helper-failure',
  );
  assertNoForbiddenKeys(events);
  assertNoForbiddenKeys(snapshot);
});

test('player IPC keeps helper lifecycle reporting after cleanup and later reuse', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new LifecycleNativeHost();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    nativeHostFactory: () => host,
    ipcMain,
  });

  await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-load-before-cleanup'),
  );
  await ipcMain.invoke(
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    authorizedEvent(),
    { requestId: 'cleanup-before-reuse' },
  );
  await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-load-after-cleanup'),
  );

  host.emitLifecycleFailure({
    requestId: null,
    error: helperFailure(),
  });

  const snapshot = await ipcMain.invoke(
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
    authorizedEvent(),
    { requestId: 'snapshot-after-cleanup-lifecycle' },
  );
  const errorEvent = [...events].reverse().find((event) => event.event === 'error');

  assert.ok(errorEvent);
  assert.equal(errorEvent.error.category, 'helper-failure');
  assert.equal((snapshot as { value: { status: string } }).value.status, 'error');
  assertNoForbiddenKeys(events);
  assertNoForbiddenKeys(snapshot);
});

test('player IPC rejects invalid renderer payloads as failures without host success', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'smoke',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    ipcMain,
  });

  const result = await ipcMain.invoke(LINEUP_PLAYER_COMMAND_CHANNEL, authorizedEvent(), {
    intent: 'player.load',
    requestId: 'player-invalid-1',
    payload: {
      media: { id: 'media-1', title: 'Episode 1', rawMediaUrl: 'redacted' },
      policy: { autoplay: true },
    },
  });

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal((result as { requestId: string }).requestId, 'player-invalid-1');
  assert.equal(
    (result as { error: { category: string; code: string } }).error.category,
    'validation-failure',
  );
  assert.equal(events.some((event) => event.event === 'error'), true);
  assert.equal(JSON.stringify(result).includes('rawMediaUrl'), false);
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(events);
});

test('player IPC enforces main authorization before adapter access', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'smoke',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    ipcMain,
  });

  const result = await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    unauthorizedEvent(),
    loadEnvelope('player-unauthorized-1'),
  );

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal((result as { requestId: string }).requestId, 'player-unauthorized-1');
  assert.equal((result as { error: { category: string } }).error.category, 'authorization');
  assert.deepEqual(events, []);
  assertNoForbiddenKeys(result);
});

test('production player IPC returns unsupported failures and does not activate fake playback', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  let nativeHostCreated = false;
  registerPlayerIpcHandlers({
    shellMode: 'production',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    nativeHostFactory: () => {
      nativeHostCreated = true;
      return new ConfigurableNativeHost();
    },
    ipcMain,
  });

  const commandResult = await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-prod-1'),
  );
  const snapshotResult = await ipcMain.invoke(
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
    authorizedEvent(),
    { requestId: 'snapshot-prod-1' },
  );
  const cleanupResult = await ipcMain.invoke(
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    authorizedEvent(),
    { requestId: 'cleanup-prod-1' },
  );

  assert.equal((commandResult as { ok: boolean }).ok, false);
  assert.equal(nativeHostCreated, false);
  assert.equal(
    (commandResult as { error: { category: string; code: string } }).error.category,
    'unsupported-capability',
  );
  assert.equal(
    (commandResult as { error: { category: string; code: string } }).error.code,
    'PLAYER_UNSUPPORTED_CAPABILITY',
  );
  assert.equal((snapshotResult as { value: { status: string; media: unknown } }).value.status, 'idle');
  assert.equal((snapshotResult as { value: { status: string; media: unknown } }).value.media, null);
  assert.equal((cleanupResult as { value: { status: string } }).value.status, 'idle');
  assert.equal(events.length, 1);
  assert.equal(events[0]?.event, 'error');
  assertNoForbiddenKeys(commandResult);
  assertNoForbiddenKeys(snapshotResult);
  assertNoForbiddenKeys(cleanupResult);
  assertNoForbiddenKeys(events);
});

test('player IPC cleanup returns a safe failure envelope when host cleanup fails', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new ConfigurableNativeHost();
  const events: PlayerEvent[] = [];
  host.cleanupError = new Error('nativeHandle=cleanup-secret');
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
    createRequestId,
    nativeHostFactory: () => host,
    ipcMain,
  });

  await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-cleanup-load-1'),
  );
  const result = await ipcMain.invoke(
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    authorizedEvent(),
    { requestId: 'player-cleanup-fails-1' },
  );

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal((result as { requestId: string }).requestId, 'player-cleanup-fails-1');
  assert.equal((result as { error: { category: string } }).error.category, 'cleanup-failure');
  assert.equal(events.some((event) => event.event === 'error'), true);
  assert.equal(JSON.stringify(result).includes('cleanup-secret'), false);
  assertNoForbiddenKeys(result);
  assertNoForbiddenKeys(events);
});

test('player IPC can use an explicit development host factory without changing production policy', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new ConfigurableNativeHost();
  host.executeResult = {
    ok: false,
    error: {
      code: 'PLAYER_HELPER_TIMEOUT',
      category: 'timeout',
      message: 'The player helper did not respond in time.',
      recoverable: true,
      retryable: true,
    },
  };

  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendPlayerEvent: () => undefined,
    createRequestId,
    nativeHostFactory: () => host,
    ipcMain,
  });

  const result = await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-dev-process-1'),
  );

  assert.equal(host.commands.length, 1);
  assert.equal(host.commands[0]?.requestId, 'player-dev-process-1');
  assert.equal((result as { ok: boolean }).ok, true);
  assert.equal(
    (result as { value: { events: PlayerEvent[] } }).value.events.some(
      (event) => event.event === 'command.settled' && !event.ok,
    ),
    true,
  );
  assertNoForbiddenKeys(result);
});
