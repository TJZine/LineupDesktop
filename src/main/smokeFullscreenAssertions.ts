import electron, { type BrowserWindow } from 'electron';

const { app } = electron;

const FOCUS_TIMEOUT_MS = 1000;
const FULLSCREEN_TRANSITION_TIMEOUT_MS = 5000;
const FULLSCREEN_STATE_POLL_MS = 25;

export interface FullscreenObservationWindow {
  isDestroyed(): boolean;
  isFullScreen(): boolean;
  on(event: 'enter-full-screen' | 'leave-full-screen', listener: () => void): unknown;
  off(event: 'enter-full-screen' | 'leave-full-screen', listener: () => void): unknown;
}

export interface FullscreenObservationScheduler<TimerHandle> {
  setTimeout(callback: () => void, delayMs: number): TimerHandle;
  clearTimeout(handle: TimerHandle): void;
}

const fullscreenObservationScheduler: FullscreenObservationScheduler<ReturnType<typeof globalThis.setTimeout>> = {
  setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  clearTimeout: (handle) => globalThis.clearTimeout(handle),
};

interface FullscreenTransitionResult {
  result: unknown;
  observed: boolean;
}

export async function assertFullscreenContinuity(
  window: BrowserWindow,
  failures: string[],
): Promise<void> {
  try {
    await ensureVisibleForFullscreen(window);
    const fullscreenOn = await setRendererFullscreenAndWait(window, true);
    if (
      !isExpectedFullscreenResult(fullscreenOn.result, true)
      || (!fullscreenOn.observed && window.isFullScreenable() && window.isFocused())
    ) {
      failures.push('fullscreen on ' + JSON.stringify({
        result: fullscreenOn.result,
        observed: fullscreenOn.observed,
        window: getFullscreenDiagnostics(window),
      }));
      return;
    }
    const fullscreenResult = await window.webContents.executeJavaScript(`
      (() => {
        const failures = [];
        const z = (selector) => {
          const element = document.querySelector(selector);
          return element instanceof HTMLElement ? Number.parseInt(getComputedStyle(element).zIndex, 10) || 0 : null;
        };
        if (document.documentElement.dataset.activeRoute !== 'player') failures.push('fullscreen route continuity');
        const presentation = document.querySelector('[data-player-presentation-surface]');
        if (!(presentation instanceof HTMLElement) || presentation.tabIndex !== -1) failures.push('fullscreen native presentation continuity');
        const active = document.activeElement;
        if (active instanceof HTMLElement && active.closest('[hidden], [inert], [aria-hidden="true"]') !== null) failures.push('fullscreen hidden focus');
        const presentationZ = z('[data-player-presentation-surface]');
        const screenZ = z('[data-screen="player"]');
        const overlayZ = z('[data-overlay-stack]');
        if (presentationZ === null || screenZ === null || overlayZ === null) {
          failures.push('fullscreen z-order target');
        } else if (!(presentationZ < screenZ && screenZ < overlayZ)) {
          failures.push('fullscreen rd15 z-order ' + JSON.stringify({ presentationZ, screenZ, overlayZ }));
        }
        return { failures };
      })();
    `) as { failures: string[] };
    failures.push(...fullscreenResult.failures);
    if (!fullscreenOn.observed && window.isFullScreenable() && window.isFocused()) {
      failures.push('fullscreen enter BrowserWindow state ' + JSON.stringify(getFullscreenDiagnostics(window)));
    }
  } catch (error) {
    failures.push('fullscreen continuity ' + formatSmokeError(error));
  } finally {
    try {
      const fullscreenOff = await setRendererFullscreenAndWait(window, false);
      if (!isExpectedFullscreenResult(fullscreenOff.result, false) || !fullscreenOff.observed) {
        failures.push('fullscreen off ' + JSON.stringify(fullscreenOff.result));
      }
    } catch (error) {
      failures.push('fullscreen off ' + formatSmokeError(error));
    }
    if (isFullscreenState(window, true) && !(await waitForFullscreenState(window, false, fullscreenObservationScheduler))) {
      failures.push('fullscreen leave BrowserWindow state');
    }
  }
}

export async function assertRendererCloseLifecycle(
  window: BrowserWindow,
  failures: string[],
): Promise<void> {
  const observed = {
    browserWindowClosed: false,
    windowAllClosed: false,
    beforeQuit: false,
    willQuit: false,
  };
  const waitForLifecycle = new Promise<void>((resolve) => {
    const check = (): void => {
      if (Object.values(observed).every(Boolean)) resolve();
    };
    window.once('closed', () => { observed.browserWindowClosed = true; check(); });
    app.once('window-all-closed', () => { observed.windowAllClosed = true; check(); });
    app.once('before-quit', () => { observed.beforeQuit = true; check(); });
    app.once('will-quit', () => { observed.willQuit = true; check(); });
  });
  const timeout = new Promise<void>((resolve) => { setTimeout(resolve, 5000); });

  let rendererResult: unknown = null;
  try {
    rendererResult = await window.webContents.executeJavaScript(`
      (async () => {
        for (let attempt = 0; attempt < 8; attempt += 1) {
          window.dispatchEvent(new KeyboardEvent('keydown', {
            key: 'Escape', bubbles: true, cancelable: true
          }));
          await new Promise((resolve) => setTimeout(resolve, 0));
          const candidate = document.querySelector('[data-shell-action="confirm-exit"]');
          if (candidate instanceof HTMLButtonElement && !candidate.closest('[hidden]')) break;
        }
        const confirm = document.querySelector('[data-shell-action="confirm-exit"]');
        if (!(confirm instanceof HTMLButtonElement) || confirm.closest('[hidden]')) {
          return {
            invoked: false,
            route: document.documentElement.dataset.activeRoute,
            activeFocus: document.activeElement instanceof HTMLElement
              ? document.activeElement.dataset.focusId ?? null : null,
            overlay: document.documentElement.dataset.activeOverlay,
          };
        }
        confirm.click();
        return { invoked: true };
      })();
    `);
  } catch {
    // BrowserWindow destruction may reject evaluation after the synchronous close.
  }

  await Promise.race([waitForLifecycle, timeout]);
  if (!Object.values(observed).every(Boolean)) {
    failures.push('renderer close lifecycle ' + JSON.stringify({ observed, rendererResult }));
  }
}

