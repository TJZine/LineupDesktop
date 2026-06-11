import type { PlexMediaItem, RawMediaItem } from './library/index.js';
import type { PlexStreamResolverMediaDetailPort } from './streamResolver.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import { parseMediaItems, extractMetadataArray } from './library/index.js';
import { payloadAsContainer } from './desktopPlexRuntimeSupport.js';

export class PlaybackMediaDetailPort implements PlexStreamResolverMediaDetailPort {
  readonly #runtime: DesktopPlexRuntime;

  constructor(runtime: DesktopPlexRuntime) {
    this.#runtime = runtime;
  }

  async getMediaDetail(input: { mediaId: string }): Promise<PlexMediaItem | null> {
    const { connection, token } = this.#runtime.getActiveConnectionAndToken();
    if (!connection || !token) {
      return null;
    }
    const prefix = 'plex-media-';
    if (!input.mediaId.startsWith(prefix)) {
      return null;
    }
    const ratingKey = input.mediaId.slice(prefix.length);
    if (!ratingKey) {
      return null;
    }

    const liveTransport = this.#runtime.getLibraryTransport();
    try {
      const payload = await liveTransport.getMetadata({
        connection,
        token,
        ratingKey,
      });

      if (!payload) {
        return null;
      }

      const parsedItems = parseMediaItems(
        extractMetadataArray<RawMediaItem>(payloadAsContainer<RawMediaItem>(payload), 'metadata'),
      );
      return parsedItems[0] ?? null;
    } catch {
      return null;
    }
  }
}
