import {
  activeOverlayId,
  DEFAULT_PLAYER_OVERLAY_PRESENTATION,
  PLAYBACK_AUDIO_TRACKS,
  PLAYBACK_SUBTITLE_TRACKS,
} from './overlayViewModels.js';
import type {
  PlayerOverlayPresentationSource,
  PlayerOverlayId,
  PlayerOverlayState,
  PlayerOverlayViewModel,
} from './overlayViewModels.js';

export {
  createRendererSafePlayerSnapshot,
  createPlayerOverlayView,
  DEFAULT_PLAYER_OVERLAY_PRESENTATION,
  getDefaultOverlayPresentationChannels,
} from './overlayViewModels.js';
export type {
  NowPlayingOverlayViewModel,
  OverlayChannelViewModel,
  PlaybackOptionsViewModel,
  PlaybackOptionTrackViewModel,
  PlayerOverlayId,
  PlayerOverlayPresentationSource,
  PlayerOverlayState,
  PlayerOverlayViewModel,
} from './overlayViewModels.js';

export type PlayerOverlayActionId =
  | 'toggleOsd'
  | 'openMiniGuide'
  | 'previousMiniGuideChannel'
  | 'nextMiniGuideChannel'
  | 'togglePlaybackOptions'
  | 'cycleAudioTrack'
  | 'cycleSubtitleTrack'
  | 'toggleMute'
  | 'volumeDown'
  | 'volumeUp'
  | 'channelDigit0'
  | 'channelDigit1'
  | 'channelDigit2'
  | 'channelDigit3'
  | 'channelDigit4'
  | 'channelDigit5'
  | 'channelDigit6'
  | 'channelDigit7'
  | 'channelDigit8'
  | 'channelDigit9'
  | 'commitChannelNumber'
  | 'clearChannelNumber'
  | 'closeTopOverlay';

type PlayerOverlayDigitActionId = Extract<PlayerOverlayActionId, `channelDigit${number}`>;

export const PLAYER_OVERLAY_IDLE_FOCUS_ID = 'player-osd';

const CHANNEL_NUMBER_BUFFER_TIMEOUT_MS = 2_500;
const CHANNEL_NUMBER_MAX_LENGTH = 3;

export function createPlayerOverlayState(
  presentation: PlayerOverlayPresentationSource = DEFAULT_PLAYER_OVERLAY_PRESENTATION,
): PlayerOverlayState {
  const firstChannel = presentation.channels[0];
  if (firstChannel === undefined) {
    throw new Error('Player overlay presentation requires at least one channel');
  }
  return {
    stack: ['channelBadge', 'nowPlaying', 'playerOsd'],
    currentChannelId: firstChannel.id,
    miniGuideSelectedChannelId: firstChannel.id,
    channelNumberBuffer: '',
    channelNumberUpdatedAtMs: null,
    selectedAudioTrackId: PLAYBACK_AUDIO_TRACKS[0].id,
    selectedSubtitleTrackId: null,
    muted: false,
    volume: 0.72,
    playbackRate: 1,
  };
}

export function applyPlayerOverlayAction(
  state: PlayerOverlayState,
  actionId: PlayerOverlayActionId,
  nowMs = Date.now(),
  presentation: PlayerOverlayPresentationSource = DEFAULT_PLAYER_OVERLAY_PRESENTATION,
): PlayerOverlayState {
  switch (actionId) {
    case 'toggleOsd':
      return toggleOverlay(state, 'playerOsd');
    case 'openMiniGuide':
      return showChannelBadge(openOverlay(state, 'miniGuide'));
    case 'previousMiniGuideChannel':
      return selectMiniGuideChannel(state, -1, presentation);
    case 'nextMiniGuideChannel':
      return selectMiniGuideChannel(state, 1, presentation);
    case 'togglePlaybackOptions':
      return openOverlay(openOverlay(state, 'playerOsd'), 'playbackOptions');
    case 'cycleAudioTrack':
      return {
        ...openOverlay(state, 'playbackOptions'),
        selectedAudioTrackId: nextAudioTrackId(state.selectedAudioTrackId),
      };
    case 'cycleSubtitleTrack':
      return {
        ...openOverlay(state, 'playbackOptions'),
        selectedSubtitleTrackId: nextSubtitleTrackId(state.selectedSubtitleTrackId),
      };
    case 'toggleMute':
      return {
        ...openOverlay(state, 'playbackOptions'),
        muted: !state.muted,
      };
    case 'volumeDown':
      return {
        ...openOverlay(state, 'playbackOptions'),
        volume: clampVolume(state.volume - 0.1),
      };
    case 'volumeUp':
      return {
        ...openOverlay(state, 'playbackOptions'),
        volume: clampVolume(state.volume + 0.1),
      };
    case 'commitChannelNumber':
      return commitChannelNumber(state, presentation);
    case 'clearChannelNumber':
      return {
        ...removeOverlay(state, 'channelNumber'),
        channelNumberBuffer: '',
        channelNumberUpdatedAtMs: null,
      };
    case 'closeTopOverlay':
      return closeTopOverlay(state);
    case 'channelDigit0':
    case 'channelDigit1':
    case 'channelDigit2':
    case 'channelDigit3':
    case 'channelDigit4':
    case 'channelDigit5':
    case 'channelDigit6':
    case 'channelDigit7':
    case 'channelDigit8':
    case 'channelDigit9':
      return appendChannelNumberDigit(state, readChannelDigit(actionId), nowMs);
    default: {
      const exhaustiveCheck: never = actionId;
      return exhaustiveCheck;
    }
  }
}

