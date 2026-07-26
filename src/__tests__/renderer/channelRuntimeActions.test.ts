import assert from 'node:assert/strict';
import test from 'node:test';

import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createChannelRuntimeController } from '../../renderer/channelRuntimeActions.js';
import { projectChannelBuildCancellation } from '../../renderer/channelRuntimeState.js';
import {
  createChannelBuilderConfigState,
  readChannelBuilderConfigRequest,
} from '../../renderer/channelSetup/builderConfigState.js';

test('channel build cancel remains reachable across pending IPC handoffs', () => {
  assert.deepEqual(
    projectChannelBuildCancellation({
      summary: null,
      operation: null,
      statusText: 'Starting channel review',
      errorText: null,
      pending: true,
    }),
    { visible: true, enabled: true, label: 'Cancel build' },
  );
  const reviewReadyState = {
    summary: null,
    operation: {
      operationId: `channel-builder-review-${'0'.repeat(32)}`,
      kind: 'review',
      state: 'review-ready',
      phase: 'review-ready',
      startedAtMs: 1,
      updatedAtMs: 2,
      progress: { completed: 1, total: 1 },
      result: {
        kind: 'review',
        planId: `channel-builder-plan-${'1'.repeat(32)}`,
        contextEpoch: 0,
        lineupRevision: 0,
        status: 'ready',
        diff: {
          summary: { created: 1, removed: 0, unchanged: 0 },
          samples: { created: ['Channel'], removed: [], unchanged: [] },
        },
        warnings: [],
        reachedCap: false,
      },
      error: null,
    },
    statusText: 'Preparing channel build',
    errorText: null,
    pending: true,
  } as const;
  assert.deepEqual(
    projectChannelBuildCancellation(reviewReadyState),
    { visible: true, enabled: true, label: 'Cancel build' },
  );
  assert.deepEqual(
    projectChannelBuildCancellation({
      ...reviewReadyState,
      statusText: 'Canceling…',
    }),
    { visible: true, enabled: false, label: 'Canceling…' },
  );
});

test('channel runtime controller keeps review and apply as explicit real operations', async () => {
  const calls: string[] = [];
  const configResult = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(configResult.ok, true);
  if (!configResult.ok) return;
  const bridge = {
    getStatus: async () => {
      calls.push('getStatus');
      return channelSetupSuccess('status', summary());
    },
    startReview: async () => {
      calls.push('startReview');
      return channelSetupSuccess('review', {
        accepted: true,
        operation: {
          operationId: `review-${'a'.repeat(32)}`,
          kind: 'review',
          state: 'review-ready',
          phase: 'done',
          progress: { completed: 1, total: 1 },
          createdAtMs: 1,
          updatedAtMs: 2,
          result: {
            kind: 'review',
            planId: `plan-${'b'.repeat(32)}`,
            contextEpoch: 0,
            lineupRevision: 0,
            status: 'ready',
            diff: { add: 1, update: 0, delete: 0, retain: 0, finalChannelCount: 1 },
            warnings: [],
            reachedCap: false,
          },
          error: null,
        },
      } as never);
    },
    startApply: async () => {
      calls.push('startApply');
      return channelSetupSuccess('apply', {
        accepted: true,
        operation: {
          operationId: `apply-${'c'.repeat(32)}`,
          kind: 'apply',
          state: 'succeeded',
          phase: 'done',
          progress: { completed: 1, total: 1 },
          createdAtMs: 3,
          updatedAtMs: 4,
          result: {
            kind: 'apply',
            commit: 'committed',
            summary: {},
            guideRefresh: 'completed',
          },
          error: null,
        },
      } as never);
    },
    getOperation: async () => assert.fail('terminal operations must not poll'),
    cancel: async () => assert.fail('unexpected cancel'),
  } as unknown as LineupDesktopPreloadApi['channelSetup'];
  const controller = createChannelRuntimeController({
    bridge,
    onStateChanged: () => undefined,
  });

  assert.equal(await controller.startReview(readChannelBuilderConfigRequest(configResult.state)), 'succeeded');
  assert.equal(controller.getState().operation?.state, 'review-ready');
  assert.equal(await controller.applyReviewed(true), 'succeeded');
  assert.deepEqual(calls, ['startReview', 'startApply', 'getStatus']);
  assert.equal(controller.getState().summary?.lineupRevision, 1);
  assert.equal(await controller.cancelActive(), 'skipped');
});

