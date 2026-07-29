import type { PlayerEvent } from '../../contracts/player.js';

export interface PlexPlaybackRecoveryIdentity {
  channelId: string;
  programId: string;
  startedAtMs: number;
}

export type PlexPlaybackRecoveryAttemptResult = 'started' | 'failed' | 'stale';

export interface PlexPlaybackRecoveryTimerPort {
  set(delayMs: number, callback: () => void): unknown;
  clear(handle: unknown): void;
}

export interface PlexPlaybackRecoveryOwnerOptions {
  timer: PlexPlaybackRecoveryTimerPort;
  retry(
    identity: PlexPlaybackRecoveryIdentity,
  ): Promise<PlexPlaybackRecoveryAttemptResult>;
}

const RETRY_DELAYS_MS = [1_000, 2_000, 4_000] as const;

export class PlexPlaybackRecoveryOwner {
  readonly #timer: PlexPlaybackRecoveryTimerPort;
  readonly #retry: PlexPlaybackRecoveryOwnerOptions['retry'];
  #identity: PlexPlaybackRecoveryIdentity | null = null;
  #attemptCount = 0;
  #generation = 0;
  #timerHandle: unknown = null;
  #attemptGeneration: number | null = null;
  #eligibleErrorLatched = false;
  #successfulAttemptGeneration: number | null = null;

  constructor(options: PlexPlaybackRecoveryOwnerOptions) {
    this.#timer = options.timer;
    this.#retry = options.retry;
  }

  activate(identity: PlexPlaybackRecoveryIdentity): void {
    if (sameIdentity(this.#identity, identity)) {
      return;
    }
    this.#invalidate();
    this.#identity = { ...identity };
    this.#attemptCount = 0;
  }

  observeAcceptedEvent(identity: PlexPlaybackRecoveryIdentity, event: PlayerEvent): void {
    if (!sameIdentity(this.#identity, identity)) {
      return;
    }
    if (isAuthoritativePlayingEvent(event)) {
      this.#attemptCount = 0;
      this.#cancelTimer();
      this.#eligibleErrorLatched = false;
      if (this.#attemptGeneration === this.#generation) {
        this.#successfulAttemptGeneration = this.#generation;
      }
      return;
    }
    if (isEligibleRecoveryError(event)) {
      if (this.#attemptGeneration === this.#generation) {
        this.#eligibleErrorLatched = true;
        return;
      }
      this.#scheduleNextAttempt();
    }
  }

  cancel(): void {
    this.#invalidate();
    this.#identity = null;
    this.#attemptCount = 0;
  }

  getAttemptCount(): number {
    return this.#attemptCount;
  }

  #scheduleNextAttempt(): void {
    if (
      this.#identity === null ||
      this.#timerHandle !== null ||
      this.#attemptGeneration === this.#generation ||
      this.#attemptCount >= RETRY_DELAYS_MS.length
    ) {
      return;
    }
    const generation = this.#generation;
    const delayMs = RETRY_DELAYS_MS[this.#attemptCount];
    this.#timerHandle = this.#timer.set(delayMs, () => {
      this.#timerHandle = null;
      void this.#runAttempt(generation);
    });
  }

  async #runAttempt(generation: number): Promise<void> {
    if (generation !== this.#generation || this.#identity === null) {
      return;
    }
    const identity = { ...this.#identity };
    this.#attemptGeneration = generation;
    this.#eligibleErrorLatched = false;
    this.#successfulAttemptGeneration = null;
    this.#attemptCount += 1;
    let result: PlexPlaybackRecoveryAttemptResult;
    try {
      result = await this.#retry(identity);
    } catch {
      result = 'failed';
    }
    if (
      generation !== this.#generation ||
      !sameIdentity(this.#identity, identity)
    ) {
      return;
    }
    const observedFailure = this.#eligibleErrorLatched;
    const observedSuccess = this.#successfulAttemptGeneration === generation;
    if (this.#attemptGeneration === generation) {
      this.#attemptGeneration = null;
    }
    this.#eligibleErrorLatched = false;
    this.#successfulAttemptGeneration = null;
    if (observedSuccess) {
      return;
    }
    if (result === 'stale') {
      this.cancel();
      return;
    }
    if (result === 'failed' || observedFailure) {
      this.#scheduleNextAttempt();
    }
  }

  #invalidate(): void {
    this.#generation = this.#generation >= Number.MAX_SAFE_INTEGER ? 1 : this.#generation + 1;
    this.#cancelTimer();
    this.#attemptGeneration = null;
    this.#eligibleErrorLatched = false;
    this.#successfulAttemptGeneration = null;
  }

  #cancelTimer(): void {
    if (this.#timerHandle !== null) {
      this.#timer.clear(this.#timerHandle);
      this.#timerHandle = null;
    }
  }
}

function sameIdentity(
  left: PlexPlaybackRecoveryIdentity | null,
  right: PlexPlaybackRecoveryIdentity,
): boolean {
  return (
    left !== null &&
    left.channelId === right.channelId &&
    left.programId === right.programId &&
    left.startedAtMs === right.startedAtMs
  );
}

function isAuthoritativePlayingEvent(event: PlayerEvent): boolean {
  return (
    event.event === 'state.changed' &&
    event.snapshot.status === 'playing' &&
    event.snapshot.playing
  );
}

function isEligibleRecoveryError(event: PlayerEvent): boolean {
  return (
    event.event === 'error' &&
    event.error.code === 'PLAYER_HOST_ENGINE_FAILURE' &&
    event.error.category === 'engine-failure' &&
    event.error.recoverable &&
    event.error.retryable
  );
}
