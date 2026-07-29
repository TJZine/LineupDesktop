import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  desktopSettingsSuccess,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createAudioSetupRuntime, type AudioSetupState } from '../../renderer/settings/audioSetupRuntime.js';
import { deferred } from '../helpers/deferred.js';

test('audio setup offers System default when enumeration is unavailable and persists completion', async () => {
  let values = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
  let completed = 0;
  const states: AudioSetupState[] = [];
  const runtime = createRuntime({
    getAudioOutputs: async ({ requestId }) => desktopSettingsSuccess(requestId, {
      status: 'unavailable',
      reason: 'platform-unsupported',
      outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
    }),
    getValues: () => values,
    replace: async (transform) => { values = transform(values); },
    onState: (state) => states.push(state),
    onComplete: () => { completed += 1; },
  });

  await runtime.initialize();
  assert.deepEqual(runtime.getState().outputs, [
    { kind: 'system-default', id: 'system-default', label: 'System default' },
  ]);
  await runtime.complete();
  assert.equal(values.audioSetupCompleted, true);
  assert.equal(values.audioOutputDeviceId, null);
  assert.equal(completed, 1);
  assert.equal(states.at(-1)?.status, 'ready');
});

test('audio setup persists only a safe opaque selected device and leaves failure open', async () => {
  const opaqueId = `audio_${'A'.repeat(43)}` as const;
  let values: DesktopSettingsValues = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
  let persist = true;
  const runtime = createRuntime({
    getAudioOutputs: async ({ requestId }) => desktopSettingsSuccess(requestId, {
      status: 'ready',
      reason: 'available',
      outputs: [
        { kind: 'system-default', id: 'system-default', label: 'System default' },
        { kind: 'device', id: opaqueId, label: 'Living Room' },
      ],
    }),
    getValues: () => values,
    replace: async (transform) => {
      if (persist) values = transform(values);
    },
  });
  await runtime.initialize();
  runtime.select(opaqueId);
  await runtime.complete();
  assert.equal(values.audioOutputDeviceId, opaqueId);
  assert.equal(values.audioSetupCompleted, true);

  values = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
  persist = false;
  await runtime.initialize();
  await runtime.complete();
  assert.equal(runtime.getState().status, 'failed');
  assert.match(runtime.getState().message, /Could not save audio setup/u);
});

test('audio setup cleanup ignores a late enumeration result', async () => {
  const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['settings']['getAudioOutputs']>>>();
  const states: AudioSetupState[] = [];
  const runtime = createRuntime({
    getAudioOutputs: () => pending.promise,
    onState: (state) => states.push(state),
  });
  const initializing = runtime.initialize();
  runtime.cleanup();
  pending.resolve(desktopSettingsSuccess('audio-setup-1', {
    status: 'ready',
    reason: 'available',
    outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
  }));
  await initializing;
  assert.equal(states.length, 1);
  assert.equal(states[0]?.status, 'loading');
});

function createRuntime(overrides: {
  getAudioOutputs?: LineupDesktopPreloadApi['settings']['getAudioOutputs'];
  getValues?: () => DesktopSettingsValues;
  replace?: (transform: (values: DesktopSettingsValues) => DesktopSettingsValues) => Promise<void>;
  onState?: (state: AudioSetupState) => void;
  onComplete?: () => void;
}) {
  const defaultValues = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
  return createAudioSetupRuntime({
    settings: {
      getAudioOutputs: overrides.getAudioOutputs ?? (async ({ requestId }) => desktopSettingsSuccess(requestId, {
        status: 'unavailable',
        reason: 'platform-unsupported',
        outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
      })),
      getSnapshot: async () => { throw new Error('not used'); },
      replace: async () => { throw new Error('not used'); },
    },
    getSettingsValues: overrides.getValues ?? (() => defaultValues),
    replaceValues: overrides.replace ?? (async () => undefined),
    onStateChanged: overrides.onState ?? (() => undefined),
    onComplete: overrides.onComplete ?? (() => undefined),
  });
}
