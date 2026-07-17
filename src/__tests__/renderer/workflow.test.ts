import test from 'node:test';
import assert from 'node:assert/strict';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupIpcResult,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';
import { deferred } from '../helpers/deferred.js';
import {
  activateWorkflowRoute,
  applyWorkflowChannelSetupAction,
  applyWorkflowEpgAction,
  applyWorkflowAction,
  applyWorkflowSettingsAction,
  applyWorkflowSettingsValues,
  applyWorkflowSupportBundleExportStatus,
  createWorkflowState as createWorkflowStateCore,
  findRouteAction,
  getRouteWorkflowView,
} from '../../renderer/workflow.js';
import { createChannelRuntimeController } from '../../renderer/channelRuntimeActions.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import {
  sanitizeChannelRuntimeError,
  type ChannelRuntimeRendererState,
} from '../../renderer/channelRuntimeState.js';
import { setEpgPresentationState, type EpgPresentationSource } from '../../renderer/epg.js';
import { createStagedSetupController, dispatchStagedSetupAction, handleStagedSetupBack } from '../../renderer/setup/stagedSetupController.js';
import { createCustomChannelController } from '../../renderer/customChannels/controller.js';

function legacyChannelBridge(
  bridge: Pick<LineupDesktopPreloadApi['channelSetup'], 'getStatus' | 'commit'>,
): LineupDesktopPreloadApi['channelSetup'] {
  const unused = async (): Promise<never> => { throw new Error('builder bridge is not used by this legacy workflow test'); };
  return { ...bridge, getRecord: unused, preview: unused, review: unused, build: unused, cancelBuild: unused };
}

const GUIDE_BASE = Date.UTC(2026, 4, 12, 20, 0, 0);
const TEST_GUIDE_PRESENTATION: EpgPresentationSource = {
  channels: [
    {
      id: 'channel-liminal-one', number: '101', name: 'Liminal One', programs: [
        {
          id: 'liminal-archive', title: 'The Midnight Archive', subtitle: 'Signal Lost',
          description: 'Archive description.', showTitle: 'The Midnight Archive', episodeLabel: 'S2 E4',
          rating: 'TV-14', quality: ['HD'], genres: ['Drama'],
          startsAtMs: GUIDE_BASE, endsAtMs: GUIDE_BASE + 4 * 30 * 60 * 1000,
        },
      ],
    },
    {
      id: 'channel-vault', number: '204', name: 'The Vault', programs: [
        {
          id: 'vault-feature', title: 'Restored Feature', subtitle: 'Studio print',
          description: 'Feature description.', showTitle: 'Restored Feature', episodeLabel: 'Feature',
          rating: 'PG', quality: ['HD'], genres: ['Cinema'],
          startsAtMs: GUIDE_BASE, endsAtMs: GUIDE_BASE + 8 * 30 * 60 * 1000,
        },
      ],
    },
  ],
  nowWatching: {
    title: 'The Midnight Archive', subtitle: 'Signal Lost', channelId: 'channel-liminal-one',
    startsAtMs: GUIDE_BASE, endsAtMs: GUIDE_BASE + 4 * 30 * 60 * 1000,
  },
  nowMs: GUIDE_BASE + 30 * 60 * 1000,
};

function createWorkflowState(
  route: Parameters<typeof createWorkflowStateCore>[0] = 'player',
  guidePresentation: EpgPresentationSource = TEST_GUIDE_PRESENTATION,
) {
  return createWorkflowStateCore(route, guidePresentation);
}

