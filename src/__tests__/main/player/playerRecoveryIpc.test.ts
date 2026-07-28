import test from 'node:test';
import assert from 'node:assert/strict';
import type { IpcMainInvokeEvent } from 'electron';

import { LINEUP_PLAYER_RECOVERY_CHANNEL } from '../../../contracts/ipc.js';
import type { PlayerSnapshot } from '../../../contracts/player.js';
import { registerPlayerRecoveryIpc } from '../../../main/player/playerRecoveryIpc.js';

type Handler = (
  event: IpcMainInvokeEvent,
  payload: unknown,
) => unknown;

class FakeIpcMain {
  readonly handlers = new Map<string, Handler>();
  handle(channel: string, handler: Handler): void {
    this.handlers.set(channel, handler);
  }
  removeHandler(channel: string): void {
    this.handlers.delete(channel);
  }
  invoke(event: unknown, payload: unknown): Promise<unknown> {
    const handler = this.handlers.get(LINEUP_PLAYER_RECOVERY_CHANNEL);
    assert.ok(handler);
    return Promise.resolve(handler(event as IpcMainInvokeEvent, payload));
  }
}

test('recovery IPC validates exact payload, authorization, and request echo', async () => {
  const ipcMain = new FakeIpcMain();
  let retryCalls = 0;
  let snapshotReads = 0;
  const teardown = registerPlayerRecoveryIpc({
    transitionOwner: {
      retryCurrent: async () => {
        retryCalls += 1;
        return { accepted: true };
      },
      skipNext: async () => ({ accepted: false, reason: 'unavailable' }),
    },
    getSnapshot: () => {
      snapshotReads += 1;
      return snapshot();
    },
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'generated',
    ipcMain,
  });

  const accepted = await ipcMain.invoke('authorized', {
    requestId: 'recovery-1',
    payload: { action: 'retry-current' },
  });
  assert.deepEqual(accepted, {
    ok: true,
    requestId: 'recovery-1',
    value: { status: 'accepted', snapshot: snapshot() },
  });
  assert.equal(retryCalls, 1);
  assert.equal(snapshotReads, 1);

  const unauthorized = await ipcMain.invoke('denied', {
    requestId: 'recovery-2',
    payload: { action: 'retry-current' },
  });
  assert.deepEqual(unauthorized, {
    ok: false,
    requestId: 'recovery-2',
    value: {
      status: 'failed',
      snapshot: {
        requestId: null,
        status: 'idle',
        media: null,
        capabilityProfileId: null,
        positionMs: 0,
        durationMs: null,
        bufferedRanges: [],
        playing: false,
        volume: 1,
        muted: false,
        playbackRate: 1,
        selectedAudioTrackId: null,
        selectedSubtitleTrackId: null,
        selectedVideoTrackId: null,
        tracks: [],
        quality: {
          mode: 'unknown',
          sourceDynamicRange: 'unknown',
          outputDynamicRangeStatus: 'unknown',
        },
        lastError: null,
      },
    },
    error: {
      code: 'PLAYER_RECOVERY_UNAUTHORIZED',
      category: 'authorization',
      message: 'Player recovery request was not authorized.',
      recoverable: false,
      retryable: false,
      requestId: 'recovery-2',
    },
  });
  assert.equal(retryCalls, 1);
  assert.equal(snapshotReads, 1);

  const invalid = await ipcMain.invoke('authorized', {
    requestId: 'recovery-3',
    payload: { action: 'skip-next', channelId: 'private-choice' },
  });
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal(snapshotReads, 2);
  teardown();
  assert.equal(ipcMain.handlers.size, 0);
});

test('accepted recovery result cannot precede transition event publication', async () => {
  const ipcMain = new FakeIpcMain();
  const trace: string[] = [];
  registerPlayerRecoveryIpc({
    transitionOwner: {
      retryCurrent: async () => {
        await Promise.resolve();
        trace.push('runtime-event');
        return { accepted: true };
      },
      skipNext: async () => ({ accepted: false, reason: 'unavailable' }),
    },
    getSnapshot: snapshot,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'generated',
    ipcMain,
  });

  await ipcMain.invoke('authorized', {
    requestId: 'recovery-order',
    payload: { action: 'retry-current' },
  });
  trace.push('ipc-result');

  assert.deepEqual(trace, ['runtime-event', 'ipc-result']);
});

function snapshot(): PlayerSnapshot {
  return {
    requestId: 'playback-1',
    status: 'error',
    media: { id: 'media-1', title: 'Media' },
    capabilityProfileId: 'desktop',
    positionMs: 0,
    durationMs: 10_000,
    bufferedRanges: [],
    playing: false,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    quality: {
      mode: 'unknown',
      sourceDynamicRange: 'unknown',
      outputDynamicRangeStatus: 'unknown',
    },
    lastError: {
      code: 'PLAYER_HOST_ENGINE_FAILURE',
      category: 'engine-failure',
      message: 'Playback failed.',
      recoverable: true,
      retryable: true,
      requestId: 'playback-1',
    },
  };
}
