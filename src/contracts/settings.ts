export const SETTINGS_SCHEMA_VERSION = 2 as const;

export const DESKTOP_SETTINGS_LOAD_STATUSES = [
  'ready',
  'missing',
  'corrupt',
  'unsupported-version',
] as const;

export const DESKTOP_SETTINGS_ERROR_CODES = [
  'unauthorized',
  'validation-failed',
  'revision-conflict',
  'storage-unavailable',
  'unsupported-version',
  'operation-failed',
] as const;

export const DESKTOP_SETTINGS_ERROR_MESSAGES = {
  unauthorized: 'Desktop settings request was not authorized.',
  'validation-failed': 'Desktop settings request or response was invalid.',
  'revision-conflict': 'Desktop settings changed; refresh and try again.',
  'storage-unavailable': 'Desktop settings storage is unavailable.',
  'unsupported-version': 'Desktop settings require a newer compatible version.',
  'operation-failed': 'Desktop settings operation failed.',
} as const satisfies Record<DesktopSettingsErrorCode, string>;

export const SETTINGS_REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/u;
export const SETTINGS_INVALID_REQUEST_ID = 'settings-invalid-request' as const;
export const AUDIO_OUTPUT_DEVICE_ID_PATTERN = /^audio_[A-Za-z0-9_-]{43}$/u;
export type DesktopAudioOutputDeviceId = `audio_${string}`;

export const DESKTOP_SETTINGS_VALUE_KEYS = [
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
  'aggressiveGuidePreloadEnabled',
  'guideDensity',
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
] as const satisfies readonly (keyof DesktopSettingsValues)[];

export interface DesktopSettingsValues {
  launchMode: 'windowed' | 'fullscreen';
  audioSetupCompleted: boolean;
  audioOutputDeviceId: DesktopAudioOutputDeviceId | null;
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
  aggressiveGuidePreloadEnabled: boolean;
  guideDensity: 'comfortable' | 'compact';
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
}

export type DesktopSettingsReplaceValues = Omit<DesktopSettingsValues, 'audioOutputDeviceId'> & {
  audioOutputDeviceId: DesktopSettingsValues['audioOutputDeviceId'] | 'system-default';
};

export const DESKTOP_SETTINGS_CAPABILITY_STATUSES = [
  'supported',
  'unsupported',
  'unproven',
] as const;

export const DESKTOP_SETTINGS_CAPABILITY_REASONS = [
  'available',
  'platform-unsupported',
  'helper-unavailable',
  'native-proof-required',
  'production-capability-unsupported',
  'safe-artwork-unavailable',
] as const;

export type DesktopSettingsCapabilityStatus =
  (typeof DESKTOP_SETTINGS_CAPABILITY_STATUSES)[number];
export type DesktopSettingsCapabilityReason =
  (typeof DESKTOP_SETTINGS_CAPABILITY_REASONS)[number];

export interface DesktopSettingsCapabilityEntry {
  status: DesktopSettingsCapabilityStatus;
  reason: DesktopSettingsCapabilityReason;
}

export interface DesktopSettingsCapabilityProjection {
  audioOutputSelection: DesktopSettingsCapabilityEntry;
  dtsPassthrough: DesktopSettingsCapabilityEntry;
  directPlayAudioFallback: DesktopSettingsCapabilityEntry;
  subtitleSelection: DesktopSettingsCapabilityEntry;
  hdrFallback: DesktopSettingsCapabilityEntry;
  transcode: DesktopSettingsCapabilityEntry;
  artworkPresentation: DesktopSettingsCapabilityEntry;
}

export const CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES: Readonly<DesktopSettingsCapabilityProjection> =
  Object.freeze({
    audioOutputSelection: Object.freeze({ status: 'unproven', reason: 'native-proof-required' }),
    dtsPassthrough: Object.freeze({ status: 'unproven', reason: 'native-proof-required' }),
    directPlayAudioFallback: Object.freeze({ status: 'supported', reason: 'available' }),
    subtitleSelection: Object.freeze({ status: 'unsupported', reason: 'production-capability-unsupported' }),
    hdrFallback: Object.freeze({ status: 'unsupported', reason: 'production-capability-unsupported' }),
    transcode: Object.freeze({ status: 'unsupported', reason: 'production-capability-unsupported' }),
    artworkPresentation: Object.freeze({ status: 'unsupported', reason: 'safe-artwork-unavailable' }),
  });

export type DesktopSettingsLoadStatus = (typeof DESKTOP_SETTINGS_LOAD_STATUSES)[number];
export type DesktopSettingsErrorCode = (typeof DESKTOP_SETTINGS_ERROR_CODES)[number];

export interface DesktopSettingsSnapshot {
  schemaVersion: typeof SETTINGS_SCHEMA_VERSION;
  revision: number;
  status: DesktopSettingsLoadStatus;
  values: DesktopSettingsValues;
}

