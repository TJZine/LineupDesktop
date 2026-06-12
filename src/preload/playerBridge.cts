import type {
  PlayerError,
  PlayerIpcResult,
  PlayerSnapshot,
} from '../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';

export type PlayerSnapshotBridgeInvoke = (
  channel: string,
  request: { requestId: string },
) => Promise<unknown>;

export interface PlayerSnapshotBridgeChannels {
  getSnapshot: string;
  cleanup: string;
}

export interface PlayerSnapshotBridgeValidators {
  isPlayerSnapshot(value: unknown): value is PlayerSnapshot;
  isPlayerError(value: unknown): value is PlayerError;
}

export function createPlayerSnapshotBridge(
  invoke: PlayerSnapshotBridgeInvoke,
  channels: PlayerSnapshotBridgeChannels,
  createRequestId: (prefix: string) => string,
  validators: PlayerSnapshotBridgeValidators,
): Pick<LineupDesktopPreloadApi['player'], 'getSnapshot' | 'cleanup'> {
  return {
    getSnapshot: () => invokePlayerSnapshotBridge(
      invoke,
      channels.getSnapshot,
      'getSnapshot',
      createRequestId('player-snapshot'),
      validators,
    ),
    cleanup: () => invokePlayerSnapshotBridge(
      invoke,
      channels.cleanup,
      'cleanup',
      createRequestId('player-cleanup'),
      validators,
    ),
  };
}

async function invokePlayerSnapshotBridge(
  invoke: PlayerSnapshotBridgeInvoke,
  channel: string,
  operation: 'getSnapshot' | 'cleanup',
  requestId: string,
  validators: PlayerSnapshotBridgeValidators,
): Promise<PlayerIpcResult<PlayerSnapshot>> {
  const request = { requestId };
  let result: unknown;
  try {
    result = await invoke(channel, request);
  } catch {
    return playerValidationFailure(
      requestId,
      `Player ${operation} invoke failed.`,
      operation,
      'invoke rejected',
    );
  }
  return validatePlayerSnapshotBridgeResult(result, requestId, operation, validators);
}

function validatePlayerSnapshotBridgeResult(
  result: unknown,
  requestId: string,
  operation: 'getSnapshot' | 'cleanup',
  validators: PlayerSnapshotBridgeValidators,
): PlayerIpcResult<PlayerSnapshot> {
  if (!isPlayerSnapshotIpcResult(result, requestId, validators)) {
    return playerValidationFailure(
      requestId,
      `Player ${operation} returned an invalid snapshot result.`,
      operation,
      'invalid invoke result',
    );
  }
  return result;
}

function isPlayerSnapshotIpcResult(
  value: unknown,
  requestId: string,
  validators: PlayerSnapshotBridgeValidators,
): value is PlayerIpcResult<PlayerSnapshot> {
  if (!isPlainRecord(value) || value.requestId !== requestId || typeof value.ok !== 'boolean') {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'requestId', 'value']) && validators.isPlayerSnapshot(value.value);
  }
  return hasOnlyKeys(value, ['ok', 'requestId', 'error']) && validators.isPlayerError(value.error);
}

function playerValidationFailure(
  requestId: string,
  message: string,
  operation: string,
  reason: string,
): PlayerIpcResult<PlayerSnapshot> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'PLAYER_VALIDATION_FAILED',
      category: 'validation-failure',
      message,
      recoverable: false,
      retryable: false,
      requestId,
      diagnostic: {
        component: 'preload-player-bridge',
        operation,
        status: 'rejected',
        reason,
      },
    },
  };
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
  requiredKeys: readonly string[],
): boolean {
  const allowed = new Set(requiredKeys);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return requiredKeys.every((key) => Object.hasOwn(value, key));
}
