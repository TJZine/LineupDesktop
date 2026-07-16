import type { DesktopInputButton, FocusState, AppRouteId, FocusRegistry } from '../navigation.js';
import type { RendererDomBindings } from '../domBindings.js';
import {
  clickFocusedRendererElement,
  focusRendererTarget,
  moveRendererFocus,
  syncRendererFocusTargets,
} from '../focusDom.js';
import { createDesktopCursorRuntime } from '../desktopCursor.js';
import { createDesktopKeyboardInputListener, startDesktopGamepadRuntime } from '../desktopInput.js';
import { closeExitConfirm, openExitConfirm, type RendererShellState } from './shellState.js';

export interface NavigationLifecycleOptions {
  getRoute(): AppRouteId;
  getFocusState(): FocusState;
  setFocusState(state: FocusState): void;
  getShellState(): RendererShellState;
  setShellState(state: RendererShellState): void;
  render(): void;
  focusRegistry: FocusRegistry;
  dom: RendererDomBindings;
  onFocusChanged(focusId: string | null): void;
  scrollFocusedIntoView(): void;
  activateRoute(route: AppRouteId): void;
  isProfileModalActive(): boolean;
  closeProfileModal(): void;
  handleChannelSetupBack(): Promise<boolean>;
  handlePlayerOverlayBack(): boolean;
  dismissInlineError(): void;
  requestFullscreen(acceptedFocusId: string): Promise<void>;
  invalidateFullscreenRequest(): void;
  closeWindow(): void;
}

export interface NavigationLifecycle {
  handleInput(input: DesktopInputButton): Promise<void>;
  cancelExit(): void;
  confirmExit(): void;
  closeApplication(): void;
  routeChanged(previousRoute: AppRouteId, nextRoute: AppRouteId): void;
  cleanup(): void;
}

export interface NavigationInputRuntimeOptions {
  host: Window;
  root: HTMLElement;
  onBeforeUnload(): void;
}

export function attachNavigationInputRuntime(
  lifecycle: NavigationLifecycle,
  options: NavigationInputRuntimeOptions,
): void {
  const cursor = createDesktopCursorRuntime({ host: options.host, root: options.root });
  const dispatch = (input: DesktopInputButton): Promise<void> => {
    cursor.hideForDesktopInput();
    return lifecycle.handleInput(input);
  };
  const keydown = createDesktopKeyboardInputListener(dispatch);
  const gamepad = startDesktopGamepadRuntime({
    host: options.host,
    getGamepads: () => options.host.navigator.getGamepads(),
    dispatch,
  });
  options.host.addEventListener('keydown', keydown);
  options.host.addEventListener('beforeunload', () => {
    options.host.removeEventListener('keydown', keydown);
    cursor.cleanup();
    gamepad.cleanup();
    lifecycle.cleanup();
    options.onBeforeUnload();
  });
}

