import type { PlayerSnapshot, PlayerStatus } from '../contracts/player.js';
import {
  findChannel,
  formatDuration,
  statusLabel,
  DEFAULT_PLAYER_OVERLAY_PRESENTATION,
  EMPTY_PLAYER_OVERLAY_CHANNEL,
} from './overlayViewModelHelpers.js';

export {
  createRendererSafePlayerSnapshot,
  getDefaultOverlayPresentationChannels,
  DEFAULT_PLAYER_OVERLAY_PRESENTATION,
  PLAYBACK_AUDIO_TRACKS,
  PLAYBACK_SUBTITLE_TRACKS,
} from './overlayViewModelHelpers.js';

export type PlayerOverlayId =
  | 'playerOsd'
  | 'nowPlaying'
  | 'miniGuide'
  | 'channelNumber'
  | 'channelBadge'
  | 'playbackOptions';

export interface OverlayChannelViewModel {
  id: string;
  number: string;
  name: string;
  currentTitle: string;
  nextTitle: string;
  nowStartLabel: string;
  nowProgressPercent: number;
  buildStrategy: 'movies' | 'shows' | 'mixed';
}

export interface NowPlayingOverlayViewModel {
  title: string;
  subtitle: string;
  channelNumber: string;
  channelName: string;
  status: PlayerStatus;
  statusLabel: string;
  positionLabel: string;
  durationLabel: string;
  progressPercent: number;
  description: string;
  badges: readonly string[];
  metaLines: readonly string[];
  playbackSummary: string;
  upNextText: string;
}

export interface PlayerOsdViewModel {
  statusLabel: 'PLAYING' | 'PAUSED' | 'BUFFERING' | 'STOPPED' | 'ERROR';
  title: string;
  subtitle: string;
  timecode: string;
  endsAtText: string;
  bufferedPercent: number;
  playedPercent: number;
  audioLabel: string;
  subtitleLabel: string;
  upNextText: string;
  bufferText: string;
  actionIds: {
    subtitles: string;
    sleep: string;
    audio: string;
  };
}

export interface PlaybackOptionTrackViewModel {
  id: string;
  label: string;
  selected: boolean;
  available: boolean;
  meta: string;
  stateLabel: string;
}

export interface PlaybackOptionsViewModel {
  volumePercent: number;
  muted: boolean;
  playbackRateLabel: string;
  audioTracks: readonly PlaybackOptionTrackViewModel[];
  subtitleTracks: readonly PlaybackOptionTrackViewModel[];
  selectedAudioLabel: string;
  selectedSubtitleLabel: string;
  playbackSummary: string;
}

export interface PlayerOverlayState {
  stack: readonly PlayerOverlayId[];
  currentChannelId: string;
  miniGuideSelectedChannelId: string;
  channelNumberBuffer: string;
  channelNumberUpdatedAtMs: number | null;
  selectedAudioTrackId: string;
  selectedSubtitleTrackId: string | null;
  muted: boolean;
  volume: number;
  playbackRate: number;
}

export interface PlayerOverlayPresentationSource {
  channels: readonly OverlayChannelViewModel[];
  playerSnapshot: PlayerSnapshot;
}

export interface PlayerOverlayViewModel {
  stack: readonly PlayerOverlayId[];
  visibleOverlays: Readonly<Record<PlayerOverlayId, boolean>>;
  activeOverlayId: PlayerOverlayId | null;
  activeFocusId: string | null;
  nowPlaying: NowPlayingOverlayViewModel;
  playerOsd: PlayerOsdViewModel;
  miniGuideChannels: readonly (OverlayChannelViewModel & { selected: boolean })[];
  selectedMiniGuideChannel: OverlayChannelViewModel;
  channelBadge: OverlayChannelViewModel;
  channelNumberBuffer: string;
  channelNumberDisplay: string;
  playbackOptions: PlaybackOptionsViewModel;
}

export const PLAYER_OVERLAY_IDS = [
  'playerOsd',
  'nowPlaying',
  'miniGuide',
  'channelNumber',
  'channelBadge',
  'playbackOptions',
] as const satisfies readonly PlayerOverlayId[];

export function normalizePlayerOverlayPresentation(
  presentation: PlayerOverlayPresentationSource = DEFAULT_PLAYER_OVERLAY_PRESENTATION,
): PlayerOverlayPresentationSource {
  return presentation.channels.length > 0
    ? presentation
    : {
      ...presentation,
      channels: [EMPTY_PLAYER_OVERLAY_CHANNEL],
    };
}

