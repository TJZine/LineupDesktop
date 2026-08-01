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
  handlePlayerEvent(event: PlayerEvent): void;
  reconcileSnapshot(snapshot: PlayerSnapshot, authoritative: boolean): void;
  routeLeave(): void;
  cleanup(): void;
}

interface PendingDirectCommand {
  requestId: string;
  command: PlayerCommandName;
  snapshotRequestId: string;
}

const COMMAND_TIMEOUT_MS = 30_000;

export function createPlayerInputCommandController(
  options: PlayerInputCommandControllerOptions,
): PlayerInputCommandController {
  let pending: PendingDirectCommand | null = null;
  let timer: number | null = null;
  let sequence = 0;
  let disposed = false;

  const release = (): PendingDirectCommand | null => {
    const released = pending;
    pending = null;
    if (timer !== null) {
      options.host.clearTimeout(timer);
      timer = null;
    }
    return released;
  };

  const fail = (requestId: string, message: string): void => {
    if (disposed || pending?.requestId !== requestId) return;
    const failed = release();
    if (failed !== null) {
      options.recordDiagnostic(`player.${failed.command}`, safeMessage(message));
    }
  };

  const settle = (event: Extract<PlayerEvent, { event: 'command.settled' }>): void => {
    if (pending?.requestId !== event.requestId || pending.command !== event.command) return;
    if (!event.ok) {
      fail(event.requestId, event.error?.message ?? 'Player command failed.');
      return;
    }
    release();
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
    pending = { requestId, command, snapshotRequestId };
    timer = options.host.setTimeout(() => {
      timer = null;
      fail(requestId, 'Player command timed out.');
    }, COMMAND_TIMEOUT_MS);
    const payload = deltaMs === undefined
      ? { snapshotRequestId }
      : { snapshotRequestId, deltaMs };
    void options.player.dispatch({ intent, requestId, payload }).then((result) => {
      if (disposed || pending?.requestId !== requestId) return;
      if (!result.ok || !result.value.accepted) {
        fail(requestId, result.ok ? 'Player command was not accepted.' : result.error.message);
        return;
      }
      for (const event of result.value.events) {
        if (event.event === 'command.settled') settle(event);
      }
    }).catch(() => fail(requestId, 'Player command failed.'));
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

  return {
    handleInput,
    handlePlayerEvent(event) {
      if (event.event === 'command.settled') settle(event);
      else if (event.event === 'error' && event.requestId !== null && pending?.requestId === event.requestId) {
        fail(event.requestId, event.error.message);
      }
    },
    reconcileSnapshot(snapshot, authoritative) {
      if (!authoritative || pending === null) return;
      if (snapshot.requestId !== pending.snapshotRequestId) {
        release();
      } else if (isInconsistentPlaybackPair(snapshot)) {
        fail(pending.requestId, 'Inconsistent player state ignored.');
      }
    },
    routeLeave() {
      release();
    },
    cleanup() {
      if (disposed) return;
      release();
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

function safeMessage(message: string): string {
  const compact = message.replace(/\p{Cc}/gu, ' ').replace(/\s+/gu, ' ').trim();
  if (compact.length === 0 || /(?:https?:\/\/|token|credential|secret|header|\\\\|\/Users\/|[A-Za-z]:\\)/iu.test(compact)) {
    return 'Player command failed.';
  }
  return compact.slice(0, 180);
}
