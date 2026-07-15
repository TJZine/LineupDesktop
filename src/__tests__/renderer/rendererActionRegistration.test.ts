import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { registerRendererActions } from '../../renderer/rendererActionRegistration.js';
import { clickFocusedRendererElement } from '../../renderer/focusDom.js';

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
  id = '';
  readonly dataset: Record<string, string> = {};
  readonly children: TestElement[] = [];
  readonly listeners = new Map<string, TestEventListener[]>();
  readonly attributes = new Map<string, string>();
  disabled = false;

  addEventListener(type: string, listener: TestEventListener): void {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  append(child: TestElement): void {
    child.parentElement = this;
    this.children.push(child);
  }

  closest(selector: string): TestElement | null {
    let current: TestElement | null = this;
    while (current !== null) {
      if (selector.includes('playback-options__row') && current.className.split(' ').includes('playback-options__row')) {
        return current;
      }
      if (selector.includes('data-settings-action') && current.dataset.settingsAction !== undefined) {
        return current;
      }
      if (selector.includes('data-settings-category') && current.dataset.settingsCategory !== undefined) {
        return current;
      }
      if (selector.includes('data-setup-stage') && current.dataset.setupStage !== undefined) {
        return current;
      }
      if (selector.includes('data-setup-flow-action') && current.dataset.setupFlowAction !== undefined) return current;
      if (selector.includes('data-plex-section-id') && current.dataset.plexSectionId !== undefined) return current;
      if (selector.includes('data-custom-channel-action') && current.dataset.customChannelAction !== undefined) {
        return current;
      }
      if (selector.includes('data-guide-program-action') && current.dataset.guideProgramAction !== undefined) return current;
      if (selector.includes('data-guide-action') && current.dataset.guideAction !== undefined) return current;
      if (selector === '[data-staged-owner]' && current.dataset.stagedOwner !== undefined) {
        return current;
      }
      if (selector.includes('[hidden]') && (
        current.attributes.has('hidden')
        || current.attributes.has('inert')
        || current.getAttribute('aria-hidden') === 'true'
      )) return current;
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

  click(): void {
    this.dispatchEvent(new TestDomEvent('click', true));
  }

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }

  getAttribute(name: string): string | null {
    return this.attributes.get(name) ?? null;
  }
}

test('renderer action registration delegates dynamic Guide state and program controls', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const guide = new TestElement();
    guide.id = 'screen-guide';
    const cell = new TestElement();
    cell.dataset.guideProgramAction = 'activate';
    cell.dataset.guideChannelId = 'channel';
    cell.dataset.guideProgramId = 'program';
    cell.dataset.guideGeneration = '7';
    cell.dataset.focusId = 'guide-program-channel--program';
    const retry = new TestElement();
    retry.dataset.guideAction = 'retry';
    const back = new TestElement();
    back.dataset.guideAction = 'back';
    guide.append(cell);
    guide.append(retry);
    guide.append(back);
    documentRef.append(guide);
    const actions: string[] = [];
    const programs: string[] = [];
    let programFocused = false;
    registerRendererActions(emptyRendererDomBindings(), documentRef as unknown as Document, {
      activateRoute: () => undefined,
      applyRouteAction: () => undefined,
      applySettingsAction: () => undefined,
      applyChannelSetupAction: () => undefined,
      applyChannelCommitAction: () => undefined,
      applyEpgAction: () => undefined,
      applyGuideAction: (action) => actions.push(action),
      focusGuideProgramFromPointer: () => {
        if (programFocused) return false;
        programFocused = true;
        return true;
      },
      activateGuideProgram: (target) => programs.push(`${target.channelId}:${target.programId}:${String(target.presentationGeneration)}`),
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
      selectAudioTrack: () => undefined,
      selectSubtitleTrack: () => undefined,
    });
    cell.dispatchEvent(new TestDomEvent('pointerdown', true));
    cell.click();
    assert.deepEqual(programs, []);
    cell.dispatchEvent(new TestDomEvent('pointerdown', true));
    cell.click();
    retry.click();
    back.click();
    assert.deepEqual(programs, ['channel:program:7']);
    assert.deepEqual(actions, ['retry', 'back']);
    retry.setAttribute('aria-disabled', 'true');
    retry.click();
    assert.deepEqual(actions, ['retry', 'back']);
  });
});

