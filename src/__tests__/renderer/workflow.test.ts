import assert from 'node:assert/strict';
import test from 'node:test';

import type { ChannelSetupSummary } from '../../contracts/channel.js';
import {
  createChannelRuntimeRendererState,
  type ChannelRuntimeRendererState,
} from '../../renderer/channelRuntimeState.js';
import {
  applyWorkflowAction,
  createWorkflowState,
  getRouteWorkflowView,
} from '../../renderer/workflow.js';
import {
  createStagedSetupController,
  dispatchStagedSetupAction,
  handleStagedSetupBack,
} from '../../renderer/setup/stagedSetupController.js';

test('workflow starts on player and routes to Guide through renderer-local state', () => {
  const initial = createWorkflowState();
  assert.equal(getRouteWorkflowView(initial).route, 'player');
  const guide = applyWorkflowAction(initial, 'openGuide');
  assert.equal(getRouteWorkflowView(guide).route, 'guide');
  assert.equal(guide.routeState.previousRoute, 'player');
});

test('workflow projects persisted setup status without legacy commit availability', () => {
  const runtime: ChannelRuntimeRendererState = {
    ...createChannelRuntimeRendererState(),
    statusText: 'Recovered',
    summary: configuredSummary(),
  };
  const view = getRouteWorkflowView(createWorkflowState('settings'), runtime);
  assert.equal(view.settings.channelCount, 1);
  assert.equal(view.settings.libraryName, 'Channel One');
  assert.equal(Object.hasOwn(view, 'channelSetupCommitAvailability'), false);
});

test('five-operation progress model covers cancelable review and noncancelable persistence', () => {
  const reviewRuntime: ChannelRuntimeRendererState = {
    ...createChannelRuntimeRendererState(),
    pending: true,
    statusText: 'Reviewing channels',
    operation: {
      operationId: `review-${'a'.repeat(32)}`,
      kind: 'review',
      state: 'running',
      phase: 'plan',
      progress: { completed: 0, total: 1 },
      startedAtMs: 1,
      updatedAtMs: 2,
      result: null,
      error: null,
    },
  };
  const review = getRouteWorkflowView(createWorkflowState('channelSetup'), reviewRuntime);
  assert.deepEqual(review.channelSetupProgress, {
    kind: 'review',
    state: 'running',
    phase: 'plan',
    progress: { completed: 0, total: 1 },
    pending: true,
    statusText: 'Reviewing channels',
    canCancel: true,
  });
  const apply = getRouteWorkflowView(createWorkflowState('channelSetup'), {
    ...reviewRuntime,
    statusText: 'Saving channels—cancel is no longer available.',
    operation: {
      operationId: `apply-${'b'.repeat(32)}`,
      kind: 'apply',
      state: 'running',
      phase: 'persist',
      progress: { completed: 1, total: 1 },
      startedAtMs: 3,
      updatedAtMs: 4,
      result: null,
      error: null,
    },
  });
  assert.equal(apply.channelSetupProgress.canCancel, false);
  assert.equal(apply.channelSetupProgress.phase, 'persist');
  for (const state of ['canceled', 'failed', 'succeeded'] as const) {
    const terminal = getRouteWorkflowView(createWorkflowState('channelSetup'), {
      ...reviewRuntime,
      pending: false,
      operation: {
        operationId: state === 'succeeded'
          ? `channel-builder-apply-${'c'.repeat(32)}`
          : `channel-builder-review-${'c'.repeat(32)}`,
        kind: state === 'succeeded' ? 'apply' : 'review',
        state,
        phase: 'done',
        progress: { completed: 1, total: 1 },
        startedAtMs: 5,
        updatedAtMs: 6,
        result: state === 'canceled'
          ? { kind: 'canceled' }
          : state === 'succeeded'
            ? {
                kind: 'apply',
                commit: 'committed',
                summary: {} as never,
                guideRefresh: 'completed',
              }
            : null,
        error: state === 'failed'
          ? {
              code: 'CHANNEL_UNKNOWN',
              message: 'Channel setup could not complete the request.',
              retryable: true,
              recoverable: true,
              operation: 'startReview',
            }
          : null,
      } as never,
    });
    assert.equal(terminal.channelSetupProgress.state, state);
    assert.equal(terminal.channelSetupProgress.canCancel, false);
    assert.deepEqual(terminal.channelSetupProgress.progress, {
      completed: 1,
      total: 1,
    });
  }
});

test('idle progress exposes no removed commit availability state', () => {
  const view = getRouteWorkflowView(createWorkflowState('channelSetup'));
  assert.equal(view.channelSetupProgress.kind, 'idle');
  assert.equal(view.channelSetupProgress.canCancel, false);
  assert.equal(Object.hasOwn(view, 'channelSetupCommitAvailability'), false);
});

