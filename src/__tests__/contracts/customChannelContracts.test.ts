import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CUSTOM_CHANNEL_ERROR_CODES,
  CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS,
  CUSTOM_CHANNEL_OPERATIONS,
  CUSTOM_CHANNEL_VALIDATION_CODES,
  containsCustomChannelForbiddenRendererField,
  customChannelFailure,
  customChannelSuccess,
  findCustomChannelForbiddenRendererField,
  type CustomChannelDraftInput,
  type CustomChannelListMediaRequest,
  type CustomChannelMutationResult,
  type CustomChannelRequest,
  type CustomChannelSnapshot,
  type CustomChannelVisibilityRequest,
} from '../../contracts/customChannels.js';

test('custom channel contract freezes operation and error vocabulary', () => {
  assert.deepEqual([...CUSTOM_CHANNEL_OPERATIONS], [
    'getSnapshot',
    'listMedia',
    'getMediaMetadata',
    'validateDraft',
    'saveDraft',
    'deleteChannel',
    'duplicateChannelDraft',
    'reorderChannels',
    'setChannelVisibility',
  ]);
  assert.deepEqual([...CUSTOM_CHANNEL_ERROR_CODES], [
    'CUSTOM_CHANNEL_UNAUTHORIZED',
    'CUSTOM_CHANNEL_VALIDATION_FAILED',
    'CUSTOM_CHANNEL_PLEX_REQUIRED',
    'CUSTOM_CHANNEL_STORAGE_UNAVAILABLE',
    'CUSTOM_CHANNEL_STORAGE_CORRUPT',
    'CUSTOM_CHANNEL_NOT_FOUND',
    'CUSTOM_CHANNEL_STALE_MEDIA',
    'CUSTOM_CHANNEL_ARTWORK_UNAVAILABLE',
    'CUSTOM_CHANNEL_CONFLICT',
    'CUSTOM_CHANNEL_UNKNOWN',
  ]);
  assert.deepEqual([...CUSTOM_CHANNEL_VALIDATION_CODES], [
    'missing-name',
    'duplicate-number',
    'invalid-number',
    'empty-content',
    'duplicate-content',
    'invalid-draft-id',
    'invalid-content',
    'invalid-playback-mode',
    'invalid-block-size',
    'invalid-hidden',
    'invalid-include-watched',
    'invalid-sort-order',
    'invalid-start-time-anchor',
    'max-channels',
    'stale-content',
    'storage-unavailable',
  ]);
});

test('custom channel result envelopes preserve request ids', () => {
  const snapshot: CustomChannelSnapshot = {
    channels: [],
    currentChannelId: null,
    visibleChannelCount: 0,
    hiddenChannelCount: 0,
    maxChannels: 500,
    nextAvailableNumber: 1,
    updatedAtMs: 1,
    storage: { status: 'not-configured', repaired: false },
  };

  assert.deepEqual(customChannelSuccess('request-1', snapshot), {
    ok: true,
    requestId: 'request-1',
    value: snapshot,
  });
  assert.deepEqual(
    customChannelFailure('request-2', {
      code: 'CUSTOM_CHANNEL_VALIDATION_FAILED',
      message: 'Draft is invalid.',
      retryable: false,
      recoverable: true,
      operation: 'validateDraft',
    }),
    {
      ok: false,
      requestId: 'request-2',
      error: {
        code: 'CUSTOM_CHANNEL_VALIDATION_FAILED',
        message: 'Draft is invalid.',
        retryable: false,
        recoverable: true,
        operation: 'validateDraft',
      },
    },
  );
});

test('custom channel draft input is renderer safe and explicit', () => {
  const draft: CustomChannelDraftInput = {
    number: 12,
    name: 'Movies',
    hidden: false,
    playbackMode: 'block',
    blockSize: 3,
    sortOrder: 'title_asc',
    includeWatched: true,
    content: [
      {
        type: 'manualItem',
        ratingKey: 'rating-1',
        title: 'Movie',
        durationMs: 90_000,
        mediaType: 'movie',
        year: 2024,
      },
    ],
  };

  assert.equal(containsCustomChannelForbiddenRendererField(draft), false);
  assert.equal(Object.hasOwn(draft.content[0] ?? {}, 'thumb'), false);
  assert.equal(Object.hasOwn(draft.content[0] ?? {}, 'url'), false);
});

