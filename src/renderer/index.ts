import type { ShellStatusEvent } from '../contracts/shell.js';
import { formatEpgTimeWindow } from './epg.js';
import {
  FocusRegistry,
  mapDesktopKeyEvent,
  type AppRouteId,
  type DesktopInputButton,
  type FocusDirection,
  type FocusState,
} from './navigation.js';
import {
  activateWorkflowRoute,
  applyWorkflowChannelSetupAction,
  applyWorkflowEpgAction,
  applyWorkflowAction,
  applyWorkflowSettingsAction,
  createWorkflowState,
  getRouteWorkflowView,
  type ChannelSetupActionId,
  type EpgActionId,
  type RouteWorkflowActionId,
  type SettingsActionId,
} from './workflow.js';
import {
  applyPlayerOverlayAction,
  createFakePlayerSnapshot,
  createPlayerOverlayState,
  createPlayerOverlayView,
  resolvePlayerOverlayFocusId,
  type PlayerOverlayActionId,
} from './overlays.js';

const statusElement = document.querySelector<HTMLElement>('[data-shell-status]');
const capabilitiesElement = document.querySelector<HTMLElement>('[data-shell-capabilities]');
const fullscreenButton = document.querySelector<HTMLButtonElement>('[data-fullscreen-toggle]');
const routeTitleElement = document.querySelector<HTMLElement>('[data-route-title]');
const routeStatusElement = document.querySelector<HTMLElement>('[data-route-status]');
const routeButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-route-button]'),
);
const routeActionButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-route-action]'),
);
const settingsActionButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-settings-action]'),
);
const setupActionButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-setup-action]'),
);
const epgActionButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-epg-action]'),
);
const overlayActionButtons = Array.from(
  document.querySelectorAll<HTMLButtonElement>('[data-overlay-action]'),
);
const screens = Array.from(document.querySelectorAll<HTMLElement>('[data-screen]'));
const focusableElements = Array.from(
  document.querySelectorAll<HTMLElement>('[data-focus-id]'),
);
const currentChannelElement = document.querySelector<HTMLElement>('[data-current-channel]');
const currentProgramElement = document.querySelector<HTMLElement>('[data-current-program]');
const currentWindowElement = document.querySelector<HTMLElement>('[data-current-window]');
const channelListElement = document.querySelector<HTMLElement>('[data-channel-list]');
const epgGridElement = document.querySelector<HTMLElement>('[data-epg-grid]');
const epgDetailChannelElement = document.querySelector<HTMLElement>('[data-epg-detail-channel]');
const epgDetailTitleElement = document.querySelector<HTMLElement>('[data-epg-detail-title]');
const epgDetailTimeElement = document.querySelector<HTMLElement>('[data-epg-detail-time]');
const settingsSourceElement = document.querySelector<HTMLElement>('[data-settings-source]');
const settingsChannelsElement = document.querySelector<HTMLElement>('[data-settings-channels]');
const settingsStateElement = document.querySelector<HTMLElement>('[data-settings-state]');
const settingsSectionsElement = document.querySelector<HTMLElement>('[data-settings-sections]');
const channelSetupSourceElement = document.querySelector<HTMLElement>('[data-channel-setup-source]');
const channelSetupEnabledElement = document.querySelector<HTMLElement>(
  '[data-channel-setup-enabled]',
);
const channelSetupBlocksElement = document.querySelector<HTMLElement>('[data-channel-setup-blocks]');
const setupStepsElement = document.querySelector<HTMLElement>('[data-setup-steps]');
const channelDraftListElement = document.querySelector<HTMLElement>('[data-channel-draft-list]');
const setupValidationElement = document.querySelector<HTMLElement>('[data-setup-validation]');
const overlayElements = Array.from(document.querySelectorAll<HTMLElement>('[data-overlay]'));
const overlayStackElement = document.querySelector<HTMLElement>('[data-overlay-stack]');
const overlayNowPlayingTitleElement = document.querySelector<HTMLElement>(
  '[data-overlay-now-playing-title]',
);
const overlayNowPlayingSubtitleElement = document.querySelector<HTMLElement>(
  '[data-overlay-now-playing-subtitle]',
);
const overlayNowPlayingChannelElement = document.querySelector<HTMLElement>(
  '[data-overlay-now-playing-channel]',
);
const overlayNowPlayingStatusElement = document.querySelector<HTMLElement>(
  '[data-overlay-now-playing-status]',
);
const overlayProgressElement = document.querySelector<HTMLElement>('[data-overlay-progress]');
const overlayMiniGuideElement = document.querySelector<HTMLElement>('[data-overlay-mini-guide]');
const overlayChannelNumberElement = document.querySelector<HTMLElement>(
  '[data-overlay-channel-number-value]',
);
const overlayChannelBadgeNumberElement = document.querySelector<HTMLElement>(
  '[data-overlay-channel-badge-number]',
);
const overlayChannelBadgeNameElement = document.querySelector<HTMLElement>(
  '[data-overlay-channel-badge-name]',
);
const overlayChannelBadgeProgramElement = document.querySelector<HTMLElement>(
  '[data-overlay-channel-badge-program]',
);
const overlayAudioLabelElement = document.querySelector<HTMLElement>('[data-overlay-audio-label]');
const overlaySubtitleLabelElement = document.querySelector<HTMLElement>(
  '[data-overlay-subtitle-label]',
);
const overlayVolumeLabelElement = document.querySelector<HTMLElement>('[data-overlay-volume-label]');
const overlayRateLabelElement = document.querySelector<HTMLElement>('[data-overlay-rate-label]');