test('channel runtime retains authoritative apply success when status refresh fails', async () => {
  const config = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(config.ok, true);
  if (!config.ok) return;
  const bridge = {
    startReview: async () => channelSetupSuccess('review', {
      accepted: true,
      operation: {
        operationId: `review-${'1'.repeat(32)}`,
        kind: 'review',
        state: 'review-ready',
        phase: 'review-ready',
        progress: { completed: 1, total: 1 },
        startedAtMs: 1,
        updatedAtMs: 2,
        result: {
          kind: 'review',
          planId: `plan-${'2'.repeat(32)}`,
          contextEpoch: 0,
          lineupRevision: 0,
          status: 'ready',
          diff: {
            summary: { created: 1, removed: 0, unchanged: 0 },
            samples: { created: ['Channel'], removed: [], unchanged: [] },
          },
          warnings: [],
          reachedCap: false,
        },
        error: null,
      },
    } as never),
    startApply: async () => channelSetupSuccess('apply', {
      accepted: true,
      operation: {
        operationId: `apply-${'3'.repeat(32)}`,
        kind: 'apply',
        state: 'succeeded',
        phase: 'done',
        progress: { completed: 1, total: 1 },
        startedAtMs: 3,
        updatedAtMs: 4,
        result: {
          kind: 'apply',
          commit: 'committed',
          summary: {
            created: 1,
            removed: 0,
            unchanged: 0,
            skipped: 0,
            finalChannelCount: 1,
            reachedMaxChannels: false,
            watchChannelId: 'summary-watch',
            byStrategy: {},
            warnings: [],
          },
          guideRefresh: 'completed',
        },
        error: null,
      },
    } as never),
    getStatus: async () => channelSetupFailure('status', {
      code: 'CHANNEL_STORAGE_UNAVAILABLE',
      message: 'Persisted channel storage is unavailable.',
      retryable: true,
      recoverable: true,
      operation: 'getStatus',
    }),
    getOperation: async () => assert.fail('terminal operations must not poll'),
    cancel: async () => assert.fail('unexpected cancel'),
  } as unknown as LineupDesktopPreloadApi['channelSetup'];
  const controller = createChannelRuntimeController({
    bridge,
    onStateChanged: () => undefined,
  });

  assert.equal(
    await controller.startReview(readChannelBuilderConfigRequest(config.state)),
    'succeeded',
  );
  assert.equal(await controller.applyReviewed(false), 'succeeded');
  assert.equal(controller.getState().operation?.state, 'succeeded');
  assert.equal(
    controller.getState().errorText,
    'Persisted channel storage is unavailable.',
  );
});

test('channel runtime cancellation publishes accepted canceling state and skips commit-started phases', async () => {
  const cancelCalls: string[] = [];
  let releasePoll!: () => void;
  const pollGate = new Promise<void>((resolve) => {
    releasePoll = resolve;
  });
  const operationId = `channel-builder-review-${'d'.repeat(32)}`;
  const bridge = {
    startReview: async () => channelSetupSuccess('review', {
      accepted: true,
      operation: {
        operationId,
        kind: 'review',
        state: 'running',
        phase: 'discover-facets',
        startedAtMs: 1,
        updatedAtMs: 2,
        progress: { completed: 0, total: null },
        result: null,
        error: null,
      },
    }),
    getOperation: async () => {
      await pollGate;
      return channelSetupSuccess('operation', {
        operation: {
          operationId,
          kind: 'review',
          state: 'canceled',
          phase: 'done',
          startedAtMs: 1,
          updatedAtMs: 4,
          progress: { completed: 1, total: 1 },
          result: { kind: 'canceled' },
          error: null,
        },
      });
    },
    cancel: async ({ operationId: requestedId }: { operationId: string }) => {
      cancelCalls.push(requestedId);
      return channelSetupSuccess('cancel', {
        accepted: true,
        reason: null,
        operation: {
          operationId,
          kind: 'review',
          state: 'canceling',
          phase: 'discover-facets',
          startedAtMs: 1,
          updatedAtMs: 3,
          progress: { completed: 0, total: null },
          result: null,
          error: null,
        },
      });
    },
    getStatus: async () => channelSetupSuccess('status', summary()),
    startApply: async () => assert.fail('canceled review must not apply'),
  } as unknown as LineupDesktopPreloadApi['channelSetup'];
  const controller = createChannelRuntimeController({
    bridge,
    onStateChanged: () => undefined,
  });
  const configResult = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(configResult.ok, true);
  if (!configResult.ok) return;
  const pending = controller.startReview(readChannelBuilderConfigRequest(configResult.state));
  await waitFor(() => controller.getState().operation?.state === 'running');
  assert.equal(await controller.cancelActive(), 'accepted');
  assert.equal(controller.getState().operation?.state, 'canceling');
  assert.equal(controller.getState().statusText, 'Canceling…');
  assert.deepEqual(cancelCalls, [operationId]);
  releasePoll();
  assert.equal(await pending, 'canceled');
  assert.equal(controller.getState().operation?.state, 'canceled');
});

