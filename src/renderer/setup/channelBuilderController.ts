import type {
  ChannelSetupBuildProgress,
  ChannelSetupBuildResult,
  ChannelSetupConfigDraft,
  ChannelSetupPreview,
  ChannelSetupRecordSummary,
  ChannelSetupReview,
  ChannelSetupStrategyKey,
} from '../../contracts/channel.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';

export const CHANNEL_BUILDER_ACTIONS = [
  'selectCategory', 'toggleStrategy', 'toggleScopeDropdown', 'selectScope',
  'toggleAdjustable', 'selectAdjustable', 'togglePriorityGrab', 'resetGuideOrder',
  'toggleAlternates',
  'confirmReplace', 'retryPreview', 'retryReview', 'cancelBuild', 'retryBuild',
] as const;
export type ChannelBuilderAction = (typeof CHANNEL_BUILDER_ACTIONS)[number];
export type ChannelBuilderPhase = 'idle' | 'preview-loading' | 'preview-ready' | 'preview-blocked' |
  'preview-error' | 'review-loading' | 'review-ready' | 'review-error' | 'progress' | 'result' | 'error';
export type ChannelBuilderCategory = 'content-sources' | 'advanced-sources' | 'build-options' | 'series-ordering' | 'limits' | 'priority-order';
export type ChannelBuilderAdjustableControl = 'build-mode' | 'combine-mode' | 'alternate-copies' | 'base-mode' | 'base-block' | 'variant-type' | 'variant-block' | 'max-channels' | 'min-items';

export interface ChannelBuilderState {
  phase: ChannelBuilderPhase;
  draft: ChannelSetupConfigDraft;
  activeCategory: ChannelBuilderCategory;
  preview: ChannelSetupPreview | null;
  review: ChannelSetupReview | null;
  progress: ChannelSetupBuildProgress | null;
  result: ChannelSetupBuildResult | null;
  record: ChannelSetupRecordSummary | null;
  safeError: string | null;
  slow: boolean;
  replaceConfirmed: boolean;
  cancelStatus: 'idle' | 'requesting' | 'accepted' | 'too-late' | 'not-active';
  openScopeDropdown: ChannelSetupStrategyKey | null;
  openAdjustableControl: ChannelBuilderAdjustableControl | null;
  grabbedPriorityKey: ChannelSetupStrategyKey | null;
  focusIntent: string | null;
}

export interface ChannelBuilderController {
  getState(): ChannelBuilderState;
  initialize(selectedLibraryIds?: readonly string[]): Promise<void>;
  setLibraries(selectedLibraryIds: readonly string[]): Promise<void>;
  apply(action: ChannelBuilderAction, detail?: string): void;
  handlePriorityDirection(direction: 'up' | 'down'): boolean;
  dismissTransient(): boolean;
  requestPreview(immediate?: boolean): Promise<void>;
  requestReview(): Promise<boolean>;
  build(existingChannelCount: number): Promise<ChannelSetupBuildResult | null>;
  cancelBuild(): Promise<void>;
  invalidate(): void;
  dispose(): void;
}

const STRATEGIES: readonly ChannelSetupStrategyKey[] = [
  'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
];
const CROSS_LIBRARY = new Set<ChannelSetupStrategyKey>(['genres', 'studios', 'actors', 'directors']);
const CATEGORIES: readonly ChannelBuilderCategory[] = ['content-sources', 'advanced-sources', 'build-options', 'series-ordering', 'limits', 'priority-order'];
const ADJUSTABLE_CONTROLS: readonly ChannelBuilderAdjustableControl[] = ['build-mode', 'combine-mode', 'alternate-copies', 'base-mode', 'base-block', 'variant-type', 'variant-block', 'max-channels', 'min-items'];

