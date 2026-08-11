import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import type { ChannelRuntimeRendererState } from '../../renderer/channelRuntimeState.js';
import { createPlayerOverlayState, openOsd, openPlaybackOptions } from '../../renderer/overlays.js';
import { createEmptyPlayerSnapshot } from '../../renderer/playerOverlayPresentation.js';
import { setEpgPresentationState, type EpgPresentationSource } from '../../renderer/epg.js';
import {
  renderChannelSetupResult,
  renderRouteDom,
  renderWorkflowDom,
} from '../../renderer/routeDom.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import {
  applyWorkflowChannelSetupAction,
  applyWorkflowSettingsAction,
  createWorkflowState as createWorkflowStateCore,
} from '../../renderer/workflow.js';
import { renderShellDom, type ShellDomBindings } from '../../renderer/shell/shellDom.js';
import { beginFullscreenRequest, rejectFullscreenRequest } from '../../renderer/shell/shellState.js';
import {
  cssDeclaration,
  extractCssAtRuleBody,
  extractCssRule,
} from './cssAtRuleTestUtils.js';

const GUIDE_BASE = Date.UTC(2026, 4, 12, 20, 0, 0);
function createRendererSafePlayerSnapshot() {
  return {
    ...createEmptyPlayerSnapshot(),
    requestId: 'route-dom-player',
    status: 'playing' as const,
    playing: true,
    media: { id: 'route-dom-media', title: 'The Midnight Archive', subtitle: 'Signal Lost', durationMs: 3_600_000 },
    durationMs: 3_600_000,
    positionMs: 720_000,
    selectedAudioTrackId: 'audio-main',
    tracks: [
      { id: 'audio-main', kind: 'audio' as const, label: 'Main', selected: true, available: true },
      { id: 'audio-alt', kind: 'audio' as const, label: 'Alt', selected: false, available: true },
      { id: 'sub-one', kind: 'subtitle' as const, label: 'English', selected: false, available: true },
    ],
  };
}
const GUIDE_PRESENTATION: EpgPresentationSource = {
  channels: [{
    id: 'channel-liminal-one', number: '101', name: 'Liminal One', programs: [{
      id: 'liminal-archive', title: 'The Midnight Archive', subtitle: 'Signal Lost',
      description: 'Archive description.', showTitle: 'The Midnight Archive', episodeLabel: 'S2 E4',
      rating: 'TV-14', quality: ['HD'], genres: ['Drama'],
      startsAtMs: GUIDE_BASE, endsAtMs: GUIDE_BASE + 60 * 60 * 1000,
      artwork: { poster: null, background: null, logo: null },
    }],
  }],
  nowWatching: {
    title: 'The Midnight Archive', subtitle: 'Signal Lost', channelId: 'channel-liminal-one',
    startsAtMs: GUIDE_BASE, endsAtMs: GUIDE_BASE + 60 * 60 * 1000,
  },
  nowMs: GUIDE_BASE + 30 * 60 * 1000,
};

function createWorkflowState(
  route: Parameters<typeof createWorkflowStateCore>[0] = 'player',
  guidePresentation: EpgPresentationSource = GUIDE_PRESENTATION,
) {
  return createWorkflowStateCore(route, guidePresentation);
}

class ElementDouble {
  hidden = false;
  disabled = false;
  textContent = '';
  className = '';
  type = '';
  readonly tagName: string;
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly style: { gridColumn?: string; setProperty: (name: string, value: string) => void } = {
    setProperty: () => undefined,
  };
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

  constructor(tagName = 'div') {
    this.tagName = tagName.toUpperCase();
  }

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
      createRendererSafePlayerSnapshot(),
      dom,
    );

    assert.equal(overlayStack.hidden, true);
    assert.equal(overlayStack.getAttribute('aria-hidden'), 'true');
    assert.equal(overlayStack.dataset.overlayRouteActive, 'false');
    assert.equal(overlayStack.dataset.overlayStack, '');
    assert.equal(osdOverlay.hidden, true);
    assert.equal(osdOverlay.getAttribute('aria-hidden'), 'true');
    assert.equal(nowPlayingOverlay.hidden, true);
    assert.equal(overlayAction.disabled, true);
    assert.equal(documentDataset.activeOverlay, '');

    renderWorkflowDom(
      createWorkflowState('player'),
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
    );

    assert.equal(overlayStack.hidden, false);
    assert.equal(overlayStack.getAttribute('aria-hidden'), 'false');
    assert.equal(overlayStack.dataset.overlayRouteActive, 'true');
    assert.equal(overlayStack.dataset.overlayStack, '');
    assert.equal(osdOverlay.hidden, true);
    assert.equal(osdOverlay.getAttribute('aria-hidden'), 'true');
    assert.equal(nowPlayingOverlay.hidden, true);
    assert.equal(overlayAction.disabled, false);
    assert.equal(documentDataset.activeOverlay, '');
  } finally {
    restoreDocument(originalDocument);
  }
});

