import test from 'node:test';
import assert from 'node:assert/strict';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupIpcResult,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';
import {
  activateWorkflowRoute,
  applyWorkflowChannelSetupAction,
  applyWorkflowEpgAction,
  applyWorkflowAction,
  applyWorkflowSettingsAction,
  applyWorkflowSupportBundleExportStatus,
  createWorkflowState,
  findRouteAction,
  getRouteWorkflowView,
} from '../../renderer/workflow.js';
import { createChannelRuntimeController } from '../../renderer/channelRuntimeActions.js';
import {
  sanitizeChannelRuntimeError,
  type ChannelRuntimeRendererState,
} from '../../renderer/channelRuntimeState.js';
import type { EpgPresentationSource } from '../../renderer/epg.js';

test('workflow state starts on the player route with injected presentation context', () => {
  const state = createWorkflowState();
  const view = getRouteWorkflowView(state);

  assert.deepEqual(state.routeState, { activeRoute: 'player', previousRoute: null });
  assert.equal(state.settingsDraft.launchMode, 'windowed');
  assert.equal(state.channelSetupDraft.activeStepId, 'channels');
  assert.equal(view.route, 'player');
  assert.equal(view.title, 'Player');
  assert.equal(view.currentProgram.channelName, 'Liminal One');
  assert.equal(view.currentProgram.title, 'The Midnight Archive');
  assert.equal(view.guide.selectedProgram?.title, 'Signal Warmup');
  assert.equal(view.actions.map((action) => action.id).join(','), 'openGuide,openSettings');
});

test('route actions move between existing route ids and carry status text', () => {
  const initial = createWorkflowState();
  const guide = applyWorkflowAction(initial, 'openGuide');
  const guideView = getRouteWorkflowView(guide);

  assert.deepEqual(guide.routeState, { activeRoute: 'guide', previousRoute: 'player' });
  assert.equal(guide.lastActionId, 'openGuide');
  assert.equal(guide.lastActionRoute, 'player');
  assert.equal(guideView.statusText, 'Guide opened from the player.');

  const setup = applyWorkflowAction(guide, 'openChannelSetup');
  assert.deepEqual(setup.routeState, { activeRoute: 'channelSetup', previousRoute: 'guide' });
  assert.equal(getRouteWorkflowView(setup).statusText, 'Plex onboarding opened from the guide.');

  const player = applyWorkflowAction(setup, 'confirmSetup');
  assert.equal(player, setup);
});

test('invalid route action for the active route leaves workflow state unchanged', () => {
  const initial = createWorkflowState('settings');
  const next = applyWorkflowAction(initial, 'openGuide');

  assert.equal(next, initial);
  assert.equal(findRouteAction('settings', 'openGuide'), null);
});

test('settings channel setup action uses settings-specific status text', () => {
  const setup = applyWorkflowAction(createWorkflowState('settings'), 'openChannelSetup');

  assert.deepEqual(setup.routeState, { activeRoute: 'channelSetup', previousRoute: 'settings' });
  assert.equal(setup.lastActionId, 'openChannelSetup');
  assert.equal(setup.lastActionRoute, 'settings');
  assert.equal(getRouteWorkflowView(setup).statusText, 'Plex onboarding opened from settings.');
});

test('settings player action uses settings-specific status text', () => {
  const player = applyWorkflowAction(createWorkflowState('settings'), 'resumePlayer');

  assert.deepEqual(player.routeState, { activeRoute: 'player', previousRoute: 'settings' });
  assert.equal(player.lastActionId, 'resumePlayer');
  assert.equal(player.lastActionRoute, 'settings');
  assert.equal(getRouteWorkflowView(player).statusText, 'Returned to player from settings.');
});

test('direct route activation clears action status and preserves previous route', () => {
  const guide = applyWorkflowAction(createWorkflowState(), 'openGuide');
  const settings = activateWorkflowRoute(guide, 'settings');
  const settingsView = getRouteWorkflowView(settings);

  assert.deepEqual(settings.routeState, { activeRoute: 'settings', previousRoute: 'guide' });
  assert.equal(settings.lastActionId, null);
  assert.equal(settings.lastActionRoute, null);
  assert.equal(settingsView.statusText, 'Settings shell is local-only and not persisted.');
});

