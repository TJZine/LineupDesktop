import type {
  ScheduledProgram,
  SchedulerState,
} from '../../domain/scheduler/index.js';
import {
  isSamePlexPlaybackScheduleSelection,
  projectPlexPlaybackScheduleSelection,
  type PlexPlaybackRuntimeStartResult,
  type PlexPlaybackScheduleSelection,
} from './plexPlaybackRuntime.js';

export type PlaybackRecoveryTransitionResult =
  | { accepted: true }
  | {
      accepted: false;
      reason: 'busy' | 'stale' | 'unavailable';
    };

export interface PlaybackProgramTransitionRuntimePort {
  startCurrentPlayback(
    reason: 'schedule-tick',
  ): Promise<PlexPlaybackRuntimeStartResult>;
  retryCurrentPlayback(
    expectedSelection: PlexPlaybackScheduleSelection,
  ): Promise<boolean>;
}

export interface PlaybackProgramTransitionOwnerOptions {
  scheduler: {
    getState(): SchedulerState;
    getNextProgram(): ScheduledProgram;
    skipToNext(): void;
    on(
      event: 'programStart',
      handler: (program: ScheduledProgram) => void,
    ): void;
    off(
      event: 'programStart',
      handler: (program: ScheduledProgram) => void,
    ): void;
  };
  runtime: PlaybackProgramTransitionRuntimePort;
  reportDiagnostic?(message: string, error: unknown): void;
}

interface PendingTransition {
  action: 'retry-current' | 'skip-next';
  generation: number;
  initialIdentity: PlexPlaybackScheduleSelection;
  runtimeAttached: boolean;
  settle(result: PlaybackRecoveryTransitionResult): void;
}

export class PlaybackProgramTransitionOwner {
  readonly #scheduler: PlaybackProgramTransitionOwnerOptions['scheduler'];
  readonly #runtime: PlaybackProgramTransitionRuntimePort;
  readonly #reportDiagnostic?: PlaybackProgramTransitionOwnerOptions['reportDiagnostic'];
  readonly #programStartHandler: (program: ScheduledProgram) => void;
  #generation = 0;
  #pending: PendingTransition | null = null;
  #cleanupHoldCount = 0;
  #disposed = false;

