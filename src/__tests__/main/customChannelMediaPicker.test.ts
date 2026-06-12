import test from 'node:test';
import assert from 'node:assert/strict';

import { isSafeArtworkRefId } from '../../contracts/artwork.js';
import { containsCustomChannelForbiddenRendererField } from '../../contracts/customChannels.js';
import type { PlexIpcResult, PlexListLibraryItemsValue, PlexMediaItemSummary, PlexSearchLibraryValue, PlexGetMetadataValue } from '../../contracts/plex.js';
import { CustomChannelArtworkProxy } from '../../main/channel/customChannelArtworkProxy.js';
import { CustomChannelMediaPicker } from '../../main/channel/customChannelMediaPicker.js';

test('custom channel media picker lists safe paged media cards', async () => {
  const picker = new CustomChannelMediaPicker({
    plexRuntime: plexRuntimeFixture(),
    artworkForItem: (item) => ({
      id: `artwork-${item.ratingKey}abcdefghijkl`,
      kind: 'poster',
      expiresAtMs: 9_000,
      altText: item.title,
      status: 'available',
    }),
  });

  const result = await picker.listMedia('media-list', {
    sourceType: 'library',
    sourceId: 'movies',
    offset: 0,
    limit: 24,
    draftContent: [{ type: 'manualItem', ratingKey: 'movie-1', title: 'Feature', durationMs: 90_000, mediaType: 'movie' }],
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value.items.map((item) => ({
    ratingKey: item.ratingKey,
    title: item.title,
	    sourceType: item.source.sourceType,
	    artwork: item.artwork?.status,
	    availability: item.availability,
	  })) : [], [{
	    ratingKey: 'movie-1',
	    title: 'Feature',
	    sourceType: 'library',
	    artwork: 'available',
	    availability: 'available',
	  }]);
  assert.equal(containsCustomChannelForbiddenRendererField(result), false);
  assert.doesNotMatch(JSON.stringify(result), /"thumb"|"art"|url|token|library\/metadata/u);
});

test('custom channel media picker searches with offset and returns safe metadata', async () => {
  const searchRequests: unknown[] = [];
  const picker = new CustomChannelMediaPicker({ plexRuntime: plexRuntimeFixture({ searchRequests }) });

  const search = await picker.listMedia('media-search', {
    sourceType: 'search',
    query: 'feature',
    offset: 1,
    limit: 1,
    mediaTypes: ['movie'],
  });
  const metadata = await picker.getMediaMetadata('media-metadata', 'movie-1');

  assert.equal(search.ok, true);
  assert.deepEqual(search.ok ? {
    offset: search.value.offset,
    limit: search.value.limit,
    titles: search.value.items.map((item) => item.title),
    hasMore: search.value.hasMore,
  } : null, { offset: 1, limit: 1, titles: ['Feature Two'], hasMore: true });
  assert.deepEqual(searchRequests, [{ query: 'feature', limit: 3, types: ['movie'] }]);
  assert.equal(metadata.ok, true);
  assert.equal(metadata.ok ? metadata.value.title : null, 'Feature');
  assert.deepEqual(metadata.ok ? metadata.value.genres : [], ['Drama']);
  assert.equal(containsCustomChannelForbiddenRendererField(search), false);
  assert.equal(containsCustomChannelForbiddenRendererField(metadata), false);
});

test('custom channel media picker filters unsupported Plex media types from cards', async () => {
  const picker = new CustomChannelMediaPicker({
    plexRuntime: plexRuntimeFixture({ includeUnsupported: true }),
  });

  const result = await picker.listMedia('media-unsupported', {
    sourceType: 'library',
    sourceId: 'movies',
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value.items.map((item) => item.ratingKey) : [], ['movie-1']);
  assert.equal(containsCustomChannelForbiddenRendererField(result), false);
});

test('custom channel media picker computes search pagination after unsupported filtering', async () => {
  const searchRequests: unknown[] = [];
  const picker = new CustomChannelMediaPicker({
    plexRuntime: plexRuntimeFixture({ searchItems: [
      mediaItem({ ratingKey: 'track-0', title: 'Track Zero', type: 'track' }),
      mediaItem({ ratingKey: 'movie-1', title: 'Feature' }),
      mediaItem({ ratingKey: 'movie-2', title: 'Feature Two' }),
      mediaItem({ ratingKey: 'track-1', title: 'Track', type: 'track' }),
    ], searchRequests }),
  });

  const result = await picker.listMedia('media-search-filtered-page', {
    sourceType: 'search',
    query: 'feature',
    offset: 0,
    limit: 1,
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? {
    titles: result.value.items.map((item) => item.title),
    total: result.value.total,
    hasMore: result.value.hasMore,
  } : null, { titles: ['Feature'], total: 2, hasMore: true });
  assert.deepEqual(searchRequests, [{ query: 'feature', limit: 2, types: ['movie', 'show', 'episode'] }]);
});

test('custom channel media picker rejects unsupported metadata without addable type', async () => {
  const picker = new CustomChannelMediaPicker({
    plexRuntime: plexRuntimeFixture({ metadataType: 'track' }),
  });

  const result = await picker.getMediaMetadata('media-track-metadata', 'movie-1');

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CUSTOM_CHANNEL_STALE_MEDIA');
  assert.equal(containsCustomChannelForbiddenRendererField(result), false);
});

test('custom channel media picker validates ids and maps Plex failures safely', async () => {
  const picker = new CustomChannelMediaPicker({
    plexRuntime: plexRuntimeFixture({ fail: true }),
  });

  const invalid = await picker.listMedia('media-invalid', {
    sourceType: 'library',
    sourceId: '../movies',
  });
  const failed = await picker.listMedia('media-failed', {
    sourceType: 'search',
    query: 'feature',
  });

  assert.equal(invalid.ok, false);
  assert.equal(invalid.ok ? null : invalid.error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(failed.ok, false);
  assert.equal(failed.ok ? null : failed.error.code, 'CUSTOM_CHANNEL_PLEX_REQUIRED');
  assert.equal(containsCustomChannelForbiddenRendererField(failed), false);
});

test('custom channel artwork proxy uses opaque refs and enforces read bounds', async () => {
  let now = 1_000;
  let authorized = true;
  const proxy = new CustomChannelArtworkProxy({
    now: () => now,
    ttlMs: 100,
    maxBytes: 4,
    timeoutMs: 50,
    isAuthorized: () => authorized,
    fetcher: async () => ({
      contentType: 'image/png',
      bytes: new Uint8Array([1, 2, 3]),
    }),
  });
  const ref = proxy.register({
    ratingKey: 'movie-1',
    sourceKey: '/library/metadata/1/thumb/1',
    kind: 'poster',
    altText: 'Feature',
  });

  assert.equal(isSafeArtworkRefId(ref.id), true);
  assert.doesNotMatch(JSON.stringify(ref), /library\/metadata|thumb|token|https?:/u);
  const read = await proxy.read(ref.id);
  assert.equal(read.ok, true);
  assert.equal(read.ok ? read.value.contentType : null, 'image/png');
  authorized = false;
  assert.deepEqual(await proxy.read(ref.id), { ok: false, reason: 'unauthorized' });
  authorized = true;
  now = 1_101;
  assert.deepEqual(await proxy.read(ref.id), { ok: false, reason: 'expired' });
});

test('custom channel artwork proxy rejects invalid content too-large responses and unknown ids', async () => {
  const invalid = new CustomChannelArtworkProxy({
    now: () => 1,
    fetcher: async () => ({ contentType: 'text/html', bytes: new Uint8Array([1]) }),
  });
  const tooLarge = new CustomChannelArtworkProxy({
    now: () => 1,
    maxBytes: 1,
    fetcher: async () => ({ contentType: 'image/jpeg', bytes: new Uint8Array([1, 2]) }),
  });
  const invalidRef = invalid.register({ ratingKey: 'movie-1', sourceKey: 'private-key', kind: 'poster', altText: 'Feature' });
  const largeRef = tooLarge.register({ ratingKey: 'movie-1', sourceKey: 'private-key', kind: 'poster', altText: 'Feature' });

  assert.deepEqual(await invalid.read('artwork-missingabcdefghijkl'), { ok: false, reason: 'not-found' });
  assert.deepEqual(await invalid.read(invalidRef.id), { ok: false, reason: 'invalid-content' });
  assert.deepEqual(await tooLarge.read(largeRef.id), { ok: false, reason: 'too-large' });
});

test('custom channel artwork proxy times out non-cooperative fetchers', async () => {
  const proxy = new CustomChannelArtworkProxy({
    now: () => 1,
    timeoutMs: 1,
    fetcher: async () => new Promise(() => undefined),
  });
  const ref = proxy.register({ ratingKey: 'movie-1', sourceKey: 'private-key', kind: 'poster', altText: 'Feature' });

  assert.deepEqual(await proxy.read(ref.id), { ok: false, reason: 'timeout' });
});

function plexRuntimeFixture(options: {
  fail?: boolean;
  includeUnsupported?: boolean;
  metadataType?: PlexMediaItemSummary['type'];
  searchItems?: PlexMediaItemSummary[];
  searchRequests?: unknown[];
} = {}) {
  return {
    listLibraryItems: async (requestId: string): Promise<PlexIpcResult<PlexListLibraryItemsValue>> => {
      if (options.fail) return failure(requestId, 'listLibraryItems');
      return {
        ok: true,
        requestId,
        value: {
          sectionId: 'movies',
          offset: 0,
          limit: 24,
	          items: options.includeUnsupported ? [mediaItem(), mediaItem({ ratingKey: 'track-1', type: 'track' })] : [mediaItem()],
          snapshot: snapshot(),
        },
      };
    },
    searchLibrary: async (
      requestId: string,
      payload: { query: string; limit?: number; types?: readonly string[] },
    ): Promise<PlexIpcResult<PlexSearchLibraryValue>> => {
      if (options.fail) return failure(requestId, 'searchLibrary');
      options.searchRequests?.push({
        query: payload.query,
        limit: payload.limit,
        ...(payload.types !== undefined ? { types: [...payload.types] } : {}),
      });
      return {
        ok: true,
        requestId,
	        value: {
	          query: 'feature',
	          sectionId: null,
	          items: options.searchItems ?? [
	            mediaItem(),
	            mediaItem({ ratingKey: 'movie-2', title: 'Feature Two' }),
	            mediaItem({ ratingKey: 'movie-3', title: 'Feature Three' }),
	          ],
	          snapshot: snapshot(),
	        },
      };
    },
    getMetadata: async (requestId: string): Promise<PlexIpcResult<PlexGetMetadataValue>> => ({
      ok: true,
      requestId,
      value: { item: mediaItem(options.metadataType ? { type: options.metadataType } : {}), snapshot: snapshot() },
    }),
  };
}

function mediaItem(overrides: Partial<PlexMediaItemSummary> = {}): PlexMediaItemSummary {
  return {
    ratingKey: 'movie-1',
    type: 'movie',
    title: 'Feature',
    sortTitle: 'Feature',
    summary: 'Safe summary',
    year: 2024,
    durationMs: 90_000,
    addedAtMs: 1,
    updatedAtMs: 1,
    genres: ['Drama'],
    ...overrides,
  };
}

function failure(requestId: string, operation: 'listLibraryItems' | 'searchLibrary'): PlexIpcResult<never> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'PLEX_AUTH_REQUIRED',
      message: 'Plex auth required.',
      retryable: false,
      recoverable: true,
      operation,
    },
  };
}

function snapshot() {
  return {
    auth: { state: 'signed-in' as const, pin: null, profile: null, homeUsers: [], credentialStatus: 'present' as const },
    servers: { status: 'ready' as const, selected: null, items: [], lastSelection: null },
    library: { status: 'ready' as const, sections: [], selectedSectionId: null, items: [], search: null, metadata: null },
    lastError: null,
    updatedAtMs: 1,
  };
}
