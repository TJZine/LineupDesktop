import type { RendererDomBindings } from './domBindings.js';
import { readClosestRouteId } from './domBindings.js';
import type {
  FocusRegistry,
  FocusDirection,
  FocusState,
} from './navigation.js';
import { getStagedSetupNeighbors } from './setup/stagedSetupFocus.js';

const dynamicFocusIdsByRegistry = new WeakMap<FocusRegistry, Set<string>>();
const focusIdsByRegistry = new WeakMap<FocusRegistry, Set<string>>();

export function syncRendererFocusTargets(
  focusRegistry: FocusRegistry,
  dom: RendererDomBindings,
): void {
  const focusableElements = readCurrentFocusableElements(dom);
  const currentFocusIds = new Set(
    focusableElements
      .map((element) => element.dataset.focusId)
      .filter((focusId): focusId is string => focusId !== undefined),
  );
  const previousFocusIds = focusIdsByRegistry.get(focusRegistry) ?? new Set();
  for (const focusId of previousFocusIds) {
    if (!currentFocusIds.has(focusId)) {
      focusRegistry.unregister(focusId);
    }
  }
  focusIdsByRegistry.set(focusRegistry, currentFocusIds);
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
  const currentFocusIds = new Set(
    dom.focusableElements
      .filter((element) => !isElementHiddenFromFocus(element))
      .map((element) => element.dataset.focusId)
      .filter((focusId): focusId is string => focusId !== undefined),
  );
  if (dom.fullscreenButton && !isElementHiddenFromFocus(dom.fullscreenButton)) {
    focusRegistry.register({
      id: 'player-fullscreen',
      route: 'player',
      order: 120,
    });
    registered.add('player-fullscreen');
  }

  dom.routeActionButtons.forEach((button, index) => {
    const route = readClosestRouteId(button);
    const focusId = button.dataset.focusId;
    if (route === null || focusId === undefined || isElementHiddenFromFocus(button)) {
      return;
    }
    focusRegistry.register({
      id: focusId,
      route,
      order: 100 + index,
      neighbors: focusId.startsWith('settings-')
        ? getSettingsNeighbors(focusId, currentFocusIds)
        : undefined,
    });
    registered.add(focusId);
  });

  [...dom.epgActionButtons, ...dom.settingsActionButtons, ...dom.setupActionButtons].forEach(
    (button, index) => registerOrderedButton(
      focusRegistry,
      registered,
      button,
      80 + index,
      currentFocusIds,
    ),
  );

  dom.plexActionButtons.forEach((button, index) => {
    registerOrderedButton(
      focusRegistry,
      registered,
      button,
      plexActionFocusOrder(button, index),
      currentFocusIds,
    );
  });

  dom.focusableElements.forEach((element, index) => {
    const focusId = element.dataset.focusId;
    const route = readClosestRouteId(element);
    if (focusId === undefined || registered.has(focusId) || element.dataset.overlayAction !== undefined) {
      return;
    }
    const shellNeighbors = getShellNeighbors(focusId);
    if (route === null && shellNeighbors === null) return;
    const neighbors = focusId.startsWith('btn-profile-pin-')
      ? getNumpadNeighbors(focusId)
      : focusId.startsWith('settings-')
      ? getSettingsNeighbors(focusId, currentFocusIds)
      : focusId.startsWith('setup-') || focusId.startsWith('plex-') || focusId.startsWith('channel-') || focusId.startsWith('custom-') || focusId.startsWith('btn-auth-') || focusId.startsWith('btn-profile-') || focusId.startsWith('btn-server-')
      ? getStagedSetupNeighbors(focusId) ?? getSetupNeighbors(focusId)
      : shellNeighbors ?? undefined;
    focusRegistry.register({
      id: focusId,
      route: route ?? 'player',
      scope: route === null ? 'global' : 'route',
      order: shellFocusOrder(focusId) ?? focusElementOrder(focusId, index),
      neighbors,
    });
    registered.add(focusId);
  });

  dom.overlayActionButtons.forEach((button, index) => {
    const focusId = button.dataset.focusId;
    if (focusId === undefined || isElementHiddenFromFocus(button)) {
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

function getShellNeighbors(focusId: string): Partial<Record<FocusDirection, string>> | null {
  switch (focusId) {
    case 'shell-error-retry':
      return { up: focusId, down: 'shell-error-exit', left: focusId, right: focusId };
    case 'shell-error-exit':
      return { up: 'shell-error-retry', down: focusId, left: focusId, right: focusId };
    case 'shell-inline-dismiss':
      return { up: focusId, down: 'shell-inline-retry', left: focusId, right: focusId };
    case 'shell-inline-retry':
      return { up: 'shell-inline-dismiss', down: focusId, left: focusId, right: focusId };
    case 'exit-confirm-cancel':
      return { up: focusId, down: focusId, left: focusId, right: 'exit-confirm-exit' };
    case 'exit-confirm-exit':
      return { up: focusId, down: focusId, left: 'exit-confirm-cancel', right: focusId };
    default:
      return null;
  }
}

function shellFocusOrder(focusId: string): number | null {
  switch (focusId) {
    case 'shell-error-retry':
    case 'shell-inline-dismiss':
    case 'exit-confirm-cancel':
      return -2;
    case 'shell-error-exit':
    case 'shell-inline-retry':
    case 'exit-confirm-exit':
      return -1;
    default:
      return null;
  }
}

function registerOrderedButton(
  focusRegistry: FocusRegistry,
  registered: Set<string>,
  button: HTMLButtonElement,
  order: number,
  currentFocusIds: ReadonlySet<string>,
): void {
  if (isElementHiddenFromFocus(button)) {
    return;
  }
  const route = readClosestRouteId(button);
  const focusId = button.dataset.focusId;
  if (route === null || focusId === undefined) {
    return;
  }
  focusRegistry.register({
    id: focusId,
    route,
    order,
    neighbors: focusId.startsWith('settings-')
      ? getSettingsNeighbors(focusId, currentFocusIds)
      : undefined,
  });
  registered.add(focusId);
}

function plexActionFocusOrder(button: HTMLButtonElement, index: number): number {
  if (readClosestRouteId(button) !== 'channelSetup') {
    return index;
  }
  const focusId = button.dataset.focusId;
  if (focusId === 'btn-auth-request' || focusId === 'btn-auth-retry') return 0;
  if (focusId === 'btn-auth-cancel') return 1;
  if (focusId === 'btn-server-refresh') return 20;
  return button.dataset.plexAction === 'clearMetadata' ? 140 + index : index;
}

function focusElementOrder(focusId: string, index: number): number {
  if (focusId === 'audio-setup-complete') return 0;
  const settingsCategoryIndex = SETTINGS_CATEGORY_FOCUS_IDS.indexOf(focusId);
  if (settingsCategoryIndex >= 0) return 10 + settingsCategoryIndex;
  if (focusId.startsWith('btn-profile-profile-')) return 10 + index / 1000;
  if (focusId === 'btn-profile-main') return 20;
  if (focusId.startsWith('btn-server-select-server-')) return 10 + index / 1000;
  if (focusId === 'btn-server-setup') return 21;
  if (focusId === 'btn-server-switch-profile') return 22;
  if (focusId.startsWith('btn-profile-pin-')) return 0 + index / 1000;
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
  if (focusId.startsWith('guide-program-')) {
    return 20 + index / 1000;
  }
  if (focusId.startsWith('guide-state-')) {
    return 10 + index / 1000;
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
    const isHiddenFromRoute = isElementHiddenFromFocus(element);
    element.classList.toggle('is-focused', isActive);
    element.tabIndex = !isHiddenFromRoute && isActive ? 0 : -1;
    if (isActive && !isHiddenFromRoute) {
      if (document.activeElement !== element) {
        element.focus({ preventScroll: true });
      }
      if (readClosestRouteId(element) === 'settings') {
        element.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      }
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
    if (!activeElement.disabled && readAriaDisabled(activeElement) !== true) {
      activeElement.click();
    }
    return;
  }
  if (typeof HTMLSelectElement !== 'undefined' && activeElement instanceof HTMLSelectElement) {
    if (activeElement.disabled || readAriaDisabled(activeElement)) return;
    const options = Array.from(activeElement.options).filter((option) => !option.disabled);
    if (options.length === 0) return;
    const currentIndex = options.findIndex((option) => option.value === activeElement.value);
    activeElement.value = options[(currentIndex + 1) % options.length]?.value ?? activeElement.value;
    activeElement.dispatchEvent(new Event('change', { bubbles: true }));
  }
}

function readCurrentFocusableElements(dom: RendererDomBindings): HTMLElement[] {
  if (typeof document !== 'undefined' && typeof document.querySelectorAll === 'function') {
    return Array.from(document.querySelectorAll<HTMLElement>('[data-focus-id]')).filter((el) => {
      const modal = el.closest('.profile-pin-modal');
      if (modal) {
        return !modal.hasAttribute('hidden') && modal.getAttribute('aria-hidden') !== 'true';
      }
      return !isElementHiddenFromFocus(el);
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

function isElementHiddenFromFocus(element: HTMLElement): boolean {
  return element.closest('[hidden], [inert], [aria-hidden="true"]') !== null
    || (element as HTMLButtonElement).disabled === true
    || (readAriaDisabled(element) && !hasBusyFocusCustody(element));
}

function readAriaDisabled(element: HTMLElement): boolean {
  return typeof element.getAttribute === 'function' && element.getAttribute('aria-disabled') === 'true';
}

function hasBusyFocusCustody(element: HTMLElement): boolean {
  return element.dataset.overlayBusyFocusCustody === 'true'
    && element.getAttribute('aria-busy') === 'true';
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
      || focusId.startsWith('guide-program-')
      || focusId.startsWith('guide-state-')
      || focusId.startsWith('overlay-mini-channel-')
      || focusId.startsWith('overlay-audio-track-')
      || focusId.startsWith('overlay-subtitle-track-')
    )
  );
}

function getNumpadNeighbors(focusId: string): Partial<Record<FocusDirection, string>> {
  const mapping: Record<string, Record<FocusDirection, string>> = {
    'btn-profile-pin-1': { up: 'btn-profile-pin-1', down: 'btn-profile-pin-4', left: 'btn-profile-pin-1', right: 'btn-profile-pin-2' },
    'btn-profile-pin-2': { up: 'btn-profile-pin-2', down: 'btn-profile-pin-5', left: 'btn-profile-pin-1', right: 'btn-profile-pin-3' },
    'btn-profile-pin-3': { up: 'btn-profile-pin-3', down: 'btn-profile-pin-6', left: 'btn-profile-pin-2', right: 'btn-profile-pin-3' },
    'btn-profile-pin-4': { up: 'btn-profile-pin-1', down: 'btn-profile-pin-7', left: 'btn-profile-pin-4', right: 'btn-profile-pin-5' },
    'btn-profile-pin-5': { up: 'btn-profile-pin-2', down: 'btn-profile-pin-8', left: 'btn-profile-pin-4', right: 'btn-profile-pin-6' },
    'btn-profile-pin-6': { up: 'btn-profile-pin-3', down: 'btn-profile-pin-9', left: 'btn-profile-pin-5', right: 'btn-profile-pin-6' },
    'btn-profile-pin-7': { up: 'btn-profile-pin-4', down: 'btn-profile-pin-backspace', left: 'btn-profile-pin-7', right: 'btn-profile-pin-8' },
    'btn-profile-pin-8': { up: 'btn-profile-pin-5', down: 'btn-profile-pin-0', left: 'btn-profile-pin-7', right: 'btn-profile-pin-9' },
    'btn-profile-pin-9': { up: 'btn-profile-pin-6', down: 'btn-profile-pin-cancel', left: 'btn-profile-pin-8', right: 'btn-profile-pin-9' },
    'btn-profile-pin-backspace': { up: 'btn-profile-pin-7', down: 'btn-profile-pin-backspace', left: 'btn-profile-pin-backspace', right: 'btn-profile-pin-0' },
    'btn-profile-pin-0': { up: 'btn-profile-pin-8', down: 'btn-profile-pin-0', left: 'btn-profile-pin-backspace', right: 'btn-profile-pin-cancel' },
    'btn-profile-pin-cancel': { up: 'btn-profile-pin-9', down: 'btn-profile-pin-cancel', left: 'btn-profile-pin-0', right: 'btn-profile-pin-cancel' },
  };
  return mapping[focusId] ?? {};
}

function getSettingsNeighbors(
  focusId: string,
  currentFocusIds: ReadonlySet<string>,
): Partial<Record<FocusDirection, string>> | undefined {
  const categoryIndex = SETTINGS_CATEGORY_FOCUS_IDS.indexOf(focusId);
  if (categoryIndex >= 0) {
    const detailTarget = SETTINGS_CONTROL_CATEGORY
      .get(focusId)
      ?.find((controlId) => currentFocusIds.has(controlId));
    return {
      up: SETTINGS_CATEGORY_FOCUS_IDS[Math.max(0, categoryIndex - 1)],
      down: categoryIndex === SETTINGS_CATEGORY_FOCUS_IDS.length - 1
        ? 'settings-switch-profile'
        : SETTINGS_CATEGORY_FOCUS_IDS[categoryIndex + 1],
      right: detailTarget ?? focusId,
    };
  }
  const owner = findSettingsControlCategory(focusId);
  if (owner !== undefined) return { left: owner };
  switch (focusId) {
    case 'settings-switch-profile':
      return { up: 'settings-category-recovery', down: 'settings-open-channel-setup' };
    case 'settings-open-channel-setup':
      return { up: 'settings-switch-profile', down: 'settings-player' };
    case 'settings-player':
      return { up: 'settings-open-channel-setup' };
    default:
      return undefined;
  }
}

const SETTINGS_CATEGORY_FOCUS_IDS: readonly string[] = [
  'settings-category-audio-subtitles',
  'settings-category-playback-hdr',
  'settings-category-appearance',
  'settings-category-guide',
  'settings-category-account',
  'settings-category-developer',
  'settings-category-recovery',
];

const SETTINGS_CONTROL_CATEGORY = new Map<string, readonly string[]>([
  ['settings-category-audio-subtitles', ['settings-audio-output', 'settings-dts-passthrough', 'settings-direct-play-audio-fallback', 'settings-subtitle-mode', 'settings-preferred-subtitle-language', 'settings-prefer-forced-subtitles']],
  ['settings-category-playback-hdr', ['settings-keep-playback-running', 'settings-hdr-fallback', 'settings-transcode-quality', 'settings-transcode-compatibility']],
  ['settings-category-appearance', ['settings-launch-mode', 'settings-info-box-background', 'settings-theme', 'settings-cinematic-now-playing', 'settings-prefer-clear-logos', 'settings-now-playing-auto-hide', 'settings-preview-badges']],
  ['settings-category-account', ['settings-profile-picker-startup']],
  ['settings-category-developer', ['settings-debug-logging', 'settings-subtitle-debug-logging', 'settings-support-bundle-export']],
  ['settings-category-recovery', ['settings-setup-reminder']],
]);

function findSettingsControlCategory(focusId: string): string | undefined {
  for (const [category, controls] of SETTINGS_CONTROL_CATEGORY) {
    if (controls.includes(focusId)) return category;
  }
  return undefined;
}

function getSetupNeighbors(focusId: string): Partial<Record<FocusDirection, string>> | undefined {
  if (focusId === 'btn-auth-request' || focusId === 'btn-auth-cancel') return { up: focusId, down: focusId, left: focusId, right: focusId };
  if (focusId === 'btn-auth-retry') return { up: focusId, down: 'btn-auth-cancel', left: focusId, right: focusId };
  if (focusId.startsWith('btn-profile-profile-')) return { up: focusId, down: 'btn-profile-main', left: focusId, right: focusId };
  if (focusId === 'btn-profile-main') return { up: 'btn-profile-profile-1', down: focusId, left: focusId, right: focusId };
  if (focusId.startsWith('btn-server-select-server-')) return { up: focusId, down: 'btn-server-refresh', left: focusId, right: focusId };
  if (focusId === 'btn-server-refresh') return { up: 'btn-server-select-server-1', down: 'btn-server-setup', left: focusId, right: focusId };
  if (focusId === 'btn-server-setup') return { up: 'btn-server-refresh', down: 'btn-server-switch-profile', left: focusId, right: focusId };
  if (focusId === 'btn-server-switch-profile') return { up: 'btn-server-setup', down: focusId, left: focusId, right: focusId };
  if (focusId.startsWith('plex-dyn-home-')) return { left: 'setup-stage-account' };
  if (focusId.startsWith('plex-dyn-server-')) return { left: 'setup-stage-server' };
  if (focusId.startsWith('plex-dyn-section-') || focusId.startsWith('plex-dyn-item-')) return { left: 'setup-stage-library' };
  if (focusId.startsWith('custom-channel-') || focusId.startsWith('custom-media-') || focusId.startsWith('custom-draft-')) return { left: 'setup-stage-custom' };

  switch (focusId) {
    case 'setup-stage-account':
      return { right: 'plex-load', down: 'setup-stage-server' };
    case 'setup-stage-server':
      return { right: 'plex-restore-server', up: 'setup-stage-account', down: 'setup-stage-library' };
    case 'setup-stage-library':
      return { right: 'plex-list-sections', up: 'setup-stage-server', down: 'setup-stage-preview' };
    case 'setup-stage-preview':
      return { right: 'plex-clear-metadata', up: 'setup-stage-library', down: 'setup-stage-build' };
    case 'setup-stage-build':
      return { right: 'channel-append', up: 'setup-stage-preview', down: 'setup-stage-custom' };
    case 'setup-stage-custom':
      return { right: 'custom-channel-refresh', up: 'setup-stage-build', down: 'setup-settings' };
    case 'setup-settings':
      return { up: 'setup-stage-custom', down: 'setup-player' };
    case 'setup-player':
      return { up: 'setup-settings' };

    case 'plex-load':
    case 'plex-request-pin':
    case 'plex-poll-pin':
    case 'plex-cancel-pin':
    case 'plex-clear-pin':
    case 'plex-home-pin':
    case 'plex-home-users':
      return { left: 'setup-stage-account' };

    case 'plex-restore-server':
    case 'plex-refresh-servers':
    case 'plex-clear-server':
      return { left: 'setup-stage-server' };

    case 'plex-list-sections':
    case 'plex-clear-section':
    case 'plex-list-items':
    case 'plex-clear-items':
    case 'plex-search-query':
    case 'plex-search':
    case 'plex-clear-search':
      return { left: 'setup-stage-library' };

    case 'plex-clear-metadata':
      return { left: 'setup-stage-preview' };

    case 'channel-append':
    case 'channel-replace':
    case 'channel-confirm-replace':
      return { left: 'setup-stage-build' };

    case 'custom-channel-refresh':
    case 'custom-channel-search-query':
    case 'custom-channel-browse':
    case 'custom-channel-search':
    case 'custom-channel-clear-search':
    case 'custom-channel-filter-all':
    case 'custom-channel-filter-movies':
    case 'custom-channel-filter-episodes':
    case 'custom-channel-name':
    case 'custom-channel-number':
    case 'custom-channel-hidden':
    case 'custom-channel-save':
      return { left: 'setup-stage-custom' };

    default:
      return undefined;
  }
}
