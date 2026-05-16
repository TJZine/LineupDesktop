import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { renderRendererFocus } from '../../renderer/focusDom.js';

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
  ) {
    this.dataset.focusId = focusId;
    if (routeButton !== undefined) {
      this.dataset.routeButton = routeButton;
    }
  }

  closest(selector: string): object | null {
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
    setupValidationElement: null,
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
  };
}
