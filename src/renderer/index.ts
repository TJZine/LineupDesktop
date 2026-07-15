import type { ShellStatusEvent } from '../contracts/shell.js';
import { queryRendererDom, type PlexRuntimeActionId } from './domBindings.js';
import { focusRendererTarget, renderRendererFocus, syncRendererFocusTargets } from './focusDom.js';
import { FocusRegistry, type AppRouteId, type FocusState } from './navigation.js';
import { createPlayerOverlayState, createPlayerOverlayView, type PlayerOverlayActionId } from './overlays.js';
import { renderRouteDom, renderWorkflowDom } from './routeDom.js';
import { mountStaticRendererDom } from './staticDom.js';
import { applySupportBundleExportResult } from './supportBundleExport.js';
import { createPlexRuntimeController } from './plexRuntimeActions.js';
import { resolveChannelSetupLiveSelection } from './channelSetup/liveSelection.js';
import { createChannelRuntimeController } from './channelRuntimeActions.js';
import { createCustomChannelController, type CustomChannelActionId } from './customChannels/controller.js';
import { dispatchCustomChannelAction } from './customChannels/actionDispatch.js';
import { renderCustomChannelWorkspace } from './customChannels/dom.js';
import { readPlexOnboardingState, renderPlexRuntimeDom } from './plexRuntimeDom.js';
import { activateWorkflowRoute, applyWorkflowAction, applyWorkflowEpgAction, applyWorkflowSettingsAction, applyWorkflowSettingsValues, createWorkflowState, getRouteWorkflowView, type EpgActionId, type RouteWorkflowActionId, type SettingsActionId } from './workflow.js';
import { createRendererPresentationFixtures } from './presentationFixtures.js';
import { recordRendererBridgeFailure, summarizeRendererBridgeError } from './rendererBridgeFailures.js';
import { setEpgPresentationState, updateEpgState } from './epg.js';
import { registerRendererActions } from './rendererActionRegistration.js';
import { subscribePlayerBridge } from './playerBridgeSubscription.js';
import { createGuidePresentationPolling } from './guidePresentationPolling.js';
import { dispatchPlexRuntimeAction } from './plexRuntimeActionDispatch.js';
import { initializeProfilePinModal, openProfilePinModal, isProfilePinModalActive, closeProfilePinModal } from './profilePinModal.js';
import type { SettingsSectionId } from './settingsSetup.js';
import { applyOverlayAction as dispatchOverlayAction, selectAudioTrack as dispatchSelectAudioTrack, selectSubtitleTrack as dispatchSelectSubtitleTrack, type PlayerOverlayActionContext } from './playerOverlayActions.js';
import { queryShellDom, renderShellDom } from './shell/shellDom.js';
import { createRendererShellState, type RendererShellState } from './shell/shellState.js';
import { createShellController } from './shell/shellController.js';
import { attachNavigationInputRuntime, createNavigationLifecycle } from './shell/navigationLifecycle.js';
import { createPlexOnboardingFlow } from './onboarding/plexOnboardingFlow.js';
import { handleStagedSetupBack } from './setup/stagedSetupController.js';
import { renderStagedSetupDom } from './setup/stagedSetupDom.js';
import { cleanupSetupRouteLifecycle, clearSetupSourceLifecycle, createSetupComposition } from './setup/setupComposition.js';
import { createSettingsRuntime } from './settings/settingsRuntime.js';
import { createFullscreenTransportCoordinator } from './fullscreenTransport.js';
mountStaticRendererDom();
const dom = queryRendererDom();
const shellDom = queryShellDom();
let fullscreenEnabled = false, shellState: RendererShellState = createRendererShellState();
const fullscreenTransport = createFullscreenTransportCoordinator({
  bridge: window.lineupDesktop.window,
  reconcile: (enabled) => {
    fullscreenEnabled = enabled;
    dom.fullscreenButton?.setAttribute('aria-pressed', String(enabled));
  },
});
const presentationFixtures = createRendererPresentationFixtures();
let workflowState = createWorkflowState('player', presentationFixtures.guide);
let overlayState = createPlayerOverlayState(presentationFixtures.overlays);
let playerSnapshot = presentationFixtures.playerSnapshot;
let activeSettingsCategory: SettingsSectionId = 'appearance', activeSetupStage = 'account';
const focusRegistry = new FocusRegistry(); let focusState: FocusState;
const settingsRuntime = createSettingsRuntime({
  settings: window.lineupDesktop.settings, windowBridge: fullscreenTransport,
  onStateChanged: (state) => {
    workflowState = applyWorkflowSettingsValues(workflowState, state.values);
    document.documentElement.dataset.settingsSaving = String(state.saving); document.documentElement.dataset.settingsErrorCode = state.errorCode ?? '';
    const errorElement = document.querySelector<HTMLElement>('[data-settings-error]');
    if (errorElement) { errorElement.textContent = state.errorMessage ?? ''; errorElement.hidden = state.errorMessage === null; }
    if (!state.loading) renderApp();
  },
});
const overlayActionContext: PlayerOverlayActionContext = {
  getOverlayState: () => overlayState,
  setOverlayState: (state) => { overlayState = state; },
  getPlayerSnapshot: () => playerSnapshot,
  getFocusState: () => focusState,
  setFocusState: (state) => { focusState = state; },
  getFocusRegistry: () => focusRegistry,
  getPresentationFixtures: () => presentationFixtures,
  renderApp,
};
const plexController = createPlexRuntimeController({
  bridge: window.lineupDesktop.plex,
  onStateChanged: () => renderApp(),
  recordRendererEvent: window.lineupDesktop.diagnostics.recordRendererEvent,
});
const channelController = createChannelRuntimeController({
  bridge: window.lineupDesktop.channelSetup,
  onStateChanged: () => renderApp(),
});
const customChannelController = createCustomChannelController({
  bridge: window.lineupDesktop.customChannels,
  onStateChanged: () => renderApp(),
});
let onboardingFlow: ReturnType<typeof createPlexOnboardingFlow>;
const setupComposition = createSetupComposition({
  plexController,
  channelController, customController: customChannelController,
  render: renderApp,
  returnToServer: () => { void onboardingFlow.changeStage('server'); },
  closeSetup: closeStagedSetup,
  tuneChannel: async (channelId) => (await window.lineupDesktop.player.tuneChannel({ channelId })).ok,
  clearDependentActionState: clearDependentChannelActionState,
});
const stagedSetupController = setupComposition.controller;
const applyStagedSetupAction = setupComposition.apply;
onboardingFlow = createPlexOnboardingFlow({
  controller: plexController, documentRef: document,
  getRoute: () => workflowState.routeState.activeRoute, getStage: () => activeSetupStage,
  setStage: (stage) => {
    activeSetupStage = stage;
    if (stage === 'library') {
      const returnRoute = workflowState.lastActionRoute === 'guide' || workflowState.lastActionRoute === 'settings' ? workflowState.lastActionRoute : 'player';
      void setupComposition.enter(returnRoute, returnRoute === 'guide' ? 'guide-setup' : returnRoute === 'settings' ? 'settings-setup' : 'player-settings');
    }
  }, render: renderApp,
});
initializeProfilePinModal({
  getPlexController: () => plexController,
  getFocusState: () => focusState,
  setFocusState: (state) => {
    focusState = state;
  },
  getFocusRegistry: () => focusRegistry,
  renderApp,
  onProfileSelected: () => { void onboardingFlow.advanceToServerSelection(); },
});

