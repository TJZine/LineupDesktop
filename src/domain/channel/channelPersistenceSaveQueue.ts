import type {
  ChannelClock,
  ChannelLogger,
  ChannelTimerHandle,
  ChannelTimerPort,
} from './interfaces.js';
import type { ChannelManagerEventMap } from './types.js';

export interface ChannelPersistenceSaveQueueConfig {
  runSave: () => Promise<void>;
  createDisposedError: () => Error;
  emitPersistenceWarning: (payload: ChannelManagerEventMap['persistenceWarning']) => void;
  logger?: ChannelLogger;
  clock: ChannelClock;
  timers: ChannelTimerPort;
  debounceMs: number;
}

export class ChannelPersistenceSaveQueue {
  private runSave: () => Promise<void>;
  private readonly createDisposedError: () => Error;
  private readonly emitPersistenceWarning: (payload: ChannelManagerEventMap['persistenceWarning']) => void;
  private readonly logger?: ChannelLogger;
  private readonly clock: ChannelClock;
  private readonly timers: ChannelTimerPort;
  private readonly debounceMs: number;

  private saveTimer: ChannelTimerHandle | null = null;
  private pendingSavePromise: Promise<void> | null = null;
  private pendingSaveResolve: (() => void) | null = null;
  private pendingSaveReject: ((error: unknown) => void) | null = null;
  private queuedSaveCatchPromise: Promise<void> | null = null;
  private writeChain: Promise<void> = Promise.resolve();
  private latestWritePromise: Promise<void> | null = null;
  private readonly activeSaveRejects = new Set<(error: unknown) => void>();
  private isDisposed = false;

  public constructor(config: ChannelPersistenceSaveQueueConfig) {
    this.runSave = config.runSave;
    this.createDisposedError = config.createDisposedError;
    this.emitPersistenceWarning = config.emitPersistenceWarning;
    this.logger = config.logger;
    this.clock = config.clock;
    this.timers = config.timers;
    this.debounceMs = config.debounceMs;
  }

  public save(): Promise<void> {
    if (this.isDisposed) {
      return Promise.reject(this.createDisposedError());
    }

    const pendingSave = this.ensurePendingSavePromise();
    if (this.saveTimer !== null) {
      this.timers.clearTimeout(this.saveTimer);
    }

    this.saveTimer = this.timers.setTimeout(() => {
      this.saveTimer = null;
      void this.runPendingSaveNow().catch(() => {
        // The pending save promise is rejected by runPendingSaveNow and handled by callers.
      });
    }, this.debounceMs);

    return pendingSave;
  }

  public saveWithSnapshot(runSave: () => Promise<void>): Promise<void> {
    this.runSave = runSave;
    return this.save();
  }

  public queue(): void {
    if (this.isDisposed) {
      this.reportFailure('Debounced save failed', this.createDisposedError());
      return;
    }

    const pendingSave = this.save();
    if (this.queuedSaveCatchPromise === pendingSave) {
      return;
    }
    this.queuedSaveCatchPromise = pendingSave;
    void pendingSave.catch((error) => {
      this.reportFailure('Debounced save failed', error);
    });
  }

  public queueWithSnapshot(runSave: () => Promise<void>): void {
    this.runSave = runSave;
    this.queue();
  }

  public async flush(): Promise<void> {
    if (this.isDisposed) {
      return;
    }
    if (this.saveTimer === null) {
      await this.latestWritePromise;
      return;
    }

    this.timers.clearTimeout(this.saveTimer);
    this.saveTimer = null;
    await this.runPendingSaveNow();
  }

  public flushWithSnapshot(runSave: () => Promise<void>): Promise<void> {
    this.runSave = runSave;
    if (this.isDisposed) {
      return Promise.reject(this.createDisposedError());
    }
    if (this.saveTimer === null) {
      return this.enqueueSerializedWrite(this.runSave);
    }
    return this.flush();
  }

  public supersedePendingSave(): void {
    if (this.isDisposed || this.saveTimer === null) {
      return;
    }

    this.timers.clearTimeout(this.saveTimer);
    this.saveTimer = null;
    this.resolvePendingSave();
  }

  public dispose(): void {
    this.isDisposed = true;
    if (this.saveTimer !== null) {
      this.timers.clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
    for (const reject of this.activeSaveRejects) {
      reject(this.createDisposedError());
    }
    this.activeSaveRejects.clear();
    this.rejectPendingSave(this.createDisposedError());
  }

  public reportFailure(message: string, error: unknown): void {
    this.emitPersistenceWarning({
      message: 'Failed to persist channels; some changes may not be saved',
      code: getErrorCode(error) ?? 'UNKNOWN',
      isQuotaError: false,
      timestamp: this.clock.now(),
    });
    this.logger?.error(message, summarizeError(error));
  }

  private ensurePendingSavePromise(): Promise<void> {
    if (this.pendingSavePromise) {
      return this.pendingSavePromise;
    }
    this.pendingSavePromise = new Promise((resolve, reject) => {
      this.pendingSaveResolve = resolve;
      this.pendingSaveReject = reject;
    });
    return this.pendingSavePromise;
  }

  private clearPendingSavePromise(): void {
    this.pendingSavePromise = null;
    this.pendingSaveResolve = null;
    this.pendingSaveReject = null;
    this.queuedSaveCatchPromise = null;
  }

  private resolvePendingSave(): void {
    const resolve = this.pendingSaveResolve;
    this.clearPendingSavePromise();
    resolve?.();
  }

  private rejectPendingSave(error: unknown): void {
    const reject = this.pendingSaveReject;
    this.clearPendingSavePromise();
    reject?.(error);
  }

  private async runPendingSaveNow(): Promise<void> {
    const runSave = this.runSave;
    const resolve = this.pendingSaveResolve;
    const reject = this.pendingSaveReject;
    this.clearPendingSavePromise();
    if (reject) {
      this.activeSaveRejects.add(reject);
    }

    try {
      await this.enqueueSerializedWrite(runSave);
      resolve?.();
    } catch (error) {
      reject?.(error);
      throw error;
    } finally {
      if (reject) {
        this.activeSaveRejects.delete(reject);
      }
    }
  }

  private enqueueSerializedWrite(runSave: () => Promise<void>): Promise<void> {
    const write = this.writeChain.then(runSave, runSave);
    this.latestWritePromise = write;
    void write.then(
      () => {
        if (this.latestWritePromise === write) {
          this.latestWritePromise = null;
        }
      },
      () => {
        if (this.latestWritePromise === write) {
          this.latestWritePromise = null;
        }
      },
    );
    this.writeChain = write.catch(() => undefined);
    return write;
  }
}

function getErrorCode(error: unknown): string | null {
  if (error && typeof error === 'object' && 'code' in error && typeof error.code === 'string') {
    return error.code;
  }
  return null;
}

function summarizeError(error: unknown): { name?: string; message: string; code?: string } {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      code: getErrorCode(error) ?? undefined,
    };
  }
  return { message: String(error) };
}
