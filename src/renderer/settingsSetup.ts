export type SettingsActionId =
  | 'cycleLaunchMode'
  | 'cycleGuideDensity'
  | 'togglePreviewBadges'
  | 'toggleSetupReminder'
  | 'exportSupportBundle';

export type ChannelSetupActionId =
  | 'advanceSetupStep'
  | 'toggleFeaturedChannel'
  | 'addDraftChannel'
  | 'resetDraftLineup'
  | 'selectRecentlyAddedSource'
  | 'selectAppendBuildMode'
  | 'selectReplaceBuildMode';

export type SettingsSectionId = 'playback' | 'guide' | 'setup';

export interface SettingsDraftState {
  launchMode: 'windowed' | 'fullscreen-preview';
  guideDensity: 'comfortable' | 'compact';
  previewBadgesEnabled: boolean;
  setupReminderEnabled: boolean;
  supportBundleExport: SupportBundleExportStatusViewModel;
}

export interface SupportBundleExportStatusViewModel {
  status: 'ready' | 'exporting' | 'succeeded' | 'failed' | 'cancelled';
  bundleDirectoryName: string | null;
  fileCount: number | null;
  redactionStatus: 'passed' | 'failed' | null;
}

export interface SettingsItemViewModel {
  id: string;
  label: string;
  valueLabel: string;
  description: string;
}

export interface SettingsSectionViewModel {
  id: SettingsSectionId;
  title: string;
  detail: string;
  items: readonly SettingsItemViewModel[];
}

export interface ChannelDraftViewModel {
  id: string;
  number: string;
  name: string;
  enabled: boolean;
  blockCount: number;
  category: string;
  reviewStatus: 'active' | 'disabled';
}

export interface ChannelSetupDraftState {
  activeStepId: ChannelSetupStepId;
  sourceName: string;
  channels: readonly ChannelDraftViewModel[];
  sourceMode: 'recently-added';
  buildMode: 'append' | 'replace';
}

export type ChannelSetupStepId = 'source' | 'channels' | 'review';

export interface ChannelSetupStepViewModel {
  id: ChannelSetupStepId;
  label: string;
  detail: string;
  state: 'complete' | 'current' | 'pending';
}

export interface ChannelSetupSummaryViewModel {
  sourceName: string;
  enabledChannelCount: number;
  totalChannelCount: number;
  totalBlockCount: number;
  readyForPreview: boolean;
}

const SETUP_STEP_ORDER: readonly ChannelSetupStepId[] = ['source', 'channels', 'review'];

const DEFAULT_CHANNELS = [] as const satisfies readonly ChannelDraftViewModel[];

export function createSettingsDraftState(): SettingsDraftState {
  return {
    launchMode: 'windowed',
    guideDensity: 'comfortable',
    previewBadgesEnabled: true,
    setupReminderEnabled: true,
    supportBundleExport: {
      status: 'ready',
      bundleDirectoryName: null,
      fileCount: null,
      redactionStatus: null,
    },
  };
}

export function createChannelSetupDraftState(): ChannelSetupDraftState {
  return {
    activeStepId: 'channels',
    sourceName: '',
    channels: DEFAULT_CHANNELS,
    sourceMode: 'recently-added',
    buildMode: 'append',
  };
}

export function applySettingsAction(
  state: SettingsDraftState,
  actionId: SettingsActionId,
): SettingsDraftState {
  switch (actionId) {
    case 'cycleLaunchMode':
      return {
        ...state,
        launchMode: state.launchMode === 'windowed' ? 'fullscreen-preview' : 'windowed',
      };
    case 'cycleGuideDensity':
      return {
        ...state,
        guideDensity: state.guideDensity === 'comfortable' ? 'compact' : 'comfortable',
      };
    case 'togglePreviewBadges':
      return { ...state, previewBadgesEnabled: !state.previewBadgesEnabled };
    case 'toggleSetupReminder':
      return { ...state, setupReminderEnabled: !state.setupReminderEnabled };
    case 'exportSupportBundle':
      return {
        ...state,
        supportBundleExport: {
          status: 'exporting',
          bundleDirectoryName: null,
          fileCount: null,
          redactionStatus: null,
        },
      };
  }
}

export function applySupportBundleExportStatus(
  state: SettingsDraftState,
  status: SupportBundleExportStatusViewModel,
): SettingsDraftState {
  return {
    ...state,
    supportBundleExport: sanitizeSupportBundleExportStatus(status),
  };
}

