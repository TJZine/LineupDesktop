import test from 'node:test';
import assert from 'node:assert/strict';

import type { KeyboardInputEvent } from 'electron';
import type { ShellMediaInput } from '../../contracts/shell.js';

import {
  registerShellAppCommandController,
  type ShellAppCommandEvent,
  type ShellAppCommandWindow,
} from '../../main/window/shellAppCommandController.js';

test('shell app-command controller maps browser-backward to renderer back input', () => {
  const fakeWindow = new FakeAppCommandWindow();
  register(fakeWindow);

  const event = fakeWindow.emitAppCommand('browser-backward');

  assert.equal(event.prevented, true);
  assert.deepEqual(fakeWindow.inputEvents, [
    { type: 'keyDown', keyCode: 'Escape' },
    { type: 'keyUp', keyCode: 'Escape' },
  ]);
});

test('shell app-command controller observes browser-forward but intentionally ignores it', () => {
  const fakeWindow = new FakeAppCommandWindow();
  register(fakeWindow);

  const event = fakeWindow.emitAppCommand('browser-forward');

  assert.equal(event.prevented, true);
  assert.deepEqual(fakeWindow.inputEvents, []);
});

test('shell app-command controller maps only valid accelerator media commands to key pairs', () => {
  const fakeWindow = new FakeAppCommandWindow();
  register(fakeWindow);

  const commands = [
    ['media-play-pause', 'MediaPlayPause'],
    ['media-stop', 'MediaStop'],
  ] as const;

  for (const [command, keyCode] of commands) {
    const event = fakeWindow.emitAppCommand(command);
    assert.equal(event.prevented, true, command);
    assert.deepEqual(
      fakeWindow.inputEvents.splice(0),
      [
        { type: 'keyDown', keyCode },
        { type: 'keyUp', keyCode },
      ],
      command,
    );
  }
  assert.deepEqual(fakeWindow.mediaInputs, []);
});

test('shell app-command controller forwards distinct media actions semantically', () => {
  const fakeWindow = new FakeAppCommandWindow();
  register(fakeWindow);

  for (const command of [
    'media-play',
    'media-pause',
    'media-rewind',
    'media-fast-forward',
  ]) {
    const event = fakeWindow.emitAppCommand(command);
    assert.equal(event.prevented, true, command);
  }

  assert.deepEqual(fakeWindow.inputEvents, []);
  assert.deepEqual(fakeWindow.mediaInputs, [
    'mediaPlay',
    'mediaPause',
    'mediaRewind',
    'mediaFastForward',
  ]);
});

test('shell app-command controller does not forward for destroyed or unfocused windows', () => {
  const destroyedWindow = new FakeAppCommandWindow({ destroyed: true });
  register(destroyedWindow);
  const destroyedEvent = destroyedWindow.emitAppCommand('browser-backward');

  const unfocusedWindow = new FakeAppCommandWindow({ focused: false });
  register(unfocusedWindow);
  const unfocusedEvent = unfocusedWindow.emitAppCommand('browser-backward');

  const destroyedWebContentsWindow = new FakeAppCommandWindow({ webContentsDestroyed: true });
  register(destroyedWebContentsWindow);
  const destroyedWebContentsEvent =
    destroyedWebContentsWindow.emitAppCommand('browser-backward');

  assert.equal(destroyedEvent.prevented, true);
  assert.equal(unfocusedEvent.prevented, true);
  assert.equal(destroyedWebContentsEvent.prevented, true);
  assert.deepEqual(destroyedWindow.inputEvents, []);
  assert.deepEqual(unfocusedWindow.inputEvents, []);
  assert.deepEqual(destroyedWebContentsWindow.inputEvents, []);
});

test('shell app-command controller leaves unsafe media commands unhandled', () => {
  const destroyedWindow = new FakeAppCommandWindow({ destroyed: true });
  register(destroyedWindow);
  const destroyedEvent = destroyedWindow.emitAppCommand('media-play');

  const unfocusedWindow = new FakeAppCommandWindow({ focused: false });
  register(unfocusedWindow);
  const unfocusedEvent = unfocusedWindow.emitAppCommand('media-pause');

  const destroyedWebContentsWindow = new FakeAppCommandWindow({ webContentsDestroyed: true });
  register(destroyedWebContentsWindow);
  const destroyedWebContentsEvent = destroyedWebContentsWindow.emitAppCommand('media-stop');

  assert.equal(destroyedEvent.prevented, false);
  assert.equal(unfocusedEvent.prevented, false);
  assert.equal(destroyedWebContentsEvent.prevented, false);
  assert.deepEqual(destroyedWindow.inputEvents, []);
  assert.deepEqual(unfocusedWindow.inputEvents, []);
  assert.deepEqual(destroyedWebContentsWindow.inputEvents, []);
  assert.deepEqual(destroyedWindow.mediaInputs, []);
  assert.deepEqual(unfocusedWindow.mediaInputs, []);
  assert.deepEqual(destroyedWebContentsWindow.mediaInputs, []);
});

