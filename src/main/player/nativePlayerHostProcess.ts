import { clearTimeout, setTimeout } from 'node:timers';
import type { Buffer } from 'node:buffer';
import type { EventEmitter } from 'node:events';
import type { Readable, Writable } from 'node:stream';
import {
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerRequestId,
} from '../../contracts/player.js';
import type { DiagnosticEventStore, DiagnosticEventInput } from '../diagnostics/diagnosticEventStore.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostEvent,
  NativePlayerHostFailure,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from './nativePlayerHostPort.js';
type ProcessMessage =
  | { type: 'result'; requestId: PlayerRequestId; ok: true; events?: readonly NativePlayerHostEvent[] }
  | { type: 'result'; requestId: PlayerRequestId; ok: false; error?: unknown }
  | { type: 'event'; event: NativePlayerHostEvent };
type PendingCommand = {
  requestId: PlayerRequestId; resolve(result: NativePlayerHostCommandResult): void;
  timeout: ReturnType<typeof setTimeout>; events: NativePlayerHostEvent[];
};
export interface NativePlayerHostChildProcess extends EventEmitter {
  stdin: Writable;
  stdout: Readable;
  stderr: Readable;
  killed?: boolean;
  kill(signal?: string): boolean;
}
export interface NativePlayerHostProcessOptions {
  spawnHostProcess(): NativePlayerHostChildProcess;
  requestTimeoutMs?: number;
  cleanupGraceMs?: number;
  diagnosticEventStore?: DiagnosticEventStore;
}
const DEFAULT_REQUEST_TIMEOUT_MS = 5_000;
const DEFAULT_CLEANUP_GRACE_MS = 500;
const MAX_LINE_LENGTH = 64 * 1024;
const SAFE_FAILURE_CATEGORIES = PLAYER_ERROR_CATEGORIES.filter(
  (category) => category !== 'stale-request' && category !== 'validation-failure',
) as readonly NativePlayerHostFailure['category'][];
// Adapter-level validation stays outside this process-framing owner.
export class NativePlayerHostProcess implements NativePlayerHostPort {
  readonly #spawnHostProcess: () => NativePlayerHostChildProcess;
  readonly #requestTimeoutMs: number;
  readonly #cleanupGraceMs: number;
  readonly #diagnosticEventStore?: DiagnosticEventStore;
  #child: NativePlayerHostChildProcess | null = null;
  #pending = new Map<PlayerRequestId, PendingCommand>();
  #lineBuffer = '';
  #lifecycleFailureListeners = new Set<(failure: NativePlayerHostLifecycleFailure) => void>();
  #spawnCount = 0;
  constructor(options: NativePlayerHostProcessOptions) {
    this.#spawnHostProcess = options.spawnHostProcess;
    this.#requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
    this.#cleanupGraceMs = options.cleanupGraceMs ?? DEFAULT_CLEANUP_GRACE_MS;
    this.#diagnosticEventStore = options.diagnosticEventStore;
  }
  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    const child = this.#getOrSpawnChild();
    if ('error' in child) {
      return { ok: false, error: child.error };
    }
    const activeChild = child.child;
    return new Promise<NativePlayerHostCommandResult>((resolve) => {
      const timeout = setTimeout(() => {
        this.#quarantineChild(
          activeChild,
          safeFailure('PLAYER_HELPER_TIMEOUT', 'timeout', true, true),
        );
      }, this.#requestTimeoutMs);
      const pending: PendingCommand = {
        requestId: command.requestId,
        resolve: (result) => {
          clearTimeout(timeout);
          resolve(result);
        },
        timeout,
        events: [],
      };
      this.#pending.set(command.requestId, pending);
      try {
        activeChild.stdin.write(`${JSON.stringify(toProcessCommand(command))}\n`, (error) => {
          if (error !== null && error !== undefined) {
            this.#resolvePending(
              command.requestId,
              {
                ok: false,
                error: safeFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true),
              },
            );
          }
        });
      } catch {
        this.#resolvePending(command.requestId, {
          ok: false,
          error: safeFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true),
        });
      }
    });
  }
  async cleanup(requestId: PlayerRequestId | null): Promise<void> {
    const child = this.#child;
    this.#child = null;
    this.#lineBuffer = '';
    this.#rejectAllPending(safeFailure('PLAYER_HELPER_CLEANED_UP', 'aborted', true, false));
    if (child === null) {
      return;
    }
    let writeError: unknown;
    try {
      child.stdin.write(`${JSON.stringify({ type: 'cleanup', requestId })}\n`, () => undefined);
    } catch (error: unknown) {
      writeError = error;
    }
    try {
      await this.#reapChild(child);
    } catch (reapError: unknown) {
      this.#recordCleanupFailure(requestId);
      if (writeError !== undefined) {
        throw writeError;
      }
      throw reapError;
    }
    if (writeError !== undefined) {
      this.#recordCleanupFailure(requestId);
      throw writeError;
    }
  }
  onLifecycleFailure(
    listener: (failure: NativePlayerHostLifecycleFailure) => void,
  ): () => void {
    this.#lifecycleFailureListeners.add(listener);
    return () => {
      this.#lifecycleFailureListeners.delete(listener);
    };
  }
  #getOrSpawnChild():
    | { child: NativePlayerHostChildProcess }
    | { error: NativePlayerHostFailure } {
    if (this.#child !== null) {
      return { child: this.#child };
    }
    try {
      const child = this.#spawnHostProcess();
      this.#child = child;
      this.#recordDiagnostic({
        category: this.#spawnCount > 0 ? 'helper-restart' : 'lifecycle',
        severity: 'info',
        status: 'succeeded',
        operation: 'helper.spawn',
        message: this.#spawnCount > 0 ? 'Player helper replacement started.' : 'Player helper started.',
        result: 'success',
        context: { restart: this.#spawnCount > 0 },
      });
      this.#spawnCount += 1;
      child.stdout.on('data', (chunk: Buffer | string) => this.#handleStdoutChunk(child, chunk));
      child.stderr.on('data', (chunk: Buffer | string) => this.#handleStderrChunk(chunk));
      child.stdin.on('error', () => this.#handleChildStreamError(child));
      child.stdout.on('error', () => this.#handleChildStreamError(child));
      child.stderr.on('error', () => this.#handleChildStreamError(child));
      child.once('error', () => {
        if (this.#child === child) {
          const failure = safeFailure('PLAYER_HELPER_SPAWN_FAILED', 'helper-failure', true, true);
          this.#child = null;
          this.#settleProcessFailure(failure);
        }
      });
      child.once('close', () => {
        if (this.#child === child) {
          const failure = safeFailure('PLAYER_HELPER_EXITED', 'helper-failure', true, true);
          this.#child = null;
          this.#settleProcessFailure(failure);
        }
      });
      return { child };
    } catch {
      const error = safeFailure('PLAYER_HELPER_SPAWN_FAILED', 'helper-failure', true, true);
      this.#recordFailure(null, error, { operation: 'helper.spawn', status: 'failed' });
      return {
        error,
      };
    }
  }
  #handleChildStreamError(child: NativePlayerHostChildProcess): void {
    if (this.#child !== child) {
      return;
    }
    this.#child = null;
    this.#lineBuffer = '';
    const failure = safeFailure('PLAYER_HELPER_STREAM_FAILED', 'helper-failure', true, true);
    const requestId = this.#firstPendingRequestId();
    this.#settleProcessFailure(failure);
    this.#reapChild(child).catch(() => this.#recordCleanupFailure(requestId));
  }
  #handleStderrChunk(chunk: Buffer | string): void {
    this.#recordDiagnostic({
      category: 'lifecycle',
      severity: 'warning',
      status: 'redacted',
      operation: 'helper.output',
      message: 'Player helper diagnostic output was dropped.',
      result: 'ignored',
      context: { bytes: chunk.toString().length },
    });
  }
  #handleStdoutChunk(child: NativePlayerHostChildProcess, chunk: Buffer | string): void {
    if (this.#child !== child) {
      return;
    }
    this.#lineBuffer += chunk.toString();
    if (this.#lineBuffer.length > MAX_LINE_LENGTH) {
      const failure = safeFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true);
      this.#quarantineChild(child, failure);
      return;
    }
    let newlineIndex = this.#lineBuffer.indexOf('\n');
    while (newlineIndex >= 0) {
      const line = this.#lineBuffer.slice(0, newlineIndex).trim();
      this.#lineBuffer = this.#lineBuffer.slice(newlineIndex + 1);
      if (line.length > 0) {
        this.#handleLine(child, line);
      }
      newlineIndex = this.#lineBuffer.indexOf('\n');
    }
  }
  #handleLine(child: NativePlayerHostChildProcess, line: string): void {
    const message = parseProcessMessage(line);
    if ('error' in message) {
      this.#quarantineChild(child, message.error);
      return;
    }
    if (message.message.type === 'event') {
      const requestId = message.message.event.requestId;
      if (requestId !== null) {
        this.#pending.get(requestId)?.events.push(message.message.event);
      }
      return;
    }
    const pending = this.#pending.get(message.message.requestId);
    if (pending === undefined) {
      return;
    }
    if (message.message.ok) {
      this.#resolvePending(pending.requestId, {
        ok: true,
        events: [...pending.events, ...(message.message.events ?? [])],
      });
      return;
    }
    this.#resolvePending(pending.requestId, {
      ok: false,
      error: normalizeFailure(message.message.error),
    });
  }
  #resolvePending(requestId: PlayerRequestId, result: NativePlayerHostCommandResult): void {
    const pending = this.#pending.get(requestId);
    if (pending === undefined) {
      return;
    }
    this.#pending.delete(requestId);
    pending.resolve(result);
  }
  #rejectAllPending(error: NativePlayerHostFailure): void {
    for (const [requestId, pending] of [...this.#pending]) {
      clearTimeout(pending.timeout);
      const cleanupAborted = error.category === 'aborted';
      this.#recordFailure(requestId, error, {
        operation: cleanupAborted ? 'helper.cleanup' : error.category === 'timeout' ? 'helper.timeout' : 'helper.command',
        status: cleanupAborted ? 'cancelled' : error.code === 'PLAYER_HELPER_MALFORMED_OUTPUT' ? 'redacted' : 'failed',
      });
      pending.resolve({ ok: false, error });
      this.#pending.delete(requestId);
    }
  }
  #quarantineChild(
    child: NativePlayerHostChildProcess,
    error: NativePlayerHostFailure,
  ): void {
    if (this.#child !== child) {
      return;
    }
    const requestId = this.#firstPendingRequestId();
    this.#child = null;
    this.#lineBuffer = '';
    this.#settleProcessFailure(error);
    this.#reapChild(child).catch(() => this.#recordCleanupFailure(requestId));
  }
  #settleProcessFailure(error: NativePlayerHostFailure): void {
    if (this.#pending.size > 0) {
      this.#rejectAllPending(error);
      return;
    }
    this.#emitLifecycleFailure({ requestId: null, error });
  }
  #emitLifecycleFailure(failure: NativePlayerHostLifecycleFailure): void {
    this.#recordFailure(failure.requestId, failure.error, {
      operation: 'helper.lifecycle',
      status: 'observed',
    });
    for (const listener of [...this.#lifecycleFailureListeners]) {
      try {
        listener(failure);
      } catch {
        // Lifecycle failure delivery is best effort; one observer must not block the rest.
      }
    }
  }
  #recordFailure(
    requestId: PlayerRequestId | null,
    error: NativePlayerHostFailure,
    input: {
      operation: string;
      status: DiagnosticEventInput['status'];
      context?: Record<string, string | number | boolean>;
    },
  ): void {
    this.#recordDiagnostic({
      category: diagnosticCategoryForFailure(error),
      severity: input.status === 'observed' || input.status === 'cancelled' ? 'warning' : 'error',
      status: input.status,
      operation: input.operation,
      message: 'Player helper lifecycle failure observed.',
      requestId: requestId ?? undefined,
      result: input.status === 'observed' ? 'ignored' : input.status === 'cancelled' ? 'cancelled' : 'failure',
      context: {
        code: error.code,
        category: error.category,
        recoverable: error.recoverable,
        retryable: error.retryable,
        ...input.context,
      },
    });
  }
  #recordDiagnostic(input: Omit<DiagnosticEventInput, 'surface'>): void {
    this.#diagnosticEventStore?.record({ surface: 'native-host-process', ...input });
  }
  #firstPendingRequestId(): PlayerRequestId | null {
    return this.#pending.keys().next().value ?? null;
  }
  #recordCleanupFailure(requestId: PlayerRequestId | null): void {
    this.#recordDiagnostic({
      category: 'cleanup', severity: 'error', status: 'failed', operation: 'helper.cleanup',
      message: 'Player helper cleanup failed.', requestId: requestId ?? undefined, result: 'failure',
      context: { code: 'PLAYER_HELPER_CLEANUP_FAILED' },
    });
  }
  async #reapChild(child: NativePlayerHostChildProcess): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      let settled = false;
      const finish = (error?: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(killTimer);
        clearTimeout(failTimer);
        if (error === undefined) {
          resolve();
          return;
        }
        reject(error);
      };
      const killTimer = setTimeout(() => {
        try {
          child.kill('SIGKILL');
        } catch {
          finish(new Error('Native player host cleanup failed.'));
        }
      }, this.#cleanupGraceMs);
      const failTimer = setTimeout(() => {
        finish(new Error('Native player host cleanup failed.'));
      }, this.#cleanupGraceMs * 2);
      child.once('close', () => {
        finish();
      });
      try {
        child.kill('SIGTERM');
      } catch {
        finish(new Error('Native player host cleanup failed.'));
      }
    });
  }
}
function toProcessCommand(command: PlayerCommand): Record<string, unknown> {
  return { type: 'command', requestId: command.requestId, command: command.command, payload: command.payload };
}
function parseProcessMessage(
  line: string,
): { message: ProcessMessage } | { error: NativePlayerHostFailure } {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return { error: safeFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
  }
  if (hasForbiddenPrivilegedField(value) || !isRecord(value)) {
    return { error: safeFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
  }
  if (value.type === 'event' && isRecord(value.event)) {
    return { message: { type: 'event', event: value.event as NativePlayerHostEvent } };
  }
  if (value.type === 'result' && typeof value.requestId === 'string' && value.requestId.length > 0) {
    if (value.ok === true) {
      return {
        message: {
          type: 'result',
          requestId: value.requestId,
          ok: true,
          events: Array.isArray(value.events) ? (value.events as NativePlayerHostEvent[]) : undefined,
        },
      };
    }
    if (value.ok === false) {
      return { message: { type: 'result', requestId: value.requestId, ok: false, error: value.error } };
    }
  }
  return { error: safeFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true) };
}
function normalizeFailure(value: unknown): NativePlayerHostFailure {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return safeFailure('PLAYER_HELPER_COMMAND_FAILED', 'helper-failure', true, true);
  }
  const category =
    typeof value.category === 'string' && isSafeFailureCategory(value.category)
      ? value.category
      : 'helper-failure';
  return safeFailure(
    typeof value.code === 'string' && value.code.length > 0
      ? normalizeCode(value.code)
      : 'PLAYER_HELPER_COMMAND_FAILED',
    category,
    typeof value.recoverable === 'boolean' ? value.recoverable : true,
    typeof value.retryable === 'boolean' ? value.retryable : true,
  );
}
function safeFailure(
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
function diagnosticCategoryForFailure(error: NativePlayerHostFailure): DiagnosticEventInput['category'] {
  return error.category === 'aborted' ? 'cleanup' : 'helper-crash';
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
  const normalized = code.replace(/[^A-Z0-9_]/g, '_').slice(0, 80);
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
  return typeof value === 'object' && value !== null;
}
