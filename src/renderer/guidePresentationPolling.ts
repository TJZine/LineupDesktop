import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import {
  EPG_CHANNEL_PAGE_SIZE,
  EPG_SLOT_DURATION_MS,
  getEpgWindowDurationMs,
  normalizeEpgPresentation,
  resolveEpgPageNavigation,
  type EpgGuideDensity,
  type EpgPresentationSource,
  type EpgState,
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
  getGuideDensity(): EpgGuideDensity;
  getChannelOffset?(): number;
  getNowMs?(): number;
  setLoading(generation: number): void;
  applyPresentation(
    presentation: ReturnType<typeof normalizeEpgPresentation>,
    generation: number,
    pagingTargetGlobalIndex: number | null | undefined,
    effectiveStartTimeMs?: number,
  ): void;
  handleFailure(source: string, message: string, generation: number, retainLastValid: boolean): void;
  setPagingBusy?(busy: boolean): void;
  applyPlayerPresentation?(
    presentation: ReturnType<typeof normalizeEpgPresentation>,
    generation: number,
    effectiveStartTimeMs?: number,
  ): void;
  handlePlayerFailure?(source: string, message: string, generation: number): void;
}

export interface GuidePresentationPollingController {
  reconcile(previousRoute: AppRouteId, nextRoute: AppRouteId): void;
  start(): void;
  stop(): void;
  refresh(source: string, options?: GuidePresentationRefreshOptions): Promise<void>;
  requestPage(input: GuidePageRefreshRequest): Promise<void>;
  navigatePage(input: GuidePageNavigationRequest): GuidePageNavigationResult;
  cancelPage(): void;
  getPendingPageTarget(): number | null;
  getGeneration(): number;
  getLastValidPresentation(): ReturnType<typeof normalizeEpgPresentation> | null;
  notePastItemsWindowChange(): void;
  settlePastItemsWindow(input: GuidePastItemsWindowSettlementInput): void;
}

export interface GuidePastItemsWindowSettlementInput {
  currentValue: 'auto' | '0' | '15' | '30';
  acceptedValue: 'auto' | '0' | '15' | '30' | null;
  saving: boolean;
}

export interface GuidePresentationRefreshOptions {
  showLoading?: boolean;
  allowPlayerRoute?: boolean;
  channelOffset?: number;
}

export interface GuidePageRefreshRequest {
  targetGlobalIndex: number;
  sourceLocalIndex: number;
  scopeToken: string | null;
  channelOffset: number;
}

export interface GuidePageNavigationRequest {
  state: EpgState;
  presentation: EpgPresentationSource;
  offset: -5 | 5;
  scopeToken: string | null;
}

export interface GuidePageNavigationResult {
  handled: boolean;
  targetLocalIndex: number | null;
}

interface GuidePresentationRefreshIntent {
  requestSequence: number;
  source: string;
  generation: number;
  lifecycleGeneration: number;
  advanceGenerationOnStart: boolean;
  playerRefresh: boolean;
  windowStartMs: number;
  requestedDurationMs: number;
  channelOffset: number;
  pastItemsWindowGeneration: number;
  readonly abortController: AbortController;
  readonly promise: Promise<void>;
  settle(): void;
}

