import type { PlayerSnapshot, PlayerStatus } from '../contracts/player.js';

export type PlayerOverlayId =
  | 'playerOsd'
  | 'nowPlaying'
  | 'miniGuide'
  | 'channelNumber'
  | 'channelBadge'
  | 'playbackOptions';

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
}

export interface PlaybackOptionsViewModel {
  volumePercent: number;
  muted: boolean;
  playbackRateLabel: string;
  audioTracks: readonly PlaybackOptionTrackViewModel[];
  subtitleTracks: readonly PlaybackOptionTrackViewModel[];
  selectedAudioLabel: string;
  selectedSubtitleLabel: string;
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

export const PLAYER_OVERLAY_IDLE_FOCUS_ID = 'player-osd';

const CHANNEL_NUMBER_BUFFER_TIMEOUT_MS = 2_500;
const CHANNEL_NUMBER_MAX_LENGTH = 3;

const PLAYER_OVERLAY_IDS = [
  'playerOsd',
  'nowPlaying',
  'miniGuide',
  'channelNumber',
  'channelBadge',
  'playbackOptions',
] as const satisfies readonly PlayerOverlayId[];

const NON_MODAL_OVERLAYS = new Set<PlayerOverlayId>(['channelBadge', 'nowPlaying']);

const FAKE_OVERLAY_CHANNELS = [
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
    name: 'Weekend Queue',
    currentTitle: 'Pilot Block',
    nextTitle: 'Comfort Marathon',
  },
] as const satisfies readonly OverlayChannelViewModel[];

const PLAYBACK_AUDIO_TRACKS = [
  { id: 'audio-main', label: 'Main stereo' },
  { id: 'audio-commentary', label: 'Commentary' },
] as const;

const PLAYBACK_SUBTITLE_TRACKS = [
  { id: null, label: 'Off' },
  { id: 'subtitle-english', label: 'English' },
  { id: 'subtitle-sdh', label: 'English SDH' },
] as const;

export function createPlayerOverlayState(): PlayerOverlayState {
  return {
    stack: ['channelBadge', 'nowPlaying', 'playerOsd'],
    miniGuideSelectedChannelId: FAKE_OVERLAY_CHANNELS[0].id,
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
): PlayerOverlayState {
  switch (actionId) {
    case 'toggleOsd':
      return toggleOverlay(state, 'playerOsd');
    case 'openMiniGuide':
      return showChannelBadge(openOverlay(state, 'miniGuide'));
    case 'previousMiniGuideChannel':
      return selectMiniGuideChannel(state, -1);
    case 'nextMiniGuideChannel':
      return selectMiniGuideChannel(state, 1);
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
      return commitChannelNumber(state);
    case 'clearChannelNumber':
      return {
        ...removeOverlay(state, 'channelNumber'),
        channelNumberBuffer: '',
        channelNumberUpdatedAtMs: null,
      };
    case 'closeTopOverlay':
      return closeTopOverlay(state);
    default:
      return appendChannelNumberDigit(state, readChannelDigit(actionId), nowMs);
  }
}

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

export function resolvePlayerOverlayFocusId(view: PlayerOverlayViewModel): string {
  return view.activeFocusId ?? PLAYER_OVERLAY_IDLE_FOCUS_ID;
}

function createNowPlayingSummary(
  snapshot: PlayerSnapshot,
  channel: OverlayChannelViewModel,
): NowPlayingOverlayViewModel {
  const durationMs = snapshot.durationMs ?? snapshot.media?.durationMs ?? 0;
  const positionMs = Math.min(snapshot.positionMs, durationMs);
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
    available: true,
  }));
  const subtitleTracks = PLAYBACK_SUBTITLE_TRACKS.map((track) => ({
    id: track.id ?? 'subtitles-off',
    label: track.label,
    selected: track.id === state.selectedSubtitleTrackId,
    available: true,
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
  };
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

function commitChannelNumber(state: PlayerOverlayState): PlayerOverlayState {
  const channel = FAKE_OVERLAY_CHANNELS.find(
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
    miniGuideSelectedChannelId: channel.id,
  });
}

function selectMiniGuideChannel(state: PlayerOverlayState, offset: number): PlayerOverlayState {
  const currentIndex = Math.max(
    0,
    FAKE_OVERLAY_CHANNELS.findIndex((channel) => channel.id === state.miniGuideSelectedChannelId),
  );
  const nextIndex = Math.max(0, Math.min(FAKE_OVERLAY_CHANNELS.length - 1, currentIndex + offset));
  return showChannelBadge(
    openOverlay(
      {
        ...state,
        miniGuideSelectedChannelId: FAKE_OVERLAY_CHANNELS[nextIndex].id,
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
  return state.stack.includes('channelBadge') ? state : { ...state, stack: ['channelBadge', ...state.stack] };
}

function closeTopOverlay(state: PlayerOverlayState): PlayerOverlayState {
  const overlayId = activeOverlayId(state);
  return overlayId === null ? state : removeOverlay(state, overlayId);
}

function activeOverlayId(state: PlayerOverlayState): PlayerOverlayId | null {
  return [...state.stack].reverse().find((overlayId) => !NON_MODAL_OVERLAYS.has(overlayId)) ?? null;
}

function activeFocusId(state: PlayerOverlayState): string | null {
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

function nextAudioTrackId(currentTrackId: string): string {
  const currentIndex = Math.max(
    0,
    PLAYBACK_AUDIO_TRACKS.findIndex((track) => track.id === currentTrackId),
  );
  return PLAYBACK_AUDIO_TRACKS[(currentIndex + 1) % PLAYBACK_AUDIO_TRACKS.length].id;
}

function nextSubtitleTrackId(currentTrackId: string | null): string | null {
  const currentIndex = Math.max(
    0,
    PLAYBACK_SUBTITLE_TRACKS.findIndex((track) => track.id === currentTrackId),
  );
  return PLAYBACK_SUBTITLE_TRACKS[(currentIndex + 1) % PLAYBACK_SUBTITLE_TRACKS.length].id;
}

function findChannel(channelId: string): OverlayChannelViewModel | undefined {
  return FAKE_OVERLAY_CHANNELS.find((channel) => channel.id === channelId);
}

function readChannelDigit(actionId: PlayerOverlayActionId): string {
  return actionId.replace('channelDigit', '');
}

function clampVolume(value: number): number {
  return Math.max(0, Math.min(1, Number(value.toFixed(2))));
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
