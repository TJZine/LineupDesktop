import { Worker } from 'node:worker_threads';

import type {
  ChannelBuilderPlannerInput,
  ChannelBuilderPlannerOutput,
} from '../../domain/channelBuilder/types.js';

export interface ChannelBuilderPlanningWorkerPort {
  on(event: 'message', listener: (message: unknown) => void): this;
  on(event: 'error', listener: () => void): this;
  on(event: 'exit', listener: () => void): this;
  postMessage(message: unknown): void;
  removeAllListeners(): this;
  terminate(): Promise<number>;
}

export type ChannelBuilderPlanningWorkerFactory = (
  url: URL,
) => ChannelBuilderPlanningWorkerPort;

export type ChannelBuilderPlanningWorkerOptions = Readonly<{
  createWorker?: ChannelBuilderPlanningWorkerFactory;
}>;

type PendingJob = {
  jobId: number;
  worker: ChannelBuilderPlanningWorkerPort;
  resolve(output: ChannelBuilderPlannerOutput): void;
  reject(error: Error): void;
  signal: AbortSignal;
  abort(): void;
};

export class ChannelBuilderPlanningWorker {
  private readonly createWorker: ChannelBuilderPlanningWorkerFactory;
  private worker: ChannelBuilderPlanningWorkerPort | null = null;
  private pending: PendingJob | null = null;
  private nextJobId = 1;
  private closed = false;

  constructor(options: ChannelBuilderPlanningWorkerOptions = {}) {
    this.createWorker =
      options.createWorker ??
      ((url) => new Worker(url));
  }

  plan(
    input: ChannelBuilderPlannerInput,
    signal: AbortSignal,
  ): Promise<ChannelBuilderPlannerOutput> {
    if (this.closed) return Promise.reject(planningFailure());
    if (this.pending !== null) return Promise.reject(planningBusy());
    if (!Number.isSafeInteger(this.nextJobId) || this.nextJobId < 1) {
      return Promise.reject(planningFailure());
    }
    if (signal.aborted) return Promise.reject(planningCanceled());
    const worker = this.worker ?? this.createAndBindWorker();
    const jobId = this.nextJobId;
    this.nextJobId += 1;
    return new Promise((resolve, reject) => {
      const abort = () => {
        if (this.pending?.jobId !== jobId) return;
        const detached = this.detachPending();
        this.detachWorker(worker);
        void worker.terminate();
        detached?.reject(planningCanceled());
      };
      this.pending = { jobId, worker, resolve, reject, signal, abort };
      signal.addEventListener('abort', abort, { once: true });
      worker.postMessage({ kind: 'plan', jobId, input });
    });
  }

  shutdown(): void {
    if (this.closed) return;
    this.closed = true;
    const pending = this.detachPending();
    const worker = this.worker;
    this.worker = null;
    pending?.reject(planningFailure());
    if (worker !== null) {
      worker.removeAllListeners();
      void worker.terminate();
    }
  }

  private createAndBindWorker(): ChannelBuilderPlanningWorkerPort {
    const worker = this.createWorker(
      new URL('./channelBuilderPlanningWorkerEntry.js', import.meta.url),
    );
    this.worker = worker;
    worker.on('message', (message: unknown) => {
      this.acceptMessage(worker, message);
    });
    worker.on('error', () => {
      this.failWorker(worker);
    });
    worker.on('exit', () => {
      this.failWorker(worker);
    });
    return worker;
  }

  private acceptMessage(worker: ChannelBuilderPlanningWorkerPort, message: unknown): void {
    const pending = this.pending;
    if (pending === null || pending.worker !== worker) return;
    if (!isPlainRecord(message) || !hasExactKeys(message, ['kind', 'jobId', ...(message.kind === 'planned' ? ['output'] : [])])) {
      this.failWorker(worker);
      return;
    }
    if (message.jobId !== pending.jobId) {
      this.failWorker(worker);
      return;
    }
    if (message.kind === 'failed') {
      const detached = this.detachPending();
      detached?.reject(planningFailure());
      return;
    }
    if (message.kind !== 'planned' || !isPlannerOutput(message.output)) {
      this.failWorker(worker);
      return;
    }
    const detached = this.detachPending();
    detached?.resolve(message.output);
  }

  private failWorker(worker: ChannelBuilderPlanningWorkerPort): void {
    if (this.worker !== worker) return;
    const pending = this.detachPending();
    this.detachWorker(worker);
    void worker.terminate();
    pending?.reject(planningFailure());
  }

  private detachPending(): PendingJob | null {
    const pending = this.pending;
    this.pending = null;
    pending?.signal.removeEventListener('abort', pending.abort);
    return pending;
  }

  private detachWorker(worker: ChannelBuilderPlanningWorkerPort): void {
    if (this.worker === worker) this.worker = null;
    worker.removeAllListeners();
  }
}

function isPlannerOutput(value: unknown): value is ChannelBuilderPlannerOutput {
  return (
    isPlainRecord(value) &&
    hasExactKeys(value, [
      'status',
      'planIdentity',
      'candidateDrafts',
      'applyCandidateIds',
      'retainedMaterializationCandidateIds',
      'candidateLedger',
      'existingLedger',
      'diff',
      'warnings',
      'reachedCap',
      'capacity',
    ]) &&
    (value.status === 'ready' || value.status === 'slow' || value.status === 'blocked') &&
    typeof value.planIdentity === 'string' &&
    /^plan-identity:[a-f0-9]{64}$/u.test(value.planIdentity) &&
    Array.isArray(value.candidateDrafts) &&
    Array.isArray(value.applyCandidateIds) &&
    Array.isArray(value.retainedMaterializationCandidateIds) &&
    Array.isArray(value.candidateLedger) &&
    Array.isArray(value.existingLedger) &&
    Array.isArray(value.warnings) &&
    typeof value.reachedCap === 'boolean' &&
    isPlainRecord(value.diff) &&
    isPlainRecord(value.capacity)
  );
}

function hasExactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function planningCanceled(): Error {
  return Object.assign(new Error('Channel Builder planning was canceled.'), {
    code: 'CHANNEL_PLANNING_CANCELED' as const,
  });
}

function planningBusy(): Error {
  return Object.assign(new Error('Channel Builder planning is busy.'), {
    code: 'CHANNEL_BUSY' as const,
  });
}

function planningFailure(): Error {
  return Object.assign(new Error('Channel Builder planning failed.'), {
    code: 'CHANNEL_UNKNOWN' as const,
  });
}
