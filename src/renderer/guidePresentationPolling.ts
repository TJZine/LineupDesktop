import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import {
  EPG_SLOT_DURATION_MS,
  getEpgWindowDurationMs,
  normalizeEpgPresentation,
  resolveEpgPageNavigation,
  type EpgGuideTimeRange,
  type EpgPresentationSource,
  type EpgState,
} from './epg.js';
import { summarizeRendererBridgeError } from './rendererBridgeFailures.js';
import {
  AUTO_GUIDE_PRELOAD_PROFILE,
  REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE,
  GuidePresentationLru,
  guideCacheKey,
  projectGuideForegroundChannelLimit,
  type GuidePerformanceProfile,
  type GuidePerformanceProfileConfig,
} from './guideVirtualization.js';
import { guidePerformanceMarks, type GuideRequestOrigin } from './guidePerformanceMarks.js';

const GUIDE_POLL_INTERVAL_MS = 15_000;
const GUIDE_REQUEST_TIMEOUT_MS = 30_000;
const GUIDE_REQUEST_TIMEOUT_MESSAGE = 'Guide refresh timed out. Try again.';

export interface GuidePresentationPollingOptions {
  guide: LineupDesktopPreloadApi['guide'];
  host: Window;
  getActiveRoute(): AppRouteId;
  getWindowStartMs(): number;
  getGuideTimeRange(): EpgGuideTimeRange;
  getGuidePerformanceProfile?(): GuidePerformanceProfile;
  getCacheIdentity?(): string | null;
  getCacheScopeToken?(): string | null;
  getChannelOffset?(): number;
  getCompleteVisibleRowCount?(): number;
  getNowMs?(): number;
  requestWindowState?(state: 'queued' | 'settled', request: Readonly<{
    generation: number;
    channelOffset: number;
    channelLimit: number;
    warmOnly: boolean;
  }>): void;
  setLoading(generation: number): void;
  applyPresentation(
    presentation: ReturnType<typeof normalizeEpgPresentation>,
    generation: number,
    pagingTargetGlobalIndex: number | null | undefined,
    effectiveStartTimeMs?: number,
    requestWindow?: Readonly<{ channelOffset: number; channelLimit: number }>,
  ): void;
  handleFailure(source: string, message: string, generation: number, retainLastValid: boolean,
    requestWindow?: Readonly<{ channelOffset: number; channelLimit: number }>): void;
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
  hasPendingGuideSettingsChange(): boolean;
  noteGuideSettingsChange(): void;
  settleGuideSettings(loading: boolean): Promise<void>;
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
  channelLimit?: number;
  windowStartMs?: number;
  warmOnly?: boolean;
  invalidateCache?: true;
  cancelActive?: true;
}

export interface GuidePageRefreshRequest {
  targetGlobalIndex: number;
  scopeToken: string | null;
  channelOffset: number;
  channelLimit?: number;
}

export interface GuidePageNavigationRequest {
  state: EpgState;
  presentation: EpgPresentationSource;
  offset: number;
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
  channelLimit: number;
  timeBufferMs: number;
  warmOnly: boolean;
  cacheIdentity: string | null;
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
  channelLimit: number,
  timeBufferMs: number,
  warmOnly: boolean,
  cacheIdentity: string | null,
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
    channelLimit,
    timeBufferMs,
    warmOnly,
    cacheIdentity,
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
  function getProfile(): GuidePerformanceProfileConfig {
    return options.getGuidePerformanceProfile?.() === 'reduced-resource'
      ? REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE
      : AUTO_GUIDE_PRELOAD_PROFILE;
  }

  const getCacheIdentity = (): string | null => options.getCacheIdentity?.() ?? null;
  const getNowMs = (): number => options.getNowMs?.() ?? Date.now();
  let guidePollTimer: number | null = null;
  let guidePresentationGeneration = 0;
  let guidePresentationLifecycleGeneration = 0;
  let lastValidPresentation: ReturnType<typeof normalizeEpgPresentation> | null = null;
  let activeRefresh: GuidePresentationRefreshIntent | null = null;
  let trailingRefresh: GuidePresentationRefreshIntent | null = null;
  let refreshRequestSequence = 0;
  let pendingPage: Readonly<GuidePageRefreshRequest & { requestSequence: number }> | null = null;
  let guideSettingsRefreshPending = false;
  let pastItemsWindowGeneration = 0;
  let pastItemsWindowSettlementPending = false;
  let cacheProfile: GuidePerformanceProfileConfig = getProfile();
  let presentationCache = new GuidePresentationLru<ReturnType<typeof normalizeEpgPresentation>>(cacheProfile);
  let warmCandidates: Array<{ windowStartMs: number; channelOffset: number }> = [];
  let warmIdleHandle: number | null = null;
  let cachedScopeToken: string | null = null;