test('inline shell error keeps Player visible but makes its background inert and retry pending', () => {
  const player = new ElementDouble();
  player.dataset.screen = 'player';
  const presentation = new ElementDouble();
  const inline = new ElementDouble();
  const retry = new ElementDouble('button');
  const dismiss = new ElementDouble('button');
  const bindings = {
    playerPresentation: presentation,
    splash: null,
    loading: null,
    blockingError: null,
    blockingErrorMessage: null,
    retryStartupButton: null,
    blockingExitButton: null,
    inlineError: inline,
    inlineErrorMessage: new ElementDouble(),
    inlineDismissButton: dismiss,
    inlineRetryButton: retry,
    toast: null,
    toastMessage: null,
    exitConfirm: null,
    exitCancelButton: null,
    exitButton: null,
  } as unknown as ShellDomBindings;
  const failed = rejectFullscreenRequest({
    bootstrap: 'ready',
    blockingErrorMessage: null,
    inlineError: null,
    toast: null,
    exitConfirmOpen: false,
    fullscreenPending: false,
  }, true);

  renderShellDom(failed, bindings, [player as unknown as HTMLElement]);
  assert.equal(player.hidden, false);
  assert.equal((player as unknown as { inert: boolean }).inert, true);
  assert.equal(player.getAttribute('aria-hidden'), 'true');
  assert.equal(presentation.hidden, false);
  assert.equal((presentation as unknown as { inert: boolean }).inert, true);
  assert.equal(presentation.getAttribute('aria-hidden'), 'true');
  assert.equal(inline.hidden, false);
  assert.equal((inline as unknown as { inert: boolean }).inert, false);

  renderShellDom(beginFullscreenRequest(failed, true), bindings, [player as unknown as HTMLElement]);
  assert.equal(inline.hidden, false);
  assert.equal(retry.disabled, true);
  assert.equal(retry.getAttribute('aria-disabled'), 'true');
  assert.equal(retry.getAttribute('aria-busy'), 'true');
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
    assert.equal((playerScreen as unknown as { inert: boolean }).inert, true);
    assert.equal(playerScreen.getAttribute('aria-hidden'), 'true');
    assert.equal(setupScreen.hidden, false);
    assert.equal((setupScreen as unknown as { inert: boolean }).inert, false);
    assert.equal(setupScreen.getAttribute('aria-hidden'), 'false');
    assert.equal(setupScreen.className, 'screen--active');
    assert.equal(setupScreen.dataset.workflowTone, 'attention');
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route DOM renders support bundle status without filesystem paths', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
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
      createRendererSafePlayerSnapshot(),
      dom,
    );

    const renderedText = collectText(settingsSectionsElement);
    assert.match(renderedText, /Support bundle/u);
    assert.match(renderedText, /Ready/u);
    assert.doesNotMatch(renderedText, /\/Users\/|[A-Za-z]:\\/u);
    assert.doesNotMatch(renderedText, /\bpath\b|\bdirectory\b/u);
    assert.equal(settingsSectionsElement.children.length, 7);
    settingsSectionsElement.children.forEach((article, index) => {
      const active = index === 2;
      assert.equal(article.hidden, !active);
      assert.equal(article.getAttribute('aria-hidden'), String(!active));
      assert.equal(article.attributes.has('inert'), !active);
    });
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route DOM disables support bundle export while an export is active', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    querySelectorAll: () => [],
    createElement: (tagName: string) => new ElementDouble(tagName),
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
    const exportingState = applyWorkflowSettingsAction(
      createWorkflowState('settings'),
      'exportSupportBundle',
    );

    renderWorkflowDom(
      exportingState,
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
    );

    const exportButton = findElementsByDataset(
      settingsSectionsElement,
      'settingsAction',
      'exportSupportBundle',
    )[0];
    assert.ok(exportButton);
    assert.equal(exportButton.disabled, true);
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route DOM renders guide states and focused program details', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const grid = new ElementDouble();
    const detailChannel = new ElementDouble();
    const detailTitle = new ElementDouble();
    const detailTime = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.epgGridElement = grid as unknown as HTMLElement;
    dom.epgDetailChannelElement = detailChannel as unknown as HTMLElement;
    dom.epgDetailTitleElement = detailTitle as unknown as HTMLElement;
    dom.epgDetailTimeElement = detailTime as unknown as HTMLElement;

    renderWorkflowDom(
      createWorkflowState('guide'),
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
    );

    const renderedText = [collectText(grid), detailChannel.textContent, detailTitle.textContent, detailTime.textContent].join(' ');
    assert.match(renderedText, /LINEUP/u);
    assert.match(renderedText, /101 - Liminal One/u);
    assert.match(renderedText, /Guide ready/u);
    assert.match(renderedText, /The Midnight Archive/u);
    assert.match(renderedText, /S2 E4/u);
    assert.match(collectVisibleText(grid), /Edit lineup/u);
    const editLineupActions = findElementsByDataset(grid, 'guideAction', 'setup');
    assert.equal(editLineupActions.length, 1);
    assert.equal(editLineupActions[0]?.dataset.focusId, 'guide-state-setup');
    assert.equal(grid.getAttribute('role'), 'grid');
    const readyRows = findElementsByRole(grid, 'row');
    assert.equal(readyRows.length, 2);
    const headerRow = readyRows[0];
    assert.ok(headerRow);
    const columnHeaders = findElementsByRole(headerRow, 'columnheader');
    assert.ok(columnHeaders.length > 1);
    assert.equal(columnHeaders[0]?.getAttribute('aria-label'), 'Channel');
    const readyRow = readyRows[1];
    assert.ok(readyRow);
    assert.equal(findElementsByRole(readyRow, 'rowheader').length, 1);
    assert.equal(findElementsByRole(readyRow, 'gridcell').length, 1);

    for (const state of ['loading', 'empty-channels', 'empty-programs', 'error'] as const) {
      const stateGrid = new ElementDouble();
      const stateTitle = new ElementDouble();
      const currentProgram = new ElementDouble();
      const currentWindow = new ElementDouble();
      dom.epgGridElement = stateGrid as unknown as HTMLElement;
      dom.epgDetailTitleElement = stateTitle as unknown as HTMLElement;
      dom.currentProgramElement = currentProgram as unknown as HTMLElement;
      dom.currentWindowElement = currentWindow as unknown as HTMLElement;
      renderWorkflowDom(
        {
          ...createWorkflowState('guide'),
          epg: setEpgPresentationState(createWorkflowState('guide').epg, state),
        },
        createPlayerOverlayState(),
        createRendererSafePlayerSnapshot(),
        dom,
      );

      const stateText = collectText(stateGrid);
      assert.equal(stateGrid.getAttribute('role'), null);
      assert.match(stateText, state === 'loading' ? /Loading guide/u : state === 'empty-channels' ? /No channels available/u : state === 'empty-programs' ? /No programs in this window/u : /Guide unavailable/u);
      assert.doesNotMatch(stateText, /Signal Warmup|After Hours Cinema|Pilot Block|Roundtable/u);
      assert.match(stateTitle.textContent, state === 'loading' ? /Loading guide/u : state === 'empty-channels' ? /No channels available/u : state === 'empty-programs' ? /No programs in this window/u : /Guide unavailable/u);
      assert.equal(currentProgram.textContent, state === 'loading' ? 'Loading guide' : state === 'empty-channels' ? 'No channels available' : state === 'empty-programs' ? 'No programs in this window' : 'Guide unavailable');
      assert.match(currentWindow.textContent, state === 'loading' ? /Schedule rows are preparing/u : state === 'empty-channels' ? /Add channels from setup/u : state === 'empty-programs' ? /Refresh the schedule/u : /could not be shown/u);
    }
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route DOM suppresses now-playing chrome and summary when ready data has no now-watching value', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const grid = new ElementDouble();
    const currentChannel = new ElementDouble();
    const currentProgram = new ElementDouble();
    const currentWindow = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.epgGridElement = grid as unknown as HTMLElement;
    dom.currentChannelElement = currentChannel as unknown as HTMLElement;
    dom.currentProgramElement = currentProgram as unknown as HTMLElement;
    dom.currentWindowElement = currentWindow as unknown as HTMLElement;

    const missingNowWatching = createWorkflowState('guide', { ...GUIDE_PRESENTATION, nowWatching: null });
    renderWorkflowDom(
      missingNowWatching,
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
    );

    assert.equal(grid.getAttribute('role'), 'grid');
    assert.doesNotMatch(collectText(grid), /NOW PLAYING/u);
    assert.equal(currentChannel.textContent, '');
    assert.equal(currentProgram.textContent, '');
    assert.equal(currentWindow.textContent, '');

    renderWorkflowDom(
      { ...missingNowWatching, epg: setEpgPresentationState(missingNowWatching.epg, 'loading') },
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
    );
    assert.equal(grid.getAttribute('role'), null);
    assert.doesNotMatch(collectText(grid), /NOW PLAYING/u);
  } finally {
    restoreDocument(originalDocument);
  }
});

