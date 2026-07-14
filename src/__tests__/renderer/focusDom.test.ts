import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { renderRendererFocus, syncRendererFocusTargets } from '../../renderer/focusDom.js';
import { FocusRegistry } from '../../renderer/navigation.js';
import { getStagedSetupNeighbors } from '../../renderer/setup/stagedSetupFocus.js';

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
    if (selector === '.profile-pin-modal') {
      return null;
    }
    if (selector === '[data-screen]') {
      if (this.focusId.startsWith('shell-') || this.focusId.startsWith('exit-confirm-')) {
        return null;
      }
      return { dataset: { screen: this.dataset.routeButton ?? 'channelSetup' } };
    }
    assert.ok(selector === '[hidden], [aria-hidden="true"]' || selector === '[hidden],[inert],[aria-hidden="true"]');
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
    const visibleInactive = new FocusElementDouble('player-fullscreen');
    const visibleActive = new FocusElementDouble('guide-window-next');
    const dom = createFocusDomBindings([hiddenActive, visibleInactive, visibleActive]);

    renderRendererFocus({ activeRoute: 'guide', activeId: 'guide-hidden-action' }, dom);

    assert.equal(hiddenActive.className, 'is-focused');
    assert.equal(hiddenActive.tabIndex, -1);
    assert.equal(hiddenActive.focusCount, 0);
    assert.equal(documentDouble.activeElement, null);
    assert.equal(visibleInactive.tabIndex, -1);

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

