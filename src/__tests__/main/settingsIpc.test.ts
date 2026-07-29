import test from 'node:test';
import assert from 'node:assert/strict';

import {
  LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
  LINEUP_SETTINGS_REPLACE_CHANNEL,
} from '../../contracts/ipc.js';
import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  createDesktopSettingsView,
} from '../../contracts/settings.js';
import { DesktopSettingsStoreError } from '../../main/persistence/desktopSettingsStore.js';
import { registerSettingsIpcHandlers } from '../../main/settings/settingsIpc.js';

type SuccessfulSettingsView = { value: ReturnType<typeof view> };

test('settings IPC authorizes, validates, echoes request ids, and registers exactly two handlers', async () => {
  const handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();
  const removed: string[] = [];
  let writes = 0;
  const teardown = registerSettingsIpcHandlers({
    store: {
      loadSnapshot: async () => snapshot(3),
      replace: async (_revision, values) => { writes++; return { ...snapshot(4), values }; },
    },
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    ipcMain: {
      handle: (channel, handler) => handlers.set(channel, handler as never),
      removeHandler: (channel) => { removed.push(channel); },
    },
  });
  assert.deepEqual([...handlers.keys()], [LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL, LINEUP_SETTINGS_REPLACE_CHANNEL]);
  const get = handlers.get(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL)!;
  const replace = handlers.get(LINEUP_SETTINGS_REPLACE_CHANNEL)!;
  assert.deepEqual(await get('authorized', { requestId: 'settings-get-1' }), {
    ok: true, requestId: 'settings-get-1', value: view(3),
  });
  const unauthorized = await get('other', { requestId: 'settings-get-2' }) as { error: { code: string } };
  assert.equal(unauthorized.error.code, 'unauthorized');
  const invalid = await replace('authorized', { requestId: 'bad id' }) as { requestId: string; error: { code: string } };
  assert.equal(invalid.requestId, 'settings-invalid-request');
  assert.equal(invalid.error.code, 'validation-failed');
  assert.equal(writes, 0);
  teardown();
  assert.deepEqual(removed, [LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL, LINEUP_SETTINGS_REPLACE_CHANNEL]);
});

test('settings IPC canonicalizes only exact system-default and clones capabilities per response', async () => {
  const handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();
  const storedValues: unknown[] = [];
  registerSettingsIpcHandlers({
    store: {
      loadSnapshot: async () => snapshot(2),
      replace: async (_revision, values) => {
        storedValues.push(values);
        return { ...snapshot(3), values };
      },
    },
    isAuthorizedEvent: () => true,
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
  });
  const get = handlers.get(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL)!;
  const replace = handlers.get(LINEUP_SETTINGS_REPLACE_CHANNEL)!;
  const first = await get({}, { requestId: 'settings-get-capabilities-1' }) as SuccessfulSettingsView;
  const second = await get({}, { requestId: 'settings-get-capabilities-2' }) as SuccessfulSettingsView;
  assert.deepEqual(first.value.capabilities, second.value.capabilities);
  assert.notEqual(first.value.capabilities, second.value.capabilities);
  assert.notEqual(first.value.capabilities.audioOutputSelection, second.value.capabilities.audioOutputSelection);

  const systemDefault = await replace({}, {
    requestId: 'settings-replace-system',
    expectedRevision: 2,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId: 'system-default' },
  }) as SuccessfulSettingsView;
  assert.equal((storedValues[0] as { audioOutputDeviceId: unknown }).audioOutputDeviceId, null);
  assert.equal(systemDefault.value.snapshot.values.audioOutputDeviceId, null);

  const opaqueId = `audio_${'z'.repeat(43)}`;
  await replace({}, {
    requestId: 'settings-replace-device',
    expectedRevision: 3,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId: opaqueId },
  });
  assert.equal((storedValues[1] as { audioOutputDeviceId: unknown }).audioOutputDeviceId, opaqueId);

  for (const audioOutputDeviceId of [` ${opaqueId}`, `${opaqueId} `, ' system-default', 'native-device']) {
    const result = await replace({}, {
      requestId: 'settings-replace-invalid-audio',
      expectedRevision: 3,
      values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId },
    }) as { ok: false; error: { code: string } };
    assert.equal(result.error.code, 'validation-failed');
  }
  assert.equal(storedValues.length, 2);
});

