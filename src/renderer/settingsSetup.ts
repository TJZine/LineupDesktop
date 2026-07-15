export type SettingsActionId =
  | 'cycleLaunchMode'
  | 'cycleGuideDensity'
  | 'togglePreviewBadges'
  | 'toggleSetupReminder'
  | 'exportSupportBundle';

export type ChannelSetupActionId =
  | 'selectAppendBuildMode'
  | 'selectReplaceBuildMode';

import type { DesktopSettingsValues } from '../contracts/settings.js';

export type SettingsSectionId = 'appearance' | 'guide' | 'recovery';

export interface SettingsDraftState extends DesktopSettingsValues {
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

export interface ChannelSetupDraftState {
  buildMode: 'append' | 'replace';
}

export interface ChannelSetupSummaryViewModel {
  sourceName: string;
  enabledChannelCount: number;
  totalChannelCount: number;
  totalBlockCount: number;
  readyForPreview: boolean;
}

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

export function applyPersistedSettingsValues(
  state: SettingsDraftState,
  values: DesktopSettingsValues,
): SettingsDraftState {
  return { ...state, ...values };
}

export function createChannelSetupDraftState(): ChannelSetupDraftState {
  return {
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
        launchMode: state.launchMode === 'windowed' ? 'fullscreen' : 'windowed',
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
      id: 'appearance',
      title: 'Appearance',
      detail: 'Choose how Lineup Desktop opens and how optional preview details appear.',
      items: [
        {
          id: 'launch-mode',
          label: 'Startup surface',
          valueLabel:
            state.launchMode === 'windowed' ? 'Windowed' : 'Fullscreen',
          description: 'Opens the desktop window in the selected mode on every launch.',
        },
        {
          id: 'preview-badges',
          label: 'Preview badges',
          valueLabel: state.previewBadgesEnabled ? 'Shown' : 'Hidden',
          description: 'Shows optional quality and metadata badges in Guide, player, and setup previews.',
        },
      ],
    },
    {
      id: 'guide',
      title: 'Guide display',
      detail: 'Tune the saved Guide presentation without changing channel or schedule data.',
      items: [
        {
          id: 'guide-density',
          label: 'Density',
          valueLabel: state.guideDensity === 'comfortable' ? 'Comfortable' : 'Compact',
          description: 'Changes row height, cell spacing, and visible schedule density.',
        },
      ],
    },
    {
      id: 'recovery',
      title: 'Channel setup recovery',
      detail: 'Keep optional setup reminders and review the main-owned recovery state.',
      items: [
        {
          id: 'setup-reminder',
          label: 'Setup reminder',
          valueLabel: state.setupReminderEnabled ? 'Shown' : 'Hidden',
          description: 'Shows an optional reminder when no channels exist; core setup paths remain available.',
        },
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
