import {
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerRequestId,
} from '../../contracts/player.js';
import type { NativePlayerHostFailure } from './nativePlayerHostPort.js';
import type { PrivilegedPlaybackDispatchContext } from './privilegedPlaybackDispatchContext.js';
import type { NativeHelperInputMessage } from './nativeHelperProtocol.js';
import type { NativeAudioOutput } from './nativePlayerHostPort.js';

export type NativeHelperProcessMessage =
  | { type: 'result'; requestId: PlayerRequestId; ok: true; events?: unknown }
  | { type: 'result'; requestId: PlayerRequestId; ok: false; error?: unknown }
  | { type: 'event'; event: unknown }
  | { type: 'audio-output.result'; requestId: PlayerRequestId; ok: true; outputs: NativeAudioOutput[] }
  | { type: 'audio-output.result'; requestId: PlayerRequestId; ok: false; error?: unknown };

const SAFE_FAILURE_CATEGORIES = PLAYER_ERROR_CATEGORIES.filter(
  (category) => category !== 'stale-request' && category !== 'validation-failure',
) as readonly NativePlayerHostFailure['category'][];

export function toNativeHelperCommand(
  command: PlayerCommand,
  context?: PrivilegedPlaybackDispatchContext | null,
): NativeHelperInputMessage {
  if (command.command === 'load' && context?.privatePlayback) {
    const { setup, playbackUrl, credentialHeader } = context.privatePlayback;
    return {
      type: 'command',
      requestId: command.requestId,
      command: command.command,
      payload: command.payload,
      setup,
      playbackUrl,
      credentialHeader,
    };
  }
  return {
    type: 'command',
    requestId: command.requestId,
    command: command.command,
    payload: command.payload,
  };
}

export function toNativeHelperCleanupMessage(
  requestId: PlayerRequestId | null,
): NativeHelperInputMessage {
  return { type: 'cleanup', requestId };
}

export function toNativeHelperAudioOutputQuery(
  requestId: PlayerRequestId,
): NativeHelperInputMessage {
  return { type: 'audio-output.query', requestId };
}

export function parseNativeHelperProcessMessage(
  line: string,
): { message: NativeHelperProcessMessage } | { error: NativePlayerHostFailure } {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return { error: safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
  }
  if (!isRecord(value)) {
    return { error: safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
  }
  if (value.type === 'event') {
    return { message: { type: 'event', event: value.event } };
  }
  if (
    value.type === 'audio-output.result' &&
    typeof value.requestId === 'string' &&
    value.requestId.length > 0
  ) {
    if (hasForbiddenPrivilegedField(value)) {
      return { error: safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
    }
    if (
      value.ok === true &&
      hasExactKeys(value, ['type', 'requestId', 'ok', 'outputs']) &&
      isNativeAudioOutputs(value.outputs)
    ) {
      return {
        message: {
          type: 'audio-output.result',
          requestId: value.requestId,
          ok: true,
          outputs: value.outputs,
        },
      };
    }
    if (
      value.ok === false &&
      hasExactKeys(value, ['type', 'requestId', 'ok', 'error'])
    ) {
      return {
        message: {
          type: 'audio-output.result',
          requestId: value.requestId,
          ok: false,
          error: value.error,
        },
      };
    }
    return { error: safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
  }
  if (value.type === 'result' && typeof value.requestId === 'string' && value.requestId.length > 0) {
    if (value.ok === true) {
      return {
        message: {
          type: 'result',
          requestId: value.requestId,
          ok: true,
          events: value.events,
        },
      };
    }
    if (value.ok === false) {
      if (hasForbiddenPrivilegedField(value.error)) {
        return { error: safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
      }
      return { message: { type: 'result', requestId: value.requestId, ok: false, error: value.error } };
    }
  }
  return { error: safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
}

function isNativeAudioOutputs(value: unknown): value is NativeAudioOutput[] {
  if (!Array.isArray(value) || value.length > 128) return false;
  return value.every((row) => (
    isRecord(row) &&
    Object.keys(row).length === 2 &&
    Object.hasOwn(row, 'nativeKey') &&
    Object.hasOwn(row, 'label') &&
    typeof row.nativeKey === 'string' &&
    [...row.nativeKey].length >= 1 &&
    [...row.nativeKey].length <= 512 &&
    typeof row.label === 'string' &&
    [...row.label].length <= 512 &&
    !hasForbiddenPrivilegedField(row)
  ));
}

export function normalizeNativeHelperFailure(value: unknown): NativePlayerHostFailure {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return safeNativeHostFailure('PLAYER_HELPER_COMMAND_FAILED', 'helper-failure', true, true);
  }
  const category =
    typeof value.category === 'string' && isSafeFailureCategory(value.category)
      ? value.category
      : 'helper-failure';
  return safeNativeHostFailure(
    typeof value.code === 'string' && value.code.length > 0
      ? normalizeCode(value.code)
      : 'PLAYER_HELPER_COMMAND_FAILED',
    category,
    typeof value.recoverable === 'boolean' ? value.recoverable : true,
    typeof value.retryable === 'boolean' ? value.retryable : true,
  );
}

export function safeNativeHostFailure(
  code: string,
  category: NativePlayerHostFailure['category'],
  recoverable: boolean,
  retryable: boolean,
): NativePlayerHostFailure {
  return {
    code: normalizeCode(code),
    category,
    message: safeFailureMessage(category),
    recoverable,
    retryable,
  };
}

function safeFailureMessage(category: NativePlayerHostFailure['category']): string {
  switch (category) {
    case 'timeout':
      return 'The player helper did not respond in time.';
    case 'aborted':
      return 'The player helper operation was stopped.';
    case 'cleanup-failure':
      return 'The player helper could not be cleaned up safely.';
    case 'unsupported-capability':
      return 'The player helper cannot perform this operation.';
    default:
      return 'The player helper failed while handling the command.';
  }
}

function normalizeCode(code: string): string {
  const normalized = code.toUpperCase().replace(/[^A-Z0-9_]/g, '_').slice(0, 80);
  return normalized.length > 0 ? normalized : 'PLAYER_HELPER_COMMAND_FAILED';
}

function isSafeFailureCategory(value: string): value is NativePlayerHostFailure['category'] {
  return (SAFE_FAILURE_CATEGORIES as readonly string[]).includes(value);
}

function hasForbiddenPrivilegedField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenPrivilegedField(item));
  }
  if (!isRecord(value)) {
    return false;
  }
  for (const [key, child] of Object.entries(value)) {
    if (
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ) ||
      hasForbiddenPrivilegedField(child)
    ) {
      return true;
    }
  }
  return false;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasExactKeys(
  value: Record<string, unknown>,
  expectedKeys: readonly string[],
): boolean {
  const keys = Object.keys(value);
  return keys.length === expectedKeys.length &&
    expectedKeys.every((key) => Object.hasOwn(value, key));
}
