import {
  readChannelCommitActionId,
  readChannelSetupActionId,
  readCustomChannelActionId,
  readEpgActionId,
  readOverlayActionId,
  readPlexRuntimeActionId,
  readRouteActionId,
  readRouteId,
  readSettingsActionId,
  readStagedSetupFlowActionId,
  type RendererDomBindings,
} from './domBindings.js';
import type { StagedSetupFlowActionId } from './setup/stagedSetupController.js';
import {
  readPlexHomeUserId,
  readPlexRatingKey,
  readPlexSectionId,
  readPlexServerId,
} from './plexRuntimeDom.js';

export interface RendererActionHandlers {
  activateRoute(route: NonNullable<ReturnType<typeof readRouteId>>): void;
  applyRouteAction(action: NonNullable<ReturnType<typeof readRouteActionId>>): void;
  applySettingsAction(action: NonNullable<ReturnType<typeof readSettingsActionId>>): void;
  applyChannelSetupAction(action: NonNullable<ReturnType<typeof readChannelSetupActionId>>): void;
  applyChannelCommitAction(action: NonNullable<ReturnType<typeof readChannelCommitActionId>>): void;
  applyEpgAction(action: NonNullable<ReturnType<typeof readEpgActionId>>): void;
  applyOverlayAction(action: NonNullable<ReturnType<typeof readOverlayActionId>>): void;
  applyPlexRuntimeAction(action: NonNullable<ReturnType<typeof readPlexRuntimeActionId>>): void;
  applyCustomChannelAction?(action: NonNullable<ReturnType<typeof readCustomChannelActionId>>, detail?: string): void;
  setPlexHomeUserPin(value: string): void;
  setPlexSearchQuery(value: string): void;
  setCustomChannelName?(value: string): void;
  setCustomChannelNumber?(value: string): void;
  setCustomChannelSearchQuery?(value: string): void;
  selectPlexHomeUser(homeUserId: string): void;
  selectPlexServer(serverId: string): void;
  selectPlexSection(sectionId: string): void;
  openPlexMetadata(ratingKey: string): void;
  focusElement(element: HTMLElement): void;
  toggleFullscreen(): void;
  selectAudioTrack(trackId: string): void;
  selectSubtitleTrack(trackId: string | null): void;
  applySettingsCategory?(category: string): void;
  applySetupStage?(stage: string): void;
  applyStagedSetupAction?(action: StagedSetupFlowActionId): void;
}

