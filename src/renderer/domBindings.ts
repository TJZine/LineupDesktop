import type { AppRouteId } from './navigation.js';
import type {
  ChannelSetupActionId,
  EpgActionId,
  RouteWorkflowActionId,
  SettingsActionId,
} from './workflow.js';
import { PERSISTED_SETTINGS_ACTION_IDS } from './settingsSetup.js';
import type { PlayerOverlayActionId } from './overlays.js';
import { CUSTOM_CHANNEL_ACTIONS, type CustomChannelActionId } from './customChannels/controller.js';
import {
  STAGED_SETUP_FLOW_ACTIONS,
  type StagedSetupFlowActionId,
} from './setup/stagedSetupController.js';

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
  channelDraftListElement: HTMLElement | null;
  channelSetupReviewElement: HTMLElement | null;
  setupValidationElement: HTMLElement | null;
  channelSetupResultElement: HTMLElement | null;
  customChannelPanelElement?: HTMLElement | null;
  customChannelActionButtons?: HTMLButtonElement[];
  customChannelStatusElement?: HTMLElement | null;
  customChannelListElement?: HTMLElement | null;
  customChannelMediaElement?: HTMLElement | null;
  customChannelDraftElement?: HTMLElement | null;
  customChannelNameInput?: HTMLInputElement | null;
  customChannelNumberInput?: HTMLInputElement | null;
  customChannelSearchInput?: HTMLInputElement | null;
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
  playerPresentationElement?: HTMLElement | null;
  overlayNowPlayingTitleElement: HTMLElement | null;
  overlayNowPlayingSubtitleElement: HTMLElement | null;
  overlayNowPlayingChannelElement: HTMLElement | null;
  overlayNowPlayingStatusElement: HTMLElement | null;
  overlayNowPlayingDescriptionElement: HTMLElement | null;
  overlayNowPlayingBadgesElement: HTMLElement | null;
  overlayNowPlayingSummaryElement: HTMLElement | null;
  overlayNowPlayingPositionElement: HTMLElement | null;
  overlayNowPlayingDurationElement: HTMLElement | null;
  overlayNowPlayingUpNextElement: HTMLElement | null;
  overlayProgressElement: HTMLElement | null;
  overlayMiniGuideElement: HTMLElement | null;
  overlayMiniGuideErrorElement?: HTMLElement | null;
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
  overlayChannelNumberMessageElement?: HTMLElement | null;
  overlayOptionsErrorElement?: HTMLElement | null;
  overlayTransitionLabelElement?: HTMLElement | null;
  overlayPlayerLoadingLabelElement?: HTMLElement | null;
  overlayPlayerErrorElement?: HTMLElement | null;
  overlayPlayerRetryButton?: HTMLButtonElement | null;
  overlayPlayerSkipButton?: HTMLButtonElement | null;
  overlayPlayerGuideButton?: HTMLButtonElement | null;
  osdStatusElement: HTMLElement | null;
  osdTitleElement: HTMLElement | null;
  osdSubtitleElement: HTMLElement | null;
  osdAudioElement: HTMLElement | null;
  osdSubtitlesElement: HTMLElement | null;
  osdUpNextElement: HTMLElement | null;
  osdTimecodeElement: HTMLElement | null;
  osdEndsAtElement: HTMLElement | null;
  osdBufferTextElement: HTMLElement | null;
  osdBufferBarElement: HTMLElement | null;
  osdPlayedBarElement: HTMLElement | null;
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
    channelDraftListElement: documentRef.querySelector<HTMLElement>('[data-channel-review-list]'),
    channelSetupReviewElement: documentRef.querySelector<HTMLElement>('[data-channel-review-impact]'),
    setupValidationElement: documentRef.querySelector<HTMLElement>('[data-channel-review-validation]'),
    channelSetupResultElement: documentRef.querySelector<HTMLElement>('[data-channel-setup-result]'),
    customChannelPanelElement: documentRef.querySelector<HTMLElement>('[data-custom-channel-panel]'),
    customChannelActionButtons: Array.from(
      documentRef.querySelectorAll<HTMLButtonElement>('[data-custom-channel-action]'),
    ),
    customChannelStatusElement: documentRef.querySelector<HTMLElement>('[data-custom-channel-status]'),
    customChannelListElement: documentRef.querySelector<HTMLElement>('[data-custom-channel-list]'),
    customChannelMediaElement: documentRef.querySelector<HTMLElement>('[data-custom-channel-media]'),
    customChannelDraftElement: documentRef.querySelector<HTMLElement>('[data-custom-channel-draft]'),
    customChannelNameInput: documentRef.querySelector<HTMLInputElement>('[data-custom-channel-name]'),
    customChannelNumberInput: documentRef.querySelector<HTMLInputElement>('[data-custom-channel-number]'),
    customChannelSearchInput: documentRef.querySelector<HTMLInputElement>('[data-custom-channel-search-query]'),
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
    playerPresentationElement: documentRef.querySelector<HTMLElement>('[data-player-presentation-surface]'),
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
    overlayNowPlayingDescriptionElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-description]',
    ),
    overlayNowPlayingBadgesElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-badges]',
    ),
    overlayNowPlayingSummaryElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-summary]',
    ),
    overlayNowPlayingPositionElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-position]',
    ),
    overlayNowPlayingDurationElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-duration]',
    ),
    overlayNowPlayingUpNextElement: documentRef.querySelector<HTMLElement>(
      '[data-overlay-now-playing-up-next]',
    ),
    overlayProgressElement: documentRef.querySelector<HTMLElement>('[data-overlay-progress]'),
    overlayMiniGuideElement: documentRef.querySelector<HTMLElement>('[data-overlay-mini-guide]'),
    overlayMiniGuideErrorElement: documentRef.querySelector<HTMLElement>('[data-overlay-mini-guide-error]'),
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
    overlayChannelNumberMessageElement: documentRef.querySelector<HTMLElement>('[data-overlay-channel-number-message]'),
    overlayOptionsErrorElement: documentRef.querySelector<HTMLElement>('[data-overlay-options-error]'),
    overlayTransitionLabelElement: documentRef.querySelector<HTMLElement>('[data-overlay-transition-label]'),
    overlayPlayerLoadingLabelElement: documentRef.querySelector<HTMLElement>('[data-overlay-player-loading-label]'),
    overlayPlayerErrorElement: documentRef.querySelector<HTMLElement>('[data-overlay-player-error]'),
    overlayPlayerRetryButton: documentRef.querySelector<HTMLButtonElement>('[data-overlay-action="retryPlayer"]'),
    overlayPlayerSkipButton: documentRef.querySelector<HTMLButtonElement>('[data-overlay-action="skipPlayer"]'),
    overlayPlayerGuideButton: documentRef.querySelector<HTMLButtonElement>('[data-focus-id="overlay-player-guide"]'),
    osdStatusElement: documentRef.querySelector<HTMLElement>('[data-osd-status]'),
    osdTitleElement: documentRef.querySelector<HTMLElement>('[data-osd-title]'),
    osdSubtitleElement: documentRef.querySelector<HTMLElement>('[data-osd-subtitle]'),
    osdAudioElement: documentRef.querySelector<HTMLElement>('[data-osd-audio]'),
    osdSubtitlesElement: documentRef.querySelector<HTMLElement>('[data-osd-subtitles]'),
    osdUpNextElement: documentRef.querySelector<HTMLElement>('[data-osd-up-next]'),
    osdTimecodeElement: documentRef.querySelector<HTMLElement>('[data-osd-timecode]'),
    osdEndsAtElement: documentRef.querySelector<HTMLElement>('[data-osd-ends-at]'),
    osdBufferTextElement: documentRef.querySelector<HTMLElement>('[data-osd-buffer-text]'),
    osdBufferBarElement: documentRef.querySelector<HTMLElement>('[data-osd-buffer-bar]'),
    osdPlayedBarElement: documentRef.querySelector<HTMLElement>('[data-osd-played-bar]'),
  };
}

