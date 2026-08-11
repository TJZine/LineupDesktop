import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  type DesktopSettingsCapabilityProjection,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import { DesktopSettingsPolicy } from '../../main/settings/desktopSettingsPolicy.js';

test('desktop settings policy requires hydration and projects exact playback preferences', () => {
  const admission: unknown[] = [];
  const events: unknown[] = [];
  const policy = new DesktopSettingsPolicy({
    platform: 'win32',
    nativeHostAvailable: true,
    diagnosticAdmission: {
      setSettingsAdmission: (input) => admission.push(input),
      recordSettingsDebug: (input) => events.push(input),
    },
  });
  assert.throws(() => policy.getPreferences(), /not been hydrated/u);

  policy.acceptSnapshot(snapshot({
    audioOutputDeviceId: `audio_${'A'.repeat(43)}`,
    dtsPassthroughEnabled: true,
    directPlayAudioFallbackEnabled: true,
    subtitleMode: 'standard',
    preferredSubtitleLanguage: 'fr',
    preferForcedSubtitlesEnabled: true,
    hdrFallbackMode: 'prefer-hdr10',
    transcodeQuality: '4000-720p',
    transcodeCompatibilityModeEnabled: true,
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: true,
  }));

  assert.deepEqual(policy.getPreferences(), {
    audioOutputDeviceId: `audio_${'A'.repeat(43)}`,
    dtsPassthroughEnabled: true,
    directPlayAudioFallbackEnabled: true,
    subtitleMode: 'standard',
    preferredSubtitleLanguage: 'fr',
    preferForcedSubtitlesEnabled: true,
    hdrFallbackMode: 'prefer-hdr10',
    transcodeQuality: '4000-720p',
    transcodeCompatibilityModeEnabled: true,
  });
  assert.deepEqual(admission, [{
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: true,
  }]);
  assert.deepEqual(events, [{
    surface: 'main',
    category: 'lifecycle',
    severity: 'debug',
    status: 'observed',
    operation: 'settings.snapshot.accepted',
    message: 'Desktop settings snapshot accepted.',
    result: 'success',
    context: {
      revision: 1,
      subtitleDebugLoggingEnabled: true,
    },
  }]);
});

test('desktop settings snapshot diagnostics follow general admission with exact safe context', () => {
  let eventId = 0;
  const diagnostics = new DiagnosticEventStore({
    clock: () => 1_000,
    idGenerator: () => `settings-event-${String(++eventId)}`,
  });
  const policy = new DesktopSettingsPolicy({
    platform: 'win32',
    nativeHostAvailable: true,
    diagnosticAdmission: diagnostics,
  });

  policy.acceptSnapshot({ ...snapshot({}), revision: 3 });
  assert.equal(diagnostics.getRecords().length, 0);

  policy.acceptSnapshot({
    ...snapshot({ debugLoggingEnabled: true }),
    revision: 7,
  });
  policy.acceptSnapshot({
    ...snapshot({
      debugLoggingEnabled: true,
      subtitleDebugLoggingEnabled: true,
    }),
    revision: 9,
  });

  assert.deepEqual(
    diagnostics.getRecords().map(({ surface, category, severity, status, operation, message, result, context }) => ({
      surface,
      category,
      severity,
      status,
      operation,
      message,
      result,
      context,
    })),
    [
      {
        surface: 'main',
        category: 'lifecycle',
        severity: 'debug',
        status: 'observed',
        operation: 'settings.snapshot.accepted',
        message: 'Desktop settings snapshot accepted.',
        result: 'success',
        context: {
          revision: 7,
          subtitleDebugLoggingEnabled: false,
        },
      },
      {
        surface: 'main',
        category: 'lifecycle',
        severity: 'debug',
        status: 'observed',
        operation: 'settings.snapshot.accepted',
        message: 'Desktop settings snapshot accepted.',
        result: 'success',
        context: {
          revision: 9,
          subtitleDebugLoggingEnabled: true,
        },
      },
    ],
  );
});

