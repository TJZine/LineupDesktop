import type {
  PlexCollection,
  PlexPlaylist,
  PlexSeason,
  PlexTagDirectoryItem,
  RawCollection,
  RawDirectoryTag,
  RawPlaylist,
  RawSeason,
} from '../types.js';

export function parseSeasons(metadata: RawSeason[]): PlexSeason[] {
  return metadata.map(parseSeason);
}

function parseSeason(data: RawSeason): PlexSeason {
  return {
    ratingKey: data.ratingKey,
    key: data.key,
    title: data.title,
    index: data.index ?? 0,
    leafCount: data.leafCount ?? 0,
    viewedLeafCount: data.viewedLeafCount ?? 0,
    thumb: data.thumb ?? null,
  };
}

export function parseCollections(metadata: RawCollection[]): PlexCollection[] {
  return metadata.map(parseCollection);
}

function parseCollection(data: RawCollection): PlexCollection {
  return {
    ratingKey: data.ratingKey,
    key: data.key,
    title: data.title,
    thumb: data.thumb ?? null,
    childCount: data.childCount ?? 0,
  };
}

export function parsePlaylists(metadata: RawPlaylist[]): PlexPlaylist[] {
  return metadata.map(parsePlaylist);
}

function parsePlaylist(data: RawPlaylist): PlexPlaylist {
  return {
    ratingKey: data.ratingKey,
    key: data.key,
    title: data.title,
    thumb: data.thumb ?? null,
    duration: data.duration ?? 0,
    leafCount: data.leafCount ?? 0,
  };
}

export function parseDirectoryTags(directories: RawDirectoryTag[]): PlexTagDirectoryItem[] {
  return directories.map((entry) => {
    let count: number | null = null;
    if (typeof entry.count === 'number' && Number.isFinite(entry.count)) {
      count = entry.count;
    } else if (typeof entry.count === 'string') {
      const parsed = Number.parseInt(entry.count, 10);
      count = Number.isFinite(parsed) ? parsed : null;
    }

    const parsed: PlexTagDirectoryItem = {
      key: String(entry.key),
      title: entry.title,
      count,
    };

    if (entry.fastKey !== undefined) {
      parsed.fastKey = entry.fastKey;
    }

    if (entry.thumb !== undefined) {
      parsed.thumb = entry.thumb;
    }

    return parsed;
  });
}
