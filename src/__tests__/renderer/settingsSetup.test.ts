import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createSettingsDraftState,
  applySettingsAction,
  applySupportBundleExportStatus,
  createSettingsSections,
} from '../../renderer/settingsSetup.js';

test('settingsSetup initial state has expected default values', () => {
  const state = createSettingsDraftState();
  assert.equal(state.launchMode, 'windowed');
  assert.equal(state.guideDensity, 'comfortable');
  assert.equal(state.previewBadgesEnabled, true);
  assert.equal(state.setupReminderEnabled, true);
  assert.deepEqual(state.supportBundleExport, {
    status: 'ready',
    bundleDirectoryName: null,
    fileCount: null,
    redactionStatus: null,
  });
});

test('applySettingsAction handles cycleLaunchMode state transition', () => {
  let state = createSettingsDraftState();
  state = applySettingsAction(state, 'cycleLaunchMode');
  assert.equal(state.launchMode, 'fullscreen');
  state = applySettingsAction(state, 'cycleLaunchMode');
  assert.equal(state.launchMode, 'windowed');
});

test('applySettingsAction handles cycleGuideDensity state transition', () => {
  let state = createSettingsDraftState();
  state = applySettingsAction(state, 'cycleGuideDensity');
  assert.equal(state.guideDensity, 'compact');
  state = applySettingsAction(state, 'cycleGuideDensity');
  assert.equal(state.guideDensity, 'comfortable');
});

test('applySettingsAction handles togglePreviewBadges state transition', () => {
  let state = createSettingsDraftState();
  state = applySettingsAction(state, 'togglePreviewBadges');
  assert.equal(state.previewBadgesEnabled, false);
  state = applySettingsAction(state, 'togglePreviewBadges');
  assert.equal(state.previewBadgesEnabled, true);
});

test('applySettingsAction handles toggleSetupReminder state transition', () => {
  let state = createSettingsDraftState();
  state = applySettingsAction(state, 'toggleSetupReminder');
  assert.equal(state.setupReminderEnabled, false);
  state = applySettingsAction(state, 'toggleSetupReminder');
  assert.equal(state.setupReminderEnabled, true);
});

test('applySettingsAction handles exportSupportBundle state transition', () => {
  let state = createSettingsDraftState();
  state = applySettingsAction(state, 'exportSupportBundle');
  assert.deepEqual(state.supportBundleExport, {
    status: 'exporting',
    bundleDirectoryName: null,
    fileCount: null,
    redactionStatus: null,
  });
});

test('applySupportBundleExportStatus sanitizes successful status and directory names', () => {
  const initialState = createSettingsDraftState();

  // Test successful standard path sanitization
  const state1 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-abc-123',
    fileCount: 42.7,
    redactionStatus: 'passed',
  });
  assert.deepEqual(state1.supportBundleExport, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-abc-123',
    fileCount: 42,
    redactionStatus: 'passed',
  });

  // Test extraction of base name from paths (with slash and backslash)
  const state2 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'path/to/lineup-desktop-support-test',
    fileCount: 5,
    redactionStatus: 'failed',
  });
  assert.equal(state2.supportBundleExport.bundleDirectoryName, 'lineup-desktop-support-test');

  const state3 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: ['C:', 'Windows', 'lineup-desktop-support-windows'].join('\\'),
    fileCount: 1,
    redactionStatus: null,
  });
  assert.equal(state3.supportBundleExport.bundleDirectoryName, 'lineup-desktop-support-windows');

  // Test invalid directory suffix matching (wrong prefix or suffix length)
  const state4 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'invalid-prefix-support-abc',
    fileCount: 10,
    redactionStatus: 'passed',
  });
  assert.equal(state4.supportBundleExport.bundleDirectoryName, null);

  const state5 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-' + 'a'.repeat(81),
    fileCount: 10,
    redactionStatus: 'passed',
  });
  assert.equal(state5.supportBundleExport.bundleDirectoryName, null);

  // Test non-printable ASCII and special character sanitization
  const state6 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-ab\x00cd$%',
    fileCount: 3,
    redactionStatus: 'passed',
  });
  // \x00 (non-printable) is filtered, $% is replaced with --
  assert.equal(state6.supportBundleExport.bundleDirectoryName, 'lineup-desktop-support-abcd--');
});

test('applySupportBundleExportStatus handles edge cases for files and redaction status', () => {
  const initialState = createSettingsDraftState();

  // Test non-finite file count
  const state1 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-ok',
    fileCount: NaN,
    redactionStatus: 'passed',
  });
  assert.equal(state1.supportBundleExport.fileCount, null);

  // Test negative file count
  const state2 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-ok',
    fileCount: -5,
    redactionStatus: 'passed',
  });
  assert.equal(state2.supportBundleExport.fileCount, null);

  // Test invalid redactionStatus
  const state3 = applySupportBundleExportStatus(initialState, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-ok',
    fileCount: 5,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    redactionStatus: 'invalid-status' as any,
  });
  assert.equal(state3.supportBundleExport.redactionStatus, null);
});

test('createSettingsSections generates sections with expected structures', () => {
  const state = createSettingsDraftState();
  const sections = createSettingsSections(state, {
    channelCount: 12,
    currentChannelName: 'Liminal One',
    currentChannelNumber: 101,
    recovery: { loaded: true, repaired: false },
  });

  assert.equal(sections.length, 3);
  assert.equal(sections[0]?.id, 'appearance');
  assert.equal(sections[1]?.id, 'guide');
  assert.equal(sections[2]?.id, 'recovery');

  const setupSection = sections[2];
  assert.equal(setupSection?.items.length, 5);
  assert.equal(setupSection?.items[0]?.id, 'setup-reminder');
  assert.equal(setupSection?.items[1]?.id, 'setup-channel-count');
  assert.equal(setupSection?.items[1]?.valueLabel, '12');
  assert.equal(setupSection?.items[2]?.id, 'setup-recovery-state');
  assert.equal(setupSection?.items[2]?.valueLabel, 'Recovered');
  assert.equal(setupSection?.items[3]?.id, 'setup-current-channel');
  assert.equal(setupSection?.items[3]?.valueLabel, '101');
});
