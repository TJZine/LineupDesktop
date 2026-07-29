import { clearImmediate, setImmediate } from 'node:timers';

import type { PlayerEvent } from '../../contracts/player.js';
import type { PlexPlaybackRuntime } from './plexPlaybackRuntime.js';

export interface PlaybackEventRouterSchedulePort {
  schedule(callback: () => void): unknown;
  cancel(handle: unknown): void;
}

export interface PlaybackEventRouterOptions {
  getRuntime(): PlexPlaybackRuntime | null;
  scheduler?: PlaybackEventRouterSchedulePort;
  reportDiagnostic?(message: string, error: unknown): void;
}

export interface PlaybackEventRouter {
  route(events: readonly PlayerEvent[]): void;
  flushCurrentRuntime(): void;
  dispose(): void;
}

interface QueuedPlaybackEvents {
  generation: number;
  runtime: PlexPlaybackRuntime;
  events: readonly PlayerEvent[];
}

export function createPlaybackEventRouter(
  options: PlaybackEventRouterOptions,
): PlaybackEventRouter {
  const scheduler = options.scheduler ?? createDefaultScheduler();
  const queue: QueuedPlaybackEvents[] = [];
  let scheduledHandle: unknown = null;
  let generation = 0;
  let disposed = false;

  function reportDrop(message: string): void {
    options.reportDiagnostic?.(message, new Error('Playback event batch dropped'));
  }

  function drain(): void {
    scheduledHandle = null;
    const pending = queue.splice(0);
    for (const entry of pending) {
      if (disposed || entry.generation !== generation) {
        continue;
      }
      if (options.getRuntime() !== entry.runtime) {
        reportDrop('Asynchronous player events targeted a replaced playback runtime');
        continue;
      }
      entry.runtime.ingestPlayerEvents(entry.events);
    }
  }

  function cancelScheduledDrain(): void {
    if (scheduledHandle !== null) {
      scheduler.cancel(scheduledHandle);
      scheduledHandle = null;
    }
  }

  return {
    route(events) {
      if (disposed) {
        reportDrop('Asynchronous player events arrived after router disposal');
        return;
      }
      const runtime = options.getRuntime();
      if (runtime === null) {
        reportDrop('Asynchronous player events arrived before playback runtime composition');
        return;
      }
      queue.push({
        generation,
        runtime,
        events: [...events],
      });
      if (scheduledHandle === null) {
        scheduledHandle = scheduler.schedule(drain);
      }
    },
    flushCurrentRuntime() {
      if (disposed) {
        return;
      }
      cancelScheduledDrain();
      drain();
    },
    dispose() {
      if (disposed) {
        return;
      }
      disposed = true;
      generation = generation >= Number.MAX_SAFE_INTEGER ? 1 : generation + 1;
      cancelScheduledDrain();
      queue.length = 0;
    },
  };
}

function createDefaultScheduler(): PlaybackEventRouterSchedulePort {
  return {
    schedule(callback) {
      return setImmediate(callback);
    },
    cancel(handle) {
      clearImmediate(handle as ReturnType<typeof setImmediate>);
    },
  };
}
