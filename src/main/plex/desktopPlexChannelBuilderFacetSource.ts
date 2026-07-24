import type {
  ChannelBuilderCandidateDraft,
  ChannelBuilderContextBinding,
  ChannelBuilderFacetId,
  ChannelBuilderFacetSnapshot,
  ChannelBuilderFacetWarningCode,
  ChannelBuilderSafeSourceReference,
  ChannelBuilderSourceIdentity,
  ChannelBuilderStrategyKey,
  ChannelBuilderTagFacet,
  ChannelSetupWarning,
  NormalizedChannelSetupConfig,
} from '../../domain/channelBuilder/types.js';
import {
  createCandidateIdentity,
  createContentFilterIdentity,
  createFacetIdentity,
  createSourceIdentity,
  createTagSemanticGroupIdentity,
  projectChannelBuilderSafeDisplayString,
} from '../../domain/channelBuilder/index.js';
import { isValidContentSource } from '../../domain/channel/channelContentSourceValidator.js';
import {
  isValidBuildStrategy,
  isValidContentFilterArray,
  isValidPlaybackMode,
  isValidSortOrder,
} from '../../domain/channel/channelValueValidators.js';
import type {
  ChannelContentSource,
  ChannelCreateInput,
  ContentFilter,
} from '../../domain/channel/types.js';
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
import { LivePlexTransportError } from './livePlexTransport.js';
import { payloadAsContainer } from './desktopPlexRuntimeSupport.js';

const PAGE_SIZE = 100 as const;
const MAX_PAGE_OFFSET = 400;
const MAX_FAMILY_ENTRIES = 500;
const MAX_SNAPSHOT_ENTRIES = 50_000;
const TV_PEOPLE_DISTINCT_SERIES_THRESHOLD = 3;
const DISPLAY_OPTIONS = Object.freeze({
  fallback: 'Untitled facet',
  maxUtf16Units: 160,
});

type TagFamily = 'genre' | 'director' | 'year' | 'studio' | 'actor';
type TagMediaType = 1 | 2 | 4;

export type ChannelBuilderFacetSessionCollectionRequest = Readonly<{
  sectionId: string;
  offset: number;
  limit: 100;
  signal: AbortSignal;
}>;

export type ChannelBuilderFacetSessionPlaylistRequest = Readonly<{
  offset: number;
  limit: 100;
  signal: AbortSignal;
}>;

