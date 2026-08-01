import type { PlayerSnapshot } from '../contracts/player.js';
import type {
  DeferredPauseResult,
  PauseCurrentResult,
} from './playerInputCommandController.js';

export type SleepTimerPresetMinutes = 15 | 30 | 60 | 120;

export type SleepTimerStatus = 'off' | 'active' | 'warning' | 'expiring' | 'expired' | 'failed';

export interface SleepTimerProjection {
  presetMinutes: SleepTimerPresetMinutes | null;
  remainingMs: number;
  status: SleepTimerStatus;
  message: string;
}

export interface SleepTimerHost {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(handle: number): void;
}

export interface SleepTimerControllerOptions {
  host: SleepTimerHost;
  now(): number;
  getProjection(): SleepTimerProjection;
  setProjection(projection: SleepTimerProjection): void;
  render(): void;
  getCurrentPlayback(): Pick<PlayerSnapshot, 'requestId' | 'status' | 'playing'>;
  pauseCurrent(
    snapshotRequestId: string,
    onDeferredResolved?: (result: DeferredPauseResult) => void,
  ): PauseCurrentResult;
  cancelDeferredPause(): void;
  recordDiagnostic(operation: string, message: string): void;
}

export interface SleepTimerController {
  cyclePreset(): SleepTimerPresetMinutes | null;
  cancel(): void;
  cleanup(): void;
}

export const SLEEP_TIMER_PRESETS: readonly SleepTimerPresetMinutes[] = [15, 30, 60, 120];
export const SLEEP_TIMER_WARNING_MS = 60_000;

const TICK_MS = 1_000;

export function createSleepTimerProjection(): SleepTimerProjection {
  return {
    presetMinutes: null,
    remainingMs: 0,
    status: 'off',
    message: 'Sleep timer off',
  };
}

export function createSleepTimerController(
  options: SleepTimerControllerOptions,
): SleepTimerController {
  let timer: number | null = null;
  let deadlineMs: number | null = null;
  let lastRemainingMs = 0;
  let warningIssued = false;
  let generation = 0;
  let disposed = false;

  const clearTimer = (): void => {
    if (timer !== null) {
      options.host.clearTimeout(timer);
      timer = null;
    }
  };

  const publish = (projection: SleepTimerProjection): void => {
    if (disposed) return;
    options.setProjection(projection);
    options.render();
  };

  // Never increase the visible countdown if the host clock moves backward.
  const remainingAt = (nowMs: number): number => {
    if (deadlineMs === null) return 0;
    return Math.min(lastRemainingMs, Math.max(0, deadlineMs - nowMs));
  };

  const schedule = (activeGeneration: number): void => {
    clearTimer();
    if (deadlineMs === null || disposed) return;
    timer = options.host.setTimeout(() => {
      timer = null;
      tick(activeGeneration);
    }, Math.min(TICK_MS, Math.max(1, lastRemainingMs)));
  };

  const expire = (activeGeneration: number): void => {
    if (disposed || activeGeneration !== generation) return;
    clearTimer();
    deadlineMs = null;
    lastRemainingMs = 0;
    const playback = options.getCurrentPlayback();
    if (
      playback.requestId !== null &&
      playback.status === 'playing' &&
      playback.playing
    ) {
      const onDeferredResolved = (result: DeferredPauseResult): void => {
        if (disposed || activeGeneration !== generation) return;
        if (result === 'started') {
          publish({
            presetMinutes: null,
            remainingMs: 0,
            status: 'expired',
            message: 'Sleep timer ended',
          });
          return;
        }
        publish({
          presetMinutes: null,
          remainingMs: 0,
          status: 'failed',
          message: 'Sleep timer ended; playback could not be paused',
        });
        options.recordDiagnostic('player.sleep-timer', 'Sleep timer pause was not accepted.');
      };
      const pauseResult = options.pauseCurrent(playback.requestId, onDeferredResolved);
      if (pauseResult === 'started') {
        onDeferredResolved('started');
      } else if (pauseResult === 'deferred') {
        publish({
          presetMinutes: null,
          remainingMs: 0,
          status: 'expiring',
          message: 'Sleep timer ended; pause pending',
        });
      } else {
        onDeferredResolved('rejected');
      }
      return;
    }
    publish({
      presetMinutes: null,
      remainingMs: 0,
      status: 'expired',
      message: 'Sleep timer ended',
    });
  };

  const tick = (activeGeneration: number): void => {
    if (disposed || activeGeneration !== generation || deadlineMs === null) return;
    const remainingMs = remainingAt(options.now());
    lastRemainingMs = remainingMs;
    if (remainingMs <= 0) {
      expire(activeGeneration);
      return;
    }
    if (!warningIssued && remainingMs <= SLEEP_TIMER_WARNING_MS) {
      warningIssued = true;
    }
    publish({
      ...options.getProjection(),
      remainingMs,
      status: warningIssued ? 'warning' : 'active',
      message: warningIssued ? 'Sleep timer ends in under 1 minute' : 'Sleep timer active',
    });
    schedule(activeGeneration);
  };

  const cancel = (): void => {
    ++generation;
    options.cancelDeferredPause();
    clearTimer();
    deadlineMs = null;
    lastRemainingMs = 0;
    warningIssued = false;
    publish(createSleepTimerProjection());
  };

  const cyclePreset = (): SleepTimerPresetMinutes | null => {
    if (disposed) return null;
    const current = options.getProjection().presetMinutes;
    const currentIndex = current === null ? -1 : SLEEP_TIMER_PRESETS.indexOf(current);
    const next = SLEEP_TIMER_PRESETS[currentIndex + 1] ?? null;
    if (next === null) {
      cancel();
      return null;
    }

    const activeGeneration = ++generation;
    options.cancelDeferredPause();
    clearTimer();
    warningIssued = false;
    lastRemainingMs = next * 60_000;
    deadlineMs = options.now() + lastRemainingMs;
    publish({
      presetMinutes: next,
      remainingMs: lastRemainingMs,
      status: 'active',
      message: `Sleep timer set for ${String(next)} minutes`,
    });
    schedule(activeGeneration);
    return next;
  };

  return {
    cyclePreset,
    cancel,
    cleanup() {
      if (disposed) return;
      ++generation;
      options.cancelDeferredPause();
      clearTimer();
      deadlineMs = null;
      lastRemainingMs = 0;
      warningIssued = false;
      options.setProjection(createSleepTimerProjection());
      disposed = true;
    },
  };
}
