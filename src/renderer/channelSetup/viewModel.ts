import type {
  ChannelSetupOperation,
  ChannelSetupSummary,
  ChannelSetupWarning,
} from '../../contracts/channel.js';
import {
  CHANNEL_BUILDER_MIXED_SCOPE_STRATEGIES,
  CHANNEL_BUILDER_STRATEGY_KEYS,
} from '../../domain/channelBuilder/constants.js';
import type { NormalizedChannelSetupConfig } from '../../domain/channelBuilder/types.js';
import type { ChannelRuntimeRendererState } from '../channelRuntimeState.js';
import type {
  ChannelSetupDraftState,
  ChannelSetupSummaryViewModel,
} from '../settingsSetup.js';

export interface ChannelSetupLiveSelectionViewModel {
  sourceName: string;
  sourceType: 'movie' | 'show';
  contentCount: number | null;
  loadedItemCount: number;
}

export interface ChannelSetupReviewRowViewModel {
  label: string;
  value: string;
  detail: string;
}

export interface ChannelSetupResultViewModel {
  title: string;
  detail: string;
  tone: 'ready' | 'attention' | 'loading';
}

export interface ChannelSetupFlowViewModel {
  buildMode: ChannelSetupDraftState['buildMode'];
  library: {
    title: string;
    detail: string;
    marker: string;
    selected: boolean;
    countLabel: string;
  };
  reviewRows: readonly ChannelSetupReviewRowViewModel[];
  result: ChannelSetupResultViewModel;
}

export interface ChannelSetupProgressViewModel {
  kind: 'idle' | 'review' | 'apply';
  state: 'idle' | NonNullable<ChannelRuntimeRendererState['operation']>['state'];
  phase: NonNullable<ChannelRuntimeRendererState['operation']>['phase'] | null;
  progress: Readonly<{ completed: number; total: number | null }>;
  pending: boolean;
  statusText: string;
  canCancel: boolean;
}

export interface ChannelBuilderReviewViewModel {
  status: 'unavailable' | 'ready' | 'slow' | 'blocked';
  counts: Readonly<{ created: number; removed: number; unchanged: number }>;
  samples: Readonly<{ created: readonly string[]; removed: readonly string[]; unchanged: readonly string[] }>;
  warnings: readonly string[];
  reachedCap: boolean;
  canApply: boolean;
}

export function createChannelBuilderReview(
  operation: ChannelSetupOperation | null,
): ChannelBuilderReviewViewModel {
  if (operation?.kind !== 'review' || operation.state !== 'review-ready') {
    return {
      status: 'unavailable',
      counts: { created: 0, removed: 0, unchanged: 0 },
      samples: { created: [], removed: [], unchanged: [] },
      warnings: [],
      reachedCap: false,
      canApply: false,
    };
  }
  return {
    status: operation.result.status,
    counts: operation.result.diff.summary,
    samples: operation.result.diff.samples,
    warnings: operation.result.warnings.map(formatBuilderWarning),
    reachedCap: operation.result.reachedCap,
    canApply: operation.result.planId !== null && operation.result.status !== 'blocked',
  };
}

export function createChannelBuilderConfigRows(
  config: NormalizedChannelSetupConfig,
): readonly Readonly<{
  key: string;
  label: string;
  enabled: boolean;
  priority: number;
  scope: 'per-library' | 'cross-library';
  scopeEditable: boolean;
}>[] {
  const mixedScope = new Set<string>(CHANNEL_BUILDER_MIXED_SCOPE_STRATEGIES);
  return CHANNEL_BUILDER_STRATEGY_KEYS.map((key) => ({
    key,
    label: strategyLabel(key),
    enabled: config.strategyConfig[key].enabled,
    priority: config.strategyConfig[key].priority,
    scope: config.strategyConfig[key].scope,
    scopeEditable: mixedScope.has(key),
  }));
}