export type ChannelBuilderFacetSessionTagRequest = Readonly<{
  sectionId: string;
  family: TagFamily;
  mediaType: TagMediaType;
  offset: number;
  limit: 100;
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
  limit: 100;
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

export type ChannelBuilderFacetDiscoveryInput = Readonly<{
  normalizedConfig: NormalizedChannelSetupConfig;
  context: ChannelBuilderContextBinding;
  deadlineAtMs: number;
  signal: AbortSignal;
}>;

export type ChannelBuilderFacetDiscoveryResult =
  | Readonly<{
      kind: 'ready' | 'slow';
      snapshot: ChannelBuilderFacetSnapshot;
      materializationIndex: ChannelBuilderFacetMaterializationIndex;
    }>
  | Readonly<{
      kind: 'blocked';
      snapshot: ChannelBuilderFacetSnapshot;
      materializationIndex: ChannelBuilderFacetMaterializationIndex;
    }>
  | Readonly<{ kind: 'canceled'; snapshot: null; materializationIndex: null }>
  | Readonly<{
      kind: 'failed';
      snapshot: null;
      materializationIndex: null;
      error: Readonly<{
        code: 'CHANNEL_PLEX_REQUIRED' | 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_UNKNOWN';
        retryable: boolean;
      }>;
    }>;

export interface ChannelBuilderFacetSource {
  discover(input: ChannelBuilderFacetDiscoveryInput): Promise<ChannelBuilderFacetDiscoveryResult>;
}

export type ChannelBuilderFacetMaterializationResult =
  | Readonly<{ status: 'ready'; candidateId: string; createInput: ChannelCreateInput }>
  | Readonly<{
      status: 'skipped';
      candidateId: string;
      reason: 'facet-unavailable' | 'source-member-unavailable';
      warning: ChannelSetupWarning;
    }>
  | Readonly<{
      status: 'failed';
      candidateId: string;
      reason:
        | 'context-changed'
        | 'source-member-mismatch'
        | 'invalid-materialization'
        | 'index-disposed';
      error: Readonly<{
        code: 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_VALIDATION_FAILED' | 'CHANNEL_PLAN_EXPIRED';
        retryable: boolean;
      }>;
    }>
  | Readonly<{ status: 'canceled'; candidateId: string }>;

export interface ChannelBuilderFacetMaterializationIndex {
  readonly context: ChannelBuilderContextBinding;
  materialize(input: Readonly<{
    candidate: ChannelBuilderCandidateDraft;
    expectedContext: ChannelBuilderContextBinding;
    signal: AbortSignal;
  }>): Promise<ChannelBuilderFacetMaterializationResult>;
  dispose(): void;
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
    libraries: binding.libraries.map(cloneLibrary),
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

export class DesktopPlexChannelBuilderFacetSource implements ChannelBuilderFacetSource {
  readonly #accessPort: ChannelBuilderFacetAccessPort;

  constructor(accessPort: ChannelBuilderFacetAccessPort) {
    this.#accessPort = accessPort;
  }

  async discover(input: ChannelBuilderFacetDiscoveryInput): Promise<ChannelBuilderFacetDiscoveryResult> {
    if (
      !validDiscoveryInput(input) ||
      input.signal.aborted
    ) {
      return { kind: 'canceled', snapshot: null, materializationIndex: null };
    }
    const owned = { index: null as MutableMaterializationIndex | null };
    try {
      const result = await this.#accessPort.withSession(
        {
          expectedContext: input.context,
          selectedLibraryIds: input.normalizedConfig.selectedLibraryIds,
          deadlineAtMs: input.deadlineAtMs,
          signal: input.signal,
        },
        async (session) => {
          ensureNotAborted(input);
          const selectedLibraries = selectLibraries(session.libraries, input.normalizedConfig);
          const discovered = await discoverFacets(input, session, selectedLibraries);
          owned.index = new MutableMaterializationIndex(input.context, discovered.indexEntries);
          return {
            snapshot: discovered.snapshot,
            materializationIndex: owned.index,
          };
        },
      );
      ensureNotAborted(input);
      return {
        kind: result.snapshot.aggregate.status,
        snapshot: result.snapshot,
        materializationIndex: result.materializationIndex,
      };
    } catch (error) {
      owned.index?.dispose();
      if (input.signal.aborted) {
        return { kind: 'canceled', snapshot: null, materializationIndex: null };
      }
      if (
        error instanceof LivePlexTransportError &&
        (error.code === 'auth-required' || error.code === 'auth-invalid')
      ) {
        return failed('CHANNEL_PLEX_REQUIRED', false);
      }
      if (hasSafeCode(error, 'CHANNEL_PLEX_REQUIRED')) {
        return failed('CHANNEL_PLEX_REQUIRED', false);
      }
      if (hasSafeCode(error, 'CHANNEL_CONTEXT_CHANGED')) {
        return failed('CHANNEL_CONTEXT_CHANGED', true);
      }
      return failed('CHANNEL_UNKNOWN', error instanceof ChannelBuilderFacetTransportUnavailableError ? false : true);
    }
  }
}

type IndexEntry = Readonly<{
  facetId: ChannelBuilderFacetId;
  sourceIdentity: ChannelBuilderSourceIdentity;
  source: ChannelContentSource;
  family:
    | 'library'
    | 'playlist'
    | 'collection'
    | 'genre'
    | 'director'
    | 'year'
    | 'studio'
    | 'actor'
    | 'recently-added';
  tagValue: string | null;
  semanticGroupIdentity: string | null;
  contentFilterIdentity: string | null;
  yearValue: number | null;
}>;

async function discoverFacets(
  input: ChannelBuilderFacetDiscoveryInput,
  session: ChannelBuilderFacetSession,
  libraries: readonly PlexLibrarySection[],
): Promise<{
  snapshot: ChannelBuilderFacetSnapshot;
  indexEntries: readonly IndexEntry[];
}> {
  const libraryFacets: ChannelBuilderFacetSnapshot['libraries'][number][] = [];
  const playlistFacets: ChannelBuilderFacetSnapshot['playlists'][number][] = [];
  const collectionFacets: ChannelBuilderFacetSnapshot['collections'][number][] = [];
  const rawTags: RawTagFacet[] = [];
  const recentlyAdded: ChannelBuilderFacetSnapshot['recentlyAdded'][number][] = [];
  const indexEntries: IndexEntry[] = [];
  const warnings = new Set<ChannelBuilderFacetWarningCode>();
  let omittedMalformedCount = 0;
  let omittedCappedCount: number | null = 0;
  let sourceFailures = 0;
  let deadlineExhausted = false;
  const enabledSourceCount =
    (input.normalizedConfig.strategyConfig.playlists.enabled ? 1 : 0) +
    (input.normalizedConfig.strategyConfig.collections.enabled ? libraries.length : 0) +
    (input.normalizedConfig.strategyConfig.recentlyAdded.enabled ? libraries.length : 0) +
    libraries.reduce(
      (count, library) => count + tagFamilies(input.normalizedConfig, library.type).length,
      0,
    );
  const noteSourceFailure = (error: unknown): void => {
    if (mustPropagate(error, input)) throw error;
    sourceFailures += 1;
    if (isDiscoveryTimeout(error, input)) {
      deadlineExhausted = true;
      warnings.add('FACET_DISCOVERY_TIMEOUT');
    }
  };

  const libraryById = new Map<string, {
    record: PlexLibrarySection;
    facetId: ChannelBuilderFacetId;
    sourceIdentity: ChannelBuilderSourceIdentity;
  }>();
  for (const library of libraries) {
    const source = librarySource(library);
    const facetId = createFacetIdentity('library', {
      profileBinding: input.context.profileBinding,
      serverBinding: input.context.serverBinding,
      family: 'library',
      libraryId: library.id,
      libraryUuid: library.uuid,
      libraryType: library.type,
    });
    const sourceIdentity = createSourceIdentity(source);
    const title = projectChannelBuilderSafeDisplayString(library.title, DISPLAY_OPTIONS);
    libraryFacets.push({
      facetId,
      sourceIdentity,
      title,
      mediaType: library.type === 'show' ? 'show' : 'movie',
      contentCount: safeCount(library.contentCount) ?? 0,
    });
    libraryById.set(library.id, { record: library, facetId, sourceIdentity });
    indexEntries.push(indexEntry(facetId, sourceIdentity, source, 'library'));
    if (input.normalizedConfig.strategyConfig.recentlyAdded.enabled) {
      const recentFacetId = createFacetIdentity('recently-added', {
        profileBinding: input.context.profileBinding,
        serverBinding: input.context.serverBinding,
        family: 'recently-added',
        libraryId: library.id,
        libraryUuid: library.uuid,
        libraryType: library.type,
      });
      recentlyAdded.push({
        facetId: recentFacetId,
        sourceIdentity,
        libraryFacetId: facetId,
        itemCount: safeCount(library.contentCount) ?? 0,
      });
      indexEntries.push(indexEntry(recentFacetId, sourceIdentity, source, 'recently-added'));
    }
  }

  if (input.normalizedConfig.strategyConfig.playlists.enabled && !deadlineExhausted) {
    try {
      const pages = await loadPages(input, (offset) =>
        session.listServerPlaylistsPage({ offset, limit: PAGE_SIZE, signal: input.signal }));
      noteCap(pages, warnings, (count) => {
        omittedCappedCount = combineOmitted(omittedCappedCount, count);
      });
      for (const playlist of pages.entries) {
        try {
          const source: ChannelContentSource = {
            type: 'playlist',
            playlistKey: normalizedRequired(playlist.ratingKey),
            playlistName: normalizedRequired(playlist.title),
          };
          const facetId = createFacetIdentity('playlist', {
            profileBinding: input.context.profileBinding,
            serverBinding: input.context.serverBinding,
            family: 'playlist',
            libraryId: null,
            libraryUuid: null,
            ratingKey: playlist.ratingKey,
            key: playlist.key,
          });
          const sourceIdentity = createSourceIdentity(source);
          playlistFacets.push({
            facetId,
            sourceIdentity,
            title: projectChannelBuilderSafeDisplayString(playlist.title, DISPLAY_OPTIONS),
            itemCount: safeCount(playlist.leafCount) ?? 0,
            durationMs: safeCount(playlist.duration) ?? 0,
          });
          indexEntries.push(indexEntry(facetId, sourceIdentity, source, 'playlist'));
        } catch {
          omittedMalformedCount += 1;
        }
      }
    } catch (error) {
      noteSourceFailure(error);
    }
  }

  if (input.normalizedConfig.strategyConfig.collections.enabled && !deadlineExhausted) {
    for (const library of libraries) {
      if (deadlineExhausted) break;
      try {
        const pages = await loadPages(input, (offset) =>
          session.listCollectionsPage({
            sectionId: library.id,
            offset,
            limit: PAGE_SIZE,
            signal: input.signal,
          }));
        noteCap(pages, warnings, (count) => {
          omittedCappedCount = combineOmitted(omittedCappedCount, count);
        });
        const libraryFacet = libraryById.get(library.id)!;
        for (const collection of pages.entries) {
          try {
            const source: ChannelContentSource = {
              type: 'collection',
              collectionKey: normalizedRequired(collection.ratingKey),
              collectionName: normalizedRequired(collection.title),
            };
            const facetId = createFacetIdentity('collection', {
              profileBinding: input.context.profileBinding,
              serverBinding: input.context.serverBinding,
              family: 'collection',
              libraryId: library.id,
              libraryUuid: library.uuid,
              ratingKey: collection.ratingKey,
              key: collection.key,
            });
            const sourceIdentity = createSourceIdentity(source);
            collectionFacets.push({
              facetId,
              sourceIdentity,
              libraryFacetId: libraryFacet.facetId,
              title: projectChannelBuilderSafeDisplayString(collection.title, DISPLAY_OPTIONS),
              itemCount: safeCount(collection.childCount) ?? 0,
            });
            indexEntries.push(indexEntry(facetId, sourceIdentity, source, 'collection'));
          } catch {
            omittedMalformedCount += 1;
          }
        }
      } catch (error) {
        noteSourceFailure(error);
      }
    }
  }

  for (const library of libraries) {
    if (deadlineExhausted) break;
    const enabledFamilies = tagFamilies(input.normalizedConfig, library.type);
    let peopleIndex: PeopleIndex | null = null;
    if (
      library.type === 'show' &&
      enabledFamilies.some((family) => family === 'actor' || family === 'director')
    ) {
      try {
        peopleIndex = await loadPeopleIndex(input, session, library.id);
      } catch (error) {
        if (mustPropagate(error, input)) throw error;
        if (isDiscoveryTimeout(error, input)) {
          deadlineExhausted = true;
          warnings.add('FACET_DISCOVERY_TIMEOUT');
        }
        warnings.add('TV_PEOPLE_METADATA_INCOMPLETE');
      }
    }
    for (const family of enabledFamilies) {
      if (deadlineExhausted) break;
      try {
        const mediaType = tagMediaType(library.type, family);
        const pages = await loadPages(input, (offset) =>
          session.listTagDirectoryPage({
            sectionId: library.id,
            family,
            mediaType,
            offset,
            limit: PAGE_SIZE,
            signal: input.signal,
          }));
        noteCap(pages, warnings, (count) => {
          omittedCappedCount = combineOmitted(omittedCappedCount, count);
        });
        for (const tag of pages.entries) {
          try {
            const built = await buildRawTagFacet(
              input,
              session,
              libraryById.get(library.id)!,
              family,
              mediaType,
              tag,
              peopleIndex,
            );
            if (built !== null) {
              rawTags.push(built.facet);
              indexEntries.push(built.indexEntry);
            }
          } catch (error) {
            if (mustPropagate(error, input)) throw error;
            if (isDiscoveryTimeout(error, input)) {
              deadlineExhausted = true;
              sourceFailures += 1;
              warnings.add('FACET_DISCOVERY_TIMEOUT');
              break;
            }
            omittedMalformedCount += 1;
          }
        }
      } catch (error) {
        noteSourceFailure(error);
      }
    }
  }

  rawTags.sort(compareRawTagFacets);
  const nonTagCount =
    libraryFacets.length +
    playlistFacets.length +
    collectionFacets.length +
    recentlyAdded.length;
  const remaining = Math.max(0, MAX_SNAPSHOT_ENTRIES - nonTagCount);
  const admittedRawTags = rawTags.slice(0, remaining);
  if (admittedRawTags.length < rawTags.length) {
    warnings.add('FACET_CAP_REACHED');
    omittedCappedCount = combineOmitted(
      omittedCappedCount,
      rawTags.length - admittedRawTags.length,
    );
  }
  const tags = admittedRawTags.map(({ rawTitle, ...safe }) => ({
    ...safe,
    displayTitle: projectChannelBuilderSafeDisplayString(rawTitle, DISPLAY_OPTIONS),
  })) as ChannelBuilderTagFacet[];
  const retainedTagIds = new Set(tags.map((tag) => tag.facetId));
  const retainedIndexEntries = indexEntries.filter(
    (entry) =>
      !['genre', 'director', 'year', 'studio', 'actor'].includes(entry.family) ||
      retainedTagIds.has(entry.facetId),
  );

  const enabledFacetEntryCount =
    playlistFacets.length + collectionFacets.length + recentlyAdded.length + tags.length;
  if (Date.now() > input.deadlineAtMs) {
    deadlineExhausted = true;
    warnings.add('FACET_DISCOVERY_TIMEOUT');
  }
  if (sourceFailures > 0 || deadlineExhausted) {
    warnings.add(enabledFacetEntryCount === 0 ? 'FACET_UNAVAILABLE' : 'FACET_PARTIAL_FAILURE');
  }
  if (omittedMalformedCount > 0) warnings.add('FACET_MALFORMED_ENTRIES_OMITTED');
  if (enabledSourceCount > 0 && enabledFacetEntryCount === 0) warnings.add('FACET_EMPTY');
  const blocked =
    enabledSourceCount > 0 &&
    enabledFacetEntryCount === 0;
  const status = blocked
    ? 'blocked'
    : warnings.size > 0
      ? 'slow'
      : 'ready';
  const warningCodes = [...warnings].sort();
  if (!warnings.has('FACET_CAP_REACHED')) omittedCappedCount = 0;
  const snapshot: ChannelBuilderFacetSnapshot = Object.freeze({
    context: Object.freeze({ ...input.context }),
    libraries: Object.freeze(libraryFacets.map((facet) => Object.freeze(facet))),
    playlists: Object.freeze(playlistFacets.map((facet) => Object.freeze(facet))),
    collections: Object.freeze(collectionFacets.map((facet) => Object.freeze(facet))),
    tags: Object.freeze(tags.map((facet) => Object.freeze(facet))),
    recentlyAdded: Object.freeze(recentlyAdded.map((facet) => Object.freeze(facet))),
    aggregate: Object.freeze({
      status,
      warningCodes: Object.freeze(warningCodes),
      omittedMalformedCount: Math.min(omittedMalformedCount, MAX_SNAPSHOT_ENTRIES),
      omittedCappedCount,
    }),
  });
  return { snapshot, indexEntries: retainedIndexEntries };
}

type RawTagFacet = Omit<ChannelBuilderTagFacet, 'displayTitle'> & Readonly<{
  rawTitle: string;
}>;

async function buildRawTagFacet(
  input: ChannelBuilderFacetDiscoveryInput,
  session: ChannelBuilderFacetSession,
  library: {
    record: PlexLibrarySection;
    facetId: ChannelBuilderFacetId;
    sourceIdentity: ChannelBuilderSourceIdentity;
  },
  family: TagFamily,
  mediaType: TagMediaType,
  tag: PlexTagDirectoryItem,
  peopleIndex: PeopleIndex | null,
): Promise<Readonly<{ facet: RawTagFacet; indexEntry: IndexEntry }> | null> {
  const key = normalizedRequired(tag.key);
  const tagValue = normalizedRequired(tag.title);
  const fastKey = tag.fastKey === undefined ? null : tag.fastKey.normalize('NFC');
  let itemCount = safeCount(tag.count);
  let episodeCount: number | null = null;
  let distinctSeriesCount: number | null = null;
  if (
    library.record.type === 'show' &&
    (family === 'actor' || family === 'director')
  ) {
    const breadth = peopleIndex?.[family].get(tagValue.toLowerCase()) ?? null;
    if (
      breadth === null ||
      breadth.episodeCount < input.normalizedConfig.minItemsPerChannel ||
      breadth.series.size < TV_PEOPLE_DISTINCT_SERIES_THRESHOLD
    ) return null;
    itemCount = breadth.episodeCount;
    episodeCount = breadth.episodeCount;
    distinctSeriesCount = breadth.series.size;
  } else if (itemCount === null) {
    ensureActive(input);
    const page = await session.listLibraryItemsPage({
      sectionId: library.record.id,
      query: { kind: 'facet-count', mediaType, family, key, tagValue, fastKey },
      offset: 0,
      limit: PAGE_SIZE,
      signal: input.signal,
    });
    itemCount = page.totalSize ?? page.entries.length;
  }
  const source = tagSource(library.record, family, key, tagValue, fastKey, mediaType);
  const facetId = createFacetIdentity(family, {
    profileBinding: input.context.profileBinding,
    serverBinding: input.context.serverBinding,
    family,
    libraryId: library.record.id,
    libraryUuid: library.record.uuid,
    key,
    tagValue,
    fastKey,
  });
  const sourceIdentity = createSourceIdentity(source);
  const semanticGroupIdentity =
    family === 'year'
      ? null
      : createTagSemanticGroupIdentity({
          profileBinding: input.context.profileBinding,
          serverBinding: input.context.serverBinding,
          family,
          tagValue,
        });
  const contentFilterIdentity =
    family === 'director'
      ? createContentFilterIdentity({
          profileBinding: input.context.profileBinding,
          serverBinding: input.context.serverBinding,
          filters: [{ field: 'director', operator: 'eq', value: tagValue }],
        })
      : null;
  const parsedYear = family === 'year' ? Number.parseInt(tagValue, 10) : Number.NaN;
  const yearValue = family === 'year' && Number.isFinite(parsedYear) ? parsedYear : null;
  const common = {
    facetId,
    sourceIdentity,
    libraryFacetId: library.facetId,
    rawTitle: tag.title,
    itemCount,
    episodeCount,
    distinctSeriesCount,
  };
  const entry: IndexEntry = {
    ...indexEntry(facetId, sourceIdentity, source, family),
    tagValue,
    semanticGroupIdentity,
    contentFilterIdentity,
    yearValue,
  };
  if (family === 'year') {
    return {
      facet: {
        ...common,
        family,
        semanticGroupIdentity: null,
        contentFilterIdentity: null,
        yearValue,
      },
      indexEntry: entry,
    };
  }
  if (family === 'director') {
    if (contentFilterIdentity === null) throw new Error('Invalid director filter');
    return {
      facet: {
        ...common,
        family,
        semanticGroupIdentity,
        contentFilterIdentity,
        yearValue: null,
      },
      indexEntry: entry,
    };
  }
  return {
    facet: {
      ...common,
      family,
      semanticGroupIdentity,
      contentFilterIdentity: null,
      yearValue: null,
    },
    indexEntry: entry,
  };
}

class MutableMaterializationIndex implements ChannelBuilderFacetMaterializationIndex {
  readonly context: ChannelBuilderContextBinding;
  #entries: Map<string, IndexEntry> | null;

  constructor(context: ChannelBuilderContextBinding, entries: readonly IndexEntry[]) {
    this.context = Object.freeze({ ...context });
    this.#entries = new Map(entries.map((entry) => [entry.facetId, entry]));
  }

  dispose(): void {
    this.#entries?.clear();
    this.#entries = null;
  }

  async materialize(input: Readonly<{
    candidate: ChannelBuilderCandidateDraft;
    expectedContext: ChannelBuilderContextBinding;
    signal: AbortSignal;
  }>): Promise<ChannelBuilderFacetMaterializationResult> {
    const candidateId = input.candidate.candidateId;
    if (this.#entries === null) return failedMaterialization(candidateId, 'index-disposed');
    if (input.signal.aborted) return { status: 'canceled', candidateId };
    if (!equalContext(this.context, input.expectedContext) || !equalOrigin(this.context, input.candidate.origin)) {
      return failedMaterialization(candidateId, 'context-changed');
    }
    try {
      const candidateIdentity = createCandidateIdentity({
        origin: input.candidate.origin,
        sourceReference: input.candidate.sourceReference,
        contentFilterIdentity: input.candidate.contentFilterPlan.contentFilterIdentity,
        sortOrder: input.candidate.sortOrder,
        lineupReplicaIndex: input.candidate.lineupReplicaIndex,
        isPlaybackModeVariant: input.candidate.isPlaybackModeVariant,
        playbackMode: input.candidate.playbackMode,
        blockSize: input.candidate.blockSize,
      });
      if (candidateIdentity !== input.candidate.candidateIdentity) {
        return failedMaterialization(candidateId, 'source-member-mismatch');
      }
      const sourceResult = resolveSource(input.candidate.sourceReference, this.#entries);
      if (sourceResult === null) {
        return skippedMaterialization(
          candidateId,
          input.candidate.sourceReference.kind === 'mixed'
            ? 'source-member-unavailable'
            : 'facet-unavailable',
          input.candidate.strategy,
        );
      }
      if (sourceResult === false) return failedMaterialization(candidateId, 'source-member-mismatch');
      const filters = resolveFilters(input.candidate, this.context, this.#entries);
      if (filters === false) return failedMaterialization(candidateId, 'invalid-materialization');
      const createInput = createInputFromCandidate(input.candidate, sourceResult, filters);
      return { status: 'ready', candidateId, createInput };
    } catch {
      return failedMaterialization(candidateId, 'invalid-materialization');
    }
  }
}

function resolveSource(
  reference: ChannelBuilderSafeSourceReference,
  entries: ReadonlyMap<string, IndexEntry>,
): ChannelContentSource | null | false {
  if (reference.kind === 'manual') return false;
  if (reference.kind === 'mixed') {
    const sources: ChannelContentSource[] = [];
    for (const child of reference.sources) {
      const resolved = resolveSource(child, entries);
      if (resolved === null || resolved === false) return resolved;
      sources.push(resolved);
    }
    const mixed: ChannelContentSource = {
      type: 'mixed',
      mixMode: reference.mixMode,
      sources,
    };
    return createSourceIdentity(mixed) === reference.sourceIdentity ? mixed : false;
  }
  if (reference.facetId === null) return false;
  const entry = entries.get(reference.facetId);
  if (entry === undefined) return null;
  if (
    entry.sourceIdentity !== reference.sourceIdentity ||
    createSourceIdentity(entry.source) !== entry.sourceIdentity
  ) return false;
  return cloneSource(entry.source);
}

function resolveFilters(
  candidate: ChannelBuilderCandidateDraft,
  context: ChannelBuilderContextBinding,
  entries: ReadonlyMap<string, IndexEntry>,
): ContentFilter[] | undefined | false {
  const plan = candidate.contentFilterPlan;
  if (plan.kind === 'none') return undefined;
  if (plan.kind === 'inline') {
    if (
      plan.filters.length === 0 ||
      !plan.filters.every((filter) => typeof filter.value === 'number' && Number.isFinite(filter.value))
    ) return false;
    const filters = plan.filters.map((filter) => ({ ...filter }));
    return createContentFilterIdentity({
      profileBinding: context.profileBinding,
      serverBinding: context.serverBinding,
      filters,
    }) === plan.contentFilterIdentity
      ? filters
      : false;
  }
  const entry = entries.get(plan.facetId);
  if (
    entry === undefined ||
    entry.family !== 'director' ||
    entry.tagValue === null ||
    entry.contentFilterIdentity !== plan.contentFilterIdentity
  ) return false;
  const filters: ContentFilter[] = [{
    field: 'director',
    operator: 'eq',
    value: entry.tagValue,
  }];
  return createContentFilterIdentity({
    profileBinding: context.profileBinding,
    serverBinding: context.serverBinding,
    filters,
  }) === plan.contentFilterIdentity
    ? filters
    : false;
}

function createInputFromCandidate(
  candidate: ChannelBuilderCandidateDraft,
  contentSource: ChannelContentSource,
  contentFilters: ContentFilter[] | undefined,
): ChannelCreateInput {
  if (
    !isValidContentSource(contentSource) ||
    !isValidPlaybackMode(candidate.playbackMode) ||
    !Number.isInteger(candidate.shuffleSeed) ||
    (candidate.sortOrder !== null && !isValidSortOrder(candidate.sortOrder)) ||
    (candidate.buildStrategy !== null && !isValidBuildStrategy(candidate.buildStrategy)) ||
    (contentFilters !== undefined && (!isValidContentFilterArray(contentFilters) || contentFilters.length === 0))
  ) throw new Error('Invalid materialization');
  return {
    contentSource,
    name: candidate.displayName,
    playbackMode: candidate.playbackMode,
    shuffleSeed: candidate.shuffleSeed,
    isAutoGenerated: true,
    ...(contentFilters !== undefined ? { contentFilters } : {}),
    ...(candidate.sortOrder !== null ? { sortOrder: candidate.sortOrder } : {}),
    ...(candidate.blockSize !== null ? { blockSize: candidate.blockSize } : {}),
    ...(candidate.buildStrategy !== null ? { buildStrategy: candidate.buildStrategy } : {}),
    ...(candidate.sourceLibraryId !== null ? { sourceLibraryId: candidate.sourceLibraryId } : {}),
    ...(candidate.sourceLibraryName !== null ? { sourceLibraryName: candidate.sourceLibraryName } : {}),
    ...(candidate.lineupReplicaIndex !== null ? { lineupReplicaIndex: candidate.lineupReplicaIndex } : {}),
    ...(candidate.isPlaybackModeVariant !== null
      ? { isPlaybackModeVariant: candidate.isPlaybackModeVariant }
      : {}),
  };
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
      ...actorStudioFilter(query.family, query.fastKey, query.key),
      type: query.mediaType,
    },
  };
}

function actorStudioFilter(
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

function tagSource(
  library: PlexLibrarySection,
  family: TagFamily,
  key: string,
  tagValue: string,
  fastKey: string | null,
  mediaType: TagMediaType,
): ChannelContentSource {
  const filter =
    family === 'genre' || family === 'director'
      ? { [family]: tagValue }
      : family === 'year'
        ? undefined
        : { ...actorStudioFilter(family, fastKey, key), type: mediaType };
  return {
    ...librarySource(library),
    ...(filter === undefined ? {} : { libraryFilter: filter }),
  };
}

function librarySource(library: PlexLibrarySection): ChannelContentSource {
  return {
    type: 'library',
    libraryId: normalizedRequired(library.id),
    libraryType: library.type === 'show' ? 'show' : 'movie',
    includeWatched: true,
  };
}

function indexEntry(
  facetId: ChannelBuilderFacetId,
  sourceIdentity: ChannelBuilderSourceIdentity,
  source: ChannelContentSource,
  family: IndexEntry['family'],
): IndexEntry {
  return {
    facetId,
    sourceIdentity,
    source,
    family,
    tagValue: null,
    semanticGroupIdentity: null,
    contentFilterIdentity: null,
    yearValue: null,
  };
}

type PeopleIndex = Readonly<{
  actor: ReadonlyMap<string, { episodeCount: number; series: ReadonlySet<string> }>;
  director: ReadonlyMap<string, { episodeCount: number; series: ReadonlySet<string> }>;
}>;

async function loadPeopleIndex(
  input: ChannelBuilderFacetDiscoveryInput,
  session: ChannelBuilderFacetSession,
  sectionId: string,
): Promise<PeopleIndex> {
  const pages = await loadPages(input, (offset) =>
    session.listLibraryItemsPage({
      sectionId,
      query: { kind: 'tv-people-index' },
      offset,
      limit: PAGE_SIZE,
      signal: input.signal,
    }));
  const actor = new Map<string, { episodeCount: number; series: Set<string> }>();
  const director = new Map<string, { episodeCount: number; series: Set<string> }>();
  for (const item of pages.entries) {
    const seriesKey = item.grandparentRatingKey?.trim() || item.grandparentTitle?.trim();
    if (!seriesKey) continue;
    addPeople(actor, item.actors, seriesKey);
    addPeople(director, item.directors, seriesKey);
  }
  return { actor, director };
}

function addPeople(
  target: Map<string, { episodeCount: number; series: Set<string> }>,
  values: readonly string[] | undefined,
  seriesKey: string,
): void {
  for (const raw of values ?? []) {
    const key = raw.trim().toLowerCase();
    if (!key) continue;
    const current = target.get(key) ?? { episodeCount: 0, series: new Set<string>() };
    current.episodeCount += 1;
    current.series.add(seriesKey);
    target.set(key, current);
  }
}

async function loadPages<T>(
  input: ChannelBuilderFacetDiscoveryInput,
  load: (offset: number) => Promise<PlexListingPage<T>>,
): Promise<{ entries: T[]; cappedOmitted: number | null; reachedCap: boolean }> {
  const entries: T[] = [];
  let offset = 0;
  let knownTotal: number | null = null;
  while (offset <= MAX_PAGE_OFFSET) {
    ensureActive(input);
    const page = await load(offset);
    ensureActive(input);
    if (page.offset !== offset) throw new Error('Unexpected facet page offset');
    knownTotal = page.totalSize;
    entries.push(...page.entries);
    if (
      page.entries.length < PAGE_SIZE ||
      (knownTotal !== null && entries.length >= knownTotal)
    ) return { entries, cappedOmitted: 0, reachedCap: false };
    offset += PAGE_SIZE;
  }
  const cappedOmitted =
    knownTotal === null ? null : Math.max(0, knownTotal - entries.length);
  return {
    entries: entries.slice(0, MAX_FAMILY_ENTRIES),
    cappedOmitted,
    reachedCap: true,
  };
}

function noteCap(
  result: { reachedCap: boolean; cappedOmitted: number | null },
  warnings: Set<ChannelBuilderFacetWarningCode>,
  add: (count: number | null) => void,
): void {
  if (!result.reachedCap) return;
  warnings.add('FACET_CAP_REACHED');
  add(result.cappedOmitted);
}

function combineOmitted(current: number | null, next: number | null): number | null {
  if (current === null || next === null) return null;
  const sum = current + next;
  return Number.isSafeInteger(sum) && sum <= MAX_SNAPSHOT_ENTRIES ? sum : null;
}

function tagFamilies(
  config: NormalizedChannelSetupConfig,
  libraryType: PlexLibrarySection['type'],
): TagFamily[] {
  const families: TagFamily[] = [];
  if (config.strategyConfig.genres.enabled) families.push('genre');
  if (config.strategyConfig.directors.enabled) families.push('director');
  if (config.strategyConfig.decades.enabled) families.push('year');
  if (config.strategyConfig.studios.enabled && libraryType === 'movie') families.push('studio');
  if (config.strategyConfig.actors.enabled) families.push('actor');
  return families;
}

function compareRawTagFacets(left: RawTagFacet, right: RawTagFacet): number {
  const count = (right.itemCount ?? 0) - (left.itemCount ?? 0);
  if (count !== 0) return count;
  if (left.family === 'year' && right.family === 'year') {
    const leftRank = left.yearValue === null ? 1 : 0;
    const rightRank = right.yearValue === null ? 1 : 0;
    return (
      leftRank - rightRank ||
      (left.yearValue ?? 0) - (right.yearValue ?? 0) ||
      lexical(left.sourceIdentity, right.sourceIdentity) ||
      lexical(left.facetId, right.facetId)
    );
  }
  return (
    lexical(left.semanticGroupIdentity ?? '', right.semanticGroupIdentity ?? '') ||
    lexical(left.contentFilterIdentity ?? '', right.contentFilterIdentity ?? '') ||
    lexical(left.sourceIdentity, right.sourceIdentity) ||
    lexical(left.facetId, right.facetId)
  );
}

function selectLibraries(
  available: readonly PlexLibrarySection[],
  config: NormalizedChannelSetupConfig,
): PlexLibrarySection[] {
  const byId = new Map<string, PlexLibrarySection>();
  for (const library of available) {
    if (byId.has(library.id)) throw safeContextError();
    byId.set(library.id, library);
  }
  return config.selectedLibraryIds.map((id) => {
    const library = byId.get(id);
    if (
      library === undefined ||
      (library.type !== 'movie' && library.type !== 'show') ||
      library.uuid.trim().length === 0
    ) throw safeContextError();
    return cloneLibrary(library);
  });
}

function validDiscoveryInput(input: ChannelBuilderFacetDiscoveryInput): boolean {
  return (
    Number.isSafeInteger(input.deadlineAtMs) &&
    input.deadlineAtMs >= 0 &&
    input.normalizedConfig.selectedLibraryIds.length >= 1 &&
    input.normalizedConfig.selectedLibraryIds.length <= 24 &&
    new Set(input.normalizedConfig.selectedLibraryIds).size ===
      input.normalizedConfig.selectedLibraryIds.length
  );
}

function ensureActive(input: ChannelBuilderFacetDiscoveryInput): void {
  ensureNotAborted(input);
  if (Date.now() > input.deadlineAtMs) throw new DiscoveryDeadlineError();
}

function ensureNotAborted(input: ChannelBuilderFacetDiscoveryInput): void {
  if (input.signal.aborted) throw new Error('aborted');
}

class DiscoveryDeadlineError extends Error {}

function mustPropagate(error: unknown, input: ChannelBuilderFacetDiscoveryInput): boolean {
  return (
    input.signal.aborted ||
    hasSafeCode(error, 'CHANNEL_CONTEXT_CHANGED') ||
    hasSafeCode(error, 'CHANNEL_PLEX_REQUIRED') ||
    (error instanceof LivePlexTransportError &&
      (error.code === 'auth-required' || error.code === 'auth-invalid'))
  );
}

function isDiscoveryTimeout(
  error: unknown,
  input: ChannelBuilderFacetDiscoveryInput,
): boolean {
  return (
    error instanceof DiscoveryDeadlineError ||
    (error instanceof LivePlexTransportError && error.code === 'timeout') ||
    Date.now() > input.deadlineAtMs
  );
}

function failed(
  code: 'CHANNEL_PLEX_REQUIRED' | 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_UNKNOWN',
  retryable: boolean,
): ChannelBuilderFacetDiscoveryResult {
  return {
    kind: 'failed',
    snapshot: null,
    materializationIndex: null,
    error: { code, retryable },
  };
}

function hasSafeCode(error: unknown, code: string): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    Object.getOwnPropertyDescriptor(error, 'code')?.value === code
  );
}

function safeContextError(): Error & { code: 'CHANNEL_CONTEXT_CHANGED' } {
  return Object.assign(new Error('Channel Builder context changed.'), {
    code: 'CHANNEL_CONTEXT_CHANGED' as const,
  });
}

function normalizedRequired(value: string): string {
  const normalized = value.normalize('NFC').trim();
  if (
    normalized.length < 1 ||
    normalized.length > 512 ||
    // eslint-disable-next-line no-control-regex
    /[\u0000-\u001f\u007f]/u.test(normalized)
  ) throw new Error('Invalid main-only facet value');
  return normalized;
}

function safeCount(value: number | null | undefined): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
    ? value
    : null;
}

