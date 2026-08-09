import type { PlayerCommandName, PlayerEvent, PlayerSnapshot } from '../contracts/player.js';
import type { DesktopSettingsValues } from '../contracts/settings.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { DesktopInputButton } from './navigation.js';
import {
  appendChannelDigit,
  closeAllPlayerOverlays,
  closeTopOverlay,
  moveMiniGuide,
  openMiniGuide,
  openNowPlaying,
  openOsd,
  openPlaybackOptions,
  reconcileSnapshotState,
  type PlayerOverlayState,
} from './overlays.js';
import {
  availableTracks,
  firstEligibleOsdFocusId,
  isAudioControlEligible,
  isSubtitleControlEligible,
  type PlayerOverlayPresentationSource,
} from './playerOverlayPresentation.js';
import type { PlayerErrorRecoveryController } from './playerErrorRecoveryController.js';
import { createPlayerOverlayView } from './overlayViewModels.js';

export interface PlayerOverlayTimerHost {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(handle: number): void;
}

export interface PlayerOverlayControllerOptions {
  player: Pick<LineupDesktopPreloadApi['player'], 'dispatch' | 'tuneChannel'>;
  host: PlayerOverlayTimerHost;
  getState(): PlayerOverlayState;
  setState(state: PlayerOverlayState): void;
  getPresentation(): PlayerOverlayPresentationSource;
  render(): void;
  focus(focusId: string | null): void;
  openGuide(invokerFocusId: string | null): void;
  refreshChannelStatus(): Promise<void>;
  refreshGuidePresentation(): Promise<void>;
  recordDiagnostic(operation: string, message: string): void;
  recovery: PlayerErrorRecoveryController;
  nowPlayingAutoHideMs: DesktopSettingsValues['nowPlayingAutoHideMs'];
}

export interface PlayerOverlayController {
  handleInput(input: DesktopInputButton, shellBlocked?: boolean): boolean;
  requestOsd(): boolean;
  requestNowPlaying(shellBlocked?: boolean): boolean;
  requestMiniGuide(): boolean;
  activateMiniGuideChannel(channelId: string): boolean;
  retry(): boolean;
  skip(): boolean;
  openOptions(family: 'audio' | 'subtitle'): boolean;
  selectTrack(family: 'audio' | 'subtitle', trackId: string | null, focusId: string): Promise<void>;
  tune(channelId: string, invoker: 'miniGuide' | 'number' | 'page'): Promise<void>;
  handlePlayerEvent(event: PlayerEvent): void;
  reconcileSnapshot(snapshot: PlayerSnapshot, authoritative: boolean, explicitTrackList?: boolean): void;
  closeTop(): boolean;
  routeLeave(): void;
  setNowPlayingAutoHideMs(value: DesktopSettingsValues['nowPlayingAutoHideMs']): void;
  dispose(): void;
}

interface PendingCommand {
  requestId: string;
  command: PlayerCommandName;
  snapshotRequestId: string | null;
  focusId: string | null;
  trackId: string | null;
  family: 'audio' | 'subtitle' | null;
}

const OSD_TIMEOUT_MS = 3_000;
const MINI_GUIDE_TIMEOUT_MS = 8_000;
const NUMBER_COMMIT_MS = 2_000;
const NUMBER_RESULT_MS = 2_000;
const NUMBER_COMPLETE_MS = 650;
const TRANSITION_DELAY_MS = 175;
const PLAYER_BRIDGE_REQUEST_TIMEOUT_MS = 30_000;
const CHANNEL_TUNE_FAILURE_MESSAGE = 'Channel tune failed.';
const TRACK_SELECTION_FAILURE_MESSAGE = 'Track selection failed.';
const PLAYER_WARNING_MESSAGE = 'Player warning.';
const PLAYER_ERROR_MESSAGE = 'Player error.';
class PlayerBridgeRequestTimeoutError extends Error {
  constructor() {
    super('Player bridge request timed out.');
    this.name = 'PlayerBridgeRequestTimeoutError';
  }
}

class PlayerBridgeRequestCanceledError extends Error {
  constructor() {
    super('Player bridge request was canceled.');
    this.name = 'PlayerBridgeRequestCanceledError';
  }
}

