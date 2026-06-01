import type { RendererDomBindings } from './domBindings.js';
import { readClosestRouteId, readRouteId } from './domBindings.js';
import type {
  FocusRegistry,
  FocusDirection,
  FocusState,
} from './navigation.js';

const dynamicPlexFocusIdsByRegistry = new WeakMap<FocusRegistry, Set<string>>();

export function syncRendererFocusTargets(
  focusRegistry: FocusRegistry,
  dom: RendererDomBindings,
): void {
  const focusableElements = readCurrentFocusableElements(dom);
  const currentDynamicPlexIds = new Set(
    focusableElements
      .map((element) => element.dataset.focusId)
      .filter((focusId): focusId is string => isDynamicPlexFocusId(focusId)),
  );
  const previousDynamicPlexIds = dynamicPlexFocusIdsByRegistry.get(focusRegistry) ?? new Set();
  for (const focusId of previousDynamicPlexIds) {
    if (!currentDynamicPlexIds.has(focusId)) {
      focusRegistry.unregister(focusId);
    }
  }
  dynamicPlexFocusIdsByRegistry.set(focusRegistry, currentDynamicPlexIds);
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
    focusRegistry.register({
      id: focusId,
      route,
      order: focusElementOrder(focusId, index),
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
    return Array.from(document.querySelectorAll<HTMLElement>('[data-focus-id]'));
  }

  const dynamicPlexElements =
    [
      dom.plexPanelElement,
      dom.plexHomeUsersElement,
      dom.plexServersElement,
      dom.plexSectionsElement,
      dom.plexItemsElement,
    ].flatMap((element) => (
      element === null || typeof element.querySelectorAll !== 'function'
        ? []
        : Array.from(element.querySelectorAll<HTMLElement>('[data-focus-id]'))
    ));
  return [
    ...new Set([
      ...dom.focusableElements.filter((element) => !isDynamicPlexFocusId(element.dataset.focusId)),
      ...dynamicPlexElements,
    ]),
  ];
}

function isDynamicPlexFocusId(focusId: string | undefined): focusId is string {
  return (
    focusId !== undefined
    && (
      focusId.startsWith('plex-dyn-home-')
      || focusId.startsWith('plex-dyn-server-')
      || focusId.startsWith('plex-dyn-section-')
      || focusId.startsWith('plex-dyn-item-')
    )
  );
}
