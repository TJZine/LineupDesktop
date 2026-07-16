import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import {
  EPG_SLOT_DURATION_MS,
  EPG_WINDOW_DURATION_MS,
  normalizeEpgPresentation,
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
    presentation: ReturnType<typeof normalizeEpgPresentation>,
    generation: number,
  ): void;
  handleFailure(source: string, message: string, generation: number): void;
  applyPlayerPresentation?(
    presentation: ReturnType<typeof normalizeEpgPresentation>,
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
  getLastValidPresentation(): ReturnType<typeof normalizeEpgPresentation> | null;
}

export interface GuidePresentationRefreshOptions {
  showLoading?: boolean;
  allowPlayerRoute?: boolean;
}

interface GuidePresentationRefreshIntent {
  source: string;
  generation: number;
  playerRefresh: boolean;
  windowStartMs: number;
  readonly promise: Promise<void>;
  settle(): void;
}

function createRefreshIntent(
  source: string,
  generation: number,
  playerRefresh: boolean,
  windowStartMs: number,
): GuidePresentationRefreshIntent {
  let settled = false;
  let resolvePromise: () => void = () => undefined;
  const promise = new Promise<void>((resolve) => {
    resolvePromise = resolve;
  });
  return {
    source,
    generation,
    playerRefresh,
    windowStartMs,
    promise,
    settle: () => {
      if (settled) return;
      settled = true;
      resolvePromise();
    },
  };
}

export function createGuidePresentationPolling(
  options: GuidePresentationPollingOptions,
): GuidePresentationPollingController {
  let guidePollTimer: number | null = null;
  let guidePresentationRequestId = 0;
  let lastValidPresentation: ReturnType<typeof normalizeEpgPresentation> | null = null;
  let activeRefresh: GuidePresentationRefreshIntent | null = null;
  let trailingRefresh: GuidePresentationRefreshIntent | null = null;

  const stop = (): void => {
    if (guidePollTimer !== null) {
      options.host.clearInterval(guidePollTimer);
      guidePollTimer = null;
    }
    guidePresentationRequestId += 1;
    const stoppedActive = activeRefresh;
    const stoppedTrailing = trailingRefresh;
    trailingRefresh = null;
    stoppedActive?.settle();
    stoppedTrailing?.settle();
  };

  const refresh = (
    source: string,
    refreshOptions: GuidePresentationRefreshOptions = {},
  ): Promise<void> => {
    const playerRefresh = options.getActiveRoute() === 'player' && refreshOptions.allowPlayerRoute === true;
    if (options.getActiveRoute() !== 'guide' && !playerRefresh) {
      return Promise.resolve();
    }
    const windowStartMs = playerRefresh
      ? Math.floor((options.getNowMs?.() ?? Date.now()) / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS
      : options.getWindowStartMs();
    const requestId = ++guidePresentationRequestId;
    if (refreshOptions.showLoading === true) {
      options.setLoading(requestId);
    }

    if (activeRefresh === null) {
      const intent = createRefreshIntent(source, requestId, playerRefresh, windowStartMs);
      startRefresh(intent);
      return intent.promise;
    }

    if (trailingRefresh === null) {
      trailingRefresh = createRefreshIntent(source, requestId, playerRefresh, windowStartMs);
    } else {
      trailingRefresh.source = source;
      trailingRefresh.generation = requestId;
      trailingRefresh.playerRefresh = playerRefresh;
      trailingRefresh.windowStartMs = windowStartMs;
    }
    return trailingRefresh.promise;
  };

  const startRefresh = (intent: GuidePresentationRefreshIntent): void => {
    activeRefresh = intent;
    void executeRefresh(intent).catch(() => undefined);
  };

  const executeRefresh = async (intent: GuidePresentationRefreshIntent): Promise<void> => {
    try {
      let result: Awaited<ReturnType<typeof options.guide.getPresentation>>;
      try {
        result = await options.guide.getPresentation({
          startTimeMs: intent.windowStartMs,
          durationMs: EPG_WINDOW_DURATION_MS,
        });
      } catch (error: unknown) {
        if (isCurrent(intent)) {
          if (intent.playerRefresh) {
            options.handlePlayerFailure?.(intent.source, summarizeRendererBridgeError(error), intent.generation);
          } else {
            options.handleFailure(intent.source, summarizeRendererBridgeError(error), intent.generation);
          }
        }
        return;
      }

      if (isCurrent(intent)) {
        if (!result.ok) {
          if (intent.playerRefresh) options.handlePlayerFailure?.(intent.source, result.error.message, intent.generation);
          else options.handleFailure(intent.source, result.error.message, intent.generation);
        } else {
          lastValidPresentation = normalizeEpgPresentation(result.value);
          if (intent.playerRefresh) options.applyPlayerPresentation?.(lastValidPresentation, intent.generation);
          else options.applyPresentation(lastValidPresentation, intent.generation);
        }
      }
    } finally {
      completeRefresh(intent);
    }
  };

  const isCurrent = (intent: GuidePresentationRefreshIntent): boolean => intent === activeRefresh
    && intent.generation === guidePresentationRequestId
    && options.getActiveRoute() === (intent.playerRefresh ? 'player' : 'guide');

  const completeRefresh = (intent: GuidePresentationRefreshIntent): void => {
    intent.settle();
    if (activeRefresh !== intent) return;
    activeRefresh = null;
    const next = trailingRefresh;
    trailingRefresh = null;
    if (next !== null) startRefresh(next);
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
