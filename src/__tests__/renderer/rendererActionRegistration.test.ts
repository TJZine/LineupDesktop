import assert from 'node:assert/strict';
import test from 'node:test';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { registerRendererActions } from '../../renderer/rendererActionRegistration.js';

test('renderer action registration keeps one DOM/Document/handler entrypoint', () => {
  assert.equal(registerRendererActions.length, 3);
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
