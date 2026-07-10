import test from 'node:test';
import assert from 'node:assert/strict';

import {
  customChannelSuccess,
  type CustomChannelListMediaRequest,
  type CustomChannelSnapshot,
} from '../../contracts/customChannels.js';
import { createCustomChannelController } from '../../renderer/customChannels/controller.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { deferred } from '../helpers/deferred.js';

test('custom channel controller loads snapshots browses media and adds draft items', async () => {
  let renders = 0;
  const bridge = createBridge();
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => {
      renders++;
    },
  });

  await controller.loadSnapshot();
  await controller.browseSource('library-1');
  await controller.applyAction('addMedia', 'rating-1');

  const state = controller.getState();
  assert.equal(state.snapshot?.visibleChannelCount, 2);
  assert.equal(state.mediaPage?.items.length, 1);
  assert.equal(state.draft.content.length, 1);
  assert.equal(state.draft.content[0]?.type, 'manualItem');
  assert.equal(renders > 0, true);
});

test('custom channel controller saves draft and handles delete confirmation locally', async () => {
  const bridge = createBridge();
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });
  await controller.loadSnapshot();
  await controller.browseSource('library-1');
  await controller.applyAction('addMedia', 'rating-1');
  controller.setDraftName('Saved Channel');
  controller.setDraftNumber('110');
  await controller.applyAction('saveDraft');

  assert.equal(controller.getState().lastSavedChannelId, 'channel-saved');
  assert.equal(controller.getState().draft.content.length, 0);
  controller.setDraftName('Unsaved Change');
  assert.equal(controller.getState().lastSavedChannelId, null);

  await controller.applyAction('requestDeleteChannel', 'channel-1');
  assert.equal(controller.getState().deleteConfirmationChannelId, 'channel-1');
  assert.equal(controller.handleBack(), true);
  assert.equal(controller.getState().deleteConfirmationChannelId, null);

  await controller.applyAction('requestDeleteChannel', 'channel-1');
  await controller.applyAction('confirmDeleteChannel', 'channel-1');
  assert.equal(controller.getState().snapshot?.channels.length, 0);
});

test('custom channel controller surfaces validation and rejects unsupported media additions', async () => {
  const bridge = createBridge();
  bridge.validateDraft = async () => customChannelSuccess('validate-1', {
    valid: false,
    issues: [{ code: 'empty-content', message: 'Add at least one playable item.', field: 'content' }],
  });
  bridge.listMedia = async () => customChannelSuccess('media-1', {
    items: [{
      ratingKey: 'rating-show',
      type: 'show',
      title: 'Show One',
      subtitle: 'Series',
      year: 2026,
      durationMs: null,
      source: { sourceType: 'library', sourceId: 'library-1', title: 'Shows' },
      availability: 'unsupported',
    }],
    offset: 0,
    limit: 24,
    total: 1,
    hasMore: false,
  });
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });

  await controller.loadSnapshot();
  await controller.browseSource('library-1');
  await controller.applyAction('addMedia', 'rating-show');
  assert.equal(controller.getState().draft.content.length, 0);
  assert.equal(controller.getState().lastError, 'Only playable movies and episodes can be added to a custom channel.');

  await controller.applyAction('saveDraft');
  assert.equal(controller.getState().validation?.valid, false);
  assert.equal(controller.getState().validation?.issues[0]?.field, 'content');
});

test('custom channel controller reorders and clears local search state on back', async () => {
  const bridge = createBridge();
  let reordered: readonly string[] = [];
  bridge.reorderChannels = async (input) => {
    reordered = input.channelIds;
    return customChannelSuccess('reorder-1', {
      snapshot: snapshot([...input.channelIds]),
      changedChannelId: null,
      currentChannelId: input.channelIds[0] ?? null,
    });
  };
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });

  await controller.loadSnapshot();
  await controller.applyAction('moveChannelDown', 'channel-1');
  assert.deepEqual(reordered, ['channel-2', 'channel-1']);

  controller.setSearchQuery('movie');
  assert.equal(controller.handleBack(), true);
  assert.equal(controller.getState().query, '');
});