test('settings actions update only renderer-local settings draft state', () => {
  const initial = createWorkflowState('settings');
  const fullscreen = applyWorkflowSettingsAction(initial, 'cycleLaunchMode');
  const compact = applyWorkflowSettingsAction(fullscreen, 'cycleGuideDensity');
  const hiddenBadges = applyWorkflowSettingsAction(compact, 'togglePreviewBadges');
  const view = getRouteWorkflowView(hiddenBadges);

  assert.deepEqual(hiddenBadges.routeState, initial.routeState);
  assert.equal(hiddenBadges.settingsDraft.launchMode, 'fullscreen-preview');
  assert.equal(hiddenBadges.settingsDraft.guideDensity, 'compact');
  assert.equal(hiddenBadges.settingsDraft.previewBadgesEnabled, false);
  assert.equal(view.settings.playbackMode, 'Fullscreen desktop player');
  assert.equal(view.settings.sections.length, 3);
});

test('support bundle settings action is user-gesture state and renders safe export status only', () => {
  const initial = createWorkflowState('settings');
  const exporting = applyWorkflowSettingsAction(initial, 'exportSupportBundle');
  const succeeded = applyWorkflowSupportBundleExportStatus(exporting, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-bundle-1',
    fileCount: 6,
    redactionStatus: 'passed',
  });
  const view = getRouteWorkflowView(succeeded);
  const supportBundle = view.settings.sections
    .flatMap((section) => section.items)
    .find((item) => item.id === 'support-bundle-export');

  assert.equal(exporting.settingsDraft.supportBundleExport.status, 'exporting');
  assert.equal(supportBundle?.valueLabel, 'lineup-desktop-support-bundle-1 - 6 files');
  assert.equal(JSON.stringify(view).includes('/Users/'), false);
  assert.equal(JSON.stringify(view).includes('C:\\'), false);
  assert.equal(JSON.stringify(view).includes('path'), false);
});

test('support bundle status sanitizes display names and shows redaction outcomes', () => {
  const initial = createWorkflowState('settings');
  const unsafe = applyWorkflowSupportBundleExportStatus(initial, {
    status: 'succeeded',
    bundleDirectoryName: 'C:\\Users\\private\\tokenizedUrl-secret',
    fileCount: 6.9,
    redactionStatus: 'failed',
  });
  const pending = applyWorkflowSupportBundleExportStatus(initial, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-bundle-3',
    fileCount: 6,
    redactionStatus: null,
  });
  const unsafeBundle = getRouteWorkflowView(unsafe).settings.sections
    .flatMap((section) => section.items)
    .find((item) => item.id === 'support-bundle-export');
  const pendingBundle = getRouteWorkflowView(pending).settings.sections
    .flatMap((section) => section.items)
    .find((item) => item.id === 'support-bundle-export');

  assert.equal(unsafe.settingsDraft.supportBundleExport.bundleDirectoryName, null);
  assert.equal(unsafe.settingsDraft.supportBundleExport.fileCount, 6);
  assert.equal(unsafeBundle?.valueLabel, 'Bundle - 6 files (redaction failed)');
  assert.equal(pendingBundle?.valueLabel, 'lineup-desktop-support-bundle-3 - 6 files (redaction pending)');
  assert.equal(JSON.stringify(unsafe).includes('C:\\Users'), false);
});