test('Guide Now Watching setting projects exactly one layout-owned status without disturbing the grid', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const grid = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.epgGridElement = grid as unknown as HTMLElement;
    const maxSafeTitle = 'T'.repeat(2_000);
    const maxSafeChannelNumber = '9'.repeat(120);
    const maxSafeChannelName = 'C'.repeat(2_000);
    const maxSafeChannelLabel = `${maxSafeChannelNumber} - ${maxSafeChannelName}`;
    const base = createWorkflowState('guide', {
      ...GUIDE_PRESENTATION,
      channels: GUIDE_PRESENTATION.channels.map((channel) => ({
        ...channel,
        number: maxSafeChannelNumber,
        name: maxSafeChannelName,
      })),
      nowWatching: { ...GUIDE_PRESENTATION.nowWatching!, title: maxSafeTitle },
    });
    const render = (enabled: boolean, layout: 'classic' | 'overlay', route: 'guide' | 'player' = 'guide') => {
      const state = route === 'guide' ? base : createWorkflowState('player', base.guidePresentation);
      renderWorkflowDom(
        {
          ...state,
          settingsDraft: {
            ...state.settingsDraft,
            nowWatchingBannerEnabled: enabled,
            guideLayout: layout,
          },
        },
        createPlayerOverlayState(),
        createRendererSafePlayerSnapshot(),
        dom,
      );
    };

    render(true, 'classic');
    const classic = findElementsByClassName(grid, 'epg-classic-now-playing');
    assert.equal(classic.length, 1);
    assert.equal(findElementsByClassName(grid, 'epg-now-watching-banner').length, 0);
    assert.equal(classic[0]?.getAttribute('role'), 'status');
    assert.equal(classic[0]?.getAttribute('aria-live'), 'polite');
    assert.equal(classic[0]?.getAttribute('aria-atomic'), 'true');
    assert.equal(classic[0]?.dataset.focusId, undefined);
    const classicChannel = findElementsByClassName(classic[0]!, 'epg-classic-now-playing-channel');
    assert.equal(classicChannel[0]?.textContent, maxSafeChannelLabel);
    const classicFocusIds = findFocusIds(grid);
    assert.ok(classicFocusIds.some((focusId) => focusId.startsWith('guide-program-')));

    render(true, 'overlay');
    const overlay = findElementsByClassName(grid, 'epg-now-watching-banner');
    assert.equal(findElementsByClassName(grid, 'epg-classic-now-playing').length, 0);
    assert.equal(overlay.length, 1);
    assert.equal(overlay[0]?.getAttribute('role'), 'status');
    assert.equal(overlay[0]?.getAttribute('aria-live'), 'polite');
    assert.equal(overlay[0]?.getAttribute('aria-atomic'), 'true');
    assert.equal(overlay[0]?.dataset.focusId, undefined);
    const overlayChannel = findElementsByClassName(overlay[0]!, 'epg-now-watching-channel');
    const overlayProgram = findElementsByClassName(overlay[0]!, 'epg-now-watching-program');
    assert.equal(overlayChannel.length, 1);
    assert.equal(overlayChannel[0]?.textContent, maxSafeChannelLabel);
    assert.equal(overlayChannel[0]?.children.length, 0);
    assert.equal(overlayProgram.length, 1);
    assert.equal(overlayProgram[0]?.textContent, maxSafeTitle);
    assert.equal(overlayProgram[0]?.children.length, 0);
    assert.equal(collectText(overlay[0]!).includes(maxSafeTitle), true);
    assert.deepEqual(findFocusIds(grid), classicFocusIds);
    assert.equal(findElementsByRole(grid, 'gridcell').length, 1);

    for (const layout of ['classic', 'overlay'] as const) {
      render(false, layout);
      assert.equal(findElementsByClassName(grid, 'epg-classic-now-playing').length, 0);
      assert.equal(findElementsByClassName(grid, 'epg-now-watching-banner').length, 0);
      assert.deepEqual(findFocusIds(grid), classicFocusIds);
    }

    render(true, 'overlay', 'player');
    assert.equal(findElementsByClassName(grid, 'epg-classic-now-playing').length, 0);
    assert.equal(findElementsByClassName(grid, 'epg-now-watching-banner').length, 0);

    render(true, 'classic');
    assert.equal(findElementsByClassName(grid, 'epg-classic-now-playing').length, 1);
    assert.equal(findElementsByClassName(grid, 'epg-now-watching-banner').length, 0);
    assert.deepEqual(findFocusIds(grid), classicFocusIds);
  } finally {
    restoreDocument(originalDocument);
  }
});

