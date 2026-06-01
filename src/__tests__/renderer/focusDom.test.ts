import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { renderRendererFocus, syncRendererFocusTargets } from '../../renderer/focusDom.js';
import { FocusRegistry } from '../../renderer/navigation.js';

class FocusElementDouble {
  className = '';
  tabIndex = -1;
  focusCount = 0;
  readonly dataset: Record<string, string> = {};
  readonly classList = {
    toggle: (name: string, enabled: boolean): void => {
      const names = new Set(this.className.split(' ').filter(Boolean));
      if (enabled) {
        names.add(name);
      } else {
        names.delete(name);
      }
      this.className = [...names].join(' ');
    },
  };

  constructor(
    readonly focusId: string,
    private readonly hiddenFromRoute = false,
    routeButton?: string,
    plexAction?: string,
  ) {
    this.dataset.focusId = focusId;
    if (routeButton !== undefined) {
      this.dataset.routeButton = routeButton;
    }
    if (plexAction !== undefined) {
      this.dataset.plexAction = plexAction;
    }
  }

  closest(selector: string): object | null {
    if (selector === '[data-screen]') {
      return { dataset: { screen: this.dataset.routeButton ?? 'channelSetup' } };
    }
    assert.equal(selector, '[hidden], [aria-hidden="true"]');
    return this.hiddenFromRoute ? {} : null;
  }

  focus(): void {
    this.focusCount += 1;
    documentDouble.activeElement = this;
  }
}

const documentDouble: { activeElement: unknown } = { activeElement: null };

test('renderer focus suppresses browser focus and tab stops inside hidden trees', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const hiddenActive = new FocusElementDouble('guide-hidden-action', true);
    const visibleRoute = new FocusElementDouble('nav-player', false, 'player');
    const visibleActive = new FocusElementDouble('guide-window-next');
    const dom = createFocusDomBindings([hiddenActive, visibleRoute, visibleActive]);

    renderRendererFocus({ activeRoute: 'guide', activeId: 'guide-hidden-action' }, dom);

    assert.equal(hiddenActive.className, 'is-focused');
    assert.equal(hiddenActive.tabIndex, -1);
    assert.equal(hiddenActive.focusCount, 0);
    assert.equal(documentDouble.activeElement, null);
    assert.equal(visibleRoute.tabIndex, 0);

    renderRendererFocus({ activeRoute: 'guide', activeId: 'guide-window-next' }, dom);

    assert.equal(hiddenActive.tabIndex, -1);
    assert.equal(visibleActive.tabIndex, 0);
    assert.equal(visibleActive.focusCount, 1);
    assert.equal(documentDouble.activeElement, visibleActive);
  } finally {
    documentDouble.activeElement = null;
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', {
        value: originalDocument,
        configurable: true,
      });
    }
  }
});

test('channel setup initial focus starts on onboarding controls before the route rail', () => {
  const registry = new FocusRegistry();
  const navPlayer = new FocusElementDouble('nav-player', false, 'player');
  const navGuide = new FocusElementDouble('nav-guide', false, 'guide');
  const navSettings = new FocusElementDouble('nav-settings', false, 'settings');
  const navSetup = new FocusElementDouble('nav-channel-setup', false, 'channelSetup');
  const load = new FocusElementDouble('plex-load', false, undefined, 'loadSnapshot');
  const requestPin = new FocusElementDouble('plex-request-pin', false, undefined, 'requestPin');
  const dom = createFocusDomBindings([navPlayer, navGuide, navSettings, navSetup, load, requestPin]);
  dom.routeButtons = [navPlayer, navGuide, navSettings, navSetup] as unknown as HTMLButtonElement[];
  dom.plexActionButtons = [load, requestPin] as unknown as HTMLButtonElement[];

  syncRendererFocusTargets(registry, dom);

  assert.deepEqual(registry.createInitialState('channelSetup'), {
    activeRoute: 'channelSetup',
    activeId: 'plex-load',
  });
  assert.deepEqual(registry.move(registry.createInitialState('channelSetup'), 'down').state, {
    activeRoute: 'channelSetup',
    activeId: 'plex-request-pin',
  });
  assert.deepEqual(registry.focusTarget(registry.createInitialState('channelSetup'), 'nav-guide').state, {
    activeRoute: 'channelSetup',
    activeId: 'plex-load',
  });
});