export function createChannelBuilderController(input: {
  bridge: LineupDesktopPreloadApi['channelSetup'];
  onStateChanged(): void;
  setTimer?: (callback: () => void, delayMs: number) => ReturnType<typeof globalThis.setTimeout>;
  clearTimer?: (timer: ReturnType<typeof globalThis.setTimeout>) => void;
  createBuildId?: () => string;
}): ChannelBuilderController {
  const setTimer = input.setTimer ?? globalThis.setTimeout;
  const clearTimer = input.clearTimer ?? globalThis.clearTimeout;
  let buildSequence = 0;
  const createBuildId = input.createBuildId ?? (() => `renderer-build-${Date.now().toString(36)}-${String(++buildSequence)}`);
  let state = initialState();
  let generation = 0;
  let debounceTimer: ReturnType<typeof globalThis.setTimeout> | null = null;
  let slowTimer: ReturnType<typeof globalThis.setTimeout> | null = null;
  let activeBuildId: string | null = null;
  let lastProgressRank = -1;
  let lastProgressCurrent = -1;
  let disposed = false;

  const emit = (patch: Partial<ChannelBuilderState>): void => {
    if (disposed) return;
    state = { ...state, ...patch };
    input.onStateChanged();
  };
  const clearTimers = (): void => {
    if (debounceTimer !== null) clearTimer(debounceTimer);
    if (slowTimer !== null) clearTimer(slowTimer);
    debounceTimer = null; slowTimer = null;
  };
  const invalidate = (): void => { generation += 1; clearTimers(); };
  const controller: ChannelBuilderController = {
    getState: () => state,
    async initialize(selectedLibraryIds = []) {
      invalidate();
      const localGeneration = generation;
      const recordResult = await input.bridge.getRecord().catch(() => null);
      if (disposed || localGeneration !== generation) return;
      const record = recordResult?.ok === true ? recordResult.value : null;
      const restored = record?.status === 'ready' ? record.config : null;
      state = {
        ...initialState(),
        record,
        draft: { ...(restored ?? initialDraft()), selectedLibraryIds: [...selectedLibraryIds] },
      };
      input.onStateChanged();
    },
    async setLibraries(selectedLibraryIds) {
      updateDraft({ ...state.draft, selectedLibraryIds: [...selectedLibraryIds] }, 'builder-category-lineup');
      await controller.requestPreview(true);
    },
    apply(action, detail) {
      const strategy = readStrategy(detail);
      const category = readCategory(detail);
      if (action === 'selectCategory' && category !== null) {
        emit({ activeCategory: category, openScopeDropdown: null, openAdjustableControl: null, grabbedPriorityKey: null, focusIntent: `builder-category-${category}` }); return;
      }
      if (strategy !== null && action === 'toggleStrategy') {
        const current = state.draft.strategyConfig[strategy] ?? strategyDefault(strategy);
        updateStrategies(strategy, { ...current, enabled: current.enabled === false }); return;
      }
      if (strategy !== null && action === 'toggleScopeDropdown' && CROSS_LIBRARY.has(strategy)) {
        const opening = state.openScopeDropdown !== strategy;
        emit({ openScopeDropdown: opening ? strategy : null, focusIntent: opening ? `builder-scope-option-${strategy}-per-library` : `builder-${strategy}-scope` }); return;
      }
      if (action === 'selectScope') {
        const selection = readScopeSelection(detail);
        if (selection !== null && CROSS_LIBRARY.has(selection.strategy)) {
          const current = state.draft.strategyConfig[selection.strategy] ?? strategyDefault(selection.strategy);
          updateStrategies(selection.strategy, { ...current, scope: selection.scope });
          emit({ openScopeDropdown: null, focusIntent: `builder-${selection.strategy}-scope` });
        }
        return;
      }
      if (action === 'toggleAdjustable') {
        const control = readAdjustableControl(detail);
        if (control !== null && adjustableEnabled(control, state.draft)) {
          const opening = state.openAdjustableControl !== control;
          const currentValue = currentAdjustableValue(control, state.draft); const focusValue = adjustableOptions(control).map(String).includes(currentValue) ? currentValue : String(adjustableOptions(control)[0]);
          emit({ openAdjustableControl: opening ? control : null, openScopeDropdown: null, focusIntent: opening ? `builder-option-${control}-${focusValue}` : `builder-control-${control}` });
        }
        return;
      }
      if (action === 'selectAdjustable') {
        const selection = readAdjustableSelection(detail);
        if (selection !== null && adjustableEnabled(selection.control, state.draft)) {
          updateAdjustable(selection.control, selection.value);
          emit({ openAdjustableControl: null, focusIntent: `builder-control-${selection.control}` });
        }
        return;
      }
      if (action === 'togglePriorityGrab' && strategy !== null && strategyEnabled(strategy, state.draft)) {
        emit({ grabbedPriorityKey: state.grabbedPriorityKey === strategy ? null : strategy, focusIntent: `builder-priority-${strategy}` }); return;
      }
      if (action === 'resetGuideOrder') { resetGuideOrder(); return; }
      if (action === 'toggleAlternates') {
        const expansion = { ...expansionDraft(state.draft), addAlternateLineups: !expansionDraft(state.draft).addAlternateLineups };
        updateDraft({ ...state.draft, channelExpansion: expansion }); return;
      }
      if (action === 'confirmReplace') emit({ replaceConfirmed: !state.replaceConfirmed, focusIntent: 'builder-replace-confirm' });
      if (action === 'retryPreview') void controller.requestPreview(true);
      if (action === 'retryReview') void controller.requestReview();
      if (action === 'cancelBuild') void controller.cancelBuild();
    },
    async requestPreview(immediate = false) {
      invalidate();
      const localGeneration = generation;
      if (state.draft.selectedLibraryIds.length === 0 || !hasEnabledStrategy(state.draft)) {
        emit({ phase: 'preview-blocked', preview: null, review: null, safeError: 'Select a library and enable at least one strategy.', slow: false });
        return;
      }
      const run = async (): Promise<void> => {
        if (disposed || localGeneration !== generation) return;
        emit({ phase: 'preview-loading', preview: null, review: null, result: null, safeError: null, slow: false });
        slowTimer = setTimer(() => { if (localGeneration === generation) emit({ slow: true }); }, 1200);
        const result = await input.bridge.preview(state.draft).catch(() => null);
        if (slowTimer !== null) clearTimer(slowTimer); slowTimer = null;
        if (disposed || localGeneration !== generation) return;
        if (result?.ok !== true) {
          emit({ phase: 'preview-error', safeError: safeMessage(result?.ok === false ? result.error.message : null), slow: false }); return;
        }
        emit({
          phase: result.value.status === 'ready' ? 'preview-ready' : result.value.status === 'blocked' ? 'preview-blocked' : 'preview-ready',
          preview: result.value, safeError: result.value.message ?? null, slow: result.value.status === 'slow',
        });
      };
      if (immediate) await run();
      else debounceTimer = setTimer(() => { debounceTimer = null; void run(); }, 180);
    },
    async requestReview() {
      if (!['preview-ready', 'review-error', 'error'].includes(state.phase) || state.preview?.status !== 'ready') return false;
      invalidate();
      const localGeneration = generation;
      emit({ phase: 'review-loading', review: null, safeError: null, slow: false });
      slowTimer = setTimer(() => { if (localGeneration === generation) emit({ slow: true }); }, 1200);
      const result = await input.bridge.review(state.draft).catch(() => null);
      if (slowTimer !== null) clearTimer(slowTimer); slowTimer = null;
      if (disposed || localGeneration !== generation) return false;
      if (result?.ok !== true) { emit({ phase: 'review-error', safeError: safeMessage(result?.ok === false ? result.error.message : null), slow: false, focusIntent: 'builder-review-retry' }); return false; }
      emit({ phase: 'review-ready', review: result.value, safeError: null, slow: false, replaceConfirmed: false, focusIntent: state.draft.buildMode === 'replace' ? 'builder-replace-confirm' : 'setup-confirm' });
      return true;
    },
    async build(_existingChannelCount) {
      if (state.phase !== 'review-ready' || state.review === null ||
        (state.draft.buildMode === 'replace' && !state.replaceConfirmed)) return null;
      invalidate();
      const localGeneration = generation;
      const buildId = createBuildId();
      activeBuildId = buildId;
      lastProgressRank = -1; lastProgressCurrent = -1;
      emit({ phase: 'progress', progress: null, result: null, safeError: null, cancelStatus: 'idle', focusIntent: 'setup-progress-cancel' });
      const terminal = await input.bridge.build({ buildId, config: state.draft, confirmReplace: state.draft.buildMode === 'replace' && state.replaceConfirmed }, (progress) => {
        const rank = progressRank(progress.task);
        if (!disposed && localGeneration === generation && activeBuildId === buildId &&
          (rank > lastProgressRank || (rank === lastProgressRank && progress.current >= lastProgressCurrent))) {
          lastProgressRank = rank; lastProgressCurrent = progress.current; emit({ progress });
        }
      }).catch(() => null);
      if (disposed || localGeneration !== generation || activeBuildId !== buildId) return null;
      activeBuildId = null;
      if (terminal?.ok !== true) { emit({ phase: 'error', safeError: safeMessage(terminal?.ok === false ? terminal.error.message : null), focusIntent: 'setup-error-retry' }); return null; }
      emit({ phase: terminal.value.kind === 'failed' ? 'error' : 'result', result: terminal.value, safeError: terminal.value.kind === 'failed' ? safeMessage(terminal.value.error.message) : null, focusIntent: terminal.value.kind === 'failed' ? 'setup-error-retry' : 'setup-done' });
      return terminal.value;
    },
    async cancelBuild() {
      if (activeBuildId === null || state.phase !== 'progress' || state.cancelStatus === 'requesting') return;
      const buildId = activeBuildId;
      emit({ cancelStatus: 'requesting' });
      const result = await input.bridge.cancelBuild({ buildId }).catch(() => null);
      if (disposed || activeBuildId !== buildId || state.phase !== 'progress') return;
      emit({ cancelStatus: result?.ok === true ? result.value.status : 'not-active' });
    },
    handlePriorityDirection(direction) {
      if (state.grabbedPriorityKey === null) return false;
      moveActiveStrategy(state.grabbedPriorityKey, direction === 'up' ? -1 : 1); return true;
    },
    dismissTransient() {
      if (state.grabbedPriorityKey !== null) { emit({ grabbedPriorityKey: null, focusIntent: `builder-priority-${state.grabbedPriorityKey}` }); return true; }
      if (state.openAdjustableControl !== null) { emit({ openAdjustableControl: null, focusIntent: `builder-control-${state.openAdjustableControl}` }); return true; }
      if (state.openScopeDropdown !== null) { emit({ openScopeDropdown: null, focusIntent: `builder-${state.openScopeDropdown}-scope` }); return true; }
      return false;
    },
    invalidate() {
      const buildId = activeBuildId;
      invalidate(); activeBuildId = null;
      if (buildId !== null) void input.bridge.cancelBuild({ buildId }).catch(() => undefined);
      emit({ phase: 'idle', preview: null, review: null, progress: null, result: null, safeError: null, slow: false, cancelStatus: 'idle' });
    },
    dispose() {
      const buildId = activeBuildId;
      disposed = true; invalidate(); activeBuildId = null;
      if (buildId !== null) void input.bridge.cancelBuild({ buildId }).catch(() => undefined);
    },
  };
  return controller;

  function updateDraft(draft: ChannelSetupConfigDraft, focusIntent?: string): void {
    emit({ draft, phase: 'preview-loading', preview: null, review: null, result: null, safeError: null, slow: false, replaceConfirmed: false, focusIntent: focusIntent ?? state.focusIntent });
    void controller.requestPreview(false);
  }
  function updateStrategies(strategy: ChannelSetupStrategyKey, value: NonNullable<ChannelSetupConfigDraft['strategyConfig'][ChannelSetupStrategyKey]>): void {
    updateDraft({ ...state.draft, strategyConfig: { ...state.draft.strategyConfig, [strategy]: value } }, `builder-strategy-${strategy}`);
  }
  function moveActiveStrategy(strategy: ChannelSetupStrategyKey, delta: number): void {
    const active = orderedStrategies(state.draft).filter((key) => strategyEnabled(key, state.draft));
    const index = active.indexOf(strategy); const target = clamp(index + delta, 0, active.length - 1);
    if (index < 0 || index === target) { emit({ focusIntent: `builder-priority-${strategy}` }); return; }
    const other = active[target]!;
    const strategyConfig = { ...state.draft.strategyConfig };
    const current = strategyConfig[strategy] ?? strategyDefault(strategy); const swapped = strategyConfig[other] ?? strategyDefault(other);
    strategyConfig[strategy] = { ...current, priority: swapped.priority };
    strategyConfig[other] = { ...swapped, priority: current.priority };
    updateDraft({ ...state.draft, strategyConfig }, `builder-priority-${strategy}`);
    emit({ grabbedPriorityKey: strategy, focusIntent: `builder-priority-${strategy}` });
  }
  function resetGuideOrder(): void {
    const strategyConfig = { ...state.draft.strategyConfig };
    STRATEGIES.forEach((key, index) => { strategyConfig[key] = { ...(strategyConfig[key] ?? strategyDefault(key)), priority: index + 1 }; });
    updateDraft({ ...state.draft, strategyConfig }, 'builder-guide-reset'); emit({ grabbedPriorityKey: null });
  }
  function updateAdjustable(control: ChannelBuilderAdjustableControl, rawValue: string): void {
    if (!adjustableOptions(control).map(String).includes(rawValue)) return;
    const numeric = Number(rawValue); const expansion = expansionDraft(state.draft); const ordering = seriesDraft(state.draft);
    if (control === 'build-mode') updateDraft({ ...state.draft, buildMode: rawValue as ChannelSetupConfigDraft['buildMode'] });
    else if (control === 'combine-mode') updateDraft({ ...state.draft, actorStudioCombineMode: rawValue as ChannelSetupConfigDraft['actorStudioCombineMode'] });
    else if (control === 'alternate-copies') updateDraft({ ...state.draft, channelExpansion: { ...expansion, alternateLineupCopies: numeric } });
    else if (control === 'base-mode') updateDraft({ ...state.draft, seriesOrdering: { ...ordering, basePlaybackMode: rawValue as typeof ordering.basePlaybackMode } });
    else if (control === 'base-block') updateDraft({ ...state.draft, seriesOrdering: { ...ordering, baseBlockSize: numeric } });
    else if (control === 'variant-type') updateDraft({ ...state.draft, channelExpansion: { ...expansion, variantType: rawValue as typeof expansion.variantType } });
    else if (control === 'variant-block') updateDraft({ ...state.draft, channelExpansion: { ...expansion, variantBlockSize: numeric } });
    else if (control === 'max-channels') updateDraft({ ...state.draft, maxChannels: numeric });
    else updateDraft({ ...state.draft, minItemsPerChannel: numeric });
  }
}

