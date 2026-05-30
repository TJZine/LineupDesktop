import test from 'node:test';
import assert from 'node:assert/strict';

import {
  channelSetupSuccess,
  type ChannelSetupIpcResult,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createChannelRuntimeController } from '../../renderer/channelRuntimeActions.js';

test('channel runtime controller ignores direct duplicate commits while one is pending', async () => {
  const pendingCommit = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const commitCalls: unknown[] = [];
  const states: string[] = [];
  const controller = createChannelRuntimeController({
    bridge: {
      getStatus: async () => channelSetupSuccess('status', summary([])),
      commit: async (input) => {
        commitCalls.push(input);
        return pendingCommit.promise;
      },
    } as LineupDesktopPreloadApi['channelSetup'],
    onStateChanged: () => {
      states.push(controller.getState().statusText);
    },
  });

  const first = controller.commit({ mode: 'append', sectionIds: ['movies'] });
  const second = controller.commit({ mode: 'append', sectionIds: ['movies'] });
  pendingCommit.resolve(channelSetupSuccess('commit', summary([
    { id: 'channel-movies', number: 1, name: 'Movies', itemCount: 2 },
  ])));
  await Promise.all([first, second]);

  assert.equal(commitCalls.length, 1);
  assert.equal(controller.getState().pending, false);
  assert.equal(controller.getState().summary?.channelCount, 1);
  assert.deepEqual(states, ['Saving channels', 'Recovered']);
});

function summary(
  channels: ReadonlyArray<{ id: string; number: number; name: string; itemCount: number }>,
): ChannelSetupSummary {
  return {
    status: channels.length > 0 ? 'configured' : 'not-configured',
    channelCount: channels.length,
    currentChannelId: channels[0]?.id ?? null,
    currentChannelNumber: channels[0]?.number ?? null,
    currentChannelName: channels[0]?.name ?? null,
    channelNumbers: channels.map((channel) => channel.number),
    channels: channels.map((channel) => ({
      ...channel,
      sourceLibraryId: null,
      sourceLibraryName: null,
    })),
    updatedAtMs: 1,
    recovery: { loaded: channels.length > 0, repaired: false },
  };
}

function deferred<TValue>(): {
  promise: Promise<TValue>;
  resolve(value: TValue): void;
} {
  let resolveValue: (value: TValue) => void = () => undefined;
  const promise = new Promise<TValue>((resolve) => {
    resolveValue = resolve;
  });
  return {
    promise,
    resolve: resolveValue,
  };
}