test('workflow product route uses injected presentation fixtures', () => {
  const presentation: EpgPresentationSource = {
    channels: [
      {
        id: 'injected-channel',
        number: '777',
        name: 'Injected Channel',
        programs: [
          {
            id: 'injected-program',
            title: 'Injected Program',
            subtitle: 'Injected Subtitle',
            description: 'Injected guide description.',
            showTitle: 'Injected Show',
            episodeLabel: 'S1 E7',
            rating: 'TV-G',
            quality: ['HD'],
            genres: ['Injected'],
            startsAtMs: Date.UTC(2026, 4, 12, 20, 0, 0),
            endsAtMs: Date.UTC(2026, 4, 12, 21, 0, 0),
          },
        ],
      },
    ],
    nowWatching: {
      title: 'Injected Now Watching',
      subtitle: 'Current injected episode',
      channelId: 'injected-channel',
      startsAtMs: Date.UTC(2026, 4, 12, 20, 0, 0),
      endsAtMs: Date.UTC(2026, 4, 12, 21, 0, 0),
    },
  };
  const view = getRouteWorkflowView(createWorkflowState('player', presentation));

  assert.equal(view.currentProgram.title, 'Injected Now Watching');
  assert.equal(view.channels[0]?.name, 'Injected Channel');
  assert.equal(view.guide.selectedProgram?.title, 'Injected Program');
  assert.doesNotMatch(JSON.stringify(view), /Liminal|Midnight Archive|The Vault/u);
});

test('settings surface uses persisted channel setup status when available', () => {
  const channelRuntime: ChannelRuntimeRendererState = {
    pending: false,
    statusText: 'Recovered',
    errorText: null,
    commitMode: 'append',
    confirmReplace: false,
    summary: {
      status: 'configured',
      channelCount: 2,
      currentChannelId: 'channel-two',
      currentChannelNumber: 204,
      currentChannelName: 'Channel Two',
      channelNumbers: [101, 204],
      channels: [
        {
          id: 'channel-one',
          number: 101,
          name: 'Channel One',
          sourceLibraryId: 'movies',
          sourceLibraryName: 'Movies',
          itemCount: 12,
        },
        {
          id: 'channel-two',
          number: 204,
          name: 'Channel Two',
          sourceLibraryId: 'shows',
          sourceLibraryName: 'Shows',
          itemCount: 8,
        },
      ],
      updatedAtMs: 123,
      recovery: { loaded: true, repaired: false },
    },
  };

  const view = getRouteWorkflowView(createWorkflowState('settings'), channelRuntime);
  const setupView = getRouteWorkflowView(createWorkflowState('channelSetup'), channelRuntime);

  assert.equal(view.settings.libraryName, 'Channel Two');
  assert.equal(view.settings.channelCount, 2);
  assert.equal(view.settings.setupState, 'Recovered');
  assert.equal(view.settings.recoveryDetail, '2 persisted channels; Current channel 204.');
  assert.equal(setupView.channelSetupSummary.sourceName, 'No library selected');
  assert.equal(setupView.channelSetupSummary.enabledChannelCount, 0);
  assert.equal(setupView.channelSetupSummary.readyForPreview, false);
  assert.equal(
    view.settings.sections.find((section) => section.id === 'setup')?.items[0]?.valueLabel,
    '2',
  );
  assert.equal(containsPlexForbiddenRendererField(view.settings), false);
});

test('settings copy describes Desktop-local capabilities and avoids legacy platform truth', () => {
  const view = getRouteWorkflowView(createWorkflowState('settings'));
  const settingsCopy = [
    view.primaryText,
    view.secondaryText,
    view.statusText,
    ...view.settings.sections.flatMap((section) => [
      section.title,
      section.detail,
      ...section.items.flatMap((item) => [item.label, item.valueLabel, item.description]),
    ]),
  ].join(' ');

  assert.match(settingsCopy, /Desktop|desktop/);
  assert.match(settingsCopy, /renderer|local|session/);
  assert.match(settingsCopy, /no desktop preference is saved|without writing preferences/);
  assert.doesNotMatch(settingsCopy, /webOS|Luna|Palm|TV service/i);
});

