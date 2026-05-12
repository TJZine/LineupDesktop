import type { PlexMediaItemMinimal } from './interfaces.js';
import type { ResolvedContentItem } from './types.js';

type PlexStreamMinimal = NonNullable<
  NonNullable<NonNullable<PlexMediaItemMinimal['media']>[number]['parts']>[number]['streams']
>[number];

type ParentEpisodeMetadata = {
  genres?: string[] | undefined;
  directors?: string[] | undefined;
  contentRating?: string | undefined;
  rating?: number | undefined;
  year?: number | undefined;
  grandparentTitle?: string | undefined;
  grandparentThumb?: string | null | undefined;
  art?: string | null | undefined;
  clearLogo?: string | null | undefined;
};

export class ContentItemMapper {
  public toResolvedItem(item: PlexMediaItemMinimal, index: number): ResolvedContentItem {
    const resolved: ResolvedContentItem = {
      ratingKey: item.ratingKey,
      type: item.type,
      title: item.title,
      fullTitle: this.buildFullTitle(item),
      durationMs: item.durationMs,
      thumb: item.thumb,
      year: item.year,
      scheduledIndex: index,
    };

    if (typeof item.seasonNumber === 'number') resolved.seasonNumber = item.seasonNumber;
    if (typeof item.episodeNumber === 'number') resolved.episodeNumber = item.episodeNumber;
    if (item.grandparentTitle) resolved.showTitle = item.grandparentTitle;
    if (item.grandparentThumb) resolved.showThumb = item.grandparentThumb;
    if (item.art !== undefined) resolved.art = item.art;
    if (item.clearLogo) resolved.clearLogo = item.clearLogo;
    if (typeof item.rating === 'number') resolved.rating = item.rating;
    if (item.contentRating) resolved.contentRating = item.contentRating;
    if (item.genres && item.genres.length > 0) resolved.genres = [...item.genres];
    if (item.directors && item.directors.length > 0) resolved.directors = [...item.directors];
    if (item.summary && item.summary.trim().length > 0) resolved.summary = item.summary;
    const mediaInfo = this.buildMediaInfo(item);
    if (mediaInfo) resolved.mediaInfo = mediaInfo;
    if (typeof item.viewCount === 'number') resolved.watched = item.viewCount > 0;
    if (typeof item.addedAtMs === 'number') resolved.addedAt = item.addedAtMs;

    return resolved;
  }

  public decorateEpisodeFromParent(
    episode: PlexMediaItemMinimal,
    parent: ParentEpisodeMetadata,
  ): PlexMediaItemMinimal {
    const merged: PlexMediaItemMinimal = { ...episode };

    if (!merged.genres && parent.genres) merged.genres = [...parent.genres];
    if (!merged.directors && parent.directors) merged.directors = [...parent.directors];
    if (!merged.contentRating && parent.contentRating) merged.contentRating = parent.contentRating;
    if (!merged.rating && typeof parent.rating === 'number') merged.rating = parent.rating;
    if (!merged.year && parent.year) merged.year = parent.year;
    if (!merged.grandparentTitle && parent.grandparentTitle) merged.grandparentTitle = parent.grandparentTitle;
    if (!merged.grandparentThumb && parent.grandparentThumb) merged.grandparentThumb = parent.grandparentThumb;
    if (merged.art == null && parent.art) merged.art = parent.art;
    if (!merged.clearLogo && parent.clearLogo) merged.clearLogo = parent.clearLogo;

    return merged;
  }

  private buildMediaInfo(item: PlexMediaItemMinimal): ResolvedContentItem['mediaInfo'] | undefined {
    const media = item.media?.[0];
    if (!media) return undefined;

    const mediaInfo: ResolvedContentItem['mediaInfo'] = {};
    const resolution = normalizeResolution(media.videoResolution);
    if (resolution) mediaInfo.resolution = resolution;

    const streams = media.parts?.[0]?.streams ?? [];
    const videoStream = streams.find((stream) => stream.streamType === 1);
    const hdr = detectHdrLabel(videoStream);
    if (hdr) mediaInfo.hdr = hdr;
    if (hdr === 'Dolby Vision') {
      const dvProfile = videoStream?.doviProfile ?? videoStream?.profile;
      if (dvProfile) mediaInfo.dvProfile = dvProfile;
    }

    const audioStream = selectAudioStream(streams);
    if (audioStream?.codec) mediaInfo.audioCodec = audioStream.codec;
    if (typeof audioStream?.channels === 'number') mediaInfo.audioChannels = audioStream.channels;
    if (!mediaInfo.audioCodec && media.audioCodec) mediaInfo.audioCodec = media.audioCodec;
    if (mediaInfo.audioChannels === undefined && typeof media.audioChannels === 'number') {
      mediaInfo.audioChannels = media.audioChannels;
    }
    const audioTitle = audioStream?.title || audioStream?.language || audioStream?.languageCode;
    if (audioTitle) mediaInfo.audioTrackTitle = audioTitle;

    return Object.keys(mediaInfo).length > 0 ? mediaInfo : undefined;
  }

  private buildFullTitle(item: PlexMediaItemMinimal): string {
    if (item.type === 'episode') {
      const showTitle = item.grandparentTitle || '';
      const seasonNum = item.seasonNumber;
      const epNum = item.episodeNumber;
      const seasonStr = typeof seasonNum === 'number' ? `S${String(seasonNum).padStart(2, '0')}` : '';
      const epStr = typeof epNum === 'number' ? `E${String(epNum).padStart(2, '0')}` : '';
      const episodeCode = seasonStr && epStr ? `${seasonStr}${epStr}` : '';

      if (showTitle && episodeCode) {
        return `${showTitle} - ${episodeCode} - ${item.title}`;
      }
      if (showTitle) {
        return `${showTitle} - ${item.title}`;
      }
    }

    return item.title;
  }
}

export type ContentResolverMapper = Pick<
  ContentItemMapper,
  'toResolvedItem' | 'decorateEpisodeFromParent'
>;

function normalizeResolution(resolution?: string): string | undefined {
  if (!resolution) return undefined;
  const normalized = resolution.trim().toLowerCase();
  if (normalized === '4k' || normalized === 'uhd' || normalized === '2160' || normalized === '2160p') {
    return '4K';
  }
  if (normalized === '1080' || normalized === '1080p') return '1080p';
  if (normalized === '720' || normalized === '720p') return '720p';
  return resolution;
}

function detectHdrLabel(stream?: PlexStreamMinimal): string | undefined {
  const profile = `${stream?.profile ?? ''} ${stream?.displayTitle ?? ''} ${stream?.extendedDisplayTitle ?? ''}`.toLowerCase();
  if (stream?.doviProfile || profile.includes('dolby vision') || profile.includes('dovi')) {
    return 'Dolby Vision';
  }
  if (
    profile.includes('hdr10') ||
    profile.includes('hdr') ||
    stream?.colorTrc === 'smpte2084' ||
    stream?.colorSpace === 'bt2020nc' ||
    stream?.colorPrimaries === 'bt2020'
  ) {
    return 'HDR';
  }
  return undefined;
}

function selectAudioStream(streams: PlexStreamMinimal[]): PlexStreamMinimal | undefined {
  const audioStreams = streams.filter((stream) => stream.streamType === 2);
  if (audioStreams.length === 0) return undefined;
  return (
    audioStreams.find((stream) => stream.selected) ??
    audioStreams.find((stream) => stream.default) ??
    audioStreams[0]
  );
}
