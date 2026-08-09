import type {
  PlayerCommandName,
  PlayerEvent,
  PlayerSnapshot,
} from '../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { DesktopInputButton } from './navigation.js';

export interface PlayerInputCommandTimerHost {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(handle: number): void;
}

export interface PlayerInputCommandControllerOptions {
  player: Pick<LineupDesktopPreloadApi['player'], 'dispatch'>;
  host: PlayerInputCommandTimerHost;
  getSnapshot(): PlayerSnapshot;
  recordDiagnostic(operation: string, message: string): void;
}

export interface PlayerInputCommandController {
  handleInput(input: DesktopInputButton, blocked?: boolean): boolean;
  pauseCurrent(
    snapshotRequestId: string,
    onDeferredResolved?: (result: DeferredPauseResult) => void,
  ): PauseCurrentResult;
  cancelDeferredPause(): void;
  handlePlayerEvent(event: PlayerEvent): void;
  reconcileSnapshot(snapshot: PlayerSnapshot, authoritative: boolean): void;
  routeLeave(): void;
  cleanup(): void;
}

export type PauseCurrentResult = 'started' | 'deferred' | 'rejected';
export type DeferredPauseResult = Exclude<PauseCurrentResult, 'deferred'>;

interface PendingDirectCommand {
  requestId: string;
  command: PlayerCommandName;
  snapshotRequestId: string;
  settled: boolean;
}

interface DeferredPause {
  snapshotRequestId: string;
  resolve(result: DeferredPauseResult): void;
}

const COMMAND_TIMEOUT_MS = 30_000;
const PLAYER_COMMAND_FAILURE_MESSAGE = 'Player command failed.';

