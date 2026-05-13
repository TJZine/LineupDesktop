import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DesktopGamepadInputPolicy,
  createDesktopGamepadSnapshot,
  createDesktopKeyboardInputListener,
  mapDesktopKeyboardEvent,
  shouldBypassDesktopInput,
  startDesktopGamepadRuntime,
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

test('fullscreen dispatch maps keyboard shortcut through the desktop input owner', () => {
  const dispatched: DesktopInputButton[] = [];
  const listener = createDesktopKeyboardInputListener((button) => {
    dispatched.push(button);
  });

  listener({ key: 'F' });

  assert.deepEqual(dispatched, ['fullscreen']);
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
