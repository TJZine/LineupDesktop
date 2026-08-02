import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
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
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { DesktopPlayerAdapter } from './desktopPlayerAdapter.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostEvent,
  NativePlayerHostFactory,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from './nativePlayerHostPort.js';

type PlayerIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterPlayerIpcHandlersOptions {
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  sendSynchronousPlayerEvent(event: PlayerEvent): void;
  onAsynchronousAdapterEvents(events: readonly PlayerEvent[]): void;
  createRequestId(prefix: string): string;
  reportDiagnostic?(message: string, error: unknown): void;
  diagnosticEventStore?: DiagnosticEventStore;
  nativeHost?: NativePlayerHostPort | null;
  nativeHostFactory?: NativePlayerHostFactory;
  onNativeHostLifecycleFailure?(failure: NativePlayerHostLifecycleFailure): void;
  ipcMain?: PlayerIpcMain;
}

export interface PlayerIpcRegistration {
  adapter: DesktopPlayerAdapter | null;
  teardown: () => Promise<void>;
}

export type PlayerIpcTeardown = PlayerIpcRegistration;

const PLAYER_IPC_CHANNELS = [
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLAYER_CLEANUP_CHANNEL,
] as const;

export function registerPlayerIpcHandlers(
  options: RegisterPlayerIpcHandlersOptions,
): PlayerIpcRegistration {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();
  const host =
    options.shellMode === 'development' || options.shellMode === 'smoke'
      ? createDevelopmentHost(options)
      : options.nativeHost ?? null;
  const adapter =
    host === null
      ? null
      : new DesktopPlayerAdapter(host, {
          onEvents: options.onAsynchronousAdapterEvents,
          diagnosticEventStore: options.diagnosticEventStore,
          rejectRendererLoad: options.shellMode === 'production',
        });
  let unsubscribeMainLifecycle =
    host !== null && options.onNativeHostLifecycleFailure !== undefined
      ? host.onLifecycleFailure?.(options.onNativeHostLifecycleFailure) ?? null
      : null;
  const runtime = { adapter };

  ipcMain.handle(LINEUP_PLAYER_COMMAND_CHANNEL, async (event, payload: unknown) => {
    const requestId = getPayloadRequestId(payload) ?? options.createRequestId('player-command');
    if (!options.isAuthorizedEvent(event)) {
      return playerFailure(requestId, unauthorizedError(requestId));
    }
    if (runtime.adapter === null) {
      const error = unsupportedCapabilityError(requestId);
      recordPlayerIpcDiagnostic(options.diagnosticEventStore, requestId, 'dispatch', 'failed', error.code);
      emitEvents(options, [{ event: 'error', requestId, error }]);
      return playerFailure(requestId, error);
    }

    const result = await runtime.adapter.dispatchRendererIntent(payload);
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

    let result: Awaited<ReturnType<DesktopPlayerAdapter['cleanup']>>;
    try {
      result = await runtime.adapter.cleanup();
    } catch (error: unknown) {
      options.reportDiagnostic?.('Player IPC cleanup failed', error);
      recordPlayerIpcDiagnostic(
        options.diagnosticEventStore,
        requestId,
        'cleanup',
        'failed',
        'PLAYER_OPERATION_UNAVAILABLE',
      );
      return playerFailure(requestId, cleanupError(requestId));
    }

    emitEvents(options, result.events);

    if (!result.accepted) {
      return playerFailure(
        requestId,
        findResultError(result.events) ?? cleanupError(requestId),
      );
    }

    return playerSuccess(requestId, result.snapshot);
  });

  return {
    adapter: runtime.adapter,
    teardown: async () => {
      const unsubscribe = unsubscribeMainLifecycle;
      unsubscribeMainLifecycle = null;
      unsubscribe?.();
      try {
        const result = await runtime.adapter?.cleanup();
        if (result !== undefined && !result.accepted) {
          options.reportDiagnostic?.(
            'Player IPC cleanup failed',
            findResultError(result.events) ?? cleanupError(result.snapshot.requestId ?? 'player-cleanup'),
          );
        }
      } catch (error) {
        options.reportDiagnostic?.('Player IPC cleanup failed', error);
        recordPlayerIpcDiagnostic(
          options.diagnosticEventStore,
          'player-cleanup',
          'cleanup',
          'failed',
          'PLAYER_OPERATION_UNAVAILABLE',
        );
      } finally {
        for (const channel of PLAYER_IPC_CHANNELS) {
          ipcMain.removeHandler(channel);
        }
      }
    }
  };
}

function recordPlayerIpcDiagnostic(
  eventStore: DiagnosticEventStore | undefined,
  requestId: PlayerRequestId,
  operation: 'dispatch' | 'cleanup',
  status: 'failed',
  code: string,
): void {
  eventStore?.record({
    surface: 'player-ipc',
    category: operation === 'cleanup' ? 'cleanup' : 'playback',
    severity: 'error',
    status,
    operation,
    message: operation === 'cleanup' ? 'Player IPC cleanup failed.' : 'Player IPC dispatch failed.',
    requestId,
    result: 'failure',
    context: { code },
  });
}

function createDevelopmentHost(
  options: Pick<RegisterPlayerIpcHandlersOptions, 'nativeHostFactory'>,
): NativePlayerHostPort {
  return options.nativeHostFactory?.() ?? new InertNativePlayerHost();
}

function emitEvents(
  options: Pick<RegisterPlayerIpcHandlersOptions, 'sendSynchronousPlayerEvent'>,
  events: readonly PlayerEvent[],
): void {
  for (const event of events) {
    options.sendSynchronousPlayerEvent(event);
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
    seekSupport: 'unknown',
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
    quality: { mode: 'unknown', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unknown' },
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
  #activePlaybackRequestId: PlayerRequestId | null = null;

  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    switch (command.command) {
      case 'load': {
        this.#activePlaybackRequestId = command.requestId;
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
              requestId: this.#activePlaybackRequestId ?? command.requestId,
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
              requestId: this.#activePlaybackRequestId ?? command.requestId,
              status: 'paused',
              playing: false,
            },
          ],
        };
      case 'stop':
        return {
          ok: true,
          events: [{ type: 'ended', requestId: this.#activePlaybackRequestId ?? command.requestId }],
        };
      case 'seek.absolute':
        return {
          ok: true,
          events: [
            {
              type: 'time.updated',
              requestId: this.#activePlaybackRequestId ?? command.requestId,
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

  async queryAudioOutputs(_requestId: PlayerRequestId) {
    return {
      ok: false as const,
      error: {
        code: 'PLAYER_HELPER_AUDIO_OUTPUT_UNSUPPORTED',
        message: 'The player helper cannot perform this operation.',
        category: 'unsupported-capability' as const,
        recoverable: false,
        retryable: false,
      },
    };
  }

  async cleanup(_requestId: PlayerRequestId | null): Promise<void> {
    this.#activePlaybackRequestId = null;
    return undefined;
  }
}
