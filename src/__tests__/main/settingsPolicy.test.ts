import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  type DesktopSettingsCapabilityProjection,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import { DesktopSettingsPolicy } from '../../main/settings/desktopSettingsPolicy.js';

test('desktop settings policy requires hydration and projects exact playback preferences', () => {
  const admission: unknown[] = [];
  const policy = new DesktopSettingsPolicy({
    platform: 'win32',
    nativeHostAvailable: true,
    diagnosticAdmission: {
      setSettingsAdmission: (input) => admission.push(input),
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
    schemaVersion: 2 as const,
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
