import { CHANNEL_BUILDER_MAX_LIBRARIES } from '../../domain/channelBuilder/constants.js';
import type {
  ChannelBuilderContextBinding,
  ChannelBuilderFacetId,
  ChannelBuilderFacetSnapshot,
  ChannelBuilderFacetWarningCode,
  ChannelBuilderSourceIdentity,
  ChannelBuilderTagFacet,
  NormalizedChannelSetupConfig,
} from '../../domain/channelBuilder/types.js';
import {
  createContentFilterIdentity,
  createFacetIdentity,
  createSourceIdentity,
  createTagSemanticGroupIdentity,
  projectChannelBuilderSafeDisplayString,
} from '../../domain/channelBuilder/index.js';
import type { ChannelContentSource } from '../../domain/channel/types.js';
import {
  buildChannelBuilderActorStudioFilter,
  CHANNEL_BUILDER_FACET_PAGE_SIZE,
  CHANNEL_BUILDER_TAG_FAMILIES,
  channelBuilderTagMediaType,
  cloneChannelBuilderFacetLibrary,
  normalizeChannelBuilderFacetValue,
  type ChannelBuilderFacetSession,
  type TagFamily,
  type TagMediaType,
} from './channelBuilderFacetSession.js';
import type {
  ChannelBuilderFacetIndexEntry,
  ChannelBuilderFacetMaterializationIndex,
} from './channelBuilderFacetMaterialization.js';
import type {
  PlexLibrarySection,
  PlexListingPage,
  PlexTagDirectoryItem,
} from './library/index.js';
import { LivePlexTransportError } from './livePlexTransport.js';

const MAX_PAGE_OFFSET = 400;
const MAX_FAMILY_ENTRIES = 500;
const MAX_SNAPSHOT_ENTRIES = 50_000;
const TV_PEOPLE_DISTINCT_SERIES_THRESHOLD = 3;
const DISPLAY_OPTIONS = Object.freeze({
  fallback: 'Untitled facet',
  maxUtf16Units: 160,
});

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

