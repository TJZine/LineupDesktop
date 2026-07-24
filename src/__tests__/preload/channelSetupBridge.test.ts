import assert from 'node:assert/strict';
import test from 'node:test';

import channelSetupBridgeModule from '../../preload/channelSetupBridge.cjs';
import type { ChannelSetupBridgeListener } from '../../preload/channelSetupBridge.cjs';

const { createChannelSetupBridge } = channelSetupBridgeModule;

const channels = {
  getStatus: 'legacy-status', commit: 'legacy-commit', getRecord: 'get-record', preview: 'preview', review: 'review',
  build: 'build', cancelBuild: 'cancel', progress: 'progress',
};
const draft = {
  selectedLibraryIds: ['movies'], maxChannels: 12, buildMode: 'merge' as const,
  strategyConfig: { genres: { enabled: true, priority: 1, scope: 'per-library' as const } },
  actorStudioCombineMode: 'separate' as const, minItemsPerChannel: 1,
};
const config = {
  ...draft,
  strategyConfig: Object.fromEntries([
    'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
  ].map((key, index) => [key, { enabled: key === 'genres', priority: index + 1, scope: 'per-library' }])),
  channelExpansion: { addAlternateLineups: false, alternateLineupCopies: 1, variantType: 'none', variantBlockSize: 2 },
  seriesOrdering: { basePlaybackMode: 'shuffle', baseBlockSize: 2 },
};

test('channel setup preload exposes exact workflow invokes with preload-owned request ids', async () => {
  const calls: Array<{ channel: string; request: { requestId: string; payload: unknown } }> = [];
  let nextId = 0;
  const api = createChannelSetupBridge(async (channel, request) => {
    calls.push({ channel, request });
    if (channel === channels.getRecord) return { ok: true, requestId: request.requestId, value: { status: 'missing' } };
    if (channel === channels.preview) return { ok: true, requestId: request.requestId, value: preview() };
    if (channel === channels.review) return { ok: true, requestId: request.requestId, value: {
      preview: preview(), diff: { summary: { created: 1, removed: 0, unchanged: 0 }, samples: { created: ['Drama'], removed: [], unchanged: [] } },
    } };
    if (channel === channels.cancelBuild) return { ok: true, requestId: request.requestId, value: { buildId: 'build-one', status: 'not-active' } };
    throw new Error('unexpected invoke');
  }, noEvents(), channels, (prefix) => `${prefix}-${String(++nextId)}`);

  assert.equal((await api.getRecord()).ok, true);
  assert.equal((await api.preview(draft)).ok, true);
  assert.equal((await api.review(draft)).ok, true);
  assert.equal((await api.cancelBuild({ buildId: 'build-one' })).ok, true);
  assert.deepEqual(calls.map((call) => call.channel), ['get-record', 'preview', 'review', 'cancel']);
  assert.equal(new Set(calls.map((call) => call.request.requestId)).size, 4);
  assert.deepEqual((calls[1]?.request.payload as { config: unknown }).config, draft);
  assert.notEqual((calls[1]?.request.payload as { config: unknown }).config, draft);
});

test('channel setup build owns listener before invoke, filters both ids and sequence, and removes it in finally', async () => {
  const order: string[] = [];
  let listener: ChannelSetupBridgeListener | null = null;
  let release!: (value: unknown) => void;
  const terminal = new Promise<unknown>((resolve) => { release = resolve; });
  const api = createChannelSetupBridge(async (_channel, request) => {
    order.push('invoke');
    assert.equal(request.requestId, 'channel-setup-build-request');
    return terminal;
  }, {
    on: (_channel, candidate) => { order.push('on'); listener = candidate; },
    removeListener: (_channel, candidate) => { order.push('remove'); assert.equal(candidate, listener); listener = null; },
  }, channels, () => 'channel-setup-build-request');
  const progress: string[] = [];
  const pending = api.build({ buildId: 'build-one', config: draft, confirmReplace: true }, (value) => {
    progress.push(value.task);
    if (progress.length === 1) throw new Error('renderer callback detached');
  });
  assert.deepEqual(order, ['on', 'invoke']);
  assert.notEqual(listener, null);
  const emit = (value: unknown) => (listener as unknown as ChannelSetupBridgeListener)({}, value);
  emit(envelope('wrong-build', 'channel-setup-build-request', 1));
  emit(envelope('build-one', 'wrong-request', 1));
  emit(envelope('build-one', 'channel-setup-build-request', 1, { rawPayload: true }));
  emit(envelope('build-one', 'channel-setup-build-request', 1));
  emit(envelope('build-one', 'channel-setup-build-request', 1));
  emit(envelope('build-one', 'channel-setup-build-request', 2));
  assert.deepEqual(progress, ['fetch_playlists', 'fetch_playlists']);
  release({ ok: true, requestId: 'channel-setup-build-request', value: {
    kind: 'committed', buildId: 'build-one', counts: counts(), warnings: [], guideRefresh: { kind: 'completed' },
  } });
  assert.equal((await pending).ok, true);
  assert.deepEqual(order, ['on', 'invoke', 'remove']);
  assert.equal(listener, null);
});