test('focus sync excludes controls inside inactive hidden setup sections', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const visibleStage = new FocusElementDouble('setup-stage-account');
  const visibleServerControl = new FocusElementDouble('plex-restore-server');
  const hiddenServerControl = new FocusElementDouble('plex-restore-server', true);
  let queryElements = [visibleStage, visibleServerControl];
  const documentWithFocusableQuery = {
    querySelectorAll: () => queryElements,
    activeElement: null,
  };
  Object.defineProperty(globalThis, 'document', {
    value: documentWithFocusableQuery,
    configurable: true,
  });

  try {
    const registry = new FocusRegistry();
    const dom = createFocusDomBindings([]);

    syncRendererFocusTargets(registry, dom);
    assert.deepEqual(dom.focusableElements.map((element) => element.dataset.focusId), [
      'setup-stage-account',
      'plex-restore-server',
    ]);
    assert.deepEqual(registry.focusTarget(
      { activeRoute: 'channelSetup', activeId: 'setup-stage-account' },
      'plex-restore-server',
    ).state, {
      activeRoute: 'channelSetup',
      activeId: 'plex-restore-server',
    });

    queryElements = [visibleStage, hiddenServerControl];
    syncRendererFocusTargets(registry, dom);
    assert.deepEqual(dom.focusableElements.map((element) => element.dataset.focusId), ['setup-stage-account']);
    assert.deepEqual(registry.focusTarget(
      { activeRoute: 'channelSetup', activeId: 'setup-stage-account' },
      'plex-restore-server',
    ).state, {
      activeRoute: 'channelSetup',
      activeId: 'setup-stage-account',
    });
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

test('channel setup initial focus starts on onboarding controls with no global route rail', () => {
  const registry = new FocusRegistry();
  const requestPin = new FocusElementDouble('btn-auth-request', false, undefined, 'requestPin');
  const dom = createFocusDomBindings([requestPin]);
  dom.plexActionButtons = [requestPin] as unknown as HTMLButtonElement[];

  syncRendererFocusTargets(registry, dom);

  assert.deepEqual(registry.createInitialState('channelSetup'), {
    activeRoute: 'channelSetup',
    activeId: 'btn-auth-request',
  });
  assert.deepEqual(registry.move(registry.createInitialState('channelSetup'), 'down').state, {
    activeRoute: 'channelSetup',
    activeId: 'btn-auth-request',
  });
  assert.equal(dom.focusableElements.some((element) => element.dataset.focusId?.startsWith('nav-')), false);
});

test('Package 2 auth, server, and PIN owners follow the refrozen focus graphs', () => {
  const authRegistry = new FocusRegistry();
  const retry = new FocusElementDouble('btn-auth-retry', false, undefined, 'requestPin');
  const cancel = new FocusElementDouble('btn-auth-cancel', false, undefined, 'dismissPinError');
  const authDom = createFocusDomBindings([retry, cancel]);
  authDom.plexActionButtons = [retry, cancel] as unknown as HTMLButtonElement[];
  syncRendererFocusTargets(authRegistry, authDom);
  const authInitial = authRegistry.createInitialState('channelSetup');
  assert.equal(authInitial.activeId, 'btn-auth-retry');
  assert.equal(authRegistry.move(authInitial, 'down').state.activeId, 'btn-auth-cancel');
  assert.equal(authRegistry.move({ ...authInitial, activeId: 'btn-auth-cancel' }, 'up').state.activeId, 'btn-auth-retry');

  const pinRegistry = new FocusRegistry();
  const pinTargets = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'backspace', '0', 'cancel']
    .map((id) => new FocusElementDouble(`btn-profile-pin-${id}`));
  const pinDom = createFocusDomBindings(pinTargets);
  syncRendererFocusTargets(pinRegistry, pinDom);
  const center = pinRegistry.focusTarget(pinRegistry.createInitialState('channelSetup'), 'btn-profile-pin-5').state;
  assert.equal(pinRegistry.move(center, 'up').state.activeId, 'btn-profile-pin-2');
  assert.equal(pinRegistry.move(center, 'down').state.activeId, 'btn-profile-pin-8');
  assert.equal(pinRegistry.move(center, 'left').state.activeId, 'btn-profile-pin-4');
  assert.equal(pinRegistry.move(center, 'right').state.activeId, 'btn-profile-pin-6');
});

test('shell focus owners register only while visible and follow the refrozen graphs', () => {
  const registry = new FocusRegistry();
  const retry = new FocusElementDouble('shell-error-retry');
  const exit = new FocusElementDouble('shell-error-exit');
  const hiddenPlayer = new FocusElementDouble('player-fullscreen', true);
  const dom = createFocusDomBindings([retry, exit, hiddenPlayer]);

  syncRendererFocusTargets(registry, dom);
  const initial = registry.createInitialState('player');
  assert.deepEqual(initial, { activeRoute: 'player', activeId: 'shell-error-retry' });
  assert.equal(registry.move(initial, 'down').state.activeId, 'shell-error-exit');
  assert.equal(registry.move(initial, 'left').state.activeId, 'shell-error-retry');
  assert.equal(registry.focusTarget(initial, 'player-fullscreen').state.activeId, 'shell-error-retry');
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

test('Package 3 fixed setup owners use the refrozen linear focus graphs', () => {
  assert.deepEqual(getStagedSetupNeighbors('setup-preview-toggle', null), {
    up: 'channel-strategy-build-custom', down: 'setup-next', left: 'setup-category-build', right: 'setup-preview-toggle',
  });
  assert.deepEqual(getStagedSetupNeighbors('setup-category-build', null), {
    up: 'setup-category-build', down: 'setup-category-build', left: 'setup-category-build', right: 'channel-strategy-build-append',
  });
  assert.deepEqual(getStagedSetupNeighbors('custom-channel-save', null), {
    up: 'custom-channel-number', down: 'custom-channel-cancel', left: 'custom-channel-save', right: 'custom-channel-save',
  });
  assert.deepEqual(getStagedSetupNeighbors('custom-delete-confirm', null), {
    up: 'custom-delete-cancel', down: 'custom-delete-confirm', left: 'custom-delete-confirm', right: 'custom-delete-confirm',
  });
});

test('Package 3 active setup owners expose exact DOM-backed retry and build edges', () => {
  const empty = activeOwnerDocument('library', ['setup-library-retry', 'setup-back']);
  assert.deepEqual(getStagedSetupNeighbors('setup-library-retry', empty), {
    up: 'setup-library-retry', down: 'setup-back', left: 'setup-library-retry', right: 'setup-library-retry',
  });
  assert.deepEqual(getStagedSetupNeighbors('setup-back', empty), {
    up: 'setup-library-retry', down: 'setup-back', left: 'setup-back', right: 'setup-back',
  });

  const recovery = activeOwnerDocument('recovery-error', ['setup-error-retry', 'setup-error-back']);
  assert.deepEqual(getStagedSetupNeighbors('setup-error-retry', recovery), {
    up: 'setup-error-retry', down: 'setup-error-back', left: 'setup-error-retry', right: 'setup-error-retry',
  });
  assert.deepEqual(getStagedSetupNeighbors('setup-error-back', recovery), {
    up: 'setup-error-retry', down: 'setup-error-back', left: 'setup-error-back', right: 'setup-error-back',
  });

  const append = activeOwnerDocument('build', ['setup-back', 'setup-confirm']);
  assert.equal(getStagedSetupNeighbors('setup-back', append)?.down, 'setup-confirm');
  assert.equal(getStagedSetupNeighbors('setup-confirm', append)?.up, 'setup-back');
  const replace = activeOwnerDocument('build', ['setup-replace-confirm', 'setup-back', 'setup-confirm']);
  assert.equal(getStagedSetupNeighbors('setup-replace-confirm', replace)?.down, 'setup-back');
  assert.equal(getStagedSetupNeighbors('setup-back', replace)?.up, 'setup-replace-confirm');
  assert.equal(getStagedSetupNeighbors('setup-back', replace)?.down, 'setup-confirm');

  const selectedReplace = activeOwnerDocument('preview', [
    'setup-category-build', 'channel-strategy-build-append', 'channel-strategy-build-replace', 'channel-strategy-build-custom',
  ], 'channel-strategy-build-replace');
  assert.equal(getStagedSetupNeighbors('setup-category-build', selectedReplace)?.right, 'channel-strategy-build-replace');
});

test('Package 3 custom editor uses one visible enabled DOM-order focus graph', () => {
  const doc = activeOwnerDocument('custom-edit', [
    'custom-channel-name', 'custom-channel-number', 'custom-channel-hidden', 'custom-draft-remove-0',
    'custom-channel-search-query', 'custom-channel-browse', 'custom-channel-search', 'custom-channel-clear-search',
    'custom-channel-filter-all', 'custom-channel-filter-movies', 'custom-channel-filter-episodes',
    'custom-media-close-details', 'custom-media-details-rating-1', 'custom-media-add-rating-1',
    'custom-channel-save', 'custom-channel-cancel',
  ]);
  assert.deepEqual(getStagedSetupNeighbors('custom-draft-remove-0', doc), {
    up: 'custom-channel-hidden', down: 'custom-channel-search-query', left: 'custom-draft-remove-0', right: 'custom-draft-remove-0',
  });
  assert.deepEqual(getStagedSetupNeighbors('custom-media-add-rating-1', doc), {
    up: 'custom-media-details-rating-1', down: 'custom-channel-save', left: 'custom-media-add-rating-1', right: 'custom-media-add-rating-1',
  });
  assert.equal(getStagedSetupNeighbors('custom-channel-cancel', doc)?.down, 'custom-channel-cancel');
});

function activeOwnerDocument(owner: string, ids: readonly string[], selectedId?: string): Document {
  const elements = ids.map((id) => ({
    dataset: { focusId: id }, disabled: false, closest: () => null,
    classList: { contains: (name: string) => name === 'selected' && id === selectedId },
    getAttribute: (name: string) => name === 'aria-pressed' && id === selectedId ? 'true' : null,
  }));
  const root = { querySelectorAll: () => elements };
  return {
    documentElement: { dataset: { setupOwner: owner } },
    querySelector: (selector: string) => {
      if (selector === `[data-staged-owner="${owner}"]`) return root;
      const focusId = selector.match(/^\[data-focus-id="(.+)"\]$/u)?.[1];
      return elements.find((element) => element.dataset.focusId === focusId) ?? null;
    },
    querySelectorAll: () => elements,
  } as unknown as Document;
}

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
