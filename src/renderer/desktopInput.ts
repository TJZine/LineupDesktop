import type { DesktopInputButton, DesktopKeyEventLike } from './navigation.js';

export interface DesktopKeyboardEventLike extends DesktopKeyEventLike {
  target?: EventTarget | null;
  preventDefault?: () => void;
}

export interface DesktopInputElementLike {
  tagName?: string;
  nodeName?: string;
  isContentEditable?: boolean;
  parentElement?: DesktopInputElementLike | null;
  getAttribute?: (name: string) => string | null;
}

export interface DesktopGamepadButtonLike {
  pressed: boolean;
  value?: number;
}

export interface DesktopGamepadLike {
  index: number;
  connected: boolean;
  buttons: ArrayLike<DesktopGamepadButtonLike>;
  axes: ArrayLike<number>;
  timestamp?: number;
}

export interface DesktopGamepadSnapshot {
  index: number;
  connected: boolean;
  buttons: ReadonlyArray<DesktopGamepadButtonLike>;
  axes: ReadonlyArray<number>;
  timestamp?: number;
}

export interface DesktopGamepadRepeatConfig {
  axisThreshold?: number;
  repeatDelayMs?: number;
  repeatIntervalMs?: number;
}

interface GamepadSourceState {
  button: DesktopInputButton;
  pressed: boolean;
  nextRepeatAtMs: number;
}

export interface DesktopGamepadRuntimeHost {
  addEventListener: (type: string, listener: EventListener) => void;
  removeEventListener: (type: string, listener: EventListener) => void;
  requestAnimationFrame: (callback: FrameRequestCallback) => number;
  cancelAnimationFrame: (handle: number) => void;
}

export interface DesktopGamepadRuntimeOptions {
  host: DesktopGamepadRuntimeHost;
  getGamepads: () => ReadonlyArray<DesktopGamepadLike | null | undefined>;
  dispatch: (button: DesktopInputButton) => void | Promise<void>;
  nowMs?: () => number;
  repeat?: DesktopGamepadRepeatConfig;
}

export interface DesktopInputCleanup {
  cleanup: () => void;
}

const TEXT_ENTRY_ROLES = new Set(['combobox', 'searchbox', 'spinbutton', 'textbox']);
const DEFAULT_AXIS_THRESHOLD = 0.5;
const DEFAULT_REPEAT_DELAY_MS = 450;
const DEFAULT_REPEAT_INTERVAL_MS = 120;

export function mapDesktopKeyEvent(event: DesktopKeyEventLike): DesktopInputButton | null {
  switch (event.key) {
    case 'ArrowUp':
      return 'up';
    case 'ArrowDown':
      return 'down';
    case 'ArrowLeft':
      return 'left';
    case 'ArrowRight':
      return 'right';
    case 'Enter':
    case ' ':
      return 'ok';
    case 'Escape':
    case 'Backspace':
      return 'back';
    case 'g':
    case 'G':
      return 'guide';
    case ',':
    case 's':
    case 'S':
      return 'settings';
    case 'f':
    case 'F':
      return 'fullscreen';
    default:
      break;
  }

  if (event.code === 'BrowserBack') {
    return 'back';
  }
  if (event.code === 'Guide') {
    return 'guide';
  }
  return null;
}

export function mapDesktopKeyboardEvent(event: DesktopKeyboardEventLike): DesktopInputButton | null {
  if (shouldBypassDesktopInput(event.target ?? null)) {
    return null;
  }
  return mapDesktopKeyEvent(event);
}

export function createDesktopKeyboardInputListener(
  dispatch: (button: DesktopInputButton) => void | Promise<void>,
): (event: DesktopKeyboardEventLike) => void {
  return (event): void => {
    const input = mapDesktopKeyboardEvent(event);
    if (input === null) {
      return;
    }
    event.preventDefault?.();
    void dispatch(input);
  };
}