function ensureVisibleForFullscreen(window: BrowserWindow): Promise<void> {
  if (window.isDestroyed() || window.isVisible()) {
    return focusSmokeWindow(window);
  }
  return new Promise((resolve) => {
    let completed = false;
    const finish = (): void => {
      if (completed) return;
      completed = true;
      globalThis.clearTimeout(timeout);
      window.off('show', finish);
      void focusSmokeWindow(window).then(resolve);
    };
    const timeout = setTimeout(finish, 1000);
    window.once('show', finish);
    window.show();
  });
}

async function focusSmokeWindow(window: BrowserWindow): Promise<void> {
  if (window.isDestroyed()) {
    return;
  }
  app.focus({ steal: true });
  window.focus();
  if (window.isFocused()) {
    return;
  }
  await new Promise<void>((resolve) => {
    let completed = false;
    const finish = (): void => {
      if (completed) return;
      completed = true;
      globalThis.clearTimeout(timeout);
      window.off('focus', finish);
      resolve();
    };
    const timeout = setTimeout(finish, FOCUS_TIMEOUT_MS);
    window.once('focus', finish);
  });
}

async function setRendererFullscreen(window: BrowserWindow, enabled: boolean): Promise<unknown> {
  return window.webContents.executeJavaScript(
    `window.lineupDesktop.window.setFullscreen(${JSON.stringify(enabled)});`,
  ) as Promise<unknown>;
}

async function setRendererFullscreenAndWait(
  window: BrowserWindow,
  enabled: boolean,
): Promise<FullscreenTransitionResult> {
  const transition = waitForFullscreenState(window, enabled, fullscreenObservationScheduler);
  const result = await setRendererFullscreen(window, enabled);
  const observed = await transition;
  return { result, observed };
}

function formatSmokeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isExpectedFullscreenResult(result: unknown, enabled: boolean): boolean {
  if (typeof result !== 'object' || result === null) return false;
  const envelope = result as { ok?: unknown; value?: unknown };
  const value = envelope.value as { enabled?: unknown } | null;
  return envelope.ok === true && typeof value === 'object' && value?.enabled === enabled;
}

export function waitForFullscreenState<TimerHandle>(
  window: FullscreenObservationWindow,
  enabled: boolean,
  scheduler: FullscreenObservationScheduler<TimerHandle>,
): Promise<boolean> {
  if (window.isDestroyed() || isFullscreenState(window, enabled)) {
    return Promise.resolve(!window.isDestroyed());
  }
  return new Promise((resolve) => {
    let completed = false;
    let eventObserved = false;
    let stateObserved = false;
    let pollTimer: TimerHandle | null = null;
    let deadlineTimer: TimerHandle | null = null;
    const eventName = enabled ? 'enter-full-screen' : 'leave-full-screen';
    const finish = (observed: boolean): void => {
      if (completed) return;
      completed = true;
      if (pollTimer !== null) scheduler.clearTimeout(pollTimer);
      if (deadlineTimer !== null) scheduler.clearTimeout(deadlineTimer);
      pollTimer = null;
      deadlineTimer = null;
      window.off(eventName, onTransition);
      resolve(observed);
    };
    const reconcile = (): void => {
      if (window.isDestroyed()) { finish(false); return; }
      stateObserved ||= isFullscreenState(window, enabled);
      if (eventObserved && stateObserved) finish(true);
    };
    const poll = (): void => {
      pollTimer = null;
      reconcile();
      if (!completed) pollTimer = scheduler.setTimeout(poll, FULLSCREEN_STATE_POLL_MS);
    };
    const onTransition = (): void => {
      eventObserved = true;
      reconcile();
    };
    window.on(eventName, onTransition);
    deadlineTimer = scheduler.setTimeout(() => {
      deadlineTimer = null;
      reconcile();
      if (!completed) finish(false);
    }, FULLSCREEN_TRANSITION_TIMEOUT_MS);
    pollTimer = scheduler.setTimeout(poll, FULLSCREEN_STATE_POLL_MS);
  });
}

function isFullscreenState(window: Pick<FullscreenObservationWindow, 'isFullScreen'>, enabled: boolean): boolean {
  return window.isFullScreen() === enabled;
}

function getFullscreenDiagnostics(window: BrowserWindow): Record<string, unknown> {
  return {
    fullscreenable: window.isFullScreenable(),
    fullscreen: window.isFullScreen(),
    visible: window.isVisible(),
    focused: window.isFocused(),
    minimized: window.isMinimized(),
    bounds: window.getBounds(),
  };
}
