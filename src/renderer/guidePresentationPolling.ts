import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import {
  EPG_SLOT_DURATION_MS,
  EPG_WINDOW_DURATION_MS,
  ensureRendererReadyGuidePresentation,
} from './epg.js';
import { summarizeRendererBridgeError } from './rendererBridgeFailures.js';

const GUIDE_POLL_INTERVAL_MS = 15_000;

export interface GuidePresentationPollingOptions {
  guide: LineupDesktopPreloadApi['guide'];
  host: Window;
  getActiveRoute(): AppRouteId;
  getWindowStartMs(): number;
  getNowMs?(): number;
  setLoading(generation: number): void;
  applyPresentation(
    presentation: ReturnType<typeof ensureRendererReadyGuidePresentation>,
    generation: number,
  ): void;
  handleFailure(source: string, message: string, generation: number): void;
  applyPlayerPresentation?(
    presentation: ReturnType<typeof ensureRendererReadyGuidePresentation>,
    generation: number,
  ): void;
  handlePlayerFailure?(source: string, message: string, generation: number): void;
}

export interface GuidePresentationPollingController {
  reconcile(previousRoute: AppRouteId, nextRoute: AppRouteId): void;
  start(): void;
  stop(): void;
  refresh(source: string, options?: GuidePresentationRefreshOptions): Promise<void>;
  getGeneration(): number;
  getLastValidPresentation(): ReturnType<typeof ensureRendererReadyGuidePresentation> | null;
}

export interface GuidePresentationRefreshOptions {
  showLoading?: boolean;
  allowPlayerRoute?: boolean;
}

export function createGuidePresentationPolling(
  options: GuidePresentationPollingOptions,
): GuidePresentationPollingController {
  let guidePollTimer: number | null = null;
  let guidePresentationRequestId = 0;
  let lastValidPresentation: ReturnType<typeof ensureRendererReadyGuidePresentation> | null = null;

  const stop = (): void => {
    if (guidePollTimer !== null) {
      options.host.clearInterval(guidePollTimer);
      guidePollTimer = null;
    }
    guidePresentationRequestId += 1;
  };

  const refresh = async (
    source: string,
    refreshOptions: GuidePresentationRefreshOptions = {},
  ): Promise<void> => {
    const requestId = ++guidePresentationRequestId;
    const playerRefresh = options.getActiveRoute() === 'player' && refreshOptions.allowPlayerRoute === true;
    if (options.getActiveRoute() !== 'guide' && !playerRefresh) {
      return;
    }
    const windowStartMs = playerRefresh
      ? Math.floor((options.getNowMs?.() ?? Date.now()) / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS
      : options.getWindowStartMs();
    if (refreshOptions.showLoading === true) {
      options.setLoading(requestId);
    }

    let result: Awaited<ReturnType<typeof options.guide.getPresentation>>;
    try {
      result = await options.guide.getPresentation({
        startTimeMs: windowStartMs,
        durationMs: EPG_WINDOW_DURATION_MS,
      });
    } catch (error: unknown) {
      if (requestId === guidePresentationRequestId) {
        if (playerRefresh) options.handlePlayerFailure?.(source, summarizeRendererBridgeError(error), requestId);
        else if (options.getActiveRoute() === 'guide') options.handleFailure(source, summarizeRendererBridgeError(error), requestId);
      }
      return;
    }

    if (requestId !== guidePresentationRequestId || (!playerRefresh && options.getActiveRoute() !== 'guide')) {
      return;
    }
    if (!result.ok) {
      if (playerRefresh) options.handlePlayerFailure?.(source, result.error.message, requestId);
      else options.handleFailure(source, result.error.message, requestId);
      return;
    }
    lastValidPresentation = ensureRendererReadyGuidePresentation(result.value, windowStartMs);
    if (playerRefresh) options.applyPlayerPresentation?.(lastValidPresentation, requestId);
    else options.applyPresentation(lastValidPresentation, requestId);
  };

  const start = (): void => {
    stop();
    const playerRoute = options.getActiveRoute() === 'player';
    if (!playerRoute && options.getActiveRoute() !== 'guide') return;
    void refresh('poll-start', { showLoading: !playerRoute, allowPlayerRoute: playerRoute });
    guidePollTimer = options.host.setInterval(() => {
      const onPlayer = options.getActiveRoute() === 'player';
      void refresh('poll-interval', { allowPlayerRoute: onPlayer });
    }, GUIDE_POLL_INTERVAL_MS) as number;
  };

  return {
    reconcile(previousRoute, nextRoute) {
      const previousEligible = previousRoute === 'guide' || previousRoute === 'player';
      const nextEligible = nextRoute === 'guide' || nextRoute === 'player';
      if (previousEligible && !nextEligible) {
        stop();
      } else if (nextEligible && previousRoute !== nextRoute) {
        start();
      }
    },
    start,
    stop,
    refresh,
    getGeneration: () => guidePresentationRequestId,
    getLastValidPresentation: () => lastValidPresentation,
  };
}
