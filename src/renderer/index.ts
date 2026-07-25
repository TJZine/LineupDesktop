import type { ShellStatusEvent } from '../contracts/shell.js';
import { queryRendererDom, type PlexRuntimeActionId } from './domBindings.js';
import { focusRendererTarget, renderRendererFocus, syncRendererFocusTargets } from './focusDom.js';
import { FocusRegistry, type AppRouteId, type FocusState } from './navigation.js';
import { createPlayerOverlayState, type PlayerOverlayActionId } from './overlays.js';
import {
  renderChannelSetupResult,
  renderRouteDom,
  renderWorkflowDom,
} from './routeDom.js';
import { mountStaticRendererDom } from './staticDom.js';
import { applySupportBundleExportResult } from './supportBundleExport.js';
import { createPlexRuntimeController } from './plexRuntimeActions.js';
import { resolveChannelSetupLiveSelection } from './channelSetup/liveSelection.js';
import { createChannelRuntimeController } from './channelRuntimeActions.js';
import {
  projectChannelBuildCancellation as projectChannelBuildCancellationState,
  type ChannelRuntimeRendererState,
} from './channelRuntimeState.js';
import { createCustomChannelController, type CustomChannelActionId } from './customChannels/controller.js';
import { dispatchCustomChannelAction } from './customChannels/actionDispatch.js';
import { renderCustomChannelWorkspace } from './customChannels/dom.js';
import { readPlexOnboardingState, renderPlexRuntimeDom } from './plexRuntimeDom.js';
import { activateWorkflowRoute, applyWorkflowAction, applyWorkflowEpgAction, applyWorkflowEpgDirection, applyWorkflowSettingsAction, applyWorkflowSettingsValues, createWorkflowState, getRouteWorkflowView, selectWorkflowEpgProgram, type EpgActionId, type RouteWorkflowActionId, type SettingsActionId } from './workflow.js';
import { createEmptyPlayerSnapshot, createPlayerOverlayPresentation } from './playerOverlayPresentation.js';
import { createPlayerOverlayController } from './playerOverlayController.js';
import { recordRendererBridgeFailure } from './rendererBridgeFailures.js';
import { findEpgProgramCell, setEpgPresentationState, setEpgTuneError, updateEpgState } from './epg.js';
import { registerRendererActions, type GuideActionId, type GuideProgramActionTarget } from './rendererActionRegistration.js';
import { subscribePlayerBridge } from './playerBridgeSubscription.js';
import { createGuidePresentationPolling } from './guidePresentationPolling.js';
import { dispatchPlexRuntimeAction } from './plexRuntimeActionDispatch.js';
import { initializeProfilePinModal, openProfilePinModal, isProfilePinModalActive, closeProfilePinModal } from './profilePinModal.js';
import type { SettingsSectionId } from './settingsSetup.js';
import { queryShellDom, renderShellDom } from './shell/shellDom.js';
import { createRendererShellState, type RendererShellState } from './shell/shellState.js';
import { createShellController } from './shell/shellController.js';
import { attachNavigationInputRuntime, createNavigationLifecycle } from './shell/navigationLifecycle.js';
import {
  createPlexOnboardingFlow,
  resolveChannelSetupEntryStage,
  resolveInitialChannelSetupStage,
} from './onboarding/plexOnboardingFlow.js';
import { handleStagedSetupBack } from './setup/stagedSetupController.js';
import { renderStagedSetupDom } from './setup/stagedSetupDom.js';
import { cleanupSetupRouteLifecycle, clearSetupSourceLifecycle, createSetupComposition } from './setup/setupComposition.js';
import { createSettingsRuntime } from './settings/settingsRuntime.js';
import { createFullscreenTransportCoordinator } from './fullscreenTransport.js';
import { createGuideTuneController, type GuideTuneTarget } from './guideTuneController.js';
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
let workflowState = createWorkflowState('player');
let overlayState = createPlayerOverlayState();
let playerSnapshot = createEmptyPlayerSnapshot();
let activeSettingsCategory: SettingsSectionId = 'appearance', activeSetupStage = 'account';
let pendingGuideFocusId: string | null = null;
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
      void setupComposition.enter(returnRoute, returnRoute === 'guide' ? 'guide-state-setup' : returnRoute === 'settings' ? 'settings-setup' : 'player-settings');
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
let guidePresentationPolling: ReturnType<typeof createGuidePresentationPolling>;
const playerOverlayController = createPlayerOverlayController({
  player: window.lineupDesktop.player,
  host: window,
  getState: () => overlayState,
  setState: (state) => { overlayState = state; },
  getPresentation: getPlayerOverlayPresentation,
  render: renderApp,
  focus: (focusId) => {
    if (focusId === null) { focusState = { activeRoute: 'player', activeId: null }; dom.playerPresentationElement?.focus(); return; }
    restoreFocusTarget(focusId);
  },
  openGuide: () => activateRoute('guide'),
  refreshChannelStatus: () => channelController.loadStatus(),
  refreshGuidePresentation: () => guidePresentationPolling.refresh('player-tune-success', { showLoading: false, allowPlayerRoute: true }),
  recordDiagnostic: (operation, message) => recordRendererBridgeFailure(window.lineupDesktop.diagnostics.recordRendererEvent, 'player.dispatch', message, { operation, route: workflowState.routeState.activeRoute }),
});
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
  handleGuideDirection,
  handlePlayerInput: (input) => playerOverlayController.handleInput(input),
  activateRoute,
  isProfileModalActive: isProfilePinModalActive,
  closeProfileModal: () => closeProfilePinModal(),
  handleChannelSetupBack,
  handlePlayerOverlayBack: playerOverlayController.closeTop,
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
  onSnapshot: playerOverlayController.reconcileSnapshot,
  onEvent: playerOverlayController.handlePlayerEvent,
  render: renderApp,
});
guidePresentationPolling = createGuidePresentationPolling({
  guide: window.lineupDesktop.guide,
  host: window,
  getActiveRoute: () => workflowState.routeState.activeRoute,
  getWindowStartMs: () => workflowState.epg.windowStartMs,
  setLoading: (generation) => {
    retainGuideProgramFocusIntent();
    workflowState = {
      ...workflowState,
      epg: setEpgPresentationState(workflowState.epg, 'loading', generation),
    };
    renderApp();
  },
  applyPresentation: (normalizedGuidePresentation, generation) => {
    const restoreProgramFocus = retainGuideProgramFocusIntent();
    workflowState = {
      ...workflowState,
      guidePresentation: normalizedGuidePresentation,
      epg: updateEpgState(workflowState.epg, normalizedGuidePresentation, generation),
    };
    if (restoreProgramFocus) {
      pendingGuideFocusId = getRouteWorkflowView(workflowState).guide.selectedProgram?.focusId ?? null;
    }
    renderApp();
    restorePendingGuideFocus();
  },
  applyPlayerPresentation: (normalizedGuidePresentation) => {
    workflowState = { ...workflowState, guidePresentation: normalizedGuidePresentation };
    renderApp();
  },
  handlePlayerFailure: (source, message) => recordRendererBridgeFailure(
    window.lineupDesktop.diagnostics.recordRendererEvent,
    'guide.getPresentation',
    message,
    { route: 'player', source },
  ),
  handleFailure: handleGuidePresentationFailure,
});
const guideTuneController = createGuideTuneController({
  player: window.lineupDesktop.player,
  getActiveRoute: () => workflowState.routeState.activeRoute,
  getPresentationGeneration: () => workflowState.epg.presentationGeneration,
  getNowMs: () => getRouteWorkflowView(workflowState).guide.nowMs,
  findProgram: (channelId, programId) => findEpgProgramCell(
    workflowState.epg,
    workflowState.guidePresentation,
    channelId,
    programId,
  ),
  onPendingChanged: () => renderApp(),
  onAccepted: acceptGuideTune,
  onFailure: handleGuideTuneFailure,
});
void playerBridgeSubscription.initializeSnapshot();
attachNavigationInputRuntime(navigationLifecycle, {
  host: window,
  root: document.documentElement,
  onBeforeUnload: () => {
    unsubscribeShellStatus();
    playerBridgeSubscription.unsubscribe();
    guidePresentationPolling.stop();
    guideTuneController.stop();
    playerOverlayController.dispose();
    shellController.cleanup();
    settingsRuntime.cleanup();
    void channelController.shutdown();
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
  applyEpgAction,
  applyGuideAction,
  focusGuideProgramFromPointer,
  activateGuideProgram,
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
  selectAudioTrack: (trackId, focusId) => { void playerOverlayController.selectTrack('audio', trackId, focusId); },
  selectSubtitleTrack: (trackId, focusId) => { void playerOverlayController.selectTrack('subtitle', trackId, focusId); },
  tuneOverlayChannel: (channelId) => { playerOverlayController.activateMiniGuideChannel(channelId); },
});

document.documentElement.dataset.activeRoute = workflowState.routeState.activeRoute;
void settingsRuntime.initialize().then(() => shellController.start()).finally(() => {
  document.documentElement.dataset.shellBoot = 'ready';
});
const initialPlexLoad = plexController.loadSnapshot().then(async () => {
  if (plexController.getState().snapshot?.auth.state === 'signed-in') {
    await plexController.getHomeUsers();
  }
});
const initialChannelLoad = channelController.loadStatus();
void Promise.allSettled([initialPlexLoad, initialChannelLoad]).then(() => {
  if (workflowState.routeState.activeRoute !== 'player') return;
  const stage = resolveInitialChannelSetupStage(
    plexController.getState(),
    channelController.getState().summary,
  );
  if (stage === null) return;
  activateRoute('channelSetup');
});
guidePresentationPolling.start();
void customChannelController.loadSnapshot();

function renderStatus(event: ShellStatusEvent): void {
  if (dom.statusElement) {
    dom.statusElement.textContent = `${event.status} ${new Date(event.timestampMs).toISOString()}`;
  }
}

function activateRoute(route: AppRouteId): void {
  const previousRoute = workflowState.routeState.activeRoute;
  if (previousRoute === 'player' && route !== 'player') playerOverlayController.routeLeave();
  if (previousRoute === 'channelSetup' && route !== 'channelSetup') {
    plexController.invalidateOnboardingOperations();
  }
  workflowState = activateWorkflowRoute(workflowState, route);
  navigationLifecycle?.routeChanged(previousRoute, workflowState.routeState.activeRoute);
  cleanupPlexRuntimeForRouteChange(previousRoute, workflowState.routeState.activeRoute);
  if (previousRoute === 'guide' && workflowState.routeState.activeRoute !== 'guide') {
    guideTuneController.stop();
    pendingGuideFocusId = null;
  }
  guidePresentationPolling.reconcile(previousRoute, workflowState.routeState.activeRoute);
  focusState = focusRegistry.focusRoute(focusState, route).state;
  renderApp();
  if (previousRoute !== route && route === 'channelSetup') {
    void onboardingFlow.changeStage(resolveChannelSetupEntryStage(plexController.getState()));
  }
}

async function applyRouteAction(action: RouteWorkflowActionId): Promise<void> {
  if (action === 'openGuide') {
    await navigationLifecycle.handleInput('guide');
    return;
  }
  const previousRoute = workflowState.routeState.activeRoute;
  const nextWorkflowState = applyWorkflowAction(workflowState, action);
  const nextRoute = nextWorkflowState.routeState.activeRoute;
  if (previousRoute === 'channelSetup' && nextRoute !== 'channelSetup') {
    plexController.invalidateOnboardingOperations();
  }
  workflowState = nextWorkflowState;
  if (previousRoute !== nextRoute) {
    if (previousRoute === 'player' && nextRoute !== 'player') playerOverlayController.routeLeave();
    cleanupPlexRuntimeForRouteChange(previousRoute, nextRoute);
    if (previousRoute === 'guide' && nextRoute !== 'guide') guideTuneController.stop();
    guidePresentationPolling.reconcile(previousRoute, nextRoute);
    focusState = focusRegistry.focusRoute(focusState, nextRoute).state;
  }
  renderApp();
  if (previousRoute !== nextRoute && nextRoute === 'channelSetup') {
    void onboardingFlow.changeStage(resolveChannelSetupEntryStage(plexController.getState()));
  }
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
  if (state.returnRoute === 'guide') pendingGuideFocusId = state.returnFocusId;
  activateRoute(state.returnRoute);
  if (state.returnRoute !== 'guide') restoreFocusTarget(state.returnFocusId);
}

function applyEpgAction(action: EpgActionId): void {
  const previousWindowStartMs = workflowState.epg.windowStartMs;
  workflowState = applyWorkflowEpgAction(workflowState, action);
  renderApp();
  if (workflowState.epg.windowStartMs !== previousWindowStartMs) {
    void guidePresentationPolling.refresh('epg-window-change', { showLoading: true });
  }
}

function handleGuideDirection(direction: 'up' | 'down' | 'left' | 'right'): boolean {
  if (workflowState.routeState.activeRoute !== 'guide' || !focusState.activeId?.startsWith('guide-program-')) {
    return false;
  }
  const movement = applyWorkflowEpgDirection(workflowState, direction);
  if (!movement.result.handled) return false;
  workflowState = movement.workflowState;
  renderApp();
  if (movement.result.windowChanged) {
    void guidePresentationPolling.refresh('epg-window-change', { showLoading: true });
  } else {
    const selectedFocusId = getRouteWorkflowView(workflowState).guide.selectedProgram?.focusId;
    if (selectedFocusId !== undefined) restoreFocusTarget(selectedFocusId);
  }
  return true;
}

function applyGuideAction(action: GuideActionId): void {
  switch (action) {
    case 'back':
      void navigationLifecycle.handleInput('back');
      return;
    case 'setup':
      void applyRouteAction('openChannelSetup');
      return;
    case 'refresh':
    case 'retry':
      void guidePresentationPolling.refresh(`guide-${action}`, { showLoading: true });
  }
}

function activateGuideProgram(target: GuideProgramActionTarget): void {
  if (focusState.activeId !== target.focusId) {
    focusRendererElement(target.element);
    return;
  }
  void guideTuneController.activate(target);
}

function focusGuideProgramFromPointer(target: GuideProgramActionTarget): boolean {
  if (focusState.activeId === target.focusId) return false;
  focusRendererElement(target.element);
  return true;
}

function updateGuideTunePendingDom(target: GuideTuneTarget | null): void {
  for (const cell of Array.from(document.querySelectorAll<HTMLButtonElement>('[data-guide-program-action]'))) {
    const pending = target !== null && cell.dataset.focusId === target.focusId;
    if (pending) {
      cell.setAttribute('aria-busy', 'true');
      cell.setAttribute('aria-disabled', 'true');
    } else {
      cell.removeAttribute('aria-busy');
      cell.removeAttribute('aria-disabled');
    }
  }
}

function acceptGuideTune(_target: GuideTuneTarget): void {
  if (workflowState.routeState.activeRoute !== 'guide') return;
  const previousRoute = workflowState.routeState.activeRoute;
  workflowState = activateWorkflowRoute(workflowState, 'player');
  navigationLifecycle.routeChanged(previousRoute, 'player');
  guidePresentationPolling.reconcile(previousRoute, 'player');
  guideTuneController.stop();
  focusState = { activeRoute: 'player', activeId: null };
  renderApp();
}

function applyOverlayAction(action: PlayerOverlayActionId): void {
  switch (action) {
    case 'openOsd': playerOverlayController.requestOsd(); return;
    case 'openNowPlaying': playerOverlayController.requestNowPlaying(); return;
    case 'openMiniGuide': playerOverlayController.requestMiniGuide(); return;
    case 'openAudioOptions': playerOverlayController.openOptions('audio'); return;
    case 'openSubtitleOptions': playerOverlayController.openOptions('subtitle'); return;
    case 'retryPlayer': playerOverlayController.retry(); return;
    case 'miniGuidePrevious': playerOverlayController.handleInput('up'); return;
    case 'miniGuideNext': playerOverlayController.handleInput('down'); return;
    case 'miniGuidePagePrevious': playerOverlayController.handleInput('pageUp'); return;
    case 'miniGuidePageNext': playerOverlayController.handleInput('pageDown'); return;
    case 'closeTopOverlay': playerOverlayController.closeTop();
  }
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

function handleGuidePresentationFailure(source: string, message: string, generation: number): void {
  workflowState = {
    ...workflowState,
    epg: setEpgPresentationState(workflowState.epg, 'error', generation),
  };
  renderApp();
  recordRendererBridgeFailure(window.lineupDesktop.diagnostics.recordRendererEvent, 'guide.getPresentation', message, {
    route: workflowState.routeState.activeRoute,
    source,
  });
}

function handleGuideTuneFailure(target: GuideTuneTarget, message: string): void {
  workflowState = {
    ...workflowState,
    epg: setEpgTuneError(workflowState.epg, message),
  };
  renderApp();
  restoreFocusTarget(target.focusId);
  recordRendererBridgeFailure(window.lineupDesktop.diagnostics.recordRendererEvent, 'player.tuneChannel', message, {
    channelId: target.channelId,
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
    getPlayerOverlayPresentation(),
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
  renderChannelSetupResult(dom, stagedSetupController.getState().result);
  projectChannelBuildCancellation(channelController.getState());
  renderShellDom(shellState, shellDom, dom.screens);
  syncRendererFocusTargets(focusRegistry, dom);
  if (workflowState.routeState.activeRoute === 'channelSetup') {
    focusState = onboardingFlow.applyFocusIntent(focusRegistry, focusState); focusState = stagedSetupController.applyFocusIntent(focusRegistry, focusState);
  }
  if (focusState.activeId !== null) {
    focusState = focusRegistry.focusTarget(focusState, focusState.activeId).state;
  }
  renderRendererFocus(focusState, dom);
  updateGuideTunePendingDom(guideTuneController.getPendingTarget());
  scrollFocusedSetupControlIntoView();
}

function projectChannelBuildCancellation(state: ChannelRuntimeRendererState): void {
  const cancel = document.querySelector<HTMLButtonElement>(
    '[data-focus-id="setup-progress-cancel"]',
  );
  const projection = projectChannelBuildCancellationState(state);
  if (cancel !== null) {
    cancel.hidden = !projection.visible;
    cancel.disabled = !projection.enabled;
    cancel.setAttribute('aria-disabled', String(!projection.enabled));
    cancel.textContent = projection.label;
  }
  const status = document.querySelector<HTMLElement>(
    '[data-channel-operation-status]',
  );
  if (status !== null) status.textContent = state.statusText;
}

function getPlayerOverlayPresentation() {
  return createPlayerOverlayPresentation({
    playerSnapshot,
    channelSummary: channelController.getState().summary,
    guidePresentation: workflowState.guidePresentation,
  });
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

function restorePendingGuideFocus(): void {
  if (pendingGuideFocusId === null || workflowState.routeState.activeRoute !== 'guide') return;
  const focusId = pendingGuideFocusId;
  if (document.querySelector(`[data-focus-id="${CSS.escape(focusId)}"]`) === null) return;
  pendingGuideFocusId = null;
  restoreFocusTarget(focusId);
}

function retainGuideProgramFocusIntent(): boolean {
  const focusId = pendingGuideFocusId?.startsWith('guide-program-') === true
    ? pendingGuideFocusId
    : focusState.activeId?.startsWith('guide-program-') === true
      ? focusState.activeId
      : null;
  if (focusId === null) return false;
  pendingGuideFocusId = focusId;
  return true;
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
  if (focusId?.startsWith('guide-program-') === true) {
    const cell = document.querySelector<HTMLElement>(`[data-focus-id="${CSS.escape(focusId)}"]`);
    const channelId = cell?.dataset.guideChannelId;
    const programId = cell?.dataset.guideProgramId;
    if (channelId !== undefined && programId !== undefined) {
      const next = selectWorkflowEpgProgram(workflowState, channelId, programId);
      if (next !== workflowState) {
        workflowState = next;
        renderApp();
      }
    }
    return;
  }
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
