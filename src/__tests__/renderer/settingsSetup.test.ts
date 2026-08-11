import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  createConservativeDesktopSettingsCapabilities,
} from '../../contracts/settings.js';
import {
  createSettingsDraftState,
  applySettingsAction,
  applySupportBundleExportStatus,
  createSettingsSectionControlFocusIds,
  createSettingsSections,
  isPersistedSettingsActionEnabled,
  nextDesktopSettingsValues,
} from '../../renderer/settingsSetup.js';

test('settingsSetup initial state has expected default values', () => {
  const state = createSettingsDraftState();
  assert.deepEqual(
    Object.fromEntries(Object.keys(DEFAULT_DESKTOP_SETTINGS_VALUES).map((key) => [
      key,
      state[key as keyof typeof DEFAULT_DESKTOP_SETTINGS_VALUES],
    ])),
    DEFAULT_DESKTOP_SETTINGS_VALUES,
  );
  assert.equal(state.launchMode, 'windowed');
  assert.equal(state.guideTimeRange, 'detailed');
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

test('applySettingsAction handles cycleGuideTimeRange state transition', () => {
  let state = createSettingsDraftState();
  state = applySettingsAction(state, 'cycleGuideTimeRange');
  assert.equal(state.guideTimeRange, 'wide');
  state = applySettingsAction(state, 'cycleGuideTimeRange');
  assert.equal(state.guideTimeRange, 'detailed');
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

  assert.deepEqual(sections.map((section) => section.id), [
    'audio-subtitles', 'playback-hdr', 'appearance', 'guide', 'account', 'developer', 'recovery',
  ]);

  const setupSection = sections[6];
  assert.equal(setupSection?.items.length, 4);
  assert.equal(setupSection?.items[0]?.id, 'setup-reminder');
  assert.equal(setupSection?.items[1]?.id, 'setup-channel-count');
  assert.equal(setupSection?.items[1]?.valueLabel, '12');
  assert.equal(setupSection?.items[2]?.id, 'setup-recovery-state');
  assert.equal(setupSection?.items[2]?.valueLabel, 'Recovered');
  assert.equal(setupSection?.items[3]?.id, 'setup-current-channel');
  assert.equal(setupSection?.items[3]?.valueLabel, '101');

  const ids = sections.flatMap((section) => section.items.map((item) => item.id));
  assert.equal(ids.length, 33);
  assert.ok(ids.includes('audio-output'));
  assert.ok(ids.includes('audio-setup-status'));
  assert.ok(ids.includes('now-playing-auto-hide'));
  assert.equal(
    sections[3]?.items
      .filter((item) => ['guide-performance-profile', 'guide-time-range', 'guide-row-density'].includes(item.id))
      .every((item) => !item.disabled),
    true,
  );
});

test('settings sections preserve exact category order, closed options, and disabled truth', () => {
  const sections = createSettingsSections(createSettingsDraftState());
  assert.deepEqual(sections.map((section) => section.title), [
    'Audio & Subtitles', 'Playback & HDR', 'Appearance', 'Guide', 'Account', 'Developer', 'Recovery',
  ]);
  const items = sections.flatMap((section) => section.items);
  assert.equal(items.find((item) => item.id === 'subtitle-mode')?.valueLabel, 'Full (Burn-in, default)');
  assert.equal(items.find((item) => item.id === 'guide-time-range')?.valueLabel, 'Detailed (2h)');
  assert.equal(items.find((item) => item.id === 'info-box-background')?.disabledReason, 'Disabled until safe artwork is available.');
  const guideItems = new Map(sections[3]?.items.map((item) => [item.id, item]) ?? []);
  for (const id of ['guide-performance-profile', 'guide-time-range', 'guide-row-density']) {
    assert.equal(guideItems.get(id)?.disabled, false);
    assert.equal(guideItems.get(id)?.disabledReason, undefined);
  }
  for (const id of ['library-tabs', 'now-watching-banner', 'guide-layout', 'past-items-window']) {
    assert.equal(guideItems.get(id)?.disabled, true);
    assert.equal(guideItems.get(id)?.disabledReason, 'Guide preferences apply to the current Guide.');
  }

  let values = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
  const themes = [values.theme];
  for (let index = 0; index < 4; index += 1) {
    values = nextDesktopSettingsValues(values, 'cycleTheme');
    themes.push(values.theme);
  }
  assert.deepEqual(themes, ['ember-steel', 'slate-pine', 'swiss', 'directv', 'glass']);
  const durations = [values.nowPlayingAutoHideMs];
  for (let index = 0; index < 6; index += 1) {
    values = nextDesktopSettingsValues(values, 'cycleNowPlayingAutoHide');
    durations.push(values.nowPlayingAutoHideMs);
  }
  assert.deepEqual(durations, [0, 5000, 10000, 15000, 30000, 60000, 120000]);
});

test('settings focus ownership exposes the exact fixed-schema interactive controls', () => {
  assert.deepEqual([...createSettingsSectionControlFocusIds()], [
    [
      'settings-category-audio-subtitles',
      [
        'settings-audio-output',
        'settings-dts-passthrough',
        'settings-direct-play-audio-fallback',
        'settings-subtitle-mode',
        'settings-preferred-subtitle-language',
        'settings-prefer-forced-subtitles',
      ],
    ],
    [
      'settings-category-playback-hdr',
      [
        'settings-keep-playback-running',
        'settings-hdr-fallback',
        'settings-transcode-quality',
        'settings-transcode-compatibility',
      ],
    ],
    [
      'settings-category-appearance',
      [
        'settings-launch-mode',
        'settings-info-box-background',
        'settings-theme',
        'settings-cinematic-now-playing',
        'settings-prefer-clear-logos',
        'settings-now-playing-auto-hide',
        'settings-preview-badges',
      ],
    ],
    [
      'settings-category-guide',
      [
        'settings-library-tabs',
        'settings-now-watching-banner',
        'settings-guide-performance-profile',
        'settings-guide-time-range',
        'settings-guide-row-density',
        'settings-guide-layout',
        'settings-past-items-window',
      ],
    ],
    ['settings-category-account', ['settings-profile-picker-startup']],
    [
      'settings-category-developer',
      [
        'settings-debug-logging',
        'settings-subtitle-debug-logging',
        'settings-support-bundle-export',
      ],
    ],
    ['settings-category-recovery', ['settings-setup-reminder']],
  ]);
});

test('Settings Audio Output requires supported capability without gating first-run defaults', () => {
  const conservative = createConservativeDesktopSettingsCapabilities();
  const conservativeRow = createSettingsSections(
    createSettingsDraftState(),
    null,
    conservative,
  )[0]?.items.find((item) => item.id === 'audio-output');
  assert.equal(conservativeRow?.disabled, true);
  assert.equal(
    conservativeRow?.disabledReason,
    'Disabled until native capability verification is complete.',
  );
  assert.equal(isPersistedSettingsActionEnabled('selectAudioOutput', conservative), false);

  const supported = {
    ...conservative,
    audioOutputSelection: { status: 'supported', reason: 'available' } as const,
  };
  const supportedRow = createSettingsSections(
    createSettingsDraftState(),
    null,
    supported,
  )[0]?.items.find((item) => item.id === 'audio-output');
  assert.equal(supportedRow?.disabled, false);
  assert.equal(supportedRow?.disabledReason, undefined);
  assert.equal(isPersistedSettingsActionEnabled('selectAudioOutput', supported), true);
});

test('Settings Audio Output summary describes a non-null preference as saved until enumeration', () => {
  const state = createSettingsDraftState();
  state.audioOutputDeviceId = `audio_${'E'.repeat(43)}`;
  const row = createSettingsSections(state)[0]?.items.find((item) => item.id === 'audio-output');

  assert.equal(row?.valueLabel, 'Saved output');
  assert.equal(
    row?.description,
    'Open Audio Output to check current availability or choose System default.',
  );
});