test('settings IPC maps every store failure to fixed renderer-safe results and never rejects', async () => {
  for (const code of ['storage-unavailable', 'unsupported-version', 'revision-conflict', 'operation-failed'] as const) {
    const handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();
    registerSettingsIpcHandlers({
      store: {
        loadSnapshot: async () => { throw new DesktopSettingsStoreError(code); },
        replace: async () => { throw new DesktopSettingsStoreError(code); },
      },
      isAuthorizedEvent: () => true,
      ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
    });
    const getResult = await handlers.get(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL)!({}, { requestId: 'settings-get-safe' }) as {
      ok: boolean; error: { code: string; message: string };
    };
    const replaceResult = await handlers.get(LINEUP_SETTINGS_REPLACE_CHANNEL)!({}, {
      requestId: 'settings-replace-safe',
      expectedRevision: 0,
      values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    }) as { ok: boolean; error: { code: string; message: string } };
    assert.equal(getResult.ok, false);
    assert.equal(getResult.error.code, code);
    assert.equal(replaceResult.ok, false);
    assert.equal(replaceResult.error.code, code);
    assert.doesNotMatch(JSON.stringify([getResult, replaceResult]), /Users|settings\.json|private detail/u);
  }
});

test('settings IPC rejects unauthorized and invalid payloads per handler without calling the store', async () => {
  const handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();
  let reads = 0;
  let writes = 0;
  registerSettingsIpcHandlers({
    store: {
      loadSnapshot: async () => { reads += 1; return snapshot(1); },
      replace: async (_revision, values) => { writes += 1; return { ...snapshot(2), values }; },
    },
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
  });
  const get = handlers.get(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL)!;
  const replace = handlers.get(LINEUP_SETTINGS_REPLACE_CHANNEL)!;
  for (const result of [
    await get('unauthorized', { requestId: 'settings-get-unauthorized' }),
    await replace('unauthorized', {
      requestId: 'settings-replace-unauthorized', expectedRevision: 0, values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    }),
  ] as Array<{ error: { code: string } }>) {
    assert.equal(result.error.code, 'unauthorized');
  }
  for (const result of [
    await get('authorized', { requestId: 'settings-get-invalid', extra: true }),
    await replace('authorized', {
      requestId: 'settings-replace-invalid', expectedRevision: -1, values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    }),
  ] as Array<{ error: { code: string } }>) {
    assert.equal(result.error.code, 'validation-failed');
  }
  assert.equal(reads, 0);
  assert.equal(writes, 0);
});

test('settings IPC maps unexpected handler exceptions to a fixed operation failure', async () => {
  const handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();
  registerSettingsIpcHandlers({
    store: {
      loadSnapshot: async () => {
        throw new Error(['', 'Users', 'private', 'settings.json'].join('/'));
      },
      replace: async () => { throw new Error('private replacement detail'); },
    },
    isAuthorizedEvent: () => true,
    ipcMain: { handle: (channel, handler) => handlers.set(channel, handler as never), removeHandler: () => undefined },
  });
  const results = [
    await handlers.get(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL)!({}, { requestId: 'settings-get-unexpected' }),
    await handlers.get(LINEUP_SETTINGS_REPLACE_CHANNEL)!({}, {
      requestId: 'settings-replace-unexpected', expectedRevision: 0, values: DEFAULT_DESKTOP_SETTINGS_VALUES,
    }),
  ] as Array<{ error: { code: string; message: string } }>;
  for (const result of results) {
    assert.deepEqual(result.error, {
      code: 'operation-failed',
      message: 'Desktop settings operation failed.',
    });
    assert.doesNotMatch(JSON.stringify(result), /Users|settings\.json|private/u);
  }
});

function snapshot(revision: number) {
  return { schemaVersion: 2 as const, revision, status: 'ready' as const, values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES } };
}

function view(revision: number) {
  return createDesktopSettingsView(snapshot(revision));
}
