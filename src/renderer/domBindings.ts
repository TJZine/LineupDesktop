import type { AppRouteId } from './navigation.js';
import type {
  ChannelSetupActionId,
  EpgActionId,
  RouteWorkflowActionId,
  SettingsActionId,
} from './workflow.js';
import type { PlayerOverlayActionId } from './overlays.js';

export interface RendererDomBindings {
  statusElement: HTMLElement | null;
  capabilitiesElement: HTMLElement | null;
  fullscreenButton: HTMLButtonElement | null;
  routeTitleElement: HTMLElement | null;
  routeStatusElement: HTMLElement | null;
  routeButtons: HTMLButtonElement[];
  routeActionButtons: HTMLButtonElement[];
  settingsActionButtons: HTMLButtonElement[];
  setupActionButtons: HTMLButtonElement[];
  channelCommitButtons: HTMLButtonElement[];
  epgActionButtons: HTMLButtonElement[];
  overlayActionButtons: HTMLButtonElement[];
  screens: HTMLElement[];
  focusableElements: HTMLElement[];
  currentChannelElement: HTMLElement | null;
  currentProgramElement: HTMLElement | null;
  currentWindowElement: HTMLElement | null;
  channelListElement: HTMLElement | null;
  epgGridElement: HTMLElement | null;
  epgDetailChannelElement: HTMLElement | null;
  epgDetailTitleElement: HTMLElement | null;
  epgDetailTimeElement: HTMLElement | null;
  settingsSourceElement: HTMLElement | null;
  settingsChannelsElement: HTMLElement | null;
  settingsStateElement: HTMLElement | null;
  settingsSectionsElement: HTMLElement | null;
  channelSetupSourceElement: HTMLElement | null;
  channelSetupEnabledElement: HTMLElement | null;
  channelSetupBlocksElement: HTMLElement | null;
  setupStepsElement: HTMLElement | null;
  channelDraftListElement: HTMLElement | null;
  channelSetupStrategyElement: HTMLElement | null;
  channelSetupReviewElement: HTMLElement | null;
  setupValidationElement: HTMLElement | null;
  channelSetupResultElement: HTMLElement | null;
  channelSetupFixtureStatusElement: HTMLElement | null;
  plexPanelElement: HTMLElement | null;
  plexActionButtons: HTMLButtonElement[];
  plexStatusElement: HTMLElement | null;
  plexErrorElement: HTMLElement | null;
  plexAccountStateElement: HTMLElement | null;
  plexServerStateElement: HTMLElement | null;
  plexLibraryStateElement: HTMLElement | null;
  plexPinElement: HTMLElement | null;
  plexHomeUserPinInput: HTMLInputElement | null;
  plexSearchQueryInput: HTMLInputElement | null;
  plexHomeUsersElement: HTMLElement | null;
  plexServersElement: HTMLElement | null;
  plexSectionsElement: HTMLElement | null;
  plexItemsElement: HTMLElement | null;
  plexMetadataElement: HTMLElement | null;
  overlayElements: HTMLElement[];
  overlayStackElement: HTMLElement | null;
  overlayNowPlayingTitleElement: HTMLElement | null;
  overlayNowPlayingSubtitleElement: HTMLElement | null;
  overlayNowPlayingChannelElement: HTMLElement | null;
  overlayNowPlayingStatusElement: HTMLElement | null;
  overlayProgressElement: HTMLElement | null;
  overlayMiniGuideElement: HTMLElement | null;
  overlayChannelNumberElement: HTMLElement | null;
  overlayChannelBadgeNumberElement: HTMLElement | null;
  overlayChannelBadgeNameElement: HTMLElement | null;
  overlayChannelBadgeProgramElement: HTMLElement | null;
  overlayAudioLabelElement: HTMLElement | null;
  overlaySubtitleLabelElement: HTMLElement | null;
  overlayVolumeLabelElement: HTMLElement | null;
  overlayRateLabelElement: HTMLElement | null;
  overlayPlaybackSummaryElement: HTMLElement | null;
  overlayAudioOptionsElement: HTMLElement | null;
  overlaySubtitleOptionsElement: HTMLElement | null;
}

