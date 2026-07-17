import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { setImmediate } from 'node:timers/promises';

import {
  LINEUP_CHANNEL_SETUP_BUILD_CHANNEL,
  LINEUP_CHANNEL_SETUP_CANCEL_BUILD_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_RECORD_CHANNEL,
  LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL,
  LINEUP_CHANNEL_SETUP_PROGRESS_CHANNEL,
  LINEUP_CHANNEL_SETUP_REVIEW_CHANNEL,
} from '../../contracts/ipc.js';
import { registerChannelSetupIpcHandlers } from '../../main/channel/channelSetupIpc.js';
import type { DesktopChannelSetupRuntime } from '../../main/channel/setup/desktopChannelSetupRuntime.js';

class IpcFake {
  readonly handlers = new Map<string, (event: never, payload: unknown) => unknown>();
  handle(channel: string, handler: (event: never, payload: unknown) => unknown) { this.handlers.set(channel, handler); }
  removeHandler(channel: string) { this.handlers.delete(channel); }
}
class SenderFake extends EventEmitter {
  readonly sent: Array<{ channel: string; payload: unknown }> = [];
  constructor(readonly id: number) { super(); }
  send(channel: string, payload: unknown) { this.sent.push({ channel, payload }); }
  isDestroyed() { return false; }
}

const config = {
  selectedLibraryIds: ['movies'], maxChannels: 10, buildMode: 'merge', strategyConfig: {},
  actorStudioCombineMode: 'separate', minItemsPerChannel: 1,
};

test('channel setup IPC registers exact channels, validates envelopes, and sends progress only to invoking sender', async () => {
  const ipcMain = new IpcFake();
  const calls: string[] = [];
  const released: number[] = [];
  const runtime = {
    getRecord: async (requestId: string) => ({ ok: true, requestId, value: { status: 'missing' } }),
    preview: async (requestId: string) => ({ ok: true, requestId, value: { status: 'ready' } }),
    review: async (requestId: string) => ({ ok: true, requestId, value: { preview: {}, diff: {} } }),
    build: async (input: { requestId: string; buildId: string; onProgress: (value: object, sequence: number) => void }) => {
      calls.push(input.buildId);
      input.onProgress({ task: 'done', current: 1, total: 1, label: 'Done', detail: 'Done' }, 1);
      return { ok: true, requestId: input.requestId, value: { kind: 'committed', buildId: input.buildId } };
    },
    cancelBuild: (_senderId: number, buildId: string) => ({ buildId, status: 'accepted' }),
    releaseSender: (senderId: number) => released.push(senderId),
    shutdown: () => undefined,
  };
  const teardown = registerChannelSetupIpcHandlers({
    runtime: runtime as unknown as DesktopChannelSetupRuntime,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain,
  });
  assert.deepEqual([...ipcMain.handlers.keys()], [
    LINEUP_CHANNEL_SETUP_GET_RECORD_CHANNEL,
    LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL,
    LINEUP_CHANNEL_SETUP_REVIEW_CHANNEL,
    LINEUP_CHANNEL_SETUP_BUILD_CHANNEL,
    LINEUP_CHANNEL_SETUP_CANCEL_BUILD_CHANNEL,
  ]);
  const sender = new SenderFake(7);
  const event = { sender } as never;
  const buildHandler = ipcMain.handlers.get(LINEUP_CHANNEL_SETUP_BUILD_CHANNEL)!;
  const result = await buildHandler(event, { requestId: 'req-1', payload: { buildId: 'build-1', config, confirmReplace: true } });
  assert.equal((result as { ok: boolean }).ok, true);
  assert.deepEqual(calls, ['build-1']);
  assert.equal(sender.sent.length, 1);
  assert.equal(sender.sent[0]?.channel, LINEUP_CHANNEL_SETUP_PROGRESS_CHANNEL);
  assert.deepEqual(sender.sent[0]?.payload, {
    buildId: 'build-1', buildRequestId: 'req-1', sequence: 1,
    progress: { task: 'done', current: 1, total: 1, label: 'Done', detail: 'Done' },
  });
  sender.emit('destroyed');
  assert.deepEqual(released, [7]);
  await teardown();
  assert.equal(ipcMain.handlers.size, 0);
});