export function registerRendererActions(
  dom: RendererDomBindings,
  documentRef: Document,
  handlers: RendererActionHandlers,
): void {
  for (const button of dom.routeButtons) {
    button.addEventListener('click', () => {
      const route = readRouteId(button.dataset.routeButton);
      if (route !== null) handlers.activateRoute(route);
    });
  }
  for (const button of dom.routeActionButtons) {
    button.addEventListener('click', () => {
      const action = readRouteActionId(button.dataset.routeAction);
      if (action !== null) handlers.applyRouteAction(action);
    });
  }
  const settingsScreen = documentRef.getElementById('screen-settings');
  settingsScreen?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const button = event.target.closest<HTMLButtonElement>('[data-settings-action]');
    const action = readSettingsActionId(button?.dataset.settingsAction);
    if (action !== null) {
      handlers.applySettingsAction(action);
      return;
    }
    const catButton = event.target.closest<HTMLButtonElement>('[data-settings-category]');
    const category = catButton?.dataset.settingsCategory;
    if (category) {
      handlers.applySettingsCategory?.(category);
    }
  });
  const setupScreen = documentRef.getElementById('screen-channel-setup');
  setupScreen?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const customButton = event.target.closest<HTMLButtonElement>('[data-custom-channel-action]');
    const customAction = readCustomChannelActionId(customButton?.dataset.customChannelAction);
    if (customAction !== null && customButton !== null && isEligibleDelegatedAction(customButton) && isActiveStagedAction(customButton)) {
      handlers.applyCustomChannelAction?.(customAction, customButton.dataset.customChannelDetail);
      return;
    }
    const flowButton = event.target.closest<HTMLButtonElement>('[data-setup-flow-action]');
    const flowAction = readStagedSetupFlowActionId(flowButton?.dataset.setupFlowAction);
    if (flowAction !== null && flowButton !== null && isEligibleDelegatedAction(flowButton)) {
      handlers.applyStagedSetupAction?.(flowAction);
      return;
    }
    const catButton = event.target.closest<HTMLButtonElement>('[data-setup-stage]');
    const stage = catButton?.dataset.setupStage;
    if (stage && catButton !== null && isEligibleDelegatedAction(catButton)) {
      handlers.applySetupStage?.(stage);
    }
  });
  for (const button of dom.setupActionButtons) {
    button.addEventListener('click', () => {
      const action = readChannelSetupActionId(button.dataset.setupAction);
      if (action !== null) handlers.applyChannelSetupAction(action);
    });
  }
  dom.channelSetupStrategyElement?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const button = event.target.closest<HTMLButtonElement>('[data-setup-action]');
    const action = readChannelSetupActionId(button?.dataset.setupAction);
    if (action !== null) handlers.applyChannelSetupAction(action);
  });
  for (const button of dom.channelCommitButtons) {
    button.addEventListener('click', () => {
      const action = readChannelCommitActionId(button.dataset.channelCommitAction);
      if (action !== null) handlers.applyChannelCommitAction(action);
    });
  }
  for (const button of dom.epgActionButtons) {
    button.addEventListener('click', () => {
      const action = readEpgActionId(button.dataset.epgAction);
      if (action !== null) handlers.applyEpgAction(action);
    });
  }
  for (const button of dom.overlayActionButtons) {
    button.addEventListener('click', () => {
      const action = readOverlayActionId(button.dataset.overlayAction);
      if (action !== null) handlers.applyOverlayAction(action);
    });
  }
  for (const button of dom.plexActionButtons) {
    button.addEventListener('click', () => {
      const action = readPlexRuntimeActionId(button.dataset.plexAction);
      if (action !== null) handlers.applyPlexRuntimeAction(action);
    });
  }
  dom.plexHomeUserPinInput?.addEventListener('input', () => {
    handlers.setPlexHomeUserPin(dom.plexHomeUserPinInput?.value ?? '');
  });
  dom.plexSearchQueryInput?.addEventListener('input', () => {
    handlers.setPlexSearchQuery(dom.plexSearchQueryInput?.value ?? '');
  });
  dom.customChannelNameInput?.addEventListener('input', () => {
    handlers.setCustomChannelName?.(dom.customChannelNameInput?.value ?? '');
  });
  dom.customChannelNumberInput?.addEventListener('input', () => {
    handlers.setCustomChannelNumber?.(dom.customChannelNumberInput?.value ?? '');
  });
  dom.customChannelSearchInput?.addEventListener('input', () => {
    handlers.setCustomChannelSearchQuery?.(dom.customChannelSearchInput?.value ?? '');
  });
  dom.plexPanelElement?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const homeUserId = readClosestPlexId(event.target, '[data-plex-home-user-id]', readPlexHomeUserId);
    const serverId = readClosestPlexId(event.target, '[data-plex-server-id]', readPlexServerId);
    const sectionId = readClosestPlexId(event.target, '[data-plex-section-id]', readPlexSectionId);
    const ratingKey = readClosestPlexId(event.target, '[data-plex-rating-key]', readPlexRatingKey);

    const plexButton = event.target.closest<HTMLElement>('[data-plex-home-user-id],[data-plex-server-id],[data-plex-section-id],[data-plex-rating-key]');
    if (plexButton !== null && !isEligibleDelegatedAction(plexButton)) return;
    if (homeUserId !== null) handlers.selectPlexHomeUser(homeUserId);
    else if (serverId !== null) handlers.selectPlexServer(serverId);
    else if (sectionId !== null) handlers.selectPlexSection(sectionId);
    else if (ratingKey !== null) handlers.openPlexMetadata(ratingKey);
  });
  documentRef.addEventListener('focusin', (event) => {
    if (event.target instanceof HTMLElement) handlers.focusElement(event.target);
  });
  dom.fullscreenButton?.addEventListener('click', () => {
    handlers.toggleFullscreen();
  });
  dom.overlayAudioOptionsElement?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const button = event.target.closest<HTMLButtonElement>('.playback-options__row');
    if (button && button.dataset.trackId) {
      handlers.selectAudioTrack(button.dataset.trackId);
    }
  });
  dom.overlaySubtitleOptionsElement?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const button = event.target.closest<HTMLButtonElement>('.playback-options__row');
    if (button) {
      const trackId = button.dataset.trackId;
      handlers.selectSubtitleTrack(trackId === 'subtitles-off' || !trackId ? null : trackId);
    }
  });
}

function isActiveStagedAction(button: HTMLButtonElement): boolean {
  return button.closest<HTMLElement>('[data-staged-owner]')?.dataset.ownerActive === 'true';
}

function isEligibleDelegatedAction(element: HTMLElement): boolean {
  if ((element as HTMLButtonElement).disabled || element.getAttribute('aria-disabled') === 'true') return false;
  return element.closest('[hidden],[inert],[aria-hidden="true"]') === null;
}

function readClosestPlexId(
  target: HTMLElement,
  selector: string,
  read: (element: HTMLElement) => string | null,
): string | null {
  const element = target.closest<HTMLElement>(selector);
  if (
    element === null
    || !isEligibleDelegatedAction(element)
  ) {
    return null;
  }
  return read(element);
}