function tagMediaType(
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
    !['genre', 'director', 'year', 'studio', 'actor'].includes(family) ||
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
    return hasExactKeys(query, ['kind', 'mediaType']) && [1, 2].includes(query.mediaType);
  }
  if (query.kind === 'tv-people-index') return hasExactKeys(query, ['kind']);
  return (
    query.kind === 'facet-count' &&
    hasExactKeys(query, ['kind', 'mediaType', 'family', 'key', 'tagValue', 'fastKey']) &&
    [1, 2, 4].includes(query.mediaType) &&
    ['genre', 'director', 'year', 'studio', 'actor'].includes(query.family) &&
    normalizedRequired(query.key).length > 0 &&
    normalizedRequired(query.tagValue).length > 0 &&
    (query.fastKey === null || typeof query.fastKey === 'string')
  );
}

function requireExactPageRequest(value: object, keys: readonly string[]): void {
  if (
    !hasExactKeys(value, keys) ||
    !Number.isInteger((value as { offset?: number }).offset) ||
    (value as { offset: number }).offset < 0 ||
    (value as { offset: number }).offset > MAX_PAGE_OFFSET ||
    (value as { limit?: number }).limit !== PAGE_SIZE ||
    !((value as { signal?: unknown }).signal instanceof AbortSignal)
  ) throw new Error('Invalid Channel Builder page request.');
}

function hasExactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) =>
    Object.prototype.hasOwnProperty.call(value, key));
}

function cloneLibrary(library: PlexLibrarySection): PlexLibrarySection {
  return { ...library, lastScannedAt: new Date(library.lastScannedAt.getTime()) };
}

function cloneSource(source: ChannelContentSource): ChannelContentSource {
  if (source.type === 'mixed') {
    return { ...source, sources: source.sources.map(cloneSource) };
  }
  if (source.type === 'library') {
    return {
      ...source,
      ...(source.libraryFilter === undefined
        ? {}
        : { libraryFilter: { ...source.libraryFilter } }),
    };
  }
  return { ...source };
}

function equalContext(left: ChannelBuilderContextBinding, right: ChannelBuilderContextBinding): boolean {
  return (
    left.contextEpoch === right.contextEpoch &&
    left.profileBinding === right.profileBinding &&
    left.serverBinding === right.serverBinding &&
    left.librarySetBinding === right.librarySetBinding
  );
}

function equalOrigin(context: ChannelBuilderContextBinding, origin: ChannelBuilderCandidateDraft['origin']): boolean {
  return (
    context.profileBinding === origin.profileBinding &&
    context.serverBinding === origin.serverBinding &&
    context.librarySetBinding === origin.librarySetBinding
  );
}

function skippedMaterialization(
  candidateId: string,
  reason: 'facet-unavailable' | 'source-member-unavailable',
  strategy: ChannelBuilderStrategyKey,
): ChannelBuilderFacetMaterializationResult {
  return {
    status: 'skipped',
    candidateId,
    reason,
    warning: {
      code: 'MATERIALIZATION_SKIPPED',
      phase: 'materialization',
      strategy,
      affectedCount: 1,
    },
  };
}

function failedMaterialization(
  candidateId: string,
  reason: 'context-changed' | 'source-member-mismatch' | 'invalid-materialization' | 'index-disposed',
): ChannelBuilderFacetMaterializationResult {
  const error: Readonly<{
    code: 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_VALIDATION_FAILED' | 'CHANNEL_PLAN_EXPIRED';
    retryable: boolean;
  }> =
    reason === 'invalid-materialization'
      ? { code: 'CHANNEL_VALIDATION_FAILED', retryable: false }
      : reason === 'index-disposed'
        ? { code: 'CHANNEL_PLAN_EXPIRED', retryable: true }
        : { code: 'CHANNEL_CONTEXT_CHANGED', retryable: true };
  return { status: 'failed', candidateId, reason, error };
}

function lexical(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
