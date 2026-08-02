import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DesktopGamepadInputPolicy,
  createDesktopBackHoldRuntime,
  createDesktopGamepadSnapshot,
  createDesktopKeyboardInputListener,
  createDesktopKeyboardInputReleaseListener,
  mapDesktopKeyboardEvent,
  mapDesktopKeyEvent,
  shouldBypassDesktopInput,
  startDesktopGamepadRuntime,
  type DesktopBackHoldTimerPort,
  type DesktopGamepadLike,
} from '../../renderer/desktopInput.js';
import type { DesktopInputButton } from '../../renderer/navigation.js';

test('desktop input dispatches mapped keyboard events and prevents browser defaults', () => {
  const dispatched: DesktopInputButton[] = [];
  let prevented = false;
  const listener = createDesktopKeyboardInputListener((button) => {
    dispatched.push(button);
  });

  listener({
    key: 'ArrowRight',
    preventDefault: () => {
      prevented = true;
    },
  });

  assert.deepEqual(dispatched, ['right']);
  assert.equal(prevented, true);
});

test('Back hold keeps one short press, fires once at 500 ms, and releases cleanly', () => {
  const timers = new FakeBackHoldTimerPort();
  const events: string[] = [];
  const runtime = createDesktopBackHoldRuntime({
    dispatchShortBack: () => { events.push('short'); },
    dispatchLongBack: () => { events.push('long'); },
    timers,
  });

  runtime.press('keyboard');
  runtime.press('keyboard');
  assert.deepEqual(events, ['short']);
  timers.advanceTo(499);
  assert.deepEqual(events, ['short']);
  timers.advanceTo(500);
  assert.deepEqual(events, ['short', 'long']);
  runtime.press('keyboard');
  timers.advanceTo(1000);
  assert.deepEqual(events, ['short', 'long']);

  assert.equal(runtime.release('keyboard'), true);
  assert.equal(timers.pendingCount(), 0);
  runtime.press('keyboard');
  assert.deepEqual(events, ['short', 'long', 'short']);
  runtime.release('keyboard');
  timers.advanceTo(2000);
  assert.deepEqual(events, ['short', 'long', 'short']);
});

test('Back hold spans keyboard/gamepad device transitions and cleanup cancels pending work', () => {
  const timers = new FakeBackHoldTimerPort();
  const events: string[] = [];
  const runtime = createDesktopBackHoldRuntime({
    dispatchShortBack: () => { events.push('short'); },
    dispatchLongBack: () => { events.push('long'); },
    timers,
  });

  runtime.press('keyboard');
  runtime.press('gamepad');
  assert.deepEqual(events, ['short']);
  assert.equal(runtime.release('keyboard'), false);
  timers.advanceTo(500);
  assert.deepEqual(events, ['short', 'long']);
  assert.equal(runtime.release('gamepad'), true);

  runtime.press('keyboard');
  runtime.cancel();
  assert.equal(timers.pendingCount(), 0);
  timers.advanceTo(1000);
  assert.deepEqual(events, ['short', 'long', 'short']);
});

test('Back hold keeps simultaneous physical aliases held until each releases', () => {
  const timers = new FakeBackHoldTimerPort();
  const events: string[] = [];
  const runtime = createDesktopBackHoldRuntime({
    dispatchShortBack: () => { events.push('short'); },
    dispatchLongBack: () => { events.push('long'); },
    timers,
  });

  runtime.press('keyboard:Escape');
  runtime.press('keyboard:Backspace');
  assert.deepEqual(events, ['short']);
  assert.equal(runtime.release('keyboard:Escape'), false);
  timers.advanceTo(500);
  assert.deepEqual(events, ['short', 'long']);
  assert.equal(runtime.release('keyboard:Backspace'), true);
});

test('Back hold waits for an async short action before the 500 ms long action', async () => {
  const timers = new FakeBackHoldTimerPort();
  const events: string[] = [];
  let settleShort: (() => void) | undefined;
  const runtime = createDesktopBackHoldRuntime({
    dispatchShortBack: () => {
      events.push('short');
      return new Promise<void>((resolve) => { settleShort = resolve; });
    },
    dispatchLongBack: () => { events.push('long'); },
    timers,
  });

  runtime.press('keyboard:Escape');
  timers.advanceTo(500);
  assert.deepEqual(events, ['short']);
  settleShort?.();
  await Promise.resolve();
  assert.deepEqual(events, ['short', 'long']);
  runtime.release('keyboard:Escape');
});

