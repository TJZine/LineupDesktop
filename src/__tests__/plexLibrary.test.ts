import test from 'node:test';
import assert from 'node:assert/strict';

import {
  containsPlexForbiddenRendererField,
  PLEX_FORBIDDEN_RENDERER_FIELD_KEYS,
  type PlexMediaItemSummary,
} from '../contracts/plex.js';
import { PlexLibraryError } from '../main/plex/library/plexLibraryError.js';
import {
  extractSearchHubMetadata,
  extractSearchHubs,
  getPlexRequestIntentForChannelSetup,
  getTagDirectoryMediaTypesForLibraryType,
  normalizeLibraryPagination,
  parseCollections,
  parseDirectoryTags,
  parseLibrarySections,
  parseMediaItem,
  parsePlaylists,
  parseSeasons,
  shouldContinueLibraryPagination,
  toRendererSafeCollectionSummary,
  toRendererSafeLibrarySectionSummary,
  toRendererSafeMediaItemSummary,
  toRendererSafePlaylistSummary,
  toRendererSafeTagDirectorySummary,
} from '../main/plex/library/index.js';
import { PLEX_LIBRARY_CONSTANTS, PLEX_MEDIA_TYPES } from '../main/plex/library/constants.js';
import type {
  PlexMediaContainer,
  RawCollection,
  RawDirectoryTag,
  RawLibrarySection,
  RawMediaItem,
  RawPlaylist,
  RawSeason,
} from '../main/plex/library/types.js';

test('plex library parser parses library sections and renderer-safe section summaries', () => {
  const sections = parseLibrarySections([
    {
      key: '1',
      uuid: 'library-movies',
      title: 'Movies',
      type: 'movie',
      agent: 'scanner-agent',
      scanner: 'scanner-name',
      art: 'art-key',
      thumb: 'thumb-key',
      scannedAt: 1_700_000_000,
    },
    {
      key: '2',
      uuid: 'library-shows',
      title: 'Shows',
      type: 'show',
      agent: 'scanner-agent',
      scanner: 'scanner-name',
    },
  ] satisfies RawLibrarySection[]);

  assert.equal(sections.length, 2);
  assert.deepEqual(sections.map((section) => section.type), ['movie', 'show']);
  assert.equal(sections[0]?.lastScannedAt.getTime(), 1_700_000_000_000);
  assert.equal(sections[1]?.art, null);

  const summary = toRendererSafeLibrarySectionSummary(sections[0]!);
  assert.deepEqual(summary, {
    id: '1',
    title: 'Movies',
    type: 'movie',
    contentCount: null,
    lastScannedAtMs: 1_700_000_000_000,
  });
  assertRendererSafe(summary);
});

test('plex media parser parses media files, streams, roles, and renderer-safe item summaries', () => {
  const item = parseMediaItem(createRawEpisode());

  assert.equal(item.ratingKey, 'episode-1');
  assert.equal(item.type, 'episode');
  assert.equal(item.title, 'Pilot');
  assert.deepEqual(item.actors, ['Ada Viewer']);
  assert.deepEqual(item.actorRoles, [{ name: 'Ada Viewer', role: 'Lead', thumb: 'actor-thumb-key' }]);
  assert.equal(item.clearLogo, 'clear-logo-key');
  assert.equal(item.media[0]?.videoCodec, 'h264');
  assert.equal(item.media[0]?.audioCodec, 'aac');
  assert.equal(item.media[0]?.parts[0]?.file, 'episode-file-redacted.mkv');
  assert.deepEqual(item.media[0]?.parts[0]?.streams[0], {
    id: 'stream-1',
    streamType: 1,
    codec: 'h264',
    displayTitle: '1080p',
    doviProfile: '8',
    doviPresent: true,
  });

  const summary = toRendererSafeMediaItemSummary(item);
  assert.deepEqual(summary, {
    ratingKey: 'episode-1',
    type: 'episode',
    title: 'Pilot',
    sortTitle: 'Pilot',
    summary: 'A metadata-only episode fixture.',
    year: 2026,
    durationMs: 1_800_000,
    addedAtMs: 1_700_000_100_000,
    updatedAtMs: 1_700_000_200_000,
    rating: 8.5,
    audienceRating: 8.2,
    contentRating: 'TV-PG',
    genres: ['Drama'],
    directors: ['Dana Director'],
    actors: ['Ada Viewer'],
    studios: ['Lineup Studio'],
    grandparentTitle: 'Example Show',
    parentTitle: 'Season 1',
    seasonNumber: 1,
    episodeNumber: 1,
    viewOffset: 120_000,
    viewCount: 2,
    lastViewedAtMs: 1_700_000_300_000,
  } satisfies PlexMediaItemSummary);
  assertRendererSafe(summary);
});