test('Guide clears stale Now Watching surfaces for every non-ready presentation state in both layouts', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const grid = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.epgGridElement = grid as unknown as HTMLElement;
    const base = createWorkflowState('guide');
    assert.notEqual(base.guidePresentation.nowWatching, null);
    const render = (layout: 'classic' | 'overlay', presentationState: 'ready' | 'loading' | 'empty-channels' | 'empty-programs' | 'error') => {
      renderWorkflowDom(
        {
          ...base,
          epg: setEpgPresentationState(base.epg, presentationState),
          settingsDraft: {
            ...base.settingsDraft,
            nowWatchingBannerEnabled: true,
            guideLayout: layout,
          },
        },
        createPlayerOverlayState(),
        createRendererSafePlayerSnapshot(),
        dom,
      );
    };

    for (const layout of ['classic', 'overlay'] as const) {
      const activeClass = layout === 'classic'
        ? 'epg-classic-now-playing'
        : 'epg-now-watching-banner';
      for (const presentationState of ['loading', 'empty-channels', 'empty-programs', 'error'] as const) {
        render(layout, 'ready');
        assert.equal(findElementsByClassName(grid, activeClass).length, 1);

        render(layout, presentationState);
        assert.equal(grid.getAttribute('role'), null);
        assert.equal(findElementsByClassName(grid, 'epg-classic-now-playing').length, 0);
        assert.equal(findElementsByClassName(grid, 'epg-now-watching-banner').length, 0);
        assert.doesNotMatch(collectText(grid), /NOW PLAYING/u);
      }
    }
  } finally {
    restoreDocument(originalDocument);
  }
});

test('Guide Now Watching surfaces explicitly honor reduced motion and forced colors', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const css = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/guide-epg.css', import.meta.url),
    'utf8',
  );
  const reducedMotion = extractCssAtRuleBody(css, '@media (prefers-reduced-motion: reduce)');
  const forcedColors = extractCssAtRuleBody(css, '@media (forced-colors: active)');
  const banner = extractCssRule(css, '.epg-now-watching-banner');
  assert.equal(
    cssDeclaration(banner, 'grid-template-columns'),
    'minmax(0, max-content) minmax(0, 1fr) minmax(0, 2fr) minmax(0, max-content)',
  );
  assert.equal(cssDeclaration(banner, 'overflow'), 'hidden');

  const bannerChildren = extractCssRule(css, '.epg-now-watching-banner > *');
  assert.equal(cssDeclaration(bannerChildren, 'min-width'), '0');

  const textSelectors = [
    '.epg-now-watching-live',
    '.epg-now-watching-channel',
    '.epg-now-watching-program',
    '.epg-now-watching-time',
  ];
  const textRule = extractCssRule(css, textSelectors);
  assert.equal(cssDeclaration(textRule, 'overflow'), 'hidden');
  assert.equal(cssDeclaration(textRule, 'text-overflow'), 'ellipsis');
  assert.equal(cssDeclaration(textRule, 'white-space'), 'nowrap');

  const reduced = extractCssRule(reducedMotion ?? '', [
    '.epg-classic-now-playing',
    '.epg-now-watching-banner',
  ]);
  assert.equal(cssDeclaration(reduced, 'animation'), 'none !important');
  assert.equal(cssDeclaration(reduced, 'transition'), 'none !important');

  const forced = extractCssRule(forcedColors ?? '', [
    '.epg-classic-now-playing',
    '.epg-now-watching-banner',
  ]);
  assert.equal(cssDeclaration(forced, 'color'), 'CanvasText');

  const forcedBanner = extractCssRule(forcedColors ?? '', '.epg-now-watching-banner');
  assert.equal(cssDeclaration(forcedBanner, 'border-color'), 'CanvasText');
});

