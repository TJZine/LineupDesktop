import {
  AUDIO_OUTPUT_DEVICE_ID_PATTERN,
  SETTINGS_SCHEMA_VERSION,
  isSharedDesktopAudioOutputList,
} from '../contracts/settingsAudioValidation.js';

export const SETTINGS_INVALID_REQUEST_ID = 'settings-invalid-request';
export const SETTINGS_REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/u;
export const SETTINGS_ERROR_CODES = [
  'unauthorized',
  'validation-failed',
  'revision-conflict',
  'storage-unavailable',
  'operation-failed',
] as const;
export const SETTINGS_ERROR_MESSAGES = {
  unauthorized: 'Desktop settings request was not authorized.',
  'validation-failed': 'Desktop settings request or response was invalid.',
  'revision-conflict': 'Desktop settings changed; refresh and try again.',
  'storage-unavailable': 'Desktop settings storage is unavailable.',
  'operation-failed': 'Desktop settings operation failed.',
} as const;

export type PreloadSettingsErrorCode = (typeof SETTINGS_ERROR_CODES)[number];

export function readSettingsRequestId(value: unknown): string {
  return isPlainRecord(value) && isSettingsRequestId(value.requestId)
    ? value.requestId
    : SETTINGS_INVALID_REQUEST_ID;
}

export function isSettingsGetSnapshotRequest(value: unknown): value is { requestId: string } {
  return isPlainRecord(value) && hasOnlyKeys(value, ['requestId']) &&
    isSettingsRequestId(value.requestId);
}

export function isSettingsReplaceRequest(value: unknown): value is {
  requestId: string;
  expectedRevision: number;
  values: {
    launchMode: 'windowed' | 'fullscreen';
    audioSetupCompleted: boolean;
    audioOutputDeviceId: string | null | 'system-default';
    dtsPassthroughEnabled: boolean;
    directPlayAudioFallbackEnabled: boolean;
    subtitleMode: 'off' | 'direct' | 'standard' | 'full';
    preferredSubtitleLanguage: 'en' | 'es' | 'fr' | 'de' | 'it' | 'pt' | 'ru' | 'ja' | 'ko' | 'zh' | null;
    preferForcedSubtitlesEnabled: boolean;
    keepPlaybackRunningInSettings: boolean;
    hdrFallbackMode: 'off' | 'prefer-hdr10' | 'force-hls';
    transcodeQuality: 'default' | '12000-1080p' | '8000-1080p' | '4000-720p' | '2000-720p' | '1500-480p';
    transcodeCompatibilityModeEnabled: boolean;
    libraryTabsEnabled: boolean;
    nowWatchingBannerEnabled: boolean;
    guideTimeRange: 'detailed' | 'wide';
    guidePerformanceProfile: 'auto' | 'reduced-resource';
    guideRowDensity: 'auto' | 'comfortable' | 'compact';
    guideLayout: 'overlay' | 'classic';
    pastItemsWindow: 'auto' | '0' | '15' | '30';
    infoBoxBackgroundMode: 'artwork-bleed' | 'artwork' | 'theme-default';
    theme: 'ember-steel' | 'slate-pine' | 'swiss' | 'directv' | 'glass';
    cinematicNowPlayingEnabled: boolean;
    preferClearLogosEnabled: boolean;
    nowPlayingAutoHideMs: 0 | 5000 | 10000 | 15000 | 30000 | 60000 | 120000;
    showProfilePickerOnStartup: boolean;
    debugLoggingEnabled: boolean;
    subtitleDebugLoggingEnabled: boolean;
    previewBadgesEnabled: boolean;
    setupReminderEnabled: boolean;
  };
} {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['requestId', 'expectedRevision', 'values']) &&
    isSettingsRequestId(value.requestId) &&
    isSafeRevision(value.expectedRevision) &&
    isSettingsValues(value.values, true);
}

