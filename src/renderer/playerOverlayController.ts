import type { PlayerCommandName, PlayerEvent, PlayerSnapshot } from '../contracts/player.js';
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
  isAudioControlEligible,
  isSubtitleControlEligible,
  resolveRetryChannelId,
  type PlayerOverlayPresentationSource,
} from './playerOverlayPresentation.js';

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
}

export interface PlayerOverlayController {
  handleInput(input: DesktopInputButton, shellBlocked?: boolean): boolean;
  requestOsd(): boolean;
  requestNowPlaying(shellBlocked?: boolean): boolean;
  requestMiniGuide(): boolean;
  activateMiniGuideChannel(channelId: string): boolean;
  retry(): boolean;
  openOptions(family: 'audio' | 'subtitle'): boolean;
  selectTrack(family: 'audio' | 'subtitle', trackId: string | null, focusId: string): Promise<void>;
  tune(channelId: string, invoker: 'miniGuide' | 'number' | 'retry'): Promise<void>;
  handlePlayerEvent(event: PlayerEvent): void;
  reconcileSnapshot(snapshot: PlayerSnapshot, authoritative: boolean, explicitTrackList?: boolean): void;
  closeTop(): boolean;
  routeLeave(): void;
  dispose(): void;
}

interface PendingCommand {
  requestId: string;
  command: PlayerCommandName;
  kind: 'space' | 'track';
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

export function createPlayerOverlayController(
  options: PlayerOverlayControllerOptions,
): PlayerOverlayController {
  let disposed = false;
  let sequence = 0;
  let tuneGeneration = 0;
  let pendingCommand: PendingCommand | null = null;
  let osdTimer: number | null = null;
  let miniGuideTimer: number | null = null;
  let numberTimer: number | null = null;
  let transitionTimer: number | null = null;
  let lastSnapshotRequestId = options.getPresentation().playerSnapshot.requestId;
  let lastAuthoritativeStatus = options.getPresentation().playerSnapshot.status;

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
    numberTimer = clearTimer(numberTimer);
  };

  const clearOverlayTimers = (): void => {
    clearTransientTimers();
    transitionTimer = clearTimer(transitionTimer);
  };

