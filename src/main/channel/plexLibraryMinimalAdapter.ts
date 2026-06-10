import type {
  ChannelAbortSignal,
  ChannelResolveOptions,
  DomainPlexMediaFile,
  DomainPlexMediaPart,
  DomainPlexMediaStream,
  IPlexLibraryMinimal,
  PlexMediaItemMinimal,
} from '../../domain/channel/interfaces.js';
import type { DomainPlexMediaType } from '../../domain/channel/types.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import {
  extractMetadataArray,
  parseMediaItems,
  type PlexMediaItem,
  type RawMediaItem,
} from '../plex/library/index.js';
import { payloadAsContainer } from '../plex/desktopPlexRuntimeSupport.js';
import { LivePlexTransportError } from '../plex/livePlexTransport.js';

export class PlexLibraryMinimalAdapter implements IPlexLibraryMinimal {
  private readonly runtime: DesktopPlexRuntime;

  constructor(runtime: DesktopPlexRuntime) {
    this.runtime = runtime;
  }

  async getLibraryItems(
    libraryId: string,
    options?: {
      includeCollections?: boolean;
      filter?: Record<string, string | number>;
      signal?: ChannelAbortSignal | null;
    },
  ): Promise<PlexMediaItemMinimal[]> {
    const { connection, token } = this.runtime.getActiveConnectionAndToken();
    if (!connection || !token) {
      throw new Error('Plex authentication or server selection is missing');
    }
    const transport = this.runtime.getLibraryTransport();
    const items: RawMediaItem[] = [];
    let offset = 0;
    const limit = 50;
    let iterations = 0;

    while (true) {
      if (++iterations > 1000) {
        throw new Error('Pagination limit exceeded');
      }
      const payload = await transport.listLibraryItems({
        connection,
        token,
        sectionId: libraryId,
        offset,
        limit,
        filter: options?.filter,
        includeCollections: options?.includeCollections,
        signal: options?.signal as AbortSignal | null,
      });
      const pageItems = extractMetadataArray<RawMediaItem>(
        payloadAsContainer<RawMediaItem>(payload),
        'library items',
      );
      items.push(...pageItems);
      if (pageItems.length < limit) {
        break;
      }
      offset += pageItems.length;
    }
    return parseMediaItems(items).map(toDomainMediaItem);
  }

  async getCollectionItems(
    collectionKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]> {
    const { connection, token } = this.runtime.getActiveConnectionAndToken();
    if (!connection || !token) {
      throw new Error('Plex authentication or server selection is missing');
    }
    const transport = this.runtime.getLibraryTransport();
    const payload = await transport.getCollectionItems({
      connection,
      token,
      collectionKey,
      signal: options?.signal as AbortSignal | null,
    });
    const items = extractMetadataArray<RawMediaItem>(
      payloadAsContainer<RawMediaItem>(payload),
      'collection items',
    );
    return parseMediaItems(items).map(toDomainMediaItem);
  }

  async getShowEpisodes(
    showKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]> {
    const { connection, token } = this.runtime.getActiveConnectionAndToken();
    if (!connection || !token) {
      throw new Error('Plex authentication or server selection is missing');
    }
    const transport = this.runtime.getLibraryTransport();
    const payload = await transport.getShowEpisodes({
      connection,
      token,
      showKey,
      signal: options?.signal as AbortSignal | null,
    });
    const items = extractMetadataArray<RawMediaItem>(
      payloadAsContainer<RawMediaItem>(payload),
      'show episodes',
    );
    return parseMediaItems(items).map(toDomainMediaItem);
  }

  async getPlaylistItems(
    playlistKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]> {
    const { connection, token } = this.runtime.getActiveConnectionAndToken();
    if (!connection || !token) {
      throw new Error('Plex authentication or server selection is missing');
    }
    const transport = this.runtime.getLibraryTransport();
    const payload = await transport.getPlaylistItems({
      connection,
      token,
      playlistKey,
      signal: options?.signal as AbortSignal | null,
    });
    const items = extractMetadataArray<RawMediaItem>(
      payloadAsContainer<RawMediaItem>(payload),
      'playlist items',
    );
    return parseMediaItems(items).map(toDomainMediaItem);
  }

  async getItem(
    ratingKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal | null> {
    const { connection, token } = this.runtime.getActiveConnectionAndToken();
    if (!connection || !token) {
      throw new Error('Plex authentication or server selection is missing');
    }
    const transport = this.runtime.getLibraryTransport();
    try {
      const payload = await transport.getMetadata({
        connection,
        token,
        ratingKey,
        signal: options?.signal as AbortSignal | null,
      });
      const items = extractMetadataArray<RawMediaItem>(
        payloadAsContainer<RawMediaItem>(payload),
        'metadata',
      );
      const parsed = parseMediaItems(items);
      if (parsed.length === 0 || !parsed[0]) {
        return null;
      }
      return toDomainMediaItem(parsed[0]);
    } catch (error) {
      if (error instanceof LivePlexTransportError && error.code === 'resource-not-found') {
        return null;
      }
      throw error;
    }
  }
}

function toDomainMediaItem(item: PlexMediaItem): PlexMediaItemMinimal {
  const media: DomainPlexMediaFile[] | undefined = item.media?.map((m) => {
    const parts: DomainPlexMediaPart[] = m.parts?.map((p) => {
      const streams: DomainPlexMediaStream[] = p.streams?.map((s) => {
        return {
          streamType: s.streamType,
          codec: s.codec,
          channels: s.channels,
          title: s.title,
          language: s.language,
          languageCode: s.languageCode,
          selected: s.selected,
          default: s.default,
          profile: s.profile,
          doviProfile: s.doviProfile,
          colorTrc: s.colorTrc,
          colorSpace: s.colorSpace,
          colorPrimaries: s.colorPrimaries,
          displayTitle: s.displayTitle,
          extendedDisplayTitle: s.extendedDisplayTitle,
        };
      }) ?? [];
      return { streams };
    }) ?? [];
    return {
      videoResolution: m.videoResolution,
      audioCodec: m.audioCodec,
      audioChannels: m.audioChannels,
      parts,
    };
  });

  return {
    ratingKey: item.ratingKey,
    type: item.type as DomainPlexMediaType,
    title: item.title,
    year: item.year,
    durationMs: item.durationMs,
    thumb: item.thumb,
    art: item.art,
    grandparentThumb: item.grandparentThumb,
    summary: item.summary,
    grandparentTitle: item.grandparentTitle,
    parentTitle: item.parentTitle,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    rating: item.rating,
    contentRating: item.contentRating,
    genres: item.genres,
    directors: item.directors,
    addedAtMs: item.addedAt?.getTime(),
    viewCount: item.viewCount,
    clearLogo: item.clearLogo,
    grandparentRatingKey: item.grandparentRatingKey,
    parentRatingKey: item.parentRatingKey,
    media,
  };
}
