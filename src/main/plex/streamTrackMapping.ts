import type { PlayerTrackId } from '../../contracts/player.js';
import type { PlexMediaPart } from './library/types.js';
import type { DesktopStreamMediaCandidate } from '../player/streamPolicy/types.js';

export interface TrackMappingItem {
  publicTrackId: PlayerTrackId;
  privateTrackId: string | null;
}

export interface VideoTrackMapItem extends TrackMappingItem {
  codec: string | null;
  dynamicRange: string;
}

export interface AudioTrackMapItem extends TrackMappingItem {
  label?: string;
  language?: string;
  codec?: string;
  channelCount?: number;
  default?: boolean;
}

export interface SubtitleTrackMapItem extends TrackMappingItem {
  label?: string;
  language?: string;
  format?: string;
  deliveryType?: string;
  forced?: boolean;
  default?: boolean;
}

export interface PlaybackTrackMap {
  video: readonly VideoTrackMapItem[];
  audio: readonly AudioTrackMapItem[];
  subtitle: readonly SubtitleTrackMapItem[];
}

export function buildPlaybackTrackMap(
  part: PlexMediaPart,
  candidate: DesktopStreamMediaCandidate,
): PlaybackTrackMap {
  const videoStreams = part.streams.filter((s) => s.streamType === 1);
  const audioStreams = part.streams.filter((s) => s.streamType === 2);
  const subtitleStreams = part.streams.filter((s) => s.streamType === 3);

  const videoMap: VideoTrackMapItem[] = [
    {
      publicTrackId: candidate.video.id,
      privateTrackId: videoStreams[0]?.id ?? null,
      codec: candidate.video.codec ?? null,
      dynamicRange: candidate.video.dynamicRange ?? 'unknown',
    },
  ];

  const audioMap: AudioTrackMapItem[] = candidate.audioTracks.map((track, index) => {
    return {
      publicTrackId: track.id,
      privateTrackId: audioStreams[index]?.id ?? null,
      label: track.label,
      language: track.language,
      codec: track.codec ?? undefined,
      channelCount: track.channelCount,
      default: track.default,
    };
  });

  const subtitleMap: SubtitleTrackMapItem[] = candidate.subtitleTracks.map((track, index) => {
    const stream = subtitleStreams[index];
    return {
      publicTrackId: track.id,
      privateTrackId: stream?.id ?? null,
      label: track.label,
      language: track.language,
      format: track.format,
      deliveryType: track.delivery,
      forced: track.forced,
      default: track.default,
    };
  });

  return {
    video: videoMap,
    audio: audioMap,
    subtitle: subtitleMap,
  };
}

export function findPrivateIdFromMap(
  publicTrackId: PlayerTrackId | null,
  map: readonly TrackMappingItem[],
): string | null {
  if (publicTrackId === null) {
    return null;
  }
  const item = map.find((x) => x.publicTrackId === publicTrackId);
  return item?.privateTrackId ?? null;
}