test('draft setup state stays isolated until persisted channel status is available', () => {
  const initial = createWorkflowState('channelSetup');
  const pausedFeatured = applyWorkflowChannelSetupAction(initial, 'toggleFeaturedChannel');
  const withDraft = applyWorkflowChannelSetupAction(pausedFeatured, 'addDraftChannel');
  const review = applyWorkflowChannelSetupAction(withDraft, 'advanceSetupStep');
  const view = getRouteWorkflowView(review);
  const viewText = JSON.stringify({
    settings: view.settings,
    channelDrafts: view.channelDrafts,
    channelSetupSummary: view.channelSetupSummary,
    setupSteps: view.setupSteps,
    setupValidationMessages: view.setupValidationMessages,
  });

  assert.deepEqual(review.routeState, initial.routeState);
  assert.equal(view.channelDrafts.length, 0);
  assert.equal(view.channelSetupSummary.sourceName, 'Persisted channel status unavailable');
  assert.equal(view.channelSetupSummary.enabledChannelCount, 0);
  assert.equal(view.channelSetupSummary.totalChannelCount, 0);
  assert.equal(view.channelSetupSummary.totalBlockCount, 0);
  assert.equal(view.channelSetupSummary.readyForPreview, false);
  assert.equal(view.channelSetupFlow.stages.find((step) => step.id === 'library')?.state, 'current');
  assert.equal(view.channelSetupFlow.stages.find((step) => step.id === 'review')?.state, 'pending');
  assert.deepEqual(view.setupValidationMessages, [
    'Choose a movie or show library section before saving channels. Selecting an individual media item only opens metadata preview.',
  ]);
  assert.doesNotMatch(viewText, /Demo Library|Liminal One|The Vault|Weekend Queue/u);
  assert.doesNotMatch(viewText, /2 of 3|6 programming blocks|16 programming blocks/u);

  const reset = applyWorkflowChannelSetupAction(review, 'resetDraftLineup');
  assert.equal(getRouteWorkflowView(reset).channelDrafts.length, 0);
  assert.deepEqual(getRouteWorkflowView(initial).actions, []);
});

test('channel setup view uses selected Plex library as the channel creation source', () => {
  const view = getRouteWorkflowView(
    createWorkflowState('channelSetup'),
    configuredChannelRuntimeState(),
    {
      sourceName: 'Selected Movies',
      sourceType: 'movie',
      contentCount: 12,
      loadedItemCount: 4,
    },
  );

  assert.equal(view.channelSetupSummary.sourceName, 'Selected Movies');
  assert.equal(view.channelSetupSummary.enabledChannelCount, 1);
  assert.equal(view.channelSetupSummary.totalBlockCount, 4);
  assert.equal(view.channelSetupSummary.readyForPreview, true);
  assert.deepEqual(view.channelSetupCommitAvailability, {
    append: true,
    replace: true,
    confirmReplace: false,
  });
  assert.match(view.setupSteps.map((step) => step.detail).join(' '), /Selected movie library: Selected Movies/u);
  assert.deepEqual(view.channelSetupFlow.stages.map((stage) => stage.label), [
    'Choose library',
    'Configure channels',
    'Review changes',
    'Build result',
  ]);
  assert.equal(view.channelSetupFlow.library.marker, 'MOV');
  assert.equal(view.channelSetupFlow.reviewRows[0]?.value, 'Selected Movies');
  assert.equal(view.channelSetupFlow.reviewRows.find((row) => row.label === 'Build mode')?.value, 'Append to saved lineup');
  assert.equal(view.channelSetupFlow.strategyOptions.find((option) => option.id === 'build-mode-append')?.selected, true);
  assert.equal(view.channelSetupFlow.strategyOptions.find((option) => option.id === 'build-mode-replace')?.disabled, false);
  assert.deepEqual(view.setupValidationMessages, [
    'Selected library is ready. Review the strategy, then append it to saved channels or replace the lineup.',
  ]);
});