export function applyChannelSetupAction(
  state: ChannelSetupDraftState,
  actionId: ChannelSetupActionId,
): ChannelSetupDraftState {
  switch (actionId) {
    case 'advanceSetupStep':
      return { ...state, activeStepId: nextSetupStepId(state.activeStepId) };
    case 'toggleFeaturedChannel':
      return {
        ...state,
        channels: state.channels.map((channel) =>
          channel.id === state.channels[0]?.id
            ? {
              ...channel,
              enabled: !channel.enabled,
              reviewStatus: channel.enabled ? 'disabled' : 'active',
            }
            : channel,
        ),
      };
    case 'addDraftChannel':
      return {
        ...state,
        channels: [
          ...state.channels,
          {
            id: `draft-extra-${state.channels.length + 1}`,
            number: String(400 + state.channels.length + 1),
            name: `Fixture Channel ${state.channels.length + 1}`,
            enabled: true,
            blockCount: 1,
            category: 'Mixed',
            reviewStatus: 'active',
          },
        ],
      };
    case 'resetDraftLineup':
      return createChannelSetupDraftState();
    case 'selectRecentlyAddedSource':
      return { ...state, sourceMode: 'recently-added' };
    case 'selectAppendBuildMode':
      return { ...state, buildMode: 'append' };
    case 'selectReplaceBuildMode':
      return { ...state, buildMode: 'replace' };
  }
}

export function createSettingsSections(
  state: SettingsDraftState,
  persistedStatus?: {
    channelCount: number;
    currentChannelName: string | null;
    currentChannelNumber?: number | null;
    recovery?: { loaded: boolean; repaired: boolean };
  } | null,
): readonly SettingsSectionViewModel[] {
  const recoveryLoaded = persistedStatus?.recovery?.loaded === true;
  const recoveryRepaired = persistedStatus?.recovery?.repaired === true;
  return [
    {
      id: 'playback',
      title: 'Desktop playback preview',
      detail: 'Renderer-only defaults for the app-owned presentation surface.',
      items: [
        {
          id: 'launch-mode',
          label: 'Startup surface',
          valueLabel:
            state.launchMode === 'windowed' ? 'Windowed' : 'Fullscreen presentation preview',
          description: 'Changes this renderer session label only; no desktop preference is saved.',
        },
        {
          id: 'preview-badges',
          label: 'Preview badges',
          valueLabel: state.previewBadgesEnabled ? 'Shown' : 'Hidden',
          description: 'Controls local preview markers for this session only.',
        },
      ],
    },
    {
      id: 'guide',
      title: 'Guide display',
      detail: 'Local guide presentation choices that do not contact Plex or save guide data.',
      items: [
        {
          id: 'guide-density',
          label: 'Density',
          valueLabel: state.guideDensity === 'comfortable' ? 'Comfortable' : 'Compact',
          description: 'Adjusts renderer guide spacing for this session only; no category color legend is used.',
        },
      ],
    },
    {
      id: 'setup',
      title: 'Channel setup recovery',
      detail: 'Persisted channel status from the main-owned setup and recovery seam.',
      items: [
        {
          id: 'setup-channel-count',
          label: 'Persisted channels',
          valueLabel: String(persistedStatus?.channelCount ?? 0),
          description: persistedStatus?.currentChannelName
            ? `Recovered current channel ${persistedStatus.currentChannelName}.`
            : 'No persisted current channel is available yet.',
        },
        {
          id: 'setup-recovery-state',
          label: 'Recovery',
          valueLabel: recoveryLoaded ? (recoveryRepaired ? 'Recovered with repairs' : 'Recovered') : 'Not recovered',
          description: recoveryLoaded
            ? 'Saved channel summaries are available for setup rerun and replacement review.'
            : 'Open Channel setup to create channels from a selected library.',
        },
        {
          id: 'setup-current-channel',
          label: 'Current channel',
          valueLabel: persistedStatus?.currentChannelNumber === null || persistedStatus?.currentChannelNumber === undefined
            ? 'None'
            : String(persistedStatus.currentChannelNumber),
          description: persistedStatus?.currentChannelName
            ? `Current saved channel is ${persistedStatus.currentChannelName}.`
            : 'No current channel has been recovered.',
        },
        {
          id: 'support-bundle-export',
          label: 'Support bundle',
          valueLabel: formatSupportBundleStatus(state.supportBundleExport),
          description: 'Main-owned diagnostics export with redaction scan status.',
        },
      ],
    },
  ];
}

function formatSupportBundleStatus(status: SupportBundleExportStatusViewModel): string {
  switch (status.status) {
    case 'ready':
      return 'Ready';
    case 'exporting':
      return 'Exporting';
    case 'succeeded': {
      const redactionLabel = status.redactionStatus === 'failed'
        ? ' (redaction failed)'
        : status.redactionStatus === null ? ' (redaction pending)' : '';
      return `${status.bundleDirectoryName ?? 'Bundle'} - ${String(status.fileCount ?? 0)} files${redactionLabel}`;
    }
    case 'failed':
      return 'Failed';
    case 'cancelled':
      return 'Cancelled';
  }
}

function sanitizeSupportBundleExportStatus(
  status: SupportBundleExportStatusViewModel,
): SupportBundleExportStatusViewModel {
  return {
    status: status.status,
    bundleDirectoryName: status.status === 'succeeded'
      ? sanitizeSupportBundleDirectoryName(status.bundleDirectoryName)
      : null,
    fileCount: status.status === 'succeeded' && isFiniteNonNegativeNumber(status.fileCount)
      ? Math.floor(status.fileCount)
      : null,
    redactionStatus: status.redactionStatus === 'passed' || status.redactionStatus === 'failed'
      ? status.redactionStatus
      : null,
  };
}

