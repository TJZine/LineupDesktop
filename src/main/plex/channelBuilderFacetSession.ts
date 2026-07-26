import { hasExactPlainRecordKeys } from '../../domain/channelBuilder/exactRecord.js';
import type { ChannelBuilderContextBinding } from '../../domain/channelBuilder/types.js';
import type { PlexConnection } from './discovery/types.js';
import {
  extractDirectoryPage,
  extractMetadataPage,
  parseCollections,
  parseDirectoryTags,
  parseMediaItems,
  parsePlaylists,
  type PlexCollection,
  type PlexLibrarySection,
  type PlexListingPage,
  type PlexMediaItem,
  type PlexPlaylist,
  type PlexTagDirectoryItem,
  type RawCollection,
  type RawDirectoryTag,
  type RawMediaItem,
  type RawPlaylist,
} from './library/index.js';
import type {
  LivePlexChannelBuilderFacetTransport,
  LivePlexLibraryTransport,
} from './livePlexTransport.js';
import { payloadAsContainer } from './desktopPlexRuntimeSupport.js';

export const CHANNEL_BUILDER_FACET_PAGE_SIZE = 100 as const;
const MAX_PAGE_OFFSET = 400;

export type TagFamily = 'genre' | 'director' | 'year' | 'studio' | 'actor';
export type TagMediaType = 1 | 2 | 4;

export const CHANNEL_BUILDER_TAG_FAMILIES: ReadonlySet<TagFamily> = new Set([
  'genre',
  'director',
  'year',
  'studio',
  'actor',
]);

export type ChannelBuilderFacetSessionCollectionRequest = Readonly<{
  sectionId: string;
  offset: number;
  limit: typeof CHANNEL_BUILDER_FACET_PAGE_SIZE;
  signal: AbortSignal;
}>;

export type ChannelBuilderFacetSessionPlaylistRequest = Readonly<{
  offset: number;
  limit: typeof CHANNEL_BUILDER_FACET_PAGE_SIZE;
  signal: AbortSignal;
}>;

export type ChannelBuilderFacetSessionTagRequest = Readonly<{
  sectionId: string;
  family: TagFamily;
  mediaType: TagMediaType;
  offset: number;
  limit: typeof CHANNEL_BUILDER_FACET_PAGE_SIZE;
  signal: AbortSignal;
}>;

export type ChannelBuilderFacetItemQuery =
  | Readonly<{ kind: 'recently-added'; mediaType: 1 | 2 }>
  | Readonly<{ kind: 'tv-people-index' }>
  | Readonly<{
      kind: 'facet-count';
      mediaType: TagMediaType;
      family: TagFamily;
      key: string;
      tagValue: string;
      fastKey: string | null;
    }>;

export type ChannelBuilderFacetSessionItemRequest = Readonly<{
  sectionId: string;
  query: ChannelBuilderFacetItemQuery;
  offset: number;
  limit: typeof CHANNEL_BUILDER_FACET_PAGE_SIZE;
  signal: AbortSignal;
}>;

export interface ChannelBuilderFacetSession {
  readonly libraries: readonly PlexLibrarySection[];
  listCollectionsPage(
    request: ChannelBuilderFacetSessionCollectionRequest,
  ): Promise<PlexListingPage<PlexCollection>>;
  listServerPlaylistsPage(
    request: ChannelBuilderFacetSessionPlaylistRequest,
  ): Promise<PlexListingPage<PlexPlaylist>>;
  listTagDirectoryPage(
    request: ChannelBuilderFacetSessionTagRequest,
  ): Promise<PlexListingPage<PlexTagDirectoryItem>>;
  listLibraryItemsPage(
    request: ChannelBuilderFacetSessionItemRequest,
  ): Promise<PlexListingPage<PlexMediaItem>>;
}

export type ChannelBuilderFacetAccessInput = Readonly<{
  expectedContext: ChannelBuilderContextBinding;
  selectedLibraryIds: readonly string[];
  deadlineAtMs: number;
  signal: AbortSignal;
}>;

export interface ChannelBuilderFacetAccessPort {
  withSession<T>(
    input: ChannelBuilderFacetAccessInput,
    run: (session: ChannelBuilderFacetSession) => Promise<T>,
  ): Promise<T>;
}

export class ChannelBuilderFacetTransportUnavailableError extends Error {
  constructor() {
    super('Channel Builder facet transport is unavailable.');
    this.name = 'ChannelBuilderFacetTransportUnavailableError';
  }
}

export type ChannelBuilderFacetSessionTransportDependencies = Readonly<{
  facetTransport: LivePlexChannelBuilderFacetTransport;
  itemTransport: Pick<LivePlexLibraryTransport, 'listLibraryItems'>;
}>;

const sessionInvalidators = new WeakMap<ChannelBuilderFacetSession, () => void>();

