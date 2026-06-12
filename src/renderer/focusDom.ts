import type { RendererDomBindings } from './domBindings.js';
import { readClosestRouteId, readRouteId } from './domBindings.js';
import type {
  FocusRegistry,
  FocusDirection,
  FocusState,
} from './navigation.js';

const dynamicFocusIdsByRegistry = new WeakMap<FocusRegistry, Set<string>>();

export function syncRendererFocusTargets(
  focusRegistry: FocusRegistry,
  dom: RendererDomBindings,
): void {
  const focusableElements = readCurrentFocusableElements(dom);
  const currentDynamicIds = new Set(
    focusableElements
      .map((element) => element.dataset.focusId)
      .filter((focusId): focusId is string => isDynamicFocusId(focusId)),
  );
  const previousDynamicIds = dynamicFocusIdsByRegistry.get(focusRegistry) ?? new Set();
  for (const focusId of previousDynamicIds) {
    if (!currentDynamicIds.has(focusId)) {
      focusRegistry.unregister(focusId);
    }
  }
  dynamicFocusIdsByRegistry.set(focusRegistry, currentDynamicIds);
  dom.focusableElements.splice(0, dom.focusableElements.length, ...focusableElements);
  registerRendererFocusTargets(focusRegistry, dom);
}

export function registerRendererFocusTargets(
  focusRegistry: FocusRegistry,
  dom: RendererDomBindings,
): void {
  const registered = new Set<string>();
  dom.routeButtons.forEach((button, index) => {
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
      hiddenOnRoutes: ['channelSetup'],
      neighbors: { right: focusId === 'nav-player' ? 'player-fullscreen' : undefined },
    });
    registered.add(focusId);
  });

  if (dom.fullscreenButton) {
    focusRegistry.register({
      id: 'player-fullscreen',
      route: 'player',
      order: 120,
      neighbors: { up: 'nav-player', left: 'nav-player' },
    });
    registered.add('player-fullscreen');
  }

  dom.routeActionButtons.forEach((button, index) => {
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
    registered.add(focusId);
  });

  [...dom.epgActionButtons, ...dom.settingsActionButtons, ...dom.setupActionButtons].forEach(
    (button, index) => registerOrderedButton(focusRegistry, registered, button, 80 + index),
  );

  dom.plexActionButtons.forEach((button, index) => {
    registerOrderedButton(focusRegistry, registered, button, plexActionFocusOrder(button, index));
  });

  dom.channelCommitButtons.forEach((button, index) => {
    registerOrderedButton(focusRegistry, registered, button, 40 + index);
  });

  dom.focusableElements.forEach((element, index) => {
    const focusId = element.dataset.focusId;
    const route = readClosestRouteId(element);
    if (focusId === undefined || registered.has(focusId) || route === null) {
      return;
    }
    const neighbors = focusId.startsWith('numpad-')
      ? getNumpadNeighbors(focusId)
      : focusId.startsWith('settings-')
      ? getSettingsNeighbors(focusId)
      : undefined;
    focusRegistry.register({
      id: focusId,
      route,
      order: focusElementOrder(focusId, index),
      neighbors,
    });
    registered.add(focusId);
  });

  dom.overlayActionButtons.forEach((button, index) => {
    const focusId = button.dataset.focusId;
    if (focusId === undefined) {
      return;
    }
    focusRegistry.register({
      id: focusId,
      route: 'player',
      order: 150 + index,
    });
    registered.add(focusId);
  });
}

function registerOrderedButton(
  focusRegistry: FocusRegistry,
  registered: Set<string>,
  button: HTMLButtonElement,
  order: number,
): void {
  const route = readClosestRouteId(button);
  const focusId = button.dataset.focusId;
  if (route === null || focusId === undefined) {
    return;
  }
  focusRegistry.register({ id: focusId, route, order });
  registered.add(focusId);
}

function plexActionFocusOrder(button: HTMLButtonElement, index: number): number {
  if (readClosestRouteId(button) !== 'channelSetup') {
    return index;
  }
  return button.dataset.plexAction === 'clearMetadata' ? 140 + index : index;
}

function focusElementOrder(focusId: string, index: number): number {
  if (focusId.startsWith('plex-dyn-section-')) {
    return 35 + index / 1000;
  }
  if (focusId.startsWith('plex-dyn-item-')) {
    return 150 + index / 1000;
  }
  if (focusId.startsWith('custom-channel-')) {
    return 170 + index / 1000;
  }
  if (focusId.startsWith('custom-media-')) {
    return 180 + index / 1000;
  }
  if (focusId.startsWith('custom-draft-')) {
    return 190 + index / 1000;
  }
  return 220 + index;
}

export function moveRendererFocus(
  focusRegistry: FocusRegistry,
  focusState: FocusState,
  direction: FocusDirection,
  dom: RendererDomBindings,
): FocusState {
  const result = focusRegistry.move(focusState, direction);
  if (result.changed) {
    renderRendererFocus(result.state, dom);
  }
  return result.state;
}

export function focusRendererTarget(
  focusRegistry: FocusRegistry,
  focusState: FocusState,
  focusId: string,
  dom: RendererDomBindings,
): FocusState {
  const result = focusRegistry.focusTarget(focusState, focusId);
  if (result.changed) {
    renderRendererFocus(result.state, dom);
  }
  return result.state;
}