  const focusActive = (): void => {
    const state = options.getState();
    const presentation = options.getPresentation();
    const snapshot = presentation.playerSnapshot;
    if (state.activeOverlayId === 'playerOsd') {
      options.focus(isAudioControlEligible(snapshot) ? 'overlay-osd-audio' : 'overlay-osd-subtitles');
    } else if (state.activeOverlayId === 'miniGuide' && state.miniGuideSelectedChannelId !== null) {
      options.focus(`overlay-mini-channel-${encodeURIComponent(state.miniGuideSelectedChannelId)}`);
    } else if (state.activeOverlayId === 'playbackOptions') {
      options.focus(state.pendingTrackFocusId ?? state.playbackOptionsFocusId);
    } else if (snapshot.status === 'error' && snapshot.lastError?.retryable === true &&
      resolveRetryChannelId(presentation, state.lastTuneChannelId) !== null) {
      options.focus('overlay-player-retry');
    } else if ((snapshot.status === 'error' || snapshot.status === 'destroyed') && presentation.channels.length > 0) {
      options.focus('overlay-player-guide');
    } else {
      options.focus(null);
    }
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
    const presentation = options.getPresentation();
    const state = options.getState();
    const channelId = resolveRetryChannelId(presentation, state.lastTuneChannelId);
    if (presentation.playerSnapshot.status !== 'error' ||
      presentation.playerSnapshot.lastError?.retryable !== true || channelId === null || state.retryPending) return false;
    void tune(channelId, 'retry');
    return true;
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

  const dispatchSpace = (): boolean => {
    const snapshot = options.getPresentation().playerSnapshot;
    if (pendingCommand !== null || options.getState().activeOverlayId === 'playbackOptions') return true;
    let intent: 'player.play' | 'player.pause' | null = null;
    let command: 'play' | 'pause' | null = null;
    if (snapshot.status === 'playing' && snapshot.playing) {
      intent = 'player.pause'; command = 'pause';
    } else if ((snapshot.status === 'ready' || snapshot.status === 'paused') && !snapshot.playing) {
      intent = 'player.play'; command = 'play';
    } else if (
      (snapshot.status === 'playing' && !snapshot.playing) ||
      ((snapshot.status === 'ready' || snapshot.status === 'paused') && snapshot.playing)
    ) {
      options.recordDiagnostic('player.space', 'Inconsistent player state ignored.');
    }
    if (intent === null || command === null) return true;
    const requestId = `renderer-${command}-${++sequence}`;
    pendingCommand = { requestId, command, kind: 'space', snapshotRequestId: snapshot.requestId, focusId: null, trackId: null, family: null };
    void options.player.dispatch({ intent, requestId, payload: {} }).then((result) => {
      if (disposed || pendingCommand?.requestId !== requestId) return;
      if (!result.ok || !result.value.accepted) failPendingCommand(result.ok ? 'Player command was not accepted.' : result.error.message);
      else for (const event of result.value.events) if (event.event === 'command.settled') settleCommand(event);
    }).catch(() => failPendingCommand('Player command failed.'));
    return true;
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
    pendingCommand = { requestId, command, kind: 'track', snapshotRequestId: snapshot.requestId, focusId, trackId, family };
    update((state) => ({ ...state, pendingTrackFocusId: focusId, playbackOptionsError: null }));
    try {
      const result = await options.player.dispatch({
        intent: family === 'audio' ? 'player.selectAudio' : 'player.selectSubtitle',
        requestId,
        payload: { trackId, snapshotRequestId: snapshot.requestId },
      });
      if (disposed || pendingCommand?.requestId !== requestId) return;
      if (!result.ok || !result.value.accepted) {
        failPendingCommand(result.ok ? 'Track selection was not accepted.' : result.error.message);
      } else {
        for (const event of result.value.events) if (event.event === 'command.settled') settleCommand(event);
      }
    } catch {
      failPendingCommand('Track selection failed.');
    }
  };

  const tune = async (
    channelId: string,
    invoker: 'miniGuide' | 'number' | 'retry',
  ): Promise<void> => {
    if (disposed || !options.getPresentation().channels.some((channel) => channel.id === channelId)) return;
    const state = options.getState();
    if (state.pendingTuneChannelId === channelId || state.transitionChannelId === channelId) return;
    const generation = ++tuneGeneration;
    transitionTimer = clearTimer(transitionTimer);
    if (invoker === 'number') numberTimer = clearTimer(numberTimer);
    update((current) => ({
      ...current,
      pendingTuneChannelId: channelId,
      transitionChannelId: channelId,
      transitionVisible: false,
      retryPending: invoker === 'retry',
      channelNumberStatus: invoker === 'number' ? 'pending' : current.channelNumberStatus,
      channelNumberMessage: null,
      playbackOptionsError: null,
      miniGuideError: invoker === 'miniGuide' ? null : current.miniGuideError,
      retryError: invoker === 'retry' ? null : current.retryError,
    }));
    transitionTimer = options.host.setTimeout(() => {
      transitionTimer = null;
      if (generation === tuneGeneration && !disposed) update((current) => ({ ...current, transitionVisible: true }));
    }, TRANSITION_DELAY_MS);
    try {
      const result = await options.player.tuneChannel({ channelId });
      if (disposed || generation !== tuneGeneration) return;
      if (!result.ok) {
        failTune(generation, invoker, result.error.message);
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
          retryPending: false,
          retryTransitionActive: invoker === 'retry',
          lastTuneChannelId: channelId,
          channelNumberStatus: invoker === 'number' && invokerOwnedAtSettlement ? 'completed' : current.channelNumberStatus,
          channelNumberMessage: invoker === 'number' && invokerOwnedAtSettlement ? 'Tuned' : current.channelNumberMessage,
        };
      });
      if (invoker === 'number' && invokerOwnedAtSettlement) {
        numberTimer = options.host.setTimeout(closeNumber, NUMBER_COMPLETE_MS);
      } else if ((invoker === 'miniGuide' && invokerOwnedAtSettlement) || invoker === 'retry') {
        options.focus(null);
      }
      await options.refreshChannelStatus().catch(() => undefined);
      if (generation !== tuneGeneration || disposed) return;
      await options.refreshGuidePresentation().catch(() => undefined);
      if (generation !== tuneGeneration || disposed) return;
    } catch {
      if (generation === tuneGeneration && !disposed) failTune(generation, invoker, 'Channel tune failed.');
    }
  };

  const failTune = (
    generation: number,
    invoker: 'miniGuide' | 'number' | 'retry',
    message: string,
  ): void => {
    if (generation !== tuneGeneration || disposed) return;
    transitionTimer = clearTimer(transitionTimer);
    const safe = safeMessage(message, 'Channel tune failed.');
    let invokerOwnedAtSettlement = false;
    update((state) => {
      const invokerOverlay = invoker === 'miniGuide' ? 'miniGuide' : invoker === 'number' ? 'channelNumber' : null;
      invokerOwnedAtSettlement = invokerOverlay !== null && state.activeOverlayId === invokerOverlay;
      return {
        ...state,
        pendingTuneChannelId: null,
        transitionChannelId: null,
        transitionVisible: false,
        retryPending: false,
        retryTransitionActive: false,
        miniGuideError: invoker === 'miniGuide' && invokerOwnedAtSettlement ? safe : state.miniGuideError,
        retryError: invoker === 'retry' ? safe : state.retryError,
        channelNumberStatus: invoker === 'number' && invokerOwnedAtSettlement ? 'error' : state.channelNumberStatus,
        channelNumberMessage: invoker === 'number' && invokerOwnedAtSettlement ? safe : state.channelNumberMessage,
      };
    });
    if (invoker === 'miniGuide' && invokerOwnedAtSettlement) focusActive();
    if (invoker === 'retry') options.focus('overlay-player-retry');
    if (invoker === 'number' && invokerOwnedAtSettlement) numberTimer = options.host.setTimeout(closeNumber, NUMBER_RESULT_MS);
  };

  const settleCommand = (event: Extract<PlayerEvent, { event: 'command.settled' }>): void => {
    if (pendingCommand?.requestId !== event.requestId || pendingCommand.command !== event.command) return;
    if (!event.ok) {
      failPendingCommand(event.error?.message ?? 'Player command failed.');
      return;
    }
    const completed = pendingCommand;
    pendingCommand = null;
    if (completed.kind === 'track') closeOptionsWithFallback(completed);
  };

  const failPendingCommand = (message: string): void => {
    const pending = pendingCommand;
    if (pending === null) return;
    pendingCommand = null;
    if (pending.kind === 'space') {
      options.recordDiagnostic('player.space', safeMessage(message, 'Player command failed.'));
      return;
    }
    setOptionsFailure(pending.focusId, safeMessage(message, 'Track selection failed.'));
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
      : isAudioControlEligible(snapshot)
        ? 'overlay-osd-audio'
        : isSubtitleControlEligible(snapshot)
          ? 'overlay-osd-subtitles'
          : null;
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
    const previousAuthoritativeStatus = lastAuthoritativeStatus;
    if (authoritative) lastAuthoritativeStatus = snapshot.status;
    const previousRequest = lastSnapshotRequestId;
    lastSnapshotRequestId = snapshot.requestId;
    if (pendingCommand !== null && previousRequest !== snapshot.requestId) {
      const invalidated = pendingCommand;
      pendingCommand = null;
      if (invalidated.kind === 'track') closeOptionsWithFallback(invalidated, false);
    }
    const ambiguousAuthoritativeLoad = authoritative && !explicitTrackList &&
      ['loading', 'buffering', 'stalled', 'seeking'].includes(snapshot.status);
    if (pendingCommand?.kind === 'track' && !ambiguousAuthoritativeLoad &&
      !trackMembership(snapshot, pendingCommand.family, pendingCommand.trackId)) {
      const invalidated = pendingCommand;
      pendingCommand = null;
      const familyEligible = invalidated.family === 'audio'
        ? isAudioControlEligible(snapshot)
        : invalidated.family === 'subtitle' && isSubtitleControlEligible(snapshot);
      if (familyEligible) {
        setOptionsFailure(firstOptionFocus(snapshot, invalidated.family), 'Track is no longer available.');
      } else {
        closeOptionsWithFallback(invalidated);
      }
      if (invalidated.focusId !== null) options.recordDiagnostic('player.track.membership', 'Pending track was removed.');
    }
    if (authoritative && (snapshot.status === 'error' || snapshot.status === 'destroyed')) {
      clearOverlayTimers();
      pendingCommand = null;
      ++tuneGeneration;
      update((state) => reconcileSnapshotState(state, snapshot));
      focusActive();
      return;
    }
    if ((authoritative || snapshot.status === 'ended') && options.getState().transitionChannelId !== null) {
      if (['idle', 'ready', 'playing', 'paused', 'ended', 'error', 'destroyed'].includes(snapshot.status)) {
        transitionTimer = clearTimer(transitionTimer);
        update((state) => ({ ...state, transitionChannelId: null, transitionVisible: false, pendingTuneChannelId: null, retryPending: false, retryTransitionActive: false }));
      }
    }
    if (pendingCommand?.kind === 'space' && authoritative && isInconsistentPlaybackPair(snapshot)) {
      failPendingCommand('Inconsistent player state ignored.');
    }
    if (authoritative || snapshot.status === 'ended') update((state) => reconcileSnapshotState(state, snapshot));
    if (authoritative && previousAuthoritativeStatus !== 'playing' && snapshot.status === 'playing' &&
      options.getState().activeOverlayId === 'playerOsd') armOsdTimer();
  };

  const closeTop = (): boolean => {
    const state = options.getState();
    if (state.activeOverlayId === null) return false;
    const wasOptions = state.activeOverlayId === 'playbackOptions';
    if (pendingCommand?.kind === 'track') pendingCommand = null;
    if (state.activeOverlayId === 'miniGuide') miniGuideTimer = clearTimer(miniGuideTimer);
    if (state.activeOverlayId === 'playerOsd') osdTimer = clearTimer(osdTimer);
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
    pendingCommand = null;
    options.setState(closeAllPlayerOverlays(options.getState()));
    options.render();
  };

  const handleInput = (input: DesktopInputButton, shellBlocked = false): boolean => {
    if (disposed) return false;
    const state = options.getState();
    if (input === 'space') return dispatchSpace();
    if (input === 'info') return requestNowPlaying(shellBlocked);
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
    openOptions,
    selectTrack,
    tune,
    handlePlayerEvent(event) {
      if (event.event === 'command.settled') settleCommand(event);
      else if (event.event === 'error' && event.requestId !== null && pendingCommand?.requestId === event.requestId) {
        failPendingCommand(event.error.message);
      } else if (event.event === 'warning' || event.event === 'error') {
        options.recordDiagnostic(
          `player.${event.event}`,
          safeMessage(
            event.event === 'warning' ? event.warning.message : event.error.message,
            event.event === 'warning' ? 'Player warning.' : 'Player error.',
          ),
        );
      }
    },
    reconcileSnapshot,
    closeTop,
    routeLeave,
    dispose() {
      if (disposed) return;
      routeLeave();
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

function safeMessage(message: string, fallback: string): string {
  const compact = message.replace(/\p{Cc}/gu, ' ').replace(/\s+/gu, ' ').trim();
  if (compact.length === 0 || /(?:https?:\/\/|token|credential|secret|header|\\\\|\/Users\/|[A-Za-z]:\\)/iu.test(compact)) {
    return fallback;
  }
  return compact.slice(0, 180);
}

function isInconsistentPlaybackPair(snapshot: PlayerSnapshot): boolean {
  return (snapshot.status === 'playing' && !snapshot.playing) ||
    ((snapshot.status === 'ready' || snapshot.status === 'paused') && snapshot.playing);
}
