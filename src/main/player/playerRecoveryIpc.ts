import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import { LINEUP_PLAYER_RECOVERY_CHANNEL } from '../../contracts/ipc.js';
import {
  PLAYER_RECOVERY_ACTIONS,
  type PlayerRecoveryAction,
  type PlayerRecoveryIpcResult,
} from '../../contracts/shell.js';
import type { PlayerError, PlayerSnapshot } from '../../contracts/player.js';
import type {
  PlaybackProgramTransitionOwner,
  PlaybackRecoveryTransitionResult,
} from './playbackProgramTransitionOwner.js';

type PlayerRecoveryIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterPlayerRecoveryIpcOptions {
  transitionOwner: Pick<
    PlaybackProgramTransitionOwner,
    'retryCurrent' | 'skipNext'
  >;
  getSnapshot(): PlayerSnapshot | null;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  ipcMain?: PlayerRecoveryIpcMain;
}

export type PlayerRecoveryIpcTeardown = () => void;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const INERT_PLAYER_SNAPSHOT: PlayerSnapshot = {
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
};

export function registerPlayerRecoveryIpc(
  options: RegisterPlayerRecoveryIpcOptions,
): PlayerRecoveryIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();
  ipcMain.handle(
    LINEUP_PLAYER_RECOVERY_CHANNEL,
    async (event, payload: unknown): Promise<PlayerRecoveryIpcResult> => {
      const request = readRequest(
        payload,
        options.createRequestId('player-recovery'),
      );
      if (!options.isAuthorizedEvent(event)) {
        return failure(
          request.requestId,
          INERT_PLAYER_SNAPSHOT,
          recoveryError(
            request.requestId,
            'PLAYER_RECOVERY_UNAUTHORIZED',
            'authorization',
            'Player recovery request was not authorized.',
            false,
          ),
        );
      }
      if (!request.ok) {
        return failure(
          request.requestId,
          readSnapshot(options),
          recoveryError(
            request.requestId,
            'PLAYER_RECOVERY_VALIDATION_FAILED',
            'validation-failure',
            'Player recovery request is invalid.',
            false,
          ),
        );
      }
      const result =
        request.action === 'retry-current'
          ? await options.transitionOwner.retryCurrent()
          : await options.transitionOwner.skipNext();
      const snapshot = readSnapshot(options);
      return result.accepted
        ? {
            ok: true,
            requestId: request.requestId,
            value: { status: 'accepted', snapshot },
          }
        : failure(
            request.requestId,
            snapshot,
            transitionFailure(request.requestId, result),
          );
    },
  );

  return () => {
    ipcMain.removeHandler(LINEUP_PLAYER_RECOVERY_CHANNEL);
  };
}

function readRequest(
  value: unknown,
  fallbackRequestId: string,
):
  | { ok: true; requestId: string; action: PlayerRecoveryAction }
  | { ok: false; requestId: string } {
  const requestId =
    isPlainRecord(value) &&
    typeof value.requestId === 'string' &&
    REQUEST_ID_PATTERN.test(value.requestId)
      ? value.requestId
      : fallbackRequestId;
  if (
    !isPlainRecord(value) ||
    !hasOnlyKeys(value, ['requestId', 'payload']) ||
    value.requestId !== requestId ||
    !isPlainRecord(value.payload) ||
    !hasOnlyKeys(value.payload, ['action']) ||
    !isPlayerRecoveryAction(value.payload.action)
  ) {
    return { ok: false, requestId };
  }
  return {
    ok: true,
    requestId,
    action: value.payload.action,
  };
}

function isPlayerRecoveryAction(value: unknown): value is PlayerRecoveryAction {
  return (
    typeof value === 'string' &&
    PLAYER_RECOVERY_ACTIONS.some((action) => action === value)
  );
}

function transitionFailure(
  requestId: string,
  result: Exclude<PlaybackRecoveryTransitionResult, { accepted: true }>,
): PlayerError {
  if (result.reason === 'busy') {
    return recoveryError(
      requestId,
      'PLAYER_RECOVERY_BUSY',
      'unknown',
      'Another player recovery action is already running.',
      true,
    );
  }
  if (result.reason === 'stale') {
    return recoveryError(
      requestId,
      'PLAYER_RECOVERY_STALE',
      'stale-request',
      'Playback changed before recovery completed.',
      true,
    );
  }
  return recoveryError(
    requestId,
    'PLAYER_RECOVERY_UNAVAILABLE',
    'unknown',
    'No playable recovery transition is available.',
    true,
  );
}

function recoveryError(
  requestId: string,
  code: string,
  category: PlayerError['category'],
  message: string,
  retryable: boolean,
): PlayerError {
  return {
    code,
    category,
    message,
    recoverable: retryable,
    retryable,
    requestId,
  };
}

function failure(
  requestId: string,
  snapshot: PlayerSnapshot,
  error: PlayerError,
): PlayerRecoveryIpcResult {
  return {
    ok: false,
    requestId,
    value: { status: 'failed', snapshot },
    error,
  };
}

function readSnapshot(options: RegisterPlayerRecoveryIpcOptions): PlayerSnapshot {
  return options.getSnapshot() ?? INERT_PLAYER_SNAPSHOT;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  allowedKeys: readonly string[],
): boolean {
  const allowed = new Set(allowedKeys);
  return (
    allowedKeys.every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => allowed.has(key))
  );
}

function getElectronIpcMain(): PlayerRecoveryIpcMain {
  const require = createRequire(import.meta.url);
  return require('electron').ipcMain as PlayerRecoveryIpcMain;
}