export function createNavigationLifecycle(options: NavigationLifecycleOptions): NavigationLifecycle {
  const routeFocusMemory = new Map<AppRouteId, string>();
  let exitInvoker: string | null = null;
  let cleanedUp = false;
  let closeInvoked = false;

  const focusTarget = (focusId: string): void => {
    syncRendererFocusTargets(options.focusRegistry, options.dom);
    options.setFocusState(focusRendererTarget(
      options.focusRegistry,
      options.getFocusState(),
      focusId,
      options.dom,
    ));
  };

  const moveFocus = (direction: 'up' | 'down' | 'left' | 'right'): void => {
    const previous = options.getFocusState();
    const next = moveRendererFocus(options.focusRegistry, previous, direction, options.dom);
    options.setFocusState(next);
    if (next.activeId !== previous.activeId) options.onFocusChanged(next.activeId);
    options.scrollFocusedIntoView();
  };

  const focusRoute = (route: AppRouteId, rememberedFocusId: string | null): void => {
    const state = options.getFocusState();
    options.setFocusState(rememberedFocusId === null
      ? options.focusRegistry.focusRoute(state, route).state
      : options.focusRegistry.focusTarget({ ...state, activeRoute: route }, rememberedFocusId).state);
    options.render();
  };

  const rememberCurrentFocus = (): void => {
    const state = options.getFocusState();
    if (state.activeId !== null) routeFocusMemory.set(state.activeRoute, state.activeId);
  };

  const openExit = (): void => {
    exitInvoker = options.getFocusState().activeId;
    options.setShellState(openExitConfirm(options.getShellState()));
    options.render();
    focusTarget('exit-confirm-cancel');
  };

  const cancelExit = (): void => {
    options.setShellState(closeExitConfirm(options.getShellState()));
    options.render();
    focusTarget(exitInvoker ?? 'player-fullscreen');
    exitInvoker = null;
  };

  const navigate = (route: AppRouteId): void => {
    if (options.getRoute() === route) return;
    rememberCurrentFocus();
    options.activateRoute(route);
    focusRoute(route, routeFocusMemory.get(route) ?? null);
  };

  return {
    async handleInput(input): Promise<void> {
      if (cleanedUp) return;
      const shellState = options.getShellState();
      if (shellState.bootstrap === 'splash' || shellState.bootstrap === 'loading') return;
      if (shellState.bootstrap === 'error') {
        if (input === 'up' || input === 'down' || input === 'left' || input === 'right') {
          moveFocus(input);
        } else if (input === 'ok') {
          clickFocusedRendererElement(options.getFocusState(), options.dom);
        }
        return;
      }
      if (shellState.inlineError !== null) {
        if (input === 'back') options.dismissInlineError();
        else if (input === 'up' || input === 'down' || input === 'left' || input === 'right') moveFocus(input);
        else if (input === 'ok') clickFocusedRendererElement(options.getFocusState(), options.dom);
        return;
      }
      if (shellState.exitConfirmOpen) {
        if (input === 'back') cancelExit();
        else if (input === 'up' || input === 'down' || input === 'left' || input === 'right') moveFocus(input);
        else if (input === 'ok') clickFocusedRendererElement(options.getFocusState(), options.dom);
        return;
      }

      if (input === 'up' || input === 'down' || input === 'left' || input === 'right') {
        moveFocus(input);
        return;
      }
      if (input === 'ok') {
        clickFocusedRendererElement(options.getFocusState(), options.dom);
        return;
      }
      if (input === 'back') {
        if (options.isProfileModalActive()) {
          options.closeProfileModal();
          return;
        }
        if (options.getRoute() === 'channelSetup' && await options.handleChannelSetupBack()) return;
        if (options.getRoute() === 'player') {
          if (options.handlePlayerOverlayBack()) return;
          openExit();
          return;
        }
        navigate('player');
        return;
      }
      if (input === 'guide') {
        navigate('guide');
        return;
      }
      if (input === 'settings') {
        navigate('settings');
        return;
      }
      if (input === 'fullscreen' && options.getRoute() === 'player') {
        await options.requestFullscreen(options.getFocusState().activeId ?? 'player-fullscreen');
      }
    },
    cancelExit,
    confirmExit(): void {
      if (!options.getShellState().exitConfirmOpen) return;
      if (closeInvoked) return;
      closeInvoked = true;
      options.closeWindow();
    },
    closeApplication(): void {
      if (closeInvoked) return;
      closeInvoked = true;
      options.closeWindow();
    },
    routeChanged(previousRoute, nextRoute): void {
      if (previousRoute === nextRoute) return;
      options.invalidateFullscreenRequest();
      const current = options.getFocusState();
      if (current.activeId !== null) routeFocusMemory.set(previousRoute, current.activeId);
    },
    cleanup(): void {
      cleanedUp = true;
      routeFocusMemory.clear();
      exitInvoker = null;
      options.invalidateFullscreenRequest();
    },
  };
}
