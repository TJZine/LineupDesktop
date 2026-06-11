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
  PLEX_LIBRARY_CONSTANTS,
  PlexLibraryError,
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
    return this.runtime.withActiveLibraryContext('listLibraryItems', async ({ connection, token, transport }) => {
      const mappedSignal = mapChannelSignalToAbortSignal(options?.signal);
      const items: RawMediaItem[] = [];
      let offset = 0;
      const limit = 50;
      let iterations = 0;

      try {
        while (true) {
          if (++iterations > PLEX_LIBRARY_CONSTANTS.MAX_PAGINATION_ITERATIONS) {
            throw new PlexLibraryError(
              'pagination-limit-exceeded',
              'Plex library pagination limit was exceeded in PlexLibraryMinimalAdapter.getLibraryItems',
            );
          }
          const payload = await transport.listLibraryItems({
            connection,
            token,
            sectionId: libraryId,
            offset,
            limit,
            filter: options?.filter,
            includeCollections: options?.includeCollections,
            signal: mappedSignal.signal,
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
      } finally {
        mappedSignal.cleanup();
      }
      return parseMediaItems(items).map(toDomainMediaItem);
    });
  }

  async getCollectionItems(
    collectionKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]> {
    return this.runtime.withActiveLibraryContext('listLibraryItems', async ({ connection, token, transport }) => {
      const mappedSignal = mapChannelSignalToAbortSignal(options?.signal);
      try {
        const payload = await transport.getCollectionItems({
          connection,
          token,
          collectionKey,
          signal: mappedSignal.signal,
        });
        const items = extractMetadataArray<RawMediaItem>(
          payloadAsContainer<RawMediaItem>(payload),
          'collection items',
        );
        return parseMediaItems(items).map(toDomainMediaItem);
      } finally {
        mappedSignal.cleanup();
      }
    });
  }

  async getShowEpisodes(
    showKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]> {
    return this.runtime.withActiveLibraryContext('listLibraryItems', async ({ connection, token, transport }) => {
      const mappedSignal = mapChannelSignalToAbortSignal(options?.signal);
      try {
        const payload = await transport.getShowEpisodes({
          connection,
          token,
          showKey,
          signal: mappedSignal.signal,
        });
        const items = extractMetadataArray<RawMediaItem>(
          payloadAsContainer<RawMediaItem>(payload),
          'show episodes',
        );
        return parseMediaItems(items).map(toDomainMediaItem);
      } finally {
        mappedSignal.cleanup();
      }
    });
  }

  async getPlaylistItems(
    playlistKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]> {
    return this.runtime.withActiveLibraryContext('listLibraryItems', async ({ connection, token, transport }) => {
      const mappedSignal = mapChannelSignalToAbortSignal(options?.signal);
      try {
        const payload = await transport.getPlaylistItems({
          connection,
          token,
          playlistKey,
          signal: mappedSignal.signal,
        });
        const items = extractMetadataArray<RawMediaItem>(
          payloadAsContainer<RawMediaItem>(payload),
          'playlist items',
        );
        return parseMediaItems(items).map(toDomainMediaItem);
      } finally {
        mappedSignal.cleanup();
      }
    });
  }

  async getItem(
    ratingKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal | null> {
    return this.runtime.withActiveLibraryContext('getMetadata', async ({ connection, token, transport }) => {
      const mappedSignal = mapChannelSignalToAbortSignal(options?.signal);
      try {
        const payload = await transport.getMetadata({
          connection,
          token,
          ratingKey,
          signal: mappedSignal.signal,
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
      } finally {
        mappedSignal.cleanup();
      }
    });
  }
}

function mapChannelSignalToAbortSignal(signal?: ChannelAbortSignal | null): {
  signal: AbortSignal | null;
  cleanup: () => void;
} {
  if (!signal) {
    return { signal: null, cleanup: () => undefined };
  }
  if (typeof AbortSignal !== 'undefined' && signal instanceof AbortSignal) {
    return { signal, cleanup: () => undefined };
  }
  const controller = new AbortController();
  if (signal.aborted) {
    controller.abort();
    return { signal: controller.signal, cleanup: () => undefined };
  }
  const abort = () => {
    controller.abort();
  };
  signal.addEventListener?.('abort', abort, { once: true });
  return {
    signal: controller.signal,
    cleanup: () => {
      signal.removeEventListener?.('abort', abort);
    },
  };
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