function createRefreshIntent(
  requestSequence: number,
  source: string,
  generation: number,
  lifecycleGeneration: number,
  advanceGenerationOnStart: boolean,
  playerRefresh: boolean,
  windowStartMs: number,
  requestedDurationMs: number,
  channelOffset: number,
  pastItemsWindowGeneration: number,
): GuidePresentationRefreshIntent {
  let settled = false;
  let resolvePromise: () => void = () => undefined;
  const promise = new Promise<void>((resolve) => {
    resolvePromise = resolve;
  });
  return {
    requestSequence,
    source,
    generation,
    lifecycleGeneration,
    advanceGenerationOnStart,
    playerRefresh,
    windowStartMs,
    requestedDurationMs,
    channelOffset,
    pastItemsWindowGeneration,
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
  let refreshRequestSequence = 0;
  let pendingPage: Readonly<GuidePageRefreshRequest & { requestSequence: number }> | null = null;
  let pastItemsWindowGeneration = 0;
  let pastItemsWindowSettlementPending = false;

  const getRequestedDurationMs = (): number => getEpgWindowDurationMs(options.getGuideDensity());

  const cancelPage = (): void => {
    if (pendingPage === null) return;
    pendingPage = null;
    const cancelledActivePage = activeRefresh?.source === 'guide-page-change'
      ? activeRefresh
      : null;
    if (trailingRefresh?.source === 'guide-page-change') {
      const cancelledTrailingPage = trailingRefresh;
      trailingRefresh = null;
      cancelledTrailingPage.settle();
    }
    guidePresentationLifecycleGeneration += 1;
    guidePresentationGeneration += 1;
    cancelledActivePage?.abortController.abort(
      createGuideRefreshError('Guide page refresh cancelled.', 'AbortError'),
    );
    options.setPagingBusy?.(false);
  };

  const stop = (): void => {
    cancelPage();
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

  const queueRefresh = (
    source: string,
    refreshOptions: GuidePresentationRefreshOptions = {},
  ): Readonly<{ promise: Promise<void>; requestSequence: number }> => {
    const playerRefresh = options.getActiveRoute() === 'player' && refreshOptions.allowPlayerRoute === true;
    if (options.getActiveRoute() !== 'guide' && !playerRefresh) {
      return { promise: Promise.resolve(), requestSequence: 0 };
    }
    const windowStartMs = playerRefresh
      ? Math.floor((options.getNowMs?.() ?? Date.now()) / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS
      : options.getWindowStartMs();
    const requestedDurationMs = getRequestedDurationMs();
    const latestIntent = trailingRefresh ?? activeRefresh;
    const channelOffset = refreshOptions.channelOffset ?? options.getChannelOffset?.() ?? 0;
    const coalescedInterval = source === 'poll-interval'
      && latestIntent !== null
      && latestIntent.lifecycleGeneration === guidePresentationLifecycleGeneration
      && latestIntent.playerRefresh === playerRefresh
      && latestIntent.windowStartMs === windowStartMs
      && latestIntent.requestedDurationMs === requestedDurationMs
      && latestIntent.channelOffset === channelOffset;
    const generation = coalescedInterval
      ? guidePresentationGeneration
      : ++guidePresentationGeneration;
    if (!coalescedInterval) guidePresentationLifecycleGeneration += 1;
    if (refreshOptions.showLoading === true) options.setLoading(generation);
    const requestSequence = ++refreshRequestSequence;

    if (activeRefresh === null) {
      const intent = createRefreshIntent(
        requestSequence,
        source,
        generation,
        guidePresentationLifecycleGeneration,
        false,
        playerRefresh,
        windowStartMs,
        requestedDurationMs,
        channelOffset,
        pastItemsWindowGeneration,
      );
      startRefresh(intent);
      return { promise: intent.promise, requestSequence };
    }

    if (trailingRefresh === null) {
      trailingRefresh = createRefreshIntent(
        requestSequence,
        source,
        generation,
        guidePresentationLifecycleGeneration,
        coalescedInterval,
        playerRefresh,
        windowStartMs,
        requestedDurationMs,
        channelOffset,
        pastItemsWindowGeneration,
      );
    } else {
      trailingRefresh.requestSequence = requestSequence;
      trailingRefresh.source = source;
      trailingRefresh.playerRefresh = playerRefresh;
      trailingRefresh.windowStartMs = windowStartMs;
      trailingRefresh.requestedDurationMs = requestedDurationMs;
      trailingRefresh.channelOffset = channelOffset;
      trailingRefresh.pastItemsWindowGeneration = pastItemsWindowGeneration;
      if (!coalescedInterval) {
        trailingRefresh.generation = generation;
        trailingRefresh.lifecycleGeneration = guidePresentationLifecycleGeneration;
        trailingRefresh.advanceGenerationOnStart = false;
      }
    }
    return { promise: trailingRefresh.promise, requestSequence };
  };

  const refresh = (
    source: string,
    refreshOptions: GuidePresentationRefreshOptions = {},
  ): Promise<void> => {
    cancelPage();
    return queueRefresh(source, refreshOptions).promise;
  };

  const requestPage = (input: GuidePageRefreshRequest): Promise<void> => {
    const queued = queueRefresh('guide-page-change', {
      channelOffset: input.channelOffset,
      showLoading: false,
    });
    if (queued.requestSequence === 0) return queued.promise;
    pendingPage = Object.freeze({ ...input, requestSequence: queued.requestSequence });
    options.setPagingBusy?.(true);
    return queued.promise;
  };

  const navigatePage = (input: GuidePageNavigationRequest): GuidePageNavigationResult => {
    const decision = resolveEpgPageNavigation(
      input.state,
      input.presentation,
      input.offset,
      pendingPage?.targetGlobalIndex ?? null,
    );
    if (decision === null) return { handled: false, targetLocalIndex: null };
    if (decision.boundaryClamped) return { handled: true, targetLocalIndex: null };
    if (!decision.fetchRequired) {
      cancelPage();
      return { handled: true, targetLocalIndex: decision.targetLocalIndex };
    }
    void requestPage({
      targetGlobalIndex: decision.targetGlobalIndex,
      sourceLocalIndex: decision.sourceLocalIndex,
      scopeToken: input.scopeToken,
      channelOffset: decision.channelOffset,
    });
    return { handled: true, targetLocalIndex: null };
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
            durationMs: intent.requestedDurationMs,
            channelOffset: intent.channelOffset,
            channelLimit: EPG_CHANNEL_PAGE_SIZE,
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
            options.handleFailure(intent.source, message, intent.generation, settlePagingFailure(intent));
          }
        }
        return;
      }

      if (isCurrent(intent)) {
        if (!result.ok) {
          if (intent.playerRefresh) options.handlePlayerFailure?.(intent.source, result.error.message, intent.generation);
          else options.handleFailure(
            intent.source,
            result.error.message,
            intent.generation,
            settlePagingFailure(intent),
          );
        } else {
          lastValidPresentation = normalizeEpgPresentation(result.value);
          const effectiveStartTimeMs = Math.max(
            intent.windowStartMs,
            lastValidPresentation.minimumStartTimeMs ?? intent.windowStartMs,
          );
          if (intent.playerRefresh) options.applyPlayerPresentation?.(lastValidPresentation, intent.generation, effectiveStartTimeMs);
          else options.applyPresentation(
            lastValidPresentation,
            intent.generation,
            settlePagingSuccess(intent, lastValidPresentation),
            effectiveStartTimeMs,
          );
        }
      }
    } finally {
      completeRefresh(intent);
    }
  };

  const isCurrent = (intent: GuidePresentationRefreshIntent): boolean => intent === activeRefresh
    && intent.lifecycleGeneration === guidePresentationLifecycleGeneration
    && intent.requestedDurationMs === getRequestedDurationMs()
    && intent.pastItemsWindowGeneration === pastItemsWindowGeneration
    && options.getActiveRoute() === (intent.playerRefresh ? 'player' : 'guide');

  const settlePagingFailure = (intent: GuidePresentationRefreshIntent): boolean => {
    if (pendingPage?.requestSequence !== intent.requestSequence) return false;
    pendingPage = null;
    options.setPagingBusy?.(false);
    return true;
  };

  const settlePagingSuccess = (
    intent: GuidePresentationRefreshIntent,
    presentation: ReturnType<typeof normalizeEpgPresentation>,
  ): number | null | undefined => {
    const page = pendingPage;
    if (page?.requestSequence !== intent.requestSequence) return undefined;
    pendingPage = null;
    options.setPagingBusy?.(false);
    const window = presentation.channelWindow;
    const scopeToken = presentation.libraryFilter?.scopeToken ?? null;
    return window !== undefined && page.scopeToken === scopeToken &&
      page.targetGlobalIndex >= window.offset &&
      page.targetGlobalIndex < window.offset + presentation.channels.length
      ? page.targetGlobalIndex
      : null;
  };

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
    requestPage,
    navigatePage,
    cancelPage,
    getPendingPageTarget: () => pendingPage?.targetGlobalIndex ?? null,
    getGeneration: () => guidePresentationGeneration,
    getLastValidPresentation: () => lastValidPresentation,
    notePastItemsWindowChange() {
      pastItemsWindowGeneration += 1;
      pastItemsWindowSettlementPending = true;
    },
    settlePastItemsWindow({ currentValue, acceptedValue, saving }) {
      if (!pastItemsWindowSettlementPending || saving || acceptedValue === null || currentValue !== acceptedValue) return;
      pastItemsWindowSettlementPending = false;
      const route = options.getActiveRoute();
      if (route === 'guide' || route === 'player') {
        void refresh('guide-past-items-window-settlement', {
          showLoading: route === 'guide',
          allowPlayerRoute: route === 'player',
        });
      }
    },
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
