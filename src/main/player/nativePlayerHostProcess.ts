import { clearTimeout, setTimeout } from 'node:timers';
import type { Buffer } from 'node:buffer';
import type { EventEmitter } from 'node:events';
import type { Readable, Writable } from 'node:stream';
import {
  type PlayerCommand,
  type PlayerRequestId,
} from '../../contracts/player.js';
import type { DiagnosticEventStore, DiagnosticEventInput } from '../diagnostics/diagnosticEventStore.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostAudioOutputResult,
  NativePlayerHostFailure,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
  NativePlayerPresentationResult,
  NativePlayerPresentationUpdate,
} from './nativePlayerHostPort.js';
import type { PrivilegedPlaybackDispatchContext } from './privilegedPlaybackDispatchContext.js';
import { MAX_PRESENTATION_MESSAGE_SIZE, validateHelperMessageSize } from './nativeHelperProtocol.js';
import {
  normalizeNativeHelperFailure,
  parseNativeHelperProcessMessage,
  safeNativeHostFailure,
  toNativeHelperCleanupMessage,
  toNativeHelperCommand,
  toNativeHelperAudioOutputQuery,
  toNativeHelperPresentationUpdate,
} from './nativeHelperProtocolCodec.js';

type PendingCommand =
  | {
      kind: 'command'; requestId: PlayerRequestId;
      resolve(result: NativePlayerHostCommandResult): void;
      timeout: ReturnType<typeof setTimeout>; events: unknown[];
    }
  | {
      kind: 'audio-output'; requestId: PlayerRequestId;
      resolve(result: NativePlayerHostAudioOutputResult): void;
      timeout: ReturnType<typeof setTimeout>; events: [];
    }
  | {
      kind: 'presentation'; requestId: PlayerRequestId;
      documentEpoch: number; revision: number;
      mode: SequencedNativePlayerPresentationUpdate['mode'];
      resolve(result: NativePlayerPresentationResult): void;
      timeout: ReturnType<typeof setTimeout>; events: [];
    };
