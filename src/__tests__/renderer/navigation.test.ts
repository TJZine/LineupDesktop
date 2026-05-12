import test from 'node:test';
import assert from 'node:assert/strict';

import {
  FocusRegistry,
  createRouteState,
  mapDesktopKeyEvent,
  setRoute,
} from '../../renderer/navigation.js';

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

test('focus registry keeps primary route targets reachable from any active route', () => {
  const registry = new FocusRegistry();
  registry.register({ id: 'nav-player', route: 'player', order: 0, scope: 'global' });
  registry.register({ id: 'nav-guide', route: 'guide', order: 1, scope: 'global' });
  registry.register({ id: 'nav-settings', route: 'settings', order: 2, scope: 'global' });
  registry.register({
    id: 'nav-channel-setup',
    route: 'channelSetup',
    order: 3,
    scope: 'global',
  });
  registry.register({
    id: 'player-fullscreen',
    route: 'player',
    order: 100,
    neighbors: { left: 'nav-player' },
  });

  const initial = registry.createInitialState('player');
  assert.deepEqual(initial, { activeRoute: 'player', activeId: 'nav-player' });

  const guide = registry.move(initial, 'down');
  assert.equal(guide.changed, true);
  assert.deepEqual(guide.state, { activeRoute: 'player', activeId: 'nav-guide' });

  const settings = registry.move(guide.state, 'down');
  assert.equal(settings.changed, true);
  assert.deepEqual(settings.state, { activeRoute: 'player', activeId: 'nav-settings' });

  const channelSetup = registry.move(settings.state, 'down');
  assert.equal(channelSetup.changed, true);
  assert.deepEqual(channelSetup.state, {
    activeRoute: 'player',
    activeId: 'nav-channel-setup',
  });

  const focusedGuideRoute = registry.focusRoute(channelSetup.state, 'guide');
  assert.equal(focusedGuideRoute.changed, true);
  assert.deepEqual(focusedGuideRoute.state, { activeRoute: 'guide', activeId: 'nav-guide' });
});

test('focus registry accepts browser focus on global primary route targets', () => {
  const registry = new FocusRegistry();
  registry.register({ id: 'nav-player', route: 'player', order: 0, scope: 'global' });
  registry.register({ id: 'nav-guide', route: 'guide', order: 1, scope: 'global' });
  registry.register({ id: 'player-fullscreen', route: 'player', order: 100 });

  const initial = registry.createInitialState('player');
  const tabbedToGuide = registry.focusTarget(initial, 'nav-guide');
  assert.equal(tabbedToGuide.changed, true);
  assert.deepEqual(tabbedToGuide.state, { activeRoute: 'player', activeId: 'nav-guide' });

  const hiddenPlayerControl = registry.focusTarget(
    { activeRoute: 'guide', activeId: 'nav-guide' },
    'player-fullscreen',
  );
  assert.equal(hiddenPlayerControl.changed, false);
  assert.deepEqual(hiddenPlayerControl.state, { activeRoute: 'guide', activeId: 'nav-guide' });
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
