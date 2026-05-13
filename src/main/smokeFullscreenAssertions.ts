import type { BrowserWindow } from 'electron';

const FULLSCREEN_TRANSITION_TIMEOUT_MS = 5000;

export async function assertFullscreenContinuity(
  window: BrowserWindow,
  failures: string[],
): Promise<void> {
  const fullscreenOn = await setRendererFullscreen(window, true);
  if (!isExpectedFullscreenResult(fullscreenOn, true)) {
    failures.push('fullscreen on ' + JSON.stringify(fullscreenOn));
    return;
  }

  try {
    if (!(await waitForFullscreenState(window, true))) {
      failures.push('fullscreen enter BrowserWindow state');
      return;
    }
    const fullscreenResult = await window.webContents.executeJavaScript(`
      (() => {
        const failures = [];
        const z = (selector) => {
          const element = document.querySelector(selector);
          return element instanceof HTMLElement ? Number.parseInt(getComputedStyle(element).zIndex, 10) || 0 : null;
        };
        const playerOsdButton = document.querySelector('[data-focus-id="player-osd"]');
        if (document.documentElement.dataset.activeRoute !== 'player') failures.push('fullscreen route continuity');
        if (
          !(playerOsdButton instanceof HTMLButtonElement) ||
          document.activeElement !== playerOsdButton ||
          playerOsdButton.tabIndex !== 0
        ) {
          failures.push('fullscreen focus continuity');
        }
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
  } finally {
    try {
      const fullscreenOff = await setRendererFullscreen(window, false);
      if (!isExpectedFullscreenResult(fullscreenOff, false)) {
        failures.push('fullscreen off ' + JSON.stringify(fullscreenOff));
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      failures.push('fullscreen off ' + message);
    }
    if (!(await waitForFullscreenState(window, false))) {
      failures.push('fullscreen leave BrowserWindow state');
    }
  }
}

async function setRendererFullscreen(window: BrowserWindow, enabled: boolean): Promise<unknown> {
  return window.webContents.executeJavaScript(
    `window.lineupDesktop.window.setFullscreen(${JSON.stringify(enabled)});`,
  ) as Promise<unknown>;
}

function isExpectedFullscreenResult(result: unknown, enabled: boolean): boolean {
  if (typeof result !== 'object' || result === null) return false;
  const envelope = result as { ok?: unknown; value?: unknown };
  const value = envelope.value as { enabled?: unknown } | null;
  return envelope.ok === true && typeof value === 'object' && value?.enabled === enabled;
}

function waitForFullscreenState(window: BrowserWindow, enabled: boolean): Promise<boolean> {
  if (window.isDestroyed() || window.isFullScreen() === enabled) {
    return Promise.resolve(!window.isDestroyed());
  }
  return new Promise((resolve) => {
    let completed = false;
    const finish = (observed: boolean): void => {
      if (completed) return;
      completed = true;
      globalThis.clearTimeout(timeout);
      if (enabled) window.off('enter-full-screen', onTransition);
      else window.off('leave-full-screen', onTransition);
      resolve(observed);
    };
    const onTransition = (): void => finish(!window.isDestroyed() && window.isFullScreen() === enabled);
    const timeout = setTimeout(
      () => finish(!window.isDestroyed() && window.isFullScreen() === enabled),
      FULLSCREEN_TRANSITION_TIMEOUT_MS,
    );
    if (enabled) window.on('enter-full-screen', onTransition);
    else window.on('leave-full-screen', onTransition);
  });
}
