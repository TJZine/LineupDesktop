import type { LineupDesktopPreloadApi, ShellCapabilities } from '../../contracts/shell.js';
import {
  beginCapabilitiesRetry,
  beginFullscreenRequest,
  dismissFullscreenError,
  fadeShellToast,
  hideShellToast,
  rejectCapabilities,
  rejectFullscreenRequest,
  resolveCapabilities,
  resolveFullscreenRequest,
  showShellToast,
  type RendererShellState,
} from './shellState.js';

const TOAST_VISIBLE_MS = 5000;
const TOAST_FADE_MS = 200;
const TOAST_DUPLICATE_THROTTLE_MS = 1500;

export interface ShellControllerHost {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(handle: number): void;
}

export interface ShellControllerOptions {
  shell: LineupDesktopPreloadApi['shell'];
  windowBridge: LineupDesktopPreloadApi['window'];
  host: ShellControllerHost;
  getState(): RendererShellState;
  setState(state: RendererShellState): void;
  render(): void;
  applyCapabilities(capabilities: ShellCapabilities): void;
  applyFullscreen(enabled: boolean): void;
  restoreFocus(focusId: string): void;
  nowMs?: () => number;
}

export interface ShellController {
  start(): Promise<void>;
  retryCapabilities(): Promise<void>;
  requestFullscreen(desired: boolean, acceptedFocusId: string): Promise<void>;
  retryFullscreen(): Promise<void>;
  dismissFullscreenError(): void;
  invalidateFullscreenRequest(): void;
  cleanup(): void;
}

export function createShellController(options: ShellControllerOptions): ShellController {
  let capabilitiesGeneration = 0;
  let fullscreenGeneration = 0;
  let retryPending = false;
  let fullscreenPending = false;
  let lastToastAtMs = Number.NEGATIVE_INFINITY;
  let lastToastEnabled: boolean | null = null;
  let toastFadeTimer: number | null = null;
  let toastHideTimer: number | null = null;
  let cleanedUp = false;
  const nowMs = options.nowMs ?? Date.now;

  const update = (state: RendererShellState): void => {
    options.setState(state);
    options.render();
  };

  const requestCapabilities = async (kind: 'initial' | 'retry'): Promise<void> => {
    if (cleanedUp || (kind === 'retry' && retryPending)) return;
    const generation = ++capabilitiesGeneration;
    retryPending = kind === 'retry';
    if (kind === 'retry') update(beginCapabilitiesRetry(options.getState()));

    try {
      const result = await options.shell.getCapabilities();
      if (cleanedUp || generation !== capabilitiesGeneration) return;
      retryPending = false;
      if (isValidCapabilitiesResult(result)) {
        options.applyCapabilities(result.value);
        update(resolveCapabilities(options.getState()));
        return;
      }
    } catch {
      // Normalize bridge rejection to the same renderer-safe blocking state.
    }
    if (cleanedUp || generation !== capabilitiesGeneration) return;
    retryPending = false;
    update(rejectCapabilities(options.getState()));
    options.restoreFocus('shell-error-retry');
  };

  const showFullscreenToast = (enabled: boolean): void => {
    const shownAtMs = nowMs();
    if (lastToastEnabled === enabled && shownAtMs - lastToastAtMs < TOAST_DUPLICATE_THROTTLE_MS) return;
    lastToastAtMs = shownAtMs;
    lastToastEnabled = enabled;
    clearToastTimers();
    update(showShellToast(options.getState(), enabled ? 'Entered fullscreen' : 'Exited fullscreen'));
    toastFadeTimer = options.host.setTimeout(() => {
      toastFadeTimer = null;
      update(fadeShellToast(options.getState()));
      toastHideTimer = options.host.setTimeout(() => {
        toastHideTimer = null;
        update(hideShellToast(options.getState()));
      }, TOAST_FADE_MS);
    }, TOAST_VISIBLE_MS);
  };

  const requestFullscreen = async (
    desired: boolean,
    acceptedFocusId: string,
    failureFocusId = 'shell-inline-dismiss',
    preserveInlineError = false,
  ): Promise<void> => {
    if (cleanedUp || fullscreenPending) return;
    fullscreenPending = true;
    const generation = ++fullscreenGeneration;
    update(beginFullscreenRequest(options.getState(), preserveInlineError));
    try {
      const result = await options.windowBridge.setFullscreen(desired);
      if (cleanedUp) return;
      if (isValidFullscreenResult(result, desired)) {
        options.applyFullscreen(result.value.enabled);
        if (generation !== fullscreenGeneration) return;
        update(resolveFullscreenRequest(options.getState()));
        options.restoreFocus(acceptedFocusId);
        showFullscreenToast(result.value.enabled);
        return;
      }
    } catch {
      // Normalize bridge rejection to the same renderer-safe inline state.
    } finally {
      fullscreenPending = false;
    }
    if (cleanedUp || generation !== fullscreenGeneration) return;
    update(rejectFullscreenRequest(options.getState(), desired));
    options.restoreFocus(failureFocusId);
  };

  const clearToastTimers = (): void => {
    if (toastFadeTimer !== null) options.host.clearTimeout(toastFadeTimer);
    if (toastHideTimer !== null) options.host.clearTimeout(toastHideTimer);
    toastFadeTimer = null;
    toastHideTimer = null;
  };

  return {
    start: () => requestCapabilities('initial'),
    retryCapabilities: () => requestCapabilities('retry'),
    requestFullscreen,
    retryFullscreen: async () => {
      const desired = options.getState().inlineError?.desiredFullscreen;
      if (desired !== undefined) {
        await requestFullscreen(desired, 'player-fullscreen', 'shell-inline-retry', true);
      }
    },
    dismissFullscreenError: () => {
      fullscreenGeneration += 1;
      update(dismissFullscreenError(options.getState()));
      options.restoreFocus('player-fullscreen');
    },
    invalidateFullscreenRequest: () => {
      fullscreenGeneration += 1;
      if (options.getState().fullscreenPending || options.getState().inlineError !== null) {
        update(dismissFullscreenError(resolveFullscreenRequest(options.getState())));
      }
    },
    cleanup: () => {
      cleanedUp = true;
      capabilitiesGeneration += 1;
      fullscreenGeneration += 1;
      retryPending = false;
      clearToastTimers();
    },
  };
}

function isValidCapabilitiesResult(
  value: unknown,
): value is Awaited<ReturnType<LineupDesktopPreloadApi['shell']['getCapabilities']>> & { ok: true } {
  if (typeof value !== 'object' || value === null) return false;
  const result = value as { ok?: unknown; value?: unknown };
  if (result.ok !== true || typeof result.value !== 'object' || result.value === null) return false;
  const capabilities = result.value as Partial<ShellCapabilities>;
  return (
    capabilities.appName === 'Lineup Desktop'
    && typeof capabilities.appVersion === 'string'
    && typeof capabilities.platform === 'string'
    && typeof capabilities.shellMode === 'string'
    && capabilities.protocolOrigin === 'lineup://shell'
  );
}

function isValidFullscreenResult(
  value: unknown,
  desired: boolean,
): value is Awaited<ReturnType<LineupDesktopPreloadApi['window']['setFullscreen']>> & { ok: true } {
  if (typeof value !== 'object' || value === null) return false;
  const result = value as { ok?: unknown; value?: unknown };
  return result.ok === true
    && typeof result.value === 'object'
    && result.value !== null
    && (result.value as { enabled?: unknown }).enabled === desired;
}