test('workflow state starts on the player route with injected presentation context', () => {
  const state = createWorkflowState();
  const view = getRouteWorkflowView(state);

  assert.deepEqual(state.routeState, { activeRoute: 'player', previousRoute: null });
  assert.equal(state.settingsDraft.launchMode, 'windowed');
  assert.equal(state.channelSetupDraft.buildMode, 'append');
  assert.equal(view.route, 'player');
  assert.equal(view.title, 'Player');
  assert.equal(view.currentProgram.channelName, 'Liminal One');
  assert.equal(view.currentProgram.title, 'The Midnight Archive');
  assert.equal(view.guide.selectedProgram?.title, 'The Midnight Archive');
  assert.equal(view.actions.map((action) => action.id).join(','), 'openChannelSetup,openGuide,openSettings');
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

test('player channel setup fallback opens the setup route', () => {
  const setup = applyWorkflowAction(createWorkflowState('player'), 'openChannelSetup');

  assert.deepEqual(setup.routeState, { activeRoute: 'channelSetup', previousRoute: 'player' });
  assert.equal(setup.lastActionId, 'openChannelSetup');
  assert.equal(setup.lastActionRoute, 'player');
  assert.equal(getRouteWorkflowView(setup).statusText, 'Channel setup opened from the player.');
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
  assert.equal(settingsView.statusText, 'Desktop settings are ready.');
});

test('workflow projects settings values accepted by the persisted runtime', () => {
  const initial = createWorkflowState('settings');
  const hiddenBadges = applyWorkflowSettingsValues(initial, {
    launchMode: 'fullscreen',
    guideDensity: 'compact',
    previewBadgesEnabled: false,
    setupReminderEnabled: true,
  });
  const view = getRouteWorkflowView(hiddenBadges);

  assert.deepEqual(hiddenBadges.routeState, initial.routeState);
  assert.equal(hiddenBadges.settingsDraft.launchMode, 'fullscreen');
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
  assert.doesNotMatch(JSON.stringify(view), /(?:[A-Za-z]:\\|\/Users\/|\/home\/)/u);
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

test('workflow product route uses injected renderer-safe presentation state', () => {
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
    nowMs: Date.UTC(2026, 4, 12, 20, 30, 0),
  };
  const view = getRouteWorkflowView(createWorkflowState('player', presentation));

  assert.equal(view.currentProgram.title, 'Injected Now Watching');
  assert.equal(view.channels[0]?.name, 'Injected Channel');
  assert.equal(view.guide.selectedProgram?.title, 'Injected Program');
  assert.doesNotMatch(JSON.stringify(view), /Liminal|Midnight Archive|The Vault/u);
});

test('workflow route summaries fall back to guide-state placeholders until the guide is ready', () => {
  const loadingState = {
    ...createWorkflowState('guide'),
    epg: setEpgPresentationState(createWorkflowState('guide').epg, 'loading'),
  };
  const guideView = getRouteWorkflowView(loadingState);
  const playerView = getRouteWorkflowView({
    ...createWorkflowState('player'),
    epg: setEpgPresentationState(createWorkflowState('player').epg, 'error'),
  });

  assert.equal(guideView.channels.length, 0);
  assert.equal(guideView.currentProgram.title, 'Loading guide');
  assert.equal(guideView.currentProgram.startsAtMs, null);
  assert.equal(guideView.primaryText, 'Schedule rows are preparing for the selected lineup.');
  assert.equal(playerView.channels.length, 0);
  assert.equal(playerView.currentProgram.title, 'Guide unavailable');
  assert.equal(playerView.currentProgram.endsAtMs, null);
  assert.equal(playerView.primaryText, 'Current program details are temporarily unavailable.');
  assert.doesNotMatch(
    JSON.stringify({
      guidePrimaryText: guideView.primaryText,
      guideCurrentProgram: guideView.currentProgram,
      playerPrimaryText: playerView.primaryText,
      playerCurrentProgram: playerView.currentProgram,
      guideChannels: guideView.channels,
      playerChannels: playerView.channels,
    }),
    /The Midnight Archive|4 channels are available|is cued on Liminal One/u,
  );
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
    view.settings.sections.find((section) => section.id === 'recovery')?.items[1]?.valueLabel,
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
  assert.match(settingsCopy, /stored|relaunch|every launch/i);
  assert.doesNotMatch(settingsCopy, /local-only|session only|no desktop preference is saved/i);
  assert.doesNotMatch(settingsCopy, /webOS|Luna|Palm|TV service/i);
});

test('channel setup route is driven by live status and selected library only', () => {
  const initial = createWorkflowState('channelSetup');
  const replace = applyWorkflowChannelSetupAction(initial, 'selectReplaceBuildMode');
  const append = applyWorkflowChannelSetupAction(replace, 'selectAppendBuildMode');
  const view = getRouteWorkflowView(append);
  const viewText = JSON.stringify({
    settings: view.settings,
    channelSetupSummary: view.channelSetupSummary,
    setupValidationMessages: view.setupValidationMessages,
  });

  assert.deepEqual(append.routeState, initial.routeState);
  assert.equal(append.channelSetupDraft.buildMode, 'append');
  assert.equal('sourceMode' in append.channelSetupDraft, false);
  assert.equal(view.channelSetupSummary.sourceName, 'Persisted channel status unavailable');
  assert.equal(view.channelSetupSummary.enabledChannelCount, 0);
  assert.equal(view.channelSetupSummary.totalChannelCount, 0);
  assert.equal(view.channelSetupSummary.totalBlockCount, 0);
  assert.equal(view.channelSetupSummary.readyForPreview, false);
  assert.deepEqual(view.setupValidationMessages, [
    'Choose a movie or show library section before saving channels. Selecting an individual media item only opens metadata preview.',
  ]);
  assert.doesNotMatch(viewText, /Demo Library|Liminal One|The Vault|Weekend Queue/u);
  assert.doesNotMatch(viewText, /2 of 3|6 programming blocks|16 programming blocks/u);
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
  assert.equal(view.channelSetupFlow.library.marker, 'MOV');
  assert.equal(view.channelSetupFlow.reviewRows[0]?.value, 'Selected Movies');
  assert.equal(view.channelSetupFlow.reviewRows.find((row) => row.label === 'Build mode')?.value, 'Append to saved lineup');
  assert.deepEqual(view.setupValidationMessages, [
    'Selected library is ready. Review the strategy, then append it to saved channels or replace the lineup.',
  ]);
});

test('channel setup local strategy actions update review state without persistence', () => {
  const initial = createWorkflowState('channelSetup');
  const replace = applyWorkflowChannelSetupAction(initial, 'selectReplaceBuildMode');
  const append = applyWorkflowChannelSetupAction(replace, 'selectAppendBuildMode');
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
  assert.equal('sourceMode' in append.channelSetupDraft, false);
  assert.equal(replaceView.channelSetupFlow.buildMode, 'replace');
  assert.equal(replaceView.channelSetupFlow.reviewRows.find((row) => row.label === 'Build mode')?.value, 'Replace saved lineup');
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
  const linuxPath = sanitizeChannelRuntimeError({
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Failed at /home/alice/project/file',
    retryable: false,
    recoverable: true,
    operation: 'commit',
  });
  const uncPath = sanitizeChannelRuntimeError({
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Failed at \\\\server\\share\\file',
    retryable: false,
    recoverable: true,
    operation: 'commit',
  });

  assert.equal(safe, 'Selected Plex libraries did not return usable channel content.');
  assert.equal(unsafe, 'Channel setup could not continue.');
  assert.equal(linuxPath, 'Channel setup could not continue.');
  assert.equal(uncPath, 'Channel setup could not continue.');
});

test('channel setup action state clears without discarding pending status recovery', async () => {
  const pendingStatus = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const pendingRefresh = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const pendingCommit = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  const statusResults = [pendingStatus, pendingRefresh];
  let renderCount = 0;
  const controller = createChannelRuntimeController({
    bridge: legacyChannelBridge({
      getStatus: async () => {
        const next = statusResults.shift();
        assert.ok(next);
        return next.promise;
      },
      commit: async () => pendingCommit.promise,
    }),
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
    channelSetupSummary: view.channelSetupSummary,
    setupValidationMessages: view.setupValidationMessages,
  });

  assert.equal(view.settings.setupState, 'Channel setup status could not be loaded.');
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

test('staged setup keeps one owner, invalidates cancelled progress, and chooses Watch deterministically', () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  controller.enter('settings', 'settings-setup');
  controller.showOwner('preview', 'setup-preview-toggle');
  controller.showOwner('build', 'setup-confirm');
  const staleGeneration = controller.beginCommit();
  controller.cancelCommitView();
  assert.equal(controller.completeCommit(staleGeneration, 'append', null, configuredChannelRuntimeState().summary), false);
  assert.equal(controller.getState().owner, 'build');

  const generation = controller.beginCommit();
  const after = configuredChannelRuntimeState().summary;
  assert.equal(controller.completeCommit(generation, 'append', null, after), true);
  assert.equal(controller.getState().owner, 'result');
  assert.equal(controller.getState().resultWatchChannelId, 'channel-one');
  assert.equal(controller.getState().returnRoute, 'settings');
  assert.equal(controller.getState().returnFocusId, 'settings-setup');
});

test('library Retry inspects failure and restores retained, first eligible, or empty focus', async () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  const movies = { id: 'movies', title: 'Movies', type: 'movie' as const, contentCount: 1, lastScannedAtMs: 0 };
  const shows = { id: 'shows', title: 'Shows', type: 'show' as const, contentCount: 1, lastScannedAtMs: 0 };
  let sections = [movies, shows];
  type LibraryState = 'ready' | 'empty' | 'error';
  let library: LibraryState = 'ready';
  let nextLibrary: LibraryState = 'ready';
  let plexError: string | null = null;
  const runtime = {
    getState: () => ({ library, preview: 'collapsed', serverId: 'server-1', previewSectionId: null, previewRatingKey: null }),
    retryLibraries: async () => { library = nextLibrary; },
  } as unknown as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'];
  const dispatch = () => dispatchStagedSetupAction({
    action: controller.getState().owner === 'recovery-error' ? 'recoveryRetry' : 'libraryRetry', controller, runtime,
    channelController: {} as Parameters<typeof dispatchStagedSetupAction>[0]['channelController'],
    sections, getSections: () => sections, getCurrentPlexError: () => plexError,
    previewCursor: null, getPreviewRatingKey: () => null, sectionsServerId: () => 'server-1',
    setPreviewCursor: () => undefined, closePreviewMetadata: () => undefined, returnToServer: () => undefined,
    closeSetup: () => undefined, tuneChannel: async () => false, startBlankCustomDraft: () => undefined,
    cancelCustomDraft: () => undefined, cancelCustomDeleteConfirmation: () => undefined,
  });

  controller.toggleLibrary('shows', sections);
  await dispatch();
  assert.equal(controller.getState().focusIntent, 'plex-dyn-section-shows');
  controller.clearLibraries(sections);
  sections = [movies];
  await dispatch();
  assert.equal(controller.getState().focusIntent, 'plex-dyn-section-movies');

  sections = [];
  nextLibrary = 'empty';
  await dispatch();
  assert.equal(controller.getState().focusIntent, 'setup-library-retry');
  nextLibrary = 'error';
  plexError = 'Libraries are offline.';
  await dispatch();
  assert.equal(controller.getState().owner, 'recovery-error');
  assert.equal(controller.getState().safeError, 'Libraries are offline.');
  assert.equal(controller.getState().focusIntent, 'setup-error-retry');
  await dispatch();
  assert.equal(controller.getState().owner, 'recovery-error');
  assert.equal(controller.getState().focusIntent, 'setup-error-retry');
  sections = [movies];
  nextLibrary = 'ready';
  plexError = null;
  await dispatch();
  assert.equal(controller.getState().owner, 'library');
  assert.equal(controller.getState().focusIntent, 'plex-dyn-section-movies');
  controller.toggleLibrary('movies', sections);
  nextLibrary = 'error';
  plexError = 'Libraries are offline.';
  await dispatch();
  nextLibrary = 'ready';
  plexError = null;
  await dispatch();
  assert.equal(controller.getState().focusIntent, 'plex-dyn-section-movies');
});

test('staged setup projects the 24-library selection limit into renderer state', () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  const sections = Array.from({ length: 25 }, (_, index) => ({
    id: `library-${String(index + 1)}`, title: `Library ${String(index + 1)}`, type: 'movie' as const, contentCount: 1, lastScannedAtMs: 0,
  }));
  controller.selectAllLibraries(sections, null);
  assert.equal(controller.getState().selectedSectionIds.length, 24);
  assert.equal(controller.getState().selectionLimitReached, true);
  controller.clearLibraries(sections);
  assert.equal(controller.getState().selectionLimitReached, false);
  assert.equal(controller.getState().focusIntent, 'plex-dyn-section-library-1');
});

test('library Retry continuations cannot reopen an invalidated or newer setup owner', async () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  const first = deferred<void>();
  const second = deferred<void>();
  const retries = [first, second];
  let call = 0;
  const runtime = {
    getState: () => ({ library: 'ready', preview: 'collapsed', serverId: 'server-1', previewSectionId: null, previewRatingKey: null }),
    retryLibraries: async () => { await retries[call++]?.promise; },
  } as unknown as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'];
  const dispatch = (action: 'libraryRetry' | 'recoveryRetry') => dispatchStagedSetupAction({
    action, controller, runtime,
    channelController: {} as Parameters<typeof dispatchStagedSetupAction>[0]['channelController'],
    sections: [], getSections: () => [], getCurrentPlexError: () => null,
    previewCursor: null, getPreviewRatingKey: () => null, sectionsServerId: () => 'server-1',
    setPreviewCursor: () => undefined, closePreviewMetadata: () => undefined, returnToServer: () => undefined,
    closeSetup: () => undefined, tuneChannel: async () => false, startBlankCustomDraft: () => undefined,
    cancelCustomDraft: () => undefined, cancelCustomDeleteConfirmation: () => undefined,
  });

  const staleLibrary = dispatch('libraryRetry');
  await Promise.resolve();
  controller.invalidateAsync();
  controller.showOwner('preview', 'setup-category-build');
  first.resolve();
  await staleLibrary;
  assert.equal(controller.getState().owner, 'preview');
  assert.equal(controller.getState().focusIntent, 'setup-category-build');

  controller.showRecovery('Libraries are offline.', { originStep: 'library', operation: 'listLibraries', invokerFocusId: 'setup-library-retry' });
  const staleRecovery = dispatch('recoveryRetry');
  await Promise.resolve();
  controller.invalidateAsync();
  second.resolve();
  await staleRecovery;
  assert.equal(controller.getState().owner, 'library');
  assert.equal(controller.getState().focusIntent, 'setup-select-all');
});

test('result Watch ignores invalidation during tune before closing or restoring result', async () => {
  for (const tuned of [true, false]) {
    const controller = createStagedSetupController({ onStateChanged: () => undefined });
    const generation = controller.beginCommit();
    controller.completeCommit(generation, 'append', null, configuredChannelRuntimeState().summary);
    const pendingTune = deferred<boolean>();
    let closeCalls = 0;
    const action = dispatchStagedSetupAction({
      action: 'resultWatch', controller,
      runtime: {} as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'],
      channelController: {} as Parameters<typeof dispatchStagedSetupAction>[0]['channelController'], sections: [],
      previewCursor: null, setPreviewCursor: () => undefined, closePreviewMetadata: () => undefined,
      returnToServer: () => undefined, closeSetup: () => { closeCalls++; }, tuneChannel: async () => pendingTune.promise,
      startBlankCustomDraft: () => undefined, cancelCustomDraft: () => undefined,
      cancelCustomDeleteConfirmation: () => undefined,
    });
    await Promise.resolve();
    controller.invalidateAsync();
    controller.showOwner('preview', 'setup-category-build');
    pendingTune.resolve(tuned);
    await action;
    assert.equal(closeCalls, 0);
    assert.equal(controller.getState().owner, 'preview');
    assert.equal(controller.getState().focusIntent, 'setup-category-build');
  }
});

test('build recovery ignores invalidation during status load before restoring or reopening recovery', async () => {
  for (const errorText of [null, 'Status remains unavailable.']) {
    const controller = createStagedSetupController({ onStateChanged: () => undefined });
    controller.showRecovery('Status unavailable.', { originStep: 'build', operation: 'refreshStatus', invokerFocusId: 'setup-confirm' });
    const pendingStatus = deferred<void>();
    const channelController = {
      loadStatus: async () => pendingStatus.promise,
      getState: () => ({ errorText }),
    } as unknown as Parameters<typeof dispatchStagedSetupAction>[0]['channelController'];
    const action = dispatchStagedSetupAction({
      action: 'recoveryRetry', controller, channelController,
      runtime: {} as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'], sections: [], previewCursor: null,
      setPreviewCursor: () => undefined, closePreviewMetadata: () => undefined, returnToServer: () => undefined,
      closeSetup: () => undefined, tuneChannel: async () => false, startBlankCustomDraft: () => undefined,
      cancelCustomDraft: () => undefined, cancelCustomDeleteConfirmation: () => undefined,
    });
    await Promise.resolve();
    controller.invalidateAsync();
    controller.showOwner('preview', 'setup-category-build');
    pendingStatus.resolve();
    await action;
    assert.equal(controller.getState().owner, 'preview');
    assert.equal(controller.getState().focusIntent, 'setup-category-build');
  }
});

test('expanding preview loads the current cursor before requesting its first live metadata key', async () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  controller.showOwner('preview', 'setup-preview-toggle');
  const calls: string[] = [];
  let preview: 'collapsed' | 'ready' | 'empty' = 'collapsed';
  let sectionId: string | null = null;
  let liveKey: string | null = null;
  const runtime = {
    getState: () => ({ library: 'ready', preview, serverId: 'server-1', previewSectionId: sectionId, previewRatingKey: null }),
    loadPreview: async (id: string) => { calls.push(`items:${id}`); sectionId = id; preview = 'ready'; liveKey = 'rating-live'; },
    loadPreviewMetadata: async (key: string) => { calls.push(`metadata:${key}`); },
  } as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'];
  await dispatchStagedSetupAction({
    action: 'previewToggle', controller, runtime,
    channelController: {} as Parameters<typeof dispatchStagedSetupAction>[0]['channelController'], sections: [],
    previewCursor: 'movies', getPreviewRatingKey: () => liveKey,
    setPreviewCursor: () => undefined, closePreviewMetadata: () => undefined, returnToServer: () => undefined,
    closeSetup: () => undefined, tuneChannel: async () => false, startBlankCustomDraft: () => undefined,
    cancelCustomDraft: () => undefined, cancelCustomDeleteConfirmation: () => undefined,
  });
  assert.deepEqual(calls, ['items:movies', 'metadata:rating-live']);
});

