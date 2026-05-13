import type { KeyboardInputEvent } from 'electron';

export interface ShellAppCommandEvent {
  preventDefault(): void;
}

export interface ShellAppCommandWebContents {
  isDestroyed(): boolean;
  sendInputEvent(inputEvent: KeyboardInputEvent): void;
}

export interface ShellAppCommandWindow {
  isDestroyed(): boolean;
  isFocused(): boolean;
  webContents: ShellAppCommandWebContents;
  on(event: 'app-command', listener: (event: ShellAppCommandEvent, command: string) => void): this;
  off(event: 'app-command', listener: (event: ShellAppCommandEvent, command: string) => void): this;
}

export interface ShellAppCommandControllerOptions {
  reportDiagnostic?: (message: string, error: unknown) => void;
}

export interface ShellAppCommandRegistration {
  teardown(): void;
}

const APP_COMMAND_KEY_CODES = {
  'browser-backward': 'Escape',
} as const satisfies Readonly<Record<string, string>>;

export function registerShellAppCommandController(
  window: ShellAppCommandWindow,
  options: ShellAppCommandControllerOptions = {},
): ShellAppCommandRegistration {
  const onAppCommand = (event: ShellAppCommandEvent, command: string): void => {
    const keyCode = APP_COMMAND_KEY_CODES[command as keyof typeof APP_COMMAND_KEY_CODES];
    if (keyCode === undefined) {
      if (command === 'browser-forward') {
        event.preventDefault();
      }
      return;
    }

    event.preventDefault();
    if (!canForwardToRenderer(window)) {
      return;
    }

    try {
      sendSyntheticKey(window.webContents, keyCode);
    } catch (error) {
      options.reportDiagnostic?.('Shell app-command forwarding failed', error);
    }
  };

  window.on('app-command', onAppCommand);

  return {
    teardown: () => {
      window.off('app-command', onAppCommand);
    },
  };
}

function canForwardToRenderer(window: ShellAppCommandWindow): boolean {
  return !window.isDestroyed() && window.isFocused() && !window.webContents.isDestroyed();
}

function sendSyntheticKey(webContents: ShellAppCommandWebContents, keyCode: string): void {
  webContents.sendInputEvent({ type: 'keyDown', keyCode });
  webContents.sendInputEvent({ type: 'keyUp', keyCode });
}
