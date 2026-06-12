import type { ShellStatusEvent } from '../contracts/shell.js';
import { queryRendererDom, type ChannelCommitActionId, type PlexRuntimeActionId } from './domBindings.js';
import { clickFocusedRendererElement, focusRendererTarget, moveRendererFocus, renderRendererFocus, syncRendererFocusTargets } from './focusDom.js';
import { createDesktopKeyboardInputListener, startDesktopGamepadRuntime } from './desktopInput.js';
import { createDesktopCursorRuntime } from './desktopCursor.js';
import { FocusRegistry, type AppRouteId, type DesktopInputButton, type FocusState } from './navigation.js';
import { applyPlayerOverlayAction, createPlayerOverlayView, createPlayerOverlayState, resolvePlayerOverlayFocusId, type PlayerOverlayActionId } from './overlays.js';
import { renderRouteDom, renderWorkflowDom } from './routeDom.js';
import { mountStaticRendererDom } from './staticDom.js';
import { applySupportBundleExportResult } from './supportBundleExport.js';
import { createPlexRuntimeController } from './plexRuntimeActions.js';
import { resolveChannelSetupLiveSelection } from './channelSetup/liveSelection.js';
import { createChannelRuntimeController } from './channelRuntimeActions.js';
import { renderPlexRuntimeDom } from './plexRuntimeDom.js';
import { activateWorkflowRoute, applyWorkflowAction, applyWorkflowChannelSetupAction, applyWorkflowEpgAction, applyWorkflowSettingsAction, createWorkflowState, type ChannelSetupActionId, type EpgActionId, type RouteWorkflowActionId, type SettingsActionId } from './workflow.js';
import { createRendererPresentationFixtures } from './presentationFixtures.js';
import {
  recordRendererBridgeFailure,
  summarizeRendererBridgeError,
} from './rendererBridgeFailures.js';
import { setEpgPresentationState, updateEpgState } from './epg.js';
import { registerRendererActions } from './rendererActionRegistration.js';
import { subscribePlayerBridge } from './playerBridgeSubscription.js';
import { createGuidePresentationPolling } from './guidePresentationPolling.js';
import { dispatchPlexRuntimeAction } from './plexRuntimeActionDispatch.js';
import { initializeProfilePinModal, openProfilePinModal, isProfilePinModalActive, closeProfilePinModal } from './profilePinModal.js';

mountStaticRendererDom();

const dom = queryRendererDom();

let fullscreenEnabled = false;
const presentationFixtures = createRendererPresentationFixtures();
let workflowState = createWorkflowState('player', presentationFixtures.guide);
let overlayState = createPlayerOverlayState(presentationFixtures.overlays);
let playerSnapshot = presentationFixtures.playerSnapshot;
const focusRegistry = new FocusRegistry();
let focusState: FocusState;
const plexController = createPlexRuntimeController({
  bridge: window.lineupDesktop.plex,
  onStateChanged: () => renderApp(),
  recordRendererEvent: window.lineupDesktop.diagnostics.recordRendererEvent,
});
const channelController = createChannelRuntimeController({
  bridge: window.lineupDesktop.channelSetup,
  onStateChanged: () => renderApp(),
});

initializeProfilePinModal({
  getPlexController: () => plexController,
  getFocusState: () => focusState,
  setFocusState: (state) => {
    focusState = state;
  },
  getFocusRegistry: () => focusRegistry,
  renderApp,
});

syncRendererFocusTargets(focusRegistry, dom);
focusState = focusRegistry.createInitialState(workflowState.routeState.activeRoute);
renderApp();

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
const cursorRuntime = createDesktopCursorRuntime({
  host: window,
  root: document.documentElement,
});

const keydownListener = createDesktopKeyboardInputListener(handleDesktopInput);
const gamepadRuntime = startDesktopGamepadRuntime({
  host: window,
  getGamepads: () => window.navigator.getGamepads(),
  dispatch: handleDesktopInput,
});