  const invalidatePresentationCache = (): void => {
    presentationCache.clear();
    warmCandidates = [];
    cachedScopeToken = null;
  };

  const emitRequestWindowState = (
    state: 'queued' | 'settled',
    intent: GuidePresentationRefreshIntent,
  ): void => options.requestWindowState?.(state, {
    generation: intent.generation,
    channelOffset: intent.channelOffset,
    channelLimit: intent.channelLimit,
    warmOnly: intent.warmOnly,
  });

  const getRequestedDurationMs = (): number => getEpgWindowDurationMs(options.getGuideTimeRange());

  const refreshProfile = (): GuidePerformanceProfileConfig => {
    const next = getProfile();
    if (next !== cacheProfile) {
      cacheProfile = next;
      presentationCache = new GuidePresentationLru(next);
      warmCandidates = [];
      cachedScopeToken = null;
    }
    return next;
  };

  const cancelPage = (): void => {
    if (pendingPage === null) return;
    invalidatePresentationCache();
    pendingPage = null;
    const cancelledActivePage = activeRefresh?.source === 'guide-page-change'
      ? activeRefresh
      : null;
    if (trailingRefresh?.source === 'guide-page-change') {
      const cancelledTrailingPage = trailingRefresh;
      trailingRefresh = null;
      emitRequestWindowState('settled', cancelledTrailingPage);
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
    if (stoppedTrailing !== null) emitRequestWindowState('settled', stoppedTrailing);
    stoppedTrailing?.settle();
    invalidatePresentationCache();
    if (warmIdleHandle !== null && 'cancelIdleCallback' in options.host) options.host.cancelIdleCallback(warmIdleHandle);
    warmIdleHandle = null;
  };

  const queueRefresh = (
    source: string,
    refreshOptions: GuidePresentationRefreshOptions = {},
  ): Readonly<{ promise: Promise<void>; requestSequence: number }> => {
    if (refreshOptions.invalidateCache === true) invalidatePresentationCache();
    const playerRefresh = options.getActiveRoute() === 'player' && refreshOptions.allowPlayerRoute === true;
    if (options.getActiveRoute() !== 'guide' && !playerRefresh) {
      return { promise: Promise.resolve(), requestSequence: 0 };
    }
    const windowStartMs = refreshOptions.windowStartMs ?? (playerRefresh
      ? Math.floor(getNowMs() / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS
      : options.getWindowStartMs());
    const requestedDurationMs = getRequestedDurationMs();
    const profile = refreshProfile();
    const latestIntent = trailingRefresh ?? activeRefresh;
    const channelOffset = refreshOptions.channelOffset ?? options.getChannelOffset?.() ?? 0;
    const channelLimit = clampChannelLimit(refreshOptions.channelLimit ??
      projectGuideForegroundChannelLimit(options.getCompleteVisibleRowCount?.() ?? 20, 2));
    if (activeRefresh?.warmOnly === true && refreshOptions.warmOnly !== true) {
      activeRefresh.abortController.abort(
        createGuideRefreshError('Guide warm refresh superseded by foreground work.', 'AbortError'),
      );
    }
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
        channelLimit,
        profile.timeBufferMs,
        refreshOptions.warmOnly === true,
        getCacheIdentity(),
        pastItemsWindowGeneration,
      );
      emitRequestWindowState('queued', intent);
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
        channelLimit,
        profile.timeBufferMs,
        refreshOptions.warmOnly === true,
        getCacheIdentity(),
        pastItemsWindowGeneration,
      );
      emitRequestWindowState('queued', trailingRefresh);
    } else {
      emitRequestWindowState('settled', trailingRefresh);
      trailingRefresh.requestSequence = requestSequence;
      trailingRefresh.source = source;
      trailingRefresh.playerRefresh = playerRefresh;
      trailingRefresh.windowStartMs = windowStartMs;
      trailingRefresh.requestedDurationMs = requestedDurationMs;
      trailingRefresh.channelOffset = channelOffset;
      trailingRefresh.channelLimit = channelLimit;
      trailingRefresh.timeBufferMs = profile.timeBufferMs;
      trailingRefresh.warmOnly = refreshOptions.warmOnly === true;
      trailingRefresh.cacheIdentity = getCacheIdentity();
      trailingRefresh.pastItemsWindowGeneration = pastItemsWindowGeneration;
      if (!coalescedInterval) {
        trailingRefresh.generation = generation;
        trailingRefresh.lifecycleGeneration = guidePresentationLifecycleGeneration;
        trailingRefresh.advanceGenerationOnStart = false;
      }
      emitRequestWindowState('queued', trailingRefresh);
    }
    return { promise: trailingRefresh.promise, requestSequence };
  };

  const refresh = (
    source: string,
    refreshOptions: GuidePresentationRefreshOptions = {},
  ): Promise<void> => {
    cancelPage();
    if (refreshOptions.cancelActive === true && activeRefresh !== null) {
      guidePresentationLifecycleGeneration += 1;
      guidePresentationGeneration += 1;
      activeRefresh.abortController.abort(
        createGuideRefreshError('Guide refresh superseded.', 'AbortError'),
      );
    }
    return queueRefresh(source, refreshOptions).promise;
  };

  const requestPage = (input: GuidePageRefreshRequest): Promise<void> => {
    const queued = queueRefresh('guide-page-change', {
      channelOffset: input.channelOffset,
      channelLimit: input.channelLimit ?? projectGuideForegroundChannelLimit(options.getCompleteVisibleRowCount?.() ?? 20, 2),
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
      projectGuideForegroundChannelLimit(options.getCompleteVisibleRowCount?.() ?? 20, 2),
    );
    if (decision === null) return { handled: false, targetLocalIndex: null };
    if (decision.boundaryClamped) return { handled: true, targetLocalIndex: null };
    if (!decision.fetchRequired) {
      cancelPage();
      return { handled: true, targetLocalIndex: decision.targetLocalIndex };
    }
    void requestPage({
      targetGlobalIndex: decision.targetGlobalIndex,
      scopeToken: input.scopeToken,
      channelOffset: decision.channelOffset,
    });
    return { handled: true, targetLocalIndex: null };
  };

  const startRefresh = (intent: GuidePresentationRefreshIntent): void => {
    if (intent.advanceGenerationOnStart) {
      emitRequestWindowState('settled', intent);
      intent.generation = ++guidePresentationGeneration;
      intent.lifecycleGeneration = guidePresentationLifecycleGeneration;
      intent.advanceGenerationOnStart = false;
      emitRequestWindowState('queued', intent);
    }
    activeRefresh = intent;
    void executeRefresh(intent).catch(() => undefined);
  };

  const executeRefresh = async (intent: GuidePresentationRefreshIntent): Promise<void> => {
    const requestOrigin: GuideRequestOrigin = intent.source === 'poll-start' || intent.source === 'poll-interval'
      ? 'poll'
      : intent.source === 'guide-auto-warm' ? 'warm' : 'foreground';
    const markSequence = guidePerformanceMarks.requestStarted(intent.generation, intent.channelOffset,
      intent.channelLimit, intent.windowStartMs, intent.requestedDurationMs, requestOrigin);
    let markedSettled = false;
    const markSettled = (
      requestClass: 'renderer-cache' | 'runtime' | 'rejected',
      accepted: boolean,
    ): void => {
      if (markedSettled) return;
      markedSettled = true;
      guidePerformanceMarks.requestSettled(markSequence, intent.generation, requestClass, accepted, requestOrigin);
    };
    try {
      const baseKey = guideCacheKey(
        Math.max(0, intent.windowStartMs - intent.timeBufferMs),
        intent.requestedDurationMs + intent.timeBufferMs * 2,
        intent.channelOffset,
        intent.channelLimit,
      );
      const currentCacheIdentity = getCacheIdentity();
      const key = intent.cacheIdentity === null ? null : `${intent.cacheIdentity}:${baseKey}`;
      const cacheEligibleSource = intent.source === 'guide-page-change' || intent.source === 'epg-window-change';
      const cached = key !== null && cacheEligibleSource && intent.cacheIdentity === currentCacheIdentity
        ? presentationCache.get(
          key,
          { focused: true, current: true },
          { nowMs: getNowMs(), maxAgeMs: GUIDE_POLL_INTERVAL_MS },
        )
        : null;
      if (cached !== null) {
        // Align the cache path's currentness recheck with the network path's async boundary.
        await Promise.resolve();
      }
      if (cached !== null && isCurrent(intent)) {
        lastValidPresentation = cached;
        markSettled('renderer-cache', true);
        options.applyPresentation(
          cached,
          intent.generation,
          settlePagingSuccess(intent, cached),
          resolveEffectiveStartTimeMs(intent, cached),
          { channelOffset: intent.channelOffset, channelLimit: intent.channelLimit },
        );
        queueIdleWarming(intent, cached);
        return;
      }
      let result: Awaited<ReturnType<typeof options.guide.getPresentation>>;
      try {
        result = await waitForGuidePresentation(
          options.guide.getPresentation({
            startTimeMs: Math.max(0, intent.windowStartMs - intent.timeBufferMs),
            durationMs: intent.requestedDurationMs + intent.timeBufferMs * 2,
            channelOffset: intent.channelOffset,
            channelLimit: intent.channelLimit,
          }),
          intent.abortController,
          options.host,
          options.guide.cancelPresentation,
        );
      } catch (error: unknown) {
        markSettled('rejected', false);
        if (isCurrent(intent) && !intent.warmOnly) {
          const message = isGuideRefreshTimeout(error)
            ? GUIDE_REQUEST_TIMEOUT_MESSAGE
            : summarizeRendererBridgeError(error);
          if (intent.playerRefresh) {
            options.handlePlayerFailure?.(intent.source, message, intent.generation);
          } else {
            options.handleFailure(intent.source, message, intent.generation, settlePagingFailure(intent),
              { channelOffset: intent.channelOffset, channelLimit: intent.channelLimit });
          }
        }
        return;
      }

      if (isCurrent(intent)) {
        if (!result.ok) {
          markSettled('rejected', false);
          if (!intent.warmOnly) {
            if (intent.playerRefresh) options.handlePlayerFailure?.(intent.source, result.error.message, intent.generation);
            else options.handleFailure(
              intent.source,
              result.error.message,
              intent.generation,
              settlePagingFailure(intent),
              { channelOffset: intent.channelOffset, channelLimit: intent.channelLimit },
            );
          }
        } else {
          const normalized = normalizeEpgPresentation(result.value);
          const nextScopeToken = normalized.libraryFilter?.scopeToken ?? null;
          const establishedScopeToken = options.getCacheScopeToken?.() ?? null;
          if (establishedScopeToken !== null && nextScopeToken !== establishedScopeToken) {
            settlePagingFailure(intent);
            markSettled('rejected', false);
            return;
          }
          if (cachedScopeToken !== null && nextScopeToken !== cachedScopeToken) invalidatePresentationCache();
          cachedScopeToken = nextScopeToken;
          const scopeMatches = nextScopeToken === establishedScopeToken;
          if (key !== null && intent.cacheIdentity === getCacheIdentity() && scopeMatches) {
            presentationCache.set({
              key,
              value: normalized,
              fetchedAtMs: getNowMs(),
              programCount: normalized.channels.reduce((count, channel) => count + channel.programs.length, 0),
              focused: !intent.warmOnly,
              current: !intent.warmOnly && normalized.channels.some((channel) => channel.programs.some((program) =>
                program.startsAtMs <= normalized.nowMs && normalized.nowMs < program.endsAtMs)),
            });
          }
          if (intent.warmOnly) {
            markSettled('runtime', true);
            return;
          }
          lastValidPresentation = normalized;
          const effectiveStartTimeMs = resolveEffectiveStartTimeMs(intent, lastValidPresentation);
          markSettled('runtime', true);
          if (intent.playerRefresh) options.applyPlayerPresentation?.(lastValidPresentation, intent.generation, effectiveStartTimeMs);
          else options.applyPresentation(
            lastValidPresentation,
            intent.generation,
            settlePagingSuccess(intent, lastValidPresentation),
            effectiveStartTimeMs,
            { channelOffset: intent.channelOffset, channelLimit: intent.channelLimit },
          );
          queueIdleWarming(intent, lastValidPresentation);
        }
      }
    } finally {
      markSettled('rejected', false);
      completeRefresh(intent);
    }
  };

  const resolveEffectiveStartTimeMs = (
    intent: GuidePresentationRefreshIntent,
    presentation: ReturnType<typeof normalizeEpgPresentation>,
  ): number => {
    const existingGuideWindowStartMs = intent.playerRefresh
      ? options.getWindowStartMs()
      : intent.windowStartMs;
    return Math.max(
      existingGuideWindowStartMs,
      presentation.minimumStartTimeMs ?? existingGuideWindowStartMs,
    );
  };

  const isCurrent = (intent: GuidePresentationRefreshIntent): boolean => intent === activeRefresh
    && intent.lifecycleGeneration === guidePresentationLifecycleGeneration
    && intent.requestedDurationMs === getRequestedDurationMs()
    && intent.pastItemsWindowGeneration === pastItemsWindowGeneration
    && intent.cacheIdentity === getCacheIdentity()
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
    emitRequestWindowState('settled', intent);
    intent.settle();
    if (activeRefresh !== intent) return;
    activeRefresh = null;
    const next = trailingRefresh;
    trailingRefresh = null;
    if (next !== null) startRefresh(next);
    else scheduleNextWarm();
  };

  const queueIdleWarming = (
    intent: GuidePresentationRefreshIntent,
    presentation: ReturnType<typeof normalizeEpgPresentation>,
  ): void => {
    if (cacheProfile !== AUTO_GUIDE_PRELOAD_PROFILE || intent.playerRefresh || intent.warmOnly) return;
    const total = presentation.channelWindow?.total ?? presentation.channels.length;
    const maximumOffset = Math.max(0, total - intent.channelLimit);
    const nextOffset = Math.min(maximumOffset, intent.channelOffset + intent.channelLimit);
    const previousOffset = Math.max(0, intent.channelOffset - intent.channelLimit);
    warmCandidates = [
      ...(nextOffset === intent.channelOffset ? [] : [{ windowStartMs: intent.windowStartMs, channelOffset: nextOffset }]),
      ...(previousOffset === intent.channelOffset ? [] : [{ windowStartMs: intent.windowStartMs, channelOffset: previousOffset }]),
      { windowStartMs: intent.windowStartMs + EPG_SLOT_DURATION_MS, channelOffset: intent.channelOffset },
      { windowStartMs: Math.max(0, intent.windowStartMs - EPG_SLOT_DURATION_MS), channelOffset: intent.channelOffset },
    ];
  };

  const scheduleNextWarm = (): void => {
    if (activeRefresh !== null || trailingRefresh !== null || warmCandidates.length === 0 || warmIdleHandle !== null) return;
    if (!('requestIdleCallback' in options.host)) return;
    warmIdleHandle = options.host.requestIdleCallback(() => {
      warmIdleHandle = null;
      if (activeRefresh !== null || trailingRefresh !== null) return;
      const candidate = warmCandidates.shift();
      if (candidate === undefined || options.getActiveRoute() !== 'guide') return;
      void queueRefresh('guide-auto-warm', { ...candidate, warmOnly: true }).promise;
    }, { timeout: 250 });
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
    hasPendingGuideSettingsChange: () => guideSettingsRefreshPending,
    noteGuideSettingsChange() {
      guideSettingsRefreshPending = true;
    },
    settleGuideSettings(loading) {
      if (loading || !guideSettingsRefreshPending) return Promise.resolve();
      guideSettingsRefreshPending = false;
      const route = options.getActiveRoute();
      if (route !== 'guide' && route !== 'player') return Promise.resolve();
      return refresh('guide-settings-change', {
        showLoading: route === 'guide',
        allowPlayerRoute: route === 'player',
        invalidateCache: true,
        cancelActive: true,
      });
    },
    notePastItemsWindowChange() {
      pastItemsWindowGeneration += 1;
      pastItemsWindowSettlementPending = true;
      invalidatePresentationCache();
    },
    settlePastItemsWindow({ currentValue, acceptedValue, saving }) {
      if (!pastItemsWindowSettlementPending || saving || acceptedValue === null || currentValue !== acceptedValue) return;
      pastItemsWindowSettlementPending = false;
      const route = options.getActiveRoute();
      if (route === 'guide' || route === 'player') {
        void refresh('guide-past-items-window-settlement', {
          showLoading: route === 'guide',
          allowPlayerRoute: route === 'player',
          invalidateCache: true,
        });
      }
    },
  };
}

function clampChannelLimit(value: number): number {
  if (!Number.isFinite(value)) return 1;
  return Math.min(24, Math.max(1, Math.trunc(value)));
}

function waitForGuidePresentation<T>(
  request: Promise<T>,
  abortController: AbortController,
  host: Window,
  cancelPresentation: () => Promise<void>,
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
      void cancelPresentation().catch(() => undefined);
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
