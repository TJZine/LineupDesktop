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
  className = '';
  readonly dataset: Record<string, string> = {};
  readonly children: TestElement[] = [];
  readonly listeners = new Map<string, TestEventListener[]>();

  addEventListener(type: string, listener: TestEventListener): void {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  append(child: TestElement): void {
    child.parentElement = this;
    this.children.push(child);
  }

  closest(_selector: string): TestElement | null {
    let current: TestElement | null = this;
    while (current !== null) {
      if (current.className.split(' ').includes('playback-options__row')) {
        return current;
      }
      current = current.parentElement;
    }
    return null;
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

class TestDocument extends TestElement {
  getElementById(): TestElement | null {
    return null;
  }
}

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
    overlayNowPlayingDescriptionElement: null,
    overlayNowPlayingBadgesElement: null,
    overlayNowPlayingSummaryElement: null,
    overlayNowPlayingPositionElement: null,
    overlayNowPlayingDurationElement: null,
    overlayNowPlayingUpNextElement: null,
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
        selectAudioTrack: () => undefined,
        selectSubtitleTrack: () => undefined,
      },
    );

    input.dispatchEvent(new TestDomEvent('focusin', true));
    input.dispatchEvent(new TestDomEvent('focus', false));

    assert.deepEqual(focused, [input]);
  });
});

test('renderer action registration delegates media-option row selections', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const audioContainer = new TestElement();
    const subtitleContainer = new TestElement();
    const audioRow = new TestElement();
    const subtitleRow = new TestElement();
    const subtitleOffRow = new TestElement();
    audioRow.className = 'playback-options__row';
    subtitleRow.className = 'playback-options__row';
    subtitleOffRow.className = 'playback-options__row';
    audioRow.dataset.trackId = 'audio-ui-1';
    subtitleRow.dataset.trackId = 'subtitle-ui-1';
    subtitleOffRow.dataset.trackId = 'subtitles-off';
    audioContainer.append(audioRow);
    subtitleContainer.append(subtitleRow);
    subtitleContainer.append(subtitleOffRow);
    const audioSelections: string[] = [];
    const subtitleSelections: Array<string | null> = [];

    registerRendererActions(
      {
        ...emptyRendererDomBindings(),
        overlayAudioOptionsElement: audioContainer as unknown as HTMLElement,
        overlaySubtitleOptionsElement: subtitleContainer as unknown as HTMLElement,
      },
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
        focusElement: () => undefined,
        toggleFullscreen: () => undefined,
        selectAudioTrack: (trackId) => audioSelections.push(trackId),
        selectSubtitleTrack: (trackId) => subtitleSelections.push(trackId),
      },
    );

    audioRow.dispatchEvent(new TestDomEvent('click', true));
    subtitleRow.dispatchEvent(new TestDomEvent('click', true));
    subtitleOffRow.dispatchEvent(new TestDomEvent('click', true));

    assert.deepEqual(audioSelections, ['audio-ui-1']);
    assert.deepEqual(subtitleSelections, ['subtitle-ui-1', null]);
  });
});
