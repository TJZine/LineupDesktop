import type { PlayerSnapshot } from '../contracts/player.js';
import {
  isAudioControlEligible,
  isSleepControlEligible,
  isSubtitleControlEligible,
  type PlayerOverlayPresentationSource,
} from './playerOverlayPresentation.js';
import {
  createSleepTimerProjection,
  type SleepTimerProjection,
} from './sleepTimerController.js';

export { createPlayerOverlayView, activeOverlayId } from './overlayViewModels.js';
export type {
  PlaybackOptionsViewModel,
  PlaybackOptionTrackViewModel,
  PlayerOverlayViewModel,
} from './overlayViewModels.js';
export type {
  OverlayChannelViewModel,
  PlayerOverlayPresentationSource,
} from './playerOverlayPresentation.js';

export type PlayerOverlayId =
  | 'playerOsd'
  | 'nowPlaying'
  | 'miniGuide'
  | 'channelNumber'
  | 'channelBadge'
  | 'playbackOptions'
  | 'transition'
  | 'playerLoading'
  | 'playerError';

export type PlayerOverlayActionId =
  | 'openOsd'
  | 'openNowPlaying'
  | 'openMiniGuide'
  | 'openAudioOptions'
  | 'openSubtitleOptions'
  | 'cycleSleepTimer'
  | 'retryPlayer'
  | 'skipPlayer'
  | 'miniGuidePrevious'
  | 'miniGuideNext'
  | 'miniGuidePagePrevious'
  | 'miniGuidePageNext'
  | 'closeTopOverlay';

export interface PlayerOverlayState {
  activeOverlayId: PlayerOverlayId | null;
  miniGuideSelectedChannelId: string | null;
  channelNumberBuffer: string;
  channelNumberStatus: 'editing' | 'pending' | 'completed' | 'error' | null;
  channelNumberMessage: string | null;
  playbackOptionsFamily: 'audio' | 'subtitle' | null;
  playbackOptionsFocusId: string | null;
  playbackOptionsInvoker: 'audio' | 'subtitle' | null;
  playbackOptionsError: string | null;
  miniGuideError: string | null;
  retryError: string | null;
  pendingTrackFocusId: string | null;
  pendingTuneChannelId: string | null;
  transitionChannelId: string | null;
  transitionVisible: boolean;
  retryPending: boolean;
  recoveryPendingAction: 'retry-current' | 'skip-next' | null;
  retryTransitionActive: boolean;
  lastTuneChannelId: string | null;
  sleepTimer: SleepTimerProjection;
}

export function createPlayerOverlayState(
  presentation?: PlayerOverlayPresentationSource,
): PlayerOverlayState {
  return {
    activeOverlayId: null,
    miniGuideSelectedChannelId: presentation?.currentChannelId ?? presentation?.channels[0]?.id ?? null,
    channelNumberBuffer: '',
    channelNumberStatus: null,
    channelNumberMessage: null,
    playbackOptionsFamily: null,
    playbackOptionsFocusId: null,
    playbackOptionsInvoker: null,
    playbackOptionsError: null,
    miniGuideError: null,
    retryError: null,
    pendingTrackFocusId: null,
    pendingTuneChannelId: null,
    transitionChannelId: null,
    transitionVisible: false,
    retryPending: false,
    recoveryPendingAction: null,
    retryTransitionActive: false,
    lastTuneChannelId: null,
    sleepTimer: createSleepTimerProjection(),
  };
}

export function openOsd(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot,
): PlayerOverlayState {
  if (!['ready', 'playing', 'paused'].includes(snapshot.status)) return state;
  if (state.activeOverlayId === 'playbackOptions' ||
    state.activeOverlayId === 'nowPlaying' || state.activeOverlayId === 'miniGuide') return state;
  if (
    !isSleepControlEligible(snapshot) &&
    !isAudioControlEligible(snapshot) &&
    !isSubtitleControlEligible(snapshot)
  ) return closeActive(state);
  return { ...closeActive(state), activeOverlayId: 'playerOsd' };
}

export function openNowPlaying(
  state: PlayerOverlayState,
  hasCurrentProgram: boolean,
  blocked: boolean,
): PlayerOverlayState {
  if (!hasCurrentProgram || blocked || state.activeOverlayId === 'playbackOptions') return state;
  return { ...closeActive(state), activeOverlayId: 'nowPlaying' };
}

