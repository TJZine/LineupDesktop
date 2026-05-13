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
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly style = { setProperty: () => undefined };

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }

  getAttribute(name: string): string | null {
    return this.attributes.get(name) ?? null;
  }

  replaceChildren(): void {
    return undefined;
  }
}

test('workflow rendering hides and disables player overlays away from the player route', () => {
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
