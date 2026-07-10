import type {
  CustomChannelContentEntryInput,
  CustomChannelMediaCard,
  CustomChannelMediaMetadata,
  CustomChannelMediaPage,
  CustomChannelMediaType,
  CustomChannelRuntimeError,
  CustomChannelSourceRef,
} from '../../contracts/customChannels.js';
import type {
  ArtworkRef,
} from '../../contracts/artwork.js';
import type {
  PlexIpcResult,
  PlexListLibraryItemsValue,
  PlexMediaItemSummary,
  PlexSearchLibraryValue,
  PlexRendererMediaType,
} from '../../contracts/plex.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import { PLEX_MEDIA_TYPES } from '../plex/library/index.js';

export interface CustomChannelMediaPickerOptions {
  plexRuntime: Pick<DesktopPlexRuntime, 'listLibraryItems' | 'searchLibrary' | 'getMetadata'>;
  artworkForItem?: (item: PlexMediaItemSummary) => ArtworkRef | null;
}

export class CustomChannelMediaPicker {
  private readonly plexRuntime: CustomChannelMediaPickerOptions['plexRuntime'];
  private readonly artworkForItem: NonNullable<CustomChannelMediaPickerOptions['artworkForItem']>;

  public constructor(options: CustomChannelMediaPickerOptions) {
    this.plexRuntime = options.plexRuntime;
    this.artworkForItem = options.artworkForItem ?? (() => null);
  }

  public async listMedia(
    requestId: string,
    input: {
      sourceType: 'library' | 'search';
      sourceId?: string;
      query?: string;
      offset?: number;
      limit?: number;
      mediaTypes?: readonly CustomChannelMediaType[];
      draftContent?: readonly CustomChannelContentEntryInput[];
    },
  ): Promise<{ ok: true; value: CustomChannelMediaPage } | { ok: false; error: CustomChannelRuntimeError }> {
    const offset = normalizeOffset(input.offset);
    const limit = normalizeLimit(input.limit);
    if (input.sourceType === 'library') {
      if (!isSafeId(input.sourceId)) return { ok: false, error: validationError('listMedia') };
      const filter = libraryFilterForMediaTypes(input.mediaTypes);
      const result = await this.plexRuntime.listLibraryItems(requestId, {
        sectionId: input.sourceId,
        offset,
        limit,
        ...(filter !== undefined ? { filter } : {}),
      });
      return mapListResult(result, input.sourceId, input.draftContent ?? [], this.artworkForItem);
    }
    if (input.sourceType === 'search') {
      const query = input.query?.trim() ?? '';
      if (query.length === 0 || query.length > 128) return { ok: false, error: validationError('listMedia') };
      const types = input.mediaTypes === undefined
        ? DEFAULT_SEARCH_MEDIA_TYPES
        : mapPlexSearchTypes(input.mediaTypes);
      const result = await this.plexRuntime.searchLibrary(requestId, {
        query,
        limit: offset + limit + 1,
        ...(input.sourceId !== undefined ? { sectionId: input.sourceId } : {}),
        ...(types !== undefined ? { types } : {}),
      });
      return mapSearchResult(result, offset, limit, input.draftContent ?? [], this.artworkForItem);
    }
    return { ok: false, error: validationError('listMedia') };
  }

  public async getMediaMetadata(
    requestId: string,
    ratingKey: string,
  ): Promise<{ ok: true; value: CustomChannelMediaMetadata } | { ok: false; error: CustomChannelRuntimeError }> {
    if (!isSafeId(ratingKey)) return { ok: false, error: validationError('getMediaMetadata') };
    const result = await this.plexRuntime.getMetadata(requestId, ratingKey);
    if (!result.ok) return { ok: false, error: plexError('getMediaMetadata') };
    if (result.value.item === null) return { ok: false, error: notFoundError('getMediaMetadata') };
    if (normalizeMediaType(result.value.item.type) === null) return { ok: false, error: unsupportedMediaError('getMediaMetadata') };
    return { ok: true, value: mapMetadata(result.value.item, this.artworkForItem) };
  }
}

function mapListResult(
  result: PlexIpcResult<PlexListLibraryItemsValue>,
  sectionId: string,
  draftContent: readonly CustomChannelContentEntryInput[],
  artworkForItem: (item: PlexMediaItemSummary) => ArtworkRef | null,
): { ok: true; value: CustomChannelMediaPage } | { ok: false; error: CustomChannelRuntimeError } {
  if (!result.ok) return { ok: false, error: plexError('listMedia') };
  const items = result.value.items.flatMap((item) =>
    mapCard(item, { sourceType: 'library', sourceId: sectionId, title: sectionId }, draftContent, artworkForItem),
  );
  return {
    ok: true,
    value: {
      items,
      offset: result.value.offset,
      limit: result.value.limit,
      total: null,
      hasMore: result.value.items.length >= result.value.limit,
    },
  };
}

function mapSearchResult(
  result: PlexIpcResult<PlexSearchLibraryValue>,
  offset: number,
  limit: number,
  draftContent: readonly CustomChannelContentEntryInput[],
  artworkForItem: (item: PlexMediaItemSummary) => ArtworkRef | null,
): { ok: true; value: CustomChannelMediaPage } | { ok: false; error: CustomChannelRuntimeError } {
  if (!result.ok) return { ok: false, error: plexError('listMedia') };
  const addableItems = result.value.items.flatMap((item) =>
    mapCard(item, { sourceType: 'search', sourceId: 'search', title: result.value.query }, draftContent, artworkForItem),
  );
  const items = addableItems.slice(offset, offset + limit);
  return {
    ok: true,
    value: {
      items,
      offset,
      limit,
      total: addableItems.length,
      hasMore: addableItems.length > offset + limit,
    },
  };
}