syncRendererFocusTargets(focusRegistry, dom);
focusState = focusRegistry.createInitialState(workflowState.routeState.activeRoute);
const shellController = createShellController({
  shell: window.lineupDesktop.shell,
  windowBridge: fullscreenTransport,
  host: window,
  getState: () => shellState,
  setState: (state) => { shellState = state; },
  render: renderApp,
  applyCapabilities: (capabilities) => {
    document.documentElement.dataset.shellMode = capabilities.shellMode;
    focusState = { activeRoute: workflowState.routeState.activeRoute, activeId: null };
    if (dom.capabilitiesElement) dom.capabilitiesElement.textContent = `${capabilities.appName} ${capabilities.appVersion} ${capabilities.shellMode}`;
  },
  restoreFocus: restoreFocusTarget,
});
const navigationLifecycle = createNavigationLifecycle({
  getRoute: () => workflowState.routeState.activeRoute,
  getFocusState: () => focusState,
  setFocusState: (state) => { focusState = state; },
  getShellState: () => shellState,
  setShellState: (state) => { shellState = state; },
  render: renderApp,
  focusRegistry,
  dom,
  onFocusChanged: updateActiveFromFocus,
  scrollFocusedIntoView: scrollFocusedSetupControlIntoView,
  activateRoute,
  isProfileModalActive: isProfilePinModalActive,
  closeProfileModal: () => closeProfilePinModal(),
  handleChannelSetupBack,
  handlePlayerOverlayBack: () => {
    const activeOverlay = createPlayerOverlayView(overlayState, {
      ...presentationFixtures.overlays,
      playerSnapshot,
    }).activeOverlayId;
    if (activeOverlay === null) return false;
    dispatchOverlayAction('closeTopOverlay', overlayActionContext);
    return true;
  },
  dismissInlineError: shellController.dismissFullscreenError,
  requestFullscreen: (acceptedFocusId) => shellController.requestFullscreen(!fullscreenEnabled, acceptedFocusId),
  invalidateFullscreenRequest: shellController.invalidateFullscreenRequest,
  closeWindow: () => window.close(),
});
shellDom.retryStartupButton?.addEventListener('click', () => { void shellController.retryCapabilities(); });
shellDom.blockingExitButton?.addEventListener('click', navigationLifecycle.closeApplication);
shellDom.inlineDismissButton?.addEventListener('click', shellController.dismissFullscreenError);
shellDom.inlineRetryButton?.addEventListener('click', () => { void shellController.retryFullscreen(); });
shellDom.exitCancelButton?.addEventListener('click', navigationLifecycle.cancelExit);
shellDom.exitButton?.addEventListener('click', navigationLifecycle.confirmExit);