export function queryRendererDom(documentRef: Document = document): RendererDomBindings {
  return {
    statusElement: documentRef.querySelector<HTMLElement>('[data-shell-status]'),
    capabilitiesElement: documentRef.querySelector<HTMLElement>('[data-shell-capabilities]'),
    fullscreenButton: documentRef.querySelector<HTMLButtonElement>('[data-fullscreen-toggle]'),
    routeTitleElement: documentRef.querySelector<HTMLElement>('[data-route-title]'),
    routeStatusElement: documentRef.querySelector<HTMLElement>('[data-route-status]'),
    routeButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-route-button]'),
    ),
    routeActionButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-route-action]'),
    ),
    settingsActionButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-settings-action]'),
    ),
    setupActionButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-setup-action]'),
    ),
    channelCommitButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-channel-commit-action]'),
    ),
    epgActionButtons: Array.from(documentRef.querySelectorAll<HTMLButtonElement>('[data-epg-action]')),
    overlayActionButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-overlay-action]'),
    ),
    screens: Array.from(documentRef.querySelectorAll<HTMLElement>('[data-screen]')),
    focusableElements: Array.from(documentRef.querySelectorAll<HTMLElement>('[data-focus-id]')),
    currentChannelElement: documentRef.querySelector<HTMLElement>('[data-current-channel]'),
    currentProgramElement: documentRef.querySelector<HTMLElement>('[data-current-program]'),
    currentWindowElement: documentRef.querySelector<HTMLElement>('[data-current-window]'),
    channelListElement: documentRef.querySelector<HTMLElement>('[data-channel-list]'),
    epgGridElement: documentRef.querySelector<HTMLElement>('[data-epg-grid]'),
    epgDetailChannelElement: documentRef.querySelector<HTMLElement>('[data-epg-detail-channel]'),
    epgDetailTitleElement: documentRef.querySelector<HTMLElement>('[data-epg-detail-title]'),
    epgDetailTimeElement: documentRef.querySelector<HTMLElement>('[data-epg-detail-time]'),
    settingsSourceElement: documentRef.querySelector<HTMLElement>('[data-settings-source]'),
    settingsChannelsElement: documentRef.querySelector<HTMLElement>('[data-settings-channels]'),
    settingsStateElement: documentRef.querySelector<HTMLElement>('[data-settings-state]'),
    settingsSectionsElement: documentRef.querySelector<HTMLElement>('[data-settings-sections]'),
    channelSetupSourceElement: documentRef.querySelector<HTMLElement>('[data-channel-setup-source]'),
    channelSetupEnabledElement: documentRef.querySelector<HTMLElement>(
      '[data-channel-setup-enabled]',
    ),
    channelSetupBlocksElement: documentRef.querySelector<HTMLElement>(
      '[data-channel-setup-blocks]',
    ),
    setupStepsElement: documentRef.querySelector<HTMLElement>('[data-channel-review-steps]'),
    channelDraftListElement: documentRef.querySelector<HTMLElement>('[data-channel-review-list]'),
    channelSetupStrategyElement: documentRef.querySelector<HTMLElement>('[data-channel-strategy-options]'),
    channelSetupReviewElement: documentRef.querySelector<HTMLElement>('[data-channel-review-impact]'),
    setupValidationElement: documentRef.querySelector<HTMLElement>('[data-channel-review-validation]'),
    channelSetupResultElement: documentRef.querySelector<HTMLElement>('[data-channel-setup-result]'),
    channelSetupFixtureStatusElement: documentRef.querySelector<HTMLElement>(
      '[data-channel-setup-fixture-status]',
    ),
    plexPanelElement: documentRef.querySelector<HTMLElement>('[data-plex-runtime-panel]'),
    plexActionButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-plex-action]'),
    ),
    plexStatusElement: documentRef.querySelector<HTMLElement>('[data-plex-status]'),
    plexErrorElement: documentRef.querySelector<HTMLElement>('[data-plex-error]'),
    plexAccountStateElement: documentRef.querySelector<HTMLElement>('[data-plex-account-state]'),
    plexServerStateElement: documentRef.querySelector<HTMLElement>('[data-plex-server-state]'),
    plexLibraryStateElement: documentRef.querySelector<HTMLElement>('[data-plex-library-state]'),
    plexPinElement: documentRef.querySelector<HTMLElement>('[data-plex-pin]'),
    plexHomeUserPinInput: documentRef.querySelector<HTMLInputElement>('[data-plex-home-user-pin]'),
    plexSearchQueryInput: documentRef.querySelector<HTMLInputElement>('[data-plex-search-query]'),
    plexHomeUsersElement: documentRef.querySelector<HTMLElement>('[data-plex-home-users]'),
    plexServersElement: documentRef.querySelector<HTMLElement>('[data-plex-servers]'),
    plexSectionsElement: documentRef.querySelector<HTMLElement>('[data-plex-sections]'),
    plexItemsElement: documentRef.querySelector<HTMLElement>('[data-plex-items]'),
    plexMetadataElement: documentRef.querySelector<HTMLElement>('[data-plex-metadata]'),
    overlayElements: Array.from(documentRef.querySelectorAll<HTMLElement>('[data-overlay]')),
    overlayStackElement: documentRef.querySelector<HTMLElement>('[data-overlay-stack]'),
    overlayNowPlayingTitleElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-title]',
    ),
    overlayNowPlayingSubtitleElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-subtitle]',
    ),
    overlayNowPlayingChannelElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-channel]',
    ),
    overlayNowPlayingStatusElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-status]',
    ),
    overlayProgressElement: documentRef.querySelector<HTMLElement>('[data-overlay-progress]'),
    overlayMiniGuideElement: documentRef.querySelector<HTMLElement>('[data-overlay-mini-guide]'),
    overlayChannelNumberElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-channel-number-value]',
    ),
    overlayChannelBadgeNumberElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-channel-badge-number]',
    ),
    overlayChannelBadgeNameElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-channel-badge-name]',
    ),
    overlayChannelBadgeProgramElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-channel-badge-program]',
    ),
    overlayAudioLabelElement: documentRef.querySelector<HTMLElement>('[data-overlay-audio-label]'),
    overlaySubtitleLabelElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-subtitle-label]',
    ),
    overlayVolumeLabelElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-volume-label]',
    ),
    overlayRateLabelElement: documentRef.querySelector<HTMLElement>('[data-overlay-rate-label]'),
    overlayPlaybackSummaryElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-playback-summary]',
    ),
    overlayAudioOptionsElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-audio-options]',
    ),
    overlaySubtitleOptionsElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-subtitle-options]',
    ),
  };
}

