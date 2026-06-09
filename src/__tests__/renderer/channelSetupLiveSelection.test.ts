import test from 'node:test';
import assert from 'node:assert/strict';

import { containsPlexForbiddenRendererField, type PlexRuntimeSnapshot } from '../../contracts/plex.js';
import { readChannelSetupActionId } from '../../renderer/domBindings.js';
import { resolveChannelSetupLiveSelection } from '../../renderer/channelSetup/liveSelection.js';
import type { PlexRuntimeRendererState } from '../../renderer/plexRuntimeState.js';

test('channel setup live selection resolves a selected movie or show library only', () => {
  const movieSelection = resolveChannelSetupLiveSelection(createRendererState({
    selectedSectionId: 'movies',
    snapshot: createSnapshot({
      selectedSectionId: 'movies',
      items: [
        mediaItem('movie-1', 'Movie One', 'movie'),
        mediaItem('movie-2', 'Movie Two', 'movie'),
      ],
    }),
  }));

  assert.deepEqual(movieSelection, {
    id: 'movies',
    sourceName: 'Movies',
    sourceType: 'movie',
    contentCount: 2,
    loadedItemCount: 2,
  });

  const showSelection = resolveChannelSetupLiveSelection(createRendererState({
    selectedSectionId: 'shows',
    snapshot: createSnapshot({
      selectedSectionId: 'shows',
      items: [mediaItem('episode-1', 'Pilot', 'episode')],
    }),
  }));

  assert.deepEqual(showSelection, {
    id: 'shows',
    sourceName: 'Shows',
    sourceType: 'show',
    contentCount: 1,
    loadedItemCount: 1,
  });

  assert.equal(containsPlexForbiddenRendererField(movieSelection), false);
  assert.equal(containsPlexForbiddenRendererField(showSelection), false);
});

test('channel setup live selection ignores unsupported library types and missing sections', () => {
  assert.equal(
    resolveChannelSetupLiveSelection(createRendererState({
      selectedSectionId: 'photos',
      snapshot: createSnapshot({ selectedSectionId: 'photos' }),
    })),
    null,
  );

  assert.equal(
    resolveChannelSetupLiveSelection(createRendererState({
      selectedSectionId: 'missing-section',
      snapshot: createSnapshot({ selectedSectionId: 'missing-section' }),
    })),
    null,
  );

  assert.equal(
    resolveChannelSetupLiveSelection(createRendererState({
      selectedSectionId: null,
      snapshot: createSnapshot({ selectedSectionId: null }),
    })),
    null,
  );
});

test('channel setup live selection does not reuse stale item or search results', () => {
  const staleItems = resolveChannelSetupLiveSelection(createRendererState({
    selectedSectionId: 'movies',
    snapshot: createSnapshot({
      selectedSectionId: 'shows',
      items: [mediaItem('episode-1', 'Pilot', 'episode')],
    }),
  }));

  assert.deepEqual(staleItems, {
    id: 'movies',
    sourceName: 'Movies',
    sourceType: 'movie',
    contentCount: 2,
    loadedItemCount: 0,
  });

  const searchResults = resolveChannelSetupLiveSelection(createRendererState({
    selectedSectionId: 'movies',
    snapshot: createSnapshot({
      selectedSectionId: 'movies',
      items: [mediaItem('search-hit', 'Search Hit', 'movie')],
      search: {
        query: 'private title must not leak from raw payload',
        items: [mediaItem('search-hit', 'Search Hit', 'movie')],
      },
    }),
  }));

  assert.deepEqual(searchResults, {
    id: 'movies',
    sourceName: 'Movies',
    sourceType: 'movie',
    contentCount: 2,
    loadedItemCount: 0,
  });

  const serialized = JSON.stringify({ staleItems, searchResults });
  assert.doesNotMatch(serialized, /serverUri|token|https?:|rawPayload|headers|credential|C:\\|\/Users\/|\/home\//u);
});

test('legacy fake channel setup action ids are not accepted by renderer DOM action reader', () => {
  for (const actionId of [
    'advanceSetupStep',
    'toggleFeaturedChannel',
    'addDraftChannel',
    'resetDraftLineup',
  ]) {
    assert.equal(readChannelSetupActionId(actionId), null);
  }

  assert.equal(readChannelSetupActionId('selectRecentlyAddedSource'), 'selectRecentlyAddedSource');
  assert.equal(readChannelSetupActionId('selectAppendBuildMode'), 'selectAppendBuildMode');
  assert.equal(readChannelSetupActionId('selectReplaceBuildMode'), 'selectReplaceBuildMode');
});

function createRendererState(input: {
  selectedSectionId: string | null;
  snapshot: PlexRuntimeSnapshot | null;
}): PlexRuntimeRendererState {
  return {
    snapshot: input.snapshot,
    selectedSectionId: input.selectedSectionId,
    selectedServerId: input.snapshot?.servers.selected?.serverId ?? null,
    selectedItemRatingKey: null,
    searchQuery: '',
    homeUserPin: '',
    statusText: 'Ready',
    errorText: null,
    pending: {
      getSnapshot: false,
      requestPin: false,
      pollPin: false,
      cancelPin: false,
      getHomeUsers: false,
      switchHomeUser: false,
      restoreSelectedServer: false,
      refreshServers: false,
      selectServer: false,
      listLibrarySections: false,
      listLibraryItems: false,
      searchLibrary: false,
      getMetadata: false,
      pollPinLoop: false,
      cleanup: false,
    },
    lastMetadata: null,
  };
}

function createSnapshot(input: {
  selectedSectionId: string | null;
  items?: PlexRuntimeSnapshot['library']['items'];
  search?: PlexRuntimeSnapshot['library']['search'];
}): PlexRuntimeSnapshot {
  return {
    auth: {
      state: 'signed-in',
      pin: null,
      profile: { accountId: 'account-safe', displayName: 'Profile' },
      homeUsers: [],
      credentialStatus: 'present',
    },
    servers: {
      status: 'ready',
      selected: {
        serverId: 'server-safe',
        name: 'Selected server',
        owned: true,
        connectionCount: 1,
        hasLocalConnection: true,
        hasRemoteConnection: false,
        hasRelayConnection: false,
        selected: true,
      },
      items: [],
      lastSelection: null,
    },
    library: {
      status: 'ready',
      sections: [
        { id: 'movies', title: 'Movies', type: 'movie', contentCount: 2, lastScannedAtMs: 1 },
        { id: 'shows', title: 'Shows', type: 'show', contentCount: 1, lastScannedAtMs: 1 },
        { id: 'photos', title: 'Photos', type: 'photo', contentCount: 3, lastScannedAtMs: 1 },
      ],
      selectedSectionId: input.selectedSectionId,
      items: input.items ?? [],
      search: input.search ?? null,
      metadata: null,
    },
    lastError: null,
    updatedAtMs: 1,
  };
}

function mediaItem(
  ratingKey: string,
  title: string,
  type: 'movie' | 'episode',
): PlexRuntimeSnapshot['library']['items'][number] {
  return {
    ratingKey,
    type,
    title,
    sortTitle: title,
    summary: '',
    year: 2020,
    durationMs: 1_800_000,
    addedAtMs: 1,
    updatedAtMs: 1,
    ...(type === 'episode'
      ? { grandparentTitle: 'Shows', seasonNumber: 1, episodeNumber: 1 }
      : {}),
  };
}
