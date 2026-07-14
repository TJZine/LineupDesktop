import test from 'node:test';
import assert from 'node:assert/strict';

import {
  FocusRegistry,
  createRouteState,
  mapDesktopKeyEvent,
  setRoute,
  type AppRouteId,
  type FocusState,
} from '../../renderer/navigation.js';
import { createNavigationLifecycle } from '../../renderer/shell/navigationLifecycle.js';
import { createRendererShellState, rejectFullscreenRequest } from '../../renderer/shell/shellState.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';

test('renderer route state records the previous route without changing unchanged routes', () => {
  const initial = createRouteState();
  assert.deepEqual(initial, { activeRoute: 'player', previousRoute: null });

  const guide = setRoute(initial, 'guide');
  assert.deepEqual(guide, { activeRoute: 'guide', previousRoute: 'player' });
  assert.equal(setRoute(guide, 'guide'), guide);
});

test('focus registry keeps focus scoped to the active route', () => {
  const registry = new FocusRegistry();
  registry.register({ id: 'player-nav', route: 'player', order: 0 });
  registry.register({
    id: 'player-action',
    route: 'player',
    order: 1,
    neighbors: { up: 'player-nav' },
  });
  registry.register({ id: 'guide-nav', route: 'guide', order: 0 });

  const initial = registry.createInitialState('player');
  assert.deepEqual(initial, { activeRoute: 'player', activeId: 'player-nav' });

  const moved = registry.move(initial, 'down');
  assert.equal(moved.changed, true);
  assert.deepEqual(moved.state, { activeRoute: 'player', activeId: 'player-action' });

  const guide = registry.focusRoute(moved.state, 'guide');
  assert.equal(guide.changed, true);
  assert.deepEqual(guide.state, { activeRoute: 'guide', activeId: 'guide-nav' });

  const guideMove = registry.move(guide.state, 'down');
  assert.equal(guideMove.changed, false);
  assert.equal(guideMove.state.activeId, 'guide-nav');
});

test('focus registry remembers route-owned targets without global nav targets', () => {
  const registry = new FocusRegistry();
  registry.register({ id: 'player-fullscreen', route: 'player', order: 0 });
  registry.register({ id: 'guide-window-next', route: 'guide', order: 0 });
  registry.register({ id: 'settings-cat-playback', route: 'settings', order: 0 });

  const initial = registry.createInitialState('player');
  assert.deepEqual(initial, { activeRoute: 'player', activeId: 'player-fullscreen' });
  assert.deepEqual(registry.focusRoute(initial, 'guide').state, {
    activeRoute: 'guide',
    activeId: 'guide-window-next',
  });
});

test('navigation lifecycle preserves shortcuts, route focus memory, exit restore, and inline-error precedence', async () => {
  let route: AppRouteId = 'player';
  let focus: FocusState = { activeRoute: route, activeId: 'player-fullscreen' };
  let shell = createRendererShellState();
  shell = { ...shell, bootstrap: 'ready' };
  let closed = 0;
  const lifecycle = createNavigationLifecycle({
    getRoute: () => route,
    getFocusState: () => focus,
    setFocusState: (state) => { focus = state; },
    getShellState: () => shell,
    setShellState: (state) => { shell = state; },
    render: () => undefined,
    focusRegistry: createLifecycleFocusRegistry(),
    dom: createLifecycleDomBindings(),
    onFocusChanged: () => undefined,
    scrollFocusedIntoView: () => undefined,
    activateRoute: (nextRoute) => { route = nextRoute; },
    isProfileModalActive: () => false,
    closeProfileModal: () => undefined,
    handleChannelSetupBack: async () => false,
    handlePlayerOverlayBack: () => false,
    dismissInlineError: () => { shell = { ...shell, inlineError: null }; focus = { ...focus, activeId: 'player-fullscreen' }; },
    requestFullscreen: async () => undefined,
    invalidateFullscreenRequest: () => undefined,
    closeWindow: () => { closed += 1; },
  });

  await lifecycle.handleInput('guide');
  assert.equal(route, 'guide');
  focus = { activeRoute: 'guide', activeId: 'guide-window-next' };
  await lifecycle.handleInput('settings');
  await lifecycle.handleInput('guide');
  assert.equal(focus.activeId, 'guide-window-next');
  await lifecycle.handleInput('back');
  assert.equal(route, 'player');
  await lifecycle.handleInput('back');
  assert.equal(shell.exitConfirmOpen, true);
  assert.equal(focus.activeId, 'exit-confirm-cancel');
  lifecycle.cancelExit();
  assert.equal(focus.activeId, 'player-fullscreen');
  await lifecycle.handleInput('back');
  lifecycle.confirmExit();
  lifecycle.confirmExit();
  assert.equal(closed, 1);

  shell = rejectFullscreenRequest({ ...shell, exitConfirmOpen: false }, true);
  await lifecycle.handleInput('back');
  assert.equal(shell.inlineError, null);
  assert.equal(focus.activeId, 'player-fullscreen');
});

test('desktop key mapping normalizes keyboard and remote-like input', () => {
  assert.equal(mapDesktopKeyEvent({ key: 'ArrowUp' }), 'up');
  assert.equal(mapDesktopKeyEvent({ key: 'Enter' }), 'ok');
  assert.equal(mapDesktopKeyEvent({ key: 'Escape' }), 'back');
  assert.equal(mapDesktopKeyEvent({ key: 'g' }), 'guide');
  assert.equal(mapDesktopKeyEvent({ key: 'S' }), 'settings');
  assert.equal(mapDesktopKeyEvent({ key: 'F' }), 'fullscreen');
  assert.equal(mapDesktopKeyEvent({ key: 'Unidentified', code: 'BrowserBack' }), 'back');
  assert.equal(mapDesktopKeyEvent({ key: 'Unidentified' }), null);
});

function createLifecycleFocusRegistry(): FocusRegistry {
  const registry = new FocusRegistry();
  registry.register({ id: 'player-fullscreen', route: 'player', order: 0 });
  registry.register({ id: 'guide-first', route: 'guide', order: 0 });
  registry.register({ id: 'guide-window-next', route: 'guide', order: 1 });
  registry.register({ id: 'settings-first', route: 'settings', order: 0 });
  registry.register({ id: 'exit-confirm-cancel', route: 'player', order: -2 });
  registry.register({ id: 'exit-confirm-exit', route: 'player', order: -1 });
  return registry;
}

function createLifecycleDomBindings(): RendererDomBindings {
  return {
    fullscreenButton: null,
    routeButtons: [],
    routeActionButtons: [],
    settingsActionButtons: [],
    setupActionButtons: [],
    channelCommitButtons: [],
    epgActionButtons: [],
    overlayActionButtons: [],
    plexActionButtons: [],
    focusableElements: [],
    plexPanelElement: null,
    plexHomeUsersElement: null,
    plexServersElement: null,
    plexSectionsElement: null,
    plexItemsElement: null,
    customChannelPanelElement: null,
  } as unknown as RendererDomBindings;
}