class TestDocument extends TestElement {
  getElementById(id: string): TestElement | null {
    const search = (el: TestElement): TestElement | null => {
      if (el.id === id) return el;
      for (const child of el.children) {
        const found = search(child);
        if (found) return found;
      }
      return null;
    };
    return search(this);
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
    channelDraftListElement: null,
    channelSetupReviewElement: null,
    setupValidationElement: null,
    channelSetupResultElement: null,
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
  const buttonDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'HTMLButtonElement');
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: TestElement,
  });
  Object.defineProperty(globalThis, 'HTMLButtonElement', {
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
    if (buttonDescriptor === undefined) Reflect.deleteProperty(globalThis, 'HTMLButtonElement');
    else Object.defineProperty(globalThis, 'HTMLButtonElement', buttonDescriptor);
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

test('renderer action registration ignores disabled server stage pointer activation', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const setupScreen = new TestElement();
    const switchProfile = new TestElement();
    setupScreen.id = 'screen-channel-setup';
    switchProfile.dataset.setupStage = 'profile';
    setupScreen.append(switchProfile);
    documentRef.append(setupScreen);
    const stages: string[] = [];

    registerRendererActions(emptyRendererDomBindings(), documentRef as unknown as Document, {
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
      selectAudioTrack: () => undefined,
      selectSubtitleTrack: () => undefined,
      applySetupStage: (stage) => stages.push(stage),
    });

    switchProfile.disabled = true;
    switchProfile.dispatchEvent(new TestDomEvent('click', true));
    switchProfile.disabled = false;
    switchProfile.setAttribute('aria-disabled', 'true');
    switchProfile.dispatchEvent(new TestDomEvent('click', true));
    switchProfile.setAttribute('aria-disabled', 'false');
    switchProfile.dispatchEvent(new TestDomEvent('click', true));
    assert.deepEqual(stages, ['profile']);
  });
});

test('delegated staged and Plex actions reject hidden inert and aria-hidden ancestry and dispatch once', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const setupScreen = new TestElement(); setupScreen.id = 'screen-channel-setup';
    const owner = new TestElement(); owner.dataset.stagedOwner = 'preview'; owner.dataset.ownerActive = 'true';
    const flow = new TestElement(); flow.dataset.setupFlowAction = 'previewNext';
    owner.append(flow); setupScreen.append(owner); documentRef.append(setupScreen);
    const plexPanel = new TestElement(); const plexOwner = new TestElement(); const section = new TestElement();
    section.dataset.plexSectionId = 'movies'; plexOwner.append(section); plexPanel.append(plexOwner); documentRef.append(plexPanel);
    const dom = emptyRendererDomBindings(); dom.plexPanelElement = plexPanel as unknown as HTMLElement;
    const flowActions: string[] = []; const sections: string[] = [];
    registerRendererActions(dom, documentRef as unknown as Document, {
      activateRoute: () => undefined, applyRouteAction: () => undefined, applySettingsAction: () => undefined,
      applyChannelSetupAction: () => undefined, applyChannelCommitAction: () => undefined, applyEpgAction: () => undefined,
      applyOverlayAction: () => undefined, applyPlexRuntimeAction: () => undefined,
      applyStagedSetupAction: (action) => flowActions.push(action),
      setPlexHomeUserPin: () => undefined, setPlexSearchQuery: () => undefined,
      selectPlexHomeUser: () => undefined, selectPlexServer: () => undefined,
      selectPlexSection: (id) => sections.push(id), openPlexMetadata: () => undefined,
      focusElement: () => undefined, toggleFullscreen: () => undefined,
      selectAudioTrack: () => undefined, selectSubtitleTrack: () => undefined,
    });
    flow.click(); section.click();
    owner.setAttribute('hidden', ''); plexOwner.setAttribute('inert', '');
    flow.click(); section.click();
    owner.attributes.delete('hidden'); owner.setAttribute('aria-hidden', 'true');
    plexOwner.attributes.delete('inert'); plexOwner.setAttribute('aria-hidden', 'true');
    flow.click(); section.click();
    assert.deepEqual(flowActions, ['previewNext']);
    assert.deepEqual(sections, ['movies']);
  });
});