test('staged setup submits the visible build mode and only confirms an actual replacement', async () => {
  const submissions: Array<{ buildMode: string; confirmReplace: boolean }> = [];
  const channelController = {
    getState: () => ({
      ...createChannelRuntimeRendererState(),
      summary: null,
    }),
    startReview: async () => 'succeeded',
    applyReviewed: async (confirmReplace: boolean) => {
      submissions.push({
        buildMode: controller.getState().buildMode,
        confirmReplace,
      });
      return 'succeeded';
    },
  };
  const sections = [{ id: 'library', type: 'movie' }];
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  controller.toggleLibrary('library', sections as never);
  assert.equal(controller.prepareBuilderConfig({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  }, {
    completion: 'unknown',
    normalizedConfig: null,
    completedAtMs: null,
  }), true);
  await dispatchStagedSetupAction({
    action: 'configModeMerge',
    controller,
    channelController,
  } as never);
  assert.equal(controller.getState().builderConfig?.config.buildMode, 'merge');
  assert.equal(controller.getState().focusIntent, 'channel-strategy-build-merge');
  controller.showOwner('build', 'setup-confirm');
  const dispatch = async (
    action: Parameters<typeof dispatchStagedSetupAction>[0]['action'] = 'buildConfirm',
  ) => dispatchStagedSetupAction({
    action,
    controller,
    channelController,
    sections,
    sectionsServerId: () => 'server',
    runtime: {},
    previewCursor: null,
    setPreviewCursor: () => undefined,
    closePreviewMetadata: () => undefined,
    returnToServer: () => undefined,
    closeSetup: () => undefined,
    tuneChannel: async () => false,
    startBlankCustomDraft: () => undefined,
    cancelCustomDraft: () => undefined,
    cancelCustomDeleteConfirmation: () => undefined,
  } as never);

  controller.setBuildMode('append');
  await dispatch();
  assert.deepEqual(submissions[0], {
    buildMode: 'append',
    confirmReplace: false,
  });

  controller.showOwner('build', 'setup-confirm-replace');
  controller.setBuildMode('replace');
  await dispatch();
  assert.equal(submissions.length, 1);
  await dispatch('openReplaceConfirm');
  assert.equal(controller.getState().owner, 'replace-confirm');
  assert.equal(controller.getState().focusIntent, 'setup-replace-cancel');
  await handleStagedSetupBack({
    controller,
    dispatch,
  } as never);
  assert.equal(controller.getState().owner, 'build');
  assert.equal(controller.getState().focusIntent, 'setup-confirm-replace');
  await dispatch('openReplaceConfirm');
  await dispatch('confirmReplace');
  assert.deepEqual(submissions[1], {
    buildMode: 'replace',
    confirmReplace: true,
  });
});

test('skipped or stale apply restores the reviewed build owner instead of stranding progress', async () => {
  for (const outcome of ['skipped', 'stale'] as const) {
    const controller = createStagedSetupController({ onStateChanged: () => undefined });
    controller.toggleLibrary('library', [{ id: 'library', type: 'movie' }] as never);
    assert.equal(controller.prepareBuilderConfig({
      serverId: 'server',
      selectedLibraryIds: ['library'],
    }, {
      completion: 'unknown',
      normalizedConfig: null,
      completedAtMs: null,
    }), true);
    controller.setBuildMode('append');
    controller.showOwner('build', 'setup-confirm');
    await dispatchStagedSetupAction({
      action: 'buildConfirm',
      controller,
      channelController: {
        getState: () => ({ ...createChannelRuntimeRendererState(), summary: null }),
        applyReviewed: async () => outcome,
      },
      sections: [{ id: 'library', type: 'movie' }],
    } as never);
    assert.equal(controller.getState().owner, 'build', outcome);
    assert.equal(controller.getState().focusIntent, 'setup-confirm', outcome);
  }
});

function configuredSummary(): ChannelSetupSummary {
  return {
    status: 'configured',
    lineupRevision: 1,
    channelCount: 1,
    currentChannelId: 'channel-one',
    currentChannelNumber: 101,
    currentChannelName: 'Channel One',
    channelNumbers: [101],
    channels: [{
      id: 'channel-one',
      number: 101,
      name: 'Channel One',
      sourceLibraryId: 'movies',
      sourceLibraryName: 'Movies',
      itemCount: 4,
    }],
    builder: { completion: 'unknown', normalizedConfig: null, completedAtMs: null },
    updatedAtMs: 1,
    recovery: { loaded: true, repaired: false },
  };
}
