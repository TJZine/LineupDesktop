import type { KeyboardInputEvent } from 'electron';
import type { ShellMediaInput } from '../../contracts/shell.js';

export interface ShellAppCommandEvent {
  preventDefault(): void;
}

export interface ShellAppCommandWebContents {
  isDestroyed(): boolean;
  sendInputEvent(inputEvent: KeyboardInputEvent): void;
}

export interface ShellAppCommandWindow {
  baseWindow: {
    isDestroyed(): boolean;
    isFocused(): boolean;
    on(event: 'app-command', listener: (event: ShellAppCommandEvent, command: string) => void): unknown;
    off(event: 'app-command', listener: (event: ShellAppCommandEvent, command: string) => void): unknown;
  };
  webContents: ShellAppCommandWebContents;
}

export interface ShellAppCommandControllerOptions {
  sendMediaInput(input: ShellMediaInput): void;
  reportDiagnostic?: (message: string, error: unknown) => void;
}

export interface ShellAppCommandRegistration {
  teardown(): void;
}

const APP_COMMAND_KEY_CODES = {
  'browser-backward': 'Escape',
  'media-play-pause': 'MediaPlayPause',
  'media-stop': 'MediaStop',
} as const satisfies Readonly<Record<string, string>>;

const APP_COMMAND_MEDIA_INPUTS = {
  'media-play': 'mediaPlay',
  'media-pause': 'mediaPause',
  'media-rewind': 'mediaRewind',
  'media-fast-forward': 'mediaFastForward',
} as const satisfies Readonly<Record<string, ShellMediaInput>>;

export function registerShellAppCommandController(
  window: ShellAppCommandWindow,
  options: ShellAppCommandControllerOptions,
): ShellAppCommandRegistration {
  const onAppCommand = (event: ShellAppCommandEvent, command: string): void => {
    const keyCode = APP_COMMAND_KEY_CODES[command as keyof typeof APP_COMMAND_KEY_CODES];
    const mediaInput = APP_COMMAND_MEDIA_INPUTS[command as keyof typeof APP_COMMAND_MEDIA_INPUTS];
    if (keyCode === undefined && mediaInput === undefined) {
      if (command === 'browser-forward') {
        event.preventDefault();
      }
      return;
    }

    const isBrowserBackward = command === 'browser-backward';
    if (isBrowserBackward) {
      event.preventDefault();
    }
    if (!canForwardToRenderer(window)) {
      return;
    }
    if (!isBrowserBackward) {
      event.preventDefault();
    }

    try {
      if (mediaInput === undefined) {
        sendSyntheticKey(window.webContents, keyCode);
      } else {
        options.sendMediaInput(mediaInput);
      }
    } catch (error) {
      options.reportDiagnostic?.('Shell app-command forwarding failed', error);
    }
  };

  window.baseWindow.on('app-command', onAppCommand);

  return {
    teardown: () => {
      window.baseWindow.off('app-command', onAppCommand);
    },
  };
}

function canForwardToRenderer(window: ShellAppCommandWindow): boolean {
  return !window.baseWindow.isDestroyed() && window.baseWindow.isFocused() && !window.webContents.isDestroyed();
}

function sendSyntheticKey(webContents: ShellAppCommandWebContents, keyCode: string): void {
  webContents.sendInputEvent({ type: 'keyDown', keyCode });
  webContents.sendInputEvent({ type: 'keyUp', keyCode });
}
