import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  desktopSettingsSuccess,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import {
  createAudioSetupRuntime,
  type AudioSetupState,
} from '../../renderer/settings/audioSetupRuntime.js';
import { canActivateRouteDuringAudioSetup } from '../../renderer/settings/audioSetupNavigation.js';
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

test('audio setup shows an honest missing saved output and persists System Default only on completion', async () => {
  const savedId = `audio_${'B'.repeat(43)}` as const;
  const availableId = `audio_${'C'.repeat(43)}` as const;
  let values: DesktopSettingsValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    audioOutputDeviceId: savedId,
  };
  const runtime = createRuntime({
    getAudioOutputs: async ({ requestId }) => desktopSettingsSuccess(requestId, {
      status: 'ready',
      reason: 'available',
      outputs: [
        { kind: 'system-default', id: 'system-default', label: 'System default' },
        { kind: 'device', id: availableId, label: 'Available output' },
      ],
    }),
    getValues: () => values,
    replace: async (transform) => { values = transform(values); },
  });

  await runtime.initialize();
  assert.deepEqual(runtime.getState(), {
    status: 'ready',
    outputs: [
      { kind: 'system-default', id: 'system-default', label: 'System default' },
      { kind: 'device', id: availableId, label: 'Available output' },
    ],
    selectedId: 'system-default',
    message: 'The saved output is unavailable. System default will be used.',
  });
  assert.equal(values.audioOutputDeviceId, savedId);
  assert.equal(values.audioSetupCompleted, false);

  await runtime.complete();
  assert.equal(values.audioOutputDeviceId, null);
  assert.equal(values.audioSetupCompleted, true);
});

test('audio setup selects a saved output normally when it becomes available again', async () => {
  const savedId = `audio_${'D'.repeat(43)}` as const;
  const values: DesktopSettingsValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    audioOutputDeviceId: savedId,
  };
  const runtime = createRuntime({
    getAudioOutputs: async ({ requestId }) => desktopSettingsSuccess(requestId, {
      status: 'ready',
      reason: 'available',
      outputs: [
        { kind: 'system-default', id: 'system-default', label: 'System default' },
        { kind: 'device', id: savedId, label: 'Saved device' },
      ],
    }),
    getValues: () => values,
  });

  await runtime.initialize();
  assert.equal(runtime.getState().selectedId, savedId);
  assert.equal(runtime.getState().message, 'Choose the audio output Lineup Desktop should use.');
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

test('audio setup contains navigation while enumeration or persistence is in flight', () => {
  assert.equal(canActivateRouteDuringAudioSetup('audioSetup', 'loading', 'player'), false);
  assert.equal(canActivateRouteDuringAudioSetup('audioSetup', 'loading', 'audioSetup'), true);
  assert.equal(canActivateRouteDuringAudioSetup('audioSetup', 'saving', 'guide'), false);
  assert.equal(canActivateRouteDuringAudioSetup('audioSetup', 'saving', 'audioSetup'), true);
  assert.equal(canActivateRouteDuringAudioSetup('audioSetup', 'ready', 'player'), true);
  assert.equal(canActivateRouteDuringAudioSetup('player', 'loading', 'guide'), true);
});

test('audio setup retries a failed save directly and ignores stale initialize results', async () => {
  const firstEnumeration =
    deferred<Awaited<ReturnType<LineupDesktopPreloadApi['settings']['getAudioOutputs']>>>();
  let enumeration = 0;
  let saves = 0;
  let values: DesktopSettingsValues = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
  const runtime = createRuntime({
    getAudioOutputs: ({ requestId }) => {
      enumeration += 1;
      if (enumeration === 1) return firstEnumeration.promise;
      return Promise.resolve(desktopSettingsSuccess(requestId, {
        status: 'unavailable',
        reason: 'platform-unsupported',
        outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
      }));
    },
    getValues: () => values,
    replace: async (transform) => {
      saves += 1;
      if (saves === 1) throw new Error('storage unavailable');
      values = transform(values);
    },
  });

  const staleInitialization = runtime.initialize();
  await runtime.initialize();
  firstEnumeration.resolve(desktopSettingsSuccess('audio-setup-1', {
    status: 'ready',
    reason: 'available',
    outputs: [
      { kind: 'system-default', id: 'system-default', label: 'System default' },
      { kind: 'device', id: `audio_${'Z'.repeat(43)}`, label: 'Stale output' },
    ],
  }));
  await staleInitialization;
  assert.equal(runtime.getState().outputs.length, 1);

  await runtime.complete();
  assert.equal(runtime.getState().status, 'failed');
  await runtime.complete();
  assert.equal(values.audioSetupCompleted, true);
  assert.equal(runtime.getState().status, 'ready');
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
