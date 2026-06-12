import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildCustomChannelCreateInput,
  type ChannelConfig,
  type CustomChannelDraftInput,
} from '../../domain/channel/index.js';

function draft(overrides: Partial<CustomChannelDraftInput> = {}): CustomChannelDraftInput {
  return {
    number: 10,
    name: 'Custom Movies',
    hidden: false,
    playbackMode: 'sequential',
    content: [
      {
        type: 'manualItem',
        ratingKey: 'movie-1',
        title: 'Movie One',
        durationMs: 90_000,
        mediaType: 'movie',
      },
    ],
    ...overrides,
  };
}

function existingChannel(overrides: Partial<ChannelConfig> = {}): ChannelConfig {
  return {
    id: 'existing',
    number: 10,
    name: 'Existing',
    contentSource: {
      type: 'library',
      libraryId: 'library-1',
      libraryType: 'movie',
      includeWatched: true,
    },
    playbackMode: 'sequential',
    startTimeAnchor: 1,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1,
    updatedAt: 1,
    lastContentRefresh: 1,
    itemCount: 1,
    totalDurationMs: 90_000,
    ...overrides,
  };
}

test('custom channel draft maps manual entries to a hidden channel create input', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      hidden: true,
      description: 'Safe description',
      color: '#336699',
      icon: 'film',
      playbackMode: 'block',
      blockSize: 2,
      sortOrder: 'title_asc',
      skipIntros: true,
      skipCredits: true,
      startTimeAnchor: 12_000,
    }),
    [],
  );

  assert.equal(result.ok, true);
  assert.deepEqual(result.input, {
    number: 10,
    name: 'Custom Movies',
    hidden: true,
    description: 'Safe description',
    color: '#336699',
    icon: 'film',
    contentSource: {
      type: 'manual',
      items: [{ ratingKey: 'movie-1', title: 'Movie One', durationMs: 90_000 }],
    },
    playbackMode: 'block',
    blockSize: 2,
    sortOrder: 'title_asc',
    startTimeAnchor: 12_000,
    skipIntros: true,
    skipCredits: true,
  });
});

test('custom channel draft maps library show playlist collection and manual entries to mixed source', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      content: [
        {
          type: 'library',
          sourceId: 'library-1',
          title: 'Movies',
          mediaType: 'movie',
          includeWatched: false,
        },
        {
          type: 'show',
          sourceId: 'show-1',
          title: 'The Show',
          seasonFilter: [1, 2],
        },
        {
          type: 'collection',
          sourceId: 'collection-1',
          title: 'Collection',
        },
        {
          type: 'playlist',
          sourceId: 'playlist-1',
          title: 'Playlist',
        },
        {
          type: 'manualItem',
          ratingKey: 'episode-1',
          title: 'Episode One',
          durationMs: 30_000,
          mediaType: 'episode',
        },
      ],
    }),
    [],
  );

  assert.equal(result.ok, true);
  assert.deepEqual(result.contentSource, {
    type: 'mixed',
    mixMode: 'sequential',
    sources: [
      {
        type: 'library',
        libraryId: 'library-1',
        libraryType: 'movie',
        includeWatched: false,
      },
      {
        type: 'show',
        showKey: 'show-1',
        showName: 'The Show',
        seasonFilter: [1, 2],
      },
      {
        type: 'collection',
        collectionKey: 'collection-1',
        collectionName: 'Collection',
      },
      {
        type: 'playlist',
        playlistKey: 'playlist-1',
        playlistName: 'Playlist',
      },
      {
        type: 'manual',
        items: [{ ratingKey: 'episode-1', title: 'Episode One', durationMs: 30_000 }],
      },
    ],
  });
});