test('custom channel controller ignores stale media requests after query changes', async () => {
  const bridge = createBridge();
  const pending = deferred<Awaited<ReturnType<typeof bridge.listMedia>>>();
  bridge.listMedia = async () => pending.promise;
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });

  controller.setSearchQuery('old');
  const search = controller.searchMedia('library-1');
  controller.setSearchQuery('new');
  pending.resolve(customChannelSuccess('media-stale', {
    items: [{
      ratingKey: 'rating-old',
      type: 'movie',
      title: 'Old Movie',
      subtitle: '2026',
      year: 2026,
      durationMs: 7_200_000,
      source: { sourceType: 'search', sourceId: 'library-1', title: 'Search' },
      availability: 'available',
    }],
    offset: 0,
    limit: 24,
    total: 1,
    hasMore: false,
  }));
  await search;

  assert.equal(controller.getState().query, 'new');
  assert.equal(controller.getState().mediaPending, false);
  assert.equal(controller.getState().mediaPage, null);
});

test('custom channel controller ignores stale media requests after source changes', async () => {
  const bridge = createBridge();
  const pending = deferred<Awaited<ReturnType<typeof bridge.listMedia>>>();
  bridge.listMedia = async () => pending.promise;
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });

  const browse = controller.browseSource('library-1');
  controller.clearMediaForSourceChange();
  pending.resolve(customChannelSuccess('media-stale-source', {
    items: [{
      ratingKey: 'rating-old-source',
      type: 'movie',
      title: 'Old Source Movie',
      subtitle: '2026',
      year: 2026,
      durationMs: 7_200_000,
      source: { sourceType: 'library', sourceId: 'library-1', title: 'Old Movies' },
      availability: 'available',
    }],
    offset: 0,
    limit: 24,
    total: 1,
    hasMore: false,
  }));
  await browse;

  assert.equal(controller.getState().mediaPending, false);
  assert.equal(controller.getState().mediaPage, null);
  assert.equal(controller.getState().draft.content.length, 0);
});

test('custom channel controller maps rejected bridge work to safe local errors', async () => {
  const bridge = createBridge();
  bridge.listMedia = async () => {
    throw new Error('/private/path/token');
  };
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });

  await controller.browseSource('library-1');

  assert.equal(controller.getState().mediaPending, false);
  assert.equal(controller.getState().lastError, 'Media lookup failed. Try again.');
});

test('custom channel controller supports filters metadata back unwind and source invalidation', async () => {
  const bridge = createBridge();
  const mediaRequests: CustomChannelListMediaRequest['payload'][] = [];
  const metadataRequests: string[] = [];
  bridge.listMedia = async (input) => {
    mediaRequests.push(input);
    return customChannelSuccess('media-1', {
      items: [{
        ratingKey: 'rating-episode',
        type: 'episode',
        title: 'Episode One',
        subtitle: 'S1 E1',
        year: 2026,
        durationMs: 3_600_000,
        parentTitle: 'Show One',
        seasonNumber: 1,
        episodeNumber: 1,
        source: { sourceType: 'library', sourceId: 'library-1', title: 'Episodes' },
        availability: 'available',
      }],
      offset: 0,
      limit: 24,
      total: 1,
      hasMore: false,
    });
  };
  bridge.getMediaMetadata = async ({ ratingKey }) => {
    metadataRequests.push(ratingKey);
    return customChannelSuccess('metadata-1', {
      ratingKey,
      type: 'episode',
      title: `Title ${ratingKey}`,
      subtitle: `Parent ${ratingKey}`,
      summary: null,
      year: 2026,
      durationMs: 7_200_000,
      parentTitle: `Parent ${ratingKey}`,
      seasonNumber: 1,
      episodeNumber: 1,
      genres: [],
      availability: 'available',
    });
  };
  const controller = createCustomChannelController({
    bridge,
    onStateChanged: () => undefined,
  });

  await controller.loadSnapshot();
  await controller.applyAction('setFilterEpisodes');
  await controller.browseSource('library-1');
  assert.deepEqual(mediaRequests.at(-1)?.mediaTypes, ['episode']);

  await controller.applyAction('openMetadata', 'rating-episode');
  assert.equal(metadataRequests.at(-1), 'rating-episode');
  assert.deepEqual(controller.getState().metadata, {
    ratingKey: 'rating-episode',
    type: 'episode',
    title: 'Title rating-episode',
    subtitle: 'Parent rating-episode',
    summary: null,
    year: 2026,
    durationMs: 7_200_000,
    parentTitle: 'Parent rating-episode',
    seasonNumber: 1,
    episodeNumber: 1,
    genres: [],
    availability: 'available',
  });
  assert.equal(controller.handleBack(), true);
  assert.equal(controller.getState().metadata, null);

  await controller.applyAction('saveDraft');
  assert.equal(controller.getState().lastSavedChannelId, 'channel-saved');
  await controller.applyAction('duplicateChannel', 'channel-1');
  assert.equal(controller.getState().lastSavedChannelId, null);

  await controller.browseSource('library-1');
  await controller.applyAction('addMedia', 'rating-episode');
  assert.equal(controller.getState().draft.content.length, 1);
  controller.clearMediaForSourceChange();
  assert.equal(controller.getState().mediaPage, null);
  assert.equal(controller.getState().query, '');
  assert.equal(controller.getState().draft.content.length, 0);
});

