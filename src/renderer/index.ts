import type { ShellStatusEvent } from '../contracts/shell.js';
import {
  queryRendererDom,
  readChannelSetupActionId,
  readEpgActionId,
  readOverlayActionId,
  readRouteActionId,
  readRouteId,
  readSettingsActionId,
} from './domBindings.js';
import {
  clickFocusedRendererElement,
  focusRendererTarget,
  moveRendererFocus,
  registerRendererFocusTargets,
  renderRendererFocus,
} from './focusDom.js';
import {
  FocusRegistry,
  mapDesktopKeyEvent,
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

registerRendererFocusTargets(focusRegistry, dom);
focusState = focusRegistry.createInitialState(workflowState.routeState.activeRoute);
renderApp();

const unsubscribeShellStatus = window.lineupDesktop.shell.onStatusChanged(renderStatus);

const keydownListener = (event: KeyboardEvent): void => {
  const input = mapDesktopKeyEvent(event);
  if (input === null) {
    return;
  }
  event.preventDefault();
  void handleDesktopInput(input);
};

window.addEventListener('keydown', keydownListener);
window.addEventListener('beforeunload', () => {
  window.removeEventListener('keydown', keydownListener);
  unsubscribeShellStatus();
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

for (const element of dom.focusableElements) {
  element.addEventListener('focus', () => {
    const focusId = element.dataset.focusId;
    if (focusId !== undefined) {
      focusState = focusRendererTarget(focusRegistry, focusState, focusId, dom);
    }
  });
}

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

function renderStatus(event: ShellStatusEvent): void {
  if (dom.statusElement) {
    dom.statusElement.textContent = `${event.status} ${new Date(event.timestampMs).toISOString()}`;
  }
}

async function handleDesktopInput(input: DesktopInputButton): Promise<void> {
  switch (input) {
    case 'up':
    case 'down':
    case 'left':
    case 'right':
      focusState = moveRendererFocus(focusRegistry, focusState, input, dom);
      return;
    case 'ok':
      clickFocusedRendererElement(focusState, dom);
      return;
    case 'back':
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
  workflowState = activateWorkflowRoute(workflowState, route);
  focusState = focusRegistry.focusRoute(focusState, route).state;
  renderApp();
}

function applyRouteAction(action: RouteWorkflowActionId): void {
  const previousRoute = workflowState.routeState.activeRoute;
  workflowState = applyWorkflowAction(workflowState, action);
  const nextRoute = workflowState.routeState.activeRoute;
  if (previousRoute !== nextRoute) {
    focusState = focusRegistry.focusRoute(focusState, nextRoute).state;
  }
  renderApp();
}

function applySettingsAction(action: SettingsActionId): void {
  workflowState = applyWorkflowSettingsAction(workflowState, action);
  renderApp();
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

function renderApp(): void {
  renderRouteDom(workflowState, dom);
  renderWorkflowDom(workflowState, overlayState, playerSnapshot, dom);
  renderRendererFocus(focusState, dom);
}
