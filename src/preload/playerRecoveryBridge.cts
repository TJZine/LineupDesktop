import type { PlayerError, PlayerSnapshot } from '../contracts/player.js';
import {
  PLAYER_RECOVERY_ACTIONS,
  type LineupDesktopPreloadApi,
  type PlayerRecoveryAction,
  type PlayerRecoveryIpcResult,
} from '../contracts/shell.js';

export type PlayerRecoveryBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export interface PlayerRecoveryBridgeValidators {
  isSnapshot(value: unknown): value is PlayerSnapshot;
  isError(value: unknown): value is PlayerError;
  hasForbiddenField(value: unknown): boolean;
}

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;

export function createPlayerRecoveryBridge(
  invoke: PlayerRecoveryBridgeInvoke,
  channel: string,
  createRequestId: (prefix: string) => string,
  validators: PlayerRecoveryBridgeValidators,
): LineupDesktopPreloadApi['player']['recover'] {
  return async (input) => {
    const requestId = createRequestId('player-recovery');
    if (
      !isPlainRecord(input) ||
      !hasOnlyKeys(input, ['action']) ||
      !isPlayerRecoveryAction(input.action)
    ) {
      return failure(
        requestId,
        createEmptySnapshot(),
        validationError(requestId),
      );
    }
    try {
      const result = await invoke(channel, {
        requestId,
        payload: { action: input.action },
      });
      return isRecoveryResult(result, requestId, validators)
        ? result
        : failure(
            requestId,
            createEmptySnapshot(),
            validationError(requestId),
          );
    } catch {
      return failure(
        requestId,
        createEmptySnapshot(),
        {
          ...validationError(requestId),
          code: 'PLAYER_OPERATION_UNAVAILABLE',
          category: 'unknown',
          message: 'Player recovery is unavailable.',
          recoverable: true,
          retryable: true,
        },
      );
    }
  };
}

function isRecoveryResult(
  value: unknown,
  requestId: string,
  validators: PlayerRecoveryBridgeValidators,
): value is PlayerRecoveryIpcResult {
  if (
    !isPlainRecord(value) ||
    value.requestId !== requestId ||
    !REQUEST_ID_PATTERN.test(requestId) ||
    validators.hasForbiddenField(value)
  ) {
    return false;
  }
  if (
    value.ok === true &&
    hasOnlyKeys(value, ['ok', 'requestId', 'value']) &&
    isPlainRecord(value.value) &&
    hasOnlyKeys(value.value, ['status', 'snapshot']) &&
    value.value.status === 'accepted' &&
    validators.isSnapshot(value.value.snapshot)
  ) {
    return true;
  }
  return (
    value.ok === false &&
    hasOnlyKeys(value, ['ok', 'requestId', 'value', 'error']) &&
    isPlainRecord(value.value) &&
    hasOnlyKeys(value.value, ['status', 'snapshot']) &&
    value.value.status === 'failed' &&
    validators.isSnapshot(value.value.snapshot) &&
    validators.isError(value.error)
  );
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

function validationError(requestId: string): PlayerError {
  return {
    code: 'PLAYER_RECOVERY_VALIDATION_FAILED',
    category: 'validation-failure',
    message: 'Player recovery request is invalid.',
    recoverable: false,
    retryable: false,
    requestId,
  };
}

function createEmptySnapshot(): PlayerSnapshot {
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
    quality: {
      mode: 'unknown',
      sourceDynamicRange: 'unknown',
      outputDynamicRangeStatus: 'unknown',
    },
    lastError: null,
  };
}

function isPlayerRecoveryAction(value: unknown): value is PlayerRecoveryAction {
  return (
    typeof value === 'string' &&
    PLAYER_RECOVERY_ACTIONS.some((action) => action === value)
  );
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