export function createPlayerOverlayController(
  options: PlayerOverlayControllerOptions,
): PlayerOverlayController {
  let disposed = false;
  let sequence = 0;
  let tuneGeneration = 0;
  let pendingCommand: PendingCommand | null = null;
  let pendingCommandTimer: number | null = null;
  let bridgeRequestSequence = 0;
  const activeBridgeRequests = new Map<
    number,
    Readonly<{
      ownerKey: string;
      reject(error: Error): void;
    }>
  >();
  let osdTimer: number | null = null;
  let miniGuideTimer: number | null = null;
  let nowPlayingTimer: number | null = null;
  let numberTimer: number | null = null;
  let transitionTimer: number | null = null;
  let lastSnapshotRequestId = options.getPresentation().playerSnapshot.requestId;
  let lastAuthoritativeStatus = options.getPresentation().playerSnapshot.status;
  let nowPlayingAutoHideMs = options.nowPlayingAutoHideMs;

  const update = (transform: (state: PlayerOverlayState) => PlayerOverlayState): void => {
    if (disposed) return;
    options.setState(transform(options.getState()));
    options.render();
  };

  const clearTimer = (timer: number | null): null => {
    if (timer !== null) options.host.clearTimeout(timer);
    return null;
  };

  const clearTransientTimers = (): void => {
    osdTimer = clearTimer(osdTimer);
    miniGuideTimer = clearTimer(miniGuideTimer);
    nowPlayingTimer = clearTimer(nowPlayingTimer);
    numberTimer = clearTimer(numberTimer);
  };

  const clearOverlayTimers = (): void => {
    clearTransientTimers();
    transitionTimer = clearTimer(transitionTimer);
  };

  const withBridgeRequestTimeout = <T>(
    ownerKey: string,
    request: Promise<T>,
  ): Promise<T> =>
    new Promise<T>((resolve, reject) => {
      const bridgeRequestId = ++bridgeRequestSequence;
      let settled = false;
      const timeout = options.host.setTimeout(() => {
        if (settled) return;
        settled = true;
        activeBridgeRequests.delete(bridgeRequestId);
        reject(new PlayerBridgeRequestTimeoutError());
      }, PLAYER_BRIDGE_REQUEST_TIMEOUT_MS);
      const settle = (): boolean => {
        if (settled) return false;
        settled = true;
        options.host.clearTimeout(timeout);
        activeBridgeRequests.delete(bridgeRequestId);
        return true;
      };
      activeBridgeRequests.set(bridgeRequestId, {
        ownerKey,
        reject: (error) => {
          if (!settle()) return;
          reject(error);
        },
      });
      request.then(
        (value) => {
          if (!settle()) return;
          resolve(value);
        },
        (error: unknown) => {
          if (!settle()) return;
          reject(error);
        },
      );
    });

  const cancelBridgeRequests = (ownerKey?: string): void => {
    for (const request of [...activeBridgeRequests.values()]) {
      if (ownerKey !== undefined && request.ownerKey !== ownerKey) continue;
      request.reject(new PlayerBridgeRequestCanceledError());
    }
  };

  const releasePendingCommand = (): PendingCommand | null => {
    const released = pendingCommand;
    pendingCommand = null;
    pendingCommandTimer = clearTimer(pendingCommandTimer);
    if (released !== null) {
      cancelBridgeRequests(`command:${released.requestId}`);
    }
    return released;
  };

  const armPendingCommandTimer = (requestId: string): void => {
    pendingCommandTimer = clearTimer(pendingCommandTimer);
    pendingCommandTimer = options.host.setTimeout(() => {
      pendingCommandTimer = null;
      const pending = pendingCommand;
      if (pending?.requestId !== requestId) return;
      failPendingCommand(requestId);
    }, PLAYER_BRIDGE_REQUEST_TIMEOUT_MS);
  };

  const focusActive = (): void => {
    options.focus(
      createPlayerOverlayView(
        options.getState(),
        options.getPresentation(),
      ).activeFocusId,
    );
  };

  const armOsdTimer = (): void => {
    osdTimer = clearTimer(osdTimer);
    if (options.getPresentation().playerSnapshot.status !== 'playing') return;
    osdTimer = options.host.setTimeout(() => {
      osdTimer = null;
      if (options.getState().activeOverlayId === 'playerOsd') {
        update(closeTopOverlay);
        options.focus(null);
      }
    }, OSD_TIMEOUT_MS);
  };

  const armMiniGuideTimer = (): void => {
    miniGuideTimer = clearTimer(miniGuideTimer);
    miniGuideTimer = options.host.setTimeout(() => {
      miniGuideTimer = null;
      if (options.getState().activeOverlayId === 'miniGuide') {
        update(closeTopOverlay);
        options.focus(null);
      }
    }, MINI_GUIDE_TIMEOUT_MS);
  };

  const armNowPlayingTimer = (): void => {
    nowPlayingTimer = clearTimer(nowPlayingTimer);
    if (nowPlayingAutoHideMs === 0) return;
    nowPlayingTimer = options.host.setTimeout(() => {
      nowPlayingTimer = null;
      if (options.getState().activeOverlayId === 'nowPlaying') {
        update(closeTopOverlay);
        options.focus(null);
      }
    }, nowPlayingAutoHideMs);
  };

  const requestOsd = (): boolean => {
    const before = options.getState();
    const next = openOsd(before, options.getPresentation().playerSnapshot);
    options.setState(next);
    options.render();
    if (next.activeOverlayId === 'playerOsd') {
      armOsdTimer();
      focusActive();
    }
    return true;
  };

  const requestNowPlaying = (shellBlocked = false): boolean => {
    const presentation = options.getPresentation();
    if (presentation.playerSnapshot.status === 'error' || presentation.playerSnapshot.status === 'destroyed') {
      return true;
    }
    const current = presentation.channels.find((channel) => channel.id === presentation.currentChannelId);
    const before = options.getState();
    const next = openNowPlaying(before, current?.currentProgram !== undefined, shellBlocked);
    if (next === before) return true;
    clearTransientTimers();
    options.setState(next);
    options.render();
    options.focus(null);
    armNowPlayingTimer();
    return true;
  };

  const requestMiniGuide = (): boolean => {
    const status = options.getPresentation().playerSnapshot.status;
    if (status === 'error' || status === 'destroyed') return true;
    const before = options.getState();
    const next = openMiniGuide(before, options.getPresentation());
    if (next === before) return true;
    clearTransientTimers();
    options.setState(next);
    options.render();
    armMiniGuideTimer();
    focusActive();
    return true;
  };

  const activateMiniGuideChannel = (channelId: string): boolean => {
    if (!options.getPresentation().channels.some((channel) => channel.id === channelId)) return false;
    update((state) => ({ ...state, miniGuideSelectedChannelId: channelId, miniGuideError: null }));
    focusActive();
    armMiniGuideTimer();
    void tune(channelId, 'miniGuide');
    return true;
  };

  const retry = (): boolean => {
    return options.recovery.retry();
  };

  const openOptions = (family: 'audio' | 'subtitle'): boolean => {
    const before = options.getState();
    const next = openPlaybackOptions(before, options.getPresentation().playerSnapshot, family);
    if (next === before) return true;
    osdTimer = clearTimer(osdTimer);
    options.setState(next);
    options.render();
    focusActive();
    return true;
  };

  const armNumberCommit = (): void => {
    numberTimer = clearTimer(numberTimer);
    if (options.getState().channelNumberBuffer.length === 3) {
      void commitNumber();
      return;
    }
    numberTimer = options.host.setTimeout(() => {
      numberTimer = null;
      void commitNumber();
    }, NUMBER_COMMIT_MS);
  };

  const commitNumber = async (): Promise<void> => {
    const state = options.getState();
    if (state.activeOverlayId !== 'channelNumber' || state.channelNumberStatus !== 'editing') return;
    const channel = options.getPresentation().channels.find(
      (candidate) => candidate.number === state.channelNumberBuffer,
    );
    if (channel === undefined) {
      update((current) => ({
        ...current,
        channelNumberStatus: 'error',
        channelNumberMessage: 'Channel unavailable.',
      }));
      numberTimer = options.host.setTimeout(closeNumber, NUMBER_RESULT_MS);
      return;
    }
    await tune(channel.id, 'number');
  };

  const closeNumber = (): void => {
    numberTimer = null;
    update((state) => ({
      ...state,
      activeOverlayId: state.activeOverlayId === 'channelNumber' ? null : state.activeOverlayId,
      channelNumberBuffer: '',
      channelNumberStatus: null,
      channelNumberMessage: null,
    }));
    options.focus(null);
  };

  const selectTrack = async (
    family: 'audio' | 'subtitle',
    trackId: string | null,
    focusId: string,
  ): Promise<void> => {
    if (disposed || pendingCommand !== null) return;
    const snapshot = options.getPresentation().playerSnapshot;
    if (snapshot.requestId === null || !trackMembership(snapshot, family, trackId)) {
      setOptionsFailure(focusId, 'Track is no longer available.');
      return;
    }
    const requestId = `renderer-select-${family}-${++sequence}`;
    const command = family === 'audio' ? 'track.audio.select' : 'track.subtitle.select';
    pendingCommand = { requestId, command, snapshotRequestId: snapshot.requestId, focusId, trackId, family };
    armPendingCommandTimer(requestId);
    update((state) => ({ ...state, pendingTrackFocusId: focusId, playbackOptionsError: null }));
    try {
      const result = await withBridgeRequestTimeout(
        `command:${requestId}`,
        options.player.dispatch({
          intent: family === 'audio' ? 'player.selectAudio' : 'player.selectSubtitle',
          requestId,
          payload: { trackId, snapshotRequestId: snapshot.requestId },
        }),
      );
      if (disposed || pendingCommand?.requestId !== requestId) return;
      if (!result.ok || !result.value.accepted) {
        failPendingCommand(requestId);
      } else {
        for (const event of result.value.events) if (event.event === 'command.settled') settleCommand(event);
      }
    } catch {
      failPendingCommand(requestId);
    }
  };

  const tune = async (
    channelId: string,
    invoker: 'miniGuide' | 'number' | 'page',
  ): Promise<void> => {
    if (disposed || !options.getPresentation().channels.some((channel) => channel.id === channelId)) return;
    const state = options.getState();
    if (state.pendingTuneChannelId === channelId || state.transitionChannelId === channelId) return;
    const generation = ++tuneGeneration;
    cancelBridgeRequests('tune');
    if (invoker === 'miniGuide') miniGuideTimer = clearTimer(miniGuideTimer);
    transitionTimer = clearTimer(transitionTimer);
    if (invoker === 'number') numberTimer = clearTimer(numberTimer);
    update((current) => ({
      ...current,
      pendingTuneChannelId: channelId,
      transitionChannelId: channelId,
      transitionVisible: false,
      channelNumberStatus: invoker === 'number' ? 'pending' : current.channelNumberStatus,
      channelNumberMessage: null,
      playbackOptionsError: null,
      miniGuideError: invoker === 'miniGuide' ? null : current.miniGuideError,
    }));
    transitionTimer = options.host.setTimeout(() => {
      transitionTimer = null;
      if (generation === tuneGeneration && !disposed) update((current) => ({ ...current, transitionVisible: true }));
    }, TRANSITION_DELAY_MS);
    try {
      const result = await withBridgeRequestTimeout(
        'tune',
        options.player.tuneChannel({ channelId }),
      );
      if (disposed || generation !== tuneGeneration) return;
      if (!result.ok) {
        failTune(generation, invoker);
        return;
      }
      if (generation !== tuneGeneration || disposed) return;
      let invokerOwnedAtSettlement = false;
      update((current) => {
        const invokerOverlay = invoker === 'miniGuide' ? 'miniGuide' : invoker === 'number' ? 'channelNumber' : null;
        invokerOwnedAtSettlement = invokerOverlay !== null && current.activeOverlayId === invokerOverlay;
        return {
          ...current,
          activeOverlayId: invoker === 'miniGuide' && invokerOwnedAtSettlement
            ? null
            : current.activeOverlayId,
          pendingTuneChannelId: null,
          lastTuneChannelId: channelId,
          channelNumberStatus: invoker === 'number' && invokerOwnedAtSettlement ? 'completed' : current.channelNumberStatus,
          channelNumberMessage: invoker === 'number' && invokerOwnedAtSettlement ? 'Tuned' : current.channelNumberMessage,
        };
      });
      if (invoker === 'number' && invokerOwnedAtSettlement) {
        numberTimer = options.host.setTimeout(closeNumber, NUMBER_COMPLETE_MS);
      } else if (invoker === 'miniGuide' && invokerOwnedAtSettlement) {
        options.focus(null);
      }
      await options.refreshChannelStatus().catch(() => undefined);
      if (generation !== tuneGeneration || disposed) return;
      await options.refreshGuidePresentation().catch(() => undefined);
      if (generation !== tuneGeneration || disposed) return;
    } catch {
      if (generation === tuneGeneration && !disposed) {
        failTune(generation, invoker);
      }
    }
  };

  const failTune = (
    generation: number,
    invoker: 'miniGuide' | 'number' | 'page',
  ): void => {
    if (generation !== tuneGeneration || disposed) return;
    transitionTimer = clearTimer(transitionTimer);
    let invokerOwnedAtSettlement = false;
    update((state) => {
      const invokerOverlay = invoker === 'miniGuide' ? 'miniGuide' : invoker === 'number' ? 'channelNumber' : null;
      invokerOwnedAtSettlement = invokerOverlay !== null && state.activeOverlayId === invokerOverlay;
      return {
        ...state,
        pendingTuneChannelId: null,
        transitionChannelId: null,
        transitionVisible: false,
        miniGuideError: invoker === 'miniGuide' && invokerOwnedAtSettlement
          ? CHANNEL_TUNE_FAILURE_MESSAGE
          : state.miniGuideError,
        channelNumberStatus: invoker === 'number' && invokerOwnedAtSettlement ? 'error' : state.channelNumberStatus,
        channelNumberMessage: invoker === 'number' && invokerOwnedAtSettlement
          ? CHANNEL_TUNE_FAILURE_MESSAGE
          : state.channelNumberMessage,
      };
    });
    if (invoker === 'miniGuide' && invokerOwnedAtSettlement) focusActive();
    if (invoker === 'number' && invokerOwnedAtSettlement) numberTimer = options.host.setTimeout(closeNumber, NUMBER_RESULT_MS);
    if (invoker === 'page') {
      options.recordDiagnostic('player.page-tune', CHANNEL_TUNE_FAILURE_MESSAGE);
    }
  };

  const tuneAdjacentChannel = (offset: -1 | 1): boolean => {
    const state = options.getState();
    if (state.activeOverlayId !== null || state.pendingTuneChannelId !== null) return true;
    const presentation = options.getPresentation();
    if (presentation.currentChannelId === null || presentation.channels.length === 0) return true;
    const currentIndex = presentation.channels.findIndex(
      (channel) => channel.id === presentation.currentChannelId,
    );
    if (currentIndex < 0) return true;
    const nextIndex = (currentIndex + offset + presentation.channels.length) % presentation.channels.length;
    const nextChannel = presentation.channels[nextIndex];
    if (nextChannel !== undefined && nextChannel.id !== presentation.currentChannelId) {
      void tune(nextChannel.id, 'page');
    }
    return true;
  };

  const settleCommand = (event: Extract<PlayerEvent, { event: 'command.settled' }>): void => {
    if (pendingCommand?.requestId !== event.requestId || pendingCommand.command !== event.command) return;
    if (!event.ok) {
      failPendingCommand(event.requestId);
      return;
    }
    const completed = releasePendingCommand();
    if (completed === null) return;
    closeOptionsWithFallback(completed);
  };

  const failPendingCommand = (requestId: string): void => {
    if (disposed || pendingCommand?.requestId !== requestId) return;
    const pending = releasePendingCommand();
    if (pending === null) return;
    setOptionsFailure(pending.focusId, TRACK_SELECTION_FAILURE_MESSAGE);
  };

  const setOptionsFailure = (focusId: string | null, message: string): void => {
    update((state) => ({
      ...state,
      activeOverlayId: 'playbackOptions',
      pendingTrackFocusId: null,
      playbackOptionsFocusId: focusId ?? state.playbackOptionsFocusId,
      playbackOptionsError: message,
    }));
    options.focus(focusId);
  };

  const closeOptionsWithFallback = (completed?: PendingCommand, restoreOsd = true): void => {
    const state = options.getState();
    const snapshot = options.getPresentation().playerSnapshot;
    const invoker = state.playbackOptionsInvoker ?? completed?.family;
    const exactEligible = invoker === 'audio'
      ? isAudioControlEligible(snapshot)
      : invoker === 'subtitle' && isSubtitleControlEligible(snapshot);
    const statusEligible = ['ready', 'playing', 'paused', 'seeking'].includes(snapshot.status);
    const fallback = !restoreOsd || !statusEligible ? null : exactEligible
      ? `overlay-osd-${invoker}`
      : firstEligibleOsdFocusId(snapshot);
    update((current) => ({
      ...current,
      activeOverlayId: fallback === null ? null : 'playerOsd',
      playbackOptionsFamily: null,
      playbackOptionsInvoker: null,
      playbackOptionsFocusId: null,
      playbackOptionsError: null,
      pendingTrackFocusId: null,
    }));
    if (fallback === null) options.focus(null);
    else options.focus(fallback);
    if (fallback !== null) armOsdTimer();
  };

  const reconcileSnapshot = (snapshot: PlayerSnapshot, authoritative: boolean, explicitTrackList = false): void => {
    if (disposed) return;
    const recoveryWasActive = isRecoveryActive(options.getState());
    const recoveryAlreadyInvalidated = options.recovery.reconcileSnapshot(snapshot);
    const previousAuthoritativeStatus = lastAuthoritativeStatus;
    if (authoritative) lastAuthoritativeStatus = snapshot.status;
    const previousRequest = lastSnapshotRequestId;
    lastSnapshotRequestId = snapshot.requestId;
    if (pendingCommand !== null && previousRequest !== snapshot.requestId) {
      const invalidated = releasePendingCommand();
      if (invalidated !== null) closeOptionsWithFallback(invalidated, false);
    }
    const ambiguousAuthoritativeLoad = authoritative && !explicitTrackList &&
      ['loading', 'buffering', 'stalled', 'seeking'].includes(snapshot.status);
    if (pendingCommand !== null && !ambiguousAuthoritativeLoad &&
      !trackMembership(snapshot, pendingCommand.family, pendingCommand.trackId)) {
      const invalidated = releasePendingCommand();
      if (invalidated !== null) {
        const familyEligible = invalidated.family === 'audio'
          ? isAudioControlEligible(snapshot)
          : invalidated.family === 'subtitle' && isSubtitleControlEligible(snapshot);
        if (familyEligible) {
          setOptionsFailure(firstOptionFocus(snapshot, invalidated.family), 'Track is no longer available.');
        } else {
          closeOptionsWithFallback(invalidated);
        }
        if (invalidated.focusId !== null) {
          options.recordDiagnostic(
            'player.track.membership',
            'Pending track was removed.',
          );
        }
      }
    }
    if ((authoritative || snapshot.status === 'ended') && options.getState().transitionChannelId !== null) {
      if (['idle', 'ready', 'playing', 'paused', 'ended', 'error', 'destroyed'].includes(snapshot.status)) {
        transitionTimer = clearTimer(transitionTimer);
        if (recoveryWasActive && !recoveryAlreadyInvalidated) {
          options.recovery.invalidate();
        }
        update((state) => ({ ...state, transitionChannelId: null, transitionVisible: false, pendingTuneChannelId: null, retryPending: false, retryTransitionActive: false }));
      }
    }
    if (authoritative && (snapshot.status === 'error' || snapshot.status === 'destroyed')) {
      clearOverlayTimers();
      releasePendingCommand();
      ++tuneGeneration;
      cancelBridgeRequests('tune');
      update((state) => reconcileSnapshotState(state, snapshot));
      focusActive();
      return;
    }
    if (authoritative || snapshot.status === 'ended') update((state) => reconcileSnapshotState(state, snapshot));
    if (authoritative && previousAuthoritativeStatus !== 'playing' && snapshot.status === 'playing' &&
      options.getState().activeOverlayId === 'playerOsd') armOsdTimer();
  };

  const closeTop = (): boolean => {
    const state = options.getState();
    if (state.activeOverlayId === null) return false;
    const wasOptions = state.activeOverlayId === 'playbackOptions';
    if (pendingCommand !== null) releasePendingCommand();
    if (state.activeOverlayId === 'miniGuide') miniGuideTimer = clearTimer(miniGuideTimer);
    if (state.activeOverlayId === 'playerOsd') osdTimer = clearTimer(osdTimer);
    if (state.activeOverlayId === 'nowPlaying') nowPlayingTimer = clearTimer(nowPlayingTimer);
    if (state.activeOverlayId === 'channelNumber') numberTimer = clearTimer(numberTimer);
    options.setState(closeTopOverlay(state));
    options.render();
    if (wasOptions) closeOptionsWithFallback();
    else options.focus(null);
    return true;
  };

  const routeLeave = (): void => {
    clearOverlayTimers();
    ++tuneGeneration;
    releasePendingCommand();
    cancelBridgeRequests();
    options.recovery.invalidate();
    options.setState(closeAllPlayerOverlays(options.getState()));
    options.render();
  };

  const handleInput = (input: DesktopInputButton, shellBlocked = false): boolean => {
    if (disposed) return false;
    const state = options.getState();
    if (input === 'nowPlaying') return requestNowPlaying(shellBlocked);
    if (input.startsWith('digit')) {
      if (state.activeOverlayId === 'playbackOptions' || ['loading', 'buffering', 'seeking', 'stalled', 'error', 'destroyed'].includes(options.getPresentation().playerSnapshot.status)) return true;
      if (state.channelNumberStatus === 'pending' || state.channelNumberStatus === 'completed' || state.channelNumberStatus === 'error') return true;
      osdTimer = clearTimer(osdTimer);
      miniGuideTimer = clearTimer(miniGuideTimer);
      const digit = input.slice('digit'.length);
      update((current) => appendChannelDigit(current, digit));
      armNumberCommit();
      options.focus(null);
      return true;
    }
    if (state.activeOverlayId === 'miniGuide') {
      if (input === 'up' || input === 'down' || input === 'pageUp' || input === 'pageDown') {
        const offset = input === 'up' ? -1 : input === 'down' ? 1 : input === 'pageUp' ? -5 : 5;
        update((current) => moveMiniGuide(current, options.getPresentation(), offset));
        armMiniGuideTimer();
        focusActive();
        return true;
      }
      if (input === 'right') {
        routeLeave();
        options.openGuide(null);
        return true;
      }
      if (input === 'left') return true;
      if (input === 'ok' && state.miniGuideSelectedChannelId !== null) {
        return activateMiniGuideChannel(state.miniGuideSelectedChannelId);
      }
    }
    if (input === 'pageUp' || input === 'pageDown') {
      return tuneAdjacentChannel(input === 'pageUp' ? -1 : 1);
    }
    if (input === 'up' && state.activeOverlayId === null) return requestMiniGuide();
    if (input === 'ok' && state.activeOverlayId === null &&
      ['error', 'destroyed'].includes(options.getPresentation().playerSnapshot.status)) return false;
    if ((input === 'down' || input === 'ok') && state.activeOverlayId === null) return requestOsd();
    if (input === 'back') return closeTop();
    return false;
  };

  return {
    handleInput,
    requestOsd,
    requestNowPlaying,
    requestMiniGuide,
    activateMiniGuideChannel,
    retry,
    skip: options.recovery.skip,
    openOptions,
    selectTrack,
    tune,
    handlePlayerEvent(event) {
      if (event.event === 'command.settled') settleCommand(event);
      else if (event.event === 'error' && event.requestId !== null && pendingCommand?.requestId === event.requestId) {
        failPendingCommand(event.requestId);
      } else if (event.event === 'warning' || event.event === 'error') {
        options.recordDiagnostic(
          `player.${event.event}`,
          event.event === 'warning' ? PLAYER_WARNING_MESSAGE : PLAYER_ERROR_MESSAGE,
        );
      }
    },
    reconcileSnapshot,
    closeTop,
    routeLeave,
    setNowPlayingAutoHideMs(value) {
      nowPlayingAutoHideMs = value;
      if (options.getState().activeOverlayId === 'nowPlaying') {
        armNowPlayingTimer();
      } else {
        nowPlayingTimer = clearTimer(nowPlayingTimer);
      }
    },
    dispose() {
      if (disposed) return;
      routeLeave();
      options.recovery.dispose();
      disposed = true;
    },
  };
}

function trackMembership(
  snapshot: PlayerSnapshot,
  family: 'audio' | 'subtitle' | null,
  trackId: string | null,
): boolean {
  if (family === 'subtitle' && trackId === null) return true;
  if (family === null || trackId === null) return false;
  return availableTracks(snapshot, family).some((track) => track.id === trackId);
}

function firstOptionFocus(
  snapshot: PlayerSnapshot,
  family: 'audio' | 'subtitle' | null,
): string | null {
  if (family === 'subtitle') return 'overlay-subtitle-track-off';
  const first = availableTracks(snapshot, 'audio')[0];
  return first === undefined ? null : `overlay-audio-track-${first.id}`;
}

function isRecoveryActive(state: PlayerOverlayState): boolean {
  return (
    state.retryPending ||
    state.recoveryPendingAction !== null ||
    state.retryTransitionActive
  );
}
