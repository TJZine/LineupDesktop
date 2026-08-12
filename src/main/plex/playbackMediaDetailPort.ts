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

  async getMediaDetail(input: { ratingKey: string }): Promise<PlexMediaItem | null> {
    const normalizedRatingKey = input.ratingKey.trim();
    if (normalizedRatingKey === '') {
      return null;
    }

    try {
      return await this.#runtime.withActiveLibraryContext('getMetadata', async ({ connection, token, transport }) => {
        const payload = await transport.getMetadata({
          connection,
          token,
          ratingKey: normalizedRatingKey,
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
      this.#diagnosticEventStore?.record({
        surface: 'main',
        category: 'playback',
        severity: 'warning',
        status: 'failed',
        operation: 'playbackMediaDetailPort.getMetadata',
        message: 'Playback media detail lookup failed.',
        context: {
          flow: 'playbackMediaDetailPort -> withActiveLibraryContext(getMetadata)',
          steps: ['transport.getMetadata', 'payloadAsContainer', 'extractMetadataArray', 'parseMediaItems'],
          reason: 'metadata lookup failed',
        },
      });
      return null;
    }
  }
}
