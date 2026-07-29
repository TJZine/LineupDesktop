import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES,
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  createDesktopSettingsView,
  desktopSettingsFailure,
  desktopSettingsSuccess,
  normalizeDesktopSettingsReplaceValues,
} from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createSettingsRuntime, type SettingsRuntimeState } from '../../renderer/settings/settingsRuntime.js';
import { deferred } from '../helpers/deferred.js';

test('settings runtime loads before presentation, applies launch intent, and persists whole snapshots', async () => {
  const replaceInputs: unknown[] = [];
  const fullscreen: boolean[] = [];
  const states: SettingsRuntimeState[] = [];
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(4, { launchMode: 'fullscreen' })),
      replace: async (input) => {
        replaceInputs.push(input);
        return desktopSettingsSuccess(input.requestId, snapshot(
          5,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: windowBridge(fullscreen),
    onStateChanged: (state) => states.push(state),
  });
  await runtime.initialize();
  assert.deepEqual(fullscreen, [true]);
  await runtime.applyAction('cycleGuideDensity');
  assert.deepEqual(replaceInputs[0], {
    requestId: 'settings-replace-1', expectedRevision: 4,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, launchMode: 'fullscreen', guideDensity: 'compact' },
  });
  assert.equal(states.at(-1)?.snapshot?.revision, 5);
  assert.deepEqual(states.at(-1)?.capabilities, CONSERVATIVE_DESKTOP_SETTINGS_CAPABILITIES);
});

test('settings runtime serializes a user launch change behind pending startup fullscreen', async () => {
  const startupFullscreen = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  const startupCalled = deferred<void>();
  const windowedCorrection = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  const correctionCalled = deferred<void>();
  const fullscreenCalls: boolean[] = [];
  const replacements: Array<Parameters<LineupDesktopPreloadApi['settings']['replace']>[0]> = [];
  let activeIntents = 0;
  let maximumActiveIntents = 0;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(
        requestId,
        snapshot(3, { launchMode: 'fullscreen' }),
      ),
      replace: async (input) => {
        replacements.push(input);
        return desktopSettingsSuccess(input.requestId, snapshot(
          4,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: {
      setFullscreen: async (enabled) => {
        fullscreenCalls.push(enabled);
        activeIntents += 1;
        maximumActiveIntents = Math.max(maximumActiveIntents, activeIntents);
        if (enabled) startupCalled.resolve();
        else correctionCalled.resolve();
        const result = await (enabled ? startupFullscreen.promise : windowedCorrection.promise);
        activeIntents -= 1;
        return result;
      },
    },
    onStateChanged: () => undefined,
  });

  const initializing = runtime.initialize();
  await startupCalled.promise;
  assert.equal(runtime.getState().loading, true);
  assert.equal(runtime.getState().values.launchMode, 'fullscreen');

  const userAction = runtime.applyAction('cycleLaunchMode');
  assert.equal(runtime.getState().values.launchMode, 'windowed');
  assert.deepEqual(fullscreenCalls, [true]);

  startupFullscreen.resolve({ ok: true, requestId: 'window-startup', value: { enabled: true } });
  await correctionCalled.promise;
  assert.deepEqual(fullscreenCalls, [true, false]);

  windowedCorrection.resolve({ ok: true, requestId: 'window-user', value: { enabled: false } });
  await Promise.all([initializing, userAction]);

  assert.equal(maximumActiveIntents, 1);
  assert.deepEqual(replacements, [{
    requestId: 'settings-replace-1',
    expectedRevision: 3,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, launchMode: 'windowed' },
  }]);
  assert.equal(runtime.getState().loading, false);
  assert.equal(runtime.getState().saving, false);
  assert.equal(runtime.getState().values.launchMode, 'windowed');
  assert.equal(runtime.getState().snapshot?.revision, 4);
  assert.equal(runtime.getState().snapshot?.values.launchMode, 'windowed');
  assert.equal(runtime.getState().errorCode, null);
  assert.equal(runtime.getState().errorMessage, null);
});

