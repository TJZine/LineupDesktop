import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  type RendererIntentEnvelope,
} from '../../contracts/ipc.js';
import type {
  PlayerCommand,
  PlayerDispatchResult,
  PlayerError,
  PlayerEvent,
  PlayerIpcResult,
  PlayerRequestId,
  PlayerSnapshot,
} from '../../contracts/player.js';
import type { ShellMode } from '../../contracts/shell.js';
import { DesktopPlayerAdapter } from './desktopPlayerAdapter.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostEvent,
  NativePlayerHostPort,
} from './nativePlayerHostPort.js';

type PlayerIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterPlayerIpcHandlersOptions {
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  sendPlayerEvent(event: PlayerEvent): void;
  createRequestId(prefix: string): string;
  ipcMain?: PlayerIpcMain;
}

export type PlayerIpcTeardown = () => void;

const PLAYER_IPC_CHANNELS = [
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLAYER_CLEANUP_CHANNEL,
] as const;

export function registerPlayerIpcHandlers(
  options: RegisterPlayerIpcHandlersOptions,
): PlayerIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();
  const runtime =
    options.shellMode === 'development' || options.shellMode === 'smoke'
      ? { adapter: new DesktopPlayerAdapter(new InertNativePlayerHost()) }
      : { adapter: null };

  ipcMain.handle(LINEUP_PLAYER_COMMAND_CHANNEL, async (event, payload: unknown) => {
    const requestId = getPayloadRequestId(payload) ?? options.createRequestId('player-command');
    if (!options.isAuthorizedEvent(event)) {
      return playerFailure(requestId, unauthorizedError(requestId));
    }
    if (runtime.adapter === null) {
      const error = unsupportedCapabilityError(requestId);
      emitEvents(options, [{ event: 'error', requestId, error }]);
      return playerFailure(requestId, error);
    }

    const result = await runtime.adapter.dispatchRendererIntent(
      payload as RendererIntentEnvelope<unknown>,
    );
    emitEvents(options, result.events);

    if (!result.accepted) {
      return playerFailure(
        requestId,
        findResultError(result.events) ?? validationError(requestId),
      );
    }

    return playerSuccess(requestId, toPlayerDispatchResult(result));
  });

  ipcMain.handle(LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL, (event, payload: unknown) => {
    const requestId = getPayloadRequestId(payload) ?? options.createRequestId('player-snapshot');
    if (!options.isAuthorizedEvent(event)) {
      return playerFailure(requestId, unauthorizedError(requestId));
    }
    return playerSuccess(requestId, runtime.adapter?.getSnapshot() ?? createInertSnapshot());
  });

  ipcMain.handle(LINEUP_PLAYER_CLEANUP_CHANNEL, async (event, payload: unknown) => {
    const requestId = getPayloadRequestId(payload) ?? options.createRequestId('player-cleanup');
    if (!options.isAuthorizedEvent(event)) {
      return playerFailure(requestId, unauthorizedError(requestId));
    }
    if (runtime.adapter === null) {
      return playerSuccess(requestId, createInertSnapshot());
    }

    const result = await runtime.adapter.cleanup();
    emitEvents(options, result.events);

    if (!result.accepted) {
      return playerFailure(
        requestId,
        findResultError(result.events) ?? cleanupError(requestId),
      );
    }

    return playerSuccess(requestId, result.snapshot);
  });

  return () => {
    runtime.adapter?.cleanup().catch(() => undefined);
    for (const channel of PLAYER_IPC_CHANNELS) {
      ipcMain.removeHandler(channel);
    }
  };
}

function emitEvents(
  options: Pick<RegisterPlayerIpcHandlersOptions, 'sendPlayerEvent'>,
  events: readonly PlayerEvent[],
): void {
  for (const event of events) {
    options.sendPlayerEvent(event);
  }
}

function toPlayerDispatchResult(result: PlayerDispatchResult): PlayerDispatchResult {
  return {
    accepted: result.accepted,
    events: result.events,
    snapshot: result.snapshot,
  };
}

function playerSuccess<T>(requestId: PlayerRequestId, value: T): PlayerIpcResult<T> {
  return { ok: true, value, requestId };
}

function playerFailure<T>(requestId: PlayerRequestId, error: PlayerError): PlayerIpcResult<T> {
  return { ok: false, error, requestId };
}