test('custom channel draft validation rejects duplicate numbers and duplicate content', () => {
  const duplicateNumber = buildCustomChannelCreateInput(draft(), [existingChannel()]);
  assert.equal(duplicateNumber.ok, false);
  assert.deepEqual(duplicateNumber.issues.map((issue) => issue.code), [
    'duplicate-number',
  ]);

  const duplicateContent = buildCustomChannelCreateInput(
    draft({
      content: [
        {
          type: 'manualItem',
          ratingKey: 'movie-1',
          title: 'Movie One',
          durationMs: 90_000,
          mediaType: 'movie',
        },
        {
          type: 'manualItem',
          ratingKey: 'movie-1',
          title: 'Movie One Again',
          durationMs: 91_000,
          mediaType: 'movie',
        },
      ],
    }),
    [],
  );
  assert.equal(duplicateContent.ok, false);
  assert.ok(duplicateContent.issues.some((issue) => issue.code === 'duplicate-content'));
});

test('custom channel draft validation rejects invalid number block size and empty content', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      number: 0,
      name: ' ',
      playbackMode: 'sequential',
      blockSize: 2,
      content: [],
    }),
    [],
  );

  assert.equal(result.ok, false);
  assert.deepEqual(
    result.issues.map((issue) => issue.code),
    ['missing-name', 'invalid-number', 'invalid-block-size', 'empty-content'],
  );
});

test('custom channel draft validation rejects malformed booleans and fractional block size', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      hidden: 'yes' as never,
      includeWatched: 'no' as never,
      playbackMode: 'block',
      blockSize: 2.5,
      content: [{
        type: 'library',
        sourceId: 'library-1',
        title: 'Library',
        mediaType: 'movie',
        includeWatched: 'no' as never,
      }],
    }),
    [],
  );

  assert.equal(result.ok, false);
  assert.deepEqual(
    result.issues.map((issue) => issue.code),
    ['invalid-hidden', 'invalid-include-watched', 'invalid-block-size', 'invalid-content'],
  );
});

test('custom channel draft validation rejects invalid sort order and start anchor', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      sortOrder: 'random-by-secret' as never,
      startTimeAnchor: Number.NaN,
    }),
    [],
  );

  assert.equal(result.ok, false);
  assert.deepEqual(result.issues.map((issue) => issue.code), [
    'invalid-sort-order',
    'invalid-start-time-anchor',
  ]);
});

test('custom channel draft validation rejects url path token and header shaped ids', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      id: 'https://plex.example/channel/1',
      content: [
        {
          type: 'manualItem',
          ratingKey: 'https://plex.example/library/metadata/1?query=value',
          title: 'Leaky Movie',
          durationMs: 90_000,
          mediaType: 'movie',
        },
        {
          type: 'library',
          sourceId: '../library/path',
          title: 'Library',
          mediaType: 'movie',
        },
      ],
    }),
    [],
  );

  assert.equal(result.ok, false);
  assert.ok(result.issues.some((issue) => issue.code === 'invalid-draft-id'));
  assert.deepEqual(
    result.issues
      .filter((issue) => issue.code === 'invalid-content')
      .map((issue) => issue.contentIndex),
    [0, 1],
  );
});

test('custom channel draft validation rejects malformed content without throwing', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      content: [
        {
          type: 'manualItem',
          ratingKey: 123,
          title: 'Movie',
          durationMs: 90_000,
          mediaType: 'movie',
        } as never,
        {
          type: 'unknown',
          sourceId: 'source-1',
          title: 'Unknown',
        } as never,
        {
          type: 'library',
          sourceId: 123,
          title: 'Library',
          mediaType: 'movie',
        } as never,
        {
          type: 'library',
          sourceId: 'library-1',
          title: 'Episodes',
          mediaType: 'episode',
        } as never,
        {
          type: 'manualItem',
          ratingKey: 'show-1',
          title: 'Show',
          durationMs: 90_000,
          mediaType: 'show',
        } as never,
      ],
    }),
    [],
  );

  assert.equal(result.ok, false);
  assert.deepEqual(
    result.issues
      .filter((issue) => issue.code === 'invalid-content')
      .map((issue) => issue.contentIndex),
    [0, 1, 2, 3, 4],
  );
});

test('custom channel draft validation rejects non-array content without throwing', () => {
  const result = buildCustomChannelCreateInput(
    draft({
      content: 'movie-1' as never,
    }),
    [],
  );

  assert.equal(result.ok, false);
  assert.deepEqual(result.issues.map((issue) => issue.code), ['empty-content']);
});