test('cancelled progress blocks repeat Build while its channel commit remains pending', async () => {
  const pendingCommit = deferred<ChannelSetupIpcResult<ChannelSetupSummary>>();
  let commitCalls = 0;
  const committedSectionIds: string[][] = [];
  const channelController = createChannelRuntimeController({
    bridge: legacyChannelBridge({
      getStatus: async () => channelSetupSuccess('status-after-cancel', configuredChannelRuntimeState().summary as ChannelSetupSummary),
      commit: async (request) => {
        commitCalls++;
        committedSectionIds.push([...request.sectionIds]);
        return pendingCommit.promise;
      },
    }),
    onStateChanged: () => undefined,
  });
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  const sections = [
    { id: 'movies', title: 'Movies', type: 'movie' as const, contentCount: 1, lastScannedAtMs: 0 },
    { id: 'shows', title: 'Shows', type: 'show' as const, contentCount: 1, lastScannedAtMs: 0 },
  ];
  controller.toggleLibrary('movies', sections);
  controller.toggleLibrary('shows', sections);
  controller.showOwner('build', 'setup-confirm');
  const dispatch = (action: Parameters<typeof dispatchStagedSetupAction>[0]['action']) => dispatchStagedSetupAction({
    action,
    controller,
    channelController,
    runtime: {} as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'],
    sections,
    previewCursor: 'movies',
    getPreviewRatingKey: () => null,
    setPreviewCursor: () => undefined,
    closePreviewMetadata: () => undefined,
    returnToServer: () => undefined,
    closeSetup: () => undefined,
    tuneChannel: async () => true,
    startBlankCustomDraft: () => undefined,
    cancelCustomDraft: () => undefined,
    cancelCustomDeleteConfirmation: () => undefined,
  });

  const firstBuild = dispatch('buildConfirm');
  assert.equal(controller.getState().owner, 'progress');
  assert.equal(channelController.getState().pending, true);
  await dispatch('progressCancel');
  assert.equal(controller.getState().owner, 'build');
  assert.equal(channelController.getState().pending, true);

  await dispatch('buildConfirm');
  assert.equal(commitCalls, 1);
  assert.deepEqual(committedSectionIds, [['movies', 'shows']]);
  assert.equal(controller.getState().owner, 'build');

  pendingCommit.resolve(channelSetupSuccess('stale-commit', configuredChannelRuntimeState().summary as ChannelSetupSummary));
  await firstBuild;
  assert.equal(controller.getState().owner, 'build');
  assert.equal(channelController.getState().pending, false);
});

