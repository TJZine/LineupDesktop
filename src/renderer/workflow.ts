import { setRoute, type AppRouteId, type RouteState } from './navigation.js';
import {
  formatChannelSetupStatus,
  type ChannelRuntimeRendererState,
} from './channelRuntimeState.js';
import {
  applyEpgAction,
  createEpgGuideView,
  createEpgState,
  DEFAULT_EPG_PRESENTATION_SOURCE,
  type EpgActionId,
  type EpgGuideViewModel,
  type EpgPresentationSource,
  type EpgState,
} from './epg.js';
import {
  applyChannelSetupAction,
  applySettingsAction,
  applySupportBundleExportStatus,
  createChannelSetupDraftState,
  createSettingsDraftState,
  createSettingsSections,
  type ChannelDraftViewModel,
  type ChannelSetupActionId,
  type ChannelSetupDraftState,
  type ChannelSetupStepViewModel,
  type ChannelSetupSummaryViewModel,
  type SettingsActionId,
  type SettingsDraftState,
  type SettingsSectionViewModel,
  type SupportBundleExportStatusViewModel,
} from './settingsSetup.js';
import {
  createChannelSetupCommitAvailability,
  createChannelSetupFlow,
  createLiveChannelSetupMessages,
  createLiveChannelSetupSteps,
  createLiveChannelSetupSummary,
  type ChannelSetupFlowViewModel,
  type ChannelSetupCommitAvailabilityViewModel,
  type ChannelSetupLiveSelectionViewModel,
} from './channelSetup/viewModel.js';

export type { ChannelSetupActionId, SettingsActionId } from './settingsSetup.js';
export type { EpgActionId } from './epg.js';

export type RouteWorkflowActionId =
  | 'openGuide'
  | 'resumePlayer'
  | 'openSettings'
  | 'openChannelSetup'
  | 'reviewLineup'
  | 'confirmSetup';

export type WorkflowStatusTone = 'ready' | 'attention' | 'draft';

export interface RouteActionViewModel {
  id: RouteWorkflowActionId;
  label: string;
  targetRoute: AppRouteId;
  statusText: string;
}

export interface ProgramSummaryViewModel {
  title: string;
  subtitle: string;
  channelName: string;
  startsAtMs: number | null;
  endsAtMs: number | null;
}

export interface ChannelSummaryViewModel {
  id: string;
  number: string;
  name: string;
  currentTitle: string;
  nextTitle: string;
}

export interface SettingsSummaryViewModel {
  libraryName: string;
  channelCount: number;
  playbackMode: string;
  setupState: string;
  recoveryDetail: string;
  sections: readonly SettingsSectionViewModel[];
}

export interface RouteWorkflowViewModel {
  route: AppRouteId;
  title: string;
  kicker: string;
  statusText: string;
  tone: WorkflowStatusTone;
  primaryText: string;
  secondaryText: string;
  currentProgram: ProgramSummaryViewModel;
  channels: readonly ChannelSummaryViewModel[];
  guide: EpgGuideViewModel;
  settings: SettingsSummaryViewModel;
  channelDrafts: readonly ChannelDraftViewModel[];
  channelSetupSummary: ChannelSetupSummaryViewModel;
  setupSteps: readonly ChannelSetupStepViewModel[];
  setupValidationMessages: readonly string[];
  channelSetupCommitAvailability: ChannelSetupCommitAvailabilityViewModel;
  channelSetupFlow: ChannelSetupFlowViewModel;
  actions: readonly RouteActionViewModel[];
}

export interface WorkflowState {
  routeState: RouteState;
  lastActionId: RouteWorkflowActionId | null;
  lastActionRoute: AppRouteId | null;
  settingsDraft: SettingsDraftState;
  channelSetupDraft: ChannelSetupDraftState;
  epg: EpgState;
  guidePresentation: EpgPresentationSource;
}