test('route DOM renders player OSD fields and playback option rows', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.osdStatusElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdTitleElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdSubtitleElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdAudioElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdSubtitlesElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdSleepElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdSleepStatusElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdSleepButton = new ElementDouble() as unknown as HTMLButtonElement;
    dom.osdUpNextElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdTimecodeElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdEndsAtElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdBufferTextElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdBufferBarElement = new ElementDouble() as unknown as HTMLElement;
    dom.osdPlayedBarElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlayAudioOptionsElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlaySubtitleOptionsElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlayPlaybackSummaryElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlayMiniGuideErrorElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlayMiniGuideElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlayPlayerErrorElement = new ElementDouble() as unknown as HTMLElement;
    dom.overlayPlayerRetryButton = new ElementDouble('button') as unknown as HTMLButtonElement;
    dom.overlayPlayerRetryButton.dataset.overlayAction = 'retryPlayer';
    dom.overlayPlayerSkipButton = new ElementDouble('button') as unknown as HTMLButtonElement;
    dom.overlayPlayerSkipButton.dataset.overlayAction = 'skipPlayer';
    dom.overlayActionButtons = [
      dom.overlayPlayerRetryButton,
      dom.overlayPlayerSkipButton,
    ];
    dom.overlayPlayerGuideButton = new ElementDouble('button') as unknown as HTMLButtonElement;

    const snapshot = {
      ...createRendererSafePlayerSnapshot(),
      tracks: [
        ...createRendererSafePlayerSnapshot().tracks,
        {
          id: 'audio-unavailable',
          kind: 'audio' as const,
          label: 'Director mix',
          selected: false,
          available: false,
        },
        {
          id: 'subtitle-unavailable',
          kind: 'subtitle' as const,
          label: 'Unavailable captions',
          deliveryType: 'external' as const,
          selected: false,
          available: false,
        },
      ],
      quality: {
        mode: 'direct-play' as const,
        sourceDynamicRange: 'sdr' as const,
        outputDynamicRangeStatus: 'sdr' as const,
        videoCodec: 'h264',
        audioCodec: 'aac',
      },
    };

    const presentation = {
      channels: [{
        id: 'channel-one', number: '101', name: 'Channel One',
        currentProgram: { id: 'program-one', title: 'Runtime program', startsAtMs: 0, endsAtMs: 2_000 },
        nextProgram: { id: 'program-two', title: 'Runtime next', startsAtMs: 2_000, endsAtMs: 3_000 },
      }],
      currentChannelId: 'channel-one', playerSnapshot: snapshot, nowMs: 1_000,
    };
    const osd = openOsd(createPlayerOverlayState(presentation), snapshot);
    const audioOptions = openPlaybackOptions(osd, snapshot, 'audio');
    renderWorkflowDom(
      createWorkflowState('player'),
      audioOptions,
      snapshot,
      dom,
      undefined,
      null,
      presentation,
    );

    const osdText = [
      dom.osdStatusElement,
      dom.osdTitleElement,
      dom.osdSubtitleElement,
      dom.osdAudioElement,
      dom.osdSubtitlesElement,
      dom.osdSleepElement,
      dom.osdSleepStatusElement,
      dom.osdUpNextElement,
      dom.osdTimecodeElement,
      dom.osdEndsAtElement,
    ].map((element) => collectText(element as unknown as ElementDouble)).join(' ');
    const optionsText = [
      dom.overlayPlaybackSummaryElement,
      dom.overlayAudioOptionsElement,
      dom.overlaySubtitleOptionsElement,
    ].map((element) => collectText(element as unknown as ElementDouble)).join(' ');

    assert.match(osdText, /PLAYING/u);
    assert.match(osdText, /The Midnight Archive/u);
    assert.match(osdText, /Signal Lost/u);
    assert.match(osdText, /Audio: Main/u);
    assert.match(osdText, /Subs: Off/u);
    assert.match(osdText, /Off/u);
    assert.match(osdText, /Sleep timer off/u);
    assert.equal(dom.osdSleepButton?.getAttribute('aria-label'), 'Sleep timer, Off');
    assert.match(osdText, /12:00 \/ 60:00/u);
    assert.match(osdText, /Runtime next/u);
    assert.match(optionsText, /Audio tracks/u);

    const audioRows = (dom.overlayAudioOptionsElement as unknown as ElementDouble).children;
    const subtitleRows = (dom.overlaySubtitleOptionsElement as unknown as ElementDouble).children;
    const audioMain = audioRows.find((row) => row.dataset.trackId === 'audio-main');
    const audioUnavailable = audioRows.find((row) => row.dataset.trackId === 'audio-unavailable');

    assert.equal(audioMain?.tagName, 'BUTTON');
    assert.equal(audioMain?.type, 'button');
    assert.equal(audioMain?.dataset.focusId, 'overlay-audio-track-audio-main');
    assert.equal(audioMain?.disabled, false);
    assert.equal(audioMain?.getAttribute('aria-busy'), 'false');
    assert.equal(audioMain?.getAttribute('aria-pressed'), 'true');
    assert.equal(audioMain?.getAttribute('aria-disabled'), null);
    assert.equal(audioMain?.dataset.overlayBusyFocusCustody, undefined);
    assert.equal(audioUnavailable, undefined);
    assert.equal(subtitleRows.length, 0);
    assert.equal((dom.overlayAudioOptionsElement as unknown as ElementDouble).hidden, false);
    assert.equal((dom.overlayAudioOptionsElement as unknown as { inert: boolean }).inert, false);
    assert.equal((dom.overlayAudioOptionsElement as unknown as ElementDouble).getAttribute('aria-hidden'), 'false');
    assert.equal((dom.overlaySubtitleOptionsElement as unknown as ElementDouble).hidden, true);
    assert.equal((dom.overlaySubtitleOptionsElement as unknown as { inert: boolean }).inert, true);
    assert.equal((dom.overlaySubtitleOptionsElement as unknown as ElementDouble).getAttribute('aria-hidden'), 'true');

    renderWorkflowDom(
      createWorkflowState('player'),
      { ...audioOptions, pendingTrackFocusId: 'overlay-audio-track-audio-main' },
      snapshot,
      dom,
      undefined,
      null,
      presentation,
    );
    const busyAudioMain = (dom.overlayAudioOptionsElement as unknown as ElementDouble).children
      .find((row) => row.dataset.trackId === 'audio-main');
    assert.equal(busyAudioMain?.disabled, false);
    assert.equal(busyAudioMain?.getAttribute('aria-disabled'), 'true');
    assert.equal(busyAudioMain?.getAttribute('aria-busy'), 'true');
    assert.equal(busyAudioMain?.dataset.overlayBusyFocusCustody, 'true');

    const errorSnapshot = {
      ...snapshot, status: 'error' as const, playing: false,
      lastError: { code: 'FAILED', category: 'engine-failure' as const, message: 'Original failure.', recoverable: true, retryable: true },
    };
    renderWorkflowDom(
      createWorkflowState('player'),
      {
        ...createPlayerOverlayState(presentation),
        retryPending: true,
        recoveryPendingAction: 'retry-current',
        retryError: 'Retry failed safely.',
      },
      errorSnapshot,
      dom,
      undefined,
      null,
      { ...presentation, playerSnapshot: errorSnapshot },
    );
    assert.equal(dom.overlayPlayerErrorElement.textContent, 'Retry failed safely.');
    assert.equal(dom.overlayPlayerRetryButton.disabled, false);
    assert.equal(dom.overlayPlayerRetryButton.getAttribute('aria-disabled'), 'true');
    assert.equal(dom.overlayPlayerRetryButton.getAttribute('aria-busy'), 'true');
    assert.equal(dom.overlayPlayerRetryButton.dataset.overlayBusyFocusCustody, 'true');
    assert.equal(dom.overlayPlayerRetryButton.hidden, false);
    assert.equal(dom.overlayPlayerSkipButton.hidden, false);
    assert.equal(dom.overlayPlayerSkipButton.getAttribute('aria-disabled'), 'true');
    assert.equal(dom.overlayPlayerSkipButton.getAttribute('aria-busy'), 'true');
    assert.equal(dom.overlayPlayerSkipButton.dataset.overlayBusyFocusCustody, 'true');
    assert.equal(dom.overlayPlayerGuideButton.hidden, true);

    renderWorkflowDom(
      createWorkflowState('player'),
      {
        ...createPlayerOverlayState(presentation),
        retryPending: true,
        recoveryPendingAction: 'skip-next',
      },
      errorSnapshot,
      dom,
      undefined,
      null,
      { ...presentation, playerSnapshot: errorSnapshot },
    );
    assert.equal(dom.overlayPlayerRetryButton.getAttribute('aria-busy'), 'true');
    assert.equal(dom.overlayPlayerRetryButton.getAttribute('aria-disabled'), 'true');
    assert.equal(dom.overlayPlayerSkipButton.getAttribute('aria-busy'), 'true');
    assert.equal(dom.overlayPlayerSkipButton.getAttribute('aria-disabled'), 'true');

    const fallbackPresentation = {
      ...presentation,
      channels: [{
        id: 'channel-one',
        number: '101',
        name: 'Channel One',
      }],
      playerSnapshot: errorSnapshot,
    };
    renderWorkflowDom(
      createWorkflowState('player'),
      createPlayerOverlayState(fallbackPresentation),
      errorSnapshot,
      dom,
      undefined,
      null,
      fallbackPresentation,
    );
    assert.equal(dom.overlayPlayerRetryButton.hidden, true);
    assert.equal(dom.overlayPlayerSkipButton.hidden, true);
    assert.equal(dom.overlayPlayerGuideButton.hidden, false);

    renderWorkflowDom(
      createWorkflowState('player'),
      {
        ...createPlayerOverlayState(presentation),
        activeOverlayId: 'miniGuide',
        miniGuideError: 'Mini failed safely.',
        pendingTuneChannelId: 'channel-one',
      },
      snapshot,
      dom,
      undefined,
      null,
      presentation,
    );
    assert.equal(dom.overlayMiniGuideErrorElement.textContent, 'Mini failed safely.');
    const busyMini = (dom.overlayMiniGuideElement as unknown as ElementDouble).children
      .find((row) => row.dataset.overlayChannelId === 'channel-one');
    assert.equal(busyMini?.disabled, false);
    assert.equal(busyMini?.getAttribute('aria-disabled'), 'true');
    assert.equal(busyMini?.getAttribute('aria-busy'), 'true');
    assert.equal(busyMini?.getAttribute('aria-current'), 'true');
    assert.equal(busyMini?.dataset.overlayBusyFocusCustody, 'true');

    for (const count of [1, 2, 4]) {
      const shortChannels = Array.from({ length: count }, (_, index) => ({
        id: `short-${index + 1}`,
        number: String(index + 1),
        name: `Short ${index + 1}`,
        currentProgram: { id: `short-program-${index + 1}`, title: `Short program ${index + 1}`, startsAtMs: 0, endsAtMs: 2_000 },
      }));
      const selectedId = shortChannels.at(-1)?.id ?? null;
      const shortPresentation = {
        ...presentation,
        channels: shortChannels,
        currentChannelId: selectedId,
      };
      renderWorkflowDom(
        createWorkflowState('player'),
        {
          ...createPlayerOverlayState(shortPresentation),
          activeOverlayId: 'miniGuide',
          miniGuideSelectedChannelId: selectedId,
        },
        snapshot,
        dom,
        undefined,
        null,
        shortPresentation,
      );
      const rows: readonly ElementDouble[] = (dom.overlayMiniGuideElement as unknown as ElementDouble).children;
      const focusIds = rows.map((row) => row.dataset.focusId);
      assert.equal(rows.length, count, `${String(count)} rendered channel rows`);
      assert.equal(new Set(focusIds).size, count, `${String(count)} unique focus ids`);
      assert.equal(rows.filter((row) => row.getAttribute('aria-current') === 'true').length, 1, `${String(count)} current rows`);
    }
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route workflow DOM leaves staged builder review policy to channelSetup/dom', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const channelList = new ElementDouble();
    const validation = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.channelDraftListElement = channelList as unknown as HTMLElement;
    dom.setupValidationElement = validation as unknown as HTMLElement;
    dom.channelSetupSourceElement = new ElementDouble() as unknown as HTMLElement;
    dom.channelSetupEnabledElement = new ElementDouble() as unknown as HTMLElement;
    dom.channelSetupBlocksElement = new ElementDouble() as unknown as HTMLElement;

    renderWorkflowDom(
      createWorkflowState('channelSetup'),
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
    );

    const renderedText = [channelList, validation].map(collectText).join(' ');
    assert.equal(renderedText.trim(), '');
    assert.doesNotMatch(renderedText, /Demo Library|The Vault|Weekend Queue|Liminal One/u);
    assert.doesNotMatch(renderedText, /serverUri|token|https?:|raw payload/u);
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route workflow DOM projects selected-library summary without overwriting staged builder policy', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });

  try {
    const source = new ElementDouble();
    const enabled = new ElementDouble();
    const blocks = new ElementDouble();
    const sourceList = new ElementDouble();
    const review = new ElementDouble();
    const validation = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.channelSetupSourceElement = source as unknown as HTMLElement;
    dom.channelSetupEnabledElement = enabled as unknown as HTMLElement;
    dom.channelSetupBlocksElement = blocks as unknown as HTMLElement;
    dom.channelDraftListElement = sourceList as unknown as HTMLElement;
    dom.channelSetupReviewElement = review as unknown as HTMLElement;
    dom.setupValidationElement = validation as unknown as HTMLElement;

    const replaceWorkflow = applyWorkflowChannelSetupAction(
      createWorkflowState('channelSetup'),
      'selectReplaceBuildMode',
    );
    renderWorkflowDom(
      replaceWorkflow,
      createPlayerOverlayState(),
      createRendererSafePlayerSnapshot(),
      dom,
      configuredChannelRuntimeState(),
      liveSelection(),
    );

    const renderedText = [source, enabled, blocks, sourceList, review, validation]
      .map(collectText)
      .join(' ');

    assert.match(renderedText, /Selected Movies/u);
    assert.match(renderedText, /1 of 1/u);
    assert.match(renderedText, /2 library items/u);
    assert.equal([sourceList, review, validation].map(collectText).join(' ').trim(), '');
  } finally {
    restoreDocument(originalDocument);
  }
});

