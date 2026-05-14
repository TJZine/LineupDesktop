import type { ShellStatusEvent } from '../contracts/shell.js';
import {
  queryRendererDom,
  readChannelSetupActionId,
  readEpgActionId,
  readOverlayActionId,
  readPlexRuntimeActionId,
  readRouteActionId,
  readRouteId,
  readSettingsActionId,
} from './domBindings.js';
import {
  clickFocusedRendererElement,
  focusRendererTarget,
  moveRendererFocus,
  renderRendererFocus,
  syncRendererFocusTargets,
} from './focusDom.js';
import {
  createDesktopKeyboardInputListener,
  startDesktopGamepadRuntime,
} from './desktopInput.js';
import { createDesktopCursorRuntime } from './desktopCursor.js';
import {
  FocusRegistry,
  type AppRouteId,
  type DesktopInputButton,
  type FocusState,
} from './navigation.js';
import {
  applyPlayerOverlayAction,
  createFakePlayerSnapshot,
  createPlayerOverlayView,
  createPlayerOverlayState,
  resolvePlayerOverlayFocusId,
  type PlayerOverlayActionId,
} from './overlays.js';
import { renderRouteDom, renderWorkflowDom } from './routeDom.js';
import { mountStaticRendererDom } from './staticDom.js';
import { applySupportBundleExportResult } from './supportBundleExport.js';
import { createPlexRuntimeController } from './plexRuntimeActions.js';
import {
  readPlexHomeUserId,
  readPlexRatingKey,
  readPlexSectionId,
  readPlexServerId,
  renderPlexRuntimeDom,
} from './plexRuntimeDom.js';
import {
  activateWorkflowRoute,
  applyWorkflowAction,
  applyWorkflowChannelSetupAction,
  applyWorkflowEpgAction,
  applyWorkflowSettingsAction,
  createWorkflowState,
  type ChannelSetupActionId,
  type EpgActionId,
  type RouteWorkflowActionId,
  type SettingsActionId,
} from './workflow.js';

mountStaticRendererDom();

const dom = queryRendererDom();

let fullscreenEnabled = false;
let workflowState = createWorkflowState('player');
let overlayState = createPlayerOverlayState();
const playerSnapshot = createFakePlayerSnapshot();
const focusRegistry = new FocusRegistry();
let focusState: FocusState;
const plexController = createPlexRuntimeController({
  bridge: window.lineupDesktop.plex,
  onStateChanged: () => renderApp(),
});

syncRendererFocusTargets(focusRegistry, dom);
focusState = focusRegistry.createInitialState(workflowState.routeState.activeRoute);
renderApp();

const unsubscribeShellStatus = window.lineupDesktop.shell.onStatusChanged(renderStatus);
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
window.addEventListener('beforeunload', () => {
  window.removeEventListener('keydown', keydownListener);
  cursorRuntime.cleanup();
  gamepadRuntime.cleanup();
  unsubscribeShellStatus();
  void plexController.cleanup();
});

for (const button of dom.routeButtons) {
  button.addEventListener('click', () => {
    const route = readRouteId(button.dataset.routeButton);
    if (route !== null) {
      activateRoute(route);
    }
  });
}

for (const button of dom.routeActionButtons) {
  button.addEventListener('click', () => {
    const action = readRouteActionId(button.dataset.routeAction);
    if (action !== null) {
      applyRouteAction(action);
    }
  });
}

for (const button of dom.settingsActionButtons) {
  button.addEventListener('click', () => {
    const action = readSettingsActionId(button.dataset.settingsAction);
    if (action !== null) {
      applySettingsAction(action);
    }
  });
}

for (const button of dom.setupActionButtons) {
  button.addEventListener('click', () => {
    const action = readChannelSetupActionId(button.dataset.setupAction);
    if (action !== null) {
      applyChannelSetupAction(action);
    }
  });
}

for (const button of dom.epgActionButtons) {
  button.addEventListener('click', () => {
    const action = readEpgActionId(button.dataset.epgAction);
    if (action !== null) {
      applyEpgAction(action);
    }
  });
}

for (const button of dom.overlayActionButtons) {
  button.addEventListener('click', () => {
    const action = readOverlayActionId(button.dataset.overlayAction);
    if (action !== null) {
      applyOverlayAction(action);
    }
  });
}

for (const button of dom.plexActionButtons) {
  button.addEventListener('click', () => {
    const action = readPlexRuntimeActionId(button.dataset.plexAction);
    if (action !== null) {
      void applyPlexRuntimeAction(action);
    }
  });
}

dom.plexHomeUserPinInput?.addEventListener('input', () => {
  plexController.setHomeUserPin(dom.plexHomeUserPinInput?.value ?? '');
});