const ROUTE_ACTIONS = {
  player: [
    {
      id: 'openGuide',
      label: 'Open guide',
      targetRoute: 'guide',
      statusText: 'Guide opened from the player.',
    },
    {
      id: 'openSettings',
      label: 'Settings',
      targetRoute: 'settings',
      statusText: 'Settings opened from the player.',
    },
  ],
  guide: [
    {
      id: 'resumePlayer',
      label: 'Watch now',
      targetRoute: 'player',
      statusText: 'Player focused on the highlighted program.',
    },
    {
      id: 'openChannelSetup',
      label: 'Set up Plex',
      targetRoute: 'channelSetup',
      statusText: 'Plex onboarding opened from the guide.',
    },
  ],
  settings: [
    {
      id: 'openChannelSetup',
      label: 'Plex setup',
      targetRoute: 'channelSetup',
      statusText: 'Plex onboarding opened from settings.',
    },
    {
      id: 'resumePlayer',
      label: 'Back to player',
      targetRoute: 'player',
      statusText: 'Returned to player from settings.',
    },
  ],
  channelSetup: [],
} as const satisfies Record<AppRouteId, readonly RouteActionViewModel[]>;

const ROUTE_COPY = {
  player: {
    title: 'Player',
    kicker: 'Now playing',
    tone: 'ready',
    primaryText: 'Current program is cued on the active channel.',
    secondaryText: 'Player chrome, OSD, mini guide, badge, and options are available on the player route.',
    defaultStatus: 'Player shell ready with renderer-safe data.',
  },
  guide: {
    title: 'Guide',
    kicker: 'Tonight',
    tone: 'ready',
    primaryText: 'Channels are available in the guide shell.',
    secondaryText: 'Guide rows prefer channel number, name, and program text over category color cues.',
    defaultStatus: 'Guide shell showing renderer-safe lineup data.',
  },
  settings: {
    title: 'Settings',
    kicker: 'Desktop preferences',
    tone: 'draft',
    primaryText: 'Persisted channel recovery status is shown after the app reports it.',
    secondaryText: 'Local display preferences apply to this renderer session; channel data is not inferred from setup drafts.',
    defaultStatus: 'Settings shell is local-only and not persisted.',
  },
  channelSetup: {
    title: 'Channel setup',
    kicker: 'Plex setup',
    tone: 'attention',
    primaryText: 'Connect Plex, choose a profile and server, then browse your library.',
    secondaryText: 'Only renderer-safe local or injected account, server, library, media, and setup summaries are shown here.',
    defaultStatus: 'Plex setup is ready for sign-in or server discovery.',
  },
} as const satisfies Record<
  AppRouteId,
  {
    title: string;
    kicker: string;
    tone: WorkflowStatusTone;
    primaryText: string;
    secondaryText: string;
    defaultStatus: string;
  }
>;

export function createWorkflowState(
  initialRoute: AppRouteId = 'player',
  guidePresentation: EpgPresentationSource = DEFAULT_EPG_PRESENTATION_SOURCE,
): WorkflowState {
  return {
    routeState: {
      activeRoute: initialRoute,
      previousRoute: null,
    },
    lastActionId: null,
    lastActionRoute: null,
    settingsDraft: createSettingsDraftState(),
    channelSetupDraft: createChannelSetupDraftState(),
    epg: createEpgState(guidePresentation),
    guidePresentation,
  };
}

export function activateWorkflowRoute(state: WorkflowState, route: AppRouteId): WorkflowState {
  return {
    routeState: setRoute(state.routeState, route),
    lastActionId: null,
    lastActionRoute: null,
    settingsDraft: state.settingsDraft,
    channelSetupDraft: state.channelSetupDraft,
    epg: state.epg,
    guidePresentation: state.guidePresentation,
  };
}

