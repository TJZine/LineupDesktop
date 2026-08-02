import type { DesktopInputButton, FocusState, AppRouteId, FocusRegistry } from '../navigation.js';
import type { RendererDomBindings } from '../domBindings.js';
import {
  clickFocusedRendererElement,
  focusRendererTarget,
  moveRendererFocus,
  syncRendererFocusTargets,
} from '../focusDom.js';
import { createDesktopCursorRuntime } from '../desktopCursor.js';
import {
  createDesktopBackHoldRuntime,
  createDesktopKeyboardInputListener,
  createDesktopKeyboardInputReleaseListener,
  startDesktopGamepadRuntime,
  type DesktopBackHoldTimerPort,
} from '../desktopInput.js';
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
  handleGuideDirection?(direction: 'up' | 'down' | 'left' | 'right'): boolean;
  handleGuidePage?(offset: -5 | 5): boolean;
  handlePlayerInput?(input: DesktopInputButton): boolean;
  handlePlayerRouteLeave?(): void;
  openInfoRecovery(): void;
  activateRoute(route: AppRouteId): boolean | void;
  isProfileModalActive(): boolean;
  closeProfileModal(): void;
  handleChannelSetupBack(): Promise<boolean>;
  dismissInlineError(): void;
  requestFullscreen(acceptedFocusId: string): Promise<void>;
  invalidateFullscreenRequest(): void;
  closeWindow(): void;
}

export interface NavigationLifecycle {
  handleInput(input: DesktopInputButton): Promise<void>;
  handleBackPress(): Promise<void>;
  handleBackHold(): Promise<void>;
  cancelBackHold(): void;
  cancelExit(): void;
  confirmExit(): void;
  closeApplication(): void;
  routeChanged(previousRoute: AppRouteId, nextRoute: AppRouteId): void;
  cleanup(): void;
}

export function activateInfoRecovery(
  activateChannelSetup: () => boolean,
  openSelectedStage: () => void,
): boolean {
  if (!activateChannelSetup()) return false;
  openSelectedStage();
  return true;
}

export interface NavigationInputRuntimeOptions {
  host: Window;
  root: HTMLElement;
  timers?: DesktopBackHoldTimerPort;
  onBeforeUnload(): void;
}

export function attachNavigationInputRuntime(
  lifecycle: NavigationLifecycle,
  options: NavigationInputRuntimeOptions,
): void {
  const cursor = createDesktopCursorRuntime({ host: options.host, root: options.root });
  const timers = options.timers ?? {
    setTimeout: (callback: () => void, delayMs: number): number =>
      options.host.setTimeout(callback, delayMs),
    clearTimeout: (handle: number): void => {
      options.host.clearTimeout(handle);
    },
  };
  const backHold = createDesktopBackHoldRuntime({
    dispatchShortBack: () => {
      cursor.hideForDesktopInput();
      return lifecycle.handleBackPress();
    },
    dispatchLongBack: () => {
      cursor.hideForDesktopInput();
      return lifecycle.handleBackHold();
    },
    timers,
  });
  const dispatch = (input: DesktopInputButton): Promise<void> => {
    cursor.hideForDesktopInput();
    return lifecycle.handleInput(input);
  };
  const keydown = createDesktopKeyboardInputListener(dispatch, {
    onBackPress: (sourceKey) => backHold.press(sourceKey),
  });
  const keyup = createDesktopKeyboardInputReleaseListener((sourceKey) => {
    if (backHold.release(sourceKey)) lifecycle.cancelBackHold();
  });
  const gamepad = startDesktopGamepadRuntime({
    host: options.host,
    getGamepads: () => options.host.navigator.getGamepads(),
    dispatch: (input) => {
      if (input === 'back') {
        return;
      }
      void dispatch(input);
    },
    onPress: (input, sourceKey) => {
      if (input === 'back') {
        cursor.hideForDesktopInput();
        backHold.press(sourceKey ?? 'gamepad');
      }
    },
    onRelease: (input, sourceKey) => {
      if (input === 'back' && backHold.release(sourceKey ?? 'gamepad')) {
        lifecycle.cancelBackHold();
      }
    },
  });
  const blur = (): void => {
    backHold.cancel();
    lifecycle.cancelBackHold();
    gamepad.pause?.();
  };
  const focus = (): void => {
    gamepad.resume?.();
  };
  options.host.addEventListener('keydown', keydown);
  options.host.addEventListener('keyup', keyup);
  options.host.addEventListener('blur', blur);
  options.host.addEventListener('focus', focus);
  const beforeUnload = (): void => {
    backHold.cancel();
    lifecycle.cancelBackHold();
    options.host.removeEventListener('keydown', keydown);
    options.host.removeEventListener('keyup', keyup);
    options.host.removeEventListener('blur', blur);
    options.host.removeEventListener('focus', focus);
    options.host.removeEventListener('beforeunload', beforeUnload);
    cursor.cleanup();
    gamepad.cleanup();
    lifecycle.cleanup();
    options.onBeforeUnload();
  };
  options.host.addEventListener('beforeunload', beforeUnload);
}