const unsubscribeShellStatus = window.lineupDesktop.shell.onStatusChanged(renderStatus);
const playerBridgeSubscription = subscribePlayerBridge({
  player: window.lineupDesktop.player,
  diagnostics: window.lineupDesktop.diagnostics,
  getSnapshot: () => playerSnapshot,
  setSnapshot: (snapshot) => {
    playerSnapshot = snapshot;
  },
  render: renderApp,
});
const guidePresentationPolling = createGuidePresentationPolling({
  guide: window.lineupDesktop.guide,
  host: window,
  getActiveRoute: () => workflowState.routeState.activeRoute,
  getWindowStartMs: () => workflowState.epg.windowStartMs,
  setLoading: () => {
    workflowState = {
      ...workflowState,
      epg: setEpgPresentationState(workflowState.epg, 'loading'),
    };
    renderApp();
  },
  applyPresentation: (normalizedGuidePresentation) => {
    workflowState = {
      ...workflowState,
      guidePresentation: normalizedGuidePresentation,
      epg: updateEpgState(workflowState.epg, normalizedGuidePresentation),
    };
    renderApp();
  },
  handleFailure: handleGuidePresentationFailure,
});
void playerBridgeSubscription.initializeSnapshot();
attachNavigationInputRuntime(navigationLifecycle, {
  host: window,
  root: document.documentElement,
  onBeforeUnload: () => {
    unsubscribeShellStatus();
    playerBridgeSubscription.unsubscribe();
    guidePresentationPolling.stop();
    shellController.cleanup();
    settingsRuntime.cleanup();
    cleanupPlexRuntime('beforeunload');
  },
});