export type PlexRuntimeActionId =
  | 'loadSnapshot'
  | 'requestPin'
  | 'pollPin'
  | 'cancelPin'
  | 'dismissPinError'
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
    case 'dismissPinError':
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
    case 'audioSetup':
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

export function readCustomChannelActionId(value: string | undefined): CustomChannelActionId | null {
  return typeof value === 'string' && CUSTOM_CHANNEL_ACTIONS.includes(value as CustomChannelActionId)
    ? value as CustomChannelActionId
    : null;
}

export function readStagedSetupFlowActionId(value: string | undefined): StagedSetupFlowActionId | null {
  if (typeof value !== 'string') return null;
  if (STAGED_SETUP_FLOW_ACTIONS.includes(value as (typeof STAGED_SETUP_FLOW_ACTIONS)[number])) {
    return value as StagedSetupFlowActionId;
  }
  return /^(?:strategyToggle|strategyPriorityDown|strategyPriorityUp|strategyScope):(?:collections|playlists|genres|directors|decades|recentlyAdded|studios|actors)$/u.test(value)
    ? value as StagedSetupFlowActionId
    : null;
}

export function readSettingsActionId(value: string | undefined): SettingsActionId | null {
  if (value === 'switchProfile' || value === 'exportSupportBundle') return value;
  return typeof value === 'string'
    && PERSISTED_SETTINGS_ACTION_IDS.includes(value as (typeof PERSISTED_SETTINGS_ACTION_IDS)[number])
    ? value as (typeof PERSISTED_SETTINGS_ACTION_IDS)[number]
    : null;
}

export function readChannelSetupActionId(value: string | undefined): ChannelSetupActionId | null {
  switch (value) {
    case 'selectAppendBuildMode':
    case 'selectReplaceBuildMode':
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
    case 'openOsd':
    case 'openNowPlaying':
    case 'openMiniGuide':
    case 'openAudioOptions':
    case 'openSubtitleOptions':
    case 'retryPlayer':
    case 'skipPlayer':
    case 'miniGuidePrevious':
    case 'miniGuideNext':
    case 'miniGuidePagePrevious':
    case 'miniGuidePageNext':
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
