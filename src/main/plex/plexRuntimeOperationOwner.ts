import type { PlexIpcResult, PlexRuntimeError, PlexRuntimeOperation, PlexRuntimeSnapshot } from '../../contracts/plex.js';
import {
  mapRuntimeError,
  normalizeOperationKey,
  staleError,
  StaleRuntimeMutationError,
  success,
} from './desktopPlexRuntimeSupport.js';

export type PlexRuntimeSnapshotCommit = (
  update: (snapshot: PlexRuntimeSnapshot) => PlexRuntimeSnapshot,
) => void;

export interface PlexRuntimeOperationContext {
  signal: AbortSignal;
  commit: PlexRuntimeSnapshotCommit;
}

export interface PlexRuntimeOperationOwnerOptions {
  commitSnapshot: PlexRuntimeSnapshotCommit;
  fail<T>(
    requestId: string,
    error: PlexRuntimeError,
    options?: { cancelled?: boolean; stale?: boolean; mutateSnapshot?: boolean },
  ): PlexIpcResult<T>;
  recordDiagnostic(
    operation: PlexRuntimeOperation,
    status: 'started' | 'succeeded' | 'failed' | 'cancelled',
    code?: string,
  ): void;
}

export class PlexRuntimeOperationOwner {
  readonly #activeOperations = new Map<string, AbortController>();
  readonly #commitSnapshot: PlexRuntimeOperationOwnerOptions['commitSnapshot'];
  readonly #fail: PlexRuntimeOperationOwnerOptions['fail'];
  readonly #recordDiagnostic: PlexRuntimeOperationOwnerOptions['recordDiagnostic'];
  #runtimeEpoch = 0;

  constructor(options: PlexRuntimeOperationOwnerOptions) {
    this.#commitSnapshot = options.commitSnapshot;
    this.#fail = options.fail;
    this.#recordDiagnostic = options.recordDiagnostic;
  }

  abort(operationKey: string): void {
    const controller = this.#activeOperations.get(operationKey);
    if (!controller) {
      return;
    }
    this.#activeOperations.delete(operationKey);
    controller.abort();
  }

  abortExcept(operationKey: string): void {
    for (const [activeOperationKey, controller] of this.#activeOperations.entries()) {
      if (activeOperationKey === operationKey) {
        continue;
      }
      this.#activeOperations.delete(activeOperationKey);
      controller.abort();
    }
  }

  shutdown(): void {
    this.#runtimeEpoch += 1;
    for (const controller of this.#activeOperations.values()) {
      controller.abort();
    }
    this.#activeOperations.clear();
  }

  async run<T>(
    requestId: string,
    operationKey: string,
    action: (context: PlexRuntimeOperationContext) => Promise<T>,
  ): Promise<PlexIpcResult<T>> {
    const operation = normalizeOperationKey(operationKey);
    this.abort(operationKey);
    const controller = new AbortController();
    const epoch = this.#runtimeEpoch;
    this.#activeOperations.set(operationKey, controller);
    this.#recordDiagnostic(operation, 'started');
    const isCurrent = () =>
      this.#runtimeEpoch === epoch && this.#activeOperations.get(operationKey) === controller;
    const commit: PlexRuntimeSnapshotCommit = (update) => {
      if (!isCurrent()) {
        throw new StaleRuntimeMutationError();
      }
      this.#commitSnapshot(update);
    };
    try {
      const value = await action({ signal: controller.signal, commit });
      if (!isCurrent()) {
        const runtimeError = staleError(operation);
        this.#recordDiagnostic(operation, 'failed', runtimeError.code);
        return this.#fail(requestId, runtimeError, { stale: true, mutateSnapshot: false });
      }
      this.#recordDiagnostic(operation, 'succeeded');
      return success(requestId, value);
    } catch (error) {
      const runtimeError = error instanceof StaleRuntimeMutationError
        ? staleError(operation)
        : mapRuntimeError(error, operation);
      const cancelled = runtimeError.code === 'PLEX_CANCELLED';
      const stale =
        !cancelled &&
        (error instanceof StaleRuntimeMutationError || this.#runtimeEpoch !== epoch || !isCurrent());
      this.#recordDiagnostic(operation, cancelled ? 'cancelled' : 'failed', runtimeError.code);
      return this.#fail(requestId, runtimeError, {
        cancelled,
        stale,
        mutateSnapshot: !stale && !cancelled,
      });
    } finally {
      if (this.#activeOperations.get(operationKey) === controller) {
        this.#activeOperations.delete(operationKey);
      }
    }
  }
}
