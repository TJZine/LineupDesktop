import type { ChannelSetupBuildProgress, ChannelSetupConfig } from '../../../contracts/channel.js';
import type {
  ChannelSetupFacetSnapshot,
  ChannelSetupLibraryFacet,
  ChannelSetupNamedFacet,
} from '../../../domain/channel/setupPlanning/index.js';
import type { DesktopPlexRuntime } from '../../plex/desktopPlexRuntime.js';
import type { LivePlexChannelSetupTransport, LivePlexLibraryTransport, LivePlexTagDirectoryFamily } from '../../plex/livePlexTransport.js';
import type { PlexConnection } from '../../plex/discovery/types.js';
import { payloadAsContainer } from '../../plex/desktopPlexRuntimeSupport.js';

export interface ChannelSetupFacetLoadResult {
  profileId: string;
  serverId: string;
  snapshot: ChannelSetupFacetSnapshot;
}

export interface ChannelSetupFacetSource {
  load(
    config: ChannelSetupConfig,
    signal: AbortSignal,
    onProgress?: (progress: ChannelSetupBuildProgress) => void,
  ): Promise<ChannelSetupFacetLoadResult>;
}

export class DesktopPlexSetupFacetSource implements ChannelSetupFacetSource {
  public constructor(private readonly plexRuntime: DesktopPlexRuntime) {}

  public async load(
    config: ChannelSetupConfig,
    signal: AbortSignal,
    onProgress: (progress: ChannelSetupBuildProgress) => void = () => undefined,
  ): Promise<ChannelSetupFacetLoadResult> {
    return this.plexRuntime.withActiveChannelSetupContext(async (context) => {
      const request = { connection: context.connection, token: context.token, signal };
      const sectionPayload = await context.transport.listLibrarySections(request);
      const libraries = parseLibraries(sectionPayload).filter((library) => (
        config.selectedLibraryIds.includes(library.id)
      ));
      const collectionsByLibraryId = new Map<string, readonly ChannelSetupNamedFacet[]>();
      const genresByLibraryId = new Map<string, readonly ChannelSetupNamedFacet[]>();
      const directorsByLibraryId = new Map<string, readonly ChannelSetupNamedFacet[]>();
      const yearsByLibraryId = new Map<string, readonly ChannelSetupNamedFacet[]>();
      const studiosByLibraryId = new Map<string, readonly ChannelSetupNamedFacet[]>();
      const actorsByLibraryId = new Map<string, readonly ChannelSetupNamedFacet[]>();
      const warnings: string[] = [];
      const enrichedLibraries: ChannelSetupLibraryFacet[] = [];
      for (const library of libraries) {
        assertNotAborted(signal);
        const itemCount = await loadContainerCount(context.transport, {
          ...request,
          sectionId: library.id,
          offset: 0,
          limit: 1,
        });
        enrichedLibraries.push({ ...library, itemCount });
      }

      onProgress(stageProgress('fetch_playlists', 0, 1, 'Loading playlists'));
      const playlists = config.strategyConfig.playlists.enabled
        ? parsePlaylists(await context.transport.listVideoPlaylists(request))
        : [];
      onProgress(stageProgress('fetch_playlists', 1, 1, 'Playlists loaded'));

      const collectionTotal = config.strategyConfig.collections.enabled ? enrichedLibraries.length : 0;
      onProgress(stageProgress('fetch_collections', 0, collectionTotal, 'Loading collections'));
      if (config.strategyConfig.collections.enabled) {
        for (const [index, library] of enrichedLibraries.entries()) {
          assertNotAborted(signal);
          const payload = await context.transport.listLibraryItems({
            ...request,
            sectionId: library.id,
            offset: 0,
            limit: 500,
            filter: { type: 18, includeGuids: 1, includeMeta: 1 },
          });
          collectionsByLibraryId.set(library.id, parseCollections(payload));
          onProgress(stageProgress('fetch_collections', index + 1, collectionTotal, 'Collections loaded'));
        }
      }

      onProgress(stageProgress('fetch_facets', 0, enrichedLibraries.length, 'Loading library facets'));
      for (const [index, library] of enrichedLibraries.entries()) {
        assertNotAborted(signal);
        await loadTagFamily('genre', 'genres', genresByLibraryId, library, config, context.transport, request);
        await loadTagFamily('director', 'directors', directorsByLibraryId, library, config, context.transport, request);
        await loadTagFamily('year', 'decades', yearsByLibraryId, library, config, context.transport, request);
        if (library.type === 'movie') {
          await loadTagFamily('studio', 'studios', studiosByLibraryId, library, config, context.transport, request);
        }
        await loadTagFamily('actor', 'actors', actorsByLibraryId, library, config, context.transport, request);
        onProgress(stageProgress('fetch_facets', index + 1, enrichedLibraries.length, 'Library facets loaded'));
      }

      const televisionLibraries = enrichedLibraries.filter((library) => library.type === 'show' && (
        config.strategyConfig.actors.enabled || config.strategyConfig.directors.enabled
      ));
      onProgress(stageProgress('scan_library_items', 0, televisionLibraries.length, 'Scanning TV people'));
      for (const [index, library] of televisionLibraries.entries()) {
          assertNotAborted(signal);
          const people = await scanTelevisionPeople(context.transport, request, library.id);
          if (people.truncated) warnings.push('A TV people scan reached its safety limit.');
          if (config.strategyConfig.actors.enabled) {
            actorsByLibraryId.set(library.id, applyPeopleCounts(actorsByLibraryId.get(library.id) ?? [], people.actors));
          }
          if (config.strategyConfig.directors.enabled) {
            directorsByLibraryId.set(library.id, applyPeopleCounts(directorsByLibraryId.get(library.id) ?? [], people.directors));
          }
          onProgress(stageProgress('scan_library_items', index + 1, televisionLibraries.length, 'TV people scan complete'));
      }
      return {
        profileId: context.profileId,
        serverId: context.serverId,
        snapshot: {
          libraries: enrichedLibraries,
          playlists,
          collectionsByLibraryId,
          genresByLibraryId,
          directorsByLibraryId,
          yearsByLibraryId,
          studiosByLibraryId,
          actorsByLibraryId,
          warnings,
        },
      };
    });
  }
}

