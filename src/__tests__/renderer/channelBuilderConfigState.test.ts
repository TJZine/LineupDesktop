import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createChannelBuilderConfigState,
  readChannelBuilderConfigRequest,
} from '../../renderer/channelSetup/builderConfigState.js';

test('minimal builder config state delegates defaults and returns ownership-safe requests', () => {
  const created = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const first = readChannelBuilderConfigRequest(created.state);
  const second = readChannelBuilderConfigRequest(created.state);
  assert.deepEqual(first, second);
  assert.notEqual(first, second);
  assert.notEqual(first.strategyConfig, second.strategyConfig);
  assert.equal(first.buildMode, 'replace');
});

test('minimal builder config state rejects incomplete context', () => {
  assert.deepEqual(
    createChannelBuilderConfigState({ serverId: '', selectedLibraryIds: [] }),
    { ok: false },
  );
});

test('minimal builder config state delegates the canonical library cap', () => {
  assert.deepEqual(
    createChannelBuilderConfigState({
      serverId: 'server',
      selectedLibraryIds: Array.from({ length: 25 }, (_, index) => `library-${index}`),
    }),
    { ok: false },
  );
});