window.addEventListener('keydown', keydownListener);

void playerBridgeSubscription.initializeSnapshot();

window.addEventListener('beforeunload', () => {
  window.removeEventListener('keydown', keydownListener);
  cursorRuntime.cleanup();
  gamepadRuntime.cleanup();
  unsubscribeShellStatus();
  playerBridgeSubscription.unsubscribe();
  guidePresentationPolling.stop();
  cleanupPlexRuntime('beforeunload');
});

registerRendererActions(dom, document, {
  activateRoute,
  applyRouteAction: (action) => { void applyRouteAction(action); },
  applySettingsAction,
  applyChannelSetupAction,
  applyChannelCommitAction: (action) => { void applyChannelCommitAction(action); },
  applyEpgAction,
  applyOverlayAction,
  applyPlexRuntimeAction: (action) => { void applyPlexRuntimeAction(action); },
  setPlexHomeUserPin: (value) => plexController.setHomeUserPin(value),
  setPlexSearchQuery: (value) => plexController.setSearchQuery(value),
  selectPlexHomeUser: (homeUserId) => {
    clearChannelSetupActionStateForSourceChange();
    const state = plexController.getState();
    const user = state.snapshot?.auth.homeUsers.find((u) => u.id === homeUserId);
    if (user?.protected) {
      openProfilePinModal(user);
    } else {
      void plexController.switchHomeUser(homeUserId);
    }
  },
  selectPlexServer: (serverId) => {
    clearChannelSetupActionStateForSourceChange();
    void plexController.selectServer(serverId);
  },
  selectPlexSection: (sectionId) => {
    clearChannelSetupActionStateForSourceChange();
    plexController.setSelectedSection(sectionId);
    void plexController.listLibraryItems(sectionId);
  },
  openPlexMetadata: (ratingKey) => { void plexController.getMetadata(ratingKey); },
  focusElement: focusRendererElement,
  toggleFullscreen: () => { void toggleFullscreen(); },
  selectAudioTrack: (trackId) => { void selectAudioTrack(trackId); },
  selectSubtitleTrack: (trackId) => { void selectSubtitleTrack(trackId); },
});

const capabilities = await window.lineupDesktop.shell.getCapabilities();
if (dom.capabilitiesElement) {
  dom.capabilitiesElement.textContent = capabilities.ok
    ? `${capabilities.value.appName} ${capabilities.value.appVersion} ${capabilities.value.shellMode}`
    : 'Unable to load capabilities';
}

document.documentElement.dataset.shellBoot = 'ready';
document.documentElement.dataset.activeRoute = workflowState.routeState.activeRoute;
void plexController.loadSnapshot();
void channelController.loadStatus();
if (workflowState.routeState.activeRoute === 'guide') {
  guidePresentationPolling.start();
}

function renderStatus(event: ShellStatusEvent): void {
  if (dom.statusElement) {
    dom.statusElement.textContent = `${event.status} ${new Date(event.timestampMs).toISOString()}`;
  }
}

async function handleDesktopInput(input: DesktopInputButton): Promise<void> {
  cursorRuntime.hideForDesktopInput();

  switch (input) {
    case 'up':
    case 'down':
    case 'left':
    case 'right':
      focusState = moveRendererFocus(focusRegistry, focusState, input, dom);
      scrollFocusedSetupControlIntoView();
      return;
    case 'ok':
      clickFocusedRendererElement(focusState, dom);
      return;
    case 'back':
      if (isProfilePinModalActive()) {
        closeProfilePinModal();
        return;
      }
      if (workflowState.routeState.activeRoute === 'channelSetup' && await handlePlexBack()) {
        renderApp();
        scrollFocusedSetupControlIntoView();
        return;
      }
      activateRoute(workflowState.routeState.previousRoute ?? 'player');
      return;
    case 'guide':
      activateRoute('guide');
      return;
    case 'settings':
      activateRoute('settings');
      return;
    case 'fullscreen':
      await toggleFullscreen();
      return;
  }
}

