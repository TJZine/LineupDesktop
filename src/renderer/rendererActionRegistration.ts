import {
  readChannelCommitActionId,
  readChannelSetupActionId,
  readEpgActionId,
  readOverlayActionId,
  readPlexRuntimeActionId,
  readRouteActionId,
  readRouteId,
  readSettingsActionId,
  type RendererDomBindings,
} from './domBindings.js';
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
  setPlexHomeUserPin(value: string): void;
  setPlexSearchQuery(value: string): void;
  selectPlexHomeUser(homeUserId: string): void;
  selectPlexServer(serverId: string): void;
  selectPlexSection(sectionId: string): void;
  openPlexMetadata(ratingKey: string): void;
  focusElement(element: HTMLElement): void;
  toggleFullscreen(): void;
  selectAudioTrack(trackId: string): void;
  selectSubtitleTrack(trackId: string | null): void;
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
  for (const button of dom.settingsActionButtons) {
    button.addEventListener('click', () => {
      const action = readSettingsActionId(button.dataset.settingsAction);
      if (action !== null) handlers.applySettingsAction(action);
    });
  }
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
  dom.plexPanelElement?.addEventListener('click', (event) => {
    if (!(event.target instanceof HTMLElement)) return;
    const homeUserId = readClosestPlexId(event.target, '[data-plex-home-user-id]', readPlexHomeUserId);
    const serverId = readClosestPlexId(event.target, '[data-plex-server-id]', readPlexServerId);
    const sectionId = readClosestPlexId(event.target, '[data-plex-section-id]', readPlexSectionId);
    const ratingKey = readClosestPlexId(event.target, '[data-plex-rating-key]', readPlexRatingKey);

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

function readClosestPlexId(
  target: HTMLElement,
  selector: string,
  read: (element: HTMLElement) => string | null,
): string | null {
  const element = target.closest<HTMLElement>(selector);
  return element === null ? null : read(element);
}