export async function discoverChannelBuilderFacets(
  input: ChannelBuilderFacetDiscoveryInput,
  session: ChannelBuilderFacetSession,
  libraries: readonly PlexLibrarySection[],
): Promise<{
  snapshot: ChannelBuilderFacetSnapshot;
  indexEntries: readonly ChannelBuilderFacetIndexEntry[];
}> {
  const libraryFacets: ChannelBuilderFacetSnapshot['libraries'][number][] = [];
  const playlistFacets: ChannelBuilderFacetSnapshot['playlists'][number][] = [];
  const collectionFacets: ChannelBuilderFacetSnapshot['collections'][number][] = [];
  const rawTags: RawTagFacet[] = [];
  const recentlyAdded: ChannelBuilderFacetSnapshot['recentlyAdded'][number][] = [];
  const indexEntries: ChannelBuilderFacetIndexEntry[] = [];
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
        session.listServerPlaylistsPage({ offset, limit: CHANNEL_BUILDER_FACET_PAGE_SIZE, signal: input.signal }));
      noteCap(pages, warnings, (count) => {
        omittedCappedCount = combineOmitted(omittedCappedCount, count);
      });
      for (const playlist of pages.entries) {
        try {
          const source: ChannelContentSource = {
            type: 'playlist',
            playlistKey: normalizeChannelBuilderFacetValue(playlist.ratingKey),
            playlistName: normalizeChannelBuilderFacetValue(playlist.title),
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
            limit: CHANNEL_BUILDER_FACET_PAGE_SIZE,
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
              collectionKey: normalizeChannelBuilderFacetValue(collection.ratingKey),
              collectionName: normalizeChannelBuilderFacetValue(collection.title),
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
        const loadedPeople = await loadPeopleIndex(input, session, library.id);
        peopleIndex = loadedPeople.index;
        if (loadedPeople.truncated) {
          warnings.add('TV_PEOPLE_METADATA_INCOMPLETE');
        }
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
        const mediaType = channelBuilderTagMediaType(library.type, family);
        const pages = await loadPages(input, (offset) =>
          session.listTagDirectoryPage({
            sectionId: library.id,
            family,
            mediaType,
            offset,
            limit: CHANNEL_BUILDER_FACET_PAGE_SIZE,
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
      !CHANNEL_BUILDER_TAG_FAMILIES.has(entry.family as TagFamily) ||
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
): Promise<Readonly<{ facet: RawTagFacet; indexEntry: ChannelBuilderFacetIndexEntry }> | null> {
  const key = normalizeChannelBuilderFacetValue(tag.key);
  const tagValue = normalizeChannelBuilderFacetValue(tag.title);
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
      limit: CHANNEL_BUILDER_FACET_PAGE_SIZE,
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
  const yearValue = family === 'year' ? parseYearValue(tagValue) : null;
  const common = {
    facetId,
    sourceIdentity,
    libraryFacetId: library.facetId,
    rawTitle: tag.title,
    itemCount,
    episodeCount,
    distinctSeriesCount,
  };
  const entry: ChannelBuilderFacetIndexEntry = {
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
        : { ...buildChannelBuilderActorStudioFilter(family, fastKey, key), type: mediaType };
  return {
    ...librarySource(library),
    ...(filter === undefined ? {} : { libraryFilter: filter }),
  };
}

function librarySource(library: PlexLibrarySection): ChannelContentSource {
  return {
    type: 'library',
    libraryId: normalizeChannelBuilderFacetValue(library.id),
    libraryType: library.type === 'show' ? 'show' : 'movie',
    includeWatched: true,
  };
}

function indexEntry(
  facetId: ChannelBuilderFacetId,
  sourceIdentity: ChannelBuilderSourceIdentity,
  source: ChannelContentSource,
  family: ChannelBuilderFacetIndexEntry['family'],
): ChannelBuilderFacetIndexEntry {
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
): Promise<Readonly<{ index: PeopleIndex; truncated: boolean }>> {
  const pages = await loadPages(input, (offset) =>
    session.listLibraryItemsPage({
      sectionId,
      query: { kind: 'tv-people-index' },
      offset,
      limit: CHANNEL_BUILDER_FACET_PAGE_SIZE,
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
  return {
    index: { actor, director },
    truncated: pages.reachedCap,
  };
}

function addPeople(
  target: Map<string, { episodeCount: number; series: Set<string> }>,
  values: readonly string[] | undefined,
  seriesKey: string,
): void {
  for (const raw of values ?? []) {
    const key = raw.normalize('NFC').trim().toLowerCase();
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
  let observedEntryCount = 0;
  const cappedResult = () => ({
    entries,
    cappedOmitted: knownTotal === null
      ? null
      : Math.max(0, Math.max(knownTotal, observedEntryCount) - entries.length),
    reachedCap: true as const,
  });
  while (offset <= MAX_PAGE_OFFSET) {
    ensureActive(input);
    const page = await load(offset);
    ensureActive(input);
    if (page.offset !== offset) throw new Error('Unexpected facet page offset');
    knownTotal = page.totalSize;
    observedEntryCount += page.entries.length;
    const retainedPageEntryCount = Math.min(
      page.entries.length,
      CHANNEL_BUILDER_FACET_PAGE_SIZE,
      MAX_FAMILY_ENTRIES - entries.length,
    );
    entries.push(...page.entries.slice(0, retainedPageEntryCount));
    const pageExceededLimit = page.entries.length > CHANNEL_BUILDER_FACET_PAGE_SIZE;
    const listingComplete =
      page.entries.length < CHANNEL_BUILDER_FACET_PAGE_SIZE ||
      (knownTotal !== null && observedEntryCount >= knownTotal);
    if (pageExceededLimit) return cappedResult();
    if (listingComplete) {
      return { entries, cappedOmitted: 0, reachedCap: false };
    }
    if (entries.length >= MAX_FAMILY_ENTRIES) return cappedResult();
    offset += CHANNEL_BUILDER_FACET_PAGE_SIZE;
  }
  return cappedResult();
}

function parseYearValue(value: string): number {
  const parsed = /^[+-]?\d+$/u.test(value) ? Number(value) : Number.NaN;
  if (!Number.isSafeInteger(parsed)) {
    throw new Error('Invalid main-only year facet value');
  }
  return parsed;
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

export function selectChannelBuilderFacetLibraries(
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
    return cloneChannelBuilderFacetLibrary(library);
  });
}

export function isValidChannelBuilderFacetDiscoveryInput(input: ChannelBuilderFacetDiscoveryInput): boolean {
  return (
    Number.isSafeInteger(input.deadlineAtMs) &&
    input.deadlineAtMs >= 0 &&
    input.normalizedConfig.selectedLibraryIds.length >= 1 &&
    input.normalizedConfig.selectedLibraryIds.length <= CHANNEL_BUILDER_MAX_LIBRARIES &&
    new Set(input.normalizedConfig.selectedLibraryIds).size ===
      input.normalizedConfig.selectedLibraryIds.length
  );
}

function ensureActive(input: ChannelBuilderFacetDiscoveryInput): void {
  ensureChannelBuilderFacetDiscoveryNotAborted(input);
  if (Date.now() > input.deadlineAtMs) throw new DiscoveryDeadlineError();
}

export function ensureChannelBuilderFacetDiscoveryNotAborted(input: ChannelBuilderFacetDiscoveryInput): void {
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

function safeCount(value: number | null | undefined): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
    ? value
    : null;
}

function lexical(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