function activateRoute(route: AppRouteId): void {
  const previousRoute = workflowState.routeState.activeRoute;
  workflowState = activateWorkflowRoute(workflowState, route);
  cleanupPlexRuntimeForRouteChange(previousRoute, workflowState.routeState.activeRoute);
  reconcileGuidePresentationPolling(previousRoute, workflowState.routeState.activeRoute);
  focusState = focusRegistry.focusRoute(focusState, route).state;
  renderApp();
}

async function applyRouteAction(action: RouteWorkflowActionId): Promise<void> {
  const previousRoute = workflowState.routeState.activeRoute;
  if (action === 'resumePlayer' && previousRoute === 'guide') {
    await tuneGuideSelectedChannel();
    return;
  }
  workflowState = applyWorkflowAction(workflowState, action);
  const nextRoute = workflowState.routeState.activeRoute;
  if (previousRoute !== nextRoute) {
    cleanupPlexRuntimeForRouteChange(previousRoute, nextRoute);
    reconcileGuidePresentationPolling(previousRoute, nextRoute);
    focusState = focusRegistry.focusRoute(focusState, nextRoute).state;
  }
  renderApp();
}

function applySettingsAction(action: SettingsActionId): void {
  workflowState = applyWorkflowSettingsAction(workflowState, action);
  renderApp();
  if (action === 'exportSupportBundle') {
    void exportSupportBundle();
  }
}

function applyChannelSetupAction(action: ChannelSetupActionId): void {
  workflowState = applyWorkflowChannelSetupAction(workflowState, action);
  renderApp();
}

function reconcileGuidePresentationPolling(previousRoute: AppRouteId, nextRoute: AppRouteId): void {
  guidePresentationPolling.reconcile(previousRoute, nextRoute);
}

async function applyChannelCommitAction(action: ChannelCommitActionId): Promise<void> {
  const plexState = plexController.getState();
  const sectionId = resolveLiveSelectedPlexSectionId(plexState);
  if (sectionId === null) {
    channelController.markBlocked('Choose a movie or show library section before saving channels. Selecting an individual media item only opens metadata preview.');
    renderApp();
    return;
  }
  await channelController.commit({
    mode: action === 'append' ? 'append' : 'replace',
    sectionIds: [sectionId],
    confirmReplace: action === 'confirmReplace',
  });
  renderApp();
}

function applyEpgAction(action: EpgActionId): void {
  const previousWindowStartMs = workflowState.epg.windowStartMs;
  workflowState = applyWorkflowEpgAction(workflowState, action);
  renderApp();
  if (workflowState.epg.windowStartMs !== previousWindowStartMs) {
    void guidePresentationPolling.refresh('epg-window-change', { showLoading: true });
  }
}

async function selectAudioTrack(trackId: string): Promise<void> {
  const requestId = `select-audio-${Date.now()}`;
  await window.lineupDesktop.player.dispatch({
    intent: 'player.selectAudio',
    requestId,
    payload: { trackId },
  });
}

async function selectSubtitleTrack(trackId: string | null): Promise<void> {
  const requestId = `select-subtitle-${Date.now()}`;
  await window.lineupDesktop.player.dispatch({
    intent: 'player.selectSubtitle',
    requestId,
    payload: { trackId },
  });
}

let channelCommitTimeoutId: number | null = null;