function findResultError(events: readonly PlayerEvent[]): PlayerError | null {
  for (const event of events) {
    if (event.event === 'error') {
      return event.error;
    }
    if (event.event === 'warning') {
      return event.warning;
    }
    if (event.event === 'command.settled' && !event.ok && event.error !== undefined) {
      return event.error;
    }
  }
  return null;
}

function unauthorizedError(requestId: PlayerRequestId): PlayerError {
  return {
    code: 'PLAYER_UNAUTHORIZED',
    category: 'authorization',
    message: 'Player request is not authorized.',
    recoverable: false,
    retryable: false,
    requestId,
    diagnostic: {
      component: 'player-ipc',
      operation: 'authorization',
      status: 'rejected',
      reason: 'unauthorized renderer request',
    },
  };
}

function unsupportedCapabilityError(requestId: PlayerRequestId): PlayerError {
  return {
    code: 'PLAYER_UNSUPPORTED_CAPABILITY',
    category: 'unsupported-capability',
    message: 'Desktop player playback is not available in this shell mode.',
    recoverable: false,
    retryable: false,
    requestId,
    diagnostic: {
      component: 'player-ipc',
      operation: 'dispatch',
      status: 'unsupported',
      reason: 'production native host is not registered',
    },
  };
}

function validationError(requestId: PlayerRequestId): PlayerError {
  return {
    code: 'PLAYER_VALIDATION_FAILED',
    category: 'validation-failure',
    message: 'The player request was rejected because it was not valid.',
    recoverable: false,
    retryable: false,
    requestId,
    diagnostic: {
      component: 'player-ipc',
      operation: 'dispatch',
      status: 'rejected',
      reason: 'invalid renderer request',
    },
  };
}

function cleanupError(requestId: PlayerRequestId): PlayerError {
  return {
    code: 'PLAYER_OPERATION_UNAVAILABLE',
    category: 'cleanup-failure',
    message: 'The player cleanup operation did not complete.',
    recoverable: true,
    retryable: true,
    requestId,
    diagnostic: {
      component: 'player-ipc',
      operation: 'cleanup',
      status: 'failed',
      reason: 'adapter cleanup failed',
    },
  };
}

function getPayloadRequestId(payload: unknown): PlayerRequestId | null {
  if (
    typeof payload === 'object' &&
    payload !== null &&
    'requestId' in payload &&
    typeof payload.requestId === 'string' &&
    payload.requestId.trim().length > 0
  ) {
    return payload.requestId;
  }
  return null;
}

function createInertSnapshot(): PlayerSnapshot {
  return {
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
    lastError: null,
  };
}

function getElectronIpcMain(): PlayerIpcMain {
  const require = createRequire(import.meta.url);
  const electron = require('electron') as { ipcMain?: PlayerIpcMain };
  if (electron.ipcMain === undefined) {
    throw new Error('Electron ipcMain is unavailable.');
  }
  return electron.ipcMain;
}

class InertNativePlayerHost implements NativePlayerHostPort {
  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    switch (command.command) {
      case 'load': {
        const events: NativePlayerHostEvent[] = [
          {
            type: 'media.loaded',
            requestId: command.requestId,
            media: command.payload.media,
            durationMs: command.payload.media.durationMs ?? null,
            tracks: [],
          },
          {
            type: 'playback.state',
            requestId: command.requestId,
            status: command.payload.policy.autoplay ? 'playing' : 'ready',
            playing: command.payload.policy.autoplay,
          },
        ];
        return { ok: true, events };
      }
      case 'play':
        return {
          ok: true,
          events: [
            {
              type: 'playback.state',
              requestId: command.requestId,
              status: 'playing',
              playing: true,
            },
          ],
        };
      case 'pause':
        return {
          ok: true,
          events: [
            {
              type: 'playback.state',
              requestId: command.requestId,
              status: 'paused',
              playing: false,
            },
          ],
        };
      case 'stop':
        return { ok: true, events: [{ type: 'ended', requestId: command.requestId }] };
      case 'seek.absolute':
        return {
          ok: true,
          events: [
            {
              type: 'time.updated',
              requestId: command.requestId,
              positionMs: command.payload.positionMs,
              durationMs: null,
            },
          ],
        };
      case 'seek.relative':
      case 'volume.set':
      case 'mute.set':
      case 'track.audio.select':
      case 'track.subtitle.select':
        return { ok: true };
    }
  }

  async cleanup(_requestId: PlayerRequestId | null): Promise<void> {
    return undefined;
  }
}