test('plex parser throws sanitized typed parse errors for invalid payloads', () => {
  assert.throws(
    () => parseLibrarySections([null] as unknown as RawLibrarySection[]),
    (error: unknown) =>
      error instanceof PlexLibraryError &&
      error.code === 'parse-error' &&
      error.message.includes('library sections[0]'),
  );

  assert.throws(
    () => parseMediaItem({ ...createRawEpisode(), title: undefined } as unknown as RawMediaItem),
    (error: unknown) =>
      error instanceof PlexLibraryError &&
      error.code === 'parse-error' &&
      error.message === 'Invalid media item payload: title is required',
  );
});

test('plex listing parsers cover seasons, collections, playlists, and tag directories', () => {
  const seasons = parseSeasons([
    {
      ratingKey: 'season-1',
      key: 'season-key-1',
      title: 'Season 1',
      index: 1,
      leafCount: 10,
      viewedLeafCount: 3,
      thumb: 'season-thumb-key',
    },
  ] satisfies RawSeason[]);
  const collections = parseCollections([
    {
      ratingKey: 'collection-1',
      key: 'collection-key-1',
      title: 'Favorites',
      childCount: 4,
      thumb: 'collection-thumb-key',
    },
  ] satisfies RawCollection[]);
  const playlists = parsePlaylists([
    {
      ratingKey: 'playlist-1',
      key: 'playlist-key-1',
      title: 'Queue',
      duration: 3_600_000,
      leafCount: 2,
      thumb: 'playlist-thumb-key',
    },
  ] satisfies RawPlaylist[]);
  const tags = parseDirectoryTags([
    {
      key: 'actor-key-1',
      title: 'Ada Viewer',
      count: '12',
      fastKey: 'fast-actor-key-1',
      thumb: 'actor-thumb-key',
    },
  ] satisfies RawDirectoryTag[]);

  assert.deepEqual(seasons[0], {
    ratingKey: 'season-1',
    key: 'season-key-1',
    title: 'Season 1',
    index: 1,
    leafCount: 10,
    viewedLeafCount: 3,
    thumb: 'season-thumb-key',
  });
  assert.deepEqual(toRendererSafeCollectionSummary(collections[0]!), {
    ratingKey: 'collection-1',
    title: 'Favorites',
    childCount: 4,
  });
  assert.deepEqual(toRendererSafePlaylistSummary(playlists[0]!), {
    ratingKey: 'playlist-1',
    title: 'Queue',
    duration: 3_600_000,
    leafCount: 2,
  });
  assert.deepEqual(toRendererSafeTagDirectorySummary(tags[0]!), {
    key: 'actor-key-1',
    title: 'Ada Viewer',
    count: 12,
  });
  assertRendererSafe([
    toRendererSafeCollectionSummary(collections[0]!),
    toRendererSafePlaylistSummary(playlists[0]!),
    toRendererSafeTagDirectorySummary(tags[0]!),
  ]);
});

test('plex search hub extraction returns typed hub metadata and validates malformed hubs', () => {
  const response: PlexMediaContainer<RawMediaItem> = {
    MediaContainer: {
      Hub: [
        {
          type: 'movie',
          hubIdentifier: 'search.movies',
          size: 1,
          title: 'Movies',
          Metadata: [createRawEpisode({ ratingKey: 'movie-1', type: 'movie', title: 'Movie Result' })],
        },
        {
          type: 'show',
          hubIdentifier: 'search.shows',
          size: 0,
          title: 'Shows',
        },
      ],
    },
  };

  const hubs = extractSearchHubs(response, 'search');
  assert.equal(hubs.length, 2);
  assert.equal(extractSearchHubMetadata(hubs[0]!, 'search movie hub')[0]?.title, 'Movie Result');
  assert.deepEqual(extractSearchHubMetadata(hubs[1]!, 'search show hub'), []);

  assert.throws(
    () => extractSearchHubs({ MediaContainer: { Hub: null } } as never, 'search'),
    PlexLibraryError,
  );
});