export function shouldBypassDesktopInput(target: EventTarget | null): boolean {
  let element = asInputElementLike(target);
  while (element !== null) {
    const tagName = (element.tagName ?? element.nodeName ?? '').toUpperCase();
    if (tagName === 'INPUT' || tagName === 'TEXTAREA' || tagName === 'SELECT') {
      return true;
    }
    if (element.isContentEditable === true) {
      return true;
    }

    const contentEditable = element.getAttribute?.('contenteditable')?.toLowerCase();
    if (
      contentEditable !== undefined &&
      contentEditable !== null &&
      contentEditable !== 'false'
    ) {
      return true;
    }

    const role = element.getAttribute?.('role')?.toLowerCase();
    if (role !== undefined && role !== null) {
      const roleTokens = role.split(/\s+/).filter((token) => token.length > 0);
      if (roleTokens.some((token) => TEXT_ENTRY_ROLES.has(token))) {
        return true;
      }
    }

    element = element.parentElement ?? null;
  }

  return false;
}

export function createDesktopGamepadSnapshot(
  gamepad: DesktopGamepadLike,
): DesktopGamepadSnapshot {
  const snapshot: DesktopGamepadSnapshot = {
    index: gamepad.index,
    connected: gamepad.connected,
    buttons: Array.from(gamepad.buttons, (button) => ({
      pressed: button.pressed,
      value: button.value,
    })),
    axes: Array.from(gamepad.axes),
  };
  if (gamepad.timestamp !== undefined) {
    return { ...snapshot, timestamp: gamepad.timestamp };
  }
  return snapshot;
}

export class DesktopGamepadInputPolicy {
  readonly #axisThreshold: number;
  readonly #repeatDelayMs: number;
  readonly #repeatIntervalMs: number;
  readonly #connectedIndexes = new Set<number>();
  readonly #states = new Map<string, GamepadSourceState>();

  constructor(config: DesktopGamepadRepeatConfig = {}) {
    this.#axisThreshold = config.axisThreshold ?? DEFAULT_AXIS_THRESHOLD;
    this.#repeatDelayMs = config.repeatDelayMs ?? DEFAULT_REPEAT_DELAY_MS;
    this.#repeatIntervalMs = config.repeatIntervalMs ?? DEFAULT_REPEAT_INTERVAL_MS;
  }

  connect(index: number): void {
    this.#connectedIndexes.add(index);
  }