export function isSettingsResult(value: unknown, expectedRequestId: string): boolean {
  if (!isPlainRecord(value) || typeof value.ok !== 'boolean' ||
    value.requestId !== expectedRequestId || !isSettingsRequestId(value.requestId)) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'value', 'requestId']) && isSettingsView(value.value);
  }
  if (!hasOnlyKeys(value, ['ok', 'error', 'requestId']) || !isPlainRecord(value.error) ||
    !hasOnlyKeys(value.error, ['code', 'message'])) {
    return false;
  }
  const code = value.error.code as PreloadSettingsErrorCode;
  return SETTINGS_ERROR_CODES.includes(code) && value.error.message === SETTINGS_ERROR_MESSAGES[code];
}

export function isSettingsAudioOutputResult(value: unknown, expectedRequestId: string): boolean {
  if (!isPlainRecord(value) || typeof value.ok !== 'boolean' ||
    value.requestId !== expectedRequestId || !isSettingsRequestId(value.requestId)) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'value', 'requestId']) &&
      isSharedDesktopAudioOutputList(value.value);
  }
  if (!hasOnlyKeys(value, ['ok', 'error', 'requestId']) ||
    !isPlainRecord(value.error) ||
    !hasOnlyKeys(value.error, ['code', 'message'])) {
    return false;
  }
  const code = value.error.code as PreloadSettingsErrorCode;
  return ['unauthorized', 'validation-failed', 'operation-failed'].includes(code) &&
    value.error.message === SETTINGS_ERROR_MESSAGES[code];
}

export function settingsBridgeFailure(
  requestId: string,
  code: PreloadSettingsErrorCode,
): { ok: false; error: { code: PreloadSettingsErrorCode; message: string }; requestId: string } {
  return { ok: false, error: { code, message: SETTINGS_ERROR_MESSAGES[code] }, requestId };
}

function isSettingsSnapshot(value: unknown): boolean {
  return isPlainRecord(value) && hasOnlyKeys(value, ['schemaVersion', 'revision', 'status', 'values']) &&
    value.schemaVersion === SETTINGS_SCHEMA_VERSION && isSafeRevision(value.revision) &&
    ['ready', 'missing', 'corrupt'].includes(value.status as string) &&
    isSettingsValues(value.values, false);
}

function isSettingsView(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['snapshot', 'capabilities']) &&
    isSettingsSnapshot(value.snapshot) &&
    isSettingsCapabilities(value.capabilities);
}

function isSettingsCapabilities(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, [
      'audioOutputSelection',
      'dtsPassthrough',
      'directPlayAudioFallback',
      'subtitleSelection',
      'hdrFallback',
      'transcode',
      'artworkPresentation',
    ]) &&
    isCapabilityEntry(value.audioOutputSelection) &&
    isCapabilityEntry(value.dtsPassthrough) &&
    isCapabilityEntry(value.directPlayAudioFallback) &&
    isCapabilityEntry(value.subtitleSelection) &&
    isCapabilityEntry(value.hdrFallback) &&
    isCapabilityEntry(value.transcode) &&
    isCapabilityEntry(value.artworkPresentation);
}

function isCapabilityEntry(value: unknown): boolean {
  if (!isPlainRecord(value) || !hasOnlyKeys(value, ['status', 'reason'])) return false;
  if (value.status === 'supported') return value.reason === 'available';
  if (value.status === 'unproven') return value.reason === 'native-proof-required';
  return value.status === 'unsupported' &&
    ['platform-unsupported', 'helper-unavailable', 'production-capability-unsupported', 'safe-artwork-unavailable']
      .includes(value.reason as string);
}

const SETTINGS_VALUE_KEYS = [
  'launchMode',
  'audioSetupCompleted',
  'audioOutputDeviceId',
  'dtsPassthroughEnabled',
  'directPlayAudioFallbackEnabled',
  'subtitleMode',
  'preferredSubtitleLanguage',
  'preferForcedSubtitlesEnabled',
  'keepPlaybackRunningInSettings',
  'hdrFallbackMode',
  'transcodeQuality',
  'transcodeCompatibilityModeEnabled',
  'libraryTabsEnabled',
  'nowWatchingBannerEnabled',
  'guideTimeRange',
  'guidePerformanceProfile',
  'guideRowDensity',
  'guideLayout',
  'pastItemsWindow',
  'infoBoxBackgroundMode',
  'theme',
  'cinematicNowPlayingEnabled',
  'preferClearLogosEnabled',
  'nowPlayingAutoHideMs',
  'showProfilePickerOnStartup',
  'debugLoggingEnabled',
  'subtitleDebugLoggingEnabled',
  'previewBadgesEnabled',
  'setupReminderEnabled',
] as const;

