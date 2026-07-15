import type { PlayerSnapshot, PlayerStatus } from '../contracts/player.js';
import {
  availableTracks,
  isAudioControlEligible,
  isSubtitleControlEligible,
  resolveRetryChannelId,
  type OverlayChannelViewModel,
  type PlayerOverlayPresentationSource,
} from './playerOverlayPresentation.js';
import { formatDuration, selectedTrackLabel, statusLabel, trackMeta } from './overlayViewModelHelpers.js';
import type { PlayerOverlayId, PlayerOverlayState } from './overlays.js';

export type { OverlayChannelViewModel, PlayerOverlayPresentationSource } from './playerOverlayPresentation.js';

export interface PlaybackOptionTrackViewModel {
  id: string;
  trackId: string | null;
  label: string;
  selected: boolean;
  meta?: string;
  focusId: string;
  busy: boolean;
}

export interface PlaybackOptionsViewModel {
  family: 'audio' | 'subtitle';
  tracks: readonly PlaybackOptionTrackViewModel[];
  error: string | null;
}

export interface PlayerOverlayViewModel {
  stack: readonly PlayerOverlayId[];
  visibleOverlays: Readonly<Record<PlayerOverlayId, boolean>>;
  activeOverlayId: PlayerOverlayId | null;
  activeFocusId: string | null;
  baseline: 'native' | 'loading' | 'error';
  errorMessage: string | null;
  retryVisible: boolean;
  guideVisible: boolean;
  retryBusy: boolean;
  currentChannel: OverlayChannelViewModel | null;
  nowPlaying: {
    title?: string;
    subtitle?: string;
    channelLabel?: string;
    statusLabel: string;
    positionLabel: string;
    durationLabel: string;
    progressPercent: number;
    upNextText?: string;
  };
  playerOsd: {
    statusLabel: string;
    title?: string;
    subtitle?: string;
    timecode: string;
    playedPercent: number;
    bufferedPercent: number;
    audioEligible: boolean;
    subtitleEligible: boolean;
    audioLabel?: string;
    subtitleLabel?: string;
  };
  miniGuideChannels: readonly (OverlayChannelViewModel & { selected: boolean; busy: boolean })[];
  miniGuideError: string | null;
  channelNumberDisplay: string;
  channelNumberStatus: PlayerOverlayState['channelNumberStatus'];
  channelNumberMessage: string | null;
  playbackOptions: PlaybackOptionsViewModel | null;
  transitionLabel: string | null;
}

