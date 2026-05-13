import test from 'node:test';
import assert from 'node:assert/strict';

import type { KeyboardInputEvent } from 'electron';

import {
  registerShellAppCommandController,
  type ShellAppCommandEvent,
  type ShellAppCommandWindow,
} from '../../main/window/shellAppCommandController.js';

test('shell app-command controller maps browser-backward to renderer back input', () => {
  const fakeWindow = new FakeAppCommandWindow();
  registerShellAppCommandController(fakeWindow.asWindow());

  const event = fakeWindow.emitAppCommand('browser-backward');

  assert.equal(event.prevented, true);
  assert.deepEqual(fakeWindow.inputEvents, [
    { type: 'keyDown', keyCode: 'Escape' },
    { type: 'keyUp', keyCode: 'Escape' },
  ]);
});

test('shell app-command controller observes browser-forward but intentionally ignores it', () => {
  const fakeWindow = new FakeAppCommandWindow();
  registerShellAppCommandController(fakeWindow.asWindow());

  const event = fakeWindow.emitAppCommand('browser-forward');

  assert.equal(event.prevented, true);
  assert.deepEqual(fakeWindow.inputEvents, []);
});

test('shell app-command controller leaves media commands for later manual proof', () => {
  const fakeWindow = new FakeAppCommandWindow();
  registerShellAppCommandController(fakeWindow.asWindow());

  const playPauseEvent = fakeWindow.emitAppCommand('media-play-pause');
  const nextEvent = fakeWindow.emitAppCommand('media-nexttrack');
  const previousEvent = fakeWindow.emitAppCommand('media-previoustrack');

  assert.equal(playPauseEvent.prevented, false);
  assert.equal(nextEvent.prevented, false);
  assert.equal(previousEvent.prevented, false);
  assert.deepEqual(fakeWindow.inputEvents, []);
});

test('shell app-command controller does not forward for destroyed or unfocused windows', () => {
  const destroyedWindow = new FakeAppCommandWindow({ destroyed: true });
  registerShellAppCommandController(destroyedWindow.asWindow());
  const destroyedEvent = destroyedWindow.emitAppCommand('browser-backward');

  const unfocusedWindow = new FakeAppCommandWindow({ focused: false });
  registerShellAppCommandController(unfocusedWindow.asWindow());
  const unfocusedEvent = unfocusedWindow.emitAppCommand('browser-backward');

  const destroyedWebContentsWindow = new FakeAppCommandWindow({ webContentsDestroyed: true });
  registerShellAppCommandController(destroyedWebContentsWindow.asWindow());
  const destroyedWebContentsEvent =
    destroyedWebContentsWindow.emitAppCommand('browser-backward');

  assert.equal(destroyedEvent.prevented, true);
  assert.equal(unfocusedEvent.prevented, true);
  assert.equal(destroyedWebContentsEvent.prevented, true);
  assert.deepEqual(destroyedWindow.inputEvents, []);
  assert.deepEqual(unfocusedWindow.inputEvents, []);
  assert.deepEqual(destroyedWebContentsWindow.inputEvents, []);
});

test('shell app-command controller does not forward unknown commands', () => {
  const fakeWindow = new FakeAppCommandWindow();
  registerShellAppCommandController(fakeWindow.asWindow());

  const event = fakeWindow.emitAppCommand('unknown-command');

  assert.equal(event.prevented, false);
  assert.deepEqual(fakeWindow.inputEvents, []);
});

test('shell app-command controller unregisters its BrowserWindow listener', () => {
  const fakeWindow = new FakeAppCommandWindow();
  const registration = registerShellAppCommandController(fakeWindow.asWindow());

  registration.teardown();
  fakeWindow.emitAppCommand('browser-backward');

  assert.deepEqual(fakeWindow.inputEvents, []);
});

interface FakeAppCommandWindowOptions {
  destroyed?: boolean;
  focused?: boolean;
  webContentsDestroyed?: boolean;
}

class FakeAppCommandWindow {
  readonly inputEvents: KeyboardInputEvent[] = [];
  destroyed: boolean;
  focused: boolean;
  webContentsDestroyed: boolean;
  readonly #listeners = new Set<(event: ShellAppCommandEvent, command: string) => void>();

  constructor(options: FakeAppCommandWindowOptions = {}) {
    this.destroyed = options.destroyed ?? false;
    this.focused = options.focused ?? true;
    this.webContentsDestroyed = options.webContentsDestroyed ?? false;
  }

  asWindow(): ShellAppCommandWindow {
    return {
      isDestroyed: () => this.destroyed,
      isFocused: () => this.focused,
      webContents: {
        isDestroyed: () => this.webContentsDestroyed,
        sendInputEvent: (inputEvent) => {
          this.inputEvents.push(inputEvent);
        },
      },
      on: (_event, listener) => {
        this.#listeners.add(listener);
        return this.asWindow();
      },
      off: (_event, listener) => {
        this.#listeners.delete(listener);
        return this.asWindow();
      },
    };
  }

  emitAppCommand(command: string): FakeAppCommandEvent {
    const event = new FakeAppCommandEvent();
    for (const listener of this.#listeners) {
      listener(event, command);
    }
    return event;
  }
}

class FakeAppCommandEvent implements ShellAppCommandEvent {
  prevented = false;

  preventDefault(): void {
    this.prevented = true;
  }
}