export interface DesktopSettingsView {
  snapshot: DesktopSettingsSnapshot;
  capabilities: DesktopSettingsCapabilityProjection;
}

export interface DesktopSettingsGetSnapshotRequest {
  requestId: string;
}

export interface DesktopSettingsReplaceRequest {
  requestId: string;
  expectedRevision: number;
  values: DesktopSettingsReplaceValues;
}

export type DesktopSettingsIpcResult<T> =
  | { ok: true; value: T; requestId: string }
  | {
      ok: false;
      error: { code: DesktopSettingsErrorCode; message: string };
      requestId: string;
    };

export const DEFAULT_DESKTOP_SETTINGS_VALUES: Readonly<DesktopSettingsValues> = Object.freeze({
  launchMode: 'windowed',
  audioSetupCompleted: false,
  audioOutputDeviceId: null,
  dtsPassthroughEnabled: false,
  directPlayAudioFallbackEnabled: false,
  subtitleMode: 'full',
  preferredSubtitleLanguage: null,
  preferForcedSubtitlesEnabled: false,
  keepPlaybackRunningInSettings: false,
  hdrFallbackMode: 'off',
  transcodeQuality: 'default',
  transcodeCompatibilityModeEnabled: false,
  libraryTabsEnabled: true,
  nowWatchingBannerEnabled: true,
  aggressiveGuidePreloadEnabled: false,
  guideDensity: 'comfortable',
  guideLayout: 'classic',
  pastItemsWindow: 'auto',
  infoBoxBackgroundMode: 'theme-default',
  theme: 'ember-steel',
  cinematicNowPlayingEnabled: false,
  preferClearLogosEnabled: false,
  nowPlayingAutoHideMs: 0,
  showProfilePickerOnStartup: false,
  debugLoggingEnabled: false,
  subtitleDebugLoggingEnabled: false,
  previewBadgesEnabled: true,
  setupReminderEnabled: true,
});

export function createDefaultDesktopSettingsValues(): DesktopSettingsValues {
  return { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
}

export function cloneDesktopSettingsValues(values: DesktopSettingsValues): DesktopSettingsValues {
  return { ...values };
}

export function desktopSettingsValuesEqual(
  left: DesktopSettingsValues,
  right: DesktopSettingsValues,
): boolean {
  return DESKTOP_SETTINGS_VALUE_KEYS.every((key) => left[key] === right[key]);
}

export function cloneDesktopSettingsCapabilities(
  capabilities: DesktopSettingsCapabilityProjection,
): DesktopSettingsCapabilityProjection {
  return {
    audioOutputSelection: { ...capabilities.audioOutputSelection },
    dtsPassthrough: { ...capabilities.dtsPassthrough },
    directPlayAudioFallback: { ...capabilities.directPlayAudioFallback },
    subtitleSelection: { ...capabilities.subtitleSelection },
    hdrFallback: { ...capabilities.hdrFallback },
    transcode: { ...capabilities.transcode },
    artworkPresentation: { ...capabilities.artworkPresentation },
  };
}

export function createConservativeDesktopSettingsCapabilities(): DesktopSettingsCapabilityProjection {
  return cloneDesktopSettingsCapabilities(CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES);
}

export function createDesktopSettingsView(snapshot: DesktopSettingsSnapshot): DesktopSettingsView {
  return {
    snapshot: {
      ...snapshot,
      values: cloneDesktopSettingsValues(snapshot.values),
    },
    capabilities: createConservativeDesktopSettingsCapabilities(),
  };
}

export function normalizeDesktopSettingsReplaceValues(
  values: DesktopSettingsReplaceValues,
): DesktopSettingsValues {
  return {
    ...values,
    audioOutputDeviceId: values.audioOutputDeviceId === 'system-default'
      ? null
      : values.audioOutputDeviceId,
  };
}

export function isDesktopSettingsRequestId(value: unknown): value is string {
  return typeof value === 'string' && SETTINGS_REQUEST_ID_PATTERN.test(value);
}

export function readDesktopSettingsRequestId(value: unknown): string {
  if (isPlainRecord(value) && isDesktopSettingsRequestId(value.requestId)) {
    return value.requestId;
  }
  return SETTINGS_INVALID_REQUEST_ID;
}

export function isDesktopSettingsValues(value: unknown): value is DesktopSettingsValues {
  return isSettingsValues(value, false);
}

export function isDesktopSettingsReplaceValues(value: unknown): value is DesktopSettingsReplaceValues {
  return isSettingsValues(value, true);
}

export function isDesktopSettingsGetSnapshotRequest(
  value: unknown,
): value is DesktopSettingsGetSnapshotRequest {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['requestId']) &&
    isDesktopSettingsRequestId(value.requestId);
}