let fullscreenEnabled = false;
let workflowState = createWorkflowState('player');
let overlayState = createPlayerOverlayState();
const playerSnapshot = createFakePlayerSnapshot();
const focusRegistry = new FocusRegistry();
let focusState: FocusState;

registerFocusTargets();
focusState = focusRegistry.createInitialState(workflowState.routeState.activeRoute);
renderRoute();
renderWorkflow();
renderFocus();

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

for (const button of routeButtons) {
  button.addEventListener('click', () => {
    const route = readRouteId(button.dataset.routeButton);
    if (route !== null) {
      activateRoute(route);
    }
  });
}

for (const button of routeActionButtons) {
  button.addEventListener('click', () => {
    const action = readRouteActionId(button.dataset.routeAction);
    if (action !== null) {
      applyRouteAction(action);
    }
  });
}

for (const button of settingsActionButtons) {
  button.addEventListener('click', () => {
    const action = readSettingsActionId(button.dataset.settingsAction);
    if (action !== null) {
      applySettingsAction(action);
    }
  });
}

for (const button of setupActionButtons) {
  button.addEventListener('click', () => {
    const action = readChannelSetupActionId(button.dataset.setupAction);
    if (action !== null) {
      applyChannelSetupAction(action);
    }
  });
}

for (const button of epgActionButtons) {
  button.addEventListener('click', () => {
    const action = readEpgActionId(button.dataset.epgAction);
    if (action !== null) {
      applyEpgAction(action);
    }
  });
}

for (const button of overlayActionButtons) {
  button.addEventListener('click', () => {
    const action = readOverlayActionId(button.dataset.overlayAction);
    if (action !== null) {
      applyOverlayAction(action);
    }
  });
}

for (const element of focusableElements) {
  element.addEventListener('focus', () => {
    const focusId = element.dataset.focusId;
    if (focusId !== undefined) {
      focusTarget(focusId);
    }
  });
}

fullscreenButton?.addEventListener('click', () => {
  void toggleFullscreen();
});

const capabilities = await window.lineupDesktop.shell.getCapabilities();
if (capabilitiesElement) {
  capabilitiesElement.textContent = capabilities.ok
    ? `${capabilities.value.appName} ${capabilities.value.appVersion} ${capabilities.value.shellMode}`
    : capabilities.error.message;
}