test('keyboard Back hooks separate press/release from ordinary input dispatch', () => {
  const dispatched: DesktopInputButton[] = [];
  const pressed: string[] = [];
  const released: string[] = [];
  const keydown = createDesktopKeyboardInputListener(
    (button) => { dispatched.push(button); },
    { onBackPress: (sourceKey) => { pressed.push(sourceKey); } },
  );
  const keyup = createDesktopKeyboardInputReleaseListener((sourceKey) => { released.push(sourceKey); });

  keydown({ key: 'Escape', preventDefault: () => undefined });
  keydown({ key: 'Backspace', preventDefault: () => undefined });
  keydown({ key: 'BrowserBack', code: 'BrowserBack', preventDefault: () => undefined });
  keydown({ key: 'ArrowRight', preventDefault: () => undefined });
  keyup({ key: 'Escape' });
  keyup({ key: 'Backspace' });
  keyup({ key: 'BrowserBack', code: 'BrowserBack' });

  assert.deepEqual(pressed, ['keyboard:Escape', 'keyboard:Backspace', 'keyboard:BrowserBack']);
  assert.deepEqual(released, ['keyboard:Escape', 'keyboard:Backspace', 'keyboard:BrowserBack']);
  assert.deepEqual(dispatched, ['right']);
});

test('text input bypass ignores TV shortcuts while editing', () => {
  const textarea = elementLike('textarea');
  const select = elementLike('select');
  const contentEditable = elementLike('div', { contenteditable: 'plaintext-only' });
  const textboxRole = elementLike('div', { role: 'textbox' });
  const childOfCombobox = elementLike('span', {}, elementLike('div', { role: 'combobox' }));
  const button = elementLike('button');

  assert.equal(shouldBypassDesktopInput(elementLike('input')), true);
  assert.equal(shouldBypassDesktopInput(textarea), true);
  assert.equal(shouldBypassDesktopInput(select), true);
  assert.equal(shouldBypassDesktopInput(contentEditable), true);
  assert.equal(shouldBypassDesktopInput(textboxRole), true);
  assert.equal(shouldBypassDesktopInput(childOfCombobox), true);
  assert.equal(shouldBypassDesktopInput(button), false);
  assert.equal(mapDesktopKeyboardEvent({ key: 'ArrowDown', target: textarea }), null);
  assert.equal(mapDesktopKeyboardEvent({ key: 'F1', target: textarea }), null);
  assert.equal(mapDesktopKeyboardEvent({ key: 'MediaStop', target: textarea }), null);
  assert.equal(mapDesktopKeyboardEvent({ key: 'ArrowDown', target: button }), 'down');
});

test('gamepad policy normalizes safe snapshots with debounce and repeat', () => {
  const policy = new DesktopGamepadInputPolicy({ repeatDelayMs: 100, repeatIntervalMs: 50 });
  const pressedDown = snapshot({
    index: 0,
    connected: true,
    buttons: buttons({ 13: true }),
    axes: [0, 0],
  });

  assert.deepEqual(policy.poll([pressedDown], 0), ['down']);
  assert.deepEqual(policy.poll([pressedDown], 80), []);
  assert.deepEqual(policy.poll([pressedDown], 100), ['down']);
  assert.deepEqual(policy.poll([pressedDown], 150), ['down']);
  assert.deepEqual(policy.poll([snapshot({ index: 0, connected: true })], 160), []);
  assert.deepEqual(policy.poll([pressedDown], 170), ['down']);
});

test('gamepad policy maps buttons and axes without exposing raw device fields', () => {
  const rawGamepad = {
    id: 'device name must not be copied',
    index: 2,
    connected: true,
    buttons: buttons({ 0: true, 3: true }),
    axes: [-0.8, 0.75],
    mapping: 'standard',
  } satisfies DesktopGamepadLike & { id: string; mapping: string };

  const safeSnapshot = createDesktopGamepadSnapshot(rawGamepad);
  assert.deepEqual(Object.keys(safeSnapshot).sort(), ['axes', 'buttons', 'connected', 'index']);

  const policy = new DesktopGamepadInputPolicy();
  assert.deepEqual(policy.poll([safeSnapshot], 0).sort(), ['down', 'fullscreen', 'left', 'ok']);
});