export function createPlayerOverlayView(
  state: PlayerOverlayState,
  presentation: PlayerOverlayPresentationSource,
): PlayerOverlayViewModel {
  const snapshot = presentation.playerSnapshot;
  const currentChannel = presentation.channels.find(
    (channel) => channel.id === presentation.currentChannelId,
  ) ?? null;
  const selectedChannel = presentation.channels.find(
    (channel) => channel.id === state.miniGuideSelectedChannelId,
  ) ?? presentation.channels[0] ?? null;
  const baseline = baselineFor(snapshot.status, state.activeOverlayId === 'playerOsd');
  const terminal = baseline === 'error' && !state.retryTransitionActive;
  const retryVisible = snapshot.status === 'error' && snapshot.lastError?.retryable === true &&
    resolveRetryChannelId(presentation, state.lastTuneChannelId) !== null;
  const guideVisible = terminal && presentation.channels.length > 0;
  const active = terminal ? 'playerError' : state.activeOverlayId;
  const visible = emptyVisibility();
  if (active !== null) visible[active] = true;
  visible.channelBadge = !terminal && state.transitionChannelId === null && currentChannel !== null &&
    (active === 'playerOsd' || active === 'nowPlaying');
  visible.transition = !terminal && active === null && state.transitionVisible;
  visible.playerLoading = !terminal && active === null && !state.transitionVisible && baseline === 'loading';
  visible.playerError = terminal;

  const durationMs = Math.max(0, snapshot.durationMs ?? snapshot.media?.durationMs ?? 0);
  const positionMs = Math.min(Math.max(0, snapshot.positionMs), durationMs);
  const progressPercent = durationMs === 0 ? 0 : Math.round((positionMs / durationMs) * 100);
  const bufferEnd = snapshot.bufferedRanges.reduce((max, range) => Math.max(max, range.endMs), 0);
  const options = active === 'playbackOptions'
    ? createPlaybackOptions(state, snapshot)
    : null;

  return {
    stack: stackFromVisibility(visible),
    visibleOverlays: visible,
    activeOverlayId: active,
    activeFocusId: focusIdFor(active, state, snapshot, retryVisible, guideVisible),
    baseline,
    errorMessage: terminal
      ? snapshot.status === 'destroyed'
        ? 'Player unavailable.'
        : state.retryError ?? snapshot.lastError?.message ?? 'Playback could not continue.'
      : null,
    retryVisible,
    guideVisible,
    retryBusy: state.retryPending,
    currentChannel,
    nowPlaying: {
      ...(currentChannel?.currentProgram === undefined && snapshot.media === null ? {} : {
        title: snapshot.media?.title ?? currentChannel?.currentProgram?.title,
      }),
      ...(snapshot.media?.subtitle === undefined && currentChannel?.currentProgram?.subtitle === undefined ? {} : {
        subtitle: snapshot.media?.subtitle ?? currentChannel?.currentProgram?.subtitle,
      }),
      ...(currentChannel === null ? {} : { channelLabel: `${currentChannel.number} ${currentChannel.name}` }),
      statusLabel: snapshot.playing ? 'Playing' : statusLabel(snapshot.status),
      positionLabel: formatDuration(positionMs),
      durationLabel: durationMs === 0 ? '--:--' : formatDuration(durationMs),
      progressPercent,
      ...(currentChannel?.nextProgram === undefined ? {} : {
        upNextText: `Up next: ${currentChannel.nextProgram.title}`,
      }),
    },
    playerOsd: {
      statusLabel: osdStatus(snapshot),
      ...(snapshot.media?.title === undefined && currentChannel?.currentProgram?.title === undefined ? {} : {
        title: snapshot.media?.title ?? currentChannel?.currentProgram?.title,
      }),
      ...(snapshot.media?.subtitle === undefined && currentChannel?.currentProgram?.subtitle === undefined ? {} : {
        subtitle: snapshot.media?.subtitle ?? currentChannel?.currentProgram?.subtitle,
      }),
      timecode: `${formatDuration(positionMs)} / ${durationMs === 0 ? '--:--' : formatDuration(durationMs)}`,
      playedPercent: progressPercent,
      bufferedPercent: durationMs === 0 ? 0 : Math.min(100, Math.round((bufferEnd / durationMs) * 100)),
      audioEligible: isAudioControlEligible(snapshot),
      subtitleEligible: isSubtitleControlEligible(snapshot),
      ...(selectedTrackLabel(snapshot, 'audio') === undefined ? {} : { audioLabel: selectedTrackLabel(snapshot, 'audio') }),
      ...(selectedTrackLabel(snapshot, 'subtitle') === undefined ? {} : { subtitleLabel: selectedTrackLabel(snapshot, 'subtitle') }),
    },
    miniGuideChannels: fiveCircularRows(presentation.channels, selectedChannel?.id ?? null).map((channel) => ({
      ...channel,
      selected: channel.id === selectedChannel?.id,
      busy: channel.id === state.pendingTuneChannelId,
    })),
    miniGuideError: state.miniGuideError,
    channelNumberDisplay: state.channelNumberBuffer.length === 0
      ? '---'
      : state.channelNumberBuffer.padEnd(3, '_'),
    channelNumberStatus: state.channelNumberStatus,
    channelNumberMessage: state.channelNumberMessage,
    playbackOptions: options,
    transitionLabel: state.transitionChannelId === null
      ? null
      : presentation.channels.find((channel) => channel.id === state.transitionChannelId)?.number ?? null,
  };
}

export function activeOverlayId(state: PlayerOverlayState): PlayerOverlayId | null {
  return state.activeOverlayId;
}

