import type { PlayerSnapshot, PlayerStatus } from '../contracts/player.js';

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
  miniGuideSelectedChannelId: string;
  channelNumberBuffer: string;
  channelNumberUpdatedAtMs: number | null;
  selectedAudioTrackId: string;
  selectedSubtitleTrackId: string | null;
  muted: boolean;
  volume: number;
  playbackRate: number;
}

export interface PlayerOverlayViewModel {
  stack: readonly PlayerOverlayId[];
  visibleOverlays: Readonly<Record<PlayerOverlayId, boolean>>;
  activeOverlayId: PlayerOverlayId | null;
  activeFocusId: string | null;
  nowPlaying: NowPlayingOverlayViewModel;
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

export const FAKE_OVERLAY_CHANNELS = [
  {
    id: 'channel-liminal-one',
    number: '101',
    name: 'Liminal One',
    currentTitle: 'The Midnight Archive',
    nextTitle: 'After Hours Cinema',
  },
  {
    id: 'channel-vault',
    number: '204',
    name: 'The Vault',
    currentTitle: 'Restored Feature',
    nextTitle: 'Director Notes',
  },
  {
    id: 'channel-weekend',
    number: '310',
    name: 'Weekend Queue With A Long Channel Name',
    currentTitle: 'Pilot Block',
    nextTitle: 'Comfort Marathon',
  },
  {
    id: 'channel-docs',
    number: '411',
    name: 'Documentary Shelf',
    currentTitle: 'Field Notes',
    nextTitle: 'Archive Interview',
  },
  {
    id: 'channel-late',
    number: '512',
    name: 'Late Signal',
    currentTitle: 'HLS Session Sample',
    nextTitle: 'Subtitle Burn-in Demo',
  },
] as const satisfies readonly OverlayChannelViewModel[];

export const PLAYBACK_AUDIO_TRACKS = [
  { id: 'audio-main', label: 'Main stereo', meta: 'Direct Play', available: true },
  { id: 'audio-commentary', label: 'Commentary', meta: 'Audio Transcode', available: true },
  { id: 'audio-described', label: 'Descriptive audio', meta: 'Unavailable', available: false },
] as const;

export const PLAYBACK_SUBTITLE_TRACKS = [
  { id: null, label: 'Off', meta: 'Direct', available: true },
  { id: 'subtitle-english', label: 'English', meta: 'Extract', available: true },
  { id: 'subtitle-sdh', label: 'English SDH', meta: 'Burn-in', available: true },
  { id: 'subtitle-forced-missing', label: 'Forced track', meta: 'Unavailable', available: false },
] as const;

export function createPlayerOverlayView(
  state: PlayerOverlayState,
  snapshot: PlayerSnapshot = createFakePlayerSnapshot(),
): PlayerOverlayViewModel {
  const selectedMiniGuideChannel =
    findChannel(state.miniGuideSelectedChannelId) ?? FAKE_OVERLAY_CHANNELS[0];
  const visibleOverlays = Object.fromEntries(
    PLAYER_OVERLAY_IDS.map((overlayId) => [overlayId, state.stack.includes(overlayId)]),
  ) as Record<PlayerOverlayId, boolean>;

  return {
    stack: state.stack,
    visibleOverlays,
    activeOverlayId: activeOverlayId(state),
    activeFocusId: activeFocusId(state),
    nowPlaying: createNowPlayingSummary(snapshot, selectedMiniGuideChannel),
    miniGuideChannels: FAKE_OVERLAY_CHANNELS.map((channel) => ({
      ...channel,
      selected: channel.id === selectedMiniGuideChannel.id,
    })),
    selectedMiniGuideChannel,
    channelBadge: selectedMiniGuideChannel,
    channelNumberBuffer: state.channelNumberBuffer,
    channelNumberDisplay:
      state.channelNumberBuffer.length === 0 ? '---' : state.channelNumberBuffer.padEnd(3, '-'),
    playbackOptions: createPlaybackOptionsView(state),
  };
}

export function createFakePlayerSnapshot(): PlayerSnapshot {
  return {
    requestId: 'renderer-fake-player',
    status: 'playing',
    media: {
      id: 'renderer-fake-media',
      title: 'The Midnight Archive',
      subtitle: 'Episode 4 - Signal Lost',
      durationMs: 3_600_000,
      container: 'local-preview',
    },
    capabilityProfileId: 'renderer-local-preview',
    positionMs: 12 * 60 * 1000,
    durationMs: 3_600_000,
    bufferedRanges: [{ startMs: 0, endMs: 18 * 60 * 1000 }],
    playing: true,
    volume: 0.72,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: 'audio-main',
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: 'video-main',
    tracks: [
      {
        id: 'audio-main',
        kind: 'audio',
        label: 'Main stereo',
        language: 'en',
        codec: 'aac',
        deliveryType: 'embedded',
        selected: true,
        available: true,
      },
      {
        id: 'audio-commentary',
        kind: 'audio',
        label: 'Commentary',
        language: 'en',
        codec: 'aac',
        deliveryType: 'embedded',
        selected: false,
        available: true,
      },
      {
        id: 'subtitle-english',
        kind: 'subtitle',
        label: 'English',
        language: 'en',
        format: 'srt',
        deliveryType: 'sidecar',
        selected: false,
        available: true,
      },
    ],
    lastError: null,
  };
}

export function getFakeOverlayChannels(): readonly OverlayChannelViewModel[] {
  return FAKE_OVERLAY_CHANNELS;
}

export function activeOverlayId(state: PlayerOverlayState): PlayerOverlayId | null {
  return [...state.stack].reverse().find((overlayId) => !NON_MODAL_OVERLAYS.has(overlayId)) ?? null;
}

export function activeFocusId(state: PlayerOverlayState): string | null {
  switch (activeOverlayId(state)) {
    case 'playerOsd':
      return 'overlay-mini-guide';
    case 'miniGuide':
      return 'overlay-mini-next';
    case 'channelNumber':
      return 'overlay-channel-commit';
    case 'playbackOptions':
      return 'overlay-audio-cycle';
    default:
      return null;
  }
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
  };
}

