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
  setLoading(): void;
  applyPresentation(presentation: ReturnType<typeof ensureRendererReadyGuidePresentation>): void;
  handleFailure(source: string, message: string): void;
}

export interface GuidePresentationPollingController {
  reconcile(previousRoute: AppRouteId, nextRoute: AppRouteId): void;
  start(): void;
  stop(): void;
  refresh(source: string): Promise<void>;
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

  const refresh = async (source: string): Promise<void> => {
    const requestId = ++guidePresentationRequestId;
    if (options.getActiveRoute() !== 'guide') {
      return;
    }
    const windowStartMs = options.getWindowStartMs();
    options.setLoading();

    let result: Awaited<ReturnType<typeof options.guide.getPresentation>>;
    try {
      result = await options.guide.getPresentation({
        startTimeMs: windowStartMs,
        durationMs: EPG_WINDOW_DURATION_MS,
      });
    } catch (error: unknown) {
      if (requestId === guidePresentationRequestId && options.getActiveRoute() === 'guide') {
        options.handleFailure(source, summarizeRendererBridgeError(error));
      }
      return;
    }

    if (requestId !== guidePresentationRequestId || options.getActiveRoute() !== 'guide') {
      return;
    }
    if (!result.ok) {
      options.handleFailure(source, result.error.message);
      return;
    }
    options.applyPresentation(ensureRendererReadyGuidePresentation(result.value, windowStartMs));
  };

  const start = (): void => {
    stop();
    void refresh('poll-start');
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
  };
}
