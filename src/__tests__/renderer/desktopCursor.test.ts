import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createDesktopCursorRuntime,
  type DesktopCursorRoot,
} from '../../renderer/desktopCursor.js';

test('desktop cursor hides after renderer inactivity timer', () => {
  const host = new FakeCursorHost();
  const timers = new FakeTimerPort();
  const root = createRoot();

  const runtime = createDesktopCursorRuntime({
    host,
    root,
    timers,
    inactivityDelayMs: 100,
  });

  assert.equal(runtime.getState(), 'visible');
  assert.equal(root.dataset.desktopCursor, 'visible');
  assert.equal(root.classList.has('desktop-cursor-hidden'), false);

  timers.flushNext();

  assert.equal(runtime.getState(), 'hidden');
  assert.equal(root.dataset.desktopCursor, 'hidden');
  assert.equal(root.classList.has('desktop-cursor-hidden'), true);
});

test('pointer activity shows the cursor and restarts inactivity hiding', () => {
  const host = new FakeCursorHost();
  const timers = new FakeTimerPort();
  const root = createRoot();
  const runtime = createDesktopCursorRuntime({ host, root, timers });

  timers.flushNext();
  assert.equal(runtime.getState(), 'hidden');

  host.emit('pointermove');

  assert.equal(runtime.getState(), 'visible');
  assert.equal(root.dataset.desktopCursor, 'visible');
  assert.equal(timers.pendingCount(), 1);

  timers.flushNext();

  assert.equal(runtime.getState(), 'hidden');
  assert.equal(root.dataset.desktopCursor, 'hidden');
});

test('desktop input hides the cursor and clears pending inactivity work', () => {
  const host = new FakeCursorHost();
  const timers = new FakeTimerPort();
  const root = createRoot();
  const runtime = createDesktopCursorRuntime({ host, root, timers });

  runtime.hideForDesktopInput();

  assert.equal(runtime.getState(), 'hidden');
  assert.equal(root.dataset.desktopCursor, 'hidden');
  assert.equal(root.classList.has('desktop-cursor-hidden'), true);
  assert.equal(timers.pendingCount(), 0);
});

test('cleanup removes cursor listeners, clears timers, and restores visible state', () => {
  const host = new FakeCursorHost();
  const timers = new FakeTimerPort();
  const root = createRoot();
  const runtime = createDesktopCursorRuntime({ host, root, timers });

  assert.equal(host.listenerCount('pointermove'), 1);
  assert.equal(host.listenerCount('mousemove'), 1);

  runtime.hideForDesktopInput();
  runtime.cleanup();
  host.emit('pointermove');

  assert.equal(host.listenerCount('pointermove'), 0);
  assert.equal(host.listenerCount('mousemove'), 0);
  assert.equal(timers.pendingCount(), 0);
  assert.equal(runtime.getState(), 'visible');
  assert.equal(root.dataset.desktopCursor, 'visible');
  assert.equal(root.classList.has('desktop-cursor-hidden'), false);
});

test('cursor presentation state is route and overlay safe', () => {
  const host = new FakeCursorHost();
  const timers = new FakeTimerPort();
  const root = createRoot();
  root.dataset.activeRoute = 'player';
  root.dataset.overlayStack = 'playerOsd,miniGuide';
  const runtime = createDesktopCursorRuntime({ host, root, timers });

  runtime.hideForDesktopInput();
  root.dataset.activeRoute = 'guide';
  root.dataset.overlayStack = 'playerOsd';

  assert.equal(root.dataset.desktopCursor, 'hidden');
  assert.equal(root.dataset.activeRoute, 'guide');
  assert.equal(root.dataset.overlayStack, 'playerOsd');

  host.emit('mousemove');

  assert.equal(root.dataset.desktopCursor, 'visible');
  assert.equal(root.dataset.activeRoute, 'guide');
  assert.equal(root.dataset.overlayStack, 'playerOsd');
});

function createRoot(): DesktopCursorRoot & {
  classList: DesktopCursorRoot['classList'] & { has: (className: string) => boolean };
} {
  const classes = new Set<string>();
  return {
    dataset: {},
    classList: {
      toggle: (className: string, force?: boolean): boolean => {
        const shouldAdd = force ?? !classes.has(className);
        if (shouldAdd) {
          classes.add(className);
        } else {
          classes.delete(className);
        }
        return shouldAdd;
      },
      has: (className: string): boolean => classes.has(className),
    },
  };
}

class FakeCursorHost {
  readonly #listeners = new Map<string, Set<EventListener>>();

  addEventListener(type: string, listener: EventListener): void {
    const listeners = this.#listeners.get(type) ?? new Set<EventListener>();
    listeners.add(listener);
    this.#listeners.set(type, listeners);
  }

  removeEventListener(type: string, listener: EventListener): void {
    this.#listeners.get(type)?.delete(listener);
  }

  emit(type: string): void {
    for (const listener of this.#listeners.get(type) ?? []) {
      listener({ type } as Event);
    }
  }

  listenerCount(type: string): number {
    return this.#listeners.get(type)?.size ?? 0;
  }
}

class FakeTimerPort {
  #nextHandle = 1;
  readonly #callbacks = new Map<number, () => void>();

  setTimeout(callback: () => void): number {
    const handle = this.#nextHandle;
    this.#nextHandle += 1;
    this.#callbacks.set(handle, callback);
    return handle;
  }

  clearTimeout(handle: number): void {
    this.#callbacks.delete(handle);
  }

  flushNext(): void {
    const [handle, callback] = this.#callbacks.entries().next().value ?? [];
    if (handle === undefined || callback === undefined) {
      return;
    }
    this.#callbacks.delete(handle);
    callback();
  }

  pendingCount(): number {
    return this.#callbacks.size;
  }
}