registerRendererActions(dom, document, {
  activateRoute,
  applyRouteAction: (action) => { void applyRouteAction(action); },
  applySettingsAction,
  applySettingsCategory: (category) => {
    activeSettingsCategory = category as SettingsSectionId;
    renderApp();
  },
  applySetupStage: (stage) => { void onboardingFlow.changeStage(stage); },
  applyStagedSetupAction: (action) => { void applyStagedSetupAction(action); },
  applyChannelSetupAction: (action) => setupComposition.setBuildMode(action === 'selectReplaceBuildMode' ? 'replace' : 'append'),
  applyChannelCommitAction: (action) => {
    stagedSetupController.setBuildMode(action === 'append' ? 'append' : 'replace');
    void applyStagedSetupAction('buildConfirm');
  },
  applyEpgAction,
  applyOverlayAction,
  applyPlexRuntimeAction: (action) => { void applyPlexRuntimeAction(action); },
  applyCustomChannelAction: (action, detail) => { void applyCustomChannelAction(action, detail); },
  setPlexHomeUserPin: (value) => plexController.setHomeUserPin(value),
  setPlexSearchQuery: (value) => plexController.setSearchQuery(value),
  setCustomChannelName: (value) => customChannelController.setDraftName(value),
  setCustomChannelNumber: (value) => customChannelController.setDraftNumber(value),
  setCustomChannelSearchQuery: (value) => customChannelController.setSearchQuery(value),
  selectPlexHomeUser: (homeUserId) => {
    if (plexController.getState().pending.switchHomeUser) return;
    clearChannelSetupActionStateForSourceChange();
    const state = plexController.getState();
    const user = state.snapshot?.auth.homeUsers.find((u) => u.id === homeUserId);
    onboardingFlow.rememberProfileFocus(focusState.activeId);
    if (user?.protected) {
      openProfilePinModal(user);
    } else void selectPlexHomeUser(homeUserId);
  },
  selectPlexServer: (serverId) => {
    if (plexController.getState().pending.selectServer) return;
    clearChannelSetupActionStateForSourceChange();
    void onboardingFlow.selectServer(serverId);
  },
  selectPlexSection: (sectionId) => {
    void setupComposition.selectSection(sectionId);
  },
  openPlexMetadata: (ratingKey) => { void setupComposition.runtime.loadPreviewMetadata(ratingKey); },
  focusElement: focusRendererElement,
  toggleFullscreen: () => { void shellController.requestFullscreen(!fullscreenEnabled, focusState.activeId ?? 'player-fullscreen'); },
  selectAudioTrack: (trackId) => { void dispatchSelectAudioTrack(trackId, overlayActionContext); },
  selectSubtitleTrack: (trackId) => { void dispatchSelectSubtitleTrack(trackId, overlayActionContext); },
});

document.documentElement.dataset.activeRoute = workflowState.routeState.activeRoute;
void settingsRuntime.initialize().then(() => shellController.start()).finally(() => {
  document.documentElement.dataset.shellBoot = 'ready';
});
void plexController.loadSnapshot().then(() => {
  if (plexController.getState().snapshot?.auth.state === 'signed-in') void plexController.getHomeUsers();
});
void channelController.loadStatus();
void customChannelController.loadSnapshot();
if (workflowState.routeState.activeRoute === 'guide') {
  guidePresentationPolling.start();
}

function renderStatus(event: ShellStatusEvent): void {
  if (dom.statusElement) {
    dom.statusElement.textContent = `${event.status} ${new Date(event.timestampMs).toISOString()}`;
  }
}

function activateRoute(route: AppRouteId): void {
  const previousRoute = workflowState.routeState.activeRoute;
  if (previousRoute === 'channelSetup' && route !== 'channelSetup') {
    plexController.invalidateOnboardingOperations();
  }
  workflowState = activateWorkflowRoute(workflowState, route);
  navigationLifecycle?.routeChanged(previousRoute, workflowState.routeState.activeRoute);
  cleanupPlexRuntimeForRouteChange(previousRoute, workflowState.routeState.activeRoute);
  guidePresentationPolling.reconcile(previousRoute, workflowState.routeState.activeRoute);
  focusState = focusRegistry.focusRoute(focusState, route).state;
  renderApp();
}

async function applyRouteAction(action: RouteWorkflowActionId): Promise<void> {
  const previousRoute = workflowState.routeState.activeRoute;
  if (action === 'resumePlayer' && previousRoute === 'guide') {
    await tuneGuideSelectedChannel();
    return;
  }
  const nextWorkflowState = applyWorkflowAction(workflowState, action);
  const nextRoute = nextWorkflowState.routeState.activeRoute;
  if (previousRoute === 'channelSetup' && nextRoute !== 'channelSetup') {
    plexController.invalidateOnboardingOperations();
  }
  workflowState = nextWorkflowState;
  if (previousRoute !== nextRoute) {
    cleanupPlexRuntimeForRouteChange(previousRoute, nextRoute);
    guidePresentationPolling.reconcile(previousRoute, nextRoute);
    focusState = focusRegistry.focusRoute(focusState, nextRoute).state;
  }
  renderApp();
}