export function resolvePlayerOverlayFocusId(view: PlayerOverlayViewModel): string {
  return view.activeFocusId ?? PLAYER_OVERLAY_IDLE_FOCUS_ID;
}

function appendChannelNumberDigit(
  state: PlayerOverlayState,
  digit: string,
  nowMs: number,
): PlayerOverlayState {
  const stale =
    state.channelNumberUpdatedAtMs !== null &&
    nowMs - state.channelNumberUpdatedAtMs > CHANNEL_NUMBER_BUFFER_TIMEOUT_MS;
  const existingBuffer = stale ? '' : state.channelNumberBuffer;
  const channelNumberBuffer = `${existingBuffer}${digit}`.slice(-CHANNEL_NUMBER_MAX_LENGTH);
  return openOverlay(
    {
      ...state,
      channelNumberBuffer,
      channelNumberUpdatedAtMs: nowMs,
    },
    'channelNumber',
  );
}

function commitChannelNumber(
  state: PlayerOverlayState,
  presentation: PlayerOverlayPresentationSource,
): PlayerOverlayState {
  const channel = presentation.channels.find(
    (candidate) => candidate.number === state.channelNumberBuffer,
  );
  const nextState = {
    ...removeOverlay(state, 'channelNumber'),
    channelNumberBuffer: '',
    channelNumberUpdatedAtMs: null,
  };

  if (channel === undefined) {
    return nextState;
  }

  return showChannelBadge({
    ...nextState,
    currentChannelId: channel.id,
    miniGuideSelectedChannelId: channel.id,
  });
}

function selectMiniGuideChannel(
  state: PlayerOverlayState,
  offset: number,
  presentation: PlayerOverlayPresentationSource,
): PlayerOverlayState {
  const currentIndex = Math.max(
    0,
    presentation.channels.findIndex((channel) => channel.id === state.miniGuideSelectedChannelId),
  );
  const nextIndex = Math.max(0, Math.min(presentation.channels.length - 1, currentIndex + offset));
  const nextChannel = presentation.channels[nextIndex];
  if (nextChannel === undefined) {
    return state;
  }
  return showChannelBadge(
    openOverlay(
      {
        ...state,
        miniGuideSelectedChannelId: nextChannel.id,
      },
      'miniGuide',
    ),
  );
}

function toggleOverlay(state: PlayerOverlayState, overlayId: PlayerOverlayId): PlayerOverlayState {
  if (state.stack.includes(overlayId)) {
    return removeOverlay(state, overlayId);
  }
  return openOverlay(state, overlayId);
}

function openOverlay(state: PlayerOverlayState, overlayId: PlayerOverlayId): PlayerOverlayState {
  return {
    ...state,
    stack: [...state.stack.filter((candidate) => candidate !== overlayId), overlayId],
  };
}

function removeOverlay(state: PlayerOverlayState, overlayId: PlayerOverlayId): PlayerOverlayState {
  return {
    ...state,
    stack: state.stack.filter((candidate) => candidate !== overlayId),
  };
}

function showChannelBadge(state: PlayerOverlayState): PlayerOverlayState {
  return state.stack.includes('channelBadge')
    ? state
    : { ...state, stack: ['channelBadge', ...state.stack] };
}

function closeTopOverlay(state: PlayerOverlayState): PlayerOverlayState {
  const overlayId = activeOverlayId(state);
  return overlayId === null ? state : removeOverlay(state, overlayId);
}

function nextAudioTrackId(currentTrackId: string): string {
  const availableTracks = PLAYBACK_AUDIO_TRACKS.filter((track) => track.available);
  const currentIndex = availableTracks.findIndex((track) => track.id === currentTrackId);
  if (currentIndex === -1) {
    return availableTracks[0]?.id ?? currentTrackId;
  }
  return availableTracks[(currentIndex + 1) % availableTracks.length]?.id ?? currentTrackId;
}

function nextSubtitleTrackId(currentTrackId: string | null): string | null {
  const availableTracks = PLAYBACK_SUBTITLE_TRACKS.filter((track) => track.available);
  const currentIndex = availableTracks.findIndex((track) => track.id === currentTrackId);
  if (currentIndex === -1) {
    return availableTracks[0]?.id ?? null;
  }
  return availableTracks[(currentIndex + 1) % availableTracks.length]?.id ?? null;
}

function readChannelDigit(actionId: PlayerOverlayDigitActionId): string {
  return actionId.replace('channelDigit', '');
}

function clampVolume(value: number): number {
  return Math.max(0, Math.min(1, Number(value.toFixed(2))));
}