function stageProgress(
  task: ChannelSetupBuildProgress['task'],
  current: number,
  total: number,
  label: string,
): ChannelSetupBuildProgress { return { task, current, total, label, detail: label }; }

async function loadTagFamily(
  family: LivePlexTagDirectoryFamily,
  strategy: keyof ChannelSetupConfig['strategyConfig'],
  target: Map<string, readonly ChannelSetupNamedFacet[]>,
  library: ChannelSetupLibraryFacet,
  config: ChannelSetupConfig,
  transport: LivePlexChannelSetupTransport,
  request: { connection: PlexConnection; token: string; signal: AbortSignal },
): Promise<void> {
  if (!config.strategyConfig[strategy].enabled) return;
  const type = library.type === 'movie' ? 1 : family === 'genre' ? 2 : 4;
  const payload = await transport.listLibraryTagDirectory({ ...request, sectionId: library.id, family, type });
  const facets = parseTags(payload);
  const recovered: ChannelSetupNamedFacet[] = [];
  for (const facet of facets) {
    if (facet.itemCount !== null || (library.type === 'show' && (family === 'actor' || family === 'director'))) {
      recovered.push(facet);
      continue;
    }
    const itemCount = await loadContainerCount(transport, {
      ...request,
      sectionId: library.id,
      offset: 0,
      limit: 1,
      filter: { type, [family]: facet.key },
    });
    recovered.push({ ...facet, itemCount });
  }
  target.set(library.id, recovered);
}

async function loadContainerCount(
  transport: LivePlexLibraryTransport,
  request: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0],
): Promise<number | null> {
  return readContainerCount(await transport.listLibraryItems(request));
}

function parseLibraries(payload: unknown): ChannelSetupLibraryFacet[] {
  const result: ChannelSetupLibraryFacet[] = [];
  readContainerArray(payload, 'Directory').forEach((raw, index) => {
    const record = requiredRecord(raw, `library[${String(index)}]`);
    const type = requiredString(record.type, 'library type');
    if (type !== 'movie' && type !== 'show') return;
    result.push({
      id: requiredOpaqueId(record.key, 'library key'),
      title: requiredSafeLabel(record.title, 'library title'),
      type,
      itemCount: null,
    });
  });
  return result;
}

function parsePlaylists(payload: unknown): ChannelSetupNamedFacet[] {
  return readContainerArray(payload, 'Metadata').map((raw, index) => {
    const record = requiredRecord(raw, `playlist[${String(index)}]`);
    const playlistType = requiredString(record.playlistType, 'playlist type');
    if (playlistType !== 'video') return null;
    return {
      key: requiredOpaqueId(record.ratingKey, 'playlist key'),
      title: requiredSafeLabel(record.title, 'playlist title'),
      itemCount: optionalCount(record.leafCount),
    };
  }).filter((value): value is ChannelSetupNamedFacet => value !== null);
}

function parseCollections(payload: unknown): ChannelSetupNamedFacet[] {
  return readContainerArray(payload, 'Metadata').map((raw, index) => {
    const record = requiredRecord(raw, `collection[${String(index)}]`);
    return {
      key: requiredOpaqueId(record.ratingKey, 'collection key'),
      title: requiredSafeLabel(record.title, 'collection title'),
      itemCount: optionalCount(record.childCount),
    };
  });
}

function parseTags(payload: unknown): ChannelSetupNamedFacet[] {
  return readContainerArray(payload, 'Directory').map((raw, index) => {
    const record = requiredRecord(raw, `tag[${String(index)}]`);
    return {
      key: requiredOpaqueId(record.key, 'tag key'),
      title: requiredSafeLabel(record.title, 'tag title'),
      itemCount: optionalCount(record.count),
    };
  });
}

interface PeopleCount { itemCount: number; series: Set<string> }
const TV_SCAN_PAGE_SIZE = 500;
const TV_SCAN_MAX_PAGES = 20;
const TV_SCAN_MAX_ITEMS = 10_000;

