import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { registerRendererActions } from '../../renderer/rendererActionRegistration.js';

type TestEventListener = (event: TestDomEvent) => void;

class TestDomEvent {
  target: TestElement | null = null;

  constructor(
    readonly type: string,
    readonly bubbles: boolean,
  ) {}
}

class TestElement {
  parentElement: TestElement | null = null;
  readonly listeners = new Map<string, TestEventListener[]>();

  addEventListener(type: string, listener: TestEventListener): void {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  append(child: TestElement): void {
    child.parentElement = this;
  }

  dispatchEvent(event: TestDomEvent): boolean {
    event.target ??= this;
    for (const listener of this.listeners.get(event.type) ?? []) {
      listener(event);
    }
    if (event.bubbles) {
      this.parentElement?.dispatchEvent(event);
    }
    return true;
  }
}

class TestDocument extends TestElement {}

function emptyRendererDomBindings(): RendererDomBindings {
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
    focusableElements: [],
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
    channelSetupStatusElement: null,
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

function withTestHTMLElement(callback: () => void): void {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'HTMLElement');
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: TestElement,
  });
  try {
    callback();
  } finally {
    if (descriptor === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLElement');
    } else {
      Object.defineProperty(globalThis, 'HTMLElement', descriptor);
    }
  }
}

test('renderer action registration delegates bubbling focusin events only', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const container = new TestElement();
    const input = new TestElement();
    documentRef.append(container);
    container.append(input);
    const focused: TestElement[] = [];

    registerRendererActions(
      emptyRendererDomBindings(),
      documentRef as unknown as Document,
      {
        activateRoute: () => undefined,
        applyRouteAction: () => undefined,
        applySettingsAction: () => undefined,
        applyChannelSetupAction: () => undefined,
        applyChannelCommitAction: () => undefined,
        applyEpgAction: () => undefined,
        applyOverlayAction: () => undefined,
        applyPlexRuntimeAction: () => undefined,
        setPlexHomeUserPin: () => undefined,
        setPlexSearchQuery: () => undefined,
        selectPlexHomeUser: () => undefined,
        selectPlexServer: () => undefined,
        selectPlexSection: () => undefined,
        openPlexMetadata: () => undefined,
        focusElement: (element) => focused.push(element as unknown as TestElement),
        toggleFullscreen: () => undefined,
      },
    );

    input.dispatchEvent(new TestDomEvent('focusin', true));
    input.dispatchEvent(new TestDomEvent('focus', false));

    assert.deepEqual(focused, [input]);
  });
});
