import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import {
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
  setLoading(generation: number): void;
  applyPresentation(
    presentation: ReturnType<typeof ensureRendererReadyGuidePresentation>,
    generation: number,
  ): void;
  handleFailure(source: string, message: string, generation: number): void;
}

export interface GuidePresentationPollingController {
  reconcile(previousRoute: AppRouteId, nextRoute: AppRouteId): void;
  start(): void;
  stop(): void;
  refresh(source: string, options?: GuidePresentationRefreshOptions): Promise<void>;
  getGeneration(): number;
}

export interface GuidePresentationRefreshOptions {
  showLoading?: boolean;
}

export function createGuidePresentationPolling(
  options: GuidePresentationPollingOptions,
): GuidePresentationPollingController {
  let guidePollTimer: number | null = null;
  let guidePresentationRequestId = 0;

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
    if (options.getActiveRoute() !== 'guide') {
      return;
    }
    const windowStartMs = options.getWindowStartMs();
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
      if (requestId === guidePresentationRequestId && options.getActiveRoute() === 'guide') {
        options.handleFailure(source, summarizeRendererBridgeError(error), requestId);
      }
      return;
    }

    if (requestId !== guidePresentationRequestId || options.getActiveRoute() !== 'guide') {
      return;
    }
    if (!result.ok) {
      options.handleFailure(source, result.error.message, requestId);
      return;
    }
    options.applyPresentation(ensureRendererReadyGuidePresentation(result.value, windowStartMs), requestId);
  };

  const start = (): void => {
    stop();
    void refresh('poll-start', { showLoading: true });
    guidePollTimer = options.host.setInterval(() => {
      void refresh('poll-interval');
    }, GUIDE_POLL_INTERVAL_MS) as number;
  };

  return {
    reconcile(previousRoute, nextRoute) {
      if (previousRoute === 'guide' && nextRoute !== 'guide') {
        stop();
      } else if (nextRoute === 'guide' && previousRoute !== 'guide') {
        start();
      }
    },
    start,
    stop,
    refresh,
    getGeneration: () => guidePresentationRequestId,
  };
}