async function scanTelevisionPeople(
  transport: LivePlexLibraryTransport,
  request: { connection: PlexConnection; token: string; signal: AbortSignal },
  sectionId: string,
): Promise<{ actors: Map<string, PeopleCount>; directors: Map<string, PeopleCount>; truncated: boolean }> {
  const actors = new Map<string, PeopleCount>();
  const directors = new Map<string, PeopleCount>();
  let offset = 0;
  let pages = 0;
  let truncated = false;
  while (pages < TV_SCAN_MAX_PAGES && offset < TV_SCAN_MAX_ITEMS) {
    assertNotAborted(request.signal);
    const limit = Math.min(TV_SCAN_PAGE_SIZE, TV_SCAN_MAX_ITEMS - offset);
    const payload = await transport.listLibraryItems({ ...request, sectionId, offset, limit, filter: { type: 4 } });
    const rawItems = readContainerArray(payload, 'Metadata');
    const items = rawItems.slice(0, limit);
    for (const raw of items) {
      const item = requiredRecord(raw, 'television episode');
      const series = optionalStringLike(item.grandparentRatingKey)
        ?? normalizeName(optionalString(item.grandparentTitle) ?? '');
      if (series.length === 0) continue;
      collectPeople(actors, item.Role, series);
      collectPeople(directors, item.Director, series);
    }
    const total = readContainerCount(payload);
    offset += items.length;
    pages += 1;
    if (items.length === 0 || items.length < limit || (total !== null && offset >= total)) break;
    if (pages >= TV_SCAN_MAX_PAGES || offset >= TV_SCAN_MAX_ITEMS) truncated = true;
  }
  return { actors, directors, truncated };
}

function collectPeople(target: Map<string, PeopleCount>, raw: unknown, series: string): void {
  if (raw === undefined) return;
  if (!Array.isArray(raw)) throw new Error('Invalid television people facet payload.');
  for (const entry of raw) {
    const record = requiredRecord(entry, 'television person');
    const title = optionalString(record.tag);
    if (!title) continue;
    const key = normalizeName(title);
    const count = target.get(key) ?? { itemCount: 0, series: new Set<string>() };
    count.itemCount += 1;
    count.series.add(series);
    target.set(key, count);
  }
}

function applyPeopleCounts(
  facets: readonly ChannelSetupNamedFacet[],
  counts: Map<string, PeopleCount>,
): ChannelSetupNamedFacet[] {
  return facets.map((facet) => {
    const count = counts.get(normalizeName(facet.title));
    return count ? { ...facet, itemCount: count.itemCount, seriesCount: count.series.size } : { ...facet, itemCount: 0, seriesCount: 0 };
  });
}

function readContainerArray(payload: unknown, field: 'Directory' | 'Metadata'): unknown[] {
  const container = requiredRecord(payloadAsContainer<unknown>(payload).MediaContainer, 'MediaContainer');
  const value = container[field];
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new Error(`Invalid Plex ${field} payload.`);
  return value;
}

function readContainerCount(payload: unknown): number | null {
  const container = requiredRecord(payloadAsContainer<unknown>(payload).MediaContainer, 'MediaContainer');
  return optionalCount(container.totalSize) ?? optionalCount(container.size);
}

function requiredRecord(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`Invalid ${label} payload.`);
  }
  return value as Record<string, unknown>;
}
function requiredString(value: unknown, label: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) throw new Error(`Invalid ${label}.`);
  return value.trim();
}
function requiredStringLike(value: unknown, label: string): string {
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return requiredString(value, label);
}
function requiredOpaqueId(value: unknown, label: string): string {
  const normalized = requiredStringLike(value, label);
  if (!/^[A-Za-z0-9._-]{1,120}$/u.test(normalized)) throw new Error(`Invalid ${label}.`);
  return normalized;
}
function requiredSafeLabel(value: unknown, label: string): string {
  const normalized = stripControlCharacters(requiredString(value, label)).trim();
  if (normalized.length === 0) return 'Plex item';
  if (/https?:|file:|[A-Za-z]:[\\/]|(?:^|\s)(?:token|authorization|x-plex-token|header)\s*[:=]/iu.test(normalized)) {
    return 'Plex item';
  }
  return normalized.slice(0, 120);
}
function stripControlCharacters(value: string): string {
  return Array.from(value, (character) => {
    const code = character.codePointAt(0) ?? 0;
    return code < 32 || code === 127 ? ' ' : character;
  }).join('');
}
function optionalString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}
function optionalStringLike(value: unknown): string | null {
  return typeof value === 'number' && Number.isFinite(value) ? String(value) : optionalString(value);
}
function normalizeName(value: string): string { return value.trim().toLocaleLowerCase(); }
function optionalCount(value: unknown): number | null {
  const number = typeof value === 'string' && value.trim().length > 0 ? Number(value) : value;
  return typeof number === 'number' && Number.isFinite(number) && number >= 0 ? Math.floor(number) : null;
}
function assertNotAborted(signal: AbortSignal): void {
  if (signal.aborted) throw new DOMException('The operation was aborted.', 'AbortError');
}