export function applyWorkflowAction(
  state: WorkflowState,
  actionId: RouteWorkflowActionId,
): WorkflowState {
  const action = findRouteAction(state.routeState.activeRoute, actionId);
  if (action === null) {
    return state;
  }

  return {
    routeState: setRoute(state.routeState, action.targetRoute),
    lastActionId: action.id,
    lastActionRoute: state.routeState.activeRoute,
    settingsDraft: state.settingsDraft,
    channelSetupDraft: state.channelSetupDraft,
    epg: state.epg,
    guidePresentation: state.guidePresentation,
  };
}

export function getRouteWorkflowView(
  state: WorkflowState,
  channelRuntime?: ChannelRuntimeRendererState,
  liveSelection: ChannelSetupLiveSelectionViewModel | null = null,
): RouteWorkflowViewModel {
  const route = state.routeState.activeRoute;
  const copy = ROUTE_COPY[route];
  const guide = createEpgGuideView(state.epg, state.guidePresentation);
  const guideReady = guide.presentationState === 'ready';
  const currentProgram = guideReady
    ? createCurrentProgramSummary(state.guidePresentation)
    : createGuidePlaceholderProgramSummary(guide);
  const channels = guideReady ? createChannelSummaries(state.guidePresentation) : [];
  const persistedSummary = channelRuntime?.summary ?? null;
  const persistedChannelCount = persistedSummary?.channelCount ?? 0;
  const selectedLibraryItemCount = persistedSummary?.channels.reduce(
    (sum, channel) => sum + channel.itemCount,
    0,
  ) ?? 0;
  const statusText =
    state.lastActionId === null || state.lastActionRoute === null
      ? copy.defaultStatus
      : findActionStatusText(state.lastActionRoute, state.lastActionId) ?? copy.defaultStatus;

  return {
    route,
    title: copy.title,
    kicker: copy.kicker,
    statusText,
    tone: copy.tone,
    primaryText: createPrimaryText(route, copy.primaryText, guide, currentProgram, channels),
    secondaryText: copy.secondaryText,
    currentProgram,
    channels,
    guide,
    settings: {
      libraryName: persistedSummary?.currentChannelName ?? 'No persisted channel library',
      channelCount: persistedChannelCount,
      playbackMode:
        state.settingsDraft.launchMode === 'windowed'
          ? 'Windowed desktop player'
          : 'Fullscreen desktop player',
      setupState: channelRuntime?.pending
        ? 'Loading persisted status'
        : channelRuntime?.errorText ?? formatChannelSetupStatus(persistedSummary),
      recoveryDetail: formatRecoveryDetail(persistedSummary),
      sections: createSettingsSections(state.settingsDraft, persistedSummary),
    },
    channelDrafts: [],
    channelSetupSummary: createLiveChannelSetupSummary(persistedSummary, selectedLibraryItemCount, liveSelection),
    setupSteps: createLiveChannelSetupSteps(state.channelSetupDraft, persistedSummary, liveSelection),
    setupValidationMessages: createLiveChannelSetupMessages(channelRuntime, persistedSummary, liveSelection),
    channelSetupCommitAvailability: createChannelSetupCommitAvailability(
      channelRuntime,
      persistedSummary,
      liveSelection,
    ),
    channelSetupFlow: createChannelSetupFlow(
      persistedSummary,
      channelRuntime,
      liveSelection,
      state.channelSetupDraft,
    ),
    actions: ROUTE_ACTIONS[route],
  };
}

function createCurrentProgramSummary(presentation: EpgPresentationSource): ProgramSummaryViewModel {
  const channel = presentation.channels.find((candidate) => candidate.id === presentation.nowWatching.channelId);
  return {
    title: presentation.nowWatching.title,
    subtitle: presentation.nowWatching.subtitle,
    channelName: channel?.name ?? 'Channel',
    startsAtMs: presentation.nowWatching.startsAtMs,
    endsAtMs: presentation.nowWatching.endsAtMs,
  };
}