test('route workflow DOM renders committed counts, warnings, and terminal cancellation', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const selectors = new Map<string, ElementDouble>([
    ['[data-setup-result-title]', new ElementDouble()],
    ['[data-setup-result-intro]', new ElementDouble()],
    ['[data-setup-result-mark]', new ElementDouble()],
    ['[data-channel-setup-result-detail]', new ElementDouble()],
  ]);
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: (selector: string) => selectors.get(selector) ?? null,
    createElement: (tagName: string) => new ElementDouble(tagName),
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentDouble,
    configurable: true,
  });
  try {
    const result = new ElementDouble();
    const dom = createOverlayDomBindings({
      overlayStack: new ElementDouble(),
      overlays: [],
      overlayActions: [],
    });
    dom.channelSetupResultElement = result as unknown as HTMLElement;
    const renderResult = (
      setupResult: Parameters<typeof renderChannelSetupResult>[1],
    ) => renderChannelSetupResult(dom, setupResult);
    renderResult({
      kind: 'committed',
      summary: {
        created: 2,
        removed: 1,
        unchanged: 3,
        skipped: 4,
        finalChannelCount: 5,
        reachedMaxChannels: false,
        watchChannelId: 'watch',
        byStrategy: {
          genres: { created: 2, skipped: 4 },
        },
        warnings: [
          {
            code: 'MIN_ITEMS_SKIPPED',
            phase: 'planning',
            strategy: 'genres',
            affectedCount: 4,
          },
          {
            code: 'GUIDE_REFRESH_FAILED',
            phase: 'refresh',
            strategy: null,
            affectedCount: null,
          },
          {
            code: 'EXISTING_SOURCE_UNMATCHABLE',
            phase: 'planning',
            strategy: null,
            affectedCount: 1,
          },
        ],
      } as never,
    });
    assert.match(result.textContent, /2 created, 1 removed, 3 unchanged, and 4 skipped/u);
    assert.match(collectText(selectors.get('[data-channel-setup-result-detail]')!), /Genres: 2 created, 4 skipped/u);
    assert.match(
      collectText(selectors.get('[data-channel-setup-result-detail]')!),
      /Channels below the minimum item count were skipped \(4\)\./u,
    );
    assert.match(
      collectText(selectors.get('[data-channel-setup-result-detail]')!),
      /Channels were saved, but Guide refresh did not complete\. Open Guide and retry refresh\./u,
    );
    assert.match(
      collectText(selectors.get('[data-channel-setup-result-detail]')!),
      /Some existing channels can be retained but cannot be matched or updated by Channel Builder\./u,
    );

    renderResult({ kind: 'canceled' });
    assert.equal(selectors.get('[data-setup-result-title]')?.textContent, 'Build canceled');
    assert.match(result.textContent, /stopped before the atomic save completed/u);
  } finally {
    restoreDocument(originalDocument);
  }
});