function applyOverlayAction(action: PlayerOverlayActionId): void {
  if (action.startsWith('channelDigit')) {
    if (channelCommitTimeoutId !== null) {
      window.clearTimeout(channelCommitTimeoutId);
    }
    channelCommitTimeoutId = window.setTimeout(() => {
      channelCommitTimeoutId = null;
      applyOverlayAction('commitChannelNumber');
    }, 2500);
  } else if (
    action === 'commitChannelNumber' ||
    action === 'clearChannelNumber' ||
    action === 'closeTopOverlay'
  ) {
    if (channelCommitTimeoutId !== null) {
      window.clearTimeout(channelCommitTimeoutId);
      channelCommitTimeoutId = null;
    }
  }

  if (action === 'volumeUp' || action === 'volumeDown') {
    const currentVolume = playerSnapshot.volume;
    const nextVolume = action === 'volumeUp'
      ? Math.min(1, Math.round((currentVolume + 0.1) * 10) / 10)
      : Math.max(0, Math.round((currentVolume - 0.1) * 10) / 10);
    const requestId = `volume-change-${Date.now()}`;
    void window.lineupDesktop.player.dispatch({
      intent: 'player.setVolume',
      requestId,
      payload: { volume: nextVolume },
    });
  } else if (action === 'toggleMute') {
    const requestId = `mute-change-${Date.now()}`;
    void window.lineupDesktop.player.dispatch({
      intent: 'player.setMute',
      requestId,
      payload: { muted: !playerSnapshot.muted },
    });
  } else if (action === 'cycleAudioTrack') {
    const audioTracks = playerSnapshot.tracks.filter((t) => t.kind === 'audio' && t.available);
    if (audioTracks.length > 0) {
      const selectedAudioIndex = audioTracks.findIndex((t) => t.selected);
      const nextAudioTrack = audioTracks[(selectedAudioIndex + 1) % audioTracks.length];
      if (nextAudioTrack) {
        void selectAudioTrack(nextAudioTrack.id);
      }
    }
  } else if (action === 'cycleSubtitleTrack') {
    const subtitleTracks = playerSnapshot.tracks.filter((t) => t.kind === 'subtitle' && t.available);
    const subtitleOptions: (string | null)[] = [null, ...subtitleTracks.map((t) => t.id)];
    const currentSub = playerSnapshot.selectedSubtitleTrackId;
    const currentIndex = subtitleOptions.indexOf(currentSub);
    const nextSub = subtitleOptions[(currentIndex + 1) % subtitleOptions.length];
    void selectSubtitleTrack(nextSub);
  }

  overlayState = applyPlayerOverlayAction(overlayState, action, Date.now(), presentationFixtures.overlays);
  const view = createPlayerOverlayView(overlayState, {
    ...presentationFixtures.overlays,
    playerSnapshot,
  });
  focusState = focusRegistry.focusTarget(focusState, resolvePlayerOverlayFocusId(view)).state;
  renderApp();
}

async function toggleFullscreen(): Promise<void> {
  const result = await window.lineupDesktop.window.setFullscreen(!fullscreenEnabled);
  if (result.ok) {
    fullscreenEnabled = result.value.enabled;
    dom.fullscreenButton?.setAttribute('aria-pressed', String(fullscreenEnabled));
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
  await dispatchPlexRuntimeAction(action, {
    controller: plexController,
    clearSourceActionState: clearChannelSetupActionStateForSourceChange,
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
    workflowState = applyWorkflowAction(workflowState, 'resumePlayer');
    const nextRoute = workflowState.routeState.activeRoute;
    cleanupPlexRuntimeForRouteChange(previousRoute, nextRoute);
    reconcileGuidePresentationPolling(previousRoute, nextRoute);
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

function clearChannelSetupActionStateForSourceChange(): void {
  channelController.clearActionState();
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
  );
  renderPlexRuntimeDom(plexState, dom);
  syncRendererFocusTargets(focusRegistry, dom);
  if (focusState.activeId !== null) {
    focusState = focusRegistry.focusTarget(focusState, focusState.activeId).state;
  }
  renderRendererFocus(focusState, dom);
  scrollFocusedSetupControlIntoView();
}

function focusRendererElement(element: HTMLElement): void {
  const focusId = element.dataset.focusId;
  if (focusId !== undefined) {
    focusState = focusRendererTarget(focusRegistry, focusState, focusId, dom);
    scrollFocusedSetupControlIntoView();
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
