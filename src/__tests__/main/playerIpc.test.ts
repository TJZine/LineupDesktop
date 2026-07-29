import test from 'node:test';
import assert from 'node:assert/strict';
import type { IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
} from '../../contracts/ipc.js';
import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
} from '../../contracts/player.js';
import { registerPlayerIpcHandlers } from '../../main/player/playerIpc.js';
import type { PrivilegedPlaybackDispatchContext } from '../../main/player/privilegedPlaybackDispatchContext.js';
import { redactMainProcessError } from '../../main/redactedDiagnostics.js';
import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostFailure,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from '../../main/player/nativePlayerHostPort.js';

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

  async queryAudioOutputs() {
    return { ok: true as const, outputs: [] };
  }
}

class EventNativeHost extends ConfigurableNativeHost {
  private readonly listeners = new Set<(event: unknown) => void>();

  onEvent(listener: (event: unknown) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  emitEvent(event: unknown): void {
    for (const listener of [...this.listeners]) {
      listener(event);
    }
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

class OrderedLifecycleNativeHost extends ConfigurableNativeHost {
  readonly trace: string[] = [];
  mainListener: ((failure: NativePlayerHostLifecycleFailure) => void) | null = null;
  private adapterListener: ((failure: NativePlayerHostLifecycleFailure) => void) | null = null;
  private readonly listeners = new Map<
    (failure: NativePlayerHostLifecycleFailure) => void,
    string
  >();

  onLifecycleFailure(listener: (failure: NativePlayerHostLifecycleFailure) => void): () => void {
    const label = listener === this.mainListener ? 'main' : 'adapter';
    if (label === 'adapter') {
      assert.equal(this.adapterListener, null, 'expected exactly one adapter lifecycle listener');
      this.adapterListener = listener;
    }
    this.listeners.set(listener, label);
    return () => {
      if (this.listeners.delete(listener)) {
        this.trace.push(`unsubscribe:${label}`);
      }
      if (listener === this.adapterListener) {
        this.adapterListener = null;
      }
    };
  }

  emitLifecycleFailure(failure: NativePlayerHostLifecycleFailure): void {
    for (const [listener, label] of [...this.listeners]) {
      this.trace.push(label);
      listener(failure);
    }
  }

  override async cleanup(): Promise<void> {
    this.trace.push('cleanup');
    await super.cleanup();
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

function playerEventSinks(events?: PlayerEvent[]) {
  return {
    sendSynchronousPlayerEvent(event: PlayerEvent): void {
      events?.push(event);
    },
    onAsynchronousAdapterEvents(batch: readonly PlayerEvent[]): void {
      events?.push(...batch);
    },
  };
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

function runtimeLoadCommand(requestId: string): PlayerCommand {
  const envelope = loadEnvelope(requestId) as { payload: PlayerLoadCommandPayload };
  return {
    command: 'load',
    requestId,
    payload: envelope.payload,
  };
}

function privilegedPlaybackContext(requestId: string): PrivilegedPlaybackDispatchContext {
  return {
    privatePlayback: {
      requestId,
      decisionKind: 'direct-play',
      playbackUrl: 'https://plex.example.invalid/library/parts/1/file.mp4',
      credentialHeader: { name: 'X-Plex-Token', value: 'private-token' },
      selectedConnection: {
        protocol: 'https',
        address: 'plex.example.invalid',
        port: 443,
        local: true,
        relay: false,
      },
      media: {
        id: 'media-1',
        title: 'Episode 1',
      },
      setup: {
        playbackMode: 'direct-play',
        mediaPath: '/library/metadata/1',
        variantId: 'variant-1',
        partPath: '/library/parts/1/file.mp4',
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: { video: [], audio: [], subtitle: [] },
        audioOutputNativeKey: null,
        dtsPassthroughEnabled: false,
      },
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
    ...playerEventSinks(),
    createRequestId,
    ipcMain,
  });

  assert.deepEqual([...ipcMain.handlers.keys()].sort(), [
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    LINEUP_PLAYER_COMMAND_CHANNEL,
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  ]);

  await teardown.teardown();

  assert.deepEqual([...ipcMain.handlers.keys()], []);
});

test('player IPC keeps synchronous command results separate from asynchronous adapter batches', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new EventNativeHost();
  host.executeResult = {
    ok: true,
    events: [
      {
        type: 'playback.state',
        requestId: 'request-split-sinks',
        status: 'playing',
        playing: true,
      },
    ],
  };
  const synchronousEvents: PlayerEvent[] = [];
  const asynchronousBatches: PlayerEvent[][] = [];
  const registration = registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    sendSynchronousPlayerEvent: (event) => synchronousEvents.push(event),
    onAsynchronousAdapterEvents: (events) => asynchronousBatches.push([...events]),
    createRequestId,
    nativeHostFactory: () => host,
    ipcMain,
  });

  await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('request-split-sinks'),
  );
  assert.equal(synchronousEvents.length > 0, true);
  assert.deepEqual(asynchronousBatches, []);

  host.emitEvent({
    type: 'time.updated',
    requestId: 'request-split-sinks',
    positionMs: 500,
    durationMs: 1_000,
  });

  assert.equal(
    synchronousEvents.some((event) => event.event === 'time.updated'),
    false,
  );
  assert.equal(asynchronousBatches.length, 1);
  assert.deepEqual(asynchronousBatches[0], [
    {
      event: 'time.updated',
      requestId: 'request-split-sinks',
      positionMs: 500,
      durationMs: 1_000,
    },
  ]);

  await registration.teardown();
});

test('player IPC reports cleanup failures and still removes handlers', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new ConfigurableNativeHost();
  const diagnosticEventStore = new DiagnosticEventStore({
    clock: () => 1_000,
    idGenerator: () => 'ipc-cleanup',
  });
  const diagnostics: Array<{ message: string; error: unknown }> = [];
  host.cleanupError = new Error('nativeHandle=secret');
  const teardown = registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    ...playerEventSinks(),
    createRequestId,
    nativeHostFactory: () => host,
    reportDiagnostic: (message, error) => diagnostics.push({ message, error }),
    diagnosticEventStore,
    ipcMain,
  });

  assert.deepEqual([...ipcMain.handlers.keys()].sort(), [
    LINEUP_PLAYER_CLEANUP_CHANNEL,
    LINEUP_PLAYER_COMMAND_CHANNEL,
    LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  ]);

  await teardown.teardown();

  assert.deepEqual([...ipcMain.handlers.keys()], []);
  assert.equal(diagnostics.length, 1);
  assert.equal(diagnostics[0]?.message, 'Player IPC cleanup failed');
  assert.equal((diagnostics[0]?.error as { category?: string }).category, 'cleanup-failure');
  assert.equal(JSON.stringify(diagnostics[0]?.error).includes('nativeHandle'), false);
  assert.equal(diagnosticEventStore.getCrashRecoverySummary().cleanupFailureCount, 1);
  assert.equal(JSON.stringify(diagnosticEventStore.getRecords()).includes('nativeHandle'), false);
});