test('settings runtime coalesces latest desired values and rebases once after revision conflict', async () => {
  type SettingsReplaceInput = Parameters<LineupDesktopPreloadApi['settings']['replace']>[0];
  type SettingsReplaceResult = Awaited<ReturnType<LineupDesktopPreloadApi['settings']['replace']>>;
  const first = deferred<SettingsReplaceResult>();
  const inputs: SettingsReplaceInput[] = [];
  let gets = 0;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, gets++ === 0 ? snapshot(1) : snapshot(8)),
      replace: async (input) => {
        inputs.push(input);
        if (inputs.length === 1) return first.promise;
        return desktopSettingsSuccess(input.requestId, snapshot(
          9,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: windowBridge([]), onStateChanged: () => undefined,
  });
  await runtime.initialize();
  const compact = runtime.applyAction('cycleGuideDensity');
  const hidden = runtime.applyAction('togglePreviewBadges');
  first.resolve(desktopSettingsFailure('settings-replace-1', 'revision-conflict'));
  await Promise.all([compact, hidden]);
  assert.equal(inputs.length, 2);
  assert.equal(inputs[1]?.expectedRevision, 8);
  assert.equal(inputs[1]?.values.guideDensity, 'compact');
  assert.equal(inputs[1]?.values.previewBadgesEnabled, false);
});

test('settings runtime synchronizes a rebased launch mode before retrying persistence', async () => {
  type SettingsReplaceInput = Parameters<LineupDesktopPreloadApi['settings']['replace']>[0];
  type SettingsReplaceResult = Awaited<ReturnType<LineupDesktopPreloadApi['settings']['replace']>>;
  type FullscreenResult = Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>;
  const firstReplace = deferred<SettingsReplaceResult>();
  const fullscreenRetry = deferred<FullscreenResult>();
  const fullscreenRetryCalled = deferred<void>();
  const inputs: SettingsReplaceInput[] = [];
  const fullscreenCalls: boolean[] = [];
  let gets = 0;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(
        requestId,
        gets++ === 0 ? snapshot(1) : snapshot(8),
      ),
      replace: async (input) => {
        inputs.push(input);
        if (inputs.length === 1) return firstReplace.promise;
        return desktopSettingsSuccess(input.requestId, snapshot(
          9,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: {
      setFullscreen: async (enabled) => {
        fullscreenCalls.push(enabled);
        if (!enabled) return { ok: true, requestId: 'window-initial', value: { enabled } };
        fullscreenRetryCalled.resolve();
        return fullscreenRetry.promise;
      },
    },
    onStateChanged: () => undefined,
  });

  await runtime.initialize();
  const density = runtime.applyAction('cycleGuideDensity');
  const launch = runtime.applyAction('cycleLaunchMode');
  firstReplace.resolve(desktopSettingsFailure('settings-replace-1', 'revision-conflict'));
  await fullscreenRetryCalled.promise;

  assert.deepEqual(fullscreenCalls, [false, true]);
  assert.equal(inputs.length, 1);

  fullscreenRetry.resolve({ ok: true, requestId: 'window-rebase', value: { enabled: true } });
  await Promise.all([density, launch]);

  assert.equal(inputs.length, 2);
  assert.equal(inputs[1]?.expectedRevision, 8);
  assert.equal(inputs[1]?.values.launchMode, 'fullscreen');
  assert.equal(inputs[1]?.values.guideDensity, 'compact');
});

test('settings runtime keeps newer whole-snapshot intent behind pending fullscreen', async () => {
  const fullscreen = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  const inputs: Array<Parameters<LineupDesktopPreloadApi['settings']['replace']>[0]> = [];
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(1)),
      replace: async (input) => {
        inputs.push(input);
        return desktopSettingsSuccess(input.requestId, snapshot(
          2,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: { setFullscreen: async (enabled) => enabled
      ? fullscreen.promise
      : { ok: true, requestId: 'window-off', value: { enabled: false } } },
    onStateChanged: () => undefined,
  });
  await runtime.initialize();
  const launch = runtime.applyAction('cycleLaunchMode');
  const badges = runtime.applyAction('togglePreviewBadges');
  fullscreen.resolve({ ok: true, requestId: 'window-on', value: { enabled: true } });
  await Promise.all([launch, badges]);
  assert.equal(inputs.length, 1);
  assert.deepEqual(inputs[0]?.values, {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    launchMode: 'fullscreen',
    previewBadgesEnabled: false,
  });
});

test('settings runtime rolls optimistic values and fullscreen intent back on save failure', async () => {
  const fullscreen: boolean[] = [];
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(2)),
      replace: async (input) => desktopSettingsFailure(input.requestId, 'operation-failed'),
    },
    windowBridge: windowBridge(fullscreen), onStateChanged: () => undefined,
  });
  await runtime.initialize();
  await runtime.applyAction('cycleLaunchMode');
  assert.deepEqual(fullscreen, [false, true, false]);
  assert.equal(runtime.getState().values.launchMode, 'windowed');
  assert.equal(runtime.getState().errorCode, 'operation-failed');
});