export function renderRendererFocus(focusState: FocusState, dom: RendererDomBindings): void {
  for (const element of dom.focusableElements) {
    const isActive = element.dataset.focusId === focusState.activeId;
    const isPrimaryRouteButton = readRouteId(element.dataset.routeButton) !== null;
    const isHiddenFromRoute = element.closest('[hidden], [aria-hidden="true"]') !== null;
    element.classList.toggle('is-focused', isActive);
    element.tabIndex = !isHiddenFromRoute && (isActive || isPrimaryRouteButton) ? 0 : -1;
    if (isActive && !isHiddenFromRoute && document.activeElement !== element) {
      element.focus({ preventScroll: true });
    }
  }
}

export function clickFocusedRendererElement(
  focusState: FocusState,
  dom: RendererDomBindings,
): void {
  const activeElement = dom.focusableElements.find(
    (element) => element.dataset.focusId === focusState.activeId,
  );
  if (activeElement instanceof HTMLButtonElement) {
    activeElement.click();
  }
}

function readCurrentFocusableElements(dom: RendererDomBindings): HTMLElement[] {
  if (typeof document !== 'undefined' && typeof document.querySelectorAll === 'function') {
    return Array.from(document.querySelectorAll<HTMLElement>('[data-focus-id]')).filter((el) => {
      const modal = el.closest('.profile-pin-modal');
      if (modal) {
        return !modal.hasAttribute('hidden') && modal.getAttribute('aria-hidden') !== 'true';
      }
      return true;
    });
  }

  const dynamicPlexElements =
    [
      dom.plexPanelElement,
      dom.plexHomeUsersElement,
      dom.plexServersElement,
      dom.plexSectionsElement,
      dom.plexItemsElement,
      dom.customChannelPanelElement,
    ].flatMap((element) => (
      element == null || typeof element.querySelectorAll !== 'function'
        ? []
        : Array.from(element.querySelectorAll<HTMLElement>('[data-focus-id]'))
    ));
  return [
    ...new Set([
      ...dom.focusableElements.filter((element) => !isDynamicFocusId(element.dataset.focusId)),
      ...dynamicPlexElements,
    ]),
  ];
}

function isDynamicFocusId(focusId: string | undefined): focusId is string {
  return (
    focusId !== undefined
    && (
      focusId.startsWith('plex-dyn-home-')
      || focusId.startsWith('plex-dyn-server-')
      || focusId.startsWith('plex-dyn-section-')
      || focusId.startsWith('plex-dyn-item-')
      || focusId.startsWith('custom-channel-')
      || focusId.startsWith('custom-media-')
      || focusId.startsWith('custom-draft-')
    )
  );
}

function getNumpadNeighbors(focusId: string): Partial<Record<FocusDirection, string>> {
  const mapping: Record<string, Record<FocusDirection, string>> = {
    'numpad-1': { up: 'numpad-clear', down: 'numpad-4', left: 'numpad-3', right: 'numpad-2' },
    'numpad-2': { up: 'numpad-0', down: 'numpad-5', left: 'numpad-1', right: 'numpad-3' },
    'numpad-3': { up: 'numpad-cancel', down: 'numpad-6', left: 'numpad-2', right: 'numpad-1' },
    'numpad-4': { up: 'numpad-1', down: 'numpad-7', left: 'numpad-6', right: 'numpad-5' },
    'numpad-5': { up: 'numpad-2', down: 'numpad-8', left: 'numpad-4', right: 'numpad-6' },
    'numpad-6': { up: 'numpad-3', down: 'numpad-9', left: 'numpad-5', right: 'numpad-4' },
    'numpad-7': { up: 'numpad-4', down: 'numpad-clear', left: 'numpad-9', right: 'numpad-8' },
    'numpad-8': { up: 'numpad-5', down: 'numpad-0', left: 'numpad-7', right: 'numpad-9' },
    'numpad-9': { up: 'numpad-6', down: 'numpad-cancel', left: 'numpad-8', right: 'numpad-7' },
    'numpad-clear': { up: 'numpad-7', down: 'numpad-1', left: 'numpad-cancel', right: 'numpad-0' },
    'numpad-0': { up: 'numpad-8', down: 'numpad-2', left: 'numpad-clear', right: 'numpad-cancel' },
    'numpad-cancel': { up: 'numpad-9', down: 'numpad-3', left: 'numpad-0', right: 'numpad-clear' },
  };
  return mapping[focusId] ?? {};
}

function getSettingsNeighbors(focusId: string): Partial<Record<FocusDirection, string>> | undefined {
  switch (focusId) {
    case 'settings-cat-playback':
      return { right: 'settings-launch-mode', down: 'settings-cat-guide' };
    case 'settings-cat-guide':
      return { right: 'settings-guide-density', up: 'settings-cat-playback', down: 'settings-cat-setup' };
    case 'settings-cat-setup':
      return { right: 'settings-support-bundle', up: 'settings-cat-guide', down: 'settings-setup' };
    case 'settings-setup':
      return { up: 'settings-cat-setup', down: 'settings-player' };
    case 'settings-player':
      return { up: 'settings-setup' };
    case 'settings-launch-mode':
      return { left: 'settings-cat-playback', down: 'settings-preview-badges' };
    case 'settings-preview-badges':
      return { left: 'settings-cat-playback', up: 'settings-launch-mode' };
    case 'settings-guide-density':
      return { left: 'settings-cat-guide', down: 'settings-setup-reminder' };
    case 'settings-setup-reminder':
      return { left: 'settings-cat-guide', up: 'settings-guide-density' };
    case 'settings-support-bundle':
      return { left: 'settings-cat-setup' };
    default:
      return undefined;
  }
}