export function readChannelBuilderAction(value: string | undefined): ChannelBuilderAction | null {
  return CHANNEL_BUILDER_ACTIONS.includes(value as ChannelBuilderAction) ? value as ChannelBuilderAction : null;
}
function initialState(): ChannelBuilderState {
  return { phase: 'idle', draft: initialDraft(), activeCategory: 'content-sources', preview: null, review: null, progress: null, result: null, record: null, safeError: null, slow: false, replaceConfirmed: false, cancelStatus: 'idle', openScopeDropdown: null, openAdjustableControl: null, grabbedPriorityKey: null, focusIntent: null };
}
function initialDraft(): ChannelSetupConfigDraft {
  return {
    selectedLibraryIds: [], maxChannels: 100, buildMode: 'append',
    strategyConfig: Object.fromEntries(STRATEGIES.map((key, index) => [key, { enabled: true, priority: index + 1, scope: 'per-library' }])),
    channelExpansion: { addAlternateLineups: false, alternateLineupCopies: 1, variantType: 'none', variantBlockSize: 2 },
    seriesOrdering: { basePlaybackMode: 'shuffle', baseBlockSize: 2 }, actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
  };
}
function strategyDefault(key: ChannelSetupStrategyKey) { return { enabled: true, priority: STRATEGIES.indexOf(key) + 1, scope: 'per-library' as const }; }
function expansionDraft(draft: ChannelSetupConfigDraft) { return { addAlternateLineups: false, alternateLineupCopies: 1, variantType: 'none' as const, variantBlockSize: 2, ...draft.channelExpansion }; }
function seriesDraft(draft: ChannelSetupConfigDraft) { return { basePlaybackMode: 'shuffle' as const, baseBlockSize: 2, ...draft.seriesOrdering }; }
function hasEnabledStrategy(draft: ChannelSetupConfigDraft): boolean { return STRATEGIES.some((key) => draft.strategyConfig[key]?.enabled !== false); }
function readStrategy(value: string | undefined): ChannelSetupStrategyKey | null { return STRATEGIES.includes(value as ChannelSetupStrategyKey) ? value as ChannelSetupStrategyKey : null; }
function readCategory(value: string | undefined): ChannelBuilderCategory | null { return CATEGORIES.includes(value as ChannelBuilderCategory) ? value as ChannelBuilderCategory : null; }
function readAdjustableControl(value: string | undefined): ChannelBuilderAdjustableControl | null { return ADJUSTABLE_CONTROLS.includes(value as ChannelBuilderAdjustableControl) ? value as ChannelBuilderAdjustableControl : null; }
function readAdjustableSelection(value: string | undefined): { control: ChannelBuilderAdjustableControl; value: string } | null { const [key, selected, extra] = value?.split(':') ?? []; const control = readAdjustableControl(key); return control !== null && selected !== undefined && extra === undefined ? { control, value: selected } : null; }
function readScopeSelection(value: string | undefined): { strategy: ChannelSetupStrategyKey; scope: 'per-library' | 'cross-library' } | null { const [key, scope, extra] = value?.split(':') ?? []; const strategy = readStrategy(key); return strategy !== null && extra === undefined && (scope === 'per-library' || scope === 'cross-library') ? { strategy, scope } : null; }
function strategyEnabled(key: ChannelSetupStrategyKey, draft: ChannelSetupConfigDraft): boolean { return draft.strategyConfig[key]?.enabled !== false; }
function orderedStrategies(draft: ChannelSetupConfigDraft): ChannelSetupStrategyKey[] { return [...STRATEGIES].sort((a, b) => (draft.strategyConfig[a]?.priority ?? strategyDefault(a).priority) - (draft.strategyConfig[b]?.priority ?? strategyDefault(b).priority)); }
function adjustableOptions(control: ChannelBuilderAdjustableControl): readonly (string | number)[] { if (control === 'build-mode') return ['replace', 'append', 'merge']; if (control === 'combine-mode') return ['separate', 'combined']; if (control === 'alternate-copies') return [1, 2, 3]; if (control === 'base-mode') return ['shuffle', 'sequential', 'block']; if (control === 'variant-type') return ['none', 'sequential', 'block']; if (control === 'base-block' || control === 'variant-block') return [2, 3, 4, 5]; if (control === 'max-channels') return [50, 100, 150, 200, 300, 400, 500]; return [1, 5, 10, 20, 50]; }
function adjustableEnabled(control: ChannelBuilderAdjustableControl, draft: ChannelSetupConfigDraft): boolean { if (control === 'alternate-copies') return expansionDraft(draft).addAlternateLineups; if (control === 'base-block') return seriesDraft(draft).basePlaybackMode === 'block'; if (control === 'variant-block') return expansionDraft(draft).variantType === 'block'; return true; }
function currentAdjustableValue(control: ChannelBuilderAdjustableControl, draft: ChannelSetupConfigDraft): string { if (control === 'build-mode') return draft.buildMode; if (control === 'combine-mode') return draft.actorStudioCombineMode; if (control === 'alternate-copies') return String(expansionDraft(draft).alternateLineupCopies); if (control === 'base-mode') return seriesDraft(draft).basePlaybackMode; if (control === 'base-block') return String(seriesDraft(draft).baseBlockSize); if (control === 'variant-type') return expansionDraft(draft).variantType; if (control === 'variant-block') return String(expansionDraft(draft).variantBlockSize); if (control === 'max-channels') return String(draft.maxChannels); return String(draft.minItemsPerChannel); }
function clamp(value: number, minimum: number, maximum: number): number { return Math.max(minimum, Math.min(maximum, value)); }
function progressRank(task: ChannelSetupBuildProgress['task']): number { return ['fetch_playlists', 'fetch_collections', 'fetch_facets', 'scan_library_items', 'build_pending', 'create_channels', 'apply_channels', 'refresh_guide', 'done'].indexOf(task); }
function safeMessage(value: string | null): string { return typeof value === 'string' && value.length > 0 && value.length <= 160 && !/https?:|token|header|[A-Za-z]:[\\/]/iu.test(value) ? value : 'Channel setup could not continue. Try again.'; }