test('main process diagnostics redact privileged key-value pairs and URLs', () => {
  const plexTokenHeader = ['X-Plex', 'Token'].join('-');
  const authorizationHeader = ['Authorization'].join('');
  const bearerScheme = ['Bearer'].join('');
  const placeholderSecret = ['raw', 'secret'].join('-');
  const authTokenKey = ['auth', 'Token'].join('');
  const authenticationTokenKey = ['authentication', 'Token'].join('');
  const accountTokenKey = ['account', 'Token'].join('');
  const activeTokenKey = ['active', 'Token'].join('');
  const plexTokenKey = ['plex', 'Token'].join('');
  const clientSecretKey = ['client', 'Secret'].join('');
  const message = redactMainProcessError(
    new Error(
      [
        `nativeHandle=${placeholderSecret}`,
        'tokenizedUrl=http://secret.example/media',
        '"authHeaders":"json-secret"',
        'rawPlexPayload: bare-secret',
        'token=raw-token',
        `${authTokenKey}: raw-auth-token`,
        `${authenticationTokenKey}=raw-authentication-token`,
        `${accountTokenKey}=raw-account-token`,
        `${activeTokenKey}=raw-active-token`,
        `${plexTokenKey}=raw-plex-token`,
        `${clientSecretKey}=raw-client-secret`,
        'pin=raw-pin',
        'header=raw-header',
        'headers=raw-headers',
        `${authorizationHeader}=raw-authorization`,
        'secret=raw-secret',
        `${['credential'].join('')}=raw-credential`,
        `${['password'].join('')}=raw-password`,
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

test('main process diagnostics preserve safe token and bearer prefixes', () => {
  const plexTokenHeader = ['X-Plex', 'Token'].join('-');
  const bearerScheme = ['Bearer'].join('');
  assert.equal(
    redactMainProcessError(new Error(`?${plexTokenHeader}=raw-token&other=1`)),
    `?${plexTokenHeader}=[redacted]&other=1`,
  );
  assert.equal(
    redactMainProcessError(new Error(`${bearerScheme} rawbearertoken12345`)),
    `${bearerScheme} [redacted]`,
  );
});

test('main process diagnostics redact multipart auth and header values', () => {
  const authorizationHeader = ['Authorization'].join('');
  const plexTokenHeader = ['X-Plex', 'Token'].join('-');
  const bearerScheme = ['Bearer'].join('');
  const basicScheme = ['Basic'].join('');
  const tokenScheme = ['Token'].join('');
  const cases = [
    `${authorizationHeader}: ${tokenScheme} rawtoken12345`,
    `${authorizationHeader}: ${bearerScheme} rawbearer:user-secret`,
    `${authorizationHeader}: ${basicScheme} rawbasic:user-secret`,
    `${authorizationHeader}: ${tokenScheme} rawtoken:user-secret`,
    `headers: ${plexTokenHeader}: placeholder-secret`,
    `${plexTokenHeader}: ${tokenScheme} placeholder-secret`,
  ];

  for (const value of cases) {
    const message = redactMainProcessError(new Error(value));
    assert.equal(message.includes('rawtoken12345'), false);
    assert.equal(message.includes('rawbearer:user-secret'), false);
    assert.equal(message.includes('rawbasic:user-secret'), false);
    assert.equal(message.includes('rawtoken:user-secret'), false);
    assert.equal(message.includes('placeholder-secret'), false);
  }
});

test('main process diagnostics redact standalone colon-bearing credential schemes', () => {
  const cases = [
    `${['Bearer'].join('')} rawbearer:user-secret`,
    `${['Basic'].join('')} rawbasic:user-secret`,
    `${['Token'].join('')} rawtoken:user-secret`,
  ];

  for (const value of cases) {
    const message = redactMainProcessError(new Error(value));
    assert.equal(message.includes('rawbearer:user-secret'), false);
    assert.equal(message.includes('rawbasic:user-secret'), false);
    assert.equal(message.includes('rawtoken:user-secret'), false);
    assert.match(message, /\[redacted\]/u);
  }
});

test('main process diagnostics redact brace-delimited header maps', () => {
  const plexTokenHeader = ['X-Plex', 'Token'].join('-');
  for (const value of [
    `headers={${plexTokenHeader}: abc123}`,
    `headers: {${plexTokenHeader}: abc123}`,
    `headers={foo: bar, ${plexTokenHeader}: abc123}`,
  ]) {
    const message = redactMainProcessError(new Error(value));
    assert.equal(message.includes('abc123'), false);
    assert.equal(message.includes('bar'), false);
    assert.equal(message.includes(plexTokenHeader), false);
  }
  assert.equal(
    redactMainProcessError(new Error(`?${plexTokenHeader}=abc123&other=1 headers={foo: bar}`)),
    `?${plexTokenHeader}=[redacted]&other=1 [redacted]`,
  );
});

test('development and smoke player IPC dispatches through fake host and emits safe events', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    ...playerEventSinks(events),
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

test('development player host keeps playback events scoped to the active load request', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    ...playerEventSinks(events),
    createRequestId,
    ipcMain,
  });

  await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-active-load'),
  );
  const commands = [
    { intent: 'player.pause', requestId: 'player-pause', payload: {} },
    { intent: 'player.play', requestId: 'player-play', payload: {} },
    {
      intent: 'player.seekAbsolute',
      requestId: 'player-seek',
      payload: { positionMs: 500 },
    },
    {
      intent: 'player.setVolume',
      requestId: 'player-volume',
      payload: { volume: 0.4 },
    },
    {
      intent: 'player.setMute',
      requestId: 'player-mute',
      payload: { muted: true },
    },
    { intent: 'player.stop', requestId: 'player-stop', payload: {} },
  ];
  const results = [];
  for (const command of commands) {
    results.push(
      await ipcMain.invoke(LINEUP_PLAYER_COMMAND_CHANNEL, authorizedEvent(), command),
    );
  }

  assert.equal((results[0] as { value: { snapshot: { status: string } } }).value.snapshot.status, 'paused');
  assert.equal((results[1] as { value: { snapshot: { status: string } } }).value.snapshot.status, 'playing');
  assert.equal((results[2] as { value: { snapshot: { positionMs: number } } }).value.snapshot.positionMs, 500);
  assert.equal((results[3] as { value: { snapshot: { volume: number } } }).value.snapshot.volume, 0.4);
  assert.equal((results[4] as { value: { snapshot: { muted: boolean } } }).value.snapshot.muted, true);
  assert.equal((results[5] as { value: { snapshot: { status: string } } }).value.snapshot.status, 'ended');
  assert.equal(
    events.some((event) => event.event === 'warning' && event.warning.category === 'stale-request'),
    false,
  );
  assert.equal(
    events
      .filter((event) => event.event === 'state.changed')
      .every((event) => event.requestId === 'player-active-load'),
    true,
  );
  assertNoForbiddenKeys(results);
  assertNoForbiddenKeys(events);
});

test('player IPC emits renderer-safe error when helper lifecycle fails asynchronously', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new LifecycleNativeHost();
  const events: PlayerEvent[] = [];
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    ...playerEventSinks(events),
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
  assert.equal(
    (snapshot as { value: { lastError: { message: string } | null } }).value.lastError?.message,
    errorEvent.error.message,
  );
  assert.equal(
    (snapshot as { value: { lastError: { message: string } | null } }).value.lastError?.message.includes(
      'raw process exit 123',
    ),
    false,
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
    ...playerEventSinks(events),
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
    ...playerEventSinks(events),
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
    ...playerEventSinks(events),
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
  registerPlayerIpcHandlers({
    shellMode: 'production',
    isAuthorizedEvent,
    ...playerEventSinks(events),
    createRequestId,
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

test('production player IPC with an injected native host instantiates adapter but rejects renderer loads', async () => {
  const ipcMain = new FakeIpcMain();
  const events: PlayerEvent[] = [];
  const host = new ConfigurableNativeHost();
  const teardown = registerPlayerIpcHandlers({
    shellMode: 'production',
    isAuthorizedEvent,
    ...playerEventSinks(events),
    createRequestId,
    nativeHost: host,
    ipcMain,
  });

  const commandResult = await ipcMain.invoke(
    LINEUP_PLAYER_COMMAND_CHANNEL,
    authorizedEvent(),
    loadEnvelope('player-prod-2'),
  );

  assert.equal((commandResult as { ok: boolean }).ok, false);
  assert.equal(
    (commandResult as { error: { category: string; code: string } }).error.code,
    'PLAYER_UNSUPPORTED_CAPABILITY',
  );

  const loadCommand = runtimeLoadCommand('player-prod-runtime-2');
  const privilegedContext = privilegedPlaybackContext(loadCommand.requestId);
  const runtimeResult = await teardown.adapter?.dispatchRuntimeCommand(loadCommand, privilegedContext);
  assert.equal(runtimeResult?.accepted, true);

  const rendererResult = await teardown.adapter?.dispatchRendererIntent(loadEnvelope('player-prod-renderer-2'));
  assert.equal(rendererResult?.accepted, false);
  assert.equal(
    rendererResult?.events.find((event) => event.event === 'error')?.error.code,
    'PLAYER_UNSUPPORTED_CAPABILITY',
  );

  assertNoForbiddenKeys(commandResult);
  assertNoForbiddenKeys(runtimeResult);
  assertNoForbiddenKeys(rendererResult);
  await teardown.teardown();
});

test('player IPC registers adapter lifecycle handling before main and unsubscribes main before cleanup', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new OrderedLifecycleNativeHost();
  let mainLifecycleCalls = 0;
  const mainListener = () => {
    mainLifecycleCalls += 1;
  };
  host.mainListener = mainListener;
  const teardown = registerPlayerIpcHandlers({
    shellMode: 'production',
    isAuthorizedEvent,
    ...playerEventSinks(),
    createRequestId,
    nativeHost: host,
    onNativeHostLifecycleFailure: mainListener,
    ipcMain,
  });
  const failure = {
    requestId: null,
    error: helperFailure(),
  };
  const activeLoad = runtimeLoadCommand('player-active-lifecycle');
  const activeResult = await teardown.adapter?.dispatchRuntimeCommand(
    activeLoad,
    privilegedPlaybackContext(activeLoad.requestId),
  );
  assert.equal(activeResult?.accepted, true);

  host.emitLifecycleFailure(failure);

  assert.deepEqual(host.trace, ['adapter', 'main']);
  assert.equal(mainLifecycleCalls, 1);

  host.trace.length = 0;
  await teardown.teardown();
  assert.deepEqual(host.trace, ['unsubscribe:main', 'cleanup']);

  host.trace.length = 0;
  host.emitLifecycleFailure(failure);
  assert.deepEqual(host.trace, ['adapter']);
  assert.equal(mainLifecycleCalls, 1);
});

test('player IPC cleanup returns a safe failure envelope when host cleanup fails', async () => {
  const ipcMain = new FakeIpcMain();
  const host = new ConfigurableNativeHost();
  const events: PlayerEvent[] = [];
  host.cleanupError = new Error('nativeHandle=cleanup-secret');
  registerPlayerIpcHandlers({
    shellMode: 'development',
    isAuthorizedEvent,
    ...playerEventSinks(events),
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
    ...playerEventSinks(),
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
