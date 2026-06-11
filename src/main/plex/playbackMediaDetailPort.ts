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
    const prefix = 'plex-media-';
    if (!input.mediaId.startsWith(prefix)) {
      return null;
    }
    const ratingKey = input.mediaId.slice(prefix.length);
    if (!ratingKey) {
      return null;
    }

    try {
      return await this.#runtime.withActiveLibraryContext('getMetadata', async ({ connection, token, transport }) => {
        const payload = await transport.getMetadata({
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
      });
    } catch {
      return null;
    }
  }
}