test('channel setup IPC rejects forbidden renderer fields and unauthorized requests', async () => {
  const ipcMain = new IpcFake();
  const teardown = registerChannelSetupIpcHandlers({
    runtime: { shutdown: () => undefined } as unknown as DesktopChannelSetupRuntime,
    isAuthorizedEvent: () => false,
    createRequestId: () => 'fallback',
    ipcMain,
  });
  const sender = new SenderFake(1);
  const unauthorized = await ipcMain.handlers.get(LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL)!({ sender } as never, {
    requestId: 'req', payload: { config },
  });
  assert.equal((unauthorized as { error: { code: string } }).error.code, 'CHANNEL_UNAUTHORIZED');
  await teardown();

  const allowedIpc = new IpcFake();
  const allowedTeardown = registerChannelSetupIpcHandlers({
    runtime: { preview: async () => { throw new Error('must not run'); }, shutdown: () => undefined } as unknown as DesktopChannelSetupRuntime,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain: allowedIpc,
  });
  const invalid = await allowedIpc.handlers.get(LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL)!({ sender } as never, {
    requestId: 'req', payload: { config: { ...config, rawPlexPayload: {} } },
  });
  assert.equal((invalid as { error: { code: string } }).error.code, 'CHANNEL_VALIDATION_FAILED');
  const invalidDrafts = [
    { ...config, extra: true },
    { ...config, strategyConfig: { genres: { enabled: true, mystery: true } } },
    { ...config, strategyConfig: { genres: { priority: 0 } } },
    { ...config, channelExpansion: { variantType: 'mystery' } },
    { ...config, channelExpansion: { variantBlockSize: 99 } },
    { ...config, seriesOrdering: { basePlaybackMode: 'random' } },
    { ...config, seriesOrdering: { baseBlockSize: 1 } },
  ];
  for (const [index, invalidConfig] of invalidDrafts.entries()) {
    const result = await allowedIpc.handlers.get(LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL)!({ sender } as never, {
      requestId: `invalid-${String(index)}`, payload: { config: invalidConfig },
    });
    assert.equal((result as { error: { code: string } }).error.code, 'CHANNEL_VALIDATION_FAILED');
  }
  await allowedTeardown();
});

test('channel setup IPC detaches destroyed sender progress custody without affecting build completion', async () => {
  const ipcMain = new IpcFake();
  let emitProgress!: () => void;
  let finish!: () => void;
  const finished = new Promise<void>((resolve) => { finish = resolve; });
  const runtime = {
    build: async (input: { requestId: string; onProgress: (value: object, sequence: number) => void }) => {
      emitProgress = () => input.onProgress({ task: 'done', current: 1, total: 1, label: 'Done', detail: 'Done' }, 1);
      await finished;
      return { ok: true, requestId: input.requestId, value: { kind: 'committed' } };
    },
    releaseSender: () => undefined,
    shutdown: () => undefined,
  };
  const teardown = registerChannelSetupIpcHandlers({
    runtime: runtime as unknown as DesktopChannelSetupRuntime,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain,
  });
  const sender = new SenderFake(11);
  const pending = ipcMain.handlers.get(LINEUP_CHANNEL_SETUP_BUILD_CHANNEL)!({ sender } as never, {
    requestId: 'request-detach', payload: { buildId: 'build-detach', config, confirmReplace: true },
  });
  await setImmediate();
  sender.emit('destroyed');
  emitProgress();
  finish();
  assert.equal(((await pending) as { ok: boolean }).ok, true);
  assert.equal(sender.sent.length, 0);
  await teardown();
});

test('channel setup IPC teardown detaches live sender progress custody before releasing runtime ownership', async () => {
  const ipcMain = new IpcFake();
  let emitProgress!: () => void;
  let finish!: () => void;
  const finished = new Promise<void>((resolve) => { finish = resolve; });
  const released: number[] = [];
  const runtime = {
    build: async (input: { requestId: string; onProgress: (value: object, sequence: number) => void }) => {
      emitProgress = () => input.onProgress({ task: 'done', current: 1, total: 1, label: 'Done', detail: 'Done' }, 1);
      await finished;
      return { ok: true, requestId: input.requestId, value: { kind: 'committed' } };
    },
    releaseSender: (senderId: number) => released.push(senderId),
    shutdown: () => undefined,
  };
  const teardown = registerChannelSetupIpcHandlers({
    runtime: runtime as unknown as DesktopChannelSetupRuntime,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain,
  });
  const sender = new SenderFake(12);
  const pending = ipcMain.handlers.get(LINEUP_CHANNEL_SETUP_BUILD_CHANNEL)!({ sender } as never, {
    requestId: 'request-teardown', payload: { buildId: 'build-teardown', config, confirmReplace: true },
  });
  await setImmediate();
  await teardown();
  emitProgress();
  finish();

  assert.equal(((await pending) as { ok: boolean }).ok, true);
  assert.deepEqual(released, [12]);
  assert.equal(sender.sent.length, 0);
});
