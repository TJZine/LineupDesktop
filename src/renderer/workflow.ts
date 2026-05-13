import { setRoute, type AppRouteId, type RouteState } from './navigation.js';
import {
  applyEpgAction,
  createEpgGuideView,
  createEpgState,
  type EpgActionId,
  type EpgGuideViewModel,
  type EpgState,
} from './epg.js';
import {
  applyChannelSetupAction,
  applySettingsAction,
  applySupportBundleExportStatus,
  createChannelSetupDraftState,
  createChannelSetupSteps,
  createSettingsDraftState,
  createSettingsSections,
  summarizeChannelSetupDraft,
  validateChannelSetupDraft,
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
  startsAtMs: number;
  endsAtMs: number;
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
  actions: readonly RouteActionViewModel[];
}

export interface WorkflowState {
  routeState: RouteState;
  lastActionId: RouteWorkflowActionId | null;
  lastActionRoute: AppRouteId | null;
  settingsDraft: SettingsDraftState;
  channelSetupDraft: ChannelSetupDraftState;
  epg: EpgState;
}

const DEMO_BASE_TIME_MS = Date.UTC(2026, 4, 12, 20, 0, 0);

const CURRENT_PROGRAM = {
  title: 'The Midnight Archive',
  subtitle: 'Episode 4 - Signal Lost',
  channelName: 'Liminal One',
  startsAtMs: DEMO_BASE_TIME_MS,
  endsAtMs: DEMO_BASE_TIME_MS + 3_600_000,
} as const satisfies ProgramSummaryViewModel;

const CHANNELS = [
  {
    id: 'channel-liminal-one',
    number: '101',
    name: 'Liminal One',
    currentTitle: CURRENT_PROGRAM.title,
    nextTitle: 'After Hours Cinema',
  },
  {
    id: 'channel-vault',
    number: '204',
    name: 'The Vault',
    currentTitle: 'Restored Feature',
    nextTitle: 'Director Notes',
  },
  {
    id: 'channel-weekend',
    number: '310',
    name: 'Weekend Queue',
    currentTitle: 'Pilot Block',
    nextTitle: 'Comfort Marathon',
  },
] as const satisfies readonly ChannelSummaryViewModel[];

const ROUTE_ACTIONS = {
  player: [
    {
      id: 'openGuide',
      label: 'Open guide',
      targetRoute: 'guide',
      statusText: 'Guide opened from the player preview.',
    },
    {
      id: 'openSettings',
      label: 'Settings',
      targetRoute: 'settings',
      statusText: 'Settings opened from the player preview.',
    },
  ],
  guide: [
    {
      id: 'resumePlayer',
      label: 'Watch now',
      targetRoute: 'player',
      statusText: 'Player preview focused on the highlighted program.',
    },
    {
      id: 'openChannelSetup',
      label: 'Edit lineup',
      targetRoute: 'channelSetup',
      statusText: 'Channel setup opened for lineup edits.',
    },
  ],
  settings: [
    {
      id: 'openChannelSetup',
      label: 'Channel setup',
      targetRoute: 'channelSetup',
      statusText: 'Channel setup opened from settings.',
    },
    {
      id: 'resumePlayer',
      label: 'Back to player',
      targetRoute: 'player',
      statusText: 'Returned to player preview from settings.',
    },
  ],
  channelSetup: [
    {
      id: 'reviewLineup',
      label: 'Review guide',
      targetRoute: 'guide',
      statusText: 'Guide preview opened for draft channel review.',
    },
    {
      id: 'confirmSetup',
      label: 'Preview player',
      targetRoute: 'player',
      statusText: 'Player preview opened with the draft lineup.',
    },
  ],
} as const satisfies Record<AppRouteId, readonly RouteActionViewModel[]>;

const ROUTE_COPY = {
  player: {
    title: 'Player',
    kicker: 'Now playing',
    tone: 'ready',
    primaryText: `${CURRENT_PROGRAM.title} is cued on ${CURRENT_PROGRAM.channelName}.`,
    secondaryText: 'Playback controls are represented by a local preview until live runtime wiring lands.',
    defaultStatus: 'Player preview ready with fake program data.',
  },
  guide: {
    title: 'Guide',
    kicker: 'Tonight',
    tone: 'ready',
    primaryText: `${CHANNELS.length} draft channels are available in the guide preview.`,
    secondaryText: 'The guide skeleton shows current and next programs without scheduler or Plex imports.',
    defaultStatus: 'Guide preview showing renderer-local lineup data.',
  },
  settings: {
    title: 'Settings',
    kicker: 'Desktop preferences',
    tone: 'draft',
    primaryText: 'Demo Library is configured as a fake local source.',
    secondaryText: `${CHANNELS.length} draft channels use desktop player preview.`,
    defaultStatus: 'Settings preview is local-only and not persisted.',
  },
  channelSetup: {
    title: 'Channel setup',
    kicker: 'Lineup draft',
    tone: 'attention',
    primaryText: 'Arrange the draft lineup before guide and player previews.',
    secondaryText: 'Setup steps are renderer-local placeholders with no persistence owner yet.',
    defaultStatus: 'Channel setup draft is ready for review.',
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

export function createWorkflowState(initialRoute: AppRouteId = 'player'): WorkflowState {
  return {
    routeState: {
      activeRoute: initialRoute,
      previousRoute: null,
    },
    lastActionId: null,
    lastActionRoute: null,
    settingsDraft: createSettingsDraftState(),
    channelSetupDraft: createChannelSetupDraftState(),
    epg: createEpgState(),
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
  };
}

export function getRouteWorkflowView(state: WorkflowState): RouteWorkflowViewModel {
  const route = state.routeState.activeRoute;
  const copy = ROUTE_COPY[route];
  const setupSummary = summarizeChannelSetupDraft(state.channelSetupDraft);
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
    primaryText: copy.primaryText,
    secondaryText: copy.secondaryText,
    currentProgram: CURRENT_PROGRAM,
    channels: CHANNELS,
    guide: createEpgGuideView(state.epg),
    settings: {
      libraryName: setupSummary.sourceName,
      channelCount: setupSummary.enabledChannelCount,
      playbackMode:
        state.settingsDraft.launchMode === 'windowed'
          ? 'Windowed desktop preview'
          : 'Fullscreen desktop preview',
      setupState: setupSummary.readyForPreview ? 'Draft ready' : 'Needs draft channels',
      sections: createSettingsSections(state.settingsDraft),
    },
    channelDrafts: state.channelSetupDraft.channels,
    channelSetupSummary: setupSummary,
    setupSteps: createChannelSetupSteps(state.channelSetupDraft),
    setupValidationMessages: validateChannelSetupDraft(state.channelSetupDraft),
    actions: ROUTE_ACTIONS[route],
  };
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
    epg: applyEpgAction(state.epg, actionId),
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