test('channel setup local strategy actions update review state without persistence', () => {
  const initial = createWorkflowState('channelSetup');
  const replace = applyWorkflowChannelSetupAction(initial, 'selectReplaceBuildMode');
  const append = applyWorkflowChannelSetupAction(replace, 'selectAppendBuildMode');
  const source = applyWorkflowChannelSetupAction(append, 'selectRecentlyAddedSource');
  const replaceView = getRouteWorkflowView(replace, configuredChannelRuntimeState(), {
    sourceName: 'Selected Movies',
    sourceType: 'movie',
    contentCount: 12,
    loadedItemCount: 4,
  });
  const appendView = getRouteWorkflowView(append, configuredChannelRuntimeState(), {
    sourceName: 'Selected Movies',
    sourceType: 'movie',
    contentCount: 12,
    loadedItemCount: 4,
  });

  assert.equal(replace.channelSetupDraft.buildMode, 'replace');
  assert.equal(source.channelSetupDraft.sourceMode, 'recently-added');
  assert.equal(replaceView.channelSetupFlow.buildMode, 'replace');
  assert.equal(replaceView.channelSetupFlow.reviewRows.find((row) => row.label === 'Build mode')?.value, 'Replace saved lineup');
  assert.equal(replaceView.channelSetupFlow.strategyOptions.find((option) => option.id === 'build-mode-replace')?.selected, true);
  assert.equal(appendView.channelSetupFlow.buildMode, 'append');
  assert.equal(appendView.channelSetupFlow.reviewRows.find((row) => row.label === 'Build mode')?.value, 'Append to saved lineup');
});

test('channel setup first-run create state only enables append for a selected library', () => {
  const firstRunRuntime: ChannelRuntimeRendererState = {
    pending: false,
    statusText: 'No persisted channels',
    errorText: null,
    commitMode: 'append',
    confirmReplace: false,
    summary: {
      status: 'not-configured',
      channelCount: 0,
      currentChannelId: null,
      currentChannelNumber: null,
      currentChannelName: null,
      channelNumbers: [],
      channels: [],
      updatedAtMs: 123,
      recovery: { loaded: true, repaired: false },
    },
  };
  const view = getRouteWorkflowView(
    createWorkflowState('channelSetup'),
    firstRunRuntime,
    {
      sourceName: 'First Run Movies',
      sourceType: 'movie',
      contentCount: 12,
      loadedItemCount: 0,
    },
  );

  assert.deepEqual(view.channelSetupCommitAvailability, {
    append: true,
    replace: false,
    confirmReplace: false,
  });
  assert.deepEqual(view.setupValidationMessages, [
    'Selected library is ready. Review the strategy, then create channels from this library to continue.',
  ]);
});

test('channel setup confirm state comes from explicit runtime confirmation', () => {
  const view = getRouteWorkflowView(
    createWorkflowState('channelSetup'),
    {
      ...configuredChannelRuntimeState(),
      statusText: 'Channel status unavailable',
      errorText: 'Replacing saved channels requires confirmation.',
      commitMode: 'replace',
      confirmReplace: true,
    },
    {
      sourceName: 'Selected Movies',
      sourceType: 'movie',
      contentCount: 12,
      loadedItemCount: 4,
    },
  );

  assert.deepEqual(view.channelSetupCommitAvailability, {
    append: true,
    replace: true,
    confirmReplace: true,
  });
  assert.deepEqual(view.setupValidationMessages, [
    'Replacing saved channels requires confirmation.',
  ]);
});

test('channel setup view surfaces sanitized commit failures in the review panel', () => {
  const failedRuntime: ChannelRuntimeRendererState = {
    ...configuredChannelRuntimeState(),
    summary: null,
    statusText: 'Channel status unavailable',
    errorText: 'Selected Plex libraries did not return usable channel content.',
  };
  const view = getRouteWorkflowView(
    createWorkflowState('channelSetup'),
    failedRuntime,
    {
      sourceName: 'Selected Shows',
      sourceType: 'show',
      contentCount: 6,
      loadedItemCount: 6,
    },
  );

  assert.deepEqual(view.setupValidationMessages, [
    'Selected Plex libraries did not return usable channel content.',
  ]);
  assert.equal(JSON.stringify(view).includes('serverUri'), false);
  assert.equal(JSON.stringify(view).includes('token'), false);
});