function applySettingsAction(action: SettingsActionId): void {
  if (action === 'exportSupportBundle') {
    workflowState = applyWorkflowSettingsAction(workflowState, action);
    renderApp();
    void exportSupportBundle();
    return;
  }
  void settingsRuntime.applyAction(action);
}

function closeStagedSetup(): void {
  const state = stagedSetupController.getState();
  activateRoute(state.returnRoute);
  restoreFocusTarget(state.returnFocusId);
}

function applyEpgAction(action: EpgActionId): void {
  const previousWindowStartMs = workflowState.epg.windowStartMs;
  workflowState = applyWorkflowEpgAction(workflowState, action);
  renderApp();
  if (workflowState.epg.windowStartMs !== previousWindowStartMs) {
    void guidePresentationPolling.refresh('epg-window-change', { showLoading: true });
  }
}

function applyOverlayAction(action: PlayerOverlayActionId): void {
  dispatchOverlayAction(action, overlayActionContext);
}

async function exportSupportBundle(): Promise<void> {
  const requestId = `support-bundle-${Date.now()}`;
  void window.lineupDesktop.diagnostics.recordRendererEvent({
    requestId,
    event: {
      surface: 'renderer',
      category: 'support-bundle-export',
      severity: 'info',
      operation: 'support-bundle.export.click',
      message: 'Support bundle export requested from settings.',
      context: { route: workflowState.routeState.activeRoute },
    },
  }).catch(() => undefined);

  workflowState = await applySupportBundleExportResult(
    () => workflowState,
    () => window.lineupDesktop.diagnostics.exportSupportBundle(),
  );
  renderApp();
}

async function applyPlexRuntimeAction(action: PlexRuntimeActionId): Promise<void> {
  if (action === 'cancelPin') onboardingFlow.setFocusIntent('btn-auth-request');
  if (action === 'refreshServers') {
    await onboardingFlow.refreshServerSelection();
    return;
  }
  await dispatchPlexRuntimeAction(action, {
    controller: plexController,
    clearSourceActionState: clearChannelSetupActionStateForSourceChange,
  });
}

async function applyCustomChannelAction(
  action: CustomChannelActionId,
  detail: string | undefined,
): Promise<void> {
  await dispatchCustomChannelAction({
    action,
    detail,
    selectedSourceId: resolveLiveSelectedPlexSectionId(plexController.getState()),
    controller: customChannelController,
    refreshChannels: () => { void channelController.loadStatus(); },
    refreshGuide: () => { void guidePresentationPolling.refresh('custom-channel-change', { showLoading: false }); },
    render: renderApp,
    flow: {
      openEditor: (focusId) => stagedSetupController.openCustomEditor(focusId),
      closeEditor: (channelId) => stagedSetupController.closeCustomEditor(channelId),
      openDelete: (channelId, focusId) => stagedSetupController.openDeleteConfirmation(channelId, focusId),
      closeDelete: (focusId) => stagedSetupController.closeDeleteConfirmation(focusId),
      restoreDeleteFocus: (focusId) => stagedSetupController.showOwner('custom-delete-confirm', focusId),
      restoreListFocus: (focusId) => stagedSetupController.showOwner(stagedSetupController.getState().customParentOwner, focusId),
    },
  });
}