export function openMiniGuide(
  state: PlayerOverlayState,
  presentation: PlayerOverlayPresentationSource,
): PlayerOverlayState {
  if (presentation.channels.length === 0) return state;
  return {
    ...closeActive(state),
    activeOverlayId: 'miniGuide',
    miniGuideSelectedChannelId: state.miniGuideSelectedChannelId ??
      presentation.currentChannelId ?? presentation.channels[0]?.id ?? null,
  };
}

export function moveMiniGuide(
  state: PlayerOverlayState,
  presentation: PlayerOverlayPresentationSource,
  offset: number,
): PlayerOverlayState {
  if (state.activeOverlayId !== 'miniGuide' || presentation.channels.length === 0) return state;
  const index = Math.max(0, presentation.channels.findIndex(
    (channel) => channel.id === state.miniGuideSelectedChannelId,
  ));
  const next = (index + offset % presentation.channels.length + presentation.channels.length) % presentation.channels.length;
  return {
    ...state,
    miniGuideSelectedChannelId: presentation.channels[next]?.id ?? state.miniGuideSelectedChannelId,
    miniGuideError: null,
  };
}

export function openPlaybackOptions(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot,
  family: 'audio' | 'subtitle',
): PlayerOverlayState {
  const eligible = family === 'audio'
    ? isAudioControlEligible(snapshot)
    : isSubtitleControlEligible(snapshot);
  if (state.activeOverlayId !== 'playerOsd' || !eligible) return state;
  const firstId = family === 'audio'
    ? snapshot.tracks.find((track) => track.kind === 'audio' && track.available)?.id
    : 'off';
  return {
    ...state,
    activeOverlayId: 'playbackOptions',
    playbackOptionsFamily: family,
    playbackOptionsInvoker: family,
    playbackOptionsFocusId: firstId === undefined ? null : `overlay-${family}-track-${firstId}`,
    playbackOptionsError: null,
  };
}

export function appendChannelDigit(state: PlayerOverlayState, digit: string): PlayerOverlayState {
  if (state.channelNumberStatus === 'pending' || !/^\d$/u.test(digit)) return state;
  return {
    ...closeActive(state),
    activeOverlayId: 'channelNumber',
    channelNumberBuffer: `${state.channelNumberBuffer}${digit}`.slice(0, 3),
    channelNumberStatus: 'editing',
    channelNumberMessage: null,
  };
}

export function closeTopOverlay(state: PlayerOverlayState): PlayerOverlayState {
  if (state.activeOverlayId === null) return state;
  if (state.activeOverlayId === 'playbackOptions') {
    return {
      ...state,
      activeOverlayId: 'playerOsd',
      playbackOptionsError: null,
      pendingTrackFocusId: null,
    };
  }
  return closeActive(state);
}

export function closeAllPlayerOverlays(state: PlayerOverlayState): PlayerOverlayState {
  return {
    ...createPlayerOverlayState(),
    miniGuideSelectedChannelId: state.miniGuideSelectedChannelId,
    lastTuneChannelId: state.lastTuneChannelId,
    retryError: state.retryError,
    retryPending: state.retryPending,
    recoveryPendingAction: state.recoveryPendingAction,
    retryTransitionActive: state.retryTransitionActive,
    sleepTimer: state.sleepTimer,
  };
}

export function reconcileSnapshotState(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot,
): PlayerOverlayState {
  if (snapshot.status === 'error' || snapshot.status === 'destroyed') {
    return {
      ...closeAllPlayerOverlays(state),
      lastTuneChannelId: state.lastTuneChannelId,
    };
  }
  if (snapshot.status === 'idle' || snapshot.status === 'ended') {
    return { ...state, activeOverlayId: null, playbackOptionsFamily: null, pendingTrackFocusId: null };
  }
  if (['loading', 'buffering', 'stalled'].includes(snapshot.status) && state.activeOverlayId === 'playerOsd') {
    return closeActive(state);
  }
  return state;
}

function closeActive(state: PlayerOverlayState): PlayerOverlayState {
  return {
    ...state,
    activeOverlayId: null,
    playbackOptionsFamily: null,
    playbackOptionsFocusId: null,
    playbackOptionsInvoker: null,
    playbackOptionsError: null,
    miniGuideError: null,
    pendingTrackFocusId: null,
    channelNumberBuffer: '',
    channelNumberStatus: null,
    channelNumberMessage: null,
  };
}
