import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES,
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  DESKTOP_SETTINGS_ERROR_CODES,
  DESKTOP_SETTINGS_ERROR_MESSAGES,
  DESKTOP_SETTINGS_LOAD_STATUSES,
  DESKTOP_SETTINGS_VALUE_KEYS,
  SETTINGS_INVALID_REQUEST_ID,
  SETTINGS_SCHEMA_VERSION,
  createDesktopSettingsView,
  desktopSettingsFailure,
  desktopSettingsSuccess,
  isDesktopSettingsCapabilityEntry,
  isDesktopSettingsCapabilityProjection,
  isDesktopSettingsGetSnapshotRequest,
  isDesktopSettingsIpcResult,
  isDesktopSettingsReplaceRequest,
  isDesktopSettingsSnapshot,
  isDesktopSettingsValues,
  isDesktopSettingsView,
  normalizeDesktopSettingsReplaceValues,
  readDesktopSettingsRequestId,
} from '../../contracts/settings.js';

const opaqueAudioId = `audio_${'A'.repeat(43)}` as const;
const values = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
const snapshot = { schemaVersion: SETTINGS_SCHEMA_VERSION, revision: 2, status: 'ready' as const, values };
const view = createDesktopSettingsView(snapshot);

test('settings contract freezes the exact version-2 values, defaults, statuses, and error vocabulary', () => {
  assert.equal(SETTINGS_SCHEMA_VERSION, 2);
  assert.deepEqual(Object.keys(values), [...DESKTOP_SETTINGS_VALUE_KEYS]);
  assert.deepEqual(values, {
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
  assert.deepEqual([...DESKTOP_SETTINGS_LOAD_STATUSES], ['ready', 'missing', 'corrupt', 'unsupported-version']);
  assert.equal(DESKTOP_SETTINGS_LOAD_STATUSES.includes('migrated' as never), false);
  assert.deepEqual([...DESKTOP_SETTINGS_ERROR_CODES], [
    'unauthorized', 'validation-failed', 'revision-conflict', 'storage-unavailable',
    'unsupported-version', 'operation-failed',
  ]);
  for (const code of DESKTOP_SETTINGS_ERROR_CODES) {
    const failure = desktopSettingsFailure('settings-1', code);
    assert.equal(failure.ok, false);
    assert.equal(failure.ok ? null : failure.error.message, DESKTOP_SETTINGS_ERROR_MESSAGES[code]);
  }
});

test('settings request and persisted record guards require exact shapes and canonical values', () => {
  assert.equal(isDesktopSettingsValues(values), true);
  assert.equal(isDesktopSettingsValues({ ...values, extra: true }), false);
  assert.equal(isDesktopSettingsValues({ ...values, audioOutputDeviceId: opaqueAudioId }), true);
  assert.equal(isDesktopSettingsValues({ ...values, audioOutputDeviceId: 'system-default' }), false);
  assert.equal(isDesktopSettingsGetSnapshotRequest({ requestId: 'settings-get-1' }), true);
  assert.equal(isDesktopSettingsGetSnapshotRequest({ requestId: 'bad id' }), false);
  assert.equal(isDesktopSettingsReplaceRequest({
    requestId: 'settings-replace-1',
    expectedRevision: 2,
    values: { ...values, audioOutputDeviceId: 'system-default' },
  }), true);
  assert.equal(normalizeDesktopSettingsReplaceValues({
    ...values,
    audioOutputDeviceId: 'system-default',
  }).audioOutputDeviceId, null);
  assert.equal(normalizeDesktopSettingsReplaceValues({
    ...values,
    audioOutputDeviceId: opaqueAudioId,
  }).audioOutputDeviceId, opaqueAudioId);
  assert.equal(isDesktopSettingsReplaceRequest({ requestId: 'settings-replace-1', expectedRevision: -1, values }), false);
  assert.equal(isDesktopSettingsSnapshot(snapshot), true);
  assert.equal(isDesktopSettingsSnapshot({ ...snapshot, revision: Number.MAX_SAFE_INTEGER + 1 }), false);
  assert.equal(readDesktopSettingsRequestId({ requestId: 'bad id' }), SETTINGS_INVALID_REQUEST_ID);
});

test('settings replacement rejects noncanonical audio ids and unsupported literal values', () => {
  for (const audioOutputDeviceId of [
    '',
    'system-default ',
    ' system-default',
    ` ${opaqueAudioId}`,
    `${opaqueAudioId} `,
    `device_${'A'.repeat(43)}`,
    `audio_${'A'.repeat(42)}`,
    `audio_${'A'.repeat(44)}`,
    `audio_${'A'.repeat(42)}=`,
    'native-speakers',
  ]) {
    assert.equal(isDesktopSettingsReplaceRequest({
      requestId: 'settings-replace-audio',
      expectedRevision: 0,
      values: { ...values, audioOutputDeviceId },
    }), false, audioOutputDeviceId);
  }
  assert.equal(isDesktopSettingsReplaceRequest({
    requestId: 'settings-replace-language',
    expectedRevision: 0,
    values: { ...values, preferredSubtitleLanguage: 'xx' },
  }), false);
  assert.equal(isDesktopSettingsReplaceRequest({
    requestId: 'settings-replace-quality',
    expectedRevision: 0,
    values: { ...values, transcodeQuality: 'maximum' },
  }), false);
});

test('settings view owns exact conservative capabilities and strict allowed pairs', () => {
  assert.deepEqual(view.capabilities, CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES);
  assert.equal(isDesktopSettingsCapabilityProjection(view.capabilities), true);
  assert.equal(isDesktopSettingsView(view), true);
  assert.notEqual(view.capabilities, CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES);
  assert.notEqual(view.capabilities.audioOutputSelection, CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES.audioOutputSelection);
  assert.equal(isDesktopSettingsCapabilityEntry({ status: 'supported', reason: 'available' }), true);
  assert.equal(isDesktopSettingsCapabilityEntry({ status: 'unsupported', reason: 'helper-unavailable' }), true);
  assert.equal(isDesktopSettingsCapabilityEntry({ status: 'unproven', reason: 'native-proof-required' }), true);
  assert.equal(isDesktopSettingsCapabilityEntry({ status: 'supported', reason: 'native-proof-required' }), false);
  assert.equal(isDesktopSettingsCapabilityEntry({ status: 'unproven', reason: 'available' }), false);
  assert.equal(isDesktopSettingsView({ ...view, extra: true }), false);
  assert.equal(isDesktopSettingsView({
    ...view,
    capabilities: { ...view.capabilities, extra: true },
  }), false);
});

test('settings result guards accept only exact view envelopes and fixed messages', () => {
  assert.equal(isDesktopSettingsIpcResult(desktopSettingsSuccess('settings-1', view), isDesktopSettingsView), true);
  assert.equal(isDesktopSettingsIpcResult(desktopSettingsFailure('settings-1', 'operation-failed'), isDesktopSettingsView), true);
  assert.equal(isDesktopSettingsIpcResult(desktopSettingsSuccess('settings-1', snapshot), isDesktopSettingsView), false);
  assert.equal(isDesktopSettingsIpcResult({
    ok: false, requestId: 'settings-1',
    error: {
      code: 'operation-failed',
      message: `raw ${['C:', 'private', 'settings.json'].join('\\')}`,
    },
  }, isDesktopSettingsView), false);
});