async function tuneGuideSelectedChannel(): Promise<void> {
  const guideChannelId = workflowState.epg.selectedChannelId;
  if (guideChannelId.length === 0) {
    workflowState = {
      ...workflowState,
      epg: setEpgPresentationState(workflowState.epg, 'error'),
    };
    renderApp();
    return;
  }

  let result: Awaited<ReturnType<typeof window.lineupDesktop.player.tuneChannel>>;
  try {
    result = await window.lineupDesktop.player.tuneChannel({ channelId: guideChannelId });
  } catch (error: unknown) {
    handleGuideTuneFailure(guideChannelId, summarizeRendererBridgeError(error));
    return;
  }
  if (result.ok) {
    const previousRoute = workflowState.routeState.activeRoute;
    const nextWorkflowState = applyWorkflowAction(workflowState, 'resumePlayer');
    const nextRoute = nextWorkflowState.routeState.activeRoute;
    if (previousRoute === 'channelSetup' && nextRoute !== 'channelSetup') {
      plexController.invalidateOnboardingOperations();
    }
    workflowState = nextWorkflowState;
    cleanupPlexRuntimeForRouteChange(previousRoute, nextRoute);
    guidePresentationPolling.reconcile(previousRoute, nextRoute);
    if (nextRoute === 'guide') {
      return;
    }
    focusState = focusRegistry.focusRoute(focusState, nextRoute).state;
    renderApp();
    return;
  }

  handleGuideTuneFailure(guideChannelId, result.error.message);
}

function handleGuidePresentationFailure(source: string, message: string): void {
  workflowState = {
    ...workflowState,
    epg: setEpgPresentationState(workflowState.epg, 'error'),
  };
  renderApp();
  recordRendererBridgeFailure(window.lineupDesktop.diagnostics.recordRendererEvent, 'guide.getPresentation', message, {
    route: workflowState.routeState.activeRoute,
    source,
  });
}

function handleGuideTuneFailure(channelId: string, message: string): void {
  workflowState = {
    ...workflowState,
    epg: setEpgPresentationState(workflowState.epg, 'error'),
  };
  renderApp();
  recordRendererBridgeFailure(window.lineupDesktop.diagnostics.recordRendererEvent, 'player.tuneChannel', message, {
    channelId,
    route: 'guide',
  });
}

async function handlePlexBack(): Promise<boolean> {
  const before = readLiveSetupSourceSignature();
  const handled = await plexController.handleBack();
  if (handled && before !== readLiveSetupSourceSignature()) {
    clearChannelSetupActionStateForSourceChange();
  }
  return handled;
}

async function handleChannelSetupBack(): Promise<boolean> {
  const onboardingState = readPlexOnboardingState(
    plexController.getState(),
    activeSetupStage,
    isProfilePinModalActive(),
  );
  if (onboardingState === null) {
    return handleStagedSetupBack({
      controller: stagedSetupController,
      customController: customChannelController,
      plexController,
      dispatch: applyStagedSetupAction,
    });
  }
  if (onboardingState === 'auth-link-code' || onboardingState === 'profile-select') return true;
  if (onboardingState === 'server-select' || onboardingState === 'server-error') {
    onboardingFlow.returnToProfileSelection();
    return true;
  }
  if (customChannelController.handleBack()) {
    renderApp();
    scrollFocusedSetupControlIntoView();
    return true;
  }
  if (onboardingState === 'auth-waiting' || onboardingState === 'auth-error') {
    onboardingFlow.setFocusIntent('btn-auth-request');
  }
  if (await handlePlexBack()) {
    renderApp();
    scrollFocusedSetupControlIntoView();
    return true;
  }
  return false;
}
function clearChannelSetupActionStateForSourceChange(): void {
  clearSetupSourceLifecycle({ composition: setupComposition, channelController, customController: customChannelController }, activeSetupStage === 'library' && stagedSetupController.getState().owner === 'library');
}

function clearDependentChannelActionState(): void {
  channelController.clearActionState();
  customChannelController.invalidateOperations();
  customChannelController.clearMediaForSourceChange();
}

function readLiveSetupSourceSignature(): string {
  const state = plexController.getState();
  return [
    state.snapshot?.auth.profile?.accountId ?? '',
    state.selectedServerId ?? '',
    state.selectedSectionId ?? '',
  ].join('|');
}

function cleanupPlexRuntimeForRouteChange(previousRoute: AppRouteId, nextRoute: AppRouteId): void {
  if (previousRoute === 'channelSetup' && nextRoute !== 'channelSetup') {
    cleanupPlexRuntime('route-change');
  }
}

