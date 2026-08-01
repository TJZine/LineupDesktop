import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  SETTINGS_SCHEMA_VERSION,
  type DesktopSettingsSnapshot,
} from '../../contracts/settings.js';
import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import { registerPlayerIpcHandlers } from '../../main/player/playerIpc.js';
import type { NativePlayerHostPort } from '../../main/player/nativePlayerHostPort.js';
import { createSettingsNativeHostComposition } from '../../main/settings/settingsNativeHostComposition.js';

test('settings/native-host composition creates one production host shared by settings and player', async () => {
  let factoryCalls = 0;
  let audioQueries = 0;
  let lifecycleSubscriptions = 0;
  const host: NativePlayerHostPort = {
    execute: async () => ({ ok: true }),
    queryAudioOutputs: async () => {
      audioQueries += 1;
      return { ok: true, outputs: [] };
    },
    cleanup: async () => undefined,
    onLifecycleFailure: () => {
      lifecycleSubscriptions += 1;
      return () => undefined;
    },
  };
  const composition = createSettingsNativeHostComposition({
    shellMode: 'production',
    platform: 'win32',
    initialSnapshot: settingsSnapshot(),
    createProductionNativeHost: () => {
      factoryCalls += 1;
      return host;
    },
    createRequestId: (prefix) => `${prefix}-1`,
    diagnosticEventStore: new DiagnosticEventStore(),
  });

  assert.equal(factoryCalls, 1);
  assert.equal(composition.nativeHost, host);
  assert.deepEqual(
    composition.settingsPolicy.getPreferences().subtitleMode,
    DEFAULT_DESKTOP_SETTINGS_VALUES.subtitleMode,
  );
  await composition.settingsAudioOutputOwner.getAudioOutputs();
  assert.equal(audioQueries, 1);

  const registration = registerPlayerIpcHandlers({
    shellMode: 'production',
    nativeHost: composition.nativeHost,
    isAuthorizedEvent: () => true,
    sendSynchronousPlayerEvent: () => undefined,
    onAsynchronousAdapterEvents: () => undefined,
    createRequestId: (prefix) => `${prefix}-1`,
    onNativeHostLifecycleFailure: () => undefined,
    ipcMain: {
      handle: () => undefined,
      removeHandler: () => undefined,
    },
  });
  assert.equal(lifecycleSubscriptions, 2);
  await registration.teardown();
});

test('settings/native-host composition keeps production creation out of development and smoke', () => {
  for (const shellMode of ['development', 'smoke'] as const) {
    let factoryCalls = 0;
    const composition = createSettingsNativeHostComposition({
      shellMode,
      platform: 'win32',
      initialSnapshot: settingsSnapshot(),
      createProductionNativeHost: () => {
        factoryCalls += 1;
        throw new Error('production factory must not run');
      },
      createRequestId: (prefix) => `${prefix}-1`,
      diagnosticEventStore: new DiagnosticEventStore(),
    });

    assert.equal(factoryCalls, 0);
    assert.equal(composition.nativeHost, null);
    assert.deepEqual(
      composition.settingsPolicy.getCapabilityProjection().audioOutputSelection,
      { status: 'unsupported', reason: 'helper-unavailable' },
    );
  }
});

test('production player IPC uses the injected host and never calls the development factory hook', async () => {
  let factoryCalls = 0;
  const host: NativePlayerHostPort = {
    execute: async () => ({ ok: true }),
    queryAudioOutputs: async () => ({ ok: true, outputs: [] }),
    cleanup: async () => undefined,
  };
  const handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();
  const registration = registerPlayerIpcHandlers({
    shellMode: 'production',
    nativeHost: host,
    nativeHostFactory: () => {
      factoryCalls += 1;
      return host;
    },
    isAuthorizedEvent: () => true,
    sendSynchronousPlayerEvent: () => undefined,
    onAsynchronousAdapterEvents: () => undefined,
    createRequestId: (prefix) => `${prefix}-1`,
    ipcMain: {
      handle: (channel, handler) => handlers.set(channel, handler as never),
      removeHandler: (channel) => { handlers.delete(channel); },
    },
  });
  assert.equal(factoryCalls, 0);
  assert.ok(registration.adapter);
  await registration.teardown();
});

function settingsSnapshot(): DesktopSettingsSnapshot {
  return {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 1,
    status: 'ready',
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES },
  };
}
