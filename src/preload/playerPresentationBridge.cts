import type {
  PlayerPresentationError,
  PlayerPresentationMode,
  PlayerPresentationRequest,
  PlayerPresentationResult,
} from '../contracts/player.js';
import { PLAYER_PRESENTATION_MODES } from '../contracts/player.js';

export type PlayerPresentationBridgeInvoke = (
  channel: string,
  input: PlayerPresentationRequest,
) => Promise<unknown>;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const MODES: ReadonlySet<string> = new Set<PlayerPresentationMode>(PLAYER_PRESENTATION_MODES);
const SUCCESS_STATUSES = new Set(['applied', 'hidden', 'deferred', 'unsupported']);
const FAILURE_STATUSES = new Set(['main-stale', 'helper-stale', 'rejected', 'timeout', 'lifecycle-failure']);
const ERROR_BY_STATUS = {
  'main-stale': { code: 'PLAYER_PRESENTATION_MAIN_STALE', message: 'Player presentation request is stale.', recoverable: true, retryable: false },
  'helper-stale': { code: 'PLAYER_PRESENTATION_HELPER_STALE', message: 'Native presentation request is stale.', recoverable: true, retryable: false },
  rejected: { code: 'PLAYER_PRESENTATION_REJECTED', message: 'Player presentation request was rejected.', recoverable: true, retryable: false },
  timeout: { code: 'PLAYER_PRESENTATION_TIMEOUT', message: 'Native presentation request timed out.', recoverable: true, retryable: true },
  'lifecycle-failure': { code: 'PLAYER_PRESENTATION_LIFECYCLE_FAILURE', message: 'Native presentation is unavailable.', recoverable: true, retryable: true },
} as const;

export function createPlayerPresentationBridge(
  invoke: PlayerPresentationBridgeInvoke,
  channel: string,
): (input: PlayerPresentationRequest) => Promise<PlayerPresentationResult> {
  return async (input) => {
    const correlation = readCorrelation(input);
    if (!isPlayerPresentationRequest(input)) {
      return rejected(correlation.documentEpoch, correlation.revision);
    }
    let result: unknown;
    try {
      result = await invoke(channel, input);
    } catch {
      return rejected(input.documentEpoch, input.revision);
    }
    if (!isMatchingPlayerPresentationResult(result, input)) {
      return rejected(input.documentEpoch, input.revision);
    }
    return result;
  };
}

function isMatchingPlayerPresentationResult(
  value: unknown,
  input: PlayerPresentationRequest,
): value is PlayerPresentationResult {
  if (!isPlayerPresentationResult(value)) return false;
  const revisionMatches = value.revision === input.revision;
  const epochMatches = input.documentEpoch === null
    ? value.ok || value.documentEpoch === null
    : value.documentEpoch === input.documentEpoch;
  const negotiationStatusIsValid = !value.ok || (input.documentEpoch === null
    ? value.status === 'deferred' || value.status === 'hidden'
    : value.status !== 'deferred');
  return revisionMatches && epochMatches && negotiationStatusIsValid;
}

export function isPlayerPresentationRequest(value: unknown): value is PlayerPresentationRequest {
  if (!isPlainRecord(value) || !hasExactKeys(value, ['documentEpoch', 'revision', 'requestId', 'mode', 'rect'])) return false;
  if (!(value.documentEpoch === null || isPositiveSafeInteger(value.documentEpoch)) ||
    !isPositiveSafeInteger(value.revision) ||
    !(value.requestId === null || typeof value.requestId === 'string' && REQUEST_ID_PATTERN.test(value.requestId)) ||
    typeof value.mode !== 'string' || !MODES.has(value.mode)) return false;
  if (value.mode === 'hidden') return value.rect === null;
  if (!isRect(value.rect)) return false;
  if (value.mode === 'player-full' || value.mode === 'guide-overlay-full') {
    return value.rect.x === 0 && value.rect.y === 0 && value.rect.width === 1 && value.rect.height === 1;
  }
  return true;
}

export function isPlayerPresentationResult(value: unknown): value is PlayerPresentationResult {
  if (!isPlainRecord(value) || typeof value.ok !== 'boolean') return false;
  if (value.ok) {
    return hasExactKeys(value, ['ok', 'status', 'documentEpoch', 'revision']) &&
      typeof value.status === 'string' && SUCCESS_STATUSES.has(value.status) &&
      isPositiveSafeInteger(value.documentEpoch) && isPositiveSafeInteger(value.revision);
  }
  return hasExactKeys(value, ['ok', 'status', 'documentEpoch', 'revision', 'error']) &&
    typeof value.status === 'string' && FAILURE_STATUSES.has(value.status) &&
    (value.documentEpoch === null || isPositiveSafeInteger(value.documentEpoch)) &&
    (value.revision === null || isPositiveSafeInteger(value.revision)) &&
    isPresentationError(value.status, value.error);
}

function isPresentationError(
  status: unknown,
  value: unknown,
): value is PlayerPresentationError {
  if (typeof status !== 'string' || !FAILURE_STATUSES.has(status) ||
    !isPlainRecord(value) || !hasExactKeys(value, ['code', 'message', 'recoverable', 'retryable'])) return false;
  const expected = ERROR_BY_STATUS[status as keyof typeof ERROR_BY_STATUS];
  return value.code === expected.code && value.message === expected.message &&
    value.recoverable === expected.recoverable && value.retryable === expected.retryable;
}

function readCorrelation(value: unknown): { documentEpoch: number | null; revision: number | null } {
  if (!isPlainRecord(value)) return { documentEpoch: null, revision: null };
  return {
    documentEpoch: value.documentEpoch === null || isPositiveSafeInteger(value.documentEpoch) ? value.documentEpoch : null,
    revision: isPositiveSafeInteger(value.revision) ? value.revision : null,
  };
}

function rejected(documentEpoch: number | null, revision: number | null): PlayerPresentationResult {
  return {
    ok: false,
    status: 'rejected',
    documentEpoch,
    revision,
    error: {
      code: 'PLAYER_PRESENTATION_REJECTED',
      message: 'Player presentation request was rejected.',
      recoverable: true,
      retryable: false,
    },
  };
}

function isRect(value: unknown): value is { x: number; y: number; width: number; height: number } {
  if (!isPlainRecord(value) || !hasExactKeys(value, ['x', 'y', 'width', 'height'])) return false;
  if (!(typeof value.x === 'number' && typeof value.y === 'number' && typeof value.width === 'number' && typeof value.height === 'number')) return false;
  const numbers = [value.x, value.y, value.width, value.height];
  return numbers.every((item) => Number.isFinite(item)) &&
    value.x >= 0 && value.y >= 0 && value.width > 0 && value.height > 0 &&
    value.x <= 1 && value.y <= 1 && value.width <= 1 && value.height <= 1 &&
    value.x + value.width <= 1 && value.y + value.height <= 1;
}

function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}