test('channel setup focus moves from selected library to commit before optional preview', () => {
  const registry = new FocusRegistry();
  const listSections = new FocusElementDouble('plex-list-sections', false, undefined, 'listLibrarySections');
  const section = new FocusElementDouble('plex-dyn-section-movies');
  const append = new FocusElementDouble('channel-append');
  const replace = new FocusElementDouble('channel-replace');
  const previewItem = new FocusElementDouble('plex-dyn-item-rating-1');
  const clearMetadata = new FocusElementDouble('plex-clear-metadata', false, undefined, 'clearMetadata');
  const dom = createFocusDomBindings([listSections, section, append, replace, previewItem, clearMetadata]);
  dom.plexActionButtons = [listSections, clearMetadata] as unknown as HTMLButtonElement[];
  dom.channelCommitButtons = [append, replace] as unknown as HTMLButtonElement[];
  dom.plexSectionsElement = { querySelectorAll: () => [section] } as unknown as HTMLElement;
  dom.plexItemsElement = { querySelectorAll: () => [previewItem] } as unknown as HTMLElement;

  syncRendererFocusTargets(registry, dom);

  const selectedSection = registry.focusTarget(
    registry.createInitialState('channelSetup'),
    'plex-dyn-section-movies',
  ).state;
  assert.equal(registry.move(selectedSection, 'down').state.activeId, 'channel-append');
  assert.equal(registry.move({ activeRoute: 'channelSetup', activeId: 'channel-replace' }, 'down').state.activeId, 'plex-clear-metadata');
  assert.equal(registry.move({ activeRoute: 'channelSetup', activeId: 'plex-clear-metadata' }, 'down').state.activeId, 'plex-dyn-item-rating-1');
});

function createFocusDomBindings(focusableElements: FocusElementDouble[]): RendererDomBindings {
  return {
    statusElement: null,
    capabilitiesElement: null,
    fullscreenButton: null,
    routeTitleElement: null,
    routeStatusElement: null,
    routeButtons: [],
    routeActionButtons: [],
    settingsActionButtons: [],
    setupActionButtons: [],
    channelCommitButtons: [],
    epgActionButtons: [],
    overlayActionButtons: [],
    screens: [],
    focusableElements: focusableElements as unknown as HTMLElement[],
    currentChannelElement: null,
    currentProgramElement: null,
    currentWindowElement: null,
    channelListElement: null,
    epgGridElement: null,
    epgDetailChannelElement: null,
    epgDetailTitleElement: null,
    epgDetailTimeElement: null,
    settingsSourceElement: null,
    settingsChannelsElement: null,
    settingsStateElement: null,
    settingsSectionsElement: null,
    channelSetupSourceElement: null,
    channelSetupEnabledElement: null,
    channelSetupBlocksElement: null,
    setupStepsElement: null,
    channelDraftListElement: null,
    channelSetupStrategyElement: null,
    channelSetupReviewElement: null,
    setupValidationElement: null,
    channelSetupResultElement: null,
    channelSetupFixtureStatusElement: null,
    plexPanelElement: null,
    plexActionButtons: [],
    plexStatusElement: null,
    plexErrorElement: null,
    plexAccountStateElement: null,
    plexServerStateElement: null,
    plexLibraryStateElement: null,
    plexPinElement: null,
    plexHomeUserPinInput: null,
    plexSearchQueryInput: null,
    plexHomeUsersElement: null,
    plexServersElement: null,
    plexSectionsElement: null,
    plexItemsElement: null,
    plexMetadataElement: null,
    overlayElements: [],
    overlayStackElement: null,
    overlayNowPlayingTitleElement: null,
    overlayNowPlayingSubtitleElement: null,
    overlayNowPlayingChannelElement: null,
    overlayNowPlayingStatusElement: null,
    overlayProgressElement: null,
    overlayMiniGuideElement: null,
    overlayChannelNumberElement: null,
    overlayChannelBadgeNumberElement: null,
    overlayChannelBadgeNameElement: null,
    overlayChannelBadgeProgramElement: null,
    overlayAudioLabelElement: null,
    overlaySubtitleLabelElement: null,
    overlayVolumeLabelElement: null,
    overlayRateLabelElement: null,
    overlayPlaybackSummaryElement: null,
    overlayAudioOptionsElement: null,
    overlaySubtitleOptionsElement: null,
    osdStatusElement: null,
    osdTitleElement: null,
    osdSubtitleElement: null,
    osdAudioElement: null,
    osdSubtitlesElement: null,
    osdUpNextElement: null,
    osdTimecodeElement: null,
    osdEndsAtElement: null,
    osdBufferTextElement: null,
    osdBufferBarElement: null,
    osdPlayedBarElement: null,
  };
}
