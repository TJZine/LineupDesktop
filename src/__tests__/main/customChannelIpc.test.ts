import test from 'node:test';
import assert from 'node:assert/strict';

import {
  LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL,
} from '../../contracts/ipc.js';
import { customChannelSuccess, type CustomChannelDraftInput } from '../../contracts/customChannels.js';
import { registerCustomChannelIpcHandlers } from '../../main/channel/customChannelIpc.js';

test('custom channel IPC authorizes and validates snapshot requests', async () => {
  const handled = new Map<string, (event: unknown, payload: unknown) => unknown>();
  const removed: string[] = [];
  let snapshotCalls = 0;
  const teardown = registerCustomChannelIpcHandlers({
    runtime: {
      getSnapshot: async (requestId: string) => {
        snapshotCalls++;
        return customChannelSuccess(requestId, safeSnapshot());
      },
    } as never,
    mediaPicker: {} as never,
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'custom-fallback',
    ipcMain: {
      handle: (channelName, handler) => {
        handled.set(channelName, handler as (event: unknown, payload: unknown) => unknown);
      },
      removeHandler: (channelName) => {
        removed.push(channelName);
      },
    },
  });

  const handler = handled.get(LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL);
  assert.ok(handler);

  const success = await handler('authorized', { requestId: 'custom-snapshot-1', payload: {} });
  assert.equal((success as { ok: boolean }).ok, true);
  assert.equal(snapshotCalls, 1);

  const unauthorized = await handler('other', { requestId: 'custom-snapshot-2', payload: {} });
  assert.equal((unauthorized as { ok: boolean }).ok, false);
  assert.equal((unauthorized as { error: { code: string } }).error.code, 'CUSTOM_CHANNEL_UNAUTHORIZED');
  assert.equal(snapshotCalls, 1);

  const invalid = await handler('authorized', {
    requestId: 'custom-snapshot-3',
    payload: { token: 'secret' },
  });
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal((invalid as { error: { code: string } }).error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(snapshotCalls, 1);

  await teardown();
  assert.deepEqual(removed.sort(), [
    LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL,
    LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL,
  ].sort());
});

test('custom channel IPC validates media requests before invoking picker', async () => {
  const handled = new Map<string, (event: unknown, payload: unknown) => unknown>();
  let pickerCalls = 0;
  registerCustomChannelIpcHandlers({
    runtime: {} as never,
    mediaPicker: {
      listMedia: async (_requestId: string) => {
        pickerCalls++;
        return {
          ok: true,
          value: {
            items: [],
            offset: 0,
            limit: 24,
            total: null,
            hasMore: false,
          },
        };
      },
    } as never,
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'custom-fallback',
    ipcMain: {
      handle: (channelName, handler) => {
        handled.set(channelName, handler as (event: unknown, payload: unknown) => unknown);
      },
      removeHandler: () => undefined,
    },
  });
  const handler = handled.get(LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL);
  assert.ok(handler);

  const success = await handler('authorized', {
    requestId: 'custom-media-1',
    payload: { sourceType: 'search', query: 'movie', limit: 24 },
  });
  assert.equal((success as { ok: boolean }).ok, true);
  assert.equal(pickerCalls, 1);

  const invalid = await handler('authorized', {
    requestId: 'custom-media-2',
    payload: { sourceType: 'search', query: 'http://private', limit: 24 },
  });
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal((invalid as { error: { code: string } }).error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(pickerCalls, 1);
});

test('custom channel IPC rejects malformed drafts before runtime save', async () => {
  const handled = new Map<string, (event: unknown, payload: unknown) => unknown>();
  let saveCalls = 0;
  registerCustomChannelIpcHandlers({
    runtime: {
      saveDraft: async (requestId: string) => {
        saveCalls++;
        return customChannelSuccess(requestId, {
          snapshot: safeSnapshot(),
          changedChannelId: 'channel-1',
          currentChannelId: 'channel-1',
        });
      },
    } as never,
    mediaPicker: {} as never,
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'custom-fallback',
    ipcMain: {
      handle: (channelName, handler) => {
        handled.set(channelName, handler as (event: unknown, payload: unknown) => unknown);
      },
      removeHandler: () => undefined,
    },
  });
  const handler = handled.get(LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL);
  assert.ok(handler);

  const success = await handler('authorized', {
    requestId: 'custom-save-1',
    payload: safeDraft(),
  });
  assert.equal((success as { ok: boolean }).ok, true);
  assert.equal(saveCalls, 1);

  const invalid = await handler('authorized', {
    requestId: 'custom-save-2',
    payload: { ...safeDraft(), hidden: 'false' },
  });
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal((invalid as { error: { code: string } }).error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(saveCalls, 1);
});

test('custom channel IPC validates delete confirmation before runtime mutation', async () => {
  const handled = new Map<string, (event: unknown, payload: unknown) => unknown>();
  let deleteCalls = 0;
  registerCustomChannelIpcHandlers({
    runtime: {
      deleteChannel: async (requestId: string) => {
        deleteCalls++;
        return customChannelSuccess(requestId, {
          snapshot: safeSnapshot(),
          changedChannelId: 'channel-1',
          currentChannelId: null,
        });
      },
    } as never,
    mediaPicker: {} as never,
    isAuthorizedEvent: (event) => (event as unknown) === 'authorized',
    createRequestId: () => 'custom-fallback',
    ipcMain: {
      handle: (channelName, handler) => {
        handled.set(channelName, handler as (event: unknown, payload: unknown) => unknown);
      },
      removeHandler: () => undefined,
    },
  });
  const handler = handled.get(LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL);
  assert.ok(handler);

  const invalid = await handler('authorized', {
    requestId: 'custom-delete-1',
    payload: { channelId: 'channel-1', confirm: 'yes' },
  });
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal(deleteCalls, 0);

  const success = await handler('authorized', {
    requestId: 'custom-delete-2',
    payload: { channelId: 'channel-1', confirm: true },
  });
  assert.equal((success as { ok: boolean }).ok, true);
  assert.equal(deleteCalls, 1);
});

function safeSnapshot() {
  return {
    channels: [],
    currentChannelId: null,
    visibleChannelCount: 0,
    hiddenChannelCount: 0,
    maxChannels: 500,
    nextAvailableNumber: 1,
    updatedAtMs: 123,
    storage: { status: 'ready' as const, repaired: false },
  };
}

function safeDraft(): CustomChannelDraftInput {
  return {
    number: 101,
    name: 'Custom One',
    hidden: false,
    content: [{
      type: 'manualItem',
      ratingKey: 'rating-1',
      title: 'Movie One',
      durationMs: 3_600_000,
      mediaType: 'movie',
    }],
    playbackMode: 'sequential',
  };
}