function createPlaybackOptionsView(state: PlayerOverlayState): PlaybackOptionsViewModel {
  const audioTracks = PLAYBACK_AUDIO_TRACKS.map((track) => ({
    ...track,
    selected: track.id === state.selectedAudioTrackId,
    stateLabel: track.id === state.selectedAudioTrackId ? 'Selected' : track.available ? 'Available' : 'Unavailable',
  }));
  const subtitleTracks = PLAYBACK_SUBTITLE_TRACKS.map((track) => ({
    id: track.id ?? 'subtitles-off',
    label: track.label,
    selected: track.id === state.selectedSubtitleTrackId,
    available: track.available,
    meta: track.meta,
    stateLabel: track.id === state.selectedSubtitleTrackId ? 'Selected' : track.available ? 'Available' : 'Unavailable',
  }));
  const selectedAudioLabel =
    audioTracks.find((track) => track.selected)?.label ?? PLAYBACK_AUDIO_TRACKS[0].label;
  const selectedSubtitleLabel =
    subtitleTracks.find((track) => track.selected)?.label ?? PLAYBACK_SUBTITLE_TRACKS[0].label;

  return {
    volumePercent: Math.round(state.volume * 100),
    muted: state.muted,
    playbackRateLabel: `${state.playbackRate.toFixed(1)}x`,
    audioTracks,
    subtitleTracks,
    selectedAudioLabel,
    selectedSubtitleLabel,
    playbackSummary: 'Playback: Direct Play / Direct Stream / HLS Session / Audio Transcode / Video Transcode',
  };
}

function findChannel(channelId: string): OverlayChannelViewModel | undefined {
  return FAKE_OVERLAY_CHANNELS.find((channel) => channel.id === channelId);
}

function formatDuration(valueMs: number): string {
  const totalSeconds = Math.floor(valueMs / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = String(totalSeconds % 60).padStart(2, '0');
  return `${minutes}:${seconds}`;
}

function statusLabel(status: PlayerStatus): string {
  return status
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

const NON_MODAL_OVERLAYS = new Set<PlayerOverlayId>(['channelBadge', 'nowPlaying']);
