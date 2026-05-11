import type { PlexMediaItem, RawMediaItem } from '../types.js';
import { parseArrayOrEmpty, parseRequiredObject } from './parserValidation.js';

const UNIX_TIMESTAMP_MS = 1000;

export function applyMediaItemDetails(item: PlexMediaItem, data: RawMediaItem): void {
  assignOptionalMediaMetadata(item, data);
  assignMediaCredits(item, data);
  assignClearLogo(item, data);
  assignEpisodeMetadata(item, data);
}

function assignOptionalMediaMetadata(item: PlexMediaItem, data: RawMediaItem): void {
  assignOptional(item, 'originalTitle', data.originalTitle);
  assignOptional(item, 'banner', data.banner ?? null, data.banner !== undefined);
  assignOptional(item, 'rating', data.rating);
  assignOptional(item, 'audienceRating', data.audienceRating);
  assignOptional(item, 'contentRating', data.contentRating);
  assignOptional(item, 'lastViewedAt', toPlexDateOrUndefined(data.lastViewedAt));
}

function assignMediaCredits(item: PlexMediaItem, data: RawMediaItem): void {
  assignTagNames(item, 'genres', data.Genre);
  assignTagNames(item, 'directors', data.Director);
  assignActorRoles(item, data.Role);
  assignTagNames(item, 'studios', data.Studio);
}

function assignClearLogo(item: PlexMediaItem, data: RawMediaItem): void {
  if (!Array.isArray(data.Image)) {
    return;
  }

  const entry = data.Image.find(
    (image) =>
      image &&
      image.type === 'clearLogo' &&
      typeof image.url === 'string' &&
      image.url.length > 0,
  );

  if (entry?.url) {
    item.clearLogo = entry.url;
  }
}

function assignEpisodeMetadata(item: PlexMediaItem, data: RawMediaItem): void {
  assignOptional(item, 'grandparentTitle', data.grandparentTitle);
  assignOptional(item, 'parentTitle', data.parentTitle);
  assignOptional(
    item,
    'grandparentThumb',
    data.grandparentThumb ?? null,
    data.grandparentThumb !== undefined,
  );
  assignOptional(item, 'parentThumb', data.parentThumb ?? null, data.parentThumb !== undefined);
  assignOptional(item, 'grandparentRatingKey', data.grandparentRatingKey);
  assignOptional(item, 'parentRatingKey', data.parentRatingKey);
  assignOptional(item, 'seasonNumber', data.parentIndex);
  assignOptional(item, 'episodeNumber', data.index);
}

export function toPlexDate(value: number | undefined): Date {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return new Date(0);
  }

  const date = new Date(value * UNIX_TIMESTAMP_MS);
  return Number.isNaN(date.getTime()) ? new Date(0) : date;
}

function toPlexDateOrUndefined(value: number | undefined): Date | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return undefined;
  }

  const date = toPlexDate(value);
  return date.getTime() === 0 && value !== 0 ? undefined : date;
}

function collectTagNames(tags: unknown): string[] {
  return parseArrayOrEmpty<unknown>(tags, 'media item tags')
    .map((tag, index) =>
      parseRequiredObject<{ tag?: string }>(tag, `media item tags[${index}]`),
    )
    .map((tag) => tag.tag)
    .filter((tag): tag is string => Boolean(tag));
}

function assignTagNames(
  item: PlexMediaItem,
  key: 'genres' | 'directors' | 'studios',
  tags: unknown,
): void {
  const names = collectTagNames(tags);

  if (names.length > 0) {
    item[key] = names;
  }
}

function assignActorRoles(item: PlexMediaItem, roles: unknown): void {
  const parsedRoles = parseActorRoles(roles);

  if (parsedRoles.length > 0) {
    item.actorRoles = parsedRoles;
    item.actors = parsedRoles.map((role) => role.name);
  }
}

function parseActorRoles(
  roles: unknown,
): Array<{ name: string; role: string | null; thumb: string | null }> {
  return parseArrayOrEmpty<unknown>(roles, 'media item roles')
    .map((entry, index) =>
      parseRequiredObject<{ tag?: string; role?: string | null; thumb?: string | null }>(
        entry,
        `media item roles[${index}]`,
      ),
    )
    .map((entry) => ({
      name: entry.tag?.trim() ?? '',
      role: typeof entry.role === 'string' && entry.role.trim().length > 0 ? entry.role.trim() : null,
      thumb: entry.thumb ?? null,
    }))
    .filter((entry) => entry.name.length > 0);
}

function assignOptional<K extends keyof PlexMediaItem>(
  item: PlexMediaItem,
  key: K,
  value: PlexMediaItem[K] | undefined,
  condition = value !== undefined,
): void {
  if (condition) {
    item[key] = value as PlexMediaItem[K];
  }
}