test('gamepad runtime connects, polls, disconnects, and cleans up listeners', () => {
  const host = new FakeGamepadHost();
  const dispatched: DesktopInputButton[] = [];
  let currentGamepads: Array<DesktopGamepadLike | null> = [];
  const runtime = startDesktopGamepadRuntime({
    host,
    getGamepads: () => currentGamepads,
    dispatch: (button) => {
      dispatched.push(button);
    },
    nowMs: () => 0,
  });

  currentGamepads = [
    {
      index: 0,
      connected: true,
      buttons: buttons({ 0: true }),
      axes: [0, 0],
    },
  ];
  host.emitGamepad('gamepadconnected', 0);
  host.flushFrame();

  assert.deepEqual(dispatched, ['ok']);
  assert.equal(host.listenerCount('gamepadconnected'), 1);

  host.emitGamepad('gamepaddisconnected', 0);
  runtime.cleanup();
  assert.equal(host.listenerCount('gamepadconnected'), 0);
  assert.equal(host.listenerCount('gamepaddisconnected'), 0);
  assert.equal(host.hasPendingFrame(), false);
});

test('gamepad runtime reports Back release on snapshot release and disconnect', () => {
  const host = new FakeGamepadHost();
  const released: Array<{ button: DesktopInputButton; sourceKey?: string }> = [];
  let currentGamepads: Array<DesktopGamepadLike | null> = [];
  const runtime = startDesktopGamepadRuntime({
    host,
    getGamepads: () => currentGamepads,
    dispatch: () => undefined,
    onRelease: (button, sourceKey) => {
      released.push({ button, sourceKey });
    },
  });

  currentGamepads = [{ index: 0, connected: true, buttons: buttons({ 1: true }), axes: [0, 0] }];
  host.emitGamepad('gamepadconnected', 0);
  host.flushFrame();
  currentGamepads = [{ index: 0, connected: true, buttons: buttons({}), axes: [0, 0] }];
  host.flushFrame();
  assert.deepEqual(released, [{ button: 'back', sourceKey: '0:button:1' }]);

  currentGamepads = [{ index: 0, connected: true, buttons: buttons({ 1: true }), axes: [0, 0] }];
  host.flushFrame();
  host.emitGamepad('gamepaddisconnected', 0);
  assert.deepEqual(released, [
    { button: 'back', sourceKey: '0:button:1' },
    { button: 'back', sourceKey: '0:button:1' },
  ]);
  runtime.cleanup();
});

test('gamepad Back aliases preserve physical source release before semantic deduplication', () => {
  const policy = new DesktopGamepadInputPolicy();
  const pressed: string[] = [];
  const emitted: string[] = [];
  const released: string[] = [];
  const onRelease = (_button: DesktopInputButton, sourceKey: string): void => {
    released.push(sourceKey);
  };
  const onEmit = (_button: DesktopInputButton, sourceKey: string): void => {
    emitted.push(sourceKey);
  };
  const onPress = (_button: DesktopInputButton, sourceKey: string): void => {
    pressed.push(sourceKey);
  };

  policy.poll([
    snapshot({ index: 0, connected: true, buttons: buttons({ 1: true, 8: true }) }),
  ], 0, onRelease, onEmit, onPress);
  policy.poll([
    snapshot({ index: 0, connected: true, buttons: buttons({ 8: true }) }),
  ], 1, onRelease, onEmit, onPress);
  policy.poll([], 2, onRelease, onEmit, onPress);

  assert.deepEqual(pressed, ['0:button:1', '0:button:8']);
  assert.deepEqual(emitted, ['0:button:1']);
  assert.deepEqual(released, ['0:button:1', '0:button:8']);
});

test('fullscreen dispatch maps keyboard shortcut through the desktop input owner', () => {
  const dispatched: DesktopInputButton[] = [];
  const listener = createDesktopKeyboardInputListener((button) => {
    dispatched.push(button);
  });

  listener({ key: 'F' });

  assert.deepEqual(dispatched, ['fullscreen']);
});