export function createChannelBuilderFacetSession(
  dependencies: ChannelBuilderFacetSessionTransportDependencies,
  binding: Readonly<{
    connection: PlexConnection;
    token: string;
    libraries: readonly PlexLibrarySection[];
  }>,
): ChannelBuilderFacetSession {
  let active = true;
  const libraryById = new Map(binding.libraries.map((library) => [library.id, library]));
  const requireActive = (): void => {
    if (!active) throw new Error('Channel Builder facet session has ended.');
  };
  const session: ChannelBuilderFacetSession = {
    libraries: binding.libraries.map(cloneChannelBuilderFacetLibrary),
    async listCollectionsPage(request) {
      requireActive();
      requireExactPageRequest(request, ['sectionId', 'offset', 'limit', 'signal']);
      const payload = await dependencies.facetTransport.listCollectionsPage({
        connection: binding.connection,
        token: binding.token,
        sectionId: request.sectionId,
        offset: request.offset,
        limit: request.limit,
        signal: request.signal,
      });
      const page = extractMetadataPage<RawCollection>(
        payloadAsContainer<RawCollection>(payload),
        'channel builder collections',
      );
      return { ...page, entries: parseCollections(page.entries) };
    },
    async listServerPlaylistsPage(request) {
      requireActive();
      requireExactPageRequest(request, ['offset', 'limit', 'signal']);
      const payload = await dependencies.facetTransport.listServerPlaylistsPage({
        connection: binding.connection,
        token: binding.token,
        offset: request.offset,
        limit: request.limit,
        signal: request.signal,
      });
      const page = extractMetadataPage<RawPlaylist>(
        payloadAsContainer<RawPlaylist>(payload),
        'channel builder playlists',
      );
      return { ...page, entries: parsePlaylists(page.entries) };
    },
    async listTagDirectoryPage(request) {
      requireActive();
      requireExactPageRequest(request, [
        'sectionId',
        'family',
        'mediaType',
        'offset',
        'limit',
        'signal',
      ]);
      requireTagMediaTypeForLibrary(
        libraryById.get(request.sectionId),
        request.family,
        request.mediaType,
      );
      const payload = await dependencies.facetTransport.listTagDirectoryPage({
        connection: binding.connection,
        token: binding.token,
        sectionId: request.sectionId,
        family: request.family,
        mediaType: request.mediaType,
        offset: request.offset,
        limit: request.limit,
        signal: request.signal,
      });
      const page = extractDirectoryPage<RawDirectoryTag>(
        payloadAsContainer<RawDirectoryTag>(payload),
        'channel builder tags',
      );
      return { ...page, entries: parseDirectoryTags(page.entries) };
    },
    async listLibraryItemsPage(request) {
      requireActive();
      requireExactPageRequest(request, ['sectionId', 'query', 'offset', 'limit', 'signal']);
      requireItemQueryForLibrary(libraryById.get(request.sectionId), request.query);
      const query = buildItemQuery(request.query);
      const payload = await dependencies.itemTransport.listLibraryItems({
        connection: binding.connection,
        token: binding.token,
        sectionId: request.sectionId,
        offset: request.offset,
        limit: request.limit,
        ...query,
        signal: request.signal,
      });
      const page = extractMetadataPage<RawMediaItem>(
        payloadAsContainer<RawMediaItem>(payload),
        'channel builder items',
      );
      return { ...page, entries: parseMediaItems(page.entries) };
    },
  };
  sessionInvalidators.set(session, () => {
    active = false;
  });
  return session;
}

export function invalidateChannelBuilderFacetSession(session: ChannelBuilderFacetSession): void {
  sessionInvalidators.get(session)?.();
  sessionInvalidators.delete(session);
}

function buildItemQuery(
  query: ChannelBuilderFacetItemQuery,
): Readonly<{ sort?: string; filter: Readonly<Record<string, string | number>> }> {
  if (!isExactQuery(query)) throw new Error('Invalid Channel Builder item query.');
  if (query.kind === 'recently-added') {
    return { sort: 'addedAt:desc', filter: { type: query.mediaType } };
  }
  if (query.kind === 'tv-people-index') return { filter: { type: 4 } };
  if (query.family === 'genre' || query.family === 'director' || query.family === 'year') {
    return { filter: { type: query.mediaType, [query.family]: query.tagValue } };
  }
  return {
    filter: {
      ...buildChannelBuilderActorStudioFilter(query.family, query.fastKey, query.key),
      type: query.mediaType,
    },
  };
}