test('channel runtime carries a cancel request across the explicit apply IPC handoff', async () => {
  const reviewOperationId = `channel-builder-review-${'e'.repeat(32)}`;
  const applyOperationId = `channel-builder-apply-${'f'.repeat(32)}`;
  const planId = `channel-builder-plan-${'a'.repeat(32)}`;
  let releaseApply!: () => void;
  const applyGate = new Promise<void>((resolve) => {
    releaseApply = resolve;
  });
  let applyRequested = false;
  const canceledOperationIds: string[] = [];
  const bridge = {
    startReview: async () => channelSetupSuccess('review', {
      accepted: true,
      operation: {
        operationId: reviewOperationId,
        kind: 'review',
        state: 'review-ready',
        phase: 'review-ready',
        startedAtMs: 1,
        updatedAtMs: 2,
        progress: { completed: 1, total: 1 },
        result: {
          kind: 'review',
          planId,
          contextEpoch: 0,
          lineupRevision: 0,
          status: 'ready',
          diff: {
            summary: { created: 1, removed: 0, unchanged: 0 },
            samples: { created: ['Channel'], removed: [], unchanged: [] },
          },
          warnings: [],
          reachedCap: false,
        },
        error: null,
      },
    }),
    startApply: async () => {
      applyRequested = true;
      await applyGate;
      return channelSetupSuccess('apply', {
        accepted: true,
        operation: {
          operationId: applyOperationId,
          kind: 'apply',
          state: 'running',
          phase: 'materialize',
          startedAtMs: 3,
          updatedAtMs: 4,
          progress: { completed: 0, total: 1 },
          result: null,
          error: null,
        },
      });
    },
    cancel: async ({ operationId }: { operationId: string }) => {
      canceledOperationIds.push(operationId);
      return channelSetupSuccess('cancel', {
        accepted: true,
        reason: null,
        operation: {
          operationId: applyOperationId,
          kind: 'apply',
          state: 'canceling',
          phase: 'materialize',
          startedAtMs: 3,
          updatedAtMs: 5,
          progress: { completed: 0, total: 1 },
          result: null,
          error: null,
        },
      });
    },
    getOperation: async () => channelSetupSuccess('operation', {
      operation: {
        operationId: applyOperationId,
        kind: 'apply',
        state: 'canceled',
        phase: 'done',
        startedAtMs: 3,
        updatedAtMs: 6,
        progress: { completed: 1, total: 1 },
        result: { kind: 'canceled' },
        error: null,
      },
    }),
    getStatus: async () => channelSetupSuccess('status', summary()),
  } as unknown as LineupDesktopPreloadApi['channelSetup'];
  const controller = createChannelRuntimeController({
    bridge,
    onStateChanged: () => undefined,
  });
  const configResult = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(configResult.ok, true);
  if (!configResult.ok) return;

  assert.equal(
    await controller.startReview(readChannelBuilderConfigRequest(configResult.state)),
    'succeeded',
  );
  const pending = controller.applyReviewed(false);
  await waitFor(() => applyRequested);
  assert.equal(controller.getState().operation?.state, 'review-ready');
  assert.equal(await controller.cancelActive(), 'accepted');
  releaseApply();

  assert.equal(await pending, 'canceled');
  assert.deepEqual(canceledOperationIds, [applyOperationId]);
});

test('channel runtime shutdown is idempotent and cancels only pre-persist work', async () => {
  const canceled: string[] = [];
  const operationId = `channel-builder-review-${'9'.repeat(32)}`;
  const bridge = {
    startReview: async () => channelSetupSuccess('review', {
      accepted: true,
      operation: {
        operationId,
        kind: 'review',
        state: 'running',
        phase: 'plan',
        startedAtMs: 1,
        updatedAtMs: 2,
        progress: { completed: 0, total: 1 },
        result: null,
        error: null,
      },
    }),
    getOperation: async () => new Promise(() => undefined),
    cancel: async ({ operationId: requestedId }: { operationId: string }) => {
      canceled.push(requestedId);
      return channelSetupSuccess('cancel', {
        accepted: true,
        reason: null,
        operation: {
          operationId,
          kind: 'review',
          state: 'canceling',
          phase: 'plan',
          startedAtMs: 1,
          updatedAtMs: 3,
          progress: { completed: 0, total: 1 },
          result: null,
          error: null,
        },
      });
    },
  } as unknown as LineupDesktopPreloadApi['channelSetup'];
  const controller = createChannelRuntimeController({
    bridge,
    onStateChanged: () => undefined,
  });
  const config = createChannelBuilderConfigState({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  assert.equal(config.ok, true);
  if (!config.ok) return;
  void controller.startReview(readChannelBuilderConfigRequest(config.state));
  await waitFor(() => controller.getState().operation?.state === 'running');
  await Promise.all([controller.shutdown(), controller.shutdown()]);
  assert.deepEqual(canceled, [operationId]);
});

function summary(): ChannelSetupSummary {
  return {
    status: 'not-configured',
    lineupRevision: 1,
    channelCount: 1,
    currentChannelId: 'channel',
    currentChannelNumber: 1,
    currentChannelName: 'Channel',
    channelNumbers: [1],
    channels: [{
      id: 'channel',
      number: 1,
      name: 'Channel',
      sourceLibraryId: null,
      sourceLibraryName: null,
      itemCount: 1,
    }],
    builder: { completion: 'unknown', normalizedConfig: null, completedAtMs: null },
    updatedAtMs: 1,
    recovery: { loaded: true, repaired: false },
  };
}

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return;
    await new Promise<void>((resolve) => globalThis.setTimeout(resolve, 1));
  }
  assert.fail('condition was not reached');
}