test('Player keyboard vocabulary maps semantic function, page, media, and digit keys exactly', () => {
  assert.equal(mapDesktopKeyEvent({ key: 'Enter' }), 'ok');
  assert.equal(mapDesktopKeyEvent({ key: ' ' }), 'space');
  assert.equal(mapDesktopKeyEvent({ key: 'i' }), 'info');
  assert.equal(mapDesktopKeyEvent({ key: 'F1' }), 'nowPlaying');
  assert.equal(mapDesktopKeyEvent({ key: 'F2' }), 'guide');
  assert.equal(mapDesktopKeyEvent({ key: 'F3' }), 'settings');
  assert.equal(mapDesktopKeyEvent({ key: 'F4' }), 'info');
  assert.equal(mapDesktopKeyEvent({ key: 'PageUp' }), 'pageUp');
  assert.equal(mapDesktopKeyEvent({ key: 'PageDown' }), 'pageDown');
  assert.equal(mapDesktopKeyEvent({ key: 'MediaPlay' }), 'mediaPlay');
  assert.equal(mapDesktopKeyEvent({ key: 'MediaPause' }), 'mediaPause');
  assert.equal(mapDesktopKeyEvent({ key: 'MediaPlayPause' }), 'mediaPlayPause');
  assert.equal(mapDesktopKeyEvent({ key: 'MediaRewind' }), 'mediaRewind');
  assert.equal(mapDesktopKeyEvent({ key: 'MediaFastForward' }), 'mediaFastForward');
  assert.equal(mapDesktopKeyEvent({ key: 'MediaStop' }), 'mediaStop');
  assert.equal(mapDesktopKeyEvent({ key: '0' }), 'digit0');
  assert.equal(mapDesktopKeyEvent({ key: '9' }), 'digit9');
});

test('modified desktop shortcuts bypass navigation and preserve browser defaults', () => {
  for (const event of [
    { key: 'g', ctrlKey: true },
    { key: 'f', metaKey: true },
    { key: 'ArrowLeft', altKey: true },
  ]) {
    let prevented = false;
    const listener = createDesktopKeyboardInputListener(() => {
      assert.fail('modified shortcuts must not dispatch');
    });
    listener({ ...event, preventDefault: () => { prevented = true; } });
    assert.equal(mapDesktopKeyEvent(event), null);
    assert.equal(prevented, false);
  }
});

function elementLike(
  tagName: string,
  attributes: Record<string, string> = {},
  parentElement: EventTarget | null = null,
): EventTarget {
  return {
    tagName,
    parentElement,
    isContentEditable: attributes.contenteditable === 'true',
    getAttribute: (name: string): string | null => attributes[name] ?? null,
  } as unknown as EventTarget;
}

function snapshot(
  overrides: Partial<DesktopGamepadLike> & { index: number; connected: boolean },
) {
  return createDesktopGamepadSnapshot({
    buttons: buttons({}),
    axes: [0, 0],
    ...overrides,
  });
}

function buttons(pressed: Record<number, boolean>): DesktopGamepadLike['buttons'] {
  return Array.from({ length: 16 }, (_, index) => ({
    pressed: pressed[index] ?? false,
    value: pressed[index] === true ? 1 : 0,
  }));
}

class FakeGamepadHost {
  readonly #listeners = new Map<string, Set<EventListener>>();
  #nextFrameHandle = 1;
  #pendingFrames = new Map<number, FrameRequestCallback>();

  addEventListener(type: string, listener: EventListener): void {
    const listeners = this.#listeners.get(type) ?? new Set<EventListener>();
    listeners.add(listener);
    this.#listeners.set(type, listeners);
  }

  removeEventListener(type: string, listener: EventListener): void {
    this.#listeners.get(type)?.delete(listener);
  }

  requestAnimationFrame(callback: FrameRequestCallback): number {
    const handle = this.#nextFrameHandle;
    this.#nextFrameHandle += 1;
    this.#pendingFrames.set(handle, callback);
    return handle;
  }

  cancelAnimationFrame(handle: number): void {
    this.#pendingFrames.delete(handle);
  }

  emitGamepad(type: string, index: number): void {
    const event = { gamepad: { index } } as unknown as Event;
    for (const listener of this.#listeners.get(type) ?? []) {
      listener(event);
    }
  }

  flushFrame(): void {
    const [handle, callback] = this.#pendingFrames.entries().next().value ?? [];
    if (handle === undefined || callback === undefined) {
      return;
    }
    this.#pendingFrames.delete(handle);
    callback(0);
  }

  hasPendingFrame(): boolean {
    return this.#pendingFrames.size > 0;
  }

  listenerCount(type: string): number {
    return this.#listeners.get(type)?.size ?? 0;
  }
}

class FakeBackHoldTimerPort implements DesktopBackHoldTimerPort {
  #nextHandle = 1;
  #now = 0;
  readonly #callbacks = new Map<number, { callback: () => void; dueAt: number }>();

  setTimeout(callback: () => void, delayMs: number): number {
    const handle = this.#nextHandle;
    this.#nextHandle += 1;
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

  pendingCount(): number {
    return this.#callbacks.size;
  }
}