test('settings runtime cleanup invalidates late responses without rendering', async () => {
  const pending = deferred<ReturnType<typeof desktopSettingsSuccess<ReturnType<typeof snapshot>>>>();
  const states: SettingsRuntimeState[] = [];
  const runtime = createSettingsRuntime({
    settings: { getSnapshot: async () => pending.promise, replace: async (input) => desktopSettingsFailure(input.requestId, 'operation-failed') },
    windowBridge: windowBridge([]), onStateChanged: (state) => states.push(state),
  });
  const initializing = runtime.initialize();
  runtime.cleanup();
  pending.resolve(desktopSettingsSuccess('settings-get-1', snapshot(3)));
  await initializing;
  assert.equal(states.length, 1);
  assert.equal(runtime.getState().snapshot, null);
});

test('settings runtime cleanup invalidates a late fullscreen consumer continuation before persistence', async () => {
  const pendingFullscreen = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  const states: SettingsRuntimeState[] = [];
  let fullscreenCalls = 0;
  let replacements = 0;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(1)),
      replace: async (input) => {
        replacements += 1;
        return desktopSettingsSuccess(input.requestId, snapshot(
          2,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: {
      setFullscreen: async (enabled) => fullscreenCalls++ === 0
        ? { ok: true, requestId: 'window-initial', value: { enabled } }
        : pendingFullscreen.promise,
    },
    onStateChanged: (state) => states.push(state),
  });
  await runtime.initialize();
  const action = runtime.applyAction('cycleLaunchMode');
  const stateCountAtCleanup = states.length;
  runtime.cleanup();
  pendingFullscreen.resolve({ ok: true, requestId: 'window-late', value: { enabled: true } });
  await action;
  assert.equal(replacements, 0);
  assert.equal(states.length, stateCountAtCleanup);
});

test('settings runtime serializes rapid launch intents and persists only the latest whole snapshot', async () => {
  const enable = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  const disable = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>>();
  const disableCalled = deferred<void>();
  const fullscreenCalls: boolean[] = [];
  const replacements: Array<Parameters<LineupDesktopPreloadApi['settings']['replace']>[0]> = [];
  let activeIntents = 0;
  let maximumActiveIntents = 0;
  let initialized = false;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(1)),
      replace: async (input) => {
        replacements.push(input);
        return desktopSettingsSuccess(input.requestId, snapshot(
          2,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: {
      setFullscreen: async (enabled) => {
        fullscreenCalls.push(enabled);
        if (!initialized) return { ok: true, requestId: 'window-initial', value: { enabled } };
        activeIntents += 1;
        maximumActiveIntents = Math.max(maximumActiveIntents, activeIntents);
        if (!enabled) disableCalled.resolve();
        const result = await (enabled ? enable.promise : disable.promise);
        activeIntents -= 1;
        return result;
      },
    },
    onStateChanged: () => undefined,
  });
  await runtime.initialize();
  initialized = true;
  const launch = runtime.applyAction('cycleLaunchMode');
  const returnWindowed = runtime.applyAction('cycleLaunchMode');
  assert.deepEqual(fullscreenCalls, [false, true]);
  enable.resolve({ ok: true, requestId: 'window-enable', value: { enabled: true } });
  await disableCalled.promise;
  assert.deepEqual(fullscreenCalls, [false, true, false]);
  disable.resolve({ ok: true, requestId: 'window-disable', value: { enabled: false } });
  await Promise.all([launch, returnWindowed]);
  assert.equal(maximumActiveIntents, 1);
  assert.equal(replacements.length, 1);
  assert.equal(replacements[0]?.values.launchMode, 'windowed');
});

