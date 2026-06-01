import type { ChannelSetupSummary } from '../../contracts/channel.js';
import type { ChannelRuntimeRendererState } from '../channelRuntimeState.js';
import type {
  ChannelSetupActionId,
  ChannelSetupDraftState,
  ChannelSetupStepViewModel,
  ChannelSetupSummaryViewModel,
} from '../settingsSetup.js';

export interface ChannelSetupLiveSelectionViewModel {
  sourceName: string;
  sourceType: 'movie' | 'show';
  contentCount: number | null;
  loadedItemCount: number;
}

export interface ChannelSetupCommitAvailabilityViewModel {
  append: boolean;
  replace: boolean;
  confirmReplace: boolean;
}

export type ChannelSetupFlowStageId = 'library' | 'strategy' | 'review' | 'result';

export interface ChannelSetupFlowStageViewModel {
  id: ChannelSetupFlowStageId;
  label: string;
  detail: string;
  state: 'complete' | 'current' | 'pending' | 'blocked';
}

export interface ChannelSetupStrategyOptionViewModel {
  id: string;
  label: string;
  detail: string;
  value: string;
  selected: boolean;
  disabled: boolean;
  actionId: ChannelSetupActionId;
  focusId: string;
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
  stageLabel: string;
  statusText: string;
  detailText: string;
  buildMode: ChannelSetupDraftState['buildMode'];
  stages: readonly ChannelSetupFlowStageViewModel[];
  library: {
    title: string;
    detail: string;
    marker: string;
    selected: boolean;
    countLabel: string;
  };
  strategyOptions: readonly ChannelSetupStrategyOptionViewModel[];
  reviewRows: readonly ChannelSetupReviewRowViewModel[];
  result: ChannelSetupResultViewModel;
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

export function createLiveChannelSetupSteps(
  _state: ChannelSetupDraftState,
  persistedSummary: ChannelRuntimeRendererState['summary'],
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): readonly ChannelSetupStepViewModel[] {
  return createChannelSetupFlow(persistedSummary, undefined, liveSelection).stages.map((stage) => ({
    id: stage.id === 'library' ? 'source' : stage.id === 'strategy' ? 'channels' : 'review',
    label: stage.label,
    detail: stage.detail,
    state: stage.state === 'complete' ? 'complete' : stage.state === 'pending' ? 'pending' : 'current',
  }));
}

export function createLiveChannelSetupMessages(
  channelRuntime: ChannelRuntimeRendererState | undefined,
  persistedSummary: ChannelRuntimeRendererState['summary'],
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): readonly string[] {
  if (channelRuntime?.pending) {
    return [channelRuntime.commitMode === 'replace' ? 'Replacing saved channels...' : 'Creating channels...'];
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

export function createChannelSetupCommitAvailability(
  channelRuntime: ChannelRuntimeRendererState | undefined,
  persistedSummary: ChannelRuntimeRendererState['summary'],
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): ChannelSetupCommitAvailabilityViewModel {
  const statusLoaded = persistedSummary !== null;
  const canAct = channelRuntime !== undefined && statusLoaded && !channelRuntime.pending && liveSelection !== null;
  const hasPersistedChannels = (persistedSummary?.channelCount ?? 0) > 0;
  return {
    append: canAct,
    replace: canAct && hasPersistedChannels,
    confirmReplace: canAct && hasPersistedChannels && channelRuntime.confirmReplace,
  };
}

export function createChannelSetupFlow(
  persistedSummary: ChannelSetupSummary | null,
  channelRuntime: ChannelRuntimeRendererState | undefined,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
  state?: ChannelSetupDraftState,
): ChannelSetupFlowViewModel {
  const hasLibrary = liveSelection !== null;
  const hasPersistedChannels = (persistedSummary?.channelCount ?? 0) > 0;
  const buildMode = state?.buildMode ?? 'append';
  const pending = channelRuntime?.pending === true;
  const errorText = channelRuntime?.errorText ?? null;
  const confirmReplace = channelRuntime?.confirmReplace === true;
  const stageLabel = pending ? 'Step 4 of 4' : hasLibrary ? 'Step 3 of 4' : 'Step 1 of 4';
  const statusText = pending
    ? channelRuntime?.commitMode === 'replace' ? 'Replacing saved channels...' : 'Creating channels...'
    : errorText ?? (hasLibrary ? 'Review changes before building.' : 'Select the library to include.');
  const detailText = hasLibrary
    ? 'Lineup Desktop will build a channel from the selected library using the current setup strategy.'
    : 'Choose a movie or show library section after Plex sign-in, profile, and server selection.';
  const result = createResult(persistedSummary, pending, errorText);

  return {
    stageLabel,
    statusText,
    detailText,
    buildMode,
    stages: [
      {
        id: 'library',
        label: 'Choose library',
        detail: hasLibrary
          ? `Selected ${libraryTypeLabel(liveSelection.sourceType).toLowerCase()}: ${liveSelection.sourceName}.`
          : 'Select one movie or show library from this setup screen.',
        state: hasLibrary ? 'complete' : 'current',
      },
      {
        id: 'strategy',
        label: 'Configure channels',
        detail: hasLibrary
          ? 'Recently added source is enabled with Desktop-safe limits.'
          : 'Strategy controls unlock after a library is selected.',
        state: hasLibrary ? 'complete' : 'pending',
      },
      {
        id: 'review',
        label: 'Review changes',
        detail: hasLibrary
          ? hasPersistedChannels
            ? 'Append to saved channels or choose replacement review.'
            : 'Create the first saved channel lineup from this library.'
          : 'Review is blocked until a library is selected.',
        state: errorText !== null ? 'blocked' : hasLibrary ? 'current' : 'pending',
      },
      {
        id: 'result',
        label: 'Build result',
        detail: result.detail,
        state: pending ? 'current' : errorText !== null || hasPersistedChannels ? 'complete' : 'pending',
      },
    ],
    library: createLibraryPanel(liveSelection),
    strategyOptions: createStrategyOptions(hasLibrary, hasPersistedChannels, buildMode),
    reviewRows: createReviewRows(persistedSummary, liveSelection, confirmReplace, buildMode),
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

function createStrategyOptions(
  hasLibrary: boolean,
  hasPersistedChannels: boolean,
  buildMode: ChannelSetupDraftState['buildMode'],
): readonly ChannelSetupStrategyOptionViewModel[] {
  return [
    {
      id: 'recently-added',
      actionId: 'selectRecentlyAddedSource',
      focusId: 'channel-strategy-source-recently-added',
      label: 'Recently added',
      detail: 'Create one deterministic channel from the selected library.',
      value: hasLibrary ? 'On' : 'Waiting',
      selected: hasLibrary,
      disabled: !hasLibrary,
    },
    {
      id: 'build-mode-append',
      actionId: 'selectAppendBuildMode',
      focusId: 'channel-strategy-build-append',
      label: 'Append',
      detail: 'Add the selected library as a new channel while keeping saved channels.',
      value: buildMode === 'append' ? 'Selected' : 'Available',
      selected: buildMode === 'append',
      disabled: !hasLibrary,
    },
    {
      id: 'build-mode-replace',
      actionId: 'selectReplaceBuildMode',
      focusId: 'channel-strategy-build-replace',
      label: 'Replace',
      detail: 'Review replacing saved channels; confirmation is separate before overwrite.',
      value: hasPersistedChannels ? (buildMode === 'replace' ? 'Selected' : 'Available') : 'Needs saved channels',
      selected: buildMode === 'replace',
      disabled: !hasLibrary || !hasPersistedChannels,
    },
  ];
}

function createReviewRows(
  persistedSummary: ChannelSetupSummary | null,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
  confirmReplace: boolean,
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
      value: confirmReplace ? 'Confirmation required' : savedCount > 0 ? 'Available after review' : 'Not available on first run',
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
