import assert from 'node:assert/strict';
import test from 'node:test';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { FocusRegistry, type FocusState } from '../../renderer/navigation.js';
import {
  activateInfoRecovery,
  createNavigationLifecycle,
  type NavigationLifecycleOptions,
} from '../../renderer/shell/navigationLifecycle.js';
import {
  createRendererShellState,
  type RendererShellState,
} from '../../renderer/shell/shellState.js';

function createHarness(
  handleGuideDirection: NavigationLifecycleOptions['handleGuideDirection'],
  handlePlayerInput?: NavigationLifecycleOptions['handlePlayerInput'],
  routeActivationAllowed = true,
  handleGuidePage?: NavigationLifecycleOptions['handleGuidePage'],
) {
  const registry = new FocusRegistry();
  registry.register({ id: 'player-guide', route: 'player', order: 0 });
  registry.register({ id: 'player-settings', route: 'player', order: 1 });
  registry.register({ id: 'guide-program-one--current', route: 'guide', order: 0 });
  registry.register({ id: 'guide-program-one--next', route: 'guide', order: 1 });
  let route: 'player' | 'guide' = 'guide';
  let focus: FocusState = { activeRoute: 'guide', activeId: 'guide-program-one--current' };
  let shellState: RendererShellState = {
    ...createRendererShellState(),
    bootstrap: 'ready',
  };
  let playerPresentationFocusCount = 0;
  let profileModalActive = false;
  let infoRecoveryCount = 0;
  const dom = {
    focusableElements: [],
    routeActionButtons: [],
    epgActionButtons: [],
    settingsActionButtons: [],
    setupActionButtons: [],
    plexActionButtons: [],
    overlayActionButtons: [],
    playerPresentationElement: {
      focus: () => {
        playerPresentationFocusCount += 1;
      },
    },
  } as unknown as RendererDomBindings;
  const lifecycle = createNavigationLifecycle({
    getRoute: () => route,
    getFocusState: () => focus,
    setFocusState: (state) => { focus = state; },
    getShellState: () => shellState,
    setShellState: (state) => { shellState = state; },
    render: () => undefined,
    focusRegistry: registry,
    dom,
    onFocusChanged: () => undefined,
    scrollFocusedIntoView: () => undefined,
    handleGuideDirection,
    handleGuidePage,
    handlePlayerInput,
    activateRoute: (nextRoute) => {
      if (!routeActivationAllowed) return false;
      route = nextRoute as 'player' | 'guide';
      return true;
    },
    isProfileModalActive: () => profileModalActive,
    closeProfileModal: () => { profileModalActive = false; },
    openInfoRecovery: () => { infoRecoveryCount += 1; },
    handleChannelSetupBack: async () => false,
    dismissInlineError: () => undefined,
    requestFullscreen: async () => undefined,
    invalidateFullscreenRequest: () => undefined,
    closeWindow: () => undefined,
  });
  return {
    lifecycle,
    getFocus: () => focus,
    setFocus: (state: FocusState) => { focus = state; },
    getRoute: () => route,
    setRoute: (nextRoute: 'player' | 'guide') => { route = nextRoute; },
    getPlayerPresentationFocusCount: () => playerPresentationFocusCount,
    unregister: (focusId: string) => registry.unregister(focusId),
    setProfileModalActive: (active: boolean) => { profileModalActive = active; },
    getInfoRecoveryCount: () => infoRecoveryCount,
  };
}

test('Guide directional first refusal runs before generic focus movement', async () => {
  const directions: string[] = [];
  const intercepted = createHarness((direction) => { directions.push(direction); return true; });
  await intercepted.lifecycle.handleInput('right');
  assert.deepEqual(directions, ['right']);
  assert.equal(intercepted.getFocus().activeId, 'guide-program-one--current');

  const fallback = createHarness(() => false);
  await fallback.lifecycle.handleInput('right');
  assert.equal(fallback.getFocus().activeId, 'guide-program-one--next');
});

test('Info recovery enters exactly one selected stage only after route activation succeeds', () => {
  const stages: string[] = [];
  let activationCount = 0;
  assert.equal(activateInfoRecovery(
    () => { activationCount += 1; return false; },
    () => { stages.push('account'); },
  ), false);
  assert.equal(activationCount, 1);
  assert.equal(stages.length, 0);

  assert.equal(activateInfoRecovery(
    () => { activationCount += 1; return true; },
    () => { stages.push('account'); },
  ), true);
  assert.equal(activationCount, 2);
  assert.deepEqual(stages, ['account']);

  assert.equal(activateInfoRecovery(
    () => { activationCount += 1; return true; },
    () => { stages.push('server'); },
  ), true);
  assert.equal(activationCount, 3);
  assert.deepEqual(stages, ['account', 'server']);
});