test('settings runtime treats a successful but mismatched fullscreen result as a fixed operation failure', async () => {
  let initialized = false;
  let replacements = 0;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(1)),
      replace: async (input) => {
        replacements += 1;
        return desktopSettingsSuccess(input.requestId, snapshot(
          2,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: {
      setFullscreen: async (enabled) => initialized
        ? { ok: true, requestId: 'window-mismatch', value: { enabled: false } }
        : { ok: true, requestId: 'window-initial', value: { enabled } },
    },
    onStateChanged: () => undefined,
  });
  await runtime.initialize();
  initialized = true;
  await runtime.applyAction('cycleLaunchMode');
  assert.equal(replacements, 0);
  assert.equal(runtime.getState().values.launchMode, 'windowed');
  assert.equal(runtime.getState().errorCode, 'operation-failed');
  assert.equal(runtime.getState().errorMessage, 'Desktop settings operation failed.');
});

test('settings runtime preserves newer nonlaunch intent after an older replace fails', async () => {
  const firstReplace = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['settings']['replace']>>>();
  const inputs: Array<Parameters<LineupDesktopPreloadApi['settings']['replace']>[0]> = [];
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, snapshot(1)),
      replace: async (input) => {
        inputs.push(input);
        if (inputs.length === 1) return firstReplace.promise;
        return desktopSettingsSuccess(input.requestId, snapshot(
          2,
          normalizeDesktopSettingsReplaceValues(input.values),
        ));
      },
    },
    windowBridge: windowBridge([]),
    onStateChanged: () => undefined,
  });
  await runtime.initialize();
  const density = runtime.applyAction('cycleGuideDensity');
  const badges = runtime.applyAction('togglePreviewBadges');
  firstReplace.resolve(desktopSettingsFailure('settings-replace-1', 'operation-failed'));
  await Promise.all([density, badges]);
  assert.equal(inputs.length, 2);
  assert.equal(inputs[1]?.values.guideDensity, 'compact');
  assert.equal(inputs[1]?.values.previewBadgesEnabled, false);
  assert.equal(runtime.getState().snapshot?.revision, 2);
});

test('settings runtime stops after one failed conflict rebase and restores accepted values', async () => {
  let gets = 0;
  let replacements = 0;
  const runtime = createSettingsRuntime({
    settings: {
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, gets++ === 0 ? snapshot(1) : snapshot(7)),
      replace: async (input) => {
        replacements += 1;
        return desktopSettingsFailure(input.requestId, 'revision-conflict');
      },
    },
    windowBridge: windowBridge([]),
    onStateChanged: () => undefined,
  });
  await runtime.initialize();
  await runtime.applyAction('cycleGuideDensity');
  assert.equal(gets, 2);
  assert.equal(replacements, 2);
  assert.equal(runtime.getState().values.guideDensity, 'comfortable');
  assert.equal(runtime.getState().snapshot?.revision, 7);
  assert.equal(runtime.getState().errorCode, 'revision-conflict');
});

function snapshot(revision: number, overrides: Partial<typeof DEFAULT_DESKTOP_SETTINGS_VALUES> = {}) {
  return createDesktopSettingsView({
    schemaVersion: 2,
    revision,
    status: 'ready',
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, ...overrides },
  });
}

function windowBridge(calls: boolean[]): LineupDesktopPreloadApi['window'] {
  return { setFullscreen: async (enabled) => {
    calls.push(enabled);
    return { ok: true, requestId: 'window-1', value: { enabled } };
  } };
}
