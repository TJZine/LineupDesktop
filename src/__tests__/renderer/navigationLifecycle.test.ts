import assert from 'node:assert/strict';
import test from 'node:test';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import type { DesktopGamepadLike } from '../../renderer/desktopInput.js';
import { FocusRegistry, type FocusState } from '../../renderer/navigation.js';
import {
  activateInfoRecovery,
  attachNavigationInputRuntime,
  createNavigationLifecycle,
  type NavigationLifecycle,
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
  handlePlayerRouteLeave?: NavigationLifecycleOptions['handlePlayerRouteLeave'],
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
  let playerRouteLeaveCount = 0;
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
    handlePlayerRouteLeave: () => {
      playerRouteLeaveCount += 1;
      handlePlayerRouteLeave?.();
    },
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
    setShell: (nextState: RendererShellState) => { shellState = nextState; },
    getShell: () => shellState,
    getPlayerPresentationFocusCount: () => playerPresentationFocusCount,
    getPlayerRouteLeaveCount: () => playerRouteLeaveCount,
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

test('Back hold closes player overlays and returns with presentation focus', async () => {
  const harness = createHarness(() => false, undefined, true, undefined, () => undefined);
  harness.setRoute('guide');
  harness.setFocus({ activeRoute: 'guide', activeId: 'guide-program-one--next' });

  await harness.lifecycle.handleBackPress();
  assert.equal(harness.getRoute(), 'player');
  await harness.lifecycle.handleBackHold();

  assert.equal(harness.getPlayerRouteLeaveCount(), 1);
  assert.deepEqual(harness.getFocus(), { activeRoute: 'player', activeId: null });
  assert.equal(harness.getPlayerPresentationFocusCount(), 1);
});

test('Back hold consumes protected bootstrap, error, and profile owners', async () => {
  const protectedStates = [
    { bootstrap: 'loading' as const },
    { bootstrap: 'error' as const, blockingErrorMessage: 'Lineup could not start.' },
    { inlineError: { desiredFullscreen: true, message: 'Fullscreen failed.' } },
  ];

  for (const patch of protectedStates) {
    const protectedHarness = createHarness(() => false);
    protectedHarness.setRoute('guide');
    protectedHarness.setShell({ ...createRendererShellState(), bootstrap: 'ready', ...patch });
    await protectedHarness.lifecycle.handleBackPress();
    await protectedHarness.lifecycle.handleBackHold();
    assert.equal(protectedHarness.getRoute(), 'guide');
    assert.equal(protectedHarness.getPlayerRouteLeaveCount(), 0);
  }

  const profileHarness = createHarness(() => false);
  profileHarness.setRoute('guide');
  profileHarness.setProfileModalActive(true);
  await profileHarness.lifecycle.handleBackPress();
  await profileHarness.lifecycle.handleBackHold();
  assert.equal(profileHarness.getRoute(), 'guide');
  assert.equal(profileHarness.getPlayerRouteLeaveCount(), 0);
});

test('Back hold unwinds the Player exit modal without restoring stale focus', async () => {
  const harness = createHarness(() => false, () => false, true, undefined, () => undefined);
  harness.setRoute('player');
  harness.setFocus({ activeRoute: 'player', activeId: 'player-settings' });

  await harness.lifecycle.handleBackPress();
  assert.equal(harness.getShell().exitConfirmOpen, true);
  await harness.lifecycle.handleBackHold();

  assert.equal(harness.getShell().exitConfirmOpen, false);
  assert.deepEqual(harness.getFocus(), { activeRoute: 'player', activeId: null });
  assert.equal(harness.getPlayerPresentationFocusCount(), 1);
});

test('attached Back input cancels on keyup/blur and removes listeners on unload', async () => {
  const host = new FakeNavigationInputHost();
  const timers = new FakeNavigationTimerPort();
  const root = createNavigationInputRoot();
  const calls: string[] = [];
  const originalWindow = Reflect.get(globalThis, 'window');
  Object.defineProperty(globalThis, 'window', { value: host, configurable: true });
  try {
  const lifecycle: NavigationLifecycle = {
    handleInput: async () => undefined,
    handleBackPress: async () => { calls.push('short'); },
    handleBackHold: async () => { calls.push('long'); },
    cancelBackHold: () => { calls.push('cancel'); },
    cancelExit: () => undefined,
    confirmExit: () => undefined,
    closeApplication: () => undefined,
    routeChanged: () => undefined,
    cleanup: () => { calls.push('cleanup'); },
  };

  attachNavigationInputRuntime(lifecycle, {
    host: host as unknown as Window,
    root: root as unknown as HTMLElement,
    timers,
    onBeforeUnload: () => { calls.push('unload'); },
  });

  host.emit('keydown', { key: 'Escape', preventDefault: () => undefined });
  assert.deepEqual(calls, ['short']);
  timers.advanceTo(499);
  assert.deepEqual(calls, ['short']);
  host.emit('keyup', { key: 'Escape' });
  timers.advanceTo(500);
  assert.deepEqual(calls, ['short', 'cancel']);

  host.emit('keydown', { key: 'Escape', preventDefault: () => undefined });
  timers.advanceTo(1000);
  await Promise.resolve();
  assert.deepEqual(calls, ['short', 'cancel', 'short', 'long']);
  host.emit('blur', {});
  assert.deepEqual(calls, ['short', 'cancel', 'short', 'long', 'cancel']);

  host.emit('keydown', { key: 'Escape', preventDefault: () => undefined });
  host.emit('beforeunload', {});
  timers.advanceTo(2000);
  assert.deepEqual(calls, [
    'short', 'cancel', 'short', 'long', 'cancel', 'short', 'cancel', 'cleanup', 'unload',
  ]);
  assert.equal(host.listenerCount('keydown'), 0);
  assert.equal(host.listenerCount('keyup'), 0);
  assert.equal(host.listenerCount('blur'), 0);
  assert.equal(host.listenerCount('focus'), 0);
  assert.equal(host.listenerCount('beforeunload'), 0);
  } finally {
    if (originalWindow === undefined) Reflect.deleteProperty(globalThis, 'window');
    else Object.defineProperty(globalThis, 'window', { value: originalWindow, configurable: true });
  }
});

test('held gamepad Back is quiesced on blur and resumes after a fresh release/press', () => {
  const host = new FakeNavigationInputHost();
  const timers = new FakeNavigationTimerPort();
  const root = createNavigationInputRoot();
  const calls: string[] = [];
  const originalWindow = Reflect.get(globalThis, 'window');
  const gamepad = createBackGamepad(true);
  host.setGamepads([gamepad]);
  Object.defineProperty(globalThis, 'window', { value: host, configurable: true });
  try {
  const lifecycle: NavigationLifecycle = {
    handleInput: async () => undefined,
    handleBackPress: async () => { calls.push('short'); },
    handleBackHold: async () => { calls.push('long'); },
    cancelBackHold: () => { calls.push('cancel'); },
    cancelExit: () => undefined,
    confirmExit: () => undefined,
    closeApplication: () => undefined,
    routeChanged: () => undefined,
    cleanup: () => { calls.push('cleanup'); },
  };

  attachNavigationInputRuntime(lifecycle, {
    host: host as unknown as Window,
    root: root as unknown as HTMLElement,
    timers,
    onBeforeUnload: () => { calls.push('unload'); },
  });
  host.emit('gamepadconnected', { gamepad: { index: 0 } });
  host.flushFrame();
  assert.deepEqual(calls, ['short']);

  host.emit('blur');
  timers.advanceTo(500);
  host.flushFrame();
  assert.deepEqual(calls, ['short', 'cancel']);

  host.emit('focus');
  host.flushFrame();
  timers.advanceTo(1000);
  assert.deepEqual(calls, ['short', 'cancel']);

  const gamepadButtons = gamepad.buttons as Array<{ pressed: boolean; value: number }>;
  gamepadButtons[1] = { pressed: false, value: 0 };
  host.flushFrame();
  gamepadButtons[1] = { pressed: true, value: 1 };
  host.flushFrame();
  assert.deepEqual(calls, ['short', 'cancel', 'short']);

  host.emit('beforeunload');
  } finally {
    if (originalWindow === undefined) Reflect.deleteProperty(globalThis, 'window');
    else Object.defineProperty(globalThis, 'window', { value: originalWindow, configurable: true });
  }
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

function createNavigationInputRoot(): { dataset: Record<string, string>; classList: { toggle: (name: string, force?: boolean) => boolean } } {
  const classes = new Set<string>();
  return {
    dataset: {},
    classList: {
      toggle: (name, force) => {
        const next = force ?? !classes.has(name);
        if (next) classes.add(name);
        else classes.delete(name);
        return next;
      },
    },
  };
}

class FakeNavigationInputHost {
  #gamepads: Array<DesktopGamepadLike> = [];
  readonly navigator = { getGamepads: (): ReadonlyArray<DesktopGamepadLike> => this.#gamepads };
  readonly #listeners = new Map<string, Set<EventListener>>();
  #nextTimer = 1;
  readonly #timers = new Set<number>();
  #nextFrame = 1;
  readonly #frames = new Map<number, FrameRequestCallback>();

  addEventListener(type: string, listener: EventListener): void {
    const listeners = this.#listeners.get(type) ?? new Set<EventListener>();
    listeners.add(listener);
    this.#listeners.set(type, listeners);
  }

  removeEventListener(type: string, listener: EventListener): void {
    this.#listeners.get(type)?.delete(listener);
  }

  setTimeout(_callback: TimerHandler, _delayMs?: number): number {
    const handle = this.#nextTimer++;
    this.#timers.add(handle);
    return handle;
  }

  clearTimeout(handle: number): void {
    this.#timers.delete(handle);
  }

  requestAnimationFrame(callback: FrameRequestCallback): number {
    const handle = this.#nextFrame++;
    this.#frames.set(handle, callback);
    return handle;
  }

  cancelAnimationFrame(handle: number): void {
    this.#frames.delete(handle);
  }

  setGamepads(gamepads: Array<DesktopGamepadLike>): void {
    this.#gamepads = gamepads;
  }

  flushFrame(): void {
    const [handle, callback] = this.#frames.entries().next().value ?? [];
    if (handle === undefined || callback === undefined) return;
    this.#frames.delete(handle);
    callback(0);
  }

  emit(type: string, event: unknown = {}): void {
    for (const listener of this.#listeners.get(type) ?? []) {
      listener(event as Event);
    }
  }

  listenerCount(type: string): number {
    return this.#listeners.get(type)?.size ?? 0;
  }
}

function createBackGamepad(pressed: boolean): DesktopGamepadLike {
  return {
    index: 0,
    connected: true,
    buttons: Array.from({ length: 16 }, (_, index) => ({
      pressed: index === 1 ? pressed : false,
      value: index === 1 && pressed ? 1 : 0,
    })),
    axes: [0, 0],
  };
}

class FakeNavigationTimerPort {
  #now = 0;
  #nextHandle = 1;
  readonly #callbacks = new Map<number, { callback: () => void; dueAt: number }>();

  setTimeout(callback: () => void, delayMs: number): number {
    const handle = this.#nextHandle++;
    this.#callbacks.set(handle, { callback, dueAt: this.#now + delayMs });
    return handle;
  }

  clearTimeout(handle: number): void {
    this.#callbacks.delete(handle);
  }

  advanceTo(now: number): void {
    this.#now = now;
    for (const [handle, timer] of [...this.#callbacks.entries()]) {
      if (timer.dueAt <= now) {
        this.#callbacks.delete(handle);
        timer.callback();
      }
    }
  }
}