function formatBuilderWarning(warning: ChannelSetupWarning): string {
  const count = warning.affectedCount === null ? '' : ` (${String(warning.affectedCount)})`;
  switch (warning.code) {
    case 'FACET_UNAVAILABLE': return `Some channel sources are unavailable${count}.`;
    case 'FACET_PARTIAL_FAILURE': return `Some channel sources could not be fully loaded${count}.`;
    case 'FACET_DISCOVERY_TIMEOUT': return `Channel source discovery timed out${count}.`;
    case 'FACET_EMPTY': return `Some channel sources contained no eligible items${count}.`;
    case 'FACET_CAP_REACHED': return `Channel source discovery reached its safety limit${count}.`;
    case 'FACET_MALFORMED_ENTRIES_OMITTED': return `Invalid channel source entries were omitted${count}.`;
    case 'TV_PEOPLE_METADATA_INCOMPLETE': return `Some TV cast or director metadata is incomplete${count}.`;
    case 'EXISTING_SOURCE_UNMATCHABLE':
      return 'Some existing channels can be retained but cannot be matched or updated by Channel Builder.';
    case 'MIN_ITEMS_SKIPPED': return `Channels below the minimum item count were skipped${count}.`;
    case 'MAX_CHANNELS_REACHED': return `The configured maximum channel count was reached${count}.`;
    case 'PLAN_EMPTY': return 'No eligible channels were found for this configuration.';
    case 'MATERIALIZATION_SKIPPED': return `Channels unavailable during preparation were skipped${count}.`;
    case 'GUIDE_REFRESH_FAILED': return 'Channels were saved, but Guide refresh did not complete.';
  }
}

function strategyLabel(key: (typeof CHANNEL_BUILDER_STRATEGY_KEYS)[number]): string {
  if (key === 'recentlyAdded') return 'Recently added';
  return `${key.charAt(0).toUpperCase()}${key.slice(1)}`;
}

export function createChannelSetupProgress(
  runtime: ChannelRuntimeRendererState | undefined,
): ChannelSetupProgressViewModel {
  const operation = runtime?.operation ?? null;
  if (operation === null) {
    return {
      kind: 'idle',
      state: 'idle',
      phase: null,
      progress: { completed: 0, total: null },
      pending: runtime?.pending === true,
      statusText: runtime?.statusText ?? 'Channel setup status not loaded',
      canCancel: false,
    };
  }
  const canCancel =
    (operation.state === 'queued' || operation.state === 'running') &&
    (operation.kind === 'review' || operation.phase === 'materialize');
  return {
    kind: operation.kind,
    state: operation.state,
    phase: operation.phase,
    progress: operation.progress,
    pending: runtime?.pending === true,
    statusText: runtime?.statusText ?? 'Channel setup status not loaded',
    canCancel,
  };
}

const UNAVAILABLE_CHANNEL_SETUP_SUMMARY = {
  sourceName: 'Persisted channel status unavailable',
  enabledChannelCount: 0,
  totalChannelCount: 0,
  totalBlockCount: 0,
  readyForPreview: false,
} as const satisfies ChannelSetupSummaryViewModel;

export function createLiveChannelSetupSummary(
  persistedSummary: ChannelRuntimeRendererState['summary'],
  selectedLibraryItemCount: number,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): ChannelSetupSummaryViewModel {
  if (liveSelection !== null) {
    return {
      sourceName: liveSelection.sourceName,
      enabledChannelCount: 1,
      totalChannelCount: 1,
      totalBlockCount: selectedLibraryCount(liveSelection),
      readyForPreview: true,
    };
  }
  if (persistedSummary === null) {
    return UNAVAILABLE_CHANNEL_SETUP_SUMMARY;
  }
  return {
    sourceName: 'No library selected',
    enabledChannelCount: 0,
    totalChannelCount: 0,
    totalBlockCount: selectedLibraryItemCount,
    readyForPreview: false,
  };
}

export function createLiveChannelSetupMessages(
  channelRuntime: ChannelRuntimeRendererState | undefined,
  persistedSummary: ChannelRuntimeRendererState['summary'],
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): readonly string[] {
  if (channelRuntime?.pending) {
    return [channelRuntime.statusText];
  }
  if (channelRuntime?.errorText !== null && channelRuntime?.errorText !== undefined) {
    return [channelRuntime.errorText];
  }
  if (liveSelection !== null) {
    return (persistedSummary?.channelCount ?? 0) > 0
      ? ['Selected library is ready. Review the strategy, then append it to saved channels or replace the lineup.']
      : ['Selected library is ready. Review the strategy, then create channels from this library to continue.'];
  }
  if ((persistedSummary?.channelCount ?? 0) > 0) {
    return ['Saved channels are ready for recovery. Choose a movie or show library section to add more channels.'];
  }
  return ['Choose a movie or show library section before saving channels. Selecting an individual media item only opens metadata preview.'];
}