test('channel runtime validation errors fall back when private terms remain', () => {
  const safe = sanitizeChannelRuntimeError({
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Selected Plex libraries did not return usable channel content.',
    retryable: false,
    recoverable: true,
    operation: 'commit',
  });
  const unsafe = sanitizeChannelRuntimeError({
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'serverUri https://private.example/token failed for C:\\Users\\private',
    retryable: false,
    recoverable: true,
    operation: 'commit',
  });

  assert.equal(safe, 'Selected Plex libraries did not return usable channel content.');
  assert.equal(unsafe, 'Channel setup could not continue.');
});

test('channel setup action state clears without discarding pending status recovery', async () => {
  const pendingStatus = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const pendingRefresh = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const pendingCommit = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const statusResults = [pendingStatus, pendingRefresh];
  let renderCount = 0;
  const controller = createChannelRuntimeController({
    bridge: {
      getStatus: async () => {
        const next = statusResults.shift();
        assert.ok(next);
        return next.promise;
      },
      commit: async () => pendingCommit.promise,
    },
    onStateChanged: () => {
      renderCount += 1;
    },
  });

  const statusPromise = controller.loadStatus();
  assert.equal(controller.getState().pending, true);
  controller.clearActionState();
  assert.equal(controller.getState().pending, true);
  assert.equal(controller.getState().errorText, null);
  pendingStatus.resolve(channelSetupSuccess('status-1', configuredChannelRuntimeState().summary as ChannelSetupSummary));
  await statusPromise;
  assert.equal(controller.getState().pending, false);
  assert.equal(controller.getState().summary?.channelCount, 1);

  controller.markBlocked('Choose a movie or show library section before saving channels.');
  let view = getRouteWorkflowView(createWorkflowState('channelSetup'), controller.getState(), {
    sourceName: 'Selected Movies',
    sourceType: 'movie',
    contentCount: 12,
    loadedItemCount: 2,
  });
  assert.deepEqual(view.setupValidationMessages, [
    'Choose a movie or show library section before saving channels.',
  ]);

  controller.clearActionState();
  view = getRouteWorkflowView(createWorkflowState('channelSetup'), controller.getState(), {
    sourceName: 'Selected Movies',
    sourceType: 'movie',
    contentCount: 12,
    loadedItemCount: 2,
  });
  assert.deepEqual(view.setupValidationMessages, [
    'Selected library is ready. Review the strategy, then append it to saved channels or replace the lineup.',
  ]);
  assert.equal(controller.getState().confirmReplace, false);

  const commitPromise = controller.commit({ mode: 'replace', sectionIds: ['old-section'] });
  assert.equal(controller.getState().pending, true);
  controller.clearActionState();
  assert.equal(controller.getState().pending, true);
  assert.equal(controller.getState().errorText, null);
  pendingCommit.resolve(channelSetupFailure('commit-1', {
    code: 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
    message: 'Replacing saved channels requires confirmation.',
    retryable: false,
    recoverable: true,
    operation: 'commit',
  }));
  await Promise.resolve();
  assert.equal(controller.getState().pending, true);
  pendingRefresh.resolve(channelSetupSuccess('status-2', {
    ...configuredChannelRuntimeState().summary as ChannelSetupSummary,
    channelCount: 2,
    channelNumbers: [101, 102],
  }));
  await commitPromise;

  assert.equal(controller.getState().errorText, null);
  assert.equal(controller.getState().confirmReplace, false);
  assert.equal(controller.getState().pending, false);
  assert.equal(controller.getState().summary?.channelCount, 2);
  assert.ok(renderCount >= 4);
});