function createBridge(): LineupDesktopPreloadApi['customChannels'] {
  return {
    getSnapshot: async () => customChannelSuccess('snapshot-1', snapshot(['channel-1', 'channel-2'])),
    listMedia: async () => customChannelSuccess('media-1', {
      items: [{
        ratingKey: 'rating-1',
        type: 'movie',
        title: 'Movie One',
        subtitle: '2026',
        year: 2026,
        durationMs: 7_200_000,
        source: { sourceType: 'library', sourceId: 'library-1', title: 'Movies' },
        availability: 'available',
      }],
      offset: 0,
      limit: 24,
      total: 1,
      hasMore: false,
    }),
    getMediaMetadata: async ({ ratingKey }) => customChannelSuccess('metadata-1', {
      ratingKey,
      type: ratingKey.includes('episode') ? 'episode' : 'movie',
      title: `Title ${ratingKey}`,
      subtitle: ratingKey.includes('episode') ? `Parent ${ratingKey}` : '2026',
      summary: null,
      year: 2026,
      durationMs: 7_200_000,
      ...(ratingKey.includes('episode') ? {
        parentTitle: `Parent ${ratingKey}`,
        seasonNumber: 1,
        episodeNumber: 1,
      } : {}),
      genres: [],
      availability: 'available',
    }),
    validateDraft: async () => customChannelSuccess('validate-1', { valid: true, issues: [] }),
    saveDraft: async () => customChannelSuccess('save-1', {
      snapshot: snapshot(['channel-1', 'channel-saved']),
      changedChannelId: 'channel-saved',
      currentChannelId: 'channel-1',
    }),
    deleteChannel: async () => customChannelSuccess('delete-1', {
      snapshot: snapshot([]),
      changedChannelId: 'channel-1',
      currentChannelId: null,
    }),
    duplicateChannelDraft: async () => customChannelSuccess('duplicate-1', {
      draft: {
        number: 112,
        name: 'Duplicate Channel',
        hidden: false,
        content: [],
        playbackMode: 'sequential',
      },
      validation: { valid: true, issues: [] },
    }),
    reorderChannels: async (input) => customChannelSuccess('reorder-1', {
      snapshot: snapshot([...input.channelIds]),
      changedChannelId: null,
      currentChannelId: input.channelIds[0] ?? null,
    }),
    setChannelVisibility: async () => customChannelSuccess('visibility-1', {
      snapshot: snapshot(['channel-1']),
      changedChannelId: 'channel-1',
      currentChannelId: 'channel-1',
    }),
  };
}

function snapshot(ids: readonly string[]): CustomChannelSnapshot {
  return {
    channels: ids.map((id, index) => ({
      id,
      number: 101 + index,
      name: `Channel ${index + 1}`,
      description: null,
      itemCount: 1,
      estimatedDurationMs: 7_200_000,
      sourceSummary: 'Manual items',
      playbackMode: 'sequential',
      hidden: false,
      updatedAtMs: 1,
      isCurrent: index === 0,
    })),
    currentChannelId: ids[0] ?? null,
    visibleChannelCount: ids.length,
    hiddenChannelCount: 0,
    maxChannels: 500,
    nextAvailableNumber: 101 + ids.length,
    updatedAtMs: 1,
    storage: { status: 'ready', repaired: false },
  };
}