test('reachable product route text avoids internal implementation-status terms', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const selectorTextHosts = new Map<string, ElementDouble>();
  const documentDouble = {
    documentElement: { dataset: {} },
    querySelector: (selector: string) => selectorTextHosts.get(selector) ?? null,
    createElement: (tagName: string) => new ElementDouble(tagName),
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
      dom.channelDraftListElement = new ElementDouble() as unknown as HTMLElement;
      dom.setupValidationElement = new ElementDouble() as unknown as HTMLElement;
      dom.overlayPlaybackSummaryElement = new ElementDouble() as unknown as HTMLElement;
      dom.overlayAudioOptionsElement = new ElementDouble() as unknown as HTMLElement;
      dom.overlaySubtitleOptionsElement = new ElementDouble() as unknown as HTMLElement;

      const workflowState = createWorkflowState(route);
      renderRouteDom(workflowState, dom);
      renderWorkflowDom(
        workflowState,
        createPlayerOverlayState(),
        createRendererSafePlayerSnapshot(),
        dom,
      );

      const channelSetupText = [
        dom.channelSetupSourceElement,
        dom.channelSetupEnabledElement,
        dom.channelSetupBlocksElement,
        dom.channelDraftListElement,
        dom.setupValidationElement,
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
          dom.channelDraftListElement,
          dom.setupValidationElement,
          dom.overlayPlaybackSummaryElement,
          dom.overlayAudioOptionsElement,
          dom.overlaySubtitleOptionsElement,
        ].map((element) => collectText(element as ElementDouble)).join(' '),
      });
    }

    assert.doesNotMatch(
      removeApprovedDebugLabels(renderedRouteText.map(({ text }) => text).join(' ')),
      PRODUCT_ROUTE_INTERNAL_COPY_PATTERN,
    );
    const channelSetupRouteText =
      renderedRouteText.find(({ route }) => route === 'channelSetup')?.channelSetupText ?? '';
    assert.doesNotMatch(
      channelSetupRouteText,
      /Demo Library|Liminal One|The Vault|Weekend Queue|2 of 3|6 programming blocks|16 programming blocks/u,
    );
  } finally {
    restoreDocument(originalDocument);
  }
});