test('Guide pages by five through its owner and protected profile state suppresses Info and Player input', async () => {
  const pageOffsets: number[] = [];
  const playerInputs: string[] = [];
  const harness = createHarness(
    () => false,
    (input) => { playerInputs.push(input); return input === 'space'; },
    true,
    (offset) => { pageOffsets.push(offset); return true; },
  );
  await harness.lifecycle.handleInput('pageDown');
  await harness.lifecycle.handleInput('pageUp');
  assert.deepEqual(pageOffsets, [5, -5]);

  harness.setRoute('player');
  harness.setProfileModalActive(true);
  await harness.lifecycle.handleInput('info');
  await harness.lifecycle.handleInput('space');
  assert.equal(harness.getInfoRecoveryCount(), 0);
  assert.deepEqual(playerInputs, []);
  harness.setProfileModalActive(false);
  await harness.lifecycle.handleInput('info');
  assert.equal(harness.getInfoRecoveryCount(), 1);
  assert.deepEqual(playerInputs, ['info']);
});

test('Guide Back restores the exact reachable Player invoker', async () => {
  const harness = createHarness(() => false);
  harness.setRoute('player');
  harness.setFocus({ activeRoute: 'player', activeId: 'player-settings' });
  await harness.lifecycle.handleInput('guide');
  assert.equal(harness.getRoute(), 'guide');
  assert.equal(harness.getFocus().activeId, 'guide-program-one--current');
  await harness.lifecycle.handleInput('back');
  assert.equal(harness.getRoute(), 'player');
  assert.equal(harness.getFocus().activeId, 'player-settings');
});

test('Guide shortcut preserves an explicitly unfocused Player return', async () => {
  const harness = createHarness(() => false);
  harness.setRoute('player');
  harness.setFocus({ activeRoute: 'player', activeId: null });
  await harness.lifecycle.handleInput('guide');
  await harness.lifecycle.handleInput('back');
  assert.equal(harness.getRoute(), 'player');
  assert.equal(harness.getFocus().activeId, null);
});

test('rejected route activation preserves the current route and focus', async () => {
  const harness = createHarness(() => false, undefined, false);
  harness.setRoute('player');
  harness.setFocus({ activeRoute: 'player', activeId: 'player-settings' });

  await harness.lifecycle.handleInput('guide');

  assert.equal(harness.getRoute(), 'player');
  assert.deepEqual(harness.getFocus(), {
    activeRoute: 'player',
    activeId: 'player-settings',
  });
});

test('Guide Back falls back only for absent memory or a disappeared invoker', async () => {
  const absent = createHarness(() => false);
  await absent.lifecycle.handleInput('back');
  assert.equal(absent.getRoute(), 'player');
  assert.equal(absent.getFocus().activeId, 'player-guide');

  const missing = createHarness(() => false);
  missing.setRoute('player');
  missing.setFocus({ activeRoute: 'player', activeId: 'player-settings' });
  await missing.lifecycle.handleInput('guide');
  missing.unregister('player-settings');
  await missing.lifecycle.handleInput('back');
  assert.equal(missing.getRoute(), 'player');
  assert.equal(missing.getFocus().activeId, 'player-guide');
});

test('cleanup makes later Guide input inert', async () => {
  let calls = 0;
  const harness = createHarness(() => { calls += 1; return true; });
  harness.lifecycle.cleanup();
  await harness.lifecycle.handleInput('left');
  assert.equal(calls, 0);
});

test('canceling exit restores the unfocused Player presentation surface', async () => {
  const harness = createHarness(() => false, () => false);
  harness.setRoute('player');
  harness.setFocus({ activeRoute: 'player', activeId: null });

  await harness.lifecycle.handleInput('back');
  harness.lifecycle.cancelExit();

  assert.deepEqual(harness.getFocus(), { activeRoute: 'player', activeId: null });
  assert.equal(harness.getPlayerPresentationFocusCount(), 1);
});

test('Player first refusal runs before generic focus, OK, Back, and route shortcuts', async () => {
  const inputs: string[] = [];
  const harness = createHarness(() => false, (input) => { inputs.push(input); return true; });
  harness.setRoute('player');
  harness.setFocus({ activeRoute: 'player', activeId: null });
  for (const input of ['up', 'ok', 'back', 'info', 'digit4', 'space'] as const) {
    await harness.lifecycle.handleInput(input);
  }
  assert.deepEqual(inputs, ['up', 'ok', 'back', 'info', 'digit4', 'space']);
  assert.equal(harness.getRoute(), 'player');
});