test('shell app-command controller leaves next/previous-track and unknown commands unhandled', () => {
  const fakeWindow = new FakeAppCommandWindow();
  register(fakeWindow);

  const nextEvent = fakeWindow.emitAppCommand('media-nexttrack');
  const previousEvent = fakeWindow.emitAppCommand('media-previoustrack');
  const unknownEvent = fakeWindow.emitAppCommand('unknown-command');

  assert.equal(nextEvent.prevented, false);
  assert.equal(previousEvent.prevented, false);
  assert.equal(unknownEvent.prevented, false);
  assert.deepEqual(fakeWindow.inputEvents, []);
});

test('shell app-command controller reports renderer forwarding errors without throwing', () => {
  const fakeWindow = new FakeAppCommandWindow({ sendInputError: new Error('send failed') });
  const diagnostics: Array<{ message: string; error: unknown }> = [];
  registerShellAppCommandController(fakeWindow.asWindow(), {
    sendMediaInput: (input) => fakeWindow.mediaInputs.push(input),
    reportDiagnostic: (message, error) => diagnostics.push({ message, error }),
  });

  const event = fakeWindow.emitAppCommand('media-play-pause');

  assert.equal(event.prevented, true);
  assert.equal(diagnostics.length, 1);
  const diagnostic = diagnostics[0];
  assert.ok(diagnostic);
  assert.equal(diagnostic.message, 'Shell app-command forwarding failed');
  assert.ok(diagnostic.error instanceof Error);
  assert.equal(diagnostic.error.message, 'send failed');
});

test('shell app-command controller unregisters its BrowserWindow listener', () => {
  const fakeWindow = new FakeAppCommandWindow();
  const registration = register(fakeWindow);

  registration.teardown();
  fakeWindow.emitAppCommand('browser-backward');
  fakeWindow.emitAppCommand('media-play');

  assert.equal(fakeWindow.listenerOnCalls, 1);
  assert.equal(fakeWindow.listenerOffCalls, 1);
  assert.deepEqual(fakeWindow.inputEvents, []);
});

interface FakeAppCommandWindowOptions {
  destroyed?: boolean;
  focused?: boolean;
  sendInputError?: Error;
  webContentsDestroyed?: boolean;
}

class FakeAppCommandWindow {
  readonly inputEvents: KeyboardInputEvent[] = [];
  readonly mediaInputs: ShellMediaInput[] = [];
  listenerOnCalls = 0;
  listenerOffCalls = 0;
  destroyed: boolean;
  focused: boolean;
  sendInputError: Error | undefined;
  webContentsDestroyed: boolean;
  readonly #listeners = new Set<(event: ShellAppCommandEvent, command: string) => void>();

  constructor(options: FakeAppCommandWindowOptions = {}) {
    this.destroyed = options.destroyed ?? false;
    this.focused = options.focused ?? true;
    this.sendInputError = options.sendInputError;
    this.webContentsDestroyed = options.webContentsDestroyed ?? false;
  }

  asWindow(): ShellAppCommandWindow {
    return {
      isDestroyed: () => this.destroyed,
      isFocused: () => this.focused,
      webContents: {
        isDestroyed: () => this.webContentsDestroyed,
        sendInputEvent: (inputEvent) => {
          if (this.sendInputError !== undefined) {
            throw this.sendInputError;
          }
          this.inputEvents.push(inputEvent);
        },
      },
      on: (_event, listener) => {
        this.listenerOnCalls += 1;
        this.#listeners.add(listener);
        return this.asWindow();
      },
      off: (_event, listener) => {
        this.listenerOffCalls += 1;
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

function register(fakeWindow: FakeAppCommandWindow) {
  return registerShellAppCommandController(fakeWindow.asWindow(), {
    sendMediaInput: (input) => fakeWindow.mediaInputs.push(input),
  });
}

class FakeAppCommandEvent implements ShellAppCommandEvent {
  prevented = false;

  preventDefault(): void {
    this.prevented = true;
  }
}