export function createPlayerOverlayView(
  state: PlayerOverlayState,
  presentation: PlayerOverlayPresentationSource = DEFAULT_PLAYER_OVERLAY_PRESENTATION,
): PlayerOverlayViewModel {
  const { channels, playerSnapshot } = normalizePlayerOverlayPresentation(presentation);
  const selectedMiniGuideChannel =
    findChannel(state.miniGuideSelectedChannelId, channels) ?? channels[0];
  const currentChannel = findChannel(state.currentChannelId, channels) ?? channels[0];
  const visibleOverlays = Object.fromEntries(
    PLAYER_OVERLAY_IDS.map((overlayId) => [overlayId, state.stack.includes(overlayId)]),
  ) as Record<PlayerOverlayId, boolean>;

  return {
    stack: state.stack,
    visibleOverlays,
    activeOverlayId: activeOverlayId(state),
    activeFocusId: activeFocusId(state, playerSnapshot),
    nowPlaying: createNowPlayingSummary(playerSnapshot, currentChannel),
    playerOsd: createPlayerOsdSummary(state, playerSnapshot, currentChannel),
    miniGuideChannels: channels.map((channel) => ({
      ...channel,
      selected: channel.id === selectedMiniGuideChannel.id,
    })),
    selectedMiniGuideChannel,
    channelBadge: currentChannel,
    channelNumberBuffer: state.channelNumberBuffer,
    channelNumberDisplay:
      state.channelNumberBuffer.length === 0 ? '---' : state.channelNumberBuffer.padEnd(3, '-'),
    playbackOptions: createPlaybackOptionsView(state, playerSnapshot),
  };
}

export function activeOverlayId(state: PlayerOverlayState): PlayerOverlayId | null {
  return [...state.stack].reverse().find((overlayId) => !NON_MODAL_OVERLAYS.has(overlayId)) ?? null;
}

export function activeFocusId(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot = DEFAULT_PLAYER_OVERLAY_PRESENTATION.playerSnapshot,
): string | null {
  switch (activeOverlayId(state)) {
    case 'playerOsd':
      return 'overlay-mini-guide';
    case 'miniGuide':
      return 'overlay-mini-next';
    case 'channelNumber':
      return 'overlay-channel-commit';
    case 'playbackOptions': {
      if (snapshot.tracks.length > 0) {
        const firstAudio = snapshot.tracks.find((t) => t.kind === 'audio' && t.available);
        if (firstAudio) {
          return `overlay-audio-track-${firstAudio.id}`;
        }
        const firstSub = snapshot.tracks.find((t) => t.kind === 'subtitle' && t.available);
        if (firstSub) {
          return `overlay-subtitle-track-${firstSub.id}`;
        }
      }
      return 'overlay-subtitle-track-subtitles-off';
    }
    default:
      return null;
  }
}

export function createPlayerOverlayViewForBadge(
  currentChannel: OverlayChannelViewModel
): NowPlayingOverlayViewModel {
  return {
    title: currentChannel.currentTitle,
    subtitle: currentChannel.name,
    channelNumber: currentChannel.number,
    channelName: currentChannel.name,
    status: 'idle',
    statusLabel: 'Stopped',
    positionLabel: '0:00',
    durationLabel: '--:--',
    progressPercent: 0,
    description: '',
    badges: [],
    metaLines: [],
    playbackSummary: '',
    upNextText: `Up next: ${currentChannel.nextTitle}`,
  };
}

function createNowPlayingSummary(
  snapshot: PlayerSnapshot,
  channel: OverlayChannelViewModel,
): NowPlayingOverlayViewModel {
  const durationMs = Math.max(0, snapshot.durationMs ?? snapshot.media?.durationMs ?? 0);
  const positionMs = Math.min(Math.max(snapshot.positionMs ?? 0, 0), durationMs);
  return {
    title: snapshot.media?.title ?? channel.currentTitle,
    subtitle: snapshot.media?.subtitle ?? channel.name,
    channelNumber: channel.number,
    channelName: channel.name,
    status: snapshot.status,
    statusLabel: snapshot.playing ? 'Playing' : statusLabel(snapshot.status),
    positionLabel: formatDuration(positionMs),
    durationLabel: durationMs <= 0 ? '--:--' : formatDuration(durationMs),
    progressPercent: durationMs <= 0 ? 0 : Math.round((positionMs / durationMs) * 100),
    description: 'Renderer-safe now-playing details are visible without artwork URLs or private playback descriptors.',
    badges: ['TV-14', '1080p', 'Direct Play'],
    metaLines: [channel.name, snapshot.media?.container ?? 'Desktop playback', statusLabel(snapshot.status)],
    playbackSummary: 'Direct Play / Direct Stream / HLS Session',
    upNextText: `Up next: ${channel.nextTitle}`,
  };
}

