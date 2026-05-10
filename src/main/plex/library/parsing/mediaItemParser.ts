import type { PlexMediaItem, RawMediaItem } from '../types.js';
import { buildBaseMediaItem } from './mediaItemBaseParser.js';
import { applyMediaItemDetails } from './mediaItemDetailsParser.js';
import { mapMediaType } from './mediaTypeParser.js';
import { parseArrayOrEmpty, parseRequiredObject } from './parserValidation.js';

export function parseMediaItem(data: RawMediaItem): PlexMediaItem {
  const mediaItemData = parseRequiredObject<RawMediaItem>(data, 'media item');
  const item = buildBaseMediaItem(mediaItemData);
  applyMediaItemDetails(item, mediaItemData);
  return item;
}

export function parseMediaItems(metadata: unknown): PlexMediaItem[] {
  return parseArrayOrEmpty<unknown>(metadata, 'media items').map((item, index) =>
    parseMediaItem(parseRequiredObject<RawMediaItem>(item, `media items[${index}]`)),
  );
}

export { mapMediaType };
