import type { PlexMediaItem, RawMediaItem } from './library/index.js';
import type { PlexStreamResolverMediaDetailPort } from './streamResolver.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import { parseMediaItems, extractMetadataArray } from './library/index.js';
import { payloadAsContainer } from './desktopPlexRuntimeSupport.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';

export interface PlaybackMediaDetailPortOptions {
  diagnosticEventStore?: DiagnosticEventStore;
}

export class PlaybackMediaDetailPort implements PlexStreamResolverMediaDetailPort {
  readonly #runtime: DesktopPlexRuntime;
  readonly #diagnosticEventStore?: DiagnosticEventStore;

  constructor(runtime: DesktopPlexRuntime, options: PlaybackMediaDetailPortOptions = {}) {
    this.#runtime = runtime;
    this.#diagnosticEventStore = options.diagnosticEventStore;
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
    } catch (error: unknown) {
      this.#diagnosticEventStore?.record({
        surface: 'main',
        category: 'playback',
        severity: 'warning',
        status: 'failed',
        operation: 'playbackMediaDetailPort.getMetadata',
        message: 'Playback media detail lookup failed.',
        context: {
          ratingKey,
          flow: 'playbackMediaDetailPort -> withActiveLibraryContext(getMetadata)',
          steps: ['transport.getMetadata', 'payloadAsContainer', 'extractMetadataArray', 'parseMediaItems'],
          error: summarizeError(error),
        },
      });
      return null;
    }
  }
}

function summarizeError(error: unknown): { name?: string; message: string } | string {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
    };
  }
  return typeof error === 'string' ? error : 'unknown error';
}
