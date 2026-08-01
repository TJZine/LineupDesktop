export type ChannelSetupActionId =
  | 'selectAppendBuildMode'
  | 'selectReplaceBuildMode';

import {
  CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES,
  type DesktopSettingsCapabilityProjection,
  createDefaultDesktopSettingsValues,
  type DesktopSettingsValues,
} from '../contracts/settings.js';

export const SETTINGS_SECTION_IDS = [
  'audio-subtitles',
  'playback-hdr',
  'appearance',
  'guide',
  'account',
  'developer',
  'recovery',
] as const;

export type SettingsSectionId = (typeof SETTINGS_SECTION_IDS)[number];

export const PERSISTED_SETTINGS_ACTION_IDS = [
  'cycleLaunchMode',
  'selectAudioOutput',
  'toggleDtsPassthrough',
  'toggleDirectPlayAudioFallback',
  'cycleSubtitleMode',
  'cyclePreferredSubtitleLanguage',
  'togglePreferForcedSubtitles',
  'toggleKeepPlaybackRunning',
  'cycleHdrFallback',
  'cycleTranscodeQuality',
  'toggleTranscodeCompatibility',
  'toggleLibraryTabs',
  'toggleNowWatchingBanner',
  'toggleAggressiveGuidePreload',
  'cycleGuideDensity',
  'cycleGuideLayout',
  'cyclePastItemsWindow',
  'cycleInfoBoxBackground',
  'cycleTheme',
  'toggleCinematicNowPlaying',
  'togglePreferClearLogos',
  'cycleNowPlayingAutoHide',
  'toggleShowProfilePickerOnStartup',
  'toggleDebugLogging',
  'toggleSubtitleDebugLogging',
  'togglePreviewBadges',
  'toggleSetupReminder',
] as const;

export type PersistedSettingsActionId = (typeof PERSISTED_SETTINGS_ACTION_IDS)[number];
export type SettingsActionId = PersistedSettingsActionId | 'switchProfile' | 'exportSupportBundle';

export interface SettingsDraftState extends DesktopSettingsValues {
  capabilities: DesktopSettingsCapabilityProjection | null;
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
  disabled?: boolean;
  disabledReason?: string;
  action?: SettingsActionId;
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
    ...createDefaultDesktopSettingsValues(),
    capabilities: CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES,
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
  capabilities: DesktopSettingsCapabilityProjection | null = state.capabilities,
): SettingsDraftState {
  return { ...state, ...values, capabilities };
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
  if (actionId === 'switchProfile') return state;
  switch (actionId) {
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
    default:
      return {
        ...state,
        ...nextDesktopSettingsValues(state, actionId),
      };
  }
}

