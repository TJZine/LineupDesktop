import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { registerPlayerIpcHandlers } from '../../main/player/playerIpc.js';
import type { NativePlayerHostPort } from '../../main/player/nativePlayerHostPort.js';

test('production main constructs one shared native host and wires roots without lifecycle duplication', () => {
  const source = readFileSync(new URL('../../main/index.ts', import.meta.url), 'utf8');
  assert.equal(source.match(/createProductionNativeHostFactory\(/gu)?.length, 1);
  assert.match(source, /const productionNativeHost = productionNativeHostFactory\?\.\(\) \?\? null;/u);
  assert.match(source, /nativeHost: productionNativeHost,/u);
  assert.match(source, /new SettingsAudioOutputOwner\(\{[\s\S]*?nativeHost: productionNativeHost,/u);
  assert.match(
    source,
    /onNativeHostLifecycleFailure:[\s\S]*?await runtime\?\.handleHelperCrash\(\)/u,
  );
  assert.match(source, /const initialSettingsSnapshot = await settingsStore\.loadSnapshot\(\);/u);
  assert.match(source, /settingsPolicy\.acceptSnapshot\(initialSettingsSnapshot\);/u);
  assert.ok(
    source.indexOf('await settingsStore.loadSnapshot()') <
      source.indexOf('registerSettingsIpcHandlers({'),
  );
  assert.ok(
    source.indexOf('registerSettingsIpcHandlers({') <
      source.indexOf('registerPlayerIpcHandlers({'),
  );
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
