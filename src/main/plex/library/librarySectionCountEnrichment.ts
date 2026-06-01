import type { PlexLibrarySectionSummary } from '../../../contracts/plex.js';
import type { LivePlexLibraryTransport } from '../livePlexTransport.js';
import { PLEX_MEDIA_TYPES } from './constants.js';
import { PlexLibraryError } from './plexLibraryError.js';
import { extractLibrarySectionDirectories, parseLibrarySections } from './parsing/index.js';
import { toRendererSafeLibrarySectionSummary } from './libraryDomain.js';
import type { PlexLibrarySection, PlexMediaContainer, RawLibrarySection } from './types.js';

type CountEnrichmentConnection = Parameters<LivePlexLibraryTransport['listLibraryItems']>[0]['connection'];

interface EnrichLibrarySectionCountsInput {
  sections: PlexLibrarySection[];
  libraryTransport: LivePlexLibraryTransport;
  connection: CountEnrichmentConnection;
  token: string;
  signal: AbortSignal;
  shouldRethrowCountError?: (error: unknown) => boolean;
}

export async function loadLibrarySectionsWithCounts(
  input: Omit<EnrichLibrarySectionCountsInput, 'sections'>,
): Promise<PlexLibrarySectionSummary[]> {
  const payload = await input.libraryTransport.listLibrarySections({
    connection: input.connection,
    token: input.token,
    signal: input.signal,
  });
  const sections = parseLibrarySections(
    extractLibrarySectionDirectories(payloadAsContainer<RawLibrarySection>(payload), 'library sections'),
  );
  await enrichLibrarySectionCounts({ ...input, sections });
  return sections.map(toRendererSafeLibrarySectionSummary);
}

async function enrichLibrarySectionCounts(input: EnrichLibrarySectionCountsInput): Promise<void> {
  await Promise.all(input.sections.map(async (section) => {
    const contentCount = await getLibraryItemCount({
      ...input,
      sectionId: section.id,
    });
    section.contentCount = contentCount;
    if (section.type !== 'show' || contentCount === null) {
      delete section.episodeCount;
      return;
    }

    const episodeCount = await getLibraryItemCount({
      ...input,
      sectionId: section.id,
      filter: { type: PLEX_MEDIA_TYPES.EPISODE },
    });
    if (episodeCount === null) {
      delete section.episodeCount;
      return;
    }
    section.episodeCount = episodeCount;
  }));
}

async function getLibraryItemCount(input: {
  libraryTransport: LivePlexLibraryTransport;
  connection: CountEnrichmentConnection;
  token: string;
  sectionId: string;
  filter?: Readonly<Record<string, string | number>>;
  signal: AbortSignal;
  shouldRethrowCountError?: (error: unknown) => boolean;
}): Promise<number | null> {
  try {
    const payload = await input.libraryTransport.listLibraryItems({
      connection: input.connection,
      token: input.token,
      sectionId: input.sectionId,
      offset: 0,
      limit: 0,
      ...(input.filter !== undefined ? { filter: input.filter } : {}),
      signal: input.signal,
    });
    const total = getPayloadItemCount(payload);
    return typeof total === 'number' && Number.isFinite(total) ? total : null;
  } catch (error) {
    if (input.signal.aborted || input.shouldRethrowCountError?.(error) === true) {
      throw error;
    }
    return null;
  }
}

function payloadAsContainer<T>(payload: unknown): PlexMediaContainer<T> {
  if (!isPlainObject(payload) || payload.kind !== 'json') {
    throw new PlexLibraryError('parse-error', 'Plex library response was not JSON');
  }
  if (!isPlainObject(payload.data) || !isPlainObject(payload.data.MediaContainer)) {
    throw new PlexLibraryError(
      'parse-error',
      'Plex library JSON response did not include a MediaContainer object',
    );
  }
  return payload.data as unknown as PlexMediaContainer<T>;
}

function getPayloadItemCount(payload: unknown): number | null {
  if (!isPlainObject(payload) || payload.kind !== 'json') {
    return null;
  }
  if (!isPlainObject(payload.data) || !isPlainObject(payload.data.MediaContainer)) {
    return null;
  }
  const container = payload.data.MediaContainer as RawMediaCountContainer;
  const total = container.totalSize ?? container.size;
  return typeof total === 'number' && Number.isFinite(total) ? total : null;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

type RawMediaCountContainer = {
  size?: unknown;
  totalSize?: unknown;
};
