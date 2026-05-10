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
  type PlayerEvent,
} from '../contracts/player.js';
import { registerPlayerIpcHandlers } from '../main/player/playerIpc.js';

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

test('player IPC registers closed handlers and tears them down', () => {
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

  teardown();

  assert.deepEqual([...ipcMain.handlers.keys()], []);
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
  registerPlayerIpcHandlers({
    shellMode: 'production',
    isAuthorizedEvent,
    sendPlayerEvent: (event) => events.push(event),
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