test('staged custom editor and delete modal restore exact list invokers', () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  controller.showOwner('setup-custom', 'custom-channel-new');
  controller.openCustomEditor('custom-channel-duplicate-custom-1');
  controller.closeCustomEditor();
  assert.equal(controller.getState().owner, 'setup-custom');
  assert.equal(controller.getState().focusIntent, 'custom-channel-duplicate-custom-1');

  controller.openDeleteConfirmation('custom-1', 'custom-channel-delete-custom-1');
  assert.equal(controller.getState().owner, 'custom-delete-confirm');
  controller.closeDeleteConfirmation('custom-channel-new');
  assert.equal(controller.getState().owner, 'setup-custom');
  assert.equal(controller.getState().focusIntent, 'custom-channel-new');
});

test('visible delete cancel clears custom substate before the next editor Back', async () => {
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  const customController = createCustomChannelController({
    bridge: {} as Parameters<typeof createCustomChannelController>[0]['bridge'],
    onStateChanged: () => undefined,
  });
  controller.showOwner('setup-custom', 'custom-channel-delete-custom-1');
  controller.openDeleteConfirmation('custom-1', 'custom-channel-delete-custom-1');
  await customController.applyAction('requestDeleteChannel', 'custom-1');
  await dispatchStagedSetupAction({
    action: 'customDeleteCancel',
    controller,
    runtime: {} as Parameters<typeof dispatchStagedSetupAction>[0]['runtime'],
    channelController: {} as ReturnType<typeof createChannelRuntimeController>,
    sections: [],
    previewCursor: null,
    getPreviewRatingKey: () => null,
    setPreviewCursor: () => undefined,
    closePreviewMetadata: () => undefined,
    returnToServer: () => undefined,
    closeSetup: () => undefined,
    tuneChannel: async () => false,
    startBlankCustomDraft: () => undefined,
    cancelCustomDraft: () => customController.cancelDraft(),
    cancelCustomDeleteConfirmation: () => customController.cancelDeleteConfirmation(),
  });
  assert.equal(customController.getState().deleteConfirmationChannelId, null);

  controller.openCustomEditor('custom-channel-new');
  await handleStagedSetupBack({
    controller,
    customController,
    plexController: {} as Parameters<typeof handleStagedSetupBack>[0]['plexController'],
    dispatch: async (action) => {
      if (action === 'customCancel') {
        customController.cancelDraft();
        controller.closeCustomEditor();
      }
    },
  });
  assert.equal(controller.getState().owner, 'setup-custom');
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