export function buildChannelBuilderActorStudioFilter(
  family: 'actor' | 'studio',
  fastKey: string | null,
  key: string,
): Readonly<Record<string, string | number>> {
  if (fastKey === null) return { [family]: key };
  const question = fastKey.indexOf('?');
  const hash = fastKey.indexOf('#');
  if (question < 0 || (hash >= 0 && question > hash)) return { [family]: key };
  const result: Record<string, string | number> = {};
  const params = new URLSearchParams(fastKey.slice(question + 1, hash < 0 ? undefined : hash));
  for (const [rawKey, rawValue] of params) {
    const normalizedKey = rawKey.trim().toLowerCase();
    const value = rawValue.trim();
    if (
      !['actor', 'studio', 'type'].includes(normalizedKey) ||
      value.length === 0 ||
      /(?:token|authorization|headers?|container|x-plex)/iu.test(normalizedKey)
    ) return { [family]: key };
    if (normalizedKey === 'type') {
      if (!/^\d+$/u.test(value)) return { [family]: key };
      result.type = Number(value);
    } else {
      result[normalizedKey] = value;
    }
  }
  return typeof result[family] === 'string' && result[family].length > 0
    ? result
    : { [family]: key };
}

export function normalizeChannelBuilderFacetValue(value: string): string {
  const normalized = value.normalize('NFC').trim();
  if (
    normalized.length < 1 ||
    normalized.length > 512 ||
    // eslint-disable-next-line no-control-regex
    /[\u0000-\u001f\u007f]/u.test(normalized)
  ) throw new Error('Invalid main-only facet value');
  return normalized;
}

function isNormalizedRequired(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  try {
    normalizeChannelBuilderFacetValue(value);
    return true;
  } catch {
    return false;
  }
}

export function channelBuilderTagMediaType(
  libraryType: PlexLibrarySection['type'],
  family: TagFamily,
): TagMediaType {
  if (libraryType === 'movie') return 1;
  return family === 'genre' ? 2 : 4;
}

function requireTagMediaTypeForLibrary(
  library: PlexLibrarySection | undefined,
  family: TagFamily,
  mediaType: TagMediaType,
): void {
  if (
    library === undefined ||
    !CHANNEL_BUILDER_TAG_FAMILIES.has(family) ||
    (library.type === 'movie' && mediaType !== 1) ||
    (library.type === 'show' &&
      (family === 'studio' ||
        (family === 'genre' ? mediaType !== 2 : mediaType !== 4))) ||
    (library.type !== 'movie' && library.type !== 'show')
  ) throw new Error('Invalid Channel Builder tag request.');
}

function requireItemQueryForLibrary(
  library: PlexLibrarySection | undefined,
  query: ChannelBuilderFacetItemQuery,
): void {
  if (library === undefined || !isExactQuery(query)) {
    throw new Error('Invalid Channel Builder item query.');
  }
  if (
    (query.kind === 'recently-added' &&
      query.mediaType !== (library.type === 'show' ? 2 : 1)) ||
    (query.kind === 'tv-people-index' && library.type !== 'show') ||
    (query.kind === 'facet-count' &&
      ((library.type === 'movie' && query.mediaType !== 1) ||
        (library.type === 'show' &&
          (query.family === 'studio' ||
            (query.family === 'genre' ? query.mediaType !== 2 : query.mediaType !== 4)))))
  ) throw new Error('Invalid Channel Builder item query.');
}

function isExactQuery(query: ChannelBuilderFacetItemQuery): boolean {
  if (query.kind === 'recently-added') {
    return (
      hasExactPlainRecordKeys(query, ['kind', 'mediaType']) &&
      [1, 2].includes(query.mediaType)
    );
  }
  if (query.kind === 'tv-people-index') {
    return hasExactPlainRecordKeys(query, ['kind']);
  }
  return (
    query.kind === 'facet-count' &&
    hasExactPlainRecordKeys(query, [
      'kind',
      'mediaType',
      'family',
      'key',
      'tagValue',
      'fastKey',
    ]) &&
    [1, 2, 4].includes(query.mediaType) &&
    CHANNEL_BUILDER_TAG_FAMILIES.has(query.family) &&
    isNormalizedRequired(query.key) &&
    isNormalizedRequired(query.tagValue) &&
    (query.fastKey === null || typeof query.fastKey === 'string')
  );
}

function requireExactPageRequest(value: object, keys: readonly string[]): void {
  if (
    !hasExactPlainRecordKeys(value, keys) ||
    !Number.isInteger((value as { offset?: number }).offset) ||
    (value as { offset: number }).offset < 0 ||
    (value as { offset: number }).offset > MAX_PAGE_OFFSET ||
    (value as { limit?: number }).limit !== CHANNEL_BUILDER_FACET_PAGE_SIZE ||
    !((value as { signal?: unknown }).signal instanceof AbortSignal)
  ) throw new Error('Invalid Channel Builder page request.');
}

export function cloneChannelBuilderFacetLibrary(library: PlexLibrarySection): PlexLibrarySection {
  return { ...library, lastScannedAt: new Date(library.lastScannedAt.getTime()) };
}