test('static product route visible text avoids internal implementation-status terms', () => {
  const root = { innerHTML: '', querySelector: () => null };
  const documentDouble = {
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  };

  mountStaticRendererDom(documentDouble as unknown as Document);

  assert.doesNotMatch(
    removeApprovedDebugLabels(readVisibleTextFromMarkup(root.innerHTML)),
    PRODUCT_ROUTE_INTERNAL_COPY_PATTERN,
  );
  assert.doesNotMatch(root.innerHTML, /data-channel-setup-fixture-status/u);
  assert.match(root.innerHTML, /data-staged-owner="replace-confirm" role="dialog" aria-modal="true"/u);
  assert.match(root.innerHTML, /data-setup-flow-action="cancelReplaceConfirm" data-focus-id="setup-replace-cancel"/u);
  assert.match(root.innerHTML, /data-setup-flow-action="confirmReplace" data-focus-id="setup-replace-confirm"/u);
});

test('static player DOM keeps native presentation beside the route-owned overlay stack', () => {
  const root = { innerHTML: '', querySelector: () => null };
  const documentDouble = {
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  };

  mountStaticRendererDom(documentDouble as unknown as Document);

  const presentationStart = root.innerHTML.indexOf('data-player-presentation-surface');
  const playerStart = root.innerHTML.indexOf('id="screen-player"');
  const overlayStart = root.innerHTML.indexOf('data-overlay-stack');
  assert.ok(presentationStart >= 0 && playerStart > presentationStart && overlayStart > playerStart);
  assert.match(
    root.innerHTML.slice(presentationStart, overlayStart),
    /<\/div>\s*<section id="screen-player"[^>]*>\s*<div class="overlay-stack"/u,
  );
  assert.match(root.innerHTML, /data-overlay="playbackOptions"[^>]*role="dialog"[^>]*aria-modal="true"/u);
  assert.match(root.innerHTML, /class="channel-number-overlay__label">CH</u);
  assert.match(root.innerHTML, /data-overlay-player-loading-label/u);
  assert.doesNotMatch(
    root.innerHTML,
    /poster-placeholder|clear-logo-placeholder|icon-placeholder|player-quick-actions|Volume|Playback rate|Quality/u,
  );
  const subtitleAction = root.innerHTML.indexOf('data-overlay-action="openSubtitleOptions"');
  const sleepAction = root.innerHTML.indexOf('data-overlay-action="cycleSleepTimer"');
  const audioAction = root.innerHTML.indexOf('data-overlay-action="openAudioOptions"');
  assert.ok(subtitleAction >= 0 && sleepAction > subtitleAction && audioAction > sleepAction);
  assert.match(root.innerHTML, /data-focus-id="overlay-osd-sleep"[^>]*aria-label="Sleep timer, Off"/u);
  assert.match(
    root.innerHTML,
    /class="player-osd__sleep-action"[^>]*>[\s\S]*?<span>Sleep<\/span>[\s\S]*?<strong data-osd-sleep>Off<\/strong>[\s\S]*?<\/button>/u,
  );
  assert.doesNotMatch(root.innerHTML, /data-overlay-action="(?:play|pause|seek|stop)/u);
  assert.equal((root.innerHTML.match(/class="playback-options__section"/gu) ?? []).length, 1);
});

const PRODUCT_ROUTE_INTERNAL_COPY_PATTERN =
  /\bRD-\d+[A-Z]?\b|future RD|\bruntime\b|runtime wiring|scheduler wiring|later runtime pass|pending runtime|not implemented|implementation status|roadmap|\bfixture\b|\bfake\b|\bsmoke\b|\bproof\b|\bscaffold\b|\bdebug\b|\bdraft(?:\b|\s+(?:channel|programming|source|controls|setup))|not proven here|live Plex/iu;

function removeApprovedDebugLabels(value: string): string {
  return value
    .replaceAll('Subtitle Debug Logging', '')
    .replaceAll('Debug Logging', '');
}

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

function collectVisibleText(element: ElementDouble): string {
  if (element.hidden || element.getAttribute('aria-hidden') === 'true') return '';
  return [element.textContent, ...element.children.map(collectVisibleText)].join(' ');
}

function findElementsByDataset(
  element: ElementDouble,
  key: string,
  value: string,
): ElementDouble[] {
  return [
    ...(element.dataset[key] === value ? [element] : []),
    ...element.children.flatMap((child) => findElementsByDataset(child, key, value)),
  ];
}

function findElementsByRole(element: ElementDouble, role: string): ElementDouble[] {
  return [
    ...(element.getAttribute('role') === role ? [element] : []),
    ...element.children.flatMap((child) => findElementsByRole(child, role)),
  ];
}

function findElementsByClassName(element: ElementDouble, className: string): ElementDouble[] {
  return [
    ...(element.className.split(' ').includes(className) ? [element] : []),
    ...element.children.flatMap((child) => findElementsByClassName(child, className)),
  ];
}

function findFocusIds(element: ElementDouble): string[] {
  return [
    ...(element.dataset.focusId === undefined ? [] : [element.dataset.focusId]),
    ...element.children.flatMap(findFocusIds),
  ];
}

function restoreDocument(originalDocument: Document | undefined): void {
  if (originalDocument === undefined) {
    Reflect.deleteProperty(globalThis, 'document');
    return;
  }
  Object.defineProperty(globalThis, 'document', {
    value: originalDocument,
    configurable: true,
  });
}

function configuredChannelRuntimeState(): ChannelRuntimeRendererState {
  return {
    pending: false,
    statusText: 'Recovered',
    errorText: null,
    operation: null,
    summary: {
      status: 'configured',
      lineupRevision: 1,
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
      builder: { completion: 'unknown', normalizedConfig: null, completedAtMs: null },
    },
  };
}

function liveSelection() {
  return {
    sourceName: 'Selected Movies',
    sourceType: 'movie' as const,
    contentCount: 24,
    loadedItemCount: 2,
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
    epgDetailDescriptionElement: null,
    epgDetailBackgroundElement: null,
    epgDetailBackgroundImageElement: null,
    epgDetailArtworkElement: null,
    epgDetailPosterElement: null,
    epgDetailArtworkPlaceholderElement: null,
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
    overlayElements: overlays as unknown as HTMLElement[],
    overlayStackElement: overlayStack as unknown as HTMLElement,
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