test('renderer action registration delegates custom editor media and delete actions only from the active owner', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const setupScreen = new TestElement();
    const editorOwner = new TestElement();
    const deleteOwner = new TestElement();
    const save = new TestElement();
    const media = new TestElement();
    const confirmDelete = new TestElement();
    setupScreen.id = 'screen-channel-setup';
    editorOwner.dataset.stagedOwner = 'custom-edit';
    editorOwner.dataset.ownerActive = 'true';
    deleteOwner.dataset.stagedOwner = 'custom-delete-confirm';
    deleteOwner.dataset.ownerActive = 'false';
    save.dataset.customChannelAction = 'saveDraft';
    media.dataset.customChannelAction = 'addMedia';
    media.dataset.customChannelDetail = 'rating-1';
    confirmDelete.dataset.customChannelAction = 'confirmDeleteChannel';
    confirmDelete.dataset.customChannelDetail = 'channel-1';
    editorOwner.append(save);
    editorOwner.append(media);
    deleteOwner.append(confirmDelete);
    setupScreen.append(editorOwner);
    setupScreen.append(deleteOwner);
    documentRef.append(setupScreen);
    const actions: string[] = [];

    registerRendererActions(emptyRendererDomBindings(), documentRef as unknown as Document, {
      activateRoute: () => undefined,
      applyRouteAction: () => undefined,
      applySettingsAction: () => undefined,
      applyChannelSetupAction: () => undefined,
      applyChannelCommitAction: () => undefined,
      applyEpgAction: () => undefined,
      applyOverlayAction: () => undefined,
      applyPlexRuntimeAction: () => undefined,
      applyCustomChannelAction: (action, detail) => actions.push(`${action}:${detail ?? ''}`),
      setPlexHomeUserPin: () => undefined,
      setPlexSearchQuery: () => undefined,
      selectPlexHomeUser: () => undefined,
      selectPlexServer: () => undefined,
      selectPlexSection: () => undefined,
      openPlexMetadata: () => undefined,
      focusElement: () => undefined,
      toggleFullscreen: () => undefined,
      selectAudioTrack: () => undefined,
      selectSubtitleTrack: () => undefined,
    });

    save.dispatchEvent(new TestDomEvent('click', true));
    media.dispatchEvent(new TestDomEvent('click', true));
    save.disabled = true;
    save.dispatchEvent(new TestDomEvent('click', true));
    editorOwner.setAttribute('aria-hidden', 'true');
    media.dispatchEvent(new TestDomEvent('click', true));
    editorOwner.setAttribute('aria-hidden', 'false');
    editorOwner.dataset.ownerActive = 'false';
    deleteOwner.dataset.ownerActive = 'true';
    confirmDelete.dataset.focusId = 'custom-delete-confirm';
    const focusDom = emptyRendererDomBindings();
    focusDom.focusableElements = [confirmDelete as unknown as HTMLElement];
    clickFocusedRendererElement({ activeRoute: 'channelSetup', activeId: 'custom-delete-confirm' }, focusDom);

    assert.deepEqual(actions, [
      'saveDraft:',
      'addMedia:rating-1',
      'confirmDeleteChannel:channel-1',
    ]);
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

test('renderer action registration delegates settings category clicks', () => {
  withTestHTMLElement(() => {
    const documentRef = new TestDocument();
    const settingsScreen = new TestElement();
    settingsScreen.id = 'screen-settings';
    documentRef.append(settingsScreen);

    const playbackCatBtn = new TestElement();
    playbackCatBtn.dataset.settingsCategory = 'playback';
    const categoriesContainer = new TestElement();
    categoriesContainer.append(playbackCatBtn);
    settingsScreen.append(categoriesContainer);

    let appliedCategory: string | null = null;

    registerRendererActions(
      emptyRendererDomBindings(),
      documentRef as unknown as Document,
      {
        activateRoute: () => undefined,
        applyRouteAction: () => undefined,
        applySettingsAction: () => undefined,
        applySettingsCategory: (cat) => {
          appliedCategory = cat;
        },
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
        selectAudioTrack: () => undefined,
        selectSubtitleTrack: () => undefined,
      },
    );

    // Dispatch click on the category button
    playbackCatBtn.dispatchEvent(new TestDomEvent('click', true));

    assert.equal(appliedCategory, 'playback');
  });
});