dom.plexSearchQueryInput?.addEventListener('input', () => {
  plexController.setSearchQuery(dom.plexSearchQueryInput?.value ?? '');
});

dom.plexPanelElement?.addEventListener('click', (event) => {
  if (!(event.target instanceof HTMLElement)) {
    return;
  }
  const homeUserButton = event.target.closest<HTMLElement>('[data-plex-home-user-id]');
  const serverButton = event.target.closest<HTMLElement>('[data-plex-server-id]');
  const sectionButton = event.target.closest<HTMLElement>('[data-plex-section-id]');
  const itemButton = event.target.closest<HTMLElement>('[data-plex-rating-key]');
  const homeUserId = homeUserButton === null ? null : readPlexHomeUserId(homeUserButton);
  const serverId = serverButton === null ? null : readPlexServerId(serverButton);
  const sectionId = sectionButton === null ? null : readPlexSectionId(sectionButton);
  const ratingKey = itemButton === null ? null : readPlexRatingKey(itemButton);

  if (homeUserId !== null) {
    void plexController.switchHomeUser(homeUserId);
  } else if (serverId !== null) {
    void plexController.selectServer(serverId);
  } else if (sectionId !== null) {
    plexController.setSelectedSection(sectionId);
    void plexController.listLibraryItems(sectionId);
  } else if (ratingKey !== null) {
    void plexController.getMetadata(ratingKey);
  }
});

for (const element of dom.focusableElements) {
  element.addEventListener('focus', () => focusRendererElement(element));
}

document.addEventListener('focusin', (event) => {
  if (event.target instanceof HTMLElement) {
    focusRendererElement(event.target);
  }
});

dom.fullscreenButton?.addEventListener('click', () => {
  void toggleFullscreen();
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
      if (workflowState.routeState.activeRoute === 'channelSetup' && await plexController.handleBack()) {
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
  focusState = focusRegistry.focusRoute(focusState, route).state;
  renderApp();
}

function applyRouteAction(action: RouteWorkflowActionId): void {
  const previousRoute = workflowState.routeState.activeRoute;
  workflowState = applyWorkflowAction(workflowState, action);
  const nextRoute = workflowState.routeState.activeRoute;
  if (previousRoute !== nextRoute) {
    cleanupPlexRuntimeForRouteChange(previousRoute, nextRoute);
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

function applyEpgAction(action: EpgActionId): void {
  workflowState = applyWorkflowEpgAction(workflowState, action);
  renderApp();
}

function applyOverlayAction(action: PlayerOverlayActionId): void {
  overlayState = applyPlayerOverlayAction(overlayState, action);
  const view = createPlayerOverlayView(overlayState, playerSnapshot);
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

async function applyPlexRuntimeAction(action: ReturnType<typeof readPlexRuntimeActionId>): Promise<void> {
  switch (action) {
    case 'loadSnapshot':
      await plexController.loadSnapshot();
      return;
    case 'requestPin':
      await plexController.requestPin();
      return;
    case 'pollPin':
      await plexController.pollPin();
      return;
    case 'cancelPin':
      await plexController.cancelPin();
      return;
    case 'getHomeUsers':
      await plexController.getHomeUsers();
      return;
    case 'restoreSelectedServer':
      await plexController.restoreSelectedServer();
      return;
    case 'refreshServers':
      await plexController.refreshServers();
      return;
    case 'listLibrarySections':
      await plexController.listLibrarySections();
      return;
    case 'listLibraryItems':
      await plexController.listLibraryItems();
      return;
    case 'searchLibrary':
      await plexController.searchLibrary();
      return;
    case 'clearMetadata':
      plexController.clearMetadata();
      return;
    case 'clearSearch':
      plexController.clearSearch();
      return;
    case 'clearItems':
      plexController.clearItems();
      return;
    case 'clearSelectedSection':
      plexController.clearSelectedSection();
      return;
    case 'clearSelectedServer':
      plexController.clearSelectedServer();
      return;
    case 'clearPinSubflow':
      await plexController.clearPinSubflow();
      return;
    case null:
      return;
  }
}

function cleanupPlexRuntimeForRouteChange(previousRoute: AppRouteId, nextRoute: AppRouteId): void {
  if (previousRoute === 'channelSetup' && nextRoute !== 'channelSetup') {
    void plexController.cleanup();
  }
}

function renderApp(): void {
  renderRouteDom(workflowState, dom);
  renderWorkflowDom(workflowState, overlayState, playerSnapshot, dom);
  renderPlexRuntimeDom(plexController.getState(), dom);
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