function isSettingsValues(value: unknown, allowSystemDefault: boolean): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, SETTINGS_VALUE_KEYS) &&
    (value.launchMode === 'windowed' || value.launchMode === 'fullscreen') &&
    typeof value.audioSetupCompleted === 'boolean' &&
    isAudioOutputDeviceId(value.audioOutputDeviceId, allowSystemDefault) &&
    typeof value.dtsPassthroughEnabled === 'boolean' &&
    typeof value.directPlayAudioFallbackEnabled === 'boolean' &&
    ['off', 'direct', 'standard', 'full'].includes(value.subtitleMode as string) &&
    (value.preferredSubtitleLanguage === null ||
      ['en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', 'zh'].includes(value.preferredSubtitleLanguage as string)) &&
    typeof value.preferForcedSubtitlesEnabled === 'boolean' &&
    typeof value.keepPlaybackRunningInSettings === 'boolean' &&
    ['off', 'prefer-hdr10', 'force-hls'].includes(value.hdrFallbackMode as string) &&
    ['default', '12000-1080p', '8000-1080p', '4000-720p', '2000-720p', '1500-480p'].includes(value.transcodeQuality as string) &&
    typeof value.transcodeCompatibilityModeEnabled === 'boolean' &&
    typeof value.libraryTabsEnabled === 'boolean' &&
    typeof value.nowWatchingBannerEnabled === 'boolean' &&
    (value.guideTimeRange === 'detailed' || value.guideTimeRange === 'wide') &&
    (value.guidePerformanceProfile === 'auto' || value.guidePerformanceProfile === 'reduced-resource') &&
    (value.guideRowDensity === 'auto' || value.guideRowDensity === 'comfortable' || value.guideRowDensity === 'compact') &&
    (value.guideLayout === 'overlay' || value.guideLayout === 'classic') &&
    ['auto', '0', '15', '30'].includes(value.pastItemsWindow as string) &&
    ['artwork-bleed', 'artwork', 'theme-default'].includes(value.infoBoxBackgroundMode as string) &&
    ['ember-steel', 'slate-pine', 'swiss', 'directv', 'glass'].includes(value.theme as string) &&
    typeof value.cinematicNowPlayingEnabled === 'boolean' &&
    typeof value.preferClearLogosEnabled === 'boolean' &&
    [0, 5000, 10000, 15000, 30000, 60000, 120000].includes(value.nowPlayingAutoHideMs as number) &&
    typeof value.showProfilePickerOnStartup === 'boolean' &&
    typeof value.debugLoggingEnabled === 'boolean' &&
    typeof value.subtitleDebugLoggingEnabled === 'boolean' &&
    typeof value.previewBadgesEnabled === 'boolean' && typeof value.setupReminderEnabled === 'boolean';
}

function isAudioOutputDeviceId(value: unknown, allowSystemDefault: boolean): boolean {
  if (value === null || (allowSystemDefault && value === 'system-default')) return true;
  return typeof value === 'string' &&
    value === value.trim() &&
    AUDIO_OUTPUT_DEVICE_ID_PATTERN.test(value);
}

function isSettingsRequestId(value: unknown): value is string {
  return typeof value === 'string' && SETTINGS_REQUEST_ID_PATTERN.test(value);
}

function isSafeRevision(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasOnlyKeys(value: Record<string, unknown>, requiredKeys: readonly string[]): boolean {
  return Object.keys(value).length === requiredKeys.length &&
    requiredKeys.every((key) => Object.hasOwn(value, key));
}
