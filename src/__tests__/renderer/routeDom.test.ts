import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { createFakePlayerSnapshot, createPlayerOverlayState } from '../../renderer/overlays.js';
import { renderWorkflowDom } from '../../renderer/routeDom.js';
import { createWorkflowState } from '../../renderer/workflow.js';

class ElementDouble {
  hidden = false;
  disabled = false;
  textContent = '';
  className = '';
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly style = { setProperty: () => undefined };
  readonly children: ElementDouble[] = [];

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }

  getAttribute(name: string): string | null {
    return this.attributes.get(name) ?? null;
  }

  append(...children: ElementDouble[]): void {
    this.children.push(...children);
  }

  replaceChildren(...children: ElementDouble[]): void {
    this.children.splice(0, this.children.length, ...children);
  }
}

test('route DOM workflow rendering hides and disables player overlays away from the player route', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDataset: Record<string, string> = {};
  const documentDouble = {
    documentElement: { dataset: documentDataset },
    querySelector: () => null,
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const overlayStack = new ElementDouble();
    const osdOverlay = new ElementDouble();
    osdOverlay.dataset.overlay = 'playerOsd';
    const nowPlayingOverlay = new ElementDouble();
    nowPlayingOverlay.dataset.overlay = 'nowPlaying';
    const overlayAction = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack,
      overlays: [osdOverlay, nowPlayingOverlay],
      overlayActions: [overlayAction],
    });

    renderWorkflowDom(
      createWorkflowState('guide'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
    );

    assert.equal(overlayStack.hidden, true);
    assert.equal(overlayStack.getAttribute('aria-hidden'), 'true');
    assert.equal(overlayStack.dataset.overlayRouteActive, 'false');
    assert.equal(overlayStack.dataset.overlayStack, '');
    assert.equal(osdOverlay.hidden, true);
    assert.equal(osdOverlay.getAttribute('aria-hidden'), 'true');
    assert.equal(osdOverlay.dataset.overlayActive, 'false');
    assert.equal(nowPlayingOverlay.hidden, true);
    assert.equal(overlayAction.disabled, true);
    assert.equal(documentDataset.activeOverlay, '');

    renderWorkflowDom(
      createWorkflowState('player'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
    );

    assert.equal(overlayStack.hidden, false);
    assert.equal(overlayStack.getAttribute('aria-hidden'), 'false');
    assert.equal(overlayStack.dataset.overlayRouteActive, 'true');
    assert.equal(overlayStack.dataset.overlayStack, 'channelBadge,nowPlaying,playerOsd');
    assert.equal(osdOverlay.hidden, false);
    assert.equal(osdOverlay.getAttribute('aria-hidden'), 'false');
    assert.equal(osdOverlay.dataset.overlayActive, 'true');
    assert.equal(nowPlayingOverlay.hidden, false);
    assert.equal(overlayAction.disabled, false);
    assert.equal(documentDataset.activeOverlay, 'playerOsd');
  } finally {
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

test('route DOM renders support bundle status without filesystem paths', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDataset: Record<string, string> = {};
  const documentDouble = {
    documentElement: { dataset: documentDataset },
    querySelector: () => null,
    createElement: () => new ElementDouble(),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const settingsSectionsElement = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.settingsSectionsElement = settingsSectionsElement as unknown as HTMLElement;

    renderWorkflowDom(
      createWorkflowState('settings'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
    );

    const renderedText = collectText(settingsSectionsElement);
    assert.match(renderedText, /Support bundle/u);
    assert.match(renderedText, /Ready/u);
    assert.doesNotMatch(renderedText, /\/Users\/|[A-Za-z]:\\/u);
    assert.doesNotMatch(renderedText, /\bpath\b|\bdirectory\b/u);
  } finally {
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

test('route DOM does not render legacy draft setup surfaces into Plex onboarding', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: () => new ElementDouble(),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const setupSteps = new ElementDouble();
    setupSteps.textContent = 'unchanged steps host';
    const draftList = new ElementDouble();
    draftList.textContent = 'unchanged draft host';
    const validation = new ElementDouble();
    validation.textContent = 'unchanged validation host';
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.setupStepsElement = setupSteps as unknown as HTMLElement;
    dom.channelDraftListElement = draftList as unknown as HTMLElement;
    dom.setupValidationElement = validation as unknown as HTMLElement;
    dom.channelSetupSourceElement = new ElementDouble() as unknown as HTMLElement;
    dom.channelSetupEnabledElement = new ElementDouble() as unknown as HTMLElement;
    dom.channelSetupBlocksElement = new ElementDouble() as unknown as HTMLElement;

    renderWorkflowDom(
      createWorkflowState('channelSetup'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
    );

    assert.equal(setupSteps.textContent, 'unchanged steps host');
    assert.equal(draftList.textContent, 'unchanged draft host');
    assert.equal(validation.textContent, 'unchanged validation host');
    assert.deepEqual(setupSteps.children, []);
    assert.deepEqual(draftList.children, []);
  } finally {
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

function collectText(element: ElementDouble): string {
  return [element.textContent, ...element.children.map(collectText)].join(' ');
}

function createOverlayDomBindings({
  overlayStack,
  overlays,
  overlayActions,
}: {
  overlayStack: ElementDouble;
  overlays: ElementDouble[];
  overlayActions: ElementDouble[];
}): RendererDomBindings {
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
    overlayActionButtons: overlayActions as unknown as HTMLButtonElement[],
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
    overlayElements: overlays as unknown as HTMLElement[],
    overlayStackElement: overlayStack as unknown as HTMLElement,
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
