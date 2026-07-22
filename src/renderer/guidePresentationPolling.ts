import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import {
  EPG_SLOT_DURATION_MS,
  EPG_WINDOW_DURATION_MS,
  normalizeEpgPresentation,
} from './epg.js';
import { summarizeRendererBridgeError } from './rendererBridgeFailures.js';

const GUIDE_POLL_INTERVAL_MS = 15_000;
const GUIDE_REQUEST_TIMEOUT_MS = 30_000;
const GUIDE_REQUEST_TIMEOUT_MESSAGE = 'Guide refresh timed out. Try again.';

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
  lifecycleGeneration: number;
  advanceGenerationOnStart: boolean;
  playerRefresh: boolean;
  windowStartMs: number;
  readonly abortController: AbortController;
  readonly promise: Promise<void>;
  settle(): void;
}

function createRefreshIntent(
  source: string,
  generation: number,
  lifecycleGeneration: number,
  advanceGenerationOnStart: boolean,
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
    lifecycleGeneration,
    advanceGenerationOnStart,
    playerRefresh,
    windowStartMs,
    abortController: new AbortController(),
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
  let guidePresentationGeneration = 0;
  let guidePresentationLifecycleGeneration = 0;
  let lastValidPresentation: ReturnType<typeof normalizeEpgPresentation> | null = null;
  let activeRefresh: GuidePresentationRefreshIntent | null = null;
  let trailingRefresh: GuidePresentationRefreshIntent | null = null;

  const stop = (): void => {
    if (guidePollTimer !== null) {
      options.host.clearInterval(guidePollTimer);
      guidePollTimer = null;
    }
    guidePresentationLifecycleGeneration += 1;
    guidePresentationGeneration += 1;
    const stoppedActive = activeRefresh;
    const stoppedTrailing = trailingRefresh;
    activeRefresh = null;
    trailingRefresh = null;
    stoppedActive?.abortController.abort(
      createGuideRefreshError('Guide refresh stopped.', 'AbortError'),
    );
    stoppedTrailing?.abortController.abort(
      createGuideRefreshError('Guide refresh stopped.', 'AbortError'),
    );
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
    const latestIntent = trailingRefresh ?? activeRefresh;
    const coalescedInterval = source === 'poll-interval'
      && latestIntent !== null
      && latestIntent.lifecycleGeneration === guidePresentationLifecycleGeneration
      && latestIntent.playerRefresh === playerRefresh
      && latestIntent.windowStartMs === windowStartMs;
    const generation = coalescedInterval
      ? guidePresentationGeneration
      : ++guidePresentationGeneration;
    if (!coalescedInterval) guidePresentationLifecycleGeneration += 1;
    if (refreshOptions.showLoading === true) options.setLoading(generation);

    if (activeRefresh === null) {
      const intent = createRefreshIntent(
        source,
        generation,
        guidePresentationLifecycleGeneration,
        false,
        playerRefresh,
        windowStartMs,
      );
      startRefresh(intent);
      return intent.promise;
    }

    if (trailingRefresh === null) {
      trailingRefresh = createRefreshIntent(
        source,
        generation,
        guidePresentationLifecycleGeneration,
        coalescedInterval,
        playerRefresh,
        windowStartMs,
      );
    } else {
      trailingRefresh.source = source;
      trailingRefresh.playerRefresh = playerRefresh;
      trailingRefresh.windowStartMs = windowStartMs;
      if (!coalescedInterval) {
        trailingRefresh.generation = generation;
        trailingRefresh.lifecycleGeneration = guidePresentationLifecycleGeneration;
        trailingRefresh.advanceGenerationOnStart = false;
      }
    }
    return trailingRefresh.promise;
  };

  const startRefresh = (intent: GuidePresentationRefreshIntent): void => {
    if (intent.advanceGenerationOnStart) {
      intent.generation = ++guidePresentationGeneration;
      intent.lifecycleGeneration = guidePresentationLifecycleGeneration;
      intent.advanceGenerationOnStart = false;
    }
    activeRefresh = intent;
    void executeRefresh(intent).catch(() => undefined);
  };

  const executeRefresh = async (intent: GuidePresentationRefreshIntent): Promise<void> => {
    try {
      let result: Awaited<ReturnType<typeof options.guide.getPresentation>>;
      try {
        result = await waitForGuidePresentation(
          options.guide.getPresentation({
            startTimeMs: intent.windowStartMs,
            durationMs: EPG_WINDOW_DURATION_MS,
          }),
          intent.abortController,
          options.host,
        );
      } catch (error: unknown) {
        if (isCurrent(intent)) {
          const message = isGuideRefreshTimeout(error)
            ? GUIDE_REQUEST_TIMEOUT_MESSAGE
            : summarizeRendererBridgeError(error);
          if (intent.playerRefresh) {
            options.handlePlayerFailure?.(intent.source, message, intent.generation);
          } else {
            options.handleFailure(intent.source, message, intent.generation);
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
    && intent.lifecycleGeneration === guidePresentationLifecycleGeneration
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
    getGeneration: () => guidePresentationGeneration,
    getLastValidPresentation: () => lastValidPresentation,
  };
}

function waitForGuidePresentation<T>(
  request: Promise<T>,
  abortController: AbortController,
  host: Window,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const { signal } = abortController;
    let settled = false;
    let timeoutId: number | null = null;

    const cleanup = (): void => {
      if (timeoutId !== null) host.clearTimeout(timeoutId);
      signal.removeEventListener('abort', handleAbort);
    };
    const settle = (action: () => void): void => {
      if (settled) return;
      settled = true;
      cleanup();
      action();
    };
    const handleAbort = (): void => {
      settle(() => reject(readGuideRefreshAbortReason(signal)));
    };

    if (signal.aborted) {
      handleAbort();
      return;
    }

    signal.addEventListener('abort', handleAbort, { once: true });
    timeoutId = host.setTimeout(() => {
      abortController.abort(createGuideRefreshError(GUIDE_REQUEST_TIMEOUT_MESSAGE, 'TimeoutError'));
    }, GUIDE_REQUEST_TIMEOUT_MS);
    void request.then(
      (value) => settle(() => resolve(value)),
      (error: unknown) => settle(() => reject(error)),
    );
  });
}

function readGuideRefreshAbortReason(signal: AbortSignal): Error {
  return signal.reason instanceof Error
    ? signal.reason
    : createGuideRefreshError('Guide refresh aborted.', 'AbortError');
}

function createGuideRefreshError(message: string, name: 'AbortError' | 'TimeoutError'): Error {
  const error = new Error(message);
  error.name = name;
  return error;
}

function isGuideRefreshTimeout(error: unknown): boolean {
  return error instanceof Error && error.name === 'TimeoutError';
}
