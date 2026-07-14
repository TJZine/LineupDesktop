export type ShellBootstrapState = 'splash' | 'loading' | 'error' | 'ready';

export interface ShellInlineErrorState {
  desiredFullscreen: boolean;
  message: string;
}

export interface ShellToastState {
  message: string;
  phase: 'visible' | 'fading';
}

export interface RendererShellState {
  bootstrap: ShellBootstrapState;
  blockingErrorMessage: string | null;
  inlineError: ShellInlineErrorState | null;
  toast: ShellToastState | null;
  exitConfirmOpen: boolean;
  fullscreenPending: boolean;
}

export function createRendererShellState(): RendererShellState {
  return {
    bootstrap: 'splash',
    blockingErrorMessage: null,
    inlineError: null,
    toast: null,
    exitConfirmOpen: false,
    fullscreenPending: false,
  };
}

export function beginCapabilitiesRetry(state: RendererShellState): RendererShellState {
  return {
    ...state,
    bootstrap: 'loading',
    blockingErrorMessage: null,
    exitConfirmOpen: false,
  };
}

export function resolveCapabilities(state: RendererShellState): RendererShellState {
  return {
    ...state,
    bootstrap: 'ready',
    blockingErrorMessage: null,
  };
}

export function rejectCapabilities(
  state: RendererShellState,
  message = 'Lineup could not start.',
): RendererShellState {
  return {
    ...state,
    bootstrap: 'error',
    blockingErrorMessage: message,
  };
}

export function beginFullscreenRequest(
  state: RendererShellState,
  preserveInlineError = false,
): RendererShellState {
  return {
    ...state,
    fullscreenPending: true,
    inlineError: preserveInlineError ? state.inlineError : null,
  };
}

export function resolveFullscreenRequest(state: RendererShellState): RendererShellState {
  return {
    ...state,
    fullscreenPending: false,
    inlineError: null,
  };
}

export function rejectFullscreenRequest(
  state: RendererShellState,
  desiredFullscreen: boolean,
  message = 'Try the fullscreen action again.',
): RendererShellState {
  return {
    ...state,
    fullscreenPending: false,
    inlineError: { desiredFullscreen, message },
  };
}

export function dismissFullscreenError(state: RendererShellState): RendererShellState {
  return { ...state, inlineError: null };
}

export function showShellToast(state: RendererShellState, message: string): RendererShellState {
  return { ...state, toast: { message, phase: 'visible' } };
}

export function fadeShellToast(state: RendererShellState): RendererShellState {
  return state.toast === null
    ? state
    : { ...state, toast: { ...state.toast, phase: 'fading' } };
}

export function hideShellToast(state: RendererShellState): RendererShellState {
  return { ...state, toast: null };
}

export function openExitConfirm(state: RendererShellState): RendererShellState {
  return { ...state, exitConfirmOpen: true };
}

export function closeExitConfirm(state: RendererShellState): RendererShellState {
  return { ...state, exitConfirmOpen: false };
}