type SequencedNativePlayerPresentationUpdate = NativePlayerPresentationUpdate & {
  operationId: PlayerRequestId;
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
  #eventListeners = new Set<(event: unknown) => void>();
  #recoveryPending = false;
  #latestPresentation: SequencedNativePlayerPresentationUpdate | null = null;
  #activePresentation: Promise<NativePlayerPresentationResult> | null = null;
  #playbackBoundaryActive = false;
  #presentationOperationSequence = 0n;
  constructor(options: NativePlayerHostProcessOptions) {
    this.#spawnHostProcess = options.spawnHostProcess;
    this.#requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
    this.#cleanupGraceMs = options.cleanupGraceMs ?? DEFAULT_CLEANUP_GRACE_MS;
    this.#diagnosticEventStore = options.diagnosticEventStore;
  }
  async execute(
    command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<NativePlayerHostCommandResult> {
    if (command.command === 'load') {
      if (this.#playbackBoundaryActive) {
        return { ok: false, error: safeNativeHostFailure('PLAYER_HELPER_DUPLICATE_REQUEST', 'helper-failure', false, false) };
      }
      this.#playbackBoundaryActive = true;
      try {
        const hidden = await this.#preparePlaybackBoundary();
        if (!hidden.ok) return hidden;
        const execution = this.#executeCommand(command, context);
        this.#playbackBoundaryActive = false;
        return await execution;
      } finally {
        this.#playbackBoundaryActive = false;
      }
    }
    return this.#executeCommand(command, context);
  }
  async #executeCommand(
    command: PlayerCommand,
    context?: PrivilegedPlaybackDispatchContext | null,
  ): Promise<NativePlayerHostCommandResult> {
    if (this.#pending.has(command.requestId)) {
      return {
        ok: false,
        error: safeNativeHostFailure('PLAYER_HELPER_DUPLICATE_REQUEST', 'helper-failure', false, false),
      };
    }
    const child = this.#getOrSpawnChild();
    if ('error' in child) {
      return { ok: false, error: child.error };
    }
    const activeChild = child.child;
    return new Promise<NativePlayerHostCommandResult>((resolve) => {
      const timeout = setTimeout(() => {
        this.#quarantineChild(
          activeChild,
          safeNativeHostFailure('PLAYER_HELPER_TIMEOUT', 'timeout', true, true),
        );
      }, this.#requestTimeoutMs);
      const pending: PendingCommand = {
        kind: 'command',
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
        const procCmd = toNativeHelperCommand(command, context);
        const serialized = JSON.stringify(procCmd);
        validateHelperMessageSize(serialized);
        activeChild.stdin.write(`${serialized}\n`, (error) => {
          if (error !== null && error !== undefined) {
            this.#resolvePending(
              command.requestId,
              {
                ok: false,
                error: safeNativeHostFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true),
              },
            );
          }
        });
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : 'Write failed';
        this.#resolvePending(command.requestId, {
          ok: false,
          error: safeNativeHostFailure(
            msg.includes('exceeds maximum limit') ? 'PLAYER_HELPER_MESSAGE_TOO_LARGE' : 'PLAYER_HELPER_WRITE_FAILED',
            'helper-failure',
            true,
            true,
          ),
        });
      }
    });
  }
  async queryAudioOutputs(
    requestId: PlayerRequestId,
  ): Promise<NativePlayerHostAudioOutputResult> {
    if (this.#pending.has(requestId)) {
      return {
        ok: false,
        error: safeNativeHostFailure('PLAYER_HELPER_DUPLICATE_REQUEST', 'helper-failure', false, false),
      };
    }
    const child = this.#getOrSpawnChild();
    if ('error' in child) {
      return { ok: false, error: child.error };
    }
    const activeChild = child.child;
    return new Promise<NativePlayerHostAudioOutputResult>((resolve) => {
      const timeout = setTimeout(() => {
        this.#quarantineChild(
          activeChild,
          safeNativeHostFailure('PLAYER_HELPER_TIMEOUT', 'timeout', true, true),
        );
      }, this.#requestTimeoutMs);
      this.#pending.set(requestId, {
        kind: 'audio-output',
        requestId,
        resolve: (result) => {
          clearTimeout(timeout);
          resolve(result);
        },
        timeout,
        events: [],
      });
      try {
        const serialized = JSON.stringify(toNativeHelperAudioOutputQuery(requestId));
        validateHelperMessageSize(serialized);
        activeChild.stdin.write(`${serialized}\n`, (error) => {
          if (error !== null && error !== undefined) {
            this.#resolveAudioPending(requestId, {
              ok: false,
              error: safeNativeHostFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true),
            });
          }
        });
      } catch {
        this.#resolveAudioPending(requestId, {
          ok: false,
          error: safeNativeHostFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true),
        });
      }
    });
  }
  async updatePresentation(
    update: NativePlayerPresentationUpdate,
  ): Promise<NativePlayerPresentationResult> {
    if (this.#playbackBoundaryActive || this.#activePresentation !== null) {
      return {
        ok: false,
        classification: 'pre-send-rejected',
        error: safeNativeHostFailure('PLAYER_HELPER_DUPLICATE_REQUEST', 'helper-failure', false, false),
      };
    }
    const sequencedUpdate = this.#assignPresentationOperationId(update);
    let serialized: string;
    try {
      serialized = JSON.stringify(toNativeHelperPresentationUpdate(sequencedUpdate));
      if (serialized.length > MAX_PRESENTATION_MESSAGE_SIZE) throw new Error('presentation message too large');
    } catch {
      return {
        ok: false,
        classification: 'pre-send-rejected',
        error: safeNativeHostFailure('PLAYER_HELPER_PRESENTATION_REJECTED', 'helper-failure', true, false),
      };
    }
    return this.#performPresentationUpdate(sequencedUpdate, serialized);
  }
  #performPresentationUpdate(
    update: SequencedNativePlayerPresentationUpdate,
    serialized: string,
  ): Promise<NativePlayerPresentationResult> {
    const operation = this.#writePresentationUpdate(update, serialized);
    this.#activePresentation = operation;
    void operation.then(() => {
      if (this.#activePresentation === operation) this.#activePresentation = null;
    });
    return operation;
  }
  async #writePresentationUpdate(
    update: SequencedNativePlayerPresentationUpdate,
    serialized: string,
  ): Promise<NativePlayerPresentationResult> {
    const child = this.#getOrSpawnChild();
    if ('error' in child) return { ok: false, classification: 'shared-host-failure', error: child.error };
    const activeChild = child.child;
    return new Promise<NativePlayerPresentationResult>((resolve) => {
      const timeout = setTimeout(() => {
        this.#quarantineChild(activeChild, safeNativeHostFailure('PLAYER_HELPER_TIMEOUT', 'timeout', true, true));
      }, this.#requestTimeoutMs);
      this.#pending.set(update.operationId, {
        kind: 'presentation', requestId: update.operationId,
        documentEpoch: update.documentEpoch, revision: update.revision, mode: update.mode,
        events: [], timeout,
        resolve: (result) => {
          clearTimeout(timeout);
          if (result.ok && result.status !== 'stale') this.#latestPresentation = update;
          resolve(result);
        },
      });
      try {
        activeChild.stdin.write(`${serialized}\n`, (error) => {
          if (error !== null && error !== undefined) {
            this.#quarantineChild(activeChild, safeNativeHostFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true));
          }
        });
      } catch {
        this.#quarantineChild(activeChild, safeNativeHostFailure('PLAYER_HELPER_WRITE_FAILED', 'helper-failure', true, true));
      }
    });
  }
  async cleanup(requestId: PlayerRequestId | null): Promise<void> {
    if (this.#playbackBoundaryActive) throw new Error('Native player cleanup is unavailable.');
    this.#playbackBoundaryActive = true;
    try {
      const hidden = await this.#preparePlaybackBoundary();
      if (!hidden.ok) throw new Error('Native player presentation could not be hidden.');
      const child = this.#child;
      this.#child = null;
      this.#lineBuffer = '';
      this.#latestPresentation = null;
      this.#rejectAllPending(safeNativeHostFailure('PLAYER_HELPER_CLEANED_UP', 'aborted', true, false));
      if (child === null) return;
      let writeError: unknown;
      try {
        child.stdin.write(`${JSON.stringify(toNativeHelperCleanupMessage(requestId))}\n`, () => undefined);
      } catch (error: unknown) {
        writeError = error;
      }
      let reapError: unknown;
      try {
        await this.#reapChild(child);
      } catch (error: unknown) {
        reapError = error;
        this.#recordCleanupFailure(requestId);
      }
      if (writeError !== undefined) {
        if (reapError === undefined) this.#recordCleanupFailure(requestId);
        throw writeError;
      }
      if (reapError !== undefined) throw reapError;
    } finally {
      this.#playbackBoundaryActive = false;
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
  onEvent(listener: (event: unknown) => void): () => void {
    this.#eventListeners.add(listener);
    return () => {
      this.#eventListeners.delete(listener);
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
      const isRecovery = this.#recoveryPending;
      this.#child = child;
      this.#recordDiagnostic({
        category: isRecovery ? 'helper-restart' : 'lifecycle',
        severity: 'info',
        status: 'succeeded',
        operation: 'helper.spawn',
        message: isRecovery ? 'Player helper replacement started.' : 'Player helper started.',
        result: 'success',
        context: { restart: isRecovery },
      });
      this.#recoveryPending = false;
      child.stdout.on('data', (chunk: Buffer | string) => this.#handleStdoutChunk(child, chunk));
      child.stderr.on('data', (chunk: Buffer | string) => this.#handleStderrChunk(chunk));
      child.stdin.on('error', () => this.#handleChildStreamError(child));
      child.stdout.on('error', () => this.#handleChildStreamError(child));
      child.stderr.on('error', () => this.#handleChildStreamError(child));
      child.once('error', () => {
        if (this.#child === child) {
          const failure = safeNativeHostFailure('PLAYER_HELPER_SPAWN_FAILED', 'helper-failure', true, true);
          this.#child = null;
          this.#lineBuffer = '';
          this.#recoveryPending = true;
          this.#settleProcessFailure(failure);
        }
      });
      child.once('close', () => {
        if (this.#child === child) {
          const failure = safeNativeHostFailure('PLAYER_HELPER_EXITED', 'helper-failure', true, true);
          this.#child = null;
          this.#lineBuffer = '';
          this.#recoveryPending = true;
          this.#settleProcessFailure(failure);
        }
      });
      return { child };
    } catch {
      const error = safeNativeHostFailure('PLAYER_HELPER_SPAWN_FAILED', 'helper-failure', true, true);
      this.#recoveryPending = true;
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
    this.#recoveryPending = true;
    const failure = safeNativeHostFailure('PLAYER_HELPER_STREAM_FAILED', 'helper-failure', true, true);
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
      const failure = safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true);
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
    const message = parseNativeHelperProcessMessage(line);
    if ('error' in message) {
      this.#quarantineChild(child, message.error);
      return;
    }
    if (message.message.type === 'event') {
      const requestId = readHelperEventRequestId(message.message.event);
      const pending = requestId === null ? undefined : this.#pending.get(requestId);
      if (pending?.kind === 'command') {
        pending.events.push(message.message.event);
        return;
      }
      this.#emitEvent(message.message.event);
      return;
    }
    if (message.message.type === 'presentation.result') {
      const pending = this.#pending.get(message.message.operationId);
      if (pending?.kind !== 'presentation' ||
        pending.requestId !== message.message.operationId ||
        pending.documentEpoch !== message.message.documentEpoch ||
        pending.revision !== message.message.revision) {
        this.#quarantineChild(child, safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true));
        return;
      }
      if (message.message.status === 'rejected') {
        this.#quarantineChild(child, safeNativeHostFailure('PLAYER_HELPER_PRESENTATION_REJECTED', 'helper-failure', true, true));
        return;
      }
      const expectedAppliedStatus = pending.mode === 'hidden' ? 'hidden' : 'applied';
      if (message.message.status !== expectedAppliedStatus && message.message.status !== 'stale') {
        this.#quarantineChild(child, safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true));
        return;
      }
      this.#resolvePresentationPending(message.message.operationId, {
        ok: true,
        status: message.message.status,
      });
      return;
    }
    const pending = this.#pending.get(message.message.requestId);
    if (pending === undefined) {
      this.#recordDiagnostic({
        category: 'validation',
        severity: 'warning',
        status: 'ignored',
        operation: 'helper.late-result',
        message: 'A late player helper result was ignored.',
        result: 'ignored',
        context: { count: 1 },
      });
      return;
    }
    if (message.message.type === 'audio-output.result') {
      if (pending.kind !== 'audio-output') {
        this.#quarantineChild(
          child,
          safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true),
        );
        return;
      }
      this.#resolveAudioPending(
        pending.requestId,
        message.message.ok
          ? { ok: true, outputs: message.message.outputs }
          : { ok: false, error: normalizeNativeHelperFailure(message.message.error) },
      );
      return;
    }
    if (pending.kind !== 'command') {
      this.#quarantineChild(
        child,
        safeNativeHostFailure('PLAYER_HELPER_MALFORMED_OUTPUT', 'helper-failure', true, true),
      );
      return;
    }
    if (message.message.ok) {
      const resultEvents =
        message.message.events === undefined
          ? pending.events
          : Array.isArray(message.message.events)
            ? [...pending.events, ...message.message.events]
            : message.message.events;
      this.#resolvePending(pending.requestId, {
        ok: true,
        events: resultEvents,
      });
      return;
    }
    this.#resolvePending(pending.requestId, {
      ok: false,
      error: normalizeNativeHelperFailure(message.message.error),
    });
  }
  #resolvePending(requestId: PlayerRequestId, result: NativePlayerHostCommandResult): void {
    const pending = this.#pending.get(requestId);
    if (pending === undefined || pending.kind !== 'command') {
      return;
    }
    this.#pending.delete(requestId);
    pending.resolve(result);
  }
  #resolveAudioPending(
    requestId: PlayerRequestId,
    result: NativePlayerHostAudioOutputResult,
  ): void {
    const pending = this.#pending.get(requestId);
    if (pending === undefined || pending.kind !== 'audio-output') {
      return;
    }
    this.#pending.delete(requestId);
    pending.resolve(result);
  }
  #resolvePresentationPending(
    operationId: PlayerRequestId,
    result: NativePlayerPresentationResult,
  ): void {
    const pending = this.#pending.get(operationId);
    if (pending === undefined || pending.kind !== 'presentation') return;
    this.#pending.delete(operationId);
    pending.resolve(result);
  }

  async #preparePlaybackBoundary(): Promise<NativePlayerHostCommandResult> {
    const active = this.#activePresentation;
    if (active !== null) {
      const settled = await active;
      if (!settled.ok) return { ok: false, error: settled.error };
      if (settled.status === 'stale') {
        this.#latestPresentation = null;
        return { ok: true };
      }
    }
    const current = this.#latestPresentation;
    if (current === null) return { ok: true };
    if (current.mode === 'hidden') {
      this.#latestPresentation = null;
      return { ok: true };
    }
    const update = this.#assignPresentationOperationId({
      ...current,
      loadedRequestId: current.loadedRequestId,
      mode: 'hidden',
      bounds: null,
    } as const);
    const serialized = JSON.stringify(toNativeHelperPresentationUpdate(update));
    const result = await this.#performPresentationUpdate(update, serialized);
    if (result.ok && (result.status === 'hidden' || result.status === 'stale')) {
      this.#latestPresentation = null;
      return { ok: true };
    }
    return {
      ok: false,
      error: result.ok
        ? safeNativeHostFailure('PLAYER_HELPER_PRESENTATION_REJECTED', 'helper-failure', true, true)
        : result.error,
    };
  }
  #assignPresentationOperationId(
    update: NativePlayerPresentationUpdate,
  ): SequencedNativePlayerPresentationUpdate {
    this.#presentationOperationSequence += 1n;
    return { ...update, operationId: `presentation-${this.#presentationOperationSequence}` };
  }
  #rejectAllPending(
    error: NativePlayerHostFailure,
    options: { recordAudioFailures: boolean } = { recordAudioFailures: true },
  ): void {
    for (const [requestId, pending] of [...this.#pending]) {
      clearTimeout(pending.timeout);
      const cleanupAborted = error.category === 'aborted';
      if (pending.kind === 'command' || pending.kind === 'presentation' || options.recordAudioFailures) {
        this.#recordFailure(requestId, error, {
          operation: cleanupAborted ? 'helper.cleanup' : error.category === 'timeout' ? 'helper.timeout' : 'helper.command',
          status: cleanupAborted ? 'cancelled' : error.code === 'PLAYER_HELPER_MALFORMED_OUTPUT' ? 'redacted' : 'failed',
        });
      }
      if (pending.kind === 'presentation') {
        pending.resolve({ ok: false, classification: 'shared-host-failure', error });
      } else {
        pending.resolve({ ok: false, error });
      }
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
    this.#recoveryPending = true;
    this.#settleProcessFailure(error);
    this.#reapChild(child).catch(() => this.#recordCleanupFailure(requestId));
  }
  #settleProcessFailure(error: NativePlayerHostFailure): void {
    const pendingRequests = [...this.#pending.values()];
    const hasPendingAudioQuery = pendingRequests.some((pending) => pending.kind === 'audio-output');
    const hasPendingPresentation = pendingRequests.some((pending) => pending.kind === 'presentation');
    if (pendingRequests.length > 0) {
      this.#rejectAllPending(error, { recordAudioFailures: !hasPendingAudioQuery });
    }
    if (pendingRequests.length === 0 || hasPendingAudioQuery || hasPendingPresentation) {
      this.#emitLifecycleFailure({ requestId: null, error });
    }
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
  #emitEvent(event: unknown): void {
    for (const listener of [...this.#eventListeners]) {
      try {
        listener(event);
      } catch {
        // Event delivery is best effort; one observer must not block the rest.
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

function readHelperEventRequestId(event: unknown): PlayerRequestId | null {
  if (
    typeof event !== 'object' ||
    event === null ||
    Array.isArray(event) ||
    !('requestId' in event)
  ) {
    return null;
  }
  return typeof event.requestId === 'string' && event.requestId.length > 0
    ? event.requestId
    : null;
}
function diagnosticCategoryForFailure(error: NativePlayerHostFailure): DiagnosticEventInput['category'] {
  return error.category === 'aborted' ? 'cleanup' : 'helper-crash';
}