test('channel setup preload rejects malformed inputs, stale results, and malformed reused-id failures', async () => {
  let invokes = 0;
  let listeners = 0;
  const api = createChannelSetupBridge(async (_channel, request) => {
    invokes += 1;
    return { ok: false, requestId: `${request.requestId}-stale`, error: {
      code: 'CHANNEL_BUILD_ID_REUSED', message: 'Build identifier was already used.', retryable: false,
      recoverable: true, operation: 'preview', rawPlexPayload: {},
    } };
  }, {
    on: () => { listeners += 1; }, removeListener: () => { listeners -= 1; },
  }, channels, (prefix) => `${prefix}-request`);

  for (const result of [
    await api.preview({ ...draft, selectedLibraryIds: ['movies', 'movies'] }),
    await api.review({ ...draft, strategyConfig: { genres: { enabled: true, mystery: true } } } as never),
    await api.build({ buildId: 'bad id', config: draft, confirmReplace: true }, () => undefined),
    await api.build({ buildId: 'build-one', config: draft, confirmReplace: true }, undefined as never),
    await api.cancelBuild({ buildId: 'bad id' }),
  ]) assert.equal(result.ok, false);
  assert.equal(invokes, 0);
  assert.equal(listeners, 0);

  const stale = await api.preview(draft);
  assert.equal(stale.ok, false);
  assert.equal(stale.ok ? '' : stale.error.code, 'CHANNEL_VALIDATION_FAILED');
  assert.equal(invokes, 1);
});

test('channel setup preload deeply validates terminal shapes and preserves exact reused-id failures', async () => {
  let response: (requestId: string) => unknown = () => undefined;
  const api = createChannelSetupBridge(async (_channel, request) => response(request.requestId), noEvents(), channels,
    (prefix) => `${prefix}-request`);

  response = (requestId) => ({ ok: false, requestId, error: {
    code: 'CHANNEL_BUILD_ID_REUSED', message: 'Build identifier was already used.', retryable: false,
    recoverable: true, operation: 'build',
  } });
  const reused = await api.build({ buildId: 'build-one', config: draft, confirmReplace: true }, () => undefined);
  assert.equal(reused.ok, false);
  assert.equal(reused.ok ? '' : reused.error.code, 'CHANNEL_BUILD_ID_REUSED');

  response = (requestId) => ({ ok: true, requestId, value: {
    kind: 'committed', buildId: 'wrong-build', counts: counts(), warnings: [], guideRefresh: { kind: 'completed' },
  } });
  const wrongBuild = await api.build({ buildId: 'build-one', config: draft, confirmReplace: true }, () => undefined);
  assert.equal(wrongBuild.ok ? '' : wrongBuild.error.code, 'CHANNEL_VALIDATION_FAILED');

  response = (requestId) => ({ ok: true, requestId, value: { buildId: 'wrong-build', status: 'accepted' } });
  const wrongCancel = await api.cancelBuild({ buildId: 'build-one' });
  assert.equal(wrongCancel.ok ? '' : wrongCancel.error.code, 'CHANNEL_VALIDATION_FAILED');

  response = (requestId) => ({ ok: true, requestId, value: {
    ...preview(), config: { ...config, strategyConfig: { ...config.strategyConfig, genres: { enabled: true, priority: 4, scope: 'per-library', rawPayload: {} } } },
  } });
  const nestedExtra = await api.preview(draft);
  assert.equal(nestedExtra.ok ? '' : nestedExtra.error.code, 'CHANNEL_VALIDATION_FAILED');

  response = (requestId) => ({ ok: true, requestId, value: {
    preview: preview(),
    diff: { summary: { created: 1, removed: 0, unchanged: 0, extra: 1 }, samples: { created: [], removed: [], unchanged: [] } },
  } });
  const reviewExtra = await api.review(draft);
  assert.equal(reviewExtra.ok ? '' : reviewExtra.error.code, 'CHANNEL_VALIDATION_FAILED');
});

function noEvents() {
  return { on: () => undefined, removeListener: () => undefined };
}
function preview() {
  return {
    status: 'ready', config, estimates: { total: 1, playlists: 0, collections: 0, recentlyAdded: 0, genres: 1, studios: 0, actors: 0, decades: 0, directors: 0 },
    eligibleGeneratedCount: 1, selectedGeneratedCount: 1, droppedByMinItemsCount: 0, droppedByPlanCapCount: 0,
    reachedMaxChannels: false, warnings: [],
  };
}
function counts() {
  return {
    plannedGeneratedCount: 1, createdCount: 1, updatedCount: 0, preservedCount: 0, removedCount: 0,
    skippedCount: 0, reachedMaxChannels: false, channelNumberCapacityExhausted: false, errorCount: 0,
  };
}
function envelope(buildId: string, buildRequestId: string, sequence: number, progressExtra: object = {}) {
  return {
    buildId, buildRequestId, sequence,
    progress: { task: 'fetch_playlists', current: sequence, total: 2, label: 'Loading playlists', detail: 'Loading playlists', ...progressExtra },
  };
}
