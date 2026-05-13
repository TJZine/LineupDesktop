import type { RendererDomBindings } from './domBindings.js';
import { readClosestRouteId, readRouteId } from './domBindings.js';
import type {
  FocusRegistry,
  FocusDirection,
  FocusState,
} from './navigation.js';

export function registerRendererFocusTargets(
  focusRegistry: FocusRegistry,
  dom: RendererDomBindings,
): void {
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
      neighbors: { right: focusId === 'nav-player' ? 'player-fullscreen' : undefined },
    });
  });

  if (dom.fullscreenButton) {
    focusRegistry.register({
      id: 'player-fullscreen',
      route: 'player',
      order: 120,
      neighbors: { up: 'nav-player', left: 'nav-player' },
    });
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
  });

  [...dom.epgActionButtons, ...dom.settingsActionButtons, ...dom.setupActionButtons].forEach(
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
  });
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