export function createChannelSetupFlow(
  persistedSummary: ChannelSetupSummary | null,
  channelRuntime: ChannelRuntimeRendererState | undefined,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
  state?: ChannelSetupDraftState,
): ChannelSetupFlowViewModel {
  const buildMode = state?.buildMode ?? 'append';
  const pending = channelRuntime?.pending === true;
  const errorText = channelRuntime?.errorText ?? null;
  const result = createResult(persistedSummary, pending, errorText);

  return {
    buildMode,
    library: createLibraryPanel(liveSelection),
    reviewRows: createReviewRows(persistedSummary, liveSelection, buildMode),
    result,
  };
}

function createLibraryPanel(
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): ChannelSetupFlowViewModel['library'] {
  if (liveSelection === null) {
    return {
      title: 'No library selected',
      detail: 'Open libraries and choose a movie or show section. Media item previews do not create channels.',
      marker: '--',
      selected: false,
      countLabel: 'Waiting for library selection',
    };
  }
  return {
    title: liveSelection.sourceName,
    detail: `${libraryTypeLabel(liveSelection.sourceType)} source selected for channel creation.`,
    marker: liveSelection.sourceType === 'movie' ? 'MOV' : 'TV',
    selected: true,
    countLabel: formatLibraryCount(liveSelection),
  };
}

function createReviewRows(
  persistedSummary: ChannelSetupSummary | null,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
  buildMode: ChannelSetupDraftState['buildMode'],
): readonly ChannelSetupReviewRowViewModel[] {
  const savedCount = persistedSummary?.channelCount ?? 0;
  return [
    {
      label: 'Selected source',
      value: liveSelection?.sourceName ?? 'No library selected',
      detail: liveSelection === null ? 'Choose a library before building.' : formatLibraryCount(liveSelection),
    },
    {
      label: 'Saved lineup',
      value: savedCount === 0 ? 'No saved channels' : `${String(savedCount)} saved channels`,
      detail: formatPersistedDetail(persistedSummary),
    },
    {
      label: 'Build mode',
      value: buildMode === 'replace' ? 'Replace saved lineup' : 'Append to saved lineup',
      detail: buildMode === 'replace'
        ? 'Replacement still requires the explicit confirm step returned by setup review.'
        : 'The selected library will be added without overwriting saved channels.',
    },
    {
      label: 'Replacement',
      value: buildMode === 'replace' && savedCount > 0 ? 'Required during apply' : 'Not required',
      detail: savedCount > 0
        ? 'Replacement keeps a separate confirm step before saved channels are overwritten.'
        : 'Create channels first; replacement appears after persisted recovery.',
    },
  ];
}

function createResult(
  persistedSummary: ChannelSetupSummary | null,
  pending: boolean,
  errorText: string | null,
): ChannelSetupResultViewModel {
  if (pending) {
    return {
      title: 'Build in progress',
      detail: 'Channel setup is applying the selected library.',
      tone: 'loading',
    };
  }
  if (errorText !== null) {
    return {
      title: 'Setup needs attention',
      detail: errorText,
      tone: 'attention',
    };
  }
  if ((persistedSummary?.channelCount ?? 0) > 0) {
    return {
      title: 'Saved channels recovered',
      detail: formatPersistedDetail(persistedSummary),
      tone: 'ready',
    };
  }
  return {
    title: 'No build result yet',
    detail: 'Choose a library and create channels to save a lineup.',
    tone: 'attention',
  };
}

function formatPersistedDetail(summary: ChannelSetupSummary | null): string {
  if (summary === null || summary.channelCount === 0) {
    return 'No persisted channels recovered.';
  }
  const current = summary.currentChannelNumber === null
    ? 'No current channel'
    : `Current channel ${String(summary.currentChannelNumber)}`;
  return `${String(summary.channelCount)} persisted channels; ${current}.`;
}

function selectedLibraryCount(liveSelection: ChannelSetupLiveSelectionViewModel): number {
  return liveSelection.loadedItemCount > 0
    ? liveSelection.loadedItemCount
    : liveSelection.contentCount ?? 0;
}

function formatLibraryCount(liveSelection: ChannelSetupLiveSelectionViewModel): string {
  const count = selectedLibraryCount(liveSelection);
  const noun = liveSelection.sourceType === 'movie' ? 'movies' : 'series';
  return count > 0 ? `${String(count)} known ${noun}` : `${libraryTypeLabel(liveSelection.sourceType)} count unavailable`;
}

function libraryTypeLabel(type: ChannelSetupLiveSelectionViewModel['sourceType']): string {
  return type === 'movie' ? 'Movie library' : 'Show library';
}