export function createNavigationLifecycle(options: NavigationLifecycleOptions): NavigationLifecycle {
  const routeFocusMemory = new Map<AppRouteId, string | null>();
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

  const focusRoute = (route: AppRouteId, rememberedFocusId: string | null | undefined): void => {
    const state = options.getFocusState();
    options.setFocusState(rememberedFocusId === undefined
      ? options.focusRegistry.focusRoute(state, route).state
      : rememberedFocusId === null
        ? { activeRoute: route, activeId: null }
        : options.focusRegistry.focusTarget({ ...state, activeRoute: route }, rememberedFocusId).state);
    options.render();
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
    if (exitInvoker === null) {
      options.setFocusState({ activeRoute: 'player', activeId: null });
      options.dom.playerPresentationElement?.focus();
    } else {
      focusTarget(exitInvoker);
    }
    exitInvoker = null;
  };

  const navigate = (route: AppRouteId): void => {
    if (options.getRoute() === route) return;
    const previousFocus = options.getFocusState();
    const accepted = options.activateRoute(route);
    if (accepted === false || options.getRoute() !== route) return;
    routeFocusMemory.set(previousFocus.activeRoute, previousFocus.activeId);
    focusRoute(route, routeFocusMemory.get(route));
  };

  let backPressProtected = false;

  const handleInput = async (input: DesktopInputButton): Promise<void> => {
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

    if (options.isProfileModalActive()) {
      if (input === 'back') options.closeProfileModal();
      else if (input === 'up' || input === 'down' || input === 'left' || input === 'right') moveFocus(input);
      else if (input === 'ok') clickFocusedRendererElement(options.getFocusState(), options.dom);
      return;
    }

    if (options.getRoute() === 'player' && options.handlePlayerInput?.(input) === true) {
      return;
    }

    if (input === 'up' || input === 'down' || input === 'left' || input === 'right') {
      if (options.getRoute() === 'guide' && options.handleGuideDirection?.(input) === true) return;
      moveFocus(input);
      return;
    }
    if (input === 'ok') {
      clickFocusedRendererElement(options.getFocusState(), options.dom);
      return;
    }
    if (input === 'pageUp' || input === 'pageDown') {
      if (options.getRoute() === 'guide') {
        options.handleGuidePage?.(input === 'pageUp' ? -5 : 5);
      }
      return;
    }
    if (input === 'back') {
      if (options.getRoute() === 'channelSetup' && await options.handleChannelSetupBack()) return;
      if (options.getRoute() === 'player') {
        openExit();
        return;
      }
      navigate('player');
      return;
    }
    if (input === 'guide') {
      navigate(options.getRoute() === 'guide' ? 'player' : 'guide');
      return;
    }
    if (input === 'settings') {
      navigate('settings');
      return;
    }
    if (input === 'info') {
      options.openInfoRecovery();
      return;
    }
    if (input === 'fullscreen' && options.getRoute() === 'player') {
      await options.requestFullscreen(options.getFocusState().activeId ?? 'player-fullscreen');
    }
  };

  const hasProtectedBackOwner = (): boolean => {
    const shellState = options.getShellState();
    return shellState.bootstrap !== 'ready' ||
      shellState.blockingErrorMessage !== null ||
      shellState.inlineError !== null ||
      options.isProfileModalActive();
  };

  const handleBackPress = async (): Promise<void> => {
    if (cleanedUp) return;
    backPressProtected = hasProtectedBackOwner();
    await handleInput('back');
  };

  const handleBackHold = async (): Promise<void> => {
    const protectedOwner = backPressProtected || hasProtectedBackOwner();
    backPressProtected = false;
    if (cleanedUp || protectedOwner) return;

    if (options.getRoute() !== 'player') {
      const accepted = options.activateRoute('player');
      if (accepted === false || options.getRoute() !== 'player') return;
    }
    options.handlePlayerRouteLeave?.();
    if (options.getShellState().exitConfirmOpen) {
      cancelExit();
    }
    routeFocusMemory.delete('player');
    options.setFocusState({ activeRoute: 'player', activeId: null });
    options.render();
    options.dom.playerPresentationElement?.focus();
  };

  return {
    handleInput,
    handleBackPress,
    handleBackHold,
    cancelBackHold: (): void => {
      backPressProtected = false;
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
      routeFocusMemory.set(previousRoute, current.activeId);
    },
    cleanup(): void {
      cleanedUp = true;
      routeFocusMemory.clear();
      exitInvoker = null;
      backPressProtected = false;
      options.invalidateFullscreenRequest();
    },
  };
}