function createGuidePlaceholderProgramSummary(
  guide: EpgGuideViewModel,
): ProgramSummaryViewModel {
  return {
    title: guide.state.label,
    subtitle: '',
    channelName: 'Guide',
    startsAtMs: null,
    endsAtMs: null,
  };
}

function createChannelSummaries(presentation: EpgPresentationSource): readonly ChannelSummaryViewModel[] {
  return presentation.channels.map((channel) => ({
    id: channel.id,
    number: channel.number,
    name: channel.name,
    currentTitle: channel.programs[0]?.title ?? 'No current program',
    nextTitle: channel.programs[1]?.title ?? 'No upcoming program',
  }));
}

function createPrimaryText(
  route: AppRouteId,
  defaultPrimaryText: string,
  guide: EpgGuideViewModel,
  currentProgram: ProgramSummaryViewModel,
  channels: readonly ChannelSummaryViewModel[],
): string {
  if (route === 'player') {
    return guide.presentationState === 'ready'
      ? `${currentProgram.title} is cued on ${currentProgram.channelName}.`
      : guidePlaceholderPrimaryText(guide.presentationState, 'player');
  }
  if (route === 'guide') {
    return guide.presentationState === 'ready'
      ? `${String(channels.length)} channels are available in the guide shell.`
      : guidePlaceholderPrimaryText(guide.presentationState, 'guide');
  }
  return defaultPrimaryText;
}

function guidePlaceholderPrimaryText(
  presentationState: EpgGuideViewModel['presentationState'],
  route: 'player' | 'guide',
): string {
  switch (presentationState) {
    case 'loading':
      return route === 'player'
        ? 'Current program details appear once guide data is ready.'
        : 'Schedule rows are preparing for the selected lineup.';
    case 'empty':
      return route === 'player'
        ? 'Current program details appear after channels are added.'
        : 'Add channels from setup to populate this guide.';
    case 'error':
      return route === 'player'
        ? 'Current program details are temporarily unavailable.'
        : 'The guide could not be shown. Try again from the route controls.';
    case 'ready':
      return route === 'player'
        ? 'Current program is cued on the active channel.'
        : 'Channels are available in the guide shell.';
  }
}

function formatRecoveryDetail(
  summary: ChannelRuntimeRendererState['summary'],
): string {
  if (summary === null || summary.channelCount === 0) {
    return 'No persisted channels recovered.';
  }
  const current = summary.currentChannelNumber === null
    ? 'No current channel'
    : `Current channel ${String(summary.currentChannelNumber)}`;
  return `${String(summary.channelCount)} persisted channels; ${current}.`;
}

export function applyWorkflowSettingsAction(
  state: WorkflowState,
  actionId: SettingsActionId,
): WorkflowState {
  return {
    ...state,
    settingsDraft: applySettingsAction(state.settingsDraft, actionId),
  };
}

export function applyWorkflowSupportBundleExportStatus(
  state: WorkflowState,
  status: SupportBundleExportStatusViewModel,
): WorkflowState {
  return {
    ...state,
    settingsDraft: applySupportBundleExportStatus(state.settingsDraft, status),
  };
}

export function applyWorkflowChannelSetupAction(
  state: WorkflowState,
  actionId: ChannelSetupActionId,
): WorkflowState {
  return {
    ...state,
    channelSetupDraft: applyChannelSetupAction(state.channelSetupDraft, actionId),
  };
}

export function applyWorkflowEpgAction(
  state: WorkflowState,
  actionId: EpgActionId,
): WorkflowState {
  return {
    ...state,
    epg: applyEpgAction(state.epg, actionId, state.guidePresentation),
  };
}

export function findRouteAction(
  route: AppRouteId,
  actionId: RouteWorkflowActionId,
): RouteActionViewModel | null {
  return ROUTE_ACTIONS[route].find((action) => action.id === actionId) ?? null;
}

function findActionStatusText(
  route: AppRouteId,
  actionId: RouteWorkflowActionId,
): string | null {
  return findRouteAction(route, actionId)?.statusText ?? null;
}