function sanitizeSupportBundleDirectoryName(value: string | null): string | null {
  if (value === null) {
    return null;
  }
  const parts = value.split(/[\\/]/u);
  const baseName = parts[parts.length - 1] ?? '';
  const safeName = baseName
    .split('')
    .filter(isPrintableAscii)
    .join('')
    .replace(/[^A-Za-z0-9.-]/gu, '-')
    .slice(0, 120);
  return /^lineup-desktop-support-[A-Za-z0-9-]{1,80}$/u.test(safeName) ? safeName : null;
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function isPrintableAscii(value: string): boolean {
  const codePoint = value.charCodeAt(0);
  return codePoint >= 0x20 && codePoint < 0x7f;
}

export function createChannelSetupSteps(
  state: ChannelSetupDraftState,
  persistedStatus?: { channelCount: number } | null,
): readonly ChannelSetupStepViewModel[] {
  const activeIndex = SETUP_STEP_ORDER.indexOf(state.activeStepId);
  return SETUP_STEP_ORDER.map((stepId, index) => ({
    id: stepId,
    label: setupStepLabel(stepId),
    detail: setupStepDetail(stepId, state, persistedStatus),
    state: index < activeIndex ? 'complete' : index === activeIndex ? 'current' : 'pending',
  }));
}

export function summarizeChannelSetupDraft(
  state: ChannelSetupDraftState,
): ChannelSetupSummaryViewModel {
  const enabledChannels = state.channels.filter((channel) => channel.enabled);
  const totalBlockCount = enabledChannels.reduce((sum, channel) => sum + channel.blockCount, 0);
  return {
    sourceName: state.sourceName,
    enabledChannelCount: enabledChannels.length,
    totalChannelCount: state.channels.length,
    totalBlockCount,
    readyForPreview: enabledChannels.length > 0 && totalBlockCount > 0,
  };
}

export function validateChannelSetupDraft(
  state: ChannelSetupDraftState,
  persistedStatus?: { channelCount: number } | null,
): readonly string[] {
  if (persistedStatus !== undefined && persistedStatus !== null) {
    return persistedStatus.channelCount > 0
      ? ['Saved channels are ready for recovery.']
      : ['Choose a movie or show library section before saving channels.'];
  }
  const failures: string[] = [];
  const summary = summarizeChannelSetupDraft(state);
  if (state.sourceName.trim().length === 0) {
    failures.push('Choose a library source.');
  }
  if (summary.enabledChannelCount === 0) {
    failures.push('Enable at least one preview channel.');
  }
  if (summary.totalBlockCount === 0) {
    failures.push('Add at least one programming block.');
  }
  return failures;
}

function nextSetupStepId(currentStepId: ChannelSetupStepId): ChannelSetupStepId {
  const currentIndex = SETUP_STEP_ORDER.indexOf(currentStepId);
  const nextIndex = (currentIndex + 1) % SETUP_STEP_ORDER.length;
  return SETUP_STEP_ORDER[nextIndex] ?? 'source';
}

function setupStepLabel(stepId: ChannelSetupStepId): string {
  switch (stepId) {
    case 'source':
      return 'Choose library';
    case 'channels':
      return 'Arrange channels';
    case 'review':
      return 'Review lineup';
  }
}

function setupStepDetail(
  stepId: ChannelSetupStepId,
  state: ChannelSetupDraftState,
  persistedStatus?: { channelCount: number } | null,
): string {
  if (persistedStatus !== undefined) {
    if (persistedStatus === null) {
      switch (stepId) {
        case 'source':
          return 'Persisted channel status is not loaded yet.';
        case 'channels':
          return 'Saved channel counts are unavailable until recovery status loads.';
        case 'review':
          return 'Saved channel review is disabled until persisted status is available.';
      }
    }
    switch (stepId) {
      case 'source':
        return 'Use the selected Plex profile, server, and library from this setup screen.';
      case 'channels':
        return `${persistedStatus.channelCount} saved channels are available for recovery.`;
      case 'review':
        return persistedStatus.channelCount > 0
          ? 'Saved channels can be replaced or appended from the selected library.'
          : 'Select a movie or show library section before saving channels.';
    }
  }
  const summary = summarizeChannelSetupDraft(state);
  switch (stepId) {
    case 'source':
      return `${summary.sourceName} is selected for this setup preview.`;
    case 'channels':
      return `${summary.enabledChannelCount} of ${summary.totalChannelCount} preview channels are enabled.`;
    case 'review':
      return summary.readyForPreview
        ? `${summary.totalBlockCount} programming blocks are ready for preview.`
        : 'Enable a preview channel before previewing the lineup.';
  }
}
