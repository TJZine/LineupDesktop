import type { PlexLibrarySectionSummary, PlexMediaItemSummary } from '../../contracts/plex.js';
import type { PlexConnection } from './discovery/types.js';
import {
  extractMetadataArray,
  extractSearchHubMetadata,
  extractSearchHubs,
  loadLibrarySectionRecordsWithCounts,
  mapSearchHubTypeToMediaType,
  normalizeLibraryPagination,
  parseMediaItems,
  PLEX_LIBRARY_CONSTANTS,
  toRendererSafeMediaItemSummary,
  type PlexMediaType,
  toRendererSafeLibrarySectionSummary,
  type RawMediaItem,
} from './library/index.js';
import { PlexLibraryError } from './library/plexLibraryError.js';
import { LivePlexTransportError, type LivePlexLibraryTransport } from './livePlexTransport.js';
import { payloadAsContainer, StaleRuntimeMutationError } from './desktopPlexRuntimeSupport.js';

export interface PlexLibraryExecutionContext {
  connection: PlexConnection;
  token: string;
  signal: AbortSignal;
}

export interface ListLibraryItemsInput {
  sectionId: string;
  offset?: number;
  limit?: number;
  sort?: string;
  filter?: Readonly<Record<string, string | number>>;
  includeCollections?: boolean;
}

export interface SearchLibraryInput {
  query: string;
  sectionId?: string | null;
  limit?: number;
  types?: readonly PlexMediaType[];
}

export class DesktopPlexLibraryOperationExecutor {
  readonly #libraryTransport: LivePlexLibraryTransport;

  constructor(libraryTransport: LivePlexLibraryTransport) {
    this.#libraryTransport = libraryTransport;
  }

  async listSections(context: PlexLibraryExecutionContext): Promise<readonly PlexLibrarySectionSummary[]> {
    return (await this.listSectionsForMain(context)).sections;
  }

  async listSectionsForMain(context: PlexLibraryExecutionContext): Promise<Readonly<{
    sections: readonly PlexLibrarySectionSummary[];
    libraryPairs: readonly Readonly<{ libraryId: string; libraryUuid: string }>[];
  }>> {
    const records = await loadLibrarySectionRecordsWithCounts({
      libraryTransport: this.#libraryTransport,
      connection: context.connection,
      token: context.token,
      signal: context.signal,
      shouldRethrowCountError: (error) => error instanceof StaleRuntimeMutationError,
    });
    const libraryPairs = records.map((record) => ({
      libraryId: record.id,
      libraryUuid: record.uuid,
    }));
    validateLibraryPairs(libraryPairs);
    libraryPairs.sort((left, right) =>
      left.libraryId.localeCompare(right.libraryId) ||
      left.libraryUuid.localeCompare(right.libraryUuid)
    );
    return {
      sections: records.map(toRendererSafeLibrarySectionSummary),
      libraryPairs,
    };
  }

  async listItems(input: ListLibraryItemsInput, context: PlexLibraryExecutionContext): Promise<{
    offset: number;
    limit: number;
    items: readonly PlexMediaItemSummary[];
  }> {
    const { offset, limit } = normalizeLibraryPagination(input);
    const hasRequestedLimit = typeof input.limit === 'number' && Number.isFinite(input.limit);
    const items: RawMediaItem[] = [];
    let nextOffset = offset;
    let iterations = 0;
    while (true) {
      if (++iterations > PLEX_LIBRARY_CONSTANTS.MAX_PAGINATION_ITERATIONS) {
        throw new PlexLibraryError(
          'pagination-limit-exceeded',
          'Plex library pagination limit was exceeded',
        );
      }
      const payload = await this.#libraryTransport.listLibraryItems({
        connection: context.connection,
        token: context.token,
        sectionId: input.sectionId,
        offset: nextOffset,
        limit,
        ...(input.sort !== undefined ? { sort: input.sort } : {}),
        ...(input.filter !== undefined ? { filter: input.filter } : {}),
        ...(input.includeCollections !== undefined ? { includeCollections: input.includeCollections } : {}),
        signal: context.signal,
      });
      const pageItems = extractMetadataArray<RawMediaItem>(
        payloadAsContainer<RawMediaItem>(payload),
        'library items',
      );
      items.push(...pageItems);
      if (pageItems.length < limit || (hasRequestedLimit && items.length >= limit)) {
        break;
      }
      nextOffset += pageItems.length;
    }
    return {
      offset,
      limit,
      items: parseMediaItems(hasRequestedLimit ? items.slice(0, limit) : items)
        .map(toRendererSafeMediaItemSummary),
    };
  }

  async search(input: SearchLibraryInput, context: PlexLibraryExecutionContext): Promise<readonly PlexMediaItemSummary[]> {
    const limit = normalizeLibraryPagination({ limit: input.limit }).limit;
    const payload = await this.#libraryTransport.searchLibrary({
      connection: context.connection,
      token: context.token,
      query: input.query,
      sectionId: input.sectionId ?? null,
      limit,
      ...(input.types !== undefined ? { types: input.types } : {}),
      signal: context.signal,
    });
    const items = extractSearchHubs(payloadAsContainer<RawMediaItem>(payload), 'search')
      .flatMap((hub) => {
        if (input.types !== undefined && input.types.length > 0) {
          const hubType = mapSearchHubTypeToMediaType(hub.type);
          if (hubType === null || !input.types.includes(hubType)) {
            return [];
          }
        }
        return extractSearchHubMetadata(hub, `search hub "${hub.type}"`);
      })
      .slice(0, limit);
    return parseMediaItems(items).map(toRendererSafeMediaItemSummary);
  }

  async getMetadata(
    ratingKey: string,
    context: PlexLibraryExecutionContext,
  ): Promise<PlexMediaItemSummary | null> {
    const payload = await this.#libraryTransport.getMetadata({
      connection: context.connection,
      token: context.token,
      ratingKey,
      signal: context.signal,
    }).catch((error: unknown) => {
      if (error instanceof LivePlexTransportError && error.code === 'resource-not-found') {
        return null;
      }
      throw error;
    });
    if (payload === null) {
      return null;
    }
    return parseMediaItems(
      extractMetadataArray<RawMediaItem>(payloadAsContainer<RawMediaItem>(payload), 'metadata'),
    ).map(toRendererSafeMediaItemSummary)[0] ?? null;
  }
}

function validateLibraryPairs(
  pairs: readonly Readonly<{ libraryId: string; libraryUuid: string }>[],
): void {
  const ids = new Set<string>();
  const exactPairs = new Set<string>();
  for (const pair of pairs) {
    if (pair.libraryId.trim().length === 0 || pair.libraryUuid.trim().length === 0) {
      throw new PlexLibraryError('parse-error', 'Plex library identity was invalid');
    }
    const exactPair = `${pair.libraryId}\u0000${pair.libraryUuid}`;
    if (ids.has(pair.libraryId) || exactPairs.has(exactPair)) {
      throw new PlexLibraryError('parse-error', 'Plex library identity was duplicated');
    }
    ids.add(pair.libraryId);
    exactPairs.add(exactPair);
  }
}
