import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CHANNEL_SETUP_COMMIT_MODES,
  CHANNEL_SETUP_ERROR_CODES,
  CHANNEL_SETUP_OPERATIONS,
  CHANNEL_SETUP_PROGRESS_TASKS,
  CHANNEL_SETUP_STRATEGY_KEYS,
  type ChannelSetupConfig,
  type ChannelSetupRecordSummary,
} from '../../contracts/channel.js';

test('channel setup contracts freeze renderer-safe builder vocabulary', () => {
  assert.deepEqual(CHANNEL_SETUP_STRATEGY_KEYS, [
    'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
  ]);
  assert.deepEqual(CHANNEL_SETUP_COMMIT_MODES, ['append', 'replace', 'merge']);
  assert.deepEqual(CHANNEL_SETUP_PROGRESS_TASKS, [
    'fetch_playlists', 'fetch_collections', 'fetch_facets', 'scan_library_items', 'build_pending',
    'create_channels', 'apply_channels', 'refresh_guide', 'done',
  ]);
  assert.deepEqual(CHANNEL_SETUP_OPERATIONS, [
    'getStatus', 'getRecord', 'preview', 'review', 'build', 'cancelBuild', 'commit',
  ]);
  assert.ok(CHANNEL_SETUP_ERROR_CODES.includes('CHANNEL_BUILD_ACTIVE'));
  assert.ok(CHANNEL_SETUP_ERROR_CODES.includes('CHANNEL_BUILD_TOO_LATE'));
});

test('normalized setup config and record summaries contain no main-owned context identifiers', () => {
  const configKeys = new Set<keyof ChannelSetupConfig>([
    'selectedLibraryIds', 'maxChannels', 'buildMode', 'strategyConfig', 'channelExpansion',
    'seriesOrdering', 'actorStudioCombineMode', 'minItemsPerChannel',
  ]);
  assert.equal(configKeys.has('serverId' as keyof ChannelSetupConfig), false);
  assert.equal(configKeys.has('profileId' as keyof ChannelSetupConfig), false);

  const ready: ChannelSetupRecordSummary = {
    status: 'ready',
    config: {} as ChannelSetupConfig,
    createdAtMs: 1,
    updatedAtMs: 2,
  };
  assert.deepEqual(Object.keys(ready).sort(), ['config', 'createdAtMs', 'status', 'updatedAtMs']);
});