export function createPlayerInputCommandController(
  options: PlayerInputCommandControllerOptions,
): PlayerInputCommandController {
  let pending: PendingDirectCommand | null = null;
  let timer: number | null = null;
  let sequence = 0;
  let disposed = false;
  let deferredPause: DeferredPause | null = null;

  const release = (): PendingDirectCommand | null => {
    const released = pending;
    pending = null;
    if (timer !== null) {
      options.host.clearTimeout(timer);
      timer = null;
    }
    return released;
  };

  const resolveDeferredPause = (result: DeferredPauseResult): void => {
    const deferred = deferredPause;
    deferredPause = null;
    deferred?.resolve(result);
  };

  const fail = (requestId: string): void => {
    if (disposed || pending?.requestId !== requestId) return;
    const failed = release();
    if (failed !== null) {
      options.recordDiagnostic(
        `player.${failed.command}`,
        PLAYER_COMMAND_FAILURE_MESSAGE,
      );
    }
    resolveDeferredPause('rejected');
  };

  const settle = (event: Extract<PlayerEvent, { event: 'command.settled' }>): void => {
    if (
      pending?.requestId !== event.requestId ||
      pending.command !== event.command ||
      pending.settled
    ) return;
    if (event.ok && pending.command === 'play' && deferredPause !== null) {
      const snapshot = options.getSnapshot();
      if (
        snapshot.requestId !== pending.snapshotRequestId ||
        isInconsistentPlaybackPair(snapshot)
      ) {
        release();
        resolveDeferredPause('rejected');
        return;
      }
      if (snapshot.status !== 'playing' || !snapshot.playing) {
        pending.settled = true;
        return;
      }
    }
    const settled = release();
    if (!event.ok && settled !== null) {
      options.recordDiagnostic(
        `player.${settled.command}`,
        PLAYER_COMMAND_FAILURE_MESSAGE,
      );
    }
    if (
      settled !== null
      && event.ok
      && (settled.command === 'play' || settled.command === 'seek.relative')
      && deferredPause !== null
    ) {
      const deferred = deferredPause;
      deferredPause = null;
      const result = pauseCurrent(deferred.snapshotRequestId);
      deferred.resolve(result === 'started' ? 'started' : 'rejected');
      return;
    }
    resolveDeferredPause('rejected');
  };

  const dispatch = (
    command: PlayerCommandName,
    intent:
      | 'player.playIfCurrent'
      | 'player.pauseIfCurrent'
      | 'player.stopIfCurrent'
      | 'player.seekRelativeIfCurrent',
    snapshotRequestId: string,
    deltaMs?: number,
  ): void => {
    const requestId = `renderer-input-${command.replace('.', '-')}-${++sequence}`;
    pending = { requestId, command, snapshotRequestId, settled: false };
    timer = options.host.setTimeout(() => {
      timer = null;
      if (pending?.requestId === requestId && pending.settled) {
        release();
        resolveDeferredPause('rejected');
      } else {
        fail(requestId);
      }
    }, COMMAND_TIMEOUT_MS);
    const payload = deltaMs === undefined
      ? { snapshotRequestId }
      : { snapshotRequestId, deltaMs };
    void options.player.dispatch({ intent, requestId, payload }).then((result) => {
      if (disposed || pending?.requestId !== requestId) return;
      if (!result.ok || !result.value.accepted) {
        fail(requestId);
        return;
      }
      for (const event of result.value.events) {
        if (event.event === 'command.settled') settle(event);
      }
    }).catch(() => fail(requestId));
  };

  const handleInput = (input: DesktopInputButton, blocked = false): boolean => {
    if (disposed || !isDirectCommandInput(input)) return false;
    if (blocked || pending !== null) return true;
    const snapshot = options.getSnapshot();
    if (snapshot.requestId === null || snapshot.status === 'destroyed') return true;
    if (isInconsistentPlaybackPair(snapshot)) {
      options.recordDiagnostic('player.input', 'Inconsistent player state ignored.');
      return true;
    }

    if (input === 'mediaStop') {
      if (snapshot.status !== 'idle') {
        dispatch('stop', 'player.stopIfCurrent', snapshot.requestId);
      }
      return true;
    }
    if (input === 'mediaRewind' || input === 'mediaFastForward') {
      if (snapshot.status !== 'idle' && snapshot.seekSupport === 'supported') {
        dispatch(
          'seek.relative',
          'player.seekRelativeIfCurrent',
          snapshot.requestId,
          input === 'mediaRewind' ? -10_000 : 10_000,
        );
      }
      return true;
    }

    const requested = input === 'mediaPlay' ? 'play'
      : input === 'mediaPause' ? 'pause'
        : deriveToggle(snapshot);
    if (requested === 'play') {
      dispatch('play', 'player.playIfCurrent', snapshot.requestId);
    } else if (requested === 'pause') {
      dispatch('pause', 'player.pauseIfCurrent', snapshot.requestId);
    }
    return true;
  };

  const pauseCurrent = (
    snapshotRequestId: string,
    onDeferredResolved?: (result: DeferredPauseResult) => void,
  ): PauseCurrentResult => {
    if (disposed) return 'rejected';
    if (pending !== null) {
      if (
        deferredPause === null
        && onDeferredResolved !== undefined
        && (pending.command === 'play' || pending.command === 'seek.relative')
        && pending.snapshotRequestId === snapshotRequestId
      ) {
        deferredPause = { snapshotRequestId, resolve: onDeferredResolved };
        return 'deferred';
      }
      return 'rejected';
    }
    const snapshot = options.getSnapshot();
    if (
      snapshot.requestId === null ||
      snapshot.requestId !== snapshotRequestId ||
      snapshot.status !== 'playing' ||
      !snapshot.playing ||
      isInconsistentPlaybackPair(snapshot)
    ) return 'rejected';
    dispatch('pause', 'player.pauseIfCurrent', snapshot.requestId);
    return 'started';
  };

  return {
    handleInput,
    pauseCurrent,
    cancelDeferredPause() {
      resolveDeferredPause('rejected');
    },
    handlePlayerEvent(event) {
      if (event.event === 'command.settled') settle(event);
      else if (event.event === 'error' && event.requestId !== null && pending?.requestId === event.requestId) {
        fail(event.requestId);
      }
    },
    reconcileSnapshot(snapshot, authoritative) {
      if (!authoritative || pending === null) return;
      if (snapshot.requestId !== pending.snapshotRequestId) {
        release();
        resolveDeferredPause('rejected');
      } else if (isInconsistentPlaybackPair(snapshot)) {
        if (pending.settled) {
          release();
          resolveDeferredPause('rejected');
        } else {
          fail(pending.requestId);
        }
      } else if (pending.settled && snapshot.status === 'playing' && snapshot.playing) {
        const deferred = deferredPause;
        release();
        deferredPause = null;
        if (deferred !== null) {
          const result = pauseCurrent(deferred.snapshotRequestId);
          deferred.resolve(result === 'started' ? 'started' : 'rejected');
        }
      }
    },
    routeLeave() {
      release();
      resolveDeferredPause('rejected');
    },
    cleanup() {
      if (disposed) return;
      release();
      resolveDeferredPause('rejected');
      disposed = true;
    },
  };
}

function isDirectCommandInput(input: DesktopInputButton): boolean {
  return input === 'space' || input === 'mediaPlay' || input === 'mediaPause' ||
    input === 'mediaPlayPause' || input === 'mediaRewind' ||
    input === 'mediaFastForward' || input === 'mediaStop';
}

function deriveToggle(snapshot: PlayerSnapshot): 'play' | 'pause' | null {
  if (snapshot.status === 'playing' && snapshot.playing) return 'pause';
  if ((snapshot.status === 'ready' || snapshot.status === 'paused') && !snapshot.playing) return 'play';
  return null;
}

function isInconsistentPlaybackPair(snapshot: PlayerSnapshot): boolean {
  return (snapshot.status === 'playing' && !snapshot.playing) ||
    ((snapshot.status === 'ready' || snapshot.status === 'paused') && snapshot.playing);
}
