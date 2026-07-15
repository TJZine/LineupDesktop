import assert from 'node:assert/strict';
import test from 'node:test';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { FocusRegistry, type FocusState } from '../../renderer/navigation.js';
import { createNavigationLifecycle, type NavigationLifecycleOptions } from '../../renderer/shell/navigationLifecycle.js';
import { createRendererShellState } from '../../renderer/shell/shellState.js';

function createHarness(handleGuideDirection: NavigationLifecycleOptions['handleGuideDirection']) {
  const registry = new FocusRegistry();
  registry.register({ id: 'player-guide', route: 'player', order: 0 });
  registry.register({ id: 'player-settings', route: 'player', order: 1 });
  registry.register({ id: 'guide-program-one--current', route: 'guide', order: 0 });
  registry.register({ id: 'guide-program-one--next', route: 'guide', order: 1 });
  let route: 'player' | 'guide' = 'guide';
  let focus: FocusState = { activeRoute: 'guide', activeId: 'guide-program-one--current' };
  const dom = { focusableElements: [] } as unknown as RendererDomBindings;
  const lifecycle = createNavigationLifecycle({
    getRoute: () => route,
    getFocusState: () => focus,
    setFocusState: (state) => { focus = state; },
    getShellState: () => ({ ...createRendererShellState(), bootstrap: 'ready' }),
    setShellState: () => undefined,
    render: () => undefined,
    focusRegistry: registry,
    dom,
    onFocusChanged: () => undefined,
    scrollFocusedIntoView: () => undefined,
    handleGuideDirection,
    activateRoute: (nextRoute) => { route = nextRoute as 'player' | 'guide'; },
    isProfileModalActive: () => false,
    closeProfileModal: () => undefined,
    handleChannelSetupBack: async () => false,
    handlePlayerOverlayBack: () => false,
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
    unregister: (focusId: string) => registry.unregister(focusId),
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