export type PlexRuntimeActionId =
  | 'loadSnapshot'
  | 'requestPin'
  | 'pollPin'
  | 'cancelPin'
  | 'getHomeUsers'
  | 'restoreSelectedServer'
  | 'refreshServers'
  | 'listLibrarySections'
  | 'listLibraryItems'
  | 'searchLibrary'
  | 'clearPinSubflow'
  | 'clearSelectedServer'
  | 'clearSelectedSection'
  | 'clearItems'
  | 'clearSearch'
  | 'clearMetadata';

export function readPlexRuntimeActionId(value: string | undefined): PlexRuntimeActionId | null {
  switch (value) {
    case 'loadSnapshot':
    case 'requestPin':
    case 'pollPin':
    case 'cancelPin':
    case 'getHomeUsers':
    case 'restoreSelectedServer':
    case 'refreshServers':
    case 'listLibrarySections':
    case 'listLibraryItems':
    case 'searchLibrary':
    case 'clearPinSubflow':
    case 'clearSelectedServer':
    case 'clearSelectedSection':
    case 'clearItems':
    case 'clearSearch':
    case 'clearMetadata':
      return value;
    default:
      return null;
  }
}

export function readRouteId(value: string | undefined): AppRouteId | null {
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

export function readRouteActionId(value: string | undefined): RouteWorkflowActionId | null {
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

export function readSettingsActionId(value: string | undefined): SettingsActionId | null {
  switch (value) {
    case 'cycleLaunchMode':
    case 'cycleGuideDensity':
    case 'togglePreviewBadges':
    case 'toggleSetupReminder':
    case 'exportSupportBundle':
      return value;
    default:
      return null;
  }
}

export function readChannelSetupActionId(value: string | undefined): ChannelSetupActionId | null {
  switch (value) {
    case 'advanceSetupStep':
    case 'toggleFeaturedChannel':
    case 'addDraftChannel':
    case 'resetDraftLineup':
    case 'selectRecentlyAddedSource':
    case 'selectAppendBuildMode':
    case 'selectReplaceBuildMode':
      return value;
    default:
      return null;
  }
}

export type ChannelCommitActionId = 'append' | 'replace' | 'confirmReplace';

export function readChannelCommitActionId(value: string | undefined): ChannelCommitActionId | null {
  switch (value) {
    case 'append':
    case 'replace':
    case 'confirmReplace':
      return value;
    default:
      return null;
  }
}

export function readEpgActionId(value: string | undefined): EpgActionId | null {
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

export function readOverlayActionId(value: string | undefined): PlayerOverlayActionId | null {
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

export function readClosestRouteId(element: HTMLElement): AppRouteId | null {
  const screen = element.closest<HTMLElement>('[data-screen]');
  return readRouteId(screen?.dataset.screen);
}
