import assert from 'node:assert/strict';
import test from 'node:test';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  SETTINGS_SCHEMA_VERSION,
  type DesktopSettingsSnapshot,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';
import { DesktopSettingsSnapshotOwner } from '../../main/settings/desktopSettingsSnapshotOwner.js';

test('settings snapshot observations are defensive and perform no backing reads', () => {
  let loads = 0;
  const initial = snapshot(1);
  const owner = new DesktopSettingsSnapshotOwner({
    loadSnapshot: async () => { loads += 1; return snapshot(2); },
    replace: async () => snapshot(2),
  }, initial);

  const first = owner.observeSnapshot();
  const second = owner.observeSnapshot();
  first.revision = 99;
  first.values.pastItemsWindow = '30';
  initial.values.pastItemsWindow = '0';

  assert.equal(loads, 0);
  assert.notEqual(first, second);
  assert.notEqual(first.values, second.values);
  assert.deepEqual(owner.observeSnapshot(), snapshot(1));
});

test('settings snapshot loads publish fresh successes and preserve the prior observation on failure', async () => {
  let next = snapshot(2, '30');
  let failure: Error | null = null;
  const owner = new DesktopSettingsSnapshotOwner({
    loadSnapshot: async () => {
      if (failure !== null) throw failure;
      return next;
    },
    replace: async () => snapshot(3),
  }, snapshot(1));

  const loaded = await owner.loadSnapshot();
  loaded.values.pastItemsWindow = '0';
  next.values.pastItemsWindow = '15';
  assert.deepEqual(owner.observeSnapshot(), snapshot(2, '30'));

  failure = new Error('read failed');
  await assert.rejects(owner.loadSnapshot(), failure);
  assert.deepEqual(owner.observeSnapshot(), snapshot(2, '30'));
});

test('settings snapshot replacements publish committed successes and preserve the prior observation on failure', async () => {
  let shouldFail = false;
  const owner = new DesktopSettingsSnapshotOwner({
    loadSnapshot: async () => snapshot(1),
    replace: async (expectedRevision, values) => {
      if (shouldFail) throw new Error('write failed');
      return { ...snapshot(expectedRevision + 1), values };
    },
  }, snapshot(1));
  const replacementValues: DesktopSettingsValues = {
    ...DEFAULT_DESKTOP_SETTINGS_VALUES,
    pastItemsWindow: '30',
  };

  const replaced = await owner.replace(1, replacementValues);
  replaced.values.pastItemsWindow = '0';
  replacementValues.pastItemsWindow = '15';
  assert.deepEqual(owner.observeSnapshot(), snapshot(2, '30'));

  shouldFail = true;
  await assert.rejects(
    owner.replace(2, { ...DEFAULT_DESKTOP_SETTINGS_VALUES, pastItemsWindow: '0' }),
    /write failed/u,
  );
  assert.deepEqual(owner.observeSnapshot(), snapshot(2, '30'));
});

function snapshot(
  revision: number,
  pastItemsWindow: DesktopSettingsSnapshot['values']['pastItemsWindow'] = '15',
): DesktopSettingsSnapshot {
  return {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision,
    status: 'ready',
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, pastItemsWindow },
  };
}