test('desktop settings policy retains an accepted snapshot when optional diagnostic recording throws', () => {
  const admission: unknown[] = [];
  const policy = new DesktopSettingsPolicy({
    platform: 'win32',
    nativeHostAvailable: true,
    diagnosticAdmission: {
      setSettingsAdmission: (input) => admission.push(input),
      recordSettingsDebug() {
        throw new Error('diagnostic recording failed');
      },
    },
  });
  const acceptedSnapshot = snapshot({
    audioOutputDeviceId: `audio_${'F'.repeat(43)}`,
    dtsPassthroughEnabled: true,
    directPlayAudioFallbackEnabled: false,
    subtitleMode: 'off',
    preferredSubtitleLanguage: 'de',
    preferForcedSubtitlesEnabled: true,
    hdrFallbackMode: 'force-hls',
    transcodeQuality: '2000-720p',
    transcodeCompatibilityModeEnabled: true,
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: false,
  });

  assert.doesNotThrow(() => policy.acceptSnapshot(acceptedSnapshot));
  assert.deepEqual(admission, [{
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: false,
  }]);
  assert.deepEqual(policy.getPreferences(), {
    audioOutputDeviceId: `audio_${'F'.repeat(43)}`,
    dtsPassthroughEnabled: true,
    directPlayAudioFallbackEnabled: false,
    subtitleMode: 'off',
    preferredSubtitleLanguage: 'de',
    preferForcedSubtitlesEnabled: true,
    hdrFallbackMode: 'force-hls',
    transcodeQuality: '2000-720p',
    transcodeCompatibilityModeEnabled: true,
  });
});

test('desktop settings policy remains hydrated when diagnostic admission throws', () => {
  const policy = new DesktopSettingsPolicy({
    platform: 'win32',
    nativeHostAvailable: true,
    diagnosticAdmission: {
      setSettingsAdmission() {
        throw new Error('diagnostic admission failed');
      },
      recordSettingsDebug() {
        throw new Error('must not escape');
      },
    },
  });
  const acceptedSnapshot = snapshot({ subtitleMode: 'standard' });

  assert.doesNotThrow(() => policy.acceptSnapshot(acceptedSnapshot));
  assert.equal(policy.getPreferences().subtitleMode, 'standard');
});

test('desktop settings policy preserves conservative production capability truth', () => {
  const windows = hydratedPolicy('win32', true);
  assert.deepEqual(windows.getCapabilityProjection().audioOutputSelection, {
    status: 'unproven',
    reason: 'native-proof-required',
  });
  assert.deepEqual(hydratedPolicy('linux', true).getCapabilityProjection().audioOutputSelection, {
    status: 'unsupported',
    reason: 'platform-unsupported',
  });
  assert.deepEqual(hydratedPolicy('win32', false).getCapabilityProjection().audioOutputSelection, {
    status: 'unsupported',
    reason: 'helper-unavailable',
  });
  for (const capabilities of [
    windows.getCapabilityProjection(),
    hydratedPolicy('linux', true).getCapabilityProjection(),
    hydratedPolicy('win32', false).getCapabilityProjection(),
  ]) {
    assert.deepEqual(withoutAudio(capabilities), {
      dtsPassthrough: { status: 'unproven', reason: 'native-proof-required' },
      directPlayAudioFallback: { status: 'supported', reason: 'available' },
      subtitleSelection: { status: 'unsupported', reason: 'production-capability-unsupported' },
      hdrFallback: { status: 'unsupported', reason: 'production-capability-unsupported' },
      transcode: { status: 'unsupported', reason: 'production-capability-unsupported' },
      artworkPresentation: { status: 'unsupported', reason: 'safe-artwork-unavailable' },
    });
  }
});

function hydratedPolicy(
  platform: ConstructorParameters<typeof DesktopSettingsPolicy>[0]['platform'],
  nativeHostAvailable: boolean,
) {
  const policy = new DesktopSettingsPolicy({ platform, nativeHostAvailable });
  policy.acceptSnapshot(snapshot({}));
  return policy;
}

function snapshot(overrides: Partial<DesktopSettingsValues>) {
  return {
    schemaVersion: 3 as const,
    revision: 1,
    status: 'ready' as const,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, ...overrides },
  };
}

function withoutAudio(capabilities: DesktopSettingsCapabilityProjection) {
  return {
    dtsPassthrough: capabilities.dtsPassthrough,
    directPlayAudioFallback: capabilities.directPlayAudioFallback,
    subtitleSelection: capabilities.subtitleSelection,
    hdrFallback: capabilities.hdrFallback,
    transcode: capabilities.transcode,
    artworkPresentation: capabilities.artworkPresentation,
  };
}
