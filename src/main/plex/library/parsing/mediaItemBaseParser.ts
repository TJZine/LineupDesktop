import type { PlexMediaItem, RawMediaItem } from '../types.js';
import { parseMediaFiles } from './mediaFileParser.js';
import { toPlexDate } from './mediaItemDetailsParser.js';
import { mapMediaType } from './mediaTypeParser.js';
import { parseRequiredString } from './parserValidation.js';

export function buildBaseMediaItem(data: RawMediaItem): PlexMediaItem {
  return {
    ...buildMediaIdentity(data),
    ...buildMediaMetadata(data),
  };
}

function buildMediaIdentity(
  data: RawMediaItem,
): Pick<PlexMediaItem, 'ratingKey' | 'key' | 'type' | 'title' | 'sortTitle'> {
  const title = parseRequiredString(data.title, 'media item', 'title');

  return {
    ratingKey: parseRequiredString(data.ratingKey, 'media item', 'ratingKey'),
    key: parseRequiredString(data.key, 'media item', 'key'),
    type: mapMediaType(parseRequiredString(data.type, 'media item', 'type')),
    title,
    sortTitle: data.titleSort ?? title,
  };
}

function buildMediaMetadata(
  data: RawMediaItem,
): Pick<
  PlexMediaItem,
  | 'summary'
  | 'year'
  | 'durationMs'
  | 'addedAt'
  | 'updatedAt'
  | 'thumb'
  | 'art'
  | 'viewOffset'
  | 'viewCount'
  | 'media'
> {
  return {
    summary: data.summary ?? '',
    year: data.year ?? 0,
    durationMs: data.duration ?? 0,
    addedAt: toPlexDate(data.addedAt),
    updatedAt: toPlexDate(data.updatedAt),
    thumb: data.thumb ?? null,
    art: data.art ?? null,
    viewOffset: data.viewOffset,
    viewCount: data.viewCount,
    media: parseMediaFiles(data.Media),
  };
}