function mapCard(
  item: PlexMediaItemSummary,
  source: CustomChannelSourceRef,
  draftContent: readonly CustomChannelContentEntryInput[],
  artworkForItem: (item: PlexMediaItemSummary) => ArtworkRef | null,
): CustomChannelMediaCard[] {
  const type = normalizeMediaType(item.type);
  if (type === null) return [];
  const artwork = artworkForItem(item);
  return [{
    ratingKey: item.ratingKey,
    type,
    title: item.title,
    subtitle: subtitleForItem(item),
    year: finiteOrNull(item.year),
    durationMs: finiteOrNull(item.durationMs),
    ...(item.parentTitle !== undefined ? { parentTitle: item.parentTitle } : {}),
    ...(item.seasonNumber !== undefined ? { seasonNumber: item.seasonNumber } : {}),
    ...(item.episodeNumber !== undefined ? { episodeNumber: item.episodeNumber } : {}),
    ...(item.contentRating !== undefined ? { contentRating: item.contentRating } : {}),
    source,
    ...(artwork !== null ? { artwork } : {}),
    availability: draftContent.some((entry) => entry.type === 'manualItem' && entry.ratingKey === item.ratingKey)
      ? 'available'
      : 'available',
  } satisfies CustomChannelMediaCard];
}

function mapMetadata(
  item: PlexMediaItemSummary,
  artworkForItem: (item: PlexMediaItemSummary) => ArtworkRef | null,
): CustomChannelMediaMetadata {
  const type = normalizeMediaType(item.type);
  if (type === null) {
    throw new Error('Unsupported metadata type reached mapper.');
  }
  const artwork = artworkForItem(item);
  return {
    ratingKey: item.ratingKey,
    type,
    title: item.title,
    subtitle: subtitleForItem(item),
    summary: item.summary || null,
    year: finiteOrNull(item.year),
    durationMs: finiteOrNull(item.durationMs),
    ...(item.parentTitle !== undefined ? { parentTitle: item.parentTitle } : {}),
    ...(item.seasonNumber !== undefined ? { seasonNumber: item.seasonNumber } : {}),
    ...(item.episodeNumber !== undefined ? { episodeNumber: item.episodeNumber } : {}),
    ...(item.contentRating !== undefined ? { contentRating: item.contentRating } : {}),
    genres: item.genres ?? [],
    ...(artwork !== null ? { artwork } : {}),
    availability: 'available',
  };
}

function normalizeMediaType(type: PlexMediaItemSummary['type']): CustomChannelMediaType | null {
  return type === 'movie' || type === 'show' || type === 'episode' ? type : null;
}

function subtitleForItem(item: PlexMediaItemSummary): string {
  if (item.type === 'episode' && item.parentTitle) return item.parentTitle;
  if (item.year > 0) return String(item.year);
  return item.type;
}

function finiteOrNull(value: number): number | null {
  return Number.isFinite(value) && value > 0 ? value : null;
}

function normalizeOffset(value: unknown): number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0 ? Math.min(value, 10_000) : 0;
}

function normalizeLimit(value: unknown): number {
  return typeof value === 'number' && Number.isInteger(value) && value > 0 ? Math.min(value, 48) : 24;
}

function isSafeId(value: unknown): value is string {
  return typeof value === 'string' && value.trim() === value && /^[A-Za-z0-9._~-]{1,128}$/u.test(value);
}

function mapPlexSearchTypes(values: readonly CustomChannelMediaType[]): PlexRendererMediaType[] {
  return values.flatMap((value) => (
    value === 'movie' || value === 'show' || value === 'episode' ? [value] : []
  ));
}

function libraryFilterForMediaTypes(
  values: readonly CustomChannelMediaType[] | undefined,
): Readonly<Record<string, string | number>> | undefined {
  if (values === undefined || values.length !== 1) {
    return undefined;
  }
  const [value] = values;
  if (value === 'movie') {
    return { type: PLEX_MEDIA_TYPES.MOVIE };
  }
  if (value === 'show') {
    return { type: PLEX_MEDIA_TYPES.SHOW };
  }
  if (value === 'episode') {
    return { type: PLEX_MEDIA_TYPES.EPISODE };
  }
  return undefined;
}

const DEFAULT_SEARCH_MEDIA_TYPES: readonly PlexRendererMediaType[] = ['movie', 'show', 'episode'];

function validationError(operation: 'listMedia' | 'getMediaMetadata'): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_VALIDATION_FAILED',
    message: 'Custom channel media request is invalid.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function plexError(operation: 'listMedia' | 'getMediaMetadata'): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_PLEX_REQUIRED',
    message: 'Plex library access is required.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function notFoundError(operation: 'getMediaMetadata'): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_NOT_FOUND',
    message: 'Custom channel media was not found.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function unsupportedMediaError(operation: 'getMediaMetadata'): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_STALE_MEDIA',
    message: 'Custom channel media is not supported.',
    retryable: false,
    recoverable: true,
    operation,
  };
}