export function nextDesktopSettingsValues(
  values: DesktopSettingsValues,
  action: PersistedSettingsActionId,
): DesktopSettingsValues {
  switch (action) {
    case 'cycleLaunchMode': return { ...values, launchMode: cycle(values.launchMode, ['windowed', 'fullscreen']) };
    case 'selectAudioOutput': return values;
    case 'toggleDtsPassthrough': return { ...values, dtsPassthroughEnabled: !values.dtsPassthroughEnabled };
    case 'toggleDirectPlayAudioFallback': return { ...values, directPlayAudioFallbackEnabled: !values.directPlayAudioFallbackEnabled };
    case 'cycleSubtitleMode': return { ...values, subtitleMode: cycle(values.subtitleMode, ['off', 'direct', 'standard', 'full']) };
    case 'cyclePreferredSubtitleLanguage': return { ...values, preferredSubtitleLanguage: cycle(values.preferredSubtitleLanguage, [null, 'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', 'zh']) };
    case 'togglePreferForcedSubtitles': return { ...values, preferForcedSubtitlesEnabled: !values.preferForcedSubtitlesEnabled };
    case 'toggleKeepPlaybackRunning': return { ...values, keepPlaybackRunningInSettings: !values.keepPlaybackRunningInSettings };
    case 'cycleHdrFallback': return { ...values, hdrFallbackMode: cycle(values.hdrFallbackMode, ['off', 'prefer-hdr10', 'force-hls']) };
    case 'cycleTranscodeQuality': return { ...values, transcodeQuality: cycle(values.transcodeQuality, ['default', '12000-1080p', '8000-1080p', '4000-720p', '2000-720p', '1500-480p']) };
    case 'toggleTranscodeCompatibility': return { ...values, transcodeCompatibilityModeEnabled: !values.transcodeCompatibilityModeEnabled };
    case 'toggleLibraryTabs': return { ...values, libraryTabsEnabled: !values.libraryTabsEnabled };
    case 'toggleNowWatchingBanner': return { ...values, nowWatchingBannerEnabled: !values.nowWatchingBannerEnabled };
    case 'toggleAggressiveGuidePreload': return { ...values, aggressiveGuidePreloadEnabled: !values.aggressiveGuidePreloadEnabled };
    case 'cycleGuideDensity': return { ...values, guideDensity: cycle(values.guideDensity, ['comfortable', 'compact']) };
    case 'cycleGuideLayout': return { ...values, guideLayout: cycle(values.guideLayout, ['overlay', 'classic']) };
    case 'cyclePastItemsWindow': return { ...values, pastItemsWindow: cycle(values.pastItemsWindow, ['auto', '0', '15', '30']) };
    case 'cycleInfoBoxBackground': return { ...values, infoBoxBackgroundMode: cycle(values.infoBoxBackgroundMode, ['artwork-bleed', 'artwork', 'theme-default']) };
    case 'cycleTheme': return { ...values, theme: cycle(values.theme, ['ember-steel', 'slate-pine', 'swiss', 'directv', 'glass']) };
    case 'toggleCinematicNowPlaying': return { ...values, cinematicNowPlayingEnabled: !values.cinematicNowPlayingEnabled };
    case 'togglePreferClearLogos': return { ...values, preferClearLogosEnabled: !values.preferClearLogosEnabled };
    case 'cycleNowPlayingAutoHide': return { ...values, nowPlayingAutoHideMs: cycle(values.nowPlayingAutoHideMs, [0, 5000, 10000, 15000, 30000, 60000, 120000]) };
    case 'toggleShowProfilePickerOnStartup': return { ...values, showProfilePickerOnStartup: !values.showProfilePickerOnStartup };
    case 'toggleDebugLogging': return { ...values, debugLoggingEnabled: !values.debugLoggingEnabled };
    case 'toggleSubtitleDebugLogging': return { ...values, subtitleDebugLoggingEnabled: !values.subtitleDebugLoggingEnabled };
    case 'togglePreviewBadges': return { ...values, previewBadgesEnabled: !values.previewBadgesEnabled };
    case 'toggleSetupReminder': return { ...values, setupReminderEnabled: !values.setupReminderEnabled };
  }
}

