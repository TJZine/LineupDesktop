export type DesktopCursorState = 'visible' | 'hidden';

export interface DesktopCursorRoot {
  classList: {
    toggle: (className: string, force?: boolean) => boolean;
  };
  dataset: Record<string, string | undefined>;
}

export interface DesktopCursorHost {
  addEventListener: (type: string, listener: EventListener, options?: AddEventListenerOptions) => void;
  removeEventListener: (type: string, listener: EventListener, options?: EventListenerOptions) => void;
}

export interface DesktopCursorTimerPort {
  setTimeout: (callback: () => void, delayMs: number) => number;
  clearTimeout: (handle: number) => void;
}

export interface DesktopCursorRuntimeOptions {
  host: DesktopCursorHost;
  root: DesktopCursorRoot;
  timers?: DesktopCursorTimerPort;
  inactivityDelayMs?: number;
}

export interface DesktopCursorRuntime {
  getState: () => DesktopCursorState;
  showForPointerActivity: () => void;
  hideForDesktopInput: () => void;
  cleanup: () => void;
}

const CURSOR_HIDDEN_CLASS = 'desktop-cursor-hidden';
const DEFAULT_INACTIVITY_DELAY_MS = 2400;

export function createDesktopCursorRuntime(
  options: DesktopCursorRuntimeOptions,
): DesktopCursorRuntime {
  const timers = options.timers ?? browserTimerPort();
  const inactivityDelayMs = options.inactivityDelayMs ?? DEFAULT_INACTIVITY_DELAY_MS;
  let state: DesktopCursorState = 'visible';
  let inactivityHandle: number | null = null;
  let cleanedUp = false;

  const applyState = (): void => {
    options.root.dataset.desktopCursor = state;
    options.root.classList.toggle(CURSOR_HIDDEN_CLASS, state === 'hidden');
  };

  const clearInactivityTimer = (): void => {
    if (inactivityHandle !== null) {
      timers.clearTimeout(inactivityHandle);
      inactivityHandle = null;
    }
  };

  const scheduleInactivityHide = (): void => {
    clearInactivityTimer();
    inactivityHandle = timers.setTimeout(() => {
      inactivityHandle = null;
      state = 'hidden';
      applyState();
    }, inactivityDelayMs);
  };

  const showForPointerActivity = (): void => {
    if (cleanedUp) {
      return;
    }
    state = 'visible';
    applyState();
    scheduleInactivityHide();
  };

  const hideForDesktopInput = (): void => {
    if (cleanedUp) {
      return;
    }
    clearInactivityTimer();
    state = 'hidden';
    applyState();
  };

  const handlePointerActivity = (): void => {
    showForPointerActivity();
  };

  options.host.addEventListener('pointermove', handlePointerActivity, { passive: true });
  options.host.addEventListener('mousemove', handlePointerActivity, { passive: true });
  applyState();
  scheduleInactivityHide();

  return {
    getState: () => state,
    showForPointerActivity,
    hideForDesktopInput,
    cleanup: (): void => {
      if (cleanedUp) {
        return;
      }
      cleanedUp = true;
      clearInactivityTimer();
      options.host.removeEventListener('pointermove', handlePointerActivity);
      options.host.removeEventListener('mousemove', handlePointerActivity);
      state = 'visible';
      applyState();
    },
  };
}

function browserTimerPort(): DesktopCursorTimerPort {
  return {
    setTimeout: (callback, delayMs) => window.setTimeout(callback, delayMs),
    clearTimeout: (handle) => {
      window.clearTimeout(handle);
    },
  };
}
