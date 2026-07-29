import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  createDesktopSettingsView,
  desktopSettingsSuccess,
  normalizeDesktopSettingsReplaceValues,
} from '../../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createFullscreenTransportCoordinator } from '../../renderer/fullscreenTransport.js';
import { createSettingsRuntime } from '../../renderer/settings/settingsRuntime.js';
import { createShellController } from '../../renderer/shell/shellController.js';
import { createRendererShellState } from '../../renderer/shell/shellState.js';
import { deferred } from '../helpers/deferred.js';

test('fullscreen coordinator serializes settings and stale shell intents while reconciling native state', async () => {
  type FullscreenResult = Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>;
  const enter = deferred<FullscreenResult>();
  const exit = deferred<FullscreenResult>();
  const enterStarted = deferred<void>();
  const exitStarted = deferred<void>();
  const calls: boolean[] = [];
  const reconciled: boolean[] = [];
  let activeCalls = 0;
  let maximumActiveCalls = 0;
  let initialized = false;

  const transport = createFullscreenTransportCoordinator({
    bridge: {
      setFullscreen: async (enabled) => {
        calls.push(enabled);
        if (!initialized) {
          initialized = true;
          return { ok: true, requestId: 'settings-initial', value: { enabled } };
        }
        activeCalls += 1;
        maximumActiveCalls = Math.max(maximumActiveCalls, activeCalls);
        if (enabled) enterStarted.resolve();
        if (!enabled) exitStarted.resolve();
        const result = await (enabled ? enter.promise : exit.promise);
        activeCalls -= 1;
        return result;
      },
    },
    reconcile: (enabled) => reconciled.push(enabled),
  });

  const settings = createSettingsRuntime({
    settings: {
      getAudioOutputs: async ({ requestId }) => desktopSettingsSuccess(requestId, {
        status: 'unavailable',
        reason: 'platform-unsupported',
        outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
      }),
      getSnapshot: async ({ requestId }) => desktopSettingsSuccess(requestId, createDesktopSettingsView({
        schemaVersion: 2,
        revision: 1,
        status: 'ready',
        values: DEFAULT_DESKTOP_SETTINGS_VALUES,
      })),
      replace: async ({ requestId, values }) => desktopSettingsSuccess(requestId, createDesktopSettingsView({
        schemaVersion: 2,
        revision: 2,
        status: 'ready',
        values: normalizeDesktopSettingsReplaceValues(values),
      })),
    },
    windowBridge: transport,
    onStateChanged: () => undefined,
  });
  await settings.initialize();
  calls.length = 0;
  reconciled.length = 0;

  let shellState = createRendererShellState();
  const shell = createShellController({
    shell: { getCapabilities: async () => { throw new Error('not used'); }, onStatusChanged: () => () => undefined },
    windowBridge: transport,
    host: { setTimeout: () => 1, clearTimeout: () => undefined },
    getState: () => shellState,
    setState: (state) => { shellState = state; },
    render: () => undefined,
    applyCapabilities: () => undefined,
    restoreFocus: () => undefined,
  });

  const settingsIntent = settings.applyAction('cycleLaunchMode');
  const shellIntent = shell.requestFullscreen(false, 'player-fullscreen');
  shell.invalidateFullscreenRequest();

  await enterStarted.promise;
  assert.deepEqual(calls, [true]);
  enter.resolve({ ok: true, requestId: 'settings-enter', value: { enabled: true } });
  await exitStarted.promise;
  assert.deepEqual(calls, [true, false]);
  exit.resolve({ ok: true, requestId: 'shell-exit', value: { enabled: false } });
  await Promise.all([settingsIntent, shellIntent]);

  assert.equal(maximumActiveCalls, 1);
  assert.deepEqual(reconciled, [true, false]);
  assert.equal(reconciled.at(-1), false);
  assert.equal(shellState.fullscreenPending, false);
  assert.equal(shellState.inlineError, null);
});

test('fullscreen coordinator coalesces adjacent duplicate intents', async () => {
  type FullscreenResult = Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>>;
  const pending = deferred<FullscreenResult>();
  let calls = 0;
  const coordinator = createFullscreenTransportCoordinator({
    bridge: {
      setFullscreen: () => {
        calls += 1;
        return pending.promise;
      },
    },
    reconcile: () => undefined,
  });

  const first = coordinator.setFullscreen(true);
  const duplicate = coordinator.setFullscreen(true);
  assert.equal(first, duplicate);
  pending.resolve({ ok: true, requestId: 'duplicate-enter', value: { enabled: true } });
  await Promise.all([first, duplicate]);
  assert.equal(calls, 1);
});
