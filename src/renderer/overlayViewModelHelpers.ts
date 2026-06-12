import type { PlayerSnapshot, PlayerStatus } from '../contracts/player.js';
import type { OverlayChannelViewModel } from './overlayViewModels.js';

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

export const DEFAULT_OVERLAY_CHANNELS = [
  {
    id: 'channel-liminal-one',
    number: '101',
    name: 'Liminal One',
    currentTitle: 'The Midnight Archive',
    nextTitle: 'After Hours Cinema',
    nowStartLabel: '8:30 PM',
    nowProgressPercent: 25,
    buildStrategy: 'shows',
  },
  {
    id: 'channel-vault',
    number: '204',
    name: 'The Vault',
    currentTitle: 'Restored Feature',
    nextTitle: 'Director Notes',
    nowStartLabel: '8:00 PM',
    nowProgressPercent: 50,
    buildStrategy: 'movies',
  },
  {
    id: 'channel-weekend',
    number: '310',
    name: 'Weekend Queue With A Long Channel Name',
    currentTitle: 'Pilot Block',
    nextTitle: 'Comfort Marathon',
    nowStartLabel: '8:00 PM',
    nowProgressPercent: 10,
    buildStrategy: 'shows',
  },
  {
    id: 'channel-docs',
    number: '411',
    name: 'Documentary Shelf',
    currentTitle: 'Field Notes',
    nextTitle: 'Archive Interview',
    nowStartLabel: '8:00 PM',
    nowProgressPercent: 65,
    buildStrategy: 'mixed',
  },
  {
    id: 'channel-late',
    number: '512',
    name: 'Late Signal',
    currentTitle: 'HLS Session Sample',
    nextTitle: 'Subtitle Burn-in Demo',
    nowStartLabel: '8:00 PM',
    nowProgressPercent: 40,
    buildStrategy: 'movies',
  },
] as const satisfies readonly OverlayChannelViewModel[];

export const EMPTY_PLAYER_OVERLAY_CHANNEL = {
  id: 'channel-unavailable',
  number: '---',
  name: 'Unavailable',
  currentTitle: 'Program details unavailable',
  nextTitle: 'Guide data unavailable',
  nowStartLabel: '--:--',
  nowProgressPercent: 0,
  buildStrategy: 'mixed',
} as const satisfies OverlayChannelViewModel;

export const DEFAULT_PLAYER_OVERLAY_PRESENTATION = {
  channels: DEFAULT_OVERLAY_CHANNELS,
  playerSnapshot: createRendererSafePlayerSnapshot(),
} as const satisfies {
  channels: readonly OverlayChannelViewModel[];
  playerSnapshot: PlayerSnapshot;
};

export function createRendererSafePlayerSnapshot(): PlayerSnapshot {
  return {
    requestId: 'renderer-presentation-player',
    status: 'playing',
    media: {
      id: 'renderer-presentation-media',
      title: 'The Midnight Archive',
      subtitle: 'Episode 4 - Signal Lost',
      durationMs: 3_600_000,
      container: 'renderer-safe-presentation',
    },
    capabilityProfileId: 'renderer-presentation',
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
    quality: { mode: 'unknown', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unknown' },
    lastError: null,
  };
}

export function getDefaultOverlayPresentationChannels(): readonly OverlayChannelViewModel[] {
  return DEFAULT_OVERLAY_CHANNELS;
}

export function findChannel(
  channelId: string,
  channels: readonly OverlayChannelViewModel[],
): OverlayChannelViewModel | undefined {
  return channels.find((channel) => channel.id === channelId);
}

export function formatDuration(valueMs: number): string {
  const totalSeconds = Math.floor(valueMs / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = String(totalSeconds % 60).padStart(2, '0');
  return `${minutes}:${seconds}`;
}

export function statusLabel(status: PlayerStatus): string {
  return status
    .split('-')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}