test('plex request intent, tag directory policy, and pagination helpers match upstream behavior', () => {
  assert.equal(getPlexRequestIntentForChannelSetup('preview'), 'preview');
  assert.equal(getPlexRequestIntentForChannelSetup('build'), 'background');
  assert.deepEqual(getTagDirectoryMediaTypesForLibraryType('show'), {
    genreType: PLEX_MEDIA_TYPES.SHOW,
    detailType: PLEX_MEDIA_TYPES.EPISODE,
  });
  assert.deepEqual(getTagDirectoryMediaTypesForLibraryType('movie'), {
    genreType: PLEX_MEDIA_TYPES.MOVIE,
    detailType: PLEX_MEDIA_TYPES.MOVIE,
  });
  assert.deepEqual(normalizeLibraryPagination({ offset: -3, limit: 20_000 }), {
    offset: 0,
    limit: PLEX_LIBRARY_CONSTANTS.ALL_LEAVES_PAGE_SIZE,
  });
  assert.equal(
    shouldContinueLibraryPagination({
      iterations: PLEX_LIBRARY_CONSTANTS.MAX_PAGINATION_ITERATIONS,
      fetchedCount: 100,
      pageSize: 100,
    }),
    false,
  );
  assert.equal(
    shouldContinueLibraryPagination({
      iterations: 1,
      fetchedCount: 100,
      totalSize: 250,
      pageSize: 100,
    }),
    true,
  );
});

test('plex renderer-facing summaries and contract vocabulary reject forbidden fields recursively', () => {
  const itemSummary = toRendererSafeMediaItemSummary(parseMediaItem(createRawEpisode()));
  assertRendererSafe(itemSummary);
  assert.equal(
    containsPlexForbiddenRendererField({
      item: itemSummary,
      nested: { serverUri: 'redacted-by-contract' },
    }),
    true,
  );
  assert.equal(PLEX_FORBIDDEN_RENDERER_FIELD_KEYS.includes('serverUri'), true);
  assert.equal(PLEX_FORBIDDEN_RENDERER_FIELD_KEYS.includes('tokenizedUrl'), true);
  assert.equal(PLEX_FORBIDDEN_RENDERER_FIELD_KEYS.includes('rawPlexPayload'), true);
  assert.equal(JSON.stringify(itemSummary).includes('episode-file-redacted.mkv'), false);
  assert.equal(JSON.stringify(itemSummary).includes('clear-logo-key'), false);
});

function assertRendererSafe(value: unknown): void {
  assert.equal(containsPlexForbiddenRendererField(value), false);
}

function createRawEpisode(overrides: Partial<RawMediaItem> = {}): RawMediaItem {
  return {
    ratingKey: 'episode-1',
    key: 'metadata-key-episode-1',
    type: 'episode',
    title: 'Pilot',
    titleSort: 'Pilot',
    summary: 'A metadata-only episode fixture.',
    year: 2026,
    duration: 1_800_000,
    addedAt: 1_700_000_100,
    updatedAt: 1_700_000_200,
    thumb: 'episode-thumb-key',
    art: 'episode-art-key',
    banner: 'episode-banner-key',
    rating: 8.5,
    audienceRating: 8.2,
    contentRating: 'TV-PG',
    Genre: [{ tag: 'Drama' }],
    Director: [{ tag: 'Dana Director' }],
    Role: [{ tag: 'Ada Viewer', role: 'Lead', thumb: 'actor-thumb-key' }],
    Studio: [{ tag: 'Lineup Studio' }],
    Image: [{ type: 'clearLogo', url: 'clear-logo-key' }],
    grandparentTitle: 'Example Show',
    parentTitle: 'Season 1',
    parentIndex: 1,
    index: 1,
    viewOffset: 120_000,
    viewCount: 2,
    lastViewedAt: 1_700_000_300,
    grandparentRatingKey: 'show-1',
    parentRatingKey: 'season-1',
    Media: [
      {
        id: 'media-1',
        duration: 1_800_000,
        bitrate: 4_000,
        width: 1920,
        height: 1080,
        aspectRatio: 1.78,
        videoCodec: 'H264',
        audioCodec: 'AAC',
        audioChannels: 2,
        container: 'MKV',
        videoResolution: '1080',
        Part: [
          {
            id: 'part-1',
            key: 'part-key-1',
            duration: 1_800_000,
            file: 'episode-file-redacted.mkv',
            size: 42_000,
            container: 'mkv',
            Stream: [
              {
                id: 'stream-1',
                streamType: 1,
                codec: 'h264',
                displayTitle: '1080p',
                DOVIProfile: 8,
                DOVIPresent: 'true',
              },
              {
                id: 'stream-2',
                streamType: 2,
                codec: 'aac',
                language: 'English',
                selected: true,
              },
            ],
          },
        ],
      },
    ],
    ...overrides,
  };
}