function cleanupPlexRuntime(reason: 'beforeunload' | 'route-change'): void {
  cleanupSetupRouteLifecycle({ composition: setupComposition, customController: customChannelController });
  if (isProfilePinModalActive()) {
    closeProfilePinModal({ refocus: false });
  }
  void plexController.cleanup().catch((error: unknown) => {
    const errorName = error instanceof Error ? error.name : typeof error;
    void window.lineupDesktop.diagnostics.recordRendererEvent({
      requestId: `plex-cleanup-${Date.now()}`,
      event: {
        surface: 'renderer',
        category: 'ipc',
        severity: 'warning',
        operation: 'plex.cleanup',
        message: 'Plex cleanup failed.',
        context: { reason, errorName },
      },
    }).catch(() => undefined);
  });
}

function renderApp(): void {
  const plexState = plexController.getState();
  const liveSelection = resolveChannelSetupLiveSelection(plexState);
  renderRouteDom(workflowState, dom, channelController.getState(), liveSelection);
  renderWorkflowDom(
    workflowState,
    overlayState,
    playerSnapshot,
    dom,
    channelController.getState(),
    liveSelection,
    presentationFixtures.overlays,
    activeSettingsCategory,
    activeSetupStage,
  );
  renderPlexRuntimeDom(plexState, dom, activeSetupStage, isProfilePinModalActive(), stagedSetupController.getState().selectedSectionIds, workflowState.settingsDraft.previewBadgesEnabled);
  renderCustomChannelWorkspace(customChannelController.getState(), dom);
  renderStagedSetupDom({
    state: stagedSetupController.getState(),
    runtimeState: setupComposition.runtime.getState(),
    view: getRouteWorkflowView(workflowState, channelController.getState(), liveSelection),
    plexState,
    customState: customChannelController.getState(),
    channelState: channelController.getState(),
    dom,
  });
  renderShellDom(shellState, shellDom, dom.screens);
  syncRendererFocusTargets(focusRegistry, dom);
  if (workflowState.routeState.activeRoute === 'channelSetup') {
    focusState = onboardingFlow.applyFocusIntent(focusRegistry, focusState); focusState = stagedSetupController.applyFocusIntent(focusRegistry, focusState);
  }
  if (focusState.activeId !== null) {
    focusState = focusRegistry.focusTarget(focusState, focusState.activeId).state;
  }
  renderRendererFocus(focusState, dom);
  scrollFocusedSetupControlIntoView();
}
async function selectPlexHomeUser(homeUserId: string): Promise<void> {
  await plexController.switchHomeUser(homeUserId);
  if (!plexController.getState().pending.switchHomeUser && plexController.getState().errorText === null) {
    void onboardingFlow.advanceToServerSelection();
  }
}

function restoreFocusTarget(focusId: string): void {
  syncRendererFocusTargets(focusRegistry, dom);
  focusState = focusRegistry.focusTarget(focusState, focusId).state;
  renderRendererFocus(focusState, dom);
}

function focusRendererElement(element: HTMLElement): void {
  const focusId = element.dataset.focusId;
  if (focusId !== undefined) {
    focusState = focusRendererTarget(focusRegistry, focusState, focusId, dom);
    updateActiveFromFocus(focusId);
    scrollFocusedSetupControlIntoView();
  }
}

function updateActiveFromFocus(focusId: string | null): void {
  if (focusId === 'settings-category-appearance' && activeSettingsCategory !== 'appearance') {
    activeSettingsCategory = 'appearance';
    renderApp();
    return;
  }
  if (focusId === 'settings-category-guide' && activeSettingsCategory !== 'guide') {
    activeSettingsCategory = 'guide';
    renderApp();
    return;
  }
  if (focusId === 'settings-category-recovery' && activeSettingsCategory !== 'recovery') {
    activeSettingsCategory = 'recovery';
    renderApp();
    return;
  }
}

function scrollFocusedSetupControlIntoView(): void {
  if (workflowState.routeState.activeRoute !== 'channelSetup' || focusState.activeId === null) {
    return;
  }
  const activeElement = document.querySelector<HTMLElement>(
    `[data-focus-id="${CSS.escape(focusState.activeId)}"]`,
  );
  activeElement?.scrollIntoView({ block: 'nearest', inline: 'nearest' });
}

function resolveLiveSelectedPlexSectionId(
  plexState: ReturnType<typeof plexController.getState>,
): string | null {
  return resolveChannelSetupLiveSelection(plexState)?.id ?? null;
}