export function isPersistedSettingsActionEnabled(
  action: PersistedSettingsActionId,
  capabilities: DesktopSettingsCapabilityProjection | null,
): boolean {
  if (capabilities === null) return false;
  switch (action) {
    case 'selectAudioOutput': return capabilities.audioOutputSelection.status === 'supported';
    case 'toggleDtsPassthrough': return capabilities.dtsPassthrough.status === 'supported';
    case 'toggleDirectPlayAudioFallback': return capabilities.directPlayAudioFallback.status === 'supported';
    case 'cycleSubtitleMode':
    case 'cyclePreferredSubtitleLanguage':
    case 'togglePreferForcedSubtitles': return capabilities.subtitleSelection.status === 'supported';
    case 'cycleHdrFallback': return capabilities.hdrFallback.status === 'supported';
    case 'cycleTranscodeQuality':
    case 'toggleTranscodeCompatibility': return capabilities.transcode.status === 'supported';
    case 'cycleInfoBoxBackground':
    case 'toggleCinematicNowPlaying':
    case 'togglePreferClearLogos': return capabilities.artworkPresentation.status === 'supported';
    case 'toggleLibraryTabs':
    case 'toggleNowWatchingBanner':
    case 'toggleAggressiveGuidePreload':
    case 'cycleGuideDensity':
    case 'cycleGuideLayout':
    case 'cyclePastItemsWindow': return false;
    case 'cycleLaunchMode':
    case 'toggleKeepPlaybackRunning':
    case 'cycleTheme':
    case 'cycleNowPlayingAutoHide':
    case 'toggleShowProfilePickerOnStartup':
    case 'toggleDebugLogging':
    case 'toggleSubtitleDebugLogging':
    case 'togglePreviewBadges':
    case 'toggleSetupReminder':
      return true;
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
  capabilities: DesktopSettingsCapabilityProjection | null = state.capabilities,
): readonly SettingsSectionViewModel[] {
  const recoveryLoaded = persistedStatus?.recovery?.loaded === true;
  const recoveryRepaired = persistedStatus?.recovery?.repaired === true;
  const capabilityReason = (
    family: keyof DesktopSettingsCapabilityProjection,
  ): string | undefined => {
    const entry = capabilities?.[family];
    if (entry?.status === 'supported') return undefined;
    switch (entry?.reason) {
      case 'platform-unsupported': return 'Unavailable on this platform.';
      case 'helper-unavailable': return 'The native audio helper is unavailable.';
      case 'native-proof-required': return 'Disabled until native capability verification is complete.';
      case 'production-capability-unsupported': return 'Disabled because the production capability is unsupported.';
      case 'safe-artwork-unavailable': return 'Disabled until safe artwork is available.';
      default: return 'Capability information is unavailable.';
    }
  };
  const control = (
    id: string,
    label: string,
    valueLabel: string,
    description: string,
    action: PersistedSettingsActionId,
    disabledReason?: string,
  ): SettingsItemViewModel => ({
    id,
    label,
    valueLabel,
    description,
    action,
    disabled: disabledReason !== undefined,
    disabledReason,
  });
  const guidePending = 'Available when Guide preferences are supported.';
  return [
    {
      id: 'audio-subtitles',
      title: 'Audio & Subtitles',
      detail: 'Choose Desktop audio output and subtitle preferences.',
      items: [
        control('audio-output', 'Audio Output', state.audioOutputDeviceId === null ? 'System default' : 'Saved output', 'Open Audio Output to check current availability or choose System default.', 'selectAudioOutput', capabilityReason('audioOutputSelection')),
        {
          id: 'audio-setup-status',
          label: 'Audio Setup',
          valueLabel: state.audioSetupCompleted ? 'Complete' : 'Required',
          description: 'First-run audio setup remains available until its whole-snapshot save succeeds.',
        },
        control('dts-passthrough', 'DTS Passthrough', onOff(state.dtsPassthroughEnabled), 'Enable if you have an eARC receiver.', 'toggleDtsPassthrough', capabilityReason('dtsPassthrough')),
        control('direct-play-audio-fallback', 'Direct Play Audio Fallback', onOff(state.directPlayAudioFallbackEnabled), 'Allow Direct Play using a compatible fallback audio track.', 'toggleDirectPlayAudioFallback', capabilityReason('directPlayAudioFallback')),
        control('subtitle-mode', 'Subtitle Mode', subtitleModeLabel(state.subtitleMode), 'Full is default and may transcode; Standard avoids transcoding when possible.', 'cycleSubtitleMode', capabilityReason('subtitleSelection')),
        control('preferred-subtitle-language', 'Preferred Subtitle Language', subtitleLanguageLabel(state.preferredSubtitleLanguage), 'Auto uses the Plex preference.', 'cyclePreferredSubtitleLanguage', capabilityReason('subtitleSelection')),
        control('prefer-forced-subtitles', 'Prefer Forced Subtitles', onOff(state.preferForcedSubtitlesEnabled), 'Prefer forced partial subtitles over full subtitles.', 'togglePreferForcedSubtitles', capabilityReason('subtitleSelection')),
      ],
    },
    {
      id: 'playback-hdr',
      title: 'Playback & HDR',
      detail: 'Playback preferences never promote an unsupported production capability.',
      items: [
        control('keep-playback-running', 'Keep Playback Running in Settings', onOff(state.keepPlaybackRunningInSettings), 'When off, only the playing request paused by Settings may resume on exit.', 'toggleKeepPlaybackRunning'),
        control('hdr-fallback', 'HDR Fallback', valueLabel(state.hdrFallbackMode, { off: 'Off', 'prefer-hdr10': 'Prefer HDR10 (Direct Play)', 'force-hls': 'Force HLS/Transcode' }), 'Choose fallback behavior for supported HDR playback paths.', 'cycleHdrFallback', capabilityReason('hdrFallback')),
        control('transcode-quality', 'Transcode Quality', valueLabel(state.transcodeQuality, { default: 'Default', '12000-1080p': '12 Mbps 1080p', '8000-1080p': '8 Mbps 1080p', '4000-720p': '4 Mbps 720p', '2000-720p': '2 Mbps 720p', '1500-480p': '1.5 Mbps 480p' }), 'Caps Plex transcoding bitrate and resolution; Direct Play is unaffected.', 'cycleTranscodeQuality', capabilityReason('transcode')),
        control('transcode-compatibility', 'Transcode Compatibility Mode', onOff(state.transcodeCompatibilityModeEnabled), 'Uses the minimal approved Plex parameter set for supported transcoding.', 'toggleTranscodeCompatibility', capabilityReason('transcode')),
      ],
    },
    {
      id: 'appearance',
      title: 'Appearance',
      detail: 'Choose the desktop launch surface, theme, and Now Playing presentation.',
      items: [
        control('launch-mode', 'Startup Surface', state.launchMode === 'windowed' ? 'Windowed' : 'Fullscreen', 'Opens the desktop window in the selected mode on every launch.', 'cycleLaunchMode'),
        control('info-box-background', 'Info Box Background', valueLabel(state.infoBoxBackgroundMode, { 'artwork-bleed': 'Artwork Bleed', artwork: 'Artwork', 'theme-default': 'Theme Default' }), 'Artwork choices require a safe artwork reference.', 'cycleInfoBoxBackground', capabilityReason('artworkPresentation')),
        control('theme', 'Theme', valueLabel(state.theme, { 'ember-steel': 'Ember & Steel', 'slate-pine': 'Slate & Pine', swiss: 'Swiss', directv: 'DIRECTV', glass: 'Glass' }), 'Visual style of the application.', 'cycleTheme'),
        control('cinematic-now-playing', 'Cinematic Now Playing', onOff(state.cinematicNowPlayingEnabled), 'Full-screen layout with a safe backdrop and poster.', 'toggleCinematicNowPlaying', capabilityReason('artworkPresentation')),
        control('prefer-clear-logos', 'Use Clear Logos', onOff(state.preferClearLogosEnabled), 'Show safe clear logos instead of text titles when available.', 'togglePreferClearLogos', capabilityReason('artworkPresentation')),
        control('now-playing-auto-hide', 'Now Playing Auto-Hide', state.nowPlayingAutoHideMs === 0 ? 'Persistent' : `${String(state.nowPlayingAutoHideMs / 1000)}s`, 'Controls the Info overlay hide delay.', 'cycleNowPlayingAutoHide'),
        control('preview-badges', 'Preview Badges', state.previewBadgesEnabled ? 'Shown' : 'Hidden', 'Shows optional quality and metadata badges in current renderer consumers.', 'togglePreviewBadges'),
      ],
    },
    {
      id: 'guide',
      title: 'Guide',
      detail: guidePending,
      items: [
        control('library-tabs', 'Library Tabs', onOff(state.libraryTabsEnabled), 'Filter the Guide by source library.', 'toggleLibraryTabs', guidePending),
        control('now-watching-banner', 'Now Watching Banner', onOff(state.nowWatchingBannerEnabled), 'Show the current channel and program above the Guide.', 'toggleNowWatchingBanner', guidePending),
        control('aggressive-guide-preload', 'Aggressive Guide Preload (Experimental)', onOff(state.aggressiveGuidePreloadEnabled), 'Uses more memory to reduce loading in large Guides.', 'toggleAggressiveGuidePreload', guidePending),
        control('guide-density', 'Guide Density', state.guideDensity === 'comfortable' ? 'Detailed (2h)' : 'Wide (3h)', 'Detailed shows 2 hours; Wide shows 3 hours.', 'cycleGuideDensity', guidePending),
        control('guide-layout', 'Guide Layout', state.guideLayout === 'overlay' ? 'Overlay' : 'Classic (PIP)', 'Overlay keeps full-screen video; Classic uses PIP.', 'cycleGuideLayout', guidePending),
        control('past-items-window', 'Past Items', valueLabel(state.pastItemsWindow, { auto: 'Auto (Recommended)', '0': 'Now (0m)', '15': '15m', '30': '30m' }), 'Controls how long past Guide items remain.', 'cyclePastItemsWindow', guidePending),
      ],
    },
    {
      id: 'account',
      title: 'Account',
      detail: 'Control the existing renderer-safe Plex Home profile journey.',
      items: [
        control('profile-picker-startup', 'Show Profile Picker on Startup', onOff(state.showProfilePickerOnStartup), 'Prompt once per launch for a Plex Home profile when supported.', 'toggleShowProfilePickerOnStartup'),
      ],
    },
    {
      id: 'developer',
      title: 'Developer',
      detail: 'Enable only fixed-schema, sanitized diagnostics.',
      items: [
        control('debug-logging', 'Debug Logging', onOff(state.debugLoggingEnabled), 'Admits additional fixed-schema renderer-safe diagnostic events.', 'toggleDebugLogging'),
        control('subtitle-debug-logging', 'Subtitle Debug Logging', onOff(state.subtitleDebugLoggingEnabled), 'Admits only redacted subtitle counts, categories, and fixed reason codes.', 'toggleSubtitleDebugLogging'),
        {
          id: 'support-bundle-export',
          label: 'Support bundle',
          valueLabel: formatSupportBundleStatus(state.supportBundleExport),
          description: 'Main-owned diagnostics export with safe name, file count, and redaction sanitization.',
          action: 'exportSupportBundle',
          disabled: state.supportBundleExport.status === 'exporting',
        },
      ],
    },
    {
      id: 'recovery',
      title: 'Recovery',
      detail: 'Review renderer-safe recovery state and optional setup reminders.',
      items: [
        control('setup-reminder', 'Setup Reminder', state.setupReminderEnabled ? 'Shown' : 'Hidden', 'Shows an optional reminder when no channels exist; core setup paths remain available.', 'toggleSetupReminder'),
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
      ],
    },
  ];
}

export function createSettingsSectionControlFocusIds(): ReadonlyMap<string, readonly string[]> {
  return new Map(
    createSettingsSections(createSettingsDraftState()).map((section) => [
      `settings-category-${section.id}`,
      section.items
        .filter((item) => item.action !== undefined)
        .map((item) => `settings-${item.id}`),
    ]),
  );
}

function cycle<T>(value: T, values: readonly T[]): T {
  const index = values.indexOf(value);
  return values[(index + 1) % values.length] ?? values[0] ?? value;
}

function onOff(value: boolean): string {
  return value ? 'On' : 'Off';
}

function valueLabel<T extends string>(value: T, labels: Readonly<Record<T, string>>): string {
  return labels[value];
}

function subtitleModeLabel(value: DesktopSettingsValues['subtitleMode']): string {
  return valueLabel(value, {
    off: 'Off',
    direct: 'Direct only (fastest)',
    standard: 'Standard (avoid transcoding)',
    full: 'Full (Burn-in, default)',
  });
}

function subtitleLanguageLabel(value: DesktopSettingsValues['preferredSubtitleLanguage']): string {
  if (value === null) return 'Auto (Plex)';
  return valueLabel(value, {
    en: 'English', es: 'Spanish', fr: 'French', de: 'German', it: 'Italian',
    pt: 'Portuguese', ru: 'Russian', ja: 'Japanese', ko: 'Korean', zh: 'Chinese',
  });
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