function createPlaybackOptions(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot,
): PlaybackOptionsViewModel {
  const family = state.playbackOptionsFamily ?? 'audio';
  const tracks = family === 'audio'
    ? availableTracks(snapshot, 'audio').map((track) => option(track.id, track.id, track.label, track.selected, trackMeta(track), state))
    : [
        option('off', null, 'Off', snapshot.selectedSubtitleTrackId === null, undefined, state),
        ...availableTracks(snapshot, 'subtitle').map((track) => option(track.id, track.id, track.label, track.selected, trackMeta(track), state)),
      ];
  return { family, tracks, error: state.playbackOptionsError };
}

function option(
  id: string,
  trackId: string | null,
  label: string,
  selected: boolean,
  meta: string | undefined,
  state: PlayerOverlayState,
): PlaybackOptionTrackViewModel {
  const focusId = `overlay-${state.playbackOptionsFamily ?? 'audio'}-track-${id}`;
  return {
    id,
    trackId,
    label,
    selected,
    ...(meta === undefined ? {} : { meta }),
    focusId,
    busy: state.pendingTrackFocusId === focusId,
  };
}

function baselineFor(status: PlayerStatus, retainingOsd: boolean): 'native' | 'loading' | 'error' {
  switch (status) {
    case 'loading':
    case 'buffering':
    case 'stalled':
      return 'loading';
    case 'seeking':
      return retainingOsd ? 'native' : 'loading';
    case 'error':
    case 'destroyed':
      return 'error';
    case 'idle':
    case 'ready':
    case 'playing':
    case 'paused':
    case 'ended':
      return 'native';
  }
}

function osdStatus(snapshot: PlayerSnapshot): string {
  if (snapshot.status === 'buffering') return 'BUFFERING';
  if (snapshot.playing) return 'PLAYING';
  if (snapshot.status === 'paused') return 'PAUSED';
  return snapshot.status.toUpperCase();
}

function focusIdFor(
  active: PlayerOverlayId | null,
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot,
  retryVisible: boolean,
  guideVisible: boolean,
): string | null {
  if (active === 'playerOsd') {
    if (isAudioControlEligible(snapshot)) return 'overlay-osd-audio';
    if (isSubtitleControlEligible(snapshot)) return 'overlay-osd-subtitles';
  }
  if (active === 'miniGuide') return state.miniGuideSelectedChannelId === null
    ? null
    : `overlay-mini-channel-${encodeURIComponent(state.miniGuideSelectedChannelId)}`;
  if (active === 'playbackOptions') return state.pendingTrackFocusId ?? state.playbackOptionsFocusId;
  if (active === 'playerError' && retryVisible) return 'overlay-player-retry';
  if (active === 'playerError' && guideVisible) return 'overlay-player-guide';
  return null;
}

function fiveCircularRows(
  channels: readonly OverlayChannelViewModel[],
  selectedId: string | null,
): readonly OverlayChannelViewModel[] {
  if (channels.length === 0) return [];
  const center = Math.max(0, channels.findIndex((channel) => channel.id === selectedId));
  return [-2, -1, 0, 1, 2].map((offset) => {
    const index = (center + offset + channels.length * 2) % channels.length;
    return channels[index] as OverlayChannelViewModel;
  });
}

function emptyVisibility(): Record<PlayerOverlayId, boolean> {
  return {
    playerOsd: false,
    nowPlaying: false,
    miniGuide: false,
    channelNumber: false,
    channelBadge: false,
    playbackOptions: false,
    transition: false,
    playerLoading: false,
    playerError: false,
  };
}

function stackFromVisibility(visible: Readonly<Record<PlayerOverlayId, boolean>>): PlayerOverlayId[] {
  const order: readonly PlayerOverlayId[] = [
    'playerLoading', 'transition', 'channelNumber', 'playerOsd', 'miniGuide',
    'nowPlaying', 'playbackOptions', 'playerError', 'channelBadge',
  ];
  return order.filter((id) => visible[id]);
}
