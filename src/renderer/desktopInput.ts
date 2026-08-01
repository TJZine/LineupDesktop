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

export interface DesktopBackHoldTimerPort {
  setTimeout: (callback: () => void, delayMs: number) => number;
  clearTimeout: (handle: number) => void;
}

export interface DesktopBackHoldRuntimeOptions {
  dispatchShortBack: () => void | Promise<void>;
  dispatchLongBack: () => void | Promise<void>;
  timers: DesktopBackHoldTimerPort;
  holdDelayMs?: number;
}

export interface DesktopBackHoldRuntime {
  press(source: string): void;
  release(source: string): boolean;
  cancel(): void;
}

export interface DesktopGamepadRuntimeOptions {
  host: DesktopGamepadRuntimeHost;
  getGamepads: () => ReadonlyArray<DesktopGamepadLike | null | undefined>;
  dispatch: (button: DesktopInputButton, sourceKey?: string) => void | Promise<void>;
  onPress?: (button: DesktopInputButton, sourceKey?: string) => void;
  onRelease?: (button: DesktopInputButton, sourceKey?: string) => void;
  nowMs?: () => number;
  repeat?: DesktopGamepadRepeatConfig;
}

export interface DesktopInputCleanup {
  cleanup: () => void;
  pause?: () => void;
  resume?: () => void;
}

const TEXT_ENTRY_ROLES = new Set(['combobox', 'searchbox', 'spinbutton', 'textbox']);
const DEFAULT_AXIS_THRESHOLD = 0.5;
const DEFAULT_REPEAT_DELAY_MS = 450;
const DEFAULT_REPEAT_INTERVAL_MS = 120;