  disconnect(index: number): void {
    this.#connectedIndexes.delete(index);
    for (const sourceKey of [...this.#states.keys()]) {
      if (sourceKey.startsWith(`${index}:`)) {
        this.#states.delete(sourceKey);
      }
    }
  }

  reset(): void {
    this.#connectedIndexes.clear();
    this.#states.clear();
  }

  hasConnectedGamepads(): boolean {
    return this.#connectedIndexes.size > 0;
  }

  poll(snapshots: ReadonlyArray<DesktopGamepadSnapshot>, nowMs: number): DesktopInputButton[] {
    const activeSourceKeys = new Set<string>();
    const emitted = new Set<DesktopInputButton>();

    for (const snapshot of snapshots) {
      if (!snapshot.connected) {
        this.disconnect(snapshot.index);
        continue;
      }

      this.connect(snapshot.index);
      for (const source of mapGamepadSnapshot(snapshot, this.#axisThreshold)) {
        activeSourceKeys.add(source.key);
        const state = this.#states.get(source.key);
        if (state === undefined || state.pressed === false) {
          this.#states.set(source.key, {
            button: source.button,
            pressed: true,
            nextRepeatAtMs: nowMs + this.#repeatDelayMs,
          });
          emitted.add(source.button);
          continue;
        }

        if (nowMs >= state.nextRepeatAtMs) {
          state.nextRepeatAtMs = nowMs + this.#repeatIntervalMs;
          emitted.add(source.button);
        }
      }
    }

    for (const sourceKey of [...this.#states.keys()]) {
      if (!activeSourceKeys.has(sourceKey)) {
        this.#states.delete(sourceKey);
      }
    }

    return [...emitted];
  }
}

export function startDesktopGamepadRuntime(
  options: DesktopGamepadRuntimeOptions,
): DesktopInputCleanup {
  const policy = new DesktopGamepadInputPolicy(options.repeat);
  const nowMs = options.nowMs ?? (() => Date.now());
  let frameHandle: number | null = null;
  let stopped = false;

  const poll = (): void => {
    frameHandle = null;
    if (stopped) {
      return;
    }

    const snapshots = options
      .getGamepads()
      .filter((gamepad): gamepad is DesktopGamepadLike => gamepad !== null && gamepad !== undefined)
      .map(createDesktopGamepadSnapshot);

    for (const button of policy.poll(snapshots, nowMs())) {
      void options.dispatch(button);
    }

    if (policy.hasConnectedGamepads()) {
      schedulePoll();
    }
  };

  const schedulePoll = (): void => {
    if (frameHandle === null && !stopped) {
      frameHandle = options.host.requestAnimationFrame(poll);
    }
  };

  const handleConnected = (event: Event): void => {
    const gamepadIndex = readGamepadIndex(event);
    if (gamepadIndex !== null) {
      policy.connect(gamepadIndex);
      schedulePoll();
    }
  };

  const handleDisconnected = (event: Event): void => {
    const gamepadIndex = readGamepadIndex(event);
    if (gamepadIndex !== null) {
      policy.disconnect(gamepadIndex);
    }
  };

  options.host.addEventListener('gamepadconnected', handleConnected);
  options.host.addEventListener('gamepaddisconnected', handleDisconnected);

  for (const gamepad of options.getGamepads()) {
    if (gamepad?.connected === true) {
      policy.connect(gamepad.index);
    }
  }
  if (policy.hasConnectedGamepads()) {
    schedulePoll();
  }

  return {
    cleanup: (): void => {
      stopped = true;
      options.host.removeEventListener('gamepadconnected', handleConnected);
      options.host.removeEventListener('gamepaddisconnected', handleDisconnected);
      if (frameHandle !== null) {
        options.host.cancelAnimationFrame(frameHandle);
        frameHandle = null;
      }
      policy.reset();
    },
  };
}

function mapGamepadSnapshot(
  snapshot: DesktopGamepadSnapshot,
  axisThreshold: number,
): Array<{ key: string; button: DesktopInputButton }> {
  const mapped: Array<{ key: string; button: DesktopInputButton }> = [];
  const buttonMap = new Map<number, DesktopInputButton>([
    [0, 'ok'],
    [1, 'back'],
    [2, 'settings'],
    [3, 'fullscreen'],
    [8, 'back'],
    [9, 'guide'],
    [12, 'up'],
    [13, 'down'],
    [14, 'left'],
    [15, 'right'],
  ]);

  for (const [index, button] of snapshot.buttons.entries()) {
    const mappedButton = buttonMap.get(index);
    if (mappedButton !== undefined && (button.pressed || (button.value ?? 0) >= 0.5)) {
      mapped.push({ key: `${snapshot.index}:button:${index}`, button: mappedButton });
    }
  }

  const horizontalAxis = snapshot.axes[0] ?? 0;
  const verticalAxis = snapshot.axes[1] ?? 0;
  if (horizontalAxis <= -axisThreshold) {
    mapped.push({ key: `${snapshot.index}:axis:left`, button: 'left' });
  } else if (horizontalAxis >= axisThreshold) {
    mapped.push({ key: `${snapshot.index}:axis:right`, button: 'right' });
  }
  if (verticalAxis <= -axisThreshold) {
    mapped.push({ key: `${snapshot.index}:axis:up`, button: 'up' });
  } else if (verticalAxis >= axisThreshold) {
    mapped.push({ key: `${snapshot.index}:axis:down`, button: 'down' });
  }

  return mapped;
}

function asInputElementLike(target: EventTarget | null): DesktopInputElementLike | null {
  if (target === null || typeof target !== 'object') {
    return null;
  }
  return target as DesktopInputElementLike;
}

function readGamepadIndex(event: Event): number | null {
  const gamepad = (event as { gamepad?: { index?: unknown } }).gamepad;
  return typeof gamepad?.index === 'number' ? gamepad.index : null;
}
