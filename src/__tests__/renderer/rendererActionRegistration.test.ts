import assert from 'node:assert/strict';
import test from 'node:test';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { readStagedSetupFlowActionId } from '../../renderer/domBindings.js';
import { registerRendererActions } from '../../renderer/rendererActionRegistration.js';

test('renderer action registration keeps one DOM/Document/handler entrypoint', () => {
  assert.equal(registerRendererActions.length, 3);
});

test('delegated builder controls accept only the closed strategy action vocabulary', () => {
  assert.equal(readStagedSetupFlowActionId('strategyToggle:genres'), 'strategyToggle:genres');
  assert.equal(readStagedSetupFlowActionId('strategyPriorityUp:actors'), 'strategyPriorityUp:actors');
  assert.equal(readStagedSetupFlowActionId('strategyScope:collections'), 'strategyScope:collections');
  assert.equal(readStagedSetupFlowActionId('strategyToggle:unknown'), null);
  assert.equal(readStagedSetupFlowActionId('strategyToggle:genres:extra'), null);
});

test('visible ready-guide setup action delegates channel-setup navigation intent', () => {
  const originalHTMLElement = Reflect.get(globalThis, 'HTMLElement');
  Object.defineProperty(globalThis, 'HTMLElement', {
    value: TestElement,
    configurable: true,
  });

  try {
    const guideScreen = new TestElement();
    const editLineup = new TestElement();
    editLineup.dataset.guideAction = 'setup';
    editLineup.dataset.focusId = 'guide-state-setup';
    const guideActions: string[] = [];
    const documentDouble = {
      getElementById: (id: string) => id === 'screen-guide' ? guideScreen : null,
      addEventListener: () => undefined,
    };

    registerRendererActions(
      createActionDomBindings(),
      documentDouble as unknown as Document,
      {
        activateRoute: () => undefined,
        applyRouteAction: () => undefined,
        applySettingsAction: () => undefined,
        applyChannelSetupAction: () => undefined,
        applyEpgAction: () => undefined,
        applyGuideAction: (action) => { guideActions.push(action); },
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

    assert.equal(editLineup.hidden, false);
    guideScreen.emit('click', editLineup);
    assert.deepEqual(guideActions, ['setup']);
  } finally {
    if (originalHTMLElement === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLElement');
    } else {
      Object.defineProperty(globalThis, 'HTMLElement', {
        value: originalHTMLElement,
        configurable: true,
      });
    }
  }
});

test('visible delegated builder and replacement-modal controls activate through the staged action seam', () => {
  const originalHTMLElement = Reflect.get(globalThis, 'HTMLElement');
  Object.defineProperty(globalThis, 'HTMLElement', { value: TestElement, configurable: true });
  try {
    const setupScreen = new TestElement();
    const actions: string[] = [];
    registerRendererActions(
      createActionDomBindings(),
      {
        getElementById: (id: string) => id === 'screen-channel-setup' ? setupScreen : null,
        addEventListener: () => undefined,
      } as unknown as Document,
      {
        activateRoute: () => undefined, applyRouteAction: () => undefined,
        applySettingsAction: () => undefined, applyChannelSetupAction: () => undefined,
        applyEpgAction: () => undefined, applyOverlayAction: () => undefined,
        applyPlexRuntimeAction: () => undefined, setPlexHomeUserPin: () => undefined,
        setPlexSearchQuery: () => undefined, selectPlexHomeUser: () => undefined,
        selectPlexServer: () => undefined, selectPlexSection: () => undefined,
        openPlexMetadata: () => undefined, focusElement: () => undefined,
        toggleFullscreen: () => undefined, selectAudioTrack: () => undefined,
        selectSubtitleTrack: () => undefined,
        applyStagedSetupAction: (action) => { actions.push(action); },
      },
    );
    for (const action of ['strategyToggle:genres', 'openReplaceConfirm', 'cancelReplaceConfirm', 'confirmReplace']) {
      const button = new TestElement();
      button.dataset.setupFlowAction = action;
      setupScreen.emit('click', button);
    }
    const disabled = new TestElement();
    disabled.disabled = true;
    disabled.dataset.setupFlowAction = 'strategyPriorityUp:genres';
    setupScreen.emit('click', disabled);
    assert.deepEqual(actions, [
      'strategyToggle:genres', 'openReplaceConfirm', 'cancelReplaceConfirm', 'confirmReplace',
    ]);
  } finally {
    if (originalHTMLElement === undefined) Reflect.deleteProperty(globalThis, 'HTMLElement');
    else Object.defineProperty(globalThis, 'HTMLElement', { value: originalHTMLElement, configurable: true });
  }
});

class TestElement {
  hidden = false;
  disabled = false;
  readonly dataset: Record<string, string> = {};
  private readonly listeners = new Map<string, ((event: { target: TestElement }) => void)[]>();

  addEventListener(type: string, listener: (event: { target: TestElement }) => void): void {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  emit(type: string, target: TestElement): void {
    for (const listener of this.listeners.get(type) ?? []) listener({ target });
  }

  closest<T>(selector: string): T | null {
    if (selector === '[data-guide-action]' && this.dataset.guideAction !== undefined) {
      return this as unknown as T;
    }
    if (selector === '[data-setup-flow-action]' && this.dataset.setupFlowAction !== undefined) {
      return this as unknown as T;
    }
    return null;
  }

  getAttribute(): string | null {
    return null;
  }
}

function createActionDomBindings(): RendererDomBindings {
  return {
    routeButtons: [],
    routeActionButtons: [],
    setupActionButtons: [],
    epgActionButtons: [],
    overlayActionButtons: [],
    plexActionButtons: [],
    fullscreenButton: null,
    playerPresentationElement: null,
    plexHomeUserPinInput: null,
    plexSearchQueryInput: null,
    customChannelNameInput: null,
    customChannelNumberInput: null,
    customChannelSearchInput: null,
    plexPanelElement: null,
    overlayAudioOptionsElement: null,
    overlaySubtitleOptionsElement: null,
    overlayMiniGuideElement: null,
  } as unknown as RendererDomBindings;
}