document.documentElement.dataset.shellBoot = 'ready';
document.documentElement.dataset.activeRoute = workflowState.routeState.activeRoute;

function renderStatus(event: ShellStatusEvent): void {
  if (statusElement) {
    statusElement.textContent = `${event.status} ${new Date(event.timestampMs).toISOString()}`;
  }
}

async function handleDesktopInput(input: DesktopInputButton): Promise<void> {
  switch (input) {
    case 'up':
    case 'down':
    case 'left':
    case 'right':
      moveFocus(input);
      return;
    case 'ok':
      clickFocusedElement();
      return;
    case 'back':
      if (workflowState.routeState.previousRoute !== null) {
        activateRoute(workflowState.routeState.previousRoute);
      } else {
        activateRoute('player');
      }
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

function registerFocusTargets(): void {
  routeButtons.forEach((button, index) => {
    const route = readRouteId(button.dataset.routeButton);
    const focusId = button.dataset.focusId;
    if (route === null || focusId === undefined) {
      return;
    }
    focusRegistry.register({
      id: focusId,
      route,
      order: index,
      scope: 'global',
      neighbors: { right: focusId === 'nav-player' ? 'player-fullscreen' : undefined },
    });
  });

  if (fullscreenButton) {
    focusRegistry.register({
      id: 'player-fullscreen',
      route: 'player',
      order: 120,
      neighbors: { up: 'nav-player', left: 'nav-player' },
    });
  }

  routeActionButtons.forEach((button, index) => {
    const route = readClosestRouteId(button);
    const focusId = button.dataset.focusId;
    if (route === null || focusId === undefined) {
      return;
    }
    focusRegistry.register({
      id: focusId,
      route,
      order: 100 + index,
    });
  });

  [...epgActionButtons, ...settingsActionButtons, ...setupActionButtons].forEach(
    (button, index) => {
      const route = readClosestRouteId(button);
      const focusId = button.dataset.focusId;
      if (route === null || focusId === undefined) {
        return;
      }
      focusRegistry.register({
        id: focusId,
        route,
        order: 80 + index,
      });
    },
  );

  overlayActionButtons.forEach((button, index) => {
    const focusId = button.dataset.focusId;
    if (focusId === undefined) {
      return;
    }
    focusRegistry.register({
      id: focusId,
      route: 'player',
      order: 150 + index,
    });
  });
}

function activateRoute(route: AppRouteId): void {
  workflowState = activateWorkflowRoute(workflowState, route);
  const result = focusRegistry.focusRoute(focusState, route);
  focusState = result.state;
  renderRoute();
  renderWorkflow();
  renderFocus();
}

function renderRoute(): void {
  const activeRoute = workflowState.routeState.activeRoute;
  const view = getRouteWorkflowView(workflowState);
  document.documentElement.dataset.activeRoute = activeRoute;
  if (routeTitleElement) {
    routeTitleElement.textContent = view.title;
  }
  if (routeStatusElement) {
    routeStatusElement.textContent = view.statusText;
  }

  for (const button of routeButtons) {
    const route = readRouteId(button.dataset.routeButton);
    const isActive = route === activeRoute;
    button.classList.toggle('is-active', isActive);
    if (isActive) {
      button.setAttribute('aria-current', 'page');
    } else {
      button.removeAttribute('aria-current');
    }
  }

  for (const screen of screens) {
    const isActive = screen.dataset.screen === activeRoute;
    screen.hidden = !isActive;
    screen.classList.toggle('screen--active', isActive);
    screen.dataset.workflowTone = isActive ? view.tone : '';
  }
}

function renderWorkflow(): void {
  const view = getRouteWorkflowView(workflowState);

  setText(`[data-workflow-kicker="${view.route}"]`, view.kicker);
  setText(`[data-workflow-primary="${view.route}"]`, view.primaryText);
  setText(`[data-workflow-secondary="${view.route}"]`, view.secondaryText);

  if (currentChannelElement) {
    currentChannelElement.textContent = view.currentProgram.channelName;
  }
  if (currentProgramElement) {
    currentProgramElement.textContent = `${view.currentProgram.title} - ${view.currentProgram.subtitle}`;
  }
  if (currentWindowElement) {
    currentWindowElement.textContent = formatEpgTimeWindow(
      view.currentProgram.startsAtMs,
      view.currentProgram.endsAtMs,
    );
  }

  if (channelListElement) {
    channelListElement.replaceChildren(
      ...view.channels.map((channel) => {
        const item = document.createElement('article');
        item.className = 'channel-list__item';
        const number = document.createElement('span');
        number.className = 'channel-list__number';
        number.textContent = channel.number;
        const copy = document.createElement('div');
        const title = document.createElement('strong');
        title.textContent = channel.name;
        const detail = document.createElement('p');
        detail.textContent = `${channel.currentTitle} next: ${channel.nextTitle}`;
        copy.append(title, detail);
        item.append(number, copy);
        return item;
      }),
    );
  }

  renderEpgGuide();
  renderPlayerOverlays();

  if (settingsSourceElement) {
    settingsSourceElement.textContent = view.settings.libraryName;
  }
  if (settingsChannelsElement) {
    settingsChannelsElement.textContent = String(view.settings.channelCount);
  }
  if (settingsStateElement) {
    settingsStateElement.textContent = view.settings.setupState;
  }
  if (settingsSectionsElement) {
    settingsSectionsElement.replaceChildren(
      ...view.settings.sections.map((section) => {
        const article = document.createElement('article');
        article.className = 'settings-section';
        const title = document.createElement('h3');
        title.textContent = section.title;
        const detail = document.createElement('p');
        detail.textContent = section.detail;
        const list = document.createElement('dl');
        for (const setting of section.items) {
          const row = document.createElement('div');
          const label = document.createElement('dt');
          label.textContent = setting.label;
          const value = document.createElement('dd');
          value.textContent = `${setting.valueLabel} - ${setting.description}`;
          row.append(label, value);
          list.append(row);
        }
        article.append(title, detail, list);
        return article;
      }),
    );
  }

  if (setupStepsElement) {
    setupStepsElement.replaceChildren(
      ...view.setupSteps.map((step) => {
        const item = document.createElement('li');
        item.dataset.stepState = step.state;
        const copy = document.createElement('div');
        const label = document.createElement('strong');
        label.textContent = step.label;
        const detail = document.createElement('span');
        detail.textContent = step.detail;
        copy.append(label, detail);
        item.append(copy);
        return item;
      }),
    );
  }
  if (channelSetupSourceElement) {
    channelSetupSourceElement.textContent = view.channelSetupSummary.sourceName;
  }
  if (channelSetupEnabledElement) {
    channelSetupEnabledElement.textContent = `${view.channelSetupSummary.enabledChannelCount} of ${view.channelSetupSummary.totalChannelCount}`;
  }
  if (channelSetupBlocksElement) {
    channelSetupBlocksElement.textContent = String(view.channelSetupSummary.totalBlockCount);
  }
  if (channelDraftListElement) {
    channelDraftListElement.replaceChildren(
      ...view.channelDrafts.map((channel) => {
        const item = document.createElement('article');
        item.className = 'channel-draft-list__item';
        item.dataset.channelEnabled = String(channel.enabled);
        const number = document.createElement('span');
        number.className = 'channel-list__number';
        number.textContent = channel.number;
        const copy = document.createElement('div');
        const title = document.createElement('strong');
        title.textContent = channel.name;
        const detail = document.createElement('p');
        detail.textContent = `${channel.enabled ? 'Enabled' : 'Paused'} - ${channel.blockCount} fake blocks`;
        copy.append(title, detail);
        item.append(number, copy);
        return item;
      }),
    );
  }
  if (setupValidationElement) {
    setupValidationElement.textContent =
      view.setupValidationMessages.length === 0
        ? 'Draft setup is ready for guide and player previews.'
        : view.setupValidationMessages.join(' ');
  }

  for (const button of routeActionButtons) {
    const action = readRouteActionId(button.dataset.routeAction);
    const route = readClosestRouteId(button);
    const viewAction =
      action === null || route === null || route !== view.route
        ? null
        : view.actions.find((candidate) => candidate.id === action);
    if (viewAction !== undefined && viewAction !== null) {
      button.textContent = viewAction.label;
    }
  }
}

function moveFocus(direction: FocusDirection): void {
  const result = focusRegistry.move(focusState, direction);
  focusState = result.state;
  if (result.changed) {
    renderFocus();
  }
}

function focusTarget(focusId: string): void {
  const result = focusRegistry.focusTarget(focusState, focusId);
  focusState = result.state;
  if (result.changed) {
    renderFocus();
  }
}

function renderFocus(): void {
  for (const element of focusableElements) {
    const isActive = element.dataset.focusId === focusState.activeId;
    const isPrimaryRouteButton = readRouteId(element.dataset.routeButton) !== null;
    element.classList.toggle('is-focused', isActive);
    element.tabIndex = isActive || isPrimaryRouteButton ? 0 : -1;
    if (isActive && document.activeElement !== element) {
      element.focus({ preventScroll: true });
    }
  }
}

function clickFocusedElement(): void {
  const activeElement = focusableElements.find(
    (element) => element.dataset.focusId === focusState.activeId,
  );
  if (activeElement instanceof HTMLButtonElement) {
    activeElement.click();
  }
}

function applyRouteAction(action: RouteWorkflowActionId): void {
  const previousRoute = workflowState.routeState.activeRoute;
  workflowState = applyWorkflowAction(workflowState, action);
  const nextRoute = workflowState.routeState.activeRoute;
  if (previousRoute !== nextRoute) {
    const result = focusRegistry.focusRoute(focusState, nextRoute);
    focusState = result.state;
  }
  renderRoute();
  renderWorkflow();
  renderFocus();
}

function applySettingsAction(action: SettingsActionId): void {
  workflowState = applyWorkflowSettingsAction(workflowState, action);
  renderRoute();
  renderWorkflow();
  renderFocus();
}

function applyChannelSetupAction(action: ChannelSetupActionId): void {
  workflowState = applyWorkflowChannelSetupAction(workflowState, action);
  renderRoute();
  renderWorkflow();
  renderFocus();
}

function applyEpgAction(action: EpgActionId): void {
  workflowState = applyWorkflowEpgAction(workflowState, action);
  renderRoute();
  renderWorkflow();
  renderFocus();
}

function applyOverlayAction(action: PlayerOverlayActionId): void {
  overlayState = applyPlayerOverlayAction(overlayState, action);
  const view = createPlayerOverlayView(overlayState, playerSnapshot);
  focusState = focusRegistry.focusTarget(focusState, resolvePlayerOverlayFocusId(view)).state;
  renderRoute();
  renderWorkflow();
  renderFocus();
}

async function toggleFullscreen(): Promise<void> {
  const result = await window.lineupDesktop.window.setFullscreen(!fullscreenEnabled);
  if (result.ok) {
    fullscreenEnabled = result.value.enabled;
    fullscreenButton?.setAttribute('aria-pressed', String(fullscreenEnabled));
  }
}

function readRouteId(value: string | undefined): AppRouteId | null {
  switch (value) {
    case 'player':
    case 'guide':
    case 'settings':
    case 'channelSetup':
      return value;
    default:
      return null;
  }
}

function readRouteActionId(value: string | undefined): RouteWorkflowActionId | null {
  switch (value) {
    case 'openGuide':
    case 'resumePlayer':
    case 'openSettings':
    case 'openChannelSetup':
    case 'reviewLineup':
    case 'confirmSetup':
      return value;
    default:
      return null;
  }
}

function readSettingsActionId(value: string | undefined): SettingsActionId | null {
  switch (value) {
    case 'cycleLaunchMode':
    case 'cycleGuideDensity':
    case 'togglePreviewBadges':
    case 'toggleSetupReminder':
      return value;
    default:
      return null;
  }
}

function readChannelSetupActionId(value: string | undefined): ChannelSetupActionId | null {
  switch (value) {
    case 'advanceSetupStep':
    case 'toggleFeaturedChannel':
    case 'addDraftChannel':
    case 'resetDraftLineup':
      return value;
    default:
      return null;
  }
}

function readEpgActionId(value: string | undefined): EpgActionId | null {
  switch (value) {
    case 'previousWindow':
    case 'nextWindow':
    case 'previousChannel':
    case 'nextChannel':
    case 'previousProgram':
    case 'nextProgram':
      return value;
    default:
      return null;
  }
}

function readOverlayActionId(value: string | undefined): PlayerOverlayActionId | null {
  switch (value) {
    case 'toggleOsd':
    case 'openMiniGuide':
    case 'previousMiniGuideChannel':
    case 'nextMiniGuideChannel':
    case 'togglePlaybackOptions':
    case 'cycleAudioTrack':
    case 'cycleSubtitleTrack':
    case 'toggleMute':
    case 'volumeDown':
    case 'volumeUp':
    case 'channelDigit0':
    case 'channelDigit1':
    case 'channelDigit2':
    case 'channelDigit3':
    case 'channelDigit4':
    case 'channelDigit5':
    case 'channelDigit6':
    case 'channelDigit7':
    case 'channelDigit8':
    case 'channelDigit9':
    case 'commitChannelNumber':
    case 'clearChannelNumber':
    case 'closeTopOverlay':
      return value;
    default:
      return null;
  }
}

function readClosestRouteId(element: HTMLElement): AppRouteId | null {
  const screen = element.closest<HTMLElement>('[data-screen]');
  return readRouteId(screen?.dataset.screen);
}

function setText(selector: string, value: string): void {
  const element = document.querySelector<HTMLElement>(selector);
  if (element) {
    element.textContent = value;
  }
}

function renderEpgGuide(): void {
  const view = getRouteWorkflowView(workflowState);
  const selectedRow = view.guide.rows.find((row) => row.id === view.guide.selectedProgram.channelId);
  if (epgDetailChannelElement) {
    epgDetailChannelElement.textContent =
      selectedRow === undefined ? '' : `${selectedRow.number} ${selectedRow.name}`;
  }
  if (epgDetailTitleElement) {
    epgDetailTitleElement.textContent = view.guide.selectedProgram.title;
  }
  if (epgDetailTimeElement) {
    epgDetailTimeElement.textContent = `${view.guide.selectedProgram.subtitle} - ${formatEpgTimeWindow(
      view.guide.selectedProgram.startsAtMs,
      view.guide.selectedProgram.endsAtMs,
    )}`;
  }

  if (!epgGridElement) {
    return;
  }

  const header = document.createElement('div');
  header.className = 'epg-grid__header';
  header.append(document.createElement('span'));
  const slotTrack = document.createElement('div');
  slotTrack.className = 'epg-grid__slots';
  for (const slot of view.guide.slots) {
    const label = document.createElement('span');
    label.textContent = slot.label;
    slotTrack.append(label);
  }
  header.append(slotTrack);

  const rows = view.guide.rows.map((row) => {
    const rowElement = document.createElement('section');
    rowElement.className = 'epg-grid__row';
    rowElement.dataset.selectedChannel = String(row.isSelected);
    const channel = document.createElement('div');
    channel.className = 'epg-grid__channel';
    const number = document.createElement('strong');
    number.textContent = row.number;
    const name = document.createElement('span');
    name.textContent = row.name;
    channel.append(number, name);
    rowElement.append(channel);

    const programs = document.createElement('div');
    programs.className = 'epg-grid__programs';
    for (const program of row.programs) {
      const cell = document.createElement('article');
      cell.className = 'epg-grid__program';
      cell.dataset.selectedProgram = String(program.isSelected);
      cell.style.gridColumn = `${program.columnStart} / span ${program.columnSpan}`;
      const title = document.createElement('strong');
      title.textContent = program.title;
      const subtitle = document.createElement('span');
      subtitle.textContent = program.subtitle;
      cell.append(title, subtitle);
      programs.append(cell);
    }
    rowElement.append(programs);
    return rowElement;
  });

  epgGridElement.replaceChildren(header, ...rows);
}

function renderPlayerOverlays(): void {
  const view = createPlayerOverlayView(overlayState, playerSnapshot);
  document.documentElement.dataset.activeOverlay = view.activeOverlayId ?? '';

  for (const element of overlayElements) {
    const overlayId = element.dataset.overlay;
    const isVisible =
      overlayId === 'playerOsd' ||
      overlayId === 'nowPlaying' ||
      overlayId === 'miniGuide' ||
      overlayId === 'channelNumber' ||
      overlayId === 'channelBadge' ||
      overlayId === 'playbackOptions'
        ? view.visibleOverlays[overlayId]
        : false;
    element.hidden = !isVisible;
    element.dataset.overlayActive = String(overlayId === view.activeOverlayId);
  }

  if (overlayStackElement) {
    overlayStackElement.dataset.overlayStack = view.stack.join(',');
  }
  if (overlayNowPlayingTitleElement) {
    overlayNowPlayingTitleElement.textContent = view.nowPlaying.title;
  }
  if (overlayNowPlayingSubtitleElement) {
    overlayNowPlayingSubtitleElement.textContent = view.nowPlaying.subtitle;
  }
  if (overlayNowPlayingChannelElement) {
    overlayNowPlayingChannelElement.textContent = `${view.nowPlaying.channelNumber} ${view.nowPlaying.channelName}`;
  }
  if (overlayNowPlayingStatusElement) {
    overlayNowPlayingStatusElement.textContent = `${view.nowPlaying.statusLabel} ${view.nowPlaying.positionLabel} / ${view.nowPlaying.durationLabel}`;
  }
  if (overlayProgressElement) {
    overlayProgressElement.style.setProperty('--overlay-progress', `${view.nowPlaying.progressPercent}%`);
    overlayProgressElement.setAttribute('aria-valuenow', String(view.nowPlaying.progressPercent));
  }
  if (overlayMiniGuideElement) {
    overlayMiniGuideElement.replaceChildren(
      ...view.miniGuideChannels.map((channel) => {
        const item = document.createElement('article');
        item.className = 'mini-guide__item';
        item.dataset.selectedChannel = String(channel.selected);
        const number = document.createElement('strong');
        number.textContent = channel.number;
        const copy = document.createElement('div');
        const name = document.createElement('span');
        name.textContent = channel.name;
        const title = document.createElement('p');
        title.textContent = `${channel.currentTitle} next: ${channel.nextTitle}`;
        copy.append(name, title);
        item.append(number, copy);
        return item;
      }),
    );
  }
  if (overlayChannelNumberElement) {
    overlayChannelNumberElement.textContent = view.channelNumberDisplay;
  }
  if (overlayChannelBadgeNumberElement) {
    overlayChannelBadgeNumberElement.textContent = view.channelBadge.number;
  }
  if (overlayChannelBadgeNameElement) {
    overlayChannelBadgeNameElement.textContent = view.channelBadge.name;
  }
  if (overlayChannelBadgeProgramElement) {
    overlayChannelBadgeProgramElement.textContent = view.channelBadge.currentTitle;
  }
  if (overlayAudioLabelElement) {
    overlayAudioLabelElement.textContent = view.playbackOptions.selectedAudioLabel;
  }
  if (overlaySubtitleLabelElement) {
    overlaySubtitleLabelElement.textContent = view.playbackOptions.selectedSubtitleLabel;
  }
  if (overlayVolumeLabelElement) {
    overlayVolumeLabelElement.textContent = view.playbackOptions.muted
      ? 'Muted'
      : `${view.playbackOptions.volumePercent}%`;
  }
  if (overlayRateLabelElement) {
    overlayRateLabelElement.textContent = view.playbackOptions.playbackRateLabel;
  }
}