  constructor(options: PlaybackProgramTransitionOwnerOptions) {
    this.#scheduler = options.scheduler;
    this.#runtime = options.runtime;
    this.#reportDiagnostic = options.reportDiagnostic;
    this.#programStartHandler = (program) => {
      this.#handleProgramStart(program);
    };
    this.#scheduler.on('programStart', this.#programStartHandler);
  }

  retryCurrent(): Promise<PlaybackRecoveryTransitionResult> {
    if (this.#disposed) {
      return Promise.resolve({ accepted: false, reason: 'unavailable' });
    }
    if (this.#cleanupHoldCount > 0) {
      return Promise.resolve({ accepted: false, reason: 'busy' });
    }
    if (this.#pending !== null) {
      return Promise.resolve({ accepted: false, reason: 'busy' });
    }
    const identity = this.#readCurrentIdentity();
    if (identity === null) {
      return Promise.resolve({ accepted: false, reason: 'unavailable' });
    }
    return new Promise((resolve) => {
      const pending: PendingTransition = {
        action: 'retry-current',
        generation: this.#generation,
        initialIdentity: identity,
        runtimeAttached: true,
        settle: resolve,
      };
      this.#pending = pending;
      void this.#runtime.retryCurrentPlayback(identity)
        .then((accepted) => {
          if (
            this.#pending !== pending ||
            pending.generation !== this.#generation
          ) {
            return;
          }
          this.#settlePending(
            accepted
              ? { accepted: true }
              : { accepted: false, reason: 'stale' },
          );
        })
        .catch(() => {
          if (this.#pending === pending) {
            this.#settlePending({ accepted: false, reason: 'unavailable' });
          }
        });
    });
  }

  skipNext(): Promise<PlaybackRecoveryTransitionResult> {
    if (this.#disposed) {
      return Promise.resolve({ accepted: false, reason: 'unavailable' });
    }
    if (this.#cleanupHoldCount > 0) {
      return Promise.resolve({ accepted: false, reason: 'busy' });
    }
    if (this.#pending !== null) {
      return Promise.resolve({ accepted: false, reason: 'busy' });
    }
    const identity = this.#readCurrentIdentity();
    if (identity === null || !this.#hasDifferentNextProgram(identity)) {
      return Promise.resolve({ accepted: false, reason: 'unavailable' });
    }
    return new Promise((resolve) => {
      const pending: PendingTransition = {
        action: 'skip-next',
        generation: nextGeneration(this.#generation),
        initialIdentity: identity,
        runtimeAttached: false,
        settle: resolve,
      };
      this.#pending = pending;
      try {
        this.#scheduler.skipToNext();
      } catch {
        this.#settlePending({ accepted: false, reason: 'unavailable' });
        return;
      }
      if (this.#pending === pending && !pending.runtimeAttached) {
        this.#settlePending({ accepted: false, reason: 'stale' });
      }
    });
  }

  invalidate(): void {
    this.#generation = nextGeneration(this.#generation);
    this.#settlePending({ accepted: false, reason: 'stale' });
  }

  acquireCleanupHold(): () => void {
    if (this.#disposed) {
      return () => undefined;
    }
    this.#cleanupHoldCount += 1;
    let released = false;
    return () => {
      if (released) {
        return;
      }
      released = true;
      this.#cleanupHoldCount -= 1;
    };
  }

  dispose(): void {
    if (this.#disposed) {
      return;
    }
    this.#disposed = true;
    this.#scheduler.off('programStart', this.#programStartHandler);
    this.invalidate();
  }

  #handleProgramStart(program: ScheduledProgram): void {
    if (this.#disposed) {
      return;
    }
    this.#generation = nextGeneration(this.#generation);
    if (this.#cleanupHoldCount > 0) {
      this.#settlePending({ accepted: false, reason: 'stale' });
      this.#reportDiagnostic?.(
        'Scheduler playback transition was dropped during cleanup',
        new Error('Playback transition unavailable during cleanup'),
      );
      return;
    }
    const currentIdentity = this.#readCurrentIdentity();
    const eventIdentity = this.#identityFromProgram(
      this.#safeGetState(),
      program,
    );
    const authoritative =
      currentIdentity !== null &&
      eventIdentity !== null &&
      isSamePlexPlaybackScheduleSelection(currentIdentity, eventIdentity);
    const pending = this.#pending;

    if (
      pending?.action === 'skip-next' &&
      pending.generation === this.#generation &&
      authoritative &&
      !isSamePlexPlaybackScheduleSelection(
        pending.initialIdentity,
        currentIdentity,
      )
    ) {
      pending.runtimeAttached = true;
      void this.#startForProgramEvent()
        .then((accepted) => {
          if (this.#pending !== pending) {
            return;
          }
          this.#settlePending(
            accepted
              ? { accepted: true }
              : { accepted: false, reason: 'unavailable' },
          );
        });
      return;
    }

    if (pending !== null) {
      this.#settlePending({ accepted: false, reason: 'stale' });
    }
    if (!authoritative) {
      this.#reportDiagnostic?.(
        'Scheduler program transition did not match authoritative state',
        new Error('Program transition rejected'),
      );
      return;
    }
    void this.#startForProgramEvent().then((accepted) => {
      if (!accepted) {
        this.#reportDiagnostic?.(
          'Scheduler playback transition failed',
          new Error('Playback transition was not accepted'),
        );
      }
    });
  }

  async #startForProgramEvent(): Promise<boolean> {
    try {
      const result = await this.#runtime.startCurrentPlayback('schedule-tick');
      return result.accepted;
    } catch {
      return false;
    }
  }

  #settlePending(result: PlaybackRecoveryTransitionResult): void {
    const pending = this.#pending;
    if (pending === null) {
      return;
    }
    this.#pending = null;
    pending.settle(result);
  }

  #hasDifferentNextProgram(identity: PlexPlaybackScheduleSelection): boolean {
    try {
      const state = this.#safeGetState();
      const next = this.#scheduler.getNextProgram();
      const nextIdentity = this.#identityFromProgram(state, next);
      return (
        nextIdentity !== null &&
        !isSamePlexPlaybackScheduleSelection(identity, nextIdentity)
      );
    } catch {
      return false;
    }
  }

  #readCurrentIdentity(): PlexPlaybackScheduleSelection | null {
    const state = this.#safeGetState();
    if (
      state === null ||
      !state.isActive ||
      state.currentProgram === null
    ) {
      return null;
    }
    return this.#identityFromProgram(state, state.currentProgram);
  }

  #safeGetState(): SchedulerState | null {
    try {
      return this.#scheduler.getState();
    } catch {
      return null;
    }
  }

  #identityFromProgram(
    state: SchedulerState | null,
    program: ScheduledProgram,
  ): PlexPlaybackScheduleSelection | null {
    if (
      state === null ||
      !state.isActive ||
      state.channelId.trim() === '' ||
      program.item.ratingKey.trim() === '' ||
      !Number.isFinite(program.scheduledStartTime) ||
      !Number.isFinite(program.scheduledEndTime)
    ) {
      return null;
    }
    return projectPlexPlaybackScheduleSelection({
      channelId: state.channelId,
      ratingKey: program.item.ratingKey,
      scheduledStartTime: program.scheduledStartTime,
      scheduledEndTime: program.scheduledEndTime,
    });
  }
}

function nextGeneration(current: number): number {
  return current >= Number.MAX_SAFE_INTEGER ? 1 : current + 1;
}
