import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import type { ChannelRuntimeRendererState } from '../../renderer/channelRuntimeState.js';
import { createFakePlayerSnapshot, createPlayerOverlayState } from '../../renderer/overlays.js';
import { renderRouteDom, renderWorkflowDom } from '../../renderer/routeDom.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
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

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }

  removeAttribute(name: string): void {
    this.attributes.delete(name);
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

test('route DOM marks channel setup as the isolated onboarding route', () => {
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
    const playerButton = new ElementDouble();
    playerButton.dataset.routeButton = 'player';
    const setupButton = new ElementDouble();
    setupButton.dataset.routeButton = 'channelSetup';
    const playerScreen = new ElementDouble();
    playerScreen.dataset.screen = 'player';
    const setupScreen = new ElementDouble();
    setupScreen.dataset.screen = 'channelSetup';
    const routeTitle = new ElementDouble();
    const routeStatus = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.routeTitleElement = routeTitle as unknown as HTMLElement;
    dom.routeStatusElement = routeStatus as unknown as HTMLElement;
    dom.routeButtons = [playerButton, setupButton] as unknown as HTMLButtonElement[];
    dom.screens = [playerScreen, setupScreen] as unknown as HTMLElement[];

    renderRouteDom(createWorkflowState('channelSetup'), dom);

    assert.equal(documentDataset.activeRoute, 'channelSetup');
    assert.equal(routeTitle.textContent, 'Channel setup');
    assert.match(routeStatus.textContent, /Plex setup/u);
    assert.equal(playerButton.getAttribute('aria-current'), null);
    assert.equal(setupButton.getAttribute('aria-current'), 'page');
    assert.equal(playerScreen.hidden, true);
    assert.equal(setupScreen.hidden, false);
    assert.equal(setupScreen.className, 'screen--active');
    assert.equal(setupScreen.dataset.workflowTone, 'attention');
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

test('route DOM renders playback options enabled and disabled fixture rows', () => {
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
    const audioOptions = new ElementDouble();
    const subtitleOptions = new ElementDouble();
    const summary = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.overlayAudioOptionsElement = audioOptions as unknown as HTMLElement;
    dom.overlaySubtitleOptionsElement = subtitleOptions as unknown as HTMLElement;
    dom.overlayPlaybackSummaryElement = summary as unknown as HTMLElement;

    renderWorkflowDom(
      createWorkflowState('player'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
    );

    const renderedText = [summary.textContent, collectText(audioOptions), collectText(subtitleOptions)].join(' ');
    assert.match(renderedText, /Direct Play/u);
    assert.match(renderedText, /Audio Transcode/u);
    assert.match(renderedText, /Burn-in/u);
    assert.match(renderedText, /Unavailable/u);
    assert.equal(audioOptions.children.some((child) => child.dataset.available === 'false'), true);
    assert.equal(subtitleOptions.children.some((child) => child.dataset.selected === 'true'), true);
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

test('route DOM renders channel setup review without privileged data', () => {
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
    const channelList = new ElementDouble();
    channelList.textContent = 'unchanged channel host';
    const validation = new ElementDouble();
    validation.textContent = 'unchanged validation host';
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.setupStepsElement = setupSteps as unknown as HTMLElement;
    dom.channelDraftListElement = channelList as unknown as HTMLElement;
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

    const renderedText = [collectText(setupSteps), collectText(channelList), collectText(validation)].join(' ');
    assert.match(renderedText, /Choose library/u);
    assert.match(renderedText, /Persisted channel status is not loaded yet/u);
    assert.doesNotMatch(renderedText, /Liminal One/u);
    assert.doesNotMatch(renderedText, /Demo Library|The Vault|Weekend Queue/u);
    assert.doesNotMatch(renderedText, /2 of 3|6 programming blocks|16 programming blocks/u);
    assert.match(renderedText, /Choose a Plex library before saving channels/u);
    assert.doesNotMatch(renderedText, /serverUri|token|https?:|raw payload/u);
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

test('route DOM keeps channel commit controls disabled until a live Plex section is selected', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const appendButton = new ElementDouble();
    appendButton.dataset.channelCommitAction = 'append';
    const replaceButton = new ElementDouble();
    replaceButton.dataset.channelCommitAction = 'replace';
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.channelCommitButtons = [appendButton, replaceButton] as unknown as HTMLButtonElement[];

    renderWorkflowDom(
      createWorkflowState('channelSetup'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
      configuredChannelRuntimeState(),
      false,
    );

    assert.equal(appendButton.disabled, true);
    assert.equal(replaceButton.disabled, true);

    renderWorkflowDom(
      createWorkflowState('channelSetup'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
      configuredChannelRuntimeState(),
      true,
    );

    assert.equal(appendButton.disabled, false);
    assert.equal(replaceButton.disabled, false);

    renderWorkflowDom(
      createWorkflowState('channelSetup'),
      createPlayerOverlayState(),
      createFakePlayerSnapshot(),
      dom,
      { ...configuredChannelRuntimeState(), pending: true },
      true,
    );

    assert.equal(appendButton.disabled, true);
    assert.equal(replaceButton.disabled, true);
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

test('reachable product route text avoids internal implementation-status terms', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const selectorTextHosts = new Map<string, ElementDouble>();
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: (selector: string) => selectorTextHosts.get(selector) ?? null,
    createElement: () => new ElementDouble(),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const renderedRouteText: { route: string; text: string; channelSetupText: string }[] = [];
    for (const route of ['player', 'guide', 'settings', 'channelSetup'] as const) {
      selectorTextHosts.clear();
      for (const field of ['kicker', 'primary', 'secondary'] as const) {
        selectorTextHosts.set(`[data-workflow-${field}="${route}"]`, new ElementDouble());
      }

      const screen = new ElementDouble();
      screen.dataset.screen = route;
      const dom = createOverlayDomBindings({
        overlayStack: new ElementDouble(),
        overlays: [],
        overlayActions: [],
      });
      dom.routeTitleElement = new ElementDouble() as unknown as HTMLElement;
      dom.routeStatusElement = new ElementDouble() as unknown as HTMLElement;
      dom.screens = [screen] as unknown as HTMLElement[];
      dom.currentChannelElement = new ElementDouble() as unknown as HTMLElement;
      dom.currentProgramElement = new ElementDouble() as unknown as HTMLElement;
      dom.currentWindowElement = new ElementDouble() as unknown as HTMLElement;
      dom.epgGridElement = new ElementDouble() as unknown as HTMLElement;
      dom.epgDetailChannelElement = new ElementDouble() as unknown as HTMLElement;
      dom.epgDetailTitleElement = new ElementDouble() as unknown as HTMLElement;
      dom.epgDetailTimeElement = new ElementDouble() as unknown as HTMLElement;
      dom.settingsSourceElement = new ElementDouble() as unknown as HTMLElement;
      dom.settingsChannelsElement = new ElementDouble() as unknown as HTMLElement;
      dom.settingsStateElement = new ElementDouble() as unknown as HTMLElement;
      dom.settingsSectionsElement = new ElementDouble() as unknown as HTMLElement;
      dom.channelSetupSourceElement = new ElementDouble() as unknown as HTMLElement;
      dom.channelSetupEnabledElement = new ElementDouble() as unknown as HTMLElement;
      dom.channelSetupBlocksElement = new ElementDouble() as unknown as HTMLElement;
      dom.setupStepsElement = new ElementDouble() as unknown as HTMLElement;
      dom.channelDraftListElement = new ElementDouble() as unknown as HTMLElement;
      dom.setupValidationElement = new ElementDouble() as unknown as HTMLElement;
      dom.channelSetupFixtureStatusElement = new ElementDouble() as unknown as HTMLElement;
      dom.overlayPlaybackSummaryElement = new ElementDouble() as unknown as HTMLElement;
      dom.overlayAudioOptionsElement = new ElementDouble() as unknown as HTMLElement;
      dom.overlaySubtitleOptionsElement = new ElementDouble() as unknown as HTMLElement;

      const workflowState = createWorkflowState(route);
      renderRouteDom(workflowState, dom);
      renderWorkflowDom(
        workflowState,
        createPlayerOverlayState(),
        createFakePlayerSnapshot(),
        dom,
      );

      const channelSetupText = [
        dom.channelSetupSourceElement,
        dom.channelSetupEnabledElement,
        dom.channelSetupBlocksElement,
        dom.setupStepsElement,
        dom.channelDraftListElement,
        dom.setupValidationElement,
        dom.channelSetupFixtureStatusElement,
      ].map((element) => collectText(element as unknown as ElementDouble)).join(' ');
      renderedRouteText.push({
        route,
        channelSetupText,
        text: [
          ...selectorTextHosts.values(),
          dom.routeTitleElement,
          dom.routeStatusElement,
          dom.currentChannelElement,
          dom.currentProgramElement,
          dom.currentWindowElement,
          dom.epgGridElement,
          dom.epgDetailChannelElement,
          dom.epgDetailTitleElement,
          dom.epgDetailTimeElement,
          dom.settingsSourceElement,
          dom.settingsChannelsElement,
          dom.settingsStateElement,
          dom.settingsSectionsElement,
          dom.channelSetupSourceElement,
          dom.channelSetupEnabledElement,
          dom.channelSetupBlocksElement,
          dom.setupStepsElement,
          dom.channelDraftListElement,
          dom.setupValidationElement,
          dom.channelSetupFixtureStatusElement,
          dom.overlayPlaybackSummaryElement,
          dom.overlayAudioOptionsElement,
          dom.overlaySubtitleOptionsElement,
        ].map((element) => collectText(element as ElementDouble)).join(' '),
      });
    }

    assert.doesNotMatch(
      renderedRouteText.map(({ text }) => text).join(' '),
      PRODUCT_ROUTE_INTERNAL_COPY_PATTERN,
    );
    const channelSetupRouteText =
      renderedRouteText.find(({ route }) => route === 'channelSetup')?.channelSetupText ?? '';
    assert.doesNotMatch(
      channelSetupRouteText,
      /Demo Library|Liminal One|The Vault|Weekend Queue|2 of 3|6 programming blocks|16 programming blocks/u,
    );
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

test('static product route visible text avoids internal implementation-status terms', () => {
  const root = { innerHTML: '', querySelector: () => null };
  const documentDouble = {
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  };

  mountStaticRendererDom(documentDouble as unknown as Document);

  assert.doesNotMatch(readVisibleTextFromMarkup(root.innerHTML), PRODUCT_ROUTE_INTERNAL_COPY_PATTERN);
});

const PRODUCT_ROUTE_INTERNAL_COPY_PATTERN =
  /\bRD-\d+[A-Z]?\b|future RD|\bruntime\b|runtime wiring|scheduler wiring|later runtime pass|pending runtime|not implemented|implementation status|roadmap|\bfixture\b|\bfake\b|\bdebug\b|\bsmoke\b|\bproof\b|\bscaffold\b|\bdraft(?:\b|\s+(?:channel|programming|source|controls|setup))|not proven here|live Plex/iu;

function readVisibleTextFromMarkup(markup: string): string {
  return markup
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/giu, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/giu, ' ')
    .replace(/<[^>]+>/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
}

function collectText(element: ElementDouble): string {
  return [element.textContent, ...element.children.map(collectText)].join(' ');
}

function configuredChannelRuntimeState(): ChannelRuntimeRendererState {
  return {
    pending: false,
    statusText: 'Recovered',
    errorText: null,
    commitMode: 'append',
    confirmReplace: false,
    summary: {
      status: 'configured',
      channelCount: 1,
      currentChannelId: 'channel-one',
      currentChannelNumber: 101,
      currentChannelName: 'Movies',
      channelNumbers: [101],
      channels: [
        {
          id: 'channel-one',
          number: 101,
          name: 'Movies',
          sourceLibraryId: 'movies',
          sourceLibraryName: 'Movies',
          itemCount: 2,
        },
      ],
      updatedAtMs: 1,
      recovery: { loaded: true, repaired: false },
    },
  };
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
    channelCommitButtons: [],
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
    overlayPlaybackSummaryElement: null,
    overlayAudioOptionsElement: null,
    overlaySubtitleOptionsElement: null,
  };
}