test('channel setup route does not use draft setup fallback after status failure', () => {
  const failedRuntime: ChannelRuntimeRendererState = {
    pending: false,
    statusText: 'Channel status unavailable',
    errorText: 'Channel setup status could not be loaded.',
    commitMode: 'append',
    confirmReplace: false,
    summary: null,
  };
  const view = getRouteWorkflowView(createWorkflowState('channelSetup'), failedRuntime);
  const viewText = JSON.stringify({
    settings: view.settings,
    channelDrafts: view.channelDrafts,
    channelSetupSummary: view.channelSetupSummary,
    setupSteps: view.setupSteps,
    setupValidationMessages: view.setupValidationMessages,
  });

  assert.equal(view.settings.setupState, 'Channel setup status could not be loaded.');
  assert.equal(view.channelDrafts.length, 0);
  assert.deepEqual(view.channelSetupSummary, {
    sourceName: 'Persisted channel status unavailable',
    enabledChannelCount: 0,
    totalChannelCount: 0,
    totalBlockCount: 0,
    readyForPreview: false,
  });
  assert.doesNotMatch(viewText, /Demo Library|Liminal One|The Vault|Weekend Queue/u);
  assert.doesNotMatch(viewText, /2 of 3|6 programming blocks|16 programming blocks/u);
});

test('channel setup disables commits after failed status even with a selected library', () => {
  const failedRuntime: ChannelRuntimeRendererState = {
    pending: false,
    statusText: 'Channel status unavailable',
    errorText: 'Channel setup status could not be loaded.',
    commitMode: 'append',
    confirmReplace: false,
    summary: null,
  };
  const view = getRouteWorkflowView(createWorkflowState('channelSetup'), failedRuntime, {
    sourceName: 'Selected Movies',
    sourceType: 'movie',
    contentCount: 12,
    loadedItemCount: 4,
  });

  assert.deepEqual(view.channelSetupCommitAvailability, {
    append: false,
    replace: false,
    confirmReplace: false,
  });
  assert.deepEqual(view.setupValidationMessages, [
    'Channel setup status could not be loaded.',
  ]);
  assert.equal(view.channelSetupFlow.result.detail, 'Channel setup status could not be loaded.');
  assert.equal(JSON.stringify(view).includes('serverUri'), false);
  assert.equal(JSON.stringify(view).includes('token'), false);
});

test('EPG actions update only renderer-local guide state', () => {
  const initial = createWorkflowState('guide');
  const nextChannel = applyWorkflowEpgAction(initial, 'nextChannel');
  const later = applyWorkflowEpgAction(nextChannel, 'nextWindow');
  const view = getRouteWorkflowView(later);

  assert.deepEqual(later.routeState, initial.routeState);
  assert.equal(view.guide.windowStartMs, initial.epg.windowStartMs + 30 * 60 * 1000);
  assert.equal(view.guide.selectedProgram?.channelId, 'channel-vault');
  assert.equal(view.guide.selectedProgram?.title, 'Restored Feature');
});

test('workflow view models avoid Plex and player privileged renderer fields', () => {
  const routeIds = ['player', 'guide', 'settings', 'channelSetup'] as const;

  for (const routeId of routeIds) {
    const view = getRouteWorkflowView(createWorkflowState(routeId));
    assert.equal(containsPlexForbiddenRendererField(view), false, routeId);
  }
});

function configuredChannelRuntimeState(): ChannelRuntimeRendererState {
  return {
    pending: false,
    statusText: 'Recovered',
    errorText: null,
    commitMode: 'append',
    confirmReplace: false,
    summary: {
      status: 'configured',
      channelCount: 1,
      currentChannelId: 'channel-one',
      currentChannelNumber: 101,
      currentChannelName: 'Channel One',
      channelNumbers: [101],
      channels: [
        {
          id: 'channel-one',
          number: 101,
          name: 'Channel One',
          sourceLibraryId: 'movies',
          sourceLibraryName: 'Movies',
          itemCount: 4,
        },
      ],
      updatedAtMs: 123,
      recovery: { loaded: true, repaired: false },
    },
  };
}

function deferred<TValue>(): {
  promise: Promise<TValue>;
  resolve: (value: TValue) => void;
} {
  let resolve: (value: TValue) => void = () => undefined;
  const promise = new Promise<TValue>((innerResolve) => {
    resolve = innerResolve;
  });
  return { promise, resolve };
}