test('custom channel requests cover every operation payload without broad RPC strings', () => {
  const listMedia: CustomChannelListMediaRequest = {
    requestId: 'request-list',
    payload: {
      sourceType: 'search',
      query: 'movie',
      offset: 0,
      limit: 24,
      mediaTypes: ['movie', 'episode'],
      draftContent: [],
    },
  };
  const visibility: CustomChannelVisibilityRequest = {
    requestId: 'request-visibility',
    payload: {
      channelId: 'channel-1',
      hidden: true,
    },
  };
  const requests: readonly CustomChannelRequest[] = [
    { requestId: 'request-empty', payload: {} },
    listMedia,
    { requestId: 'request-metadata', payload: { ratingKey: 'rating-1' } },
    { requestId: 'request-draft', payload: draft('request-draft') },
    { requestId: 'request-delete', payload: { channelId: 'channel-1', confirm: true } },
    { requestId: 'request-duplicate', payload: { channelId: 'channel-1' } },
    { requestId: 'request-reorder', payload: { channelIds: ['channel-1', 'channel-2'] } },
    visibility,
  ];

  assert.equal(requests.length, CUSTOM_CHANNEL_OPERATIONS.length - 1);
  assert.equal(containsCustomChannelForbiddenRendererField(requests), false);
});

test('custom channel mutation result returns a snapshot and safe channel ids only', () => {
  const result: CustomChannelMutationResult = {
    snapshot: {
      channels: [{
        id: 'channel-1',
        number: 1,
        name: 'Movies',
        description: null,
        itemCount: 1,
        estimatedDurationMs: 90_000,
        sourceSummary: '1 item',
        playbackMode: 'sequential',
        hidden: false,
        updatedAtMs: 1,
        isCurrent: true,
      }],
      currentChannelId: 'channel-1',
      visibleChannelCount: 1,
      hiddenChannelCount: 0,
      maxChannels: 500,
      nextAvailableNumber: 2,
      updatedAtMs: 1,
      storage: { status: 'ready', repaired: false },
    },
    changedChannelId: 'channel-1',
    currentChannelId: 'channel-1',
  };

  assert.equal(containsCustomChannelForbiddenRendererField(result), false);
});

test('custom channel forbidden field audit rejects secrets paths urls and artwork keys recursively', () => {
  assert.ok(CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS.includes('token'));
  assert.ok(CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS.includes('url'));
  assert.ok(CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS.includes('thumb'));
  assert.ok(CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS.includes('imageKey'));

  const finding = findCustomChannelForbiddenRendererField({
    channel: {
      content: [
        {
          title: 'Movie',
          artwork: { thumb: '/library/metadata/1/thumb' },
        },
      ],
    },
  });

  assert.deepEqual(finding, { path: '$.channel.content[0].artwork', key: 'thumb' });
  assert.equal(
    containsCustomChannelForbiddenRendererField({
      error: { message: 'safe', context: { count: 1 } },
    }),
    false,
  );
});

test('custom channel forbidden field audit rejects field variants and unsafe strings', () => {
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ Token: 'redacted' }),
    { path: '$', key: 'Token' },
  );
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ artwork: { 'auth-header': 'blocked' } }),
    { path: '$.artwork', key: 'auth-header' },
  );
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ nested: { TOKENIZED_URL: 'blocked' } }),
    { path: '$.nested', key: 'TOKENIZED_URL' },
  );
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ value: 'https://plex.example/library/metadata/1' }),
    { path: '$.value', key: '<string>' },
  );
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ value: 'Authorization: Bearer redacted' }),
    { path: '$.value', key: '<string>' },
  );
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ value: '/library/metadata/1/thumb/123' }),
    { path: '$.value', key: '<string>' },
  );
  assert.deepEqual(
    findCustomChannelForbiddenRendererField({ value: '../Library/cache/poster.jpg' }),
    { path: '$.value', key: '<string>' },
  );
});

function draft(requestId: string): CustomChannelDraftInput {
  return {
    number: 12,
    name: `Draft ${requestId}`,
    hidden: false,
    playbackMode: 'sequential',
    content: [{
      type: 'manualItem',
      ratingKey: 'rating-1',
      title: 'Movie',
      durationMs: 90_000,
      mediaType: 'movie',
    }],
  };
}
