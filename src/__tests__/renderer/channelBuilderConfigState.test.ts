import test from 'node:test';
import assert from 'node:assert/strict';

import {
  applyChannelBuilderConfigAction,
  applyChannelBuilderConfigMutation,
  createChannelBuilderConfigState,
  recontextualizeChannelBuilderConfigState,
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

test('editable builder state normalizes every supported configuration family', () => {
  const created = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(created.ok, true);
  if (!created.ok) return;
  let state = created.state;
  const mutations = [
    { kind: 'set-build-mode', value: 'merge' },
    { kind: 'set-combine-mode', value: 'combined' },
    { kind: 'set-max-channels', value: 320 },
    { kind: 'set-min-items', value: 12 },
    { kind: 'toggle-strategy', strategy: 'genres' },
    { kind: 'set-strategy-priority', strategy: 'genres', value: 9 },
    { kind: 'set-strategy-scope', strategy: 'genres', value: 'cross-library' },
    { kind: 'toggle-alternates' },
    { kind: 'set-alternate-copies', value: 3 },
    { kind: 'set-variant-type', value: 'block' },
    { kind: 'set-variant-block-size', value: 5 },
    { kind: 'set-series-mode', value: 'sequential' },
    { kind: 'set-series-block-size', value: 4 },
  ] as const;
  for (const mutation of mutations) {
    const updated = applyChannelBuilderConfigMutation(state, mutation);
    assert.equal(updated.ok, true, mutation.kind);
    if (!updated.ok) return;
    state = updated.state;
  }
  const config = readChannelBuilderConfigRequest(state);
  assert.equal(config.buildMode, 'merge');
  assert.equal(config.actorStudioCombineMode, 'combined');
  assert.equal(config.maxChannels, 320);
  assert.equal(config.minItemsPerChannel, 12);
  assert.deepEqual(config.strategyConfig.genres, {
    enabled: false,
    priority: 9,
    scope: 'cross-library',
  });
  assert.deepEqual(config.channelExpansion, {
    addAlternateLineups: true,
    alternateLineupCopies: 3,
    variantType: 'block',
    variantBlockSize: 5,
  });
  assert.deepEqual(config.seriesOrdering, {
    basePlaybackMode: 'sequential',
    baseBlockSize: 4,
  });
  assert.deepEqual(Object.keys(config.strategyConfig), [
    'collections', 'playlists', 'genres', 'directors',
    'decades', 'recentlyAdded', 'studios', 'actors',
  ]);
});

test('editable builder state rejects invalid controls and safely restores into new context', () => {
  const created = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library-a'],
  });
  assert.equal(created.ok, true);
  if (!created.ok) return;
  assert.deepEqual(
    applyChannelBuilderConfigMutation(created.state, {
      kind: 'set-strategy-scope',
      strategy: 'collections',
      value: 'cross-library',
    }),
    { ok: false },
  );
  const restored = recontextualizeChannelBuilderConfigState(created.state, {
    serverId: 'server-next',
    selectedLibraryIds: ['library-b', 'library-c'],
  });
  assert.equal(restored.ok, true);
  if (!restored.ok) return;
  assert.equal(restored.state.config.serverId, 'server-next');
  assert.deepEqual(restored.state.config.selectedLibraryIds, ['library-b', 'library-c']);
  assert.equal(restored.state.config.maxChannels, created.state.config.maxChannels);
  assert.deepEqual(
    applyChannelBuilderConfigAction(created.state, 'configAlternateCopies'),
    { ok: false },
  );
  assert.deepEqual(
    applyChannelBuilderConfigAction(created.state, 'configVariantBlockSize'),
    { ok: false },
  );
  assert.deepEqual(
    applyChannelBuilderConfigAction(created.state, 'configSeriesBlockSize'),
    { ok: false },
  );
  const disabledGenre = applyChannelBuilderConfigMutation(created.state, {
    kind: 'toggle-strategy',
    strategy: 'genres',
  });
  assert.equal(disabledGenre.ok, true);
  if (!disabledGenre.ok) return;
  assert.deepEqual(
    applyChannelBuilderConfigAction(disabledGenre.state, 'strategyPriorityUp:genres'),
    { ok: false },
  );
});