export function mapDesktopKeyEvent(event: DesktopKeyEventLike): DesktopInputButton | null {
  if (event.ctrlKey === true || event.metaKey === true || event.altKey === true) {
    return null;
  }
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
      return 'ok';
    case ' ':
      return 'space';
    case 'F1':
      return 'nowPlaying';
    case 'F2':
      return 'guide';
    case 'F3':
      return 'settings';
    case 'F4':
      return 'info';
    case 'Escape':
    case 'Backspace':
      return 'back';
    case 'g':
    case 'G':
      return 'guide';
    case 'i':
    case 'I':
      return 'info';
    case 'PageUp':
      return 'pageUp';
    case 'PageDown':
      return 'pageDown';
    case 'MediaPlay':
      return 'mediaPlay';
    case 'MediaPause':
      return 'mediaPause';
    case 'MediaPlayPause':
      return 'mediaPlayPause';
    case 'MediaRewind':
      return 'mediaRewind';
    case 'MediaFastForward':
      return 'mediaFastForward';
    case 'MediaStop':
      return 'mediaStop';
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

  if (/^[0-9]$/u.test(event.key)) {
    return `digit${event.key}` as DesktopInputButton;
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

export interface DesktopKeyboardInputListenerOptions {
  onBackPress?: (sourceKey: string) => void;
}

export function createDesktopKeyboardInputListener(
  dispatch: (button: DesktopInputButton) => void | Promise<void>,
  options: DesktopKeyboardInputListenerOptions = {},
): (event: DesktopKeyboardEventLike) => void {
  return (event): void => {
    const input = mapDesktopKeyboardEvent(event);
    if (input === null) {
      return;
    }
    event.preventDefault?.();
    if (input === 'back' && options.onBackPress !== undefined) {
      options.onBackPress(getDesktopBackSourceKey(event));
    } else {
      void dispatch(input);
    }
  };
}

export function createDesktopKeyboardInputReleaseListener(
  onBackRelease: (sourceKey: string) => void,
): (event: DesktopKeyboardEventLike) => void {
  return (event): void => {
    if (event.key === 'Escape' || event.key === 'Backspace' || event.code === 'BrowserBack') {
      onBackRelease(getDesktopBackSourceKey(event));
    }
  };
}

function getDesktopBackSourceKey(event: DesktopKeyboardEventLike): string {
  if (event.code === 'BrowserBack') return 'keyboard:BrowserBack';
  if (event.key === 'Escape') return 'keyboard:Escape';
  if (event.key === 'Backspace') return 'keyboard:Backspace';
  return `keyboard:${event.code ?? event.key}`;
}

export function createDesktopBackHoldRuntime(
  options: DesktopBackHoldRuntimeOptions,
): DesktopBackHoldRuntime {
  const holdDelayMs = options.holdDelayMs ?? 500;
  const pressedSources = new Set<string>();
  let holdTimer: number | null = null;
  let generation = 0;
  let shortBackSettled = true;
  let longBackPending = false;

  const dispatchLongBackIfReady = (currentGeneration: number): void => {
    if (!longBackPending || !shortBackSettled || currentGeneration !== generation || pressedSources.size === 0) {
      return;
    }
    longBackPending = false;
    void options.dispatchLongBack();
  };

  const clearHoldTimer = (): void => {
    if (holdTimer !== null) {
      options.timers.clearTimeout(holdTimer);
      holdTimer = null;
    }
  };

  const press = (source: string): void => {
    if (pressedSources.has(source)) return;
    const wasPressed = pressedSources.size > 0;
    pressedSources.add(source);
    if (wasPressed) return;

    const currentGeneration = ++generation;
    shortBackSettled = false;
    longBackPending = false;
    holdTimer = options.timers.setTimeout(() => {
      holdTimer = null;
      if (currentGeneration !== generation || pressedSources.size === 0) return;
      longBackPending = true;
      dispatchLongBackIfReady(currentGeneration);
    }, holdDelayMs);
    const shortBackResult = options.dispatchShortBack();
    if (shortBackResult === undefined) {
      shortBackSettled = true;
      return;
    }
    void shortBackResult.then(
      () => {
        if (currentGeneration !== generation) return;
        shortBackSettled = true;
        dispatchLongBackIfReady(currentGeneration);
      },
      () => {
        if (currentGeneration !== generation) return;
        shortBackSettled = true;
        dispatchLongBackIfReady(currentGeneration);
      },
    );
  };

  const release = (source: string): boolean => {
    if (!pressedSources.delete(source)) return false;
    if (pressedSources.size > 0) return false;
    generation += 1;
    longBackPending = false;
    clearHoldTimer();
    return true;
  };

  return {
    press,
    release,
    cancel: (): void => {
      pressedSources.clear();
      generation += 1;
      longBackPending = false;
      clearHoldTimer();
    },
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
  #suspended = false;

  constructor(config: DesktopGamepadRepeatConfig = {}) {
    this.#axisThreshold = config.axisThreshold ?? DEFAULT_AXIS_THRESHOLD;
    this.#repeatDelayMs = config.repeatDelayMs ?? DEFAULT_REPEAT_DELAY_MS;
    this.#repeatIntervalMs = config.repeatIntervalMs ?? DEFAULT_REPEAT_INTERVAL_MS;
  }

  connect(index: number): void {
    this.#connectedIndexes.add(index);
  }

  disconnect(
    index: number,
    onRelease?: (button: DesktopInputButton, sourceKey: string) => void,
  ): void {
    this.#connectedIndexes.delete(index);
    for (const sourceKey of [...this.#states.keys()]) {
      if (sourceKey.startsWith(`${index}:`)) {
        const state = this.#states.get(sourceKey);
        if (state !== undefined) {
          onRelease?.(state.button, sourceKey);
        }
        this.#states.delete(sourceKey);
      }
    }
  }

  reset(onRelease?: (button: DesktopInputButton, sourceKey: string) => void): void {
    if (onRelease !== undefined) {
      for (const [sourceKey, state] of this.#states) {
        onRelease(state.button, sourceKey);
      }
    }
    this.#connectedIndexes.clear();
    this.#states.clear();
    this.#suspended = false;
  }

  suspend(onRelease?: (button: DesktopInputButton, sourceKey: string) => void): void {
    if (onRelease !== undefined) {
      for (const [sourceKey, state] of this.#states) {
        onRelease(state.button, sourceKey);
      }
    }
    this.#states.clear();
    this.#suspended = true;
  }

  hasConnectedGamepads(): boolean {
    return this.#connectedIndexes.size > 0;
  }

  poll(
    snapshots: ReadonlyArray<DesktopGamepadSnapshot>,
    nowMs: number,
    onRelease?: (button: DesktopInputButton, sourceKey: string) => void,
    onEmit?: (button: DesktopInputButton, sourceKey: string) => void,
    onPress?: (button: DesktopInputButton, sourceKey: string) => void,
  ): DesktopInputButton[] {
    const activeSourceKeys = new Set<string>();
    const emitted = new Set<DesktopInputButton>();

    if (this.#suspended) {
      for (const snapshot of snapshots) {
        if (!snapshot.connected) {
          this.disconnect(snapshot.index, onRelease);
          continue;
        }
        this.connect(snapshot.index);
        if (mapGamepadSnapshot(snapshot, this.#axisThreshold).length > 0) {
          activeSourceKeys.add(`${snapshot.index}:active`);
        }
      }
      if (activeSourceKeys.size === 0) this.#suspended = false;
      return [];
    }

    for (const snapshot of snapshots) {
      if (!snapshot.connected) {
        this.disconnect(snapshot.index, onRelease);
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
          onPress?.(source.button, source.key);
          if (!emitted.has(source.button)) {
            emitted.add(source.button);
            onEmit?.(source.button, source.key);
          }
          continue;
        }

        if (nowMs >= state.nextRepeatAtMs) {
          state.nextRepeatAtMs = nowMs + this.#repeatIntervalMs;
          if (!emitted.has(source.button)) {
            emitted.add(source.button);
            onEmit?.(source.button, source.key);
          }
        }
      }
    }

    for (const sourceKey of [...this.#states.keys()]) {
      if (!activeSourceKeys.has(sourceKey)) {
        const state = this.#states.get(sourceKey);
        if (state !== undefined) {
          onRelease?.(state.button, sourceKey);
        }
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
  let paused = false;

  const poll = (): void => {
    frameHandle = null;
    if (stopped || paused) {
      return;
    }

    const snapshots = options
      .getGamepads()
      .filter((gamepad): gamepad is DesktopGamepadLike => gamepad !== null && gamepad !== undefined)
      .map(createDesktopGamepadSnapshot);

    policy.poll(
      snapshots,
      nowMs(),
      options.onRelease,
      (button, sourceKey) => { void options.dispatch(button, sourceKey); },
      options.onPress,
    );

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
      if (!paused) schedulePoll();
    }
  };

  const handleDisconnected = (event: Event): void => {
    const gamepadIndex = readGamepadIndex(event);
    if (gamepadIndex !== null) {
      policy.disconnect(gamepadIndex, options.onRelease);
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
    pause: (): void => {
      if (stopped || paused) return;
      paused = true;
      if (frameHandle !== null) {
        options.host.cancelAnimationFrame(frameHandle);
        frameHandle = null;
      }
      policy.suspend(options.onRelease);
    },
    resume: (): void => {
      if (stopped || !paused) return;
      paused = false;
      if (policy.hasConnectedGamepads()) schedulePoll();
    },
    cleanup: (): void => {
      stopped = true;
      paused = false;
      options.host.removeEventListener('gamepadconnected', handleConnected);
      options.host.removeEventListener('gamepaddisconnected', handleDisconnected);
      if (frameHandle !== null) {
        options.host.cancelAnimationFrame(frameHandle);
        frameHandle = null;
      }
      policy.reset(options.onRelease);
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
