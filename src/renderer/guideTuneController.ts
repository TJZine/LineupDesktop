import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import { isEpgProgramPlayable, type EpgProgramCellViewModel } from './epg.js';
import { summarizeRendererBridgeError } from './rendererBridgeFailures.js';

export interface GuideTuneTarget {
  channelId: string;
  programId: string;
  focusId: string;
  presentationGeneration: number;
}

export interface GuideTuneControllerOptions {
  player: Pick<LineupDesktopPreloadApi['player'], 'tuneChannel'>;
  getActiveRoute(): AppRouteId;
  getPresentationGeneration(): number;
  getNowMs(): number;
  findProgram(channelId: string, programId: string): EpgProgramCellViewModel | null;
  onPendingChanged(target: GuideTuneTarget | null): void;
  onAccepted(target: GuideTuneTarget): void;
  onFailure(target: GuideTuneTarget, message: string): void;
}

export interface GuideTuneController {
  activate(target: GuideTuneTarget): Promise<boolean>;
  isPending(): boolean;
  getPendingTarget(): GuideTuneTarget | null;
  stop(): void;
}

export function createGuideTuneController(options: GuideTuneControllerOptions): GuideTuneController {
  let requestGeneration = 0;
  let pendingTarget: GuideTuneTarget | null = null;

  const notifyPending = (target: GuideTuneTarget | null): void => {
    try {
      options.onPendingChanged(target);
    } catch {
      // Rendering callbacks must not strand the controller's lifecycle state.
    }
  };

  const stop = (): void => {
    requestGeneration += 1;
    pendingTarget = null;
    notifyPending(null);
  };

  return {
    async activate(target): Promise<boolean> {
      if (pendingTarget !== null || options.getActiveRoute() !== 'guide') return false;
      if (target.presentationGeneration !== options.getPresentationGeneration()) return false;
      const current = options.findProgram(target.channelId, target.programId);
      if (
        current === null
        || current.focusId !== target.focusId
        || current.presentationGeneration !== target.presentationGeneration
        || !isEpgProgramPlayable(current, options.getNowMs())
      ) {
        return false;
      }

      const generation = ++requestGeneration;
      pendingTarget = target;
      notifyPending(target);
      let result: Awaited<ReturnType<typeof options.player.tuneChannel>>;
      try {
        result = await options.player.tuneChannel({ channelId: target.channelId });
      } catch (error: unknown) {
        if (isCurrent(generation, target)) {
          pendingTarget = null;
          notifyPending(null);
          try {
            options.onFailure(target, summarizeRendererBridgeError(error));
          } catch {
            // The bridge request is settled even if a UI callback fails.
          }
        } else {
          clearStalePending(generation, target);
        }
        return true;
      }

      if (!isCurrent(generation, target)) {
        clearStalePending(generation, target);
        return true;
      }
      pendingTarget = null;
      notifyPending(null);
      try {
        if (result.ok) options.onAccepted(target);
        else options.onFailure(target, result.error.message);
      } catch {
        // Completion callbacks are renderer-local and may safely fail closed.
      }
      return true;
    },
    isPending: () => pendingTarget !== null,
    getPendingTarget: () => pendingTarget === null ? null : { ...pendingTarget },
    stop,
  };

  function isCurrent(generation: number, target: GuideTuneTarget): boolean {
    return generation === requestGeneration
      && pendingTarget?.focusId === target.focusId
      && options.getActiveRoute() === 'guide';
  }

  function clearStalePending(generation: number, target: GuideTuneTarget): void {
    if (generation !== requestGeneration || pendingTarget?.focusId !== target.focusId) return;
    pendingTarget = null;
    notifyPending(null);
  }
}