function createPlayerOsdSummary(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot,
  channel: OverlayChannelViewModel,
): PlayerOsdViewModel {
  const nowPlaying = createNowPlayingSummary(snapshot, channel);
  return {
    statusLabel: snapshot.status === 'buffering'
      ? 'BUFFERING'
      : snapshot.status === 'error'
        ? 'ERROR'
        : snapshot.playing
          ? 'PLAYING'
          : snapshot.status === 'paused'
            ? 'PAUSED'
            : 'STOPPED',
    title: nowPlaying.title,
    subtitle: nowPlaying.subtitle,
    timecode: `${nowPlaying.positionLabel} / ${nowPlaying.durationLabel}`,
    endsAtText: 'Ends 9:30 PM',
    bufferedPercent: Math.max(nowPlaying.progressPercent, 32),
    playedPercent: nowPlaying.progressPercent,
    audioLabel: createPlaybackOptionsView(state, snapshot).selectedAudioLabel,
    subtitleLabel: createPlaybackOptionsView(state, snapshot).selectedSubtitleLabel,
    upNextText: `Next on ${channel.number}: ${channel.nextTitle}`,
    bufferText: snapshot.status === 'buffering' ? 'Buffering' : '',
    actionIds: {
      subtitles: 'overlay-subtitle-cycle',
      sleep: 'overlay-close',
      audio: 'overlay-audio-cycle',
    },
  };
}

function createPlaybackOptionsView(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot = DEFAULT_PLAYER_OVERLAY_PRESENTATION.playerSnapshot,
): PlaybackOptionsViewModel {
  const audioTracks = snapshot.tracks
    .filter((track) => track.kind === 'audio')
    .map((track) => {
      let meta = 'Available';
      if (track.codec) {
        meta = track.codec.toUpperCase();
        if (track.channelCount) {
          meta += ` ${track.channelCount}ch`;
        }
      }
      return {
        id: track.id,
        label: track.label,
        selected: track.selected,
        available: track.available,
        meta,
        stateLabel: track.selected ? 'Selected' : track.available ? 'Available' : 'Unavailable',
      };
    });

  const subtitleTracks = [
    {
      id: 'subtitles-off',
      label: 'Off',
      selected: snapshot.selectedSubtitleTrackId === null,
      available: true,
      meta: '',
      stateLabel: snapshot.selectedSubtitleTrackId === null ? 'Selected' : 'Available',
    },
    ...snapshot.tracks
      .filter((track) => track.kind === 'subtitle')
      .map((track) => {
        let meta = track.deliveryType === 'burned-in' ? 'Burn-in' : 'External';
        if (track.forced) {
          meta += ' (Forced)';
        }
        return {
          id: track.id,
          label: track.label,
          selected: track.selected,
          available: track.available,
          meta,
          stateLabel: track.selected ? 'Selected' : track.available ? 'Available' : 'Unavailable',
        };
      }),
  ];

  const selectedAudioLabel =
    audioTracks.find((track) => track.selected)?.label ?? 'None';
  const selectedSubtitleLabel =
    subtitleTracks.find((track) => track.selected)?.label ?? 'Off';

  let playbackSummary = 'Playback: Direct Play';
  if (snapshot.quality) {
    const q = snapshot.quality;
    const modeLabel =
      q.mode === 'direct-play'
        ? 'Direct Play'
        : q.mode === 'direct-stream'
          ? 'Direct Stream'
          : q.mode === 'transcode'
            ? 'Transcode'
            : 'Unknown Mode';
    let videoPart = q.videoCodec ? q.videoCodec.toUpperCase() : 'Unknown Video';
    if (q.sourceDynamicRange && q.sourceDynamicRange !== 'unknown') {
      videoPart += ` (${q.sourceDynamicRange.toUpperCase()})`;
    }
    const audioPart = q.audioCodec ? q.audioCodec.toUpperCase() : 'Unknown Audio';
    playbackSummary = `Playback: ${modeLabel} / Video: ${videoPart} / Audio: ${audioPart}`;
  }

  return {
    volumePercent: Math.round(snapshot.volume * 100),
    muted: snapshot.muted,
    playbackRateLabel: `${snapshot.playbackRate.toFixed(1)}x`,
    audioTracks,
    subtitleTracks,
    selectedAudioLabel,
    selectedSubtitleLabel,
    playbackSummary,
  };
}

const NON_MODAL_OVERLAYS = new Set<PlayerOverlayId>(['channelBadge', 'nowPlaying']);