export function isDesktopSettingsReplaceRequest(
  value: unknown,
): value is DesktopSettingsReplaceRequest {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['requestId', 'expectedRevision', 'values']) &&
    isDesktopSettingsRequestId(value.requestId) &&
    isSafeRevision(value.expectedRevision) &&
    isDesktopSettingsReplaceValues(value.values);
}

export function isDesktopSettingsSnapshot(value: unknown): value is DesktopSettingsSnapshot {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['schemaVersion', 'revision', 'status', 'values']) &&
    value.schemaVersion === SETTINGS_SCHEMA_VERSION &&
    isSafeRevision(value.revision) &&
    DESKTOP_SETTINGS_LOAD_STATUSES.includes(value.status as DesktopSettingsLoadStatus) &&
    isDesktopSettingsValues(value.values);
}

export function isDesktopSettingsCapabilityEntry(
  value: unknown,
): value is DesktopSettingsCapabilityEntry {
  if (!isPlainRecord(value) || !hasOnlyKeys(value, ['status', 'reason'])) {
    return false;
  }
  switch (value.status) {
    case 'supported':
      return value.reason === 'available';
    case 'unsupported':
      return value.reason === 'platform-unsupported' ||
        value.reason === 'helper-unavailable' ||
        value.reason === 'production-capability-unsupported' ||
        value.reason === 'safe-artwork-unavailable';
    case 'unproven':
      return value.reason === 'native-proof-required';
    default:
      return false;
  }
}

export function isDesktopSettingsCapabilityProjection(
  value: unknown,
): value is DesktopSettingsCapabilityProjection {
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
    isDesktopSettingsCapabilityEntry(value.audioOutputSelection) &&
    isDesktopSettingsCapabilityEntry(value.dtsPassthrough) &&
    isDesktopSettingsCapabilityEntry(value.directPlayAudioFallback) &&
    isDesktopSettingsCapabilityEntry(value.subtitleSelection) &&
    isDesktopSettingsCapabilityEntry(value.hdrFallback) &&
    isDesktopSettingsCapabilityEntry(value.transcode) &&
    isDesktopSettingsCapabilityEntry(value.artworkPresentation);
}

export function isDesktopSettingsView(value: unknown): value is DesktopSettingsView {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['snapshot', 'capabilities']) &&
    isDesktopSettingsSnapshot(value.snapshot) &&
    isDesktopSettingsCapabilityProjection(value.capabilities);
}

export function isDesktopSettingsIpcResult<T>(
  value: unknown,
  isValue: (candidate: unknown) => candidate is T,
): value is DesktopSettingsIpcResult<T> {
  if (!isPlainRecord(value) || typeof value.ok !== 'boolean' || !isDesktopSettingsRequestId(value.requestId)) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'value', 'requestId']) && isValue(value.value);
  }
  if (!hasOnlyKeys(value, ['ok', 'error', 'requestId']) || !isPlainRecord(value.error)) {
    return false;
  }
  if (!hasOnlyKeys(value.error, ['code', 'message'])) {
    return false;
  }
  const code = value.error.code as DesktopSettingsErrorCode;
  return DESKTOP_SETTINGS_ERROR_CODES.includes(code) &&
    value.error.message === DESKTOP_SETTINGS_ERROR_MESSAGES[code];
}

export function desktopSettingsSuccess<T>(
  requestId: string,
  value: T,
): DesktopSettingsIpcResult<T> {
  return { ok: true, value, requestId };
}

export function desktopSettingsFailure<T>(
  requestId: string,
  code: DesktopSettingsErrorCode,
): DesktopSettingsIpcResult<T> {
  return {
    ok: false,
    error: { code, message: DESKTOP_SETTINGS_ERROR_MESSAGES[code] },
    requestId,
  };
}

export function isSafeRevision(value: unknown): value is number {
  return Number.isSafeInteger(value) && typeof value === 'number' && value >= 0;
}

function isSettingsValues(value: unknown, allowSystemDefault: boolean): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, DESKTOP_SETTINGS_VALUE_KEYS) &&
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
    typeof value.aggressiveGuidePreloadEnabled === 'boolean' &&
    (value.guideDensity === 'comfortable' || value.guideDensity === 'compact') &&
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
    typeof value.previewBadgesEnabled === 'boolean' &&
    typeof value.setupReminderEnabled === 'boolean';
}

function isAudioOutputDeviceId(value: unknown, allowSystemDefault: boolean): boolean {
  if (value === null) return true;
  if (allowSystemDefault && value === 'system-default') return true;
  return typeof value === 'string' &&
    value === value.trim() &&
    AUDIO_OUTPUT_DEVICE_ID_PATTERN.test(value);
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasOnlyKeys(value: Record<string, unknown>, requiredKeys: readonly string[]): boolean {
  return Object.keys(value).length === requiredKeys.length &&
    requiredKeys.every((key) => Object.hasOwn(value, key));
}
