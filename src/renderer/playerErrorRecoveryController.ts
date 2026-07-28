import type { PlayerSnapshot } from '../contracts/player.js';
import type {
  LineupDesktopPreloadApi,
  PlayerRecoveryAction,
} from '../contracts/shell.js';
import type { PlayerOverlayState } from './overlays.js';

export interface PlayerErrorRecoveryTimerHost {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(handle: number): void;
}

export interface PlayerErrorRecoveryControllerOptions {
  bridge: Pick<LineupDesktopPreloadApi['player'], 'recover'>;
  host: PlayerErrorRecoveryTimerHost;
  getState(): PlayerOverlayState;
  setState(state: PlayerOverlayState): void;
  acceptSnapshot(snapshot: PlayerSnapshot): void;
  render(): void;
  focus(focusId: string | null): void;
}

export interface PlayerErrorRecoveryController {
  retry(): boolean;
  skip(): boolean;
  reconcileSnapshot(snapshot: PlayerSnapshot): void;
  invalidate(): void;
  dispose(): void;
}

const RECOVERY_TIMEOUT_MS = 5_000;

export function createPlayerErrorRecoveryController(
  options: PlayerErrorRecoveryControllerOptions,
): PlayerErrorRecoveryController {
  let generation = 0;
  let timeoutHandle: number | null = null;
  let disposed = false;
  let lastErrorRequestId: string | null = null;

  const clearTimeout = (): void => {
    if (timeoutHandle !== null) {
      options.host.clearTimeout(timeoutHandle);
      timeoutHandle = null;
    }
  };

  const update = (
    transform: (state: PlayerOverlayState) => PlayerOverlayState,
  ): void => {
    options.setState(transform(options.getState()));
    options.render();
  };

  const closeActionGeneration = (actionGeneration: number): boolean => {
    if (disposed || generation !== actionGeneration) {
      return false;
    }
    generation = nextGeneration(generation);
    clearTimeout();
    return true;
  };

  const invalidate = (): void => {
    generation = nextGeneration(generation);
    clearTimeout();
    update((state) => ({
      ...state,
      retryPending: false,
      recoveryPendingAction: null,
      retryTransitionActive: false,
    }));
  };

  const fail = (
    action: PlayerRecoveryAction,
    actionGeneration: number,
    message: string,
  ): void => {
    if (!closeActionGeneration(actionGeneration)) {
      return;
    }
    update((state) => ({
      ...state,
      retryPending: false,
      recoveryPendingAction: null,
      retryTransitionActive: false,
      retryError: safeMessage(message),
    }));
    options.focus(
      action === 'retry-current'
        ? 'overlay-player-retry'
        : 'overlay-player-skip',
    );
  };

  const run = (action: PlayerRecoveryAction): boolean => {
    if (
      disposed ||
      options.getState().recoveryPendingAction !== null
    ) {
      return false;
    }
    const actionGeneration = nextGeneration(generation);
    generation = actionGeneration;
    update((state) => ({
      ...state,
      retryPending: true,
      recoveryPendingAction: action,
      retryTransitionActive: false,
      retryError: null,
    }));
    timeoutHandle = options.host.setTimeout(() => {
      timeoutHandle = null;
      fail(action, actionGeneration, 'Player recovery timed out.');
    }, RECOVERY_TIMEOUT_MS);
    void options.bridge.recover({ action })
      .then((result) => {
        if (!result.ok) {
          fail(action, actionGeneration, result.error.message);
          return;
        }
        if (!closeActionGeneration(actionGeneration)) {
          return;
        }
        options.setState({
          ...options.getState(),
          retryPending: false,
          recoveryPendingAction: null,
          retryTransitionActive: true,
          retryError: null,
        });
        options.acceptSnapshot(result.value.snapshot);
        options.render();
        options.focus(null);
      })
      .catch(() => {
        fail(action, actionGeneration, 'Player recovery failed.');
      });
    return true;
  };

  return {
    retry: () => run('retry-current'),
    skip: () => run('skip-next'),
    reconcileSnapshot(snapshot) {
      const nextErrorRequestId =
        snapshot.status === 'error' || snapshot.status === 'destroyed'
          ? snapshot.requestId
          : null;
      if (
        lastErrorRequestId !== null &&
        nextErrorRequestId !== lastErrorRequestId
      ) {
        invalidate();
      }
      lastErrorRequestId = nextErrorRequestId;
      if (nextErrorRequestId === null && options.getState().retryTransitionActive) {
        update((state) => ({
          ...state,
          retryTransitionActive: false,
          retryError: null,
        }));
      }
    },
    invalidate,
    dispose() {
      if (disposed) {
        return;
      }
      invalidate();
      disposed = true;
    },
  };
}

function safeMessage(message: string): string {
  const compact = message
    .replace(/\p{Cc}/gu, ' ')
    .replace(/\s+/gu, ' ')
    .trim();
  if (
    compact.length === 0 ||
    /(?:https?:\/\/|token|credential|secret|header|\\\\|\/Users\/|[A-Za-z]:\\)/iu.test(
      compact,
    )
  ) {
    return 'Player recovery failed.';
  }
  return compact.slice(0, 180);
}

function nextGeneration(current: number): number {
  return current >= Number.MAX_SAFE_INTEGER ? 1 : current + 1;
}
