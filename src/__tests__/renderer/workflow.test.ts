import test from 'node:test';
import assert from 'node:assert/strict';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
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

test('workflow state starts on the player route with fake program context', () => {
  const state = createWorkflowState();
  const view = getRouteWorkflowView(state);

  assert.deepEqual(state.routeState, { activeRoute: 'player', previousRoute: null });
  assert.equal(state.settingsDraft.launchMode, 'windowed');
  assert.equal(state.channelSetupDraft.activeStepId, 'channels');
  assert.equal(view.route, 'player');
  assert.equal(view.title, 'Player');
  assert.equal(view.currentProgram.channelName, 'Liminal One');
  assert.equal(view.guide.selectedProgram.title, 'The Midnight Archive');
  assert.equal(view.actions.map((action) => action.id).join(','), 'openGuide,openSettings');
});

test('route actions move between existing route ids and carry status text', () => {
  const initial = createWorkflowState();
  const guide = applyWorkflowAction(initial, 'openGuide');
  const guideView = getRouteWorkflowView(guide);

  assert.deepEqual(guide.routeState, { activeRoute: 'guide', previousRoute: 'player' });
  assert.equal(guide.lastActionId, 'openGuide');
  assert.equal(guide.lastActionRoute, 'player');
  assert.equal(guideView.statusText, 'Guide opened from the player preview.');

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
  assert.equal(getRouteWorkflowView(player).statusText, 'Returned to player preview from settings.');
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
  assert.equal(view.settings.playbackMode, 'Fullscreen desktop preview');
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

test('legacy draft setup state stays renderer-local and outside reachable Plex onboarding actions', () => {
  const initial = createWorkflowState('channelSetup');
  const pausedFeatured = applyWorkflowChannelSetupAction(initial, 'toggleFeaturedChannel');
  const withDraft = applyWorkflowChannelSetupAction(pausedFeatured, 'addDraftChannel');
  const review = applyWorkflowChannelSetupAction(withDraft, 'advanceSetupStep');
  const view = getRouteWorkflowView(review);

  assert.deepEqual(review.routeState, initial.routeState);
  assert.equal(view.channelDrafts.length, 4);
  assert.equal(view.channelSetupSummary.enabledChannelCount, 2);
  assert.equal(view.channelSetupSummary.totalBlockCount, 6);
  assert.equal(view.setupSteps.find((step) => step.id === 'review')?.state, 'current');
  assert.deepEqual(view.setupValidationMessages, []);

  const reset = applyWorkflowChannelSetupAction(review, 'resetDraftLineup');
  assert.equal(getRouteWorkflowView(reset).channelDrafts.length, 3);
  assert.deepEqual(getRouteWorkflowView(initial).actions, []);
});

test('EPG actions update only renderer-local guide state', () => {
  const initial = createWorkflowState('guide');
  const nextChannel = applyWorkflowEpgAction(initial, 'nextChannel');
  const later = applyWorkflowEpgAction(nextChannel, 'nextWindow');
  const view = getRouteWorkflowView(later);

  assert.deepEqual(later.routeState, initial.routeState);
  assert.equal(view.guide.windowStartMs, initial.epg.windowStartMs + 30 * 60 * 1000);
  assert.equal(view.guide.selectedProgram.channelId, 'channel-vault');
  assert.equal(view.guide.selectedProgram.title, 'Restored Feature');
});

test('fake workflow view models avoid Plex and player privileged renderer fields', () => {
  const routeIds = ['player', 'guide', 'settings', 'channelSetup'] as const;

  for (const routeId of routeIds) {
    const view = getRouteWorkflowView(createWorkflowState(routeId));
    assert.equal(containsPlexForbiddenRendererField(view), false, routeId);
  }
});
