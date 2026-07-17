import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlexRuntimeRendererState } from '../../renderer/plexRuntimeState.js';
import { createPlexRuntimeRendererState } from '../../renderer/plexRuntimeState.js';
import { createSetupRuntimeCoordinator } from '../../renderer/setup/setupRuntimeCoordinator.js';
import { cleanupSetupRouteLifecycle, clearSetupSourceLifecycle, createSetupComposition } from '../../renderer/setup/setupComposition.js';
import type { PlexRuntimeController } from '../../renderer/plexRuntimeActions.js';
import {
  SETUP_LIBRARY_LIMIT,
  normalizeSetupLibrarySelection,
  resolveSetupPreviewCursor,
  selectAllSetupLibraries,
  toggleSetupLibrarySelection,
} from '../../renderer/setup/setupLibrarySelection.js';
import type { PlexLibrarySectionSummary } from '../../contracts/plex.js';
import { deferred } from '../helpers/deferred.js';

test('setup library selection is ordered, deduplicated, eligible-only, and capped at 24', () => {
  const sections = Array.from({ length: 26 }, (_, index) => section(`library-${String(index + 1)}`, index === 25 ? 'artist' : index % 2 ? 'show' : 'movie'));
  const all = selectAllSetupLibraries(sections);
  assert.equal(all.selectedSectionIds.length, SETUP_LIBRARY_LIMIT);
  assert.equal(all.limitReached, true);
  assert.deepEqual(normalizeSetupLibrarySelection(['library-4', 'library-2', 'library-4'], sections), ['library-2', 'library-4']);
  const blocked = toggleSetupLibrarySelection(all.selectedSectionIds, 'library-25', sections);
  assert.deepEqual(blocked.selectedSectionIds, all.selectedSectionIds);
  assert.equal(blocked.limitReached, true);
  const removed = toggleSetupLibrarySelection(all.selectedSectionIds, 'library-2', sections);
  assert.equal(removed.selectedSectionIds.includes('library-2'), false);
  assert.equal(resolveSetupPreviewCursor([], 'library-2'), null);
  assert.equal(resolveSetupPreviewCursor(['library-2'], 'library-2'), 'library-2');
  assert.equal(resolveSetupPreviewCursor(['library-3'], 'library-2'), 'library-3');
});

test('source-change and route cleanup lifecycle owners invalidate only through setup composition', () => {
  const calls: string[] = [];
  let runtimeBypassCalls = 0;
  let controllerBypassCalls = 0;
  const composition = {
    invalidate: (keepOwner = false) => { calls.push(`composition:${String(keepOwner)}`); },
    runtime: { invalidate: () => { runtimeBypassCalls++; } },
    controller: { invalidateAsync: () => { controllerBypassCalls++; } },
  };
  const channelController = { clearActionState: () => { calls.push('channel'); } };
  const customController = {
    invalidateOperations: () => { calls.push('custom-operations'); },
    clearMediaForSourceChange: () => { calls.push('custom-media'); },
  };

  clearSetupSourceLifecycle({ composition, channelController, customController }, true);
  cleanupSetupRouteLifecycle({ composition, customController });

  assert.deepEqual(calls, [
    'composition:true', 'channel', 'custom-operations', 'custom-media',
    'composition:false', 'custom-operations',
  ]);
  assert.equal(runtimeBypassCalls, 0);
  assert.equal(controllerBypassCalls, 0);
});

test('setup coordinator automatically loads once per current server and distinguishes empty and failure', async () => {
  let state = plexState('server-1', [], null);
  let calls = 0;
  let responseSections: readonly PlexLibrarySectionSummary[] = [section('movies', 'movie')];
  const coordinator = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => {
      calls++;
      state = plexState('server-1', responseSections, null);
    },
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    onStateChanged: () => undefined,
  });
  await coordinator.enterLibrary('server-1', state);
  await coordinator.enterLibrary('server-1', state);
  assert.equal(calls, 1);
  assert.equal(coordinator.getState().library, 'ready');

  coordinator.invalidate();
  responseSections = [section('music', 'artist')];
  state = plexState('server-1', responseSections, null);
  await coordinator.enterLibrary('server-1', state);
  assert.equal(coordinator.getState().library, 'empty');

  coordinator.invalidate();
  state = plexState('server-1', [], null);
  const failed = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => { state = plexState('server-1', [], 'Libraries unavailable.'); },
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    onStateChanged: () => undefined,
  });
  await failed.enterLibrary('server-1', state);
  assert.equal(failed.getState().library, 'error');
});

test('setup coordinator replays the latest library entry after an invalidated real-controller-like pending load', async () => {
  let state = plexState('server-1', [], null);
  const first = deferred<void>();
  const second = deferred<void>();
  let pending = false;
  let calls = 0;
  let duplicateNoops = 0;
  const coordinator = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => {
      if (pending) { duplicateNoops++; return; }
      pending = true;
      calls++;
      const call = calls;
      await (call === 1 ? first.promise : second.promise);
      state = plexState('server-1', [section(call === 1 ? 'stale' : 'latest', 'movie')], null);
      pending = false;
    },
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    onStateChanged: () => undefined,
  });

  const stale = coordinator.enterLibrary('server-1', state);
  await Promise.resolve();
  coordinator.invalidate();
  const latest = coordinator.enterLibrary('server-1', state);
  first.resolve();
  await stale;
  for (let turn = 0; turn < 5 && calls < 2; turn++) await Promise.resolve();
  assert.equal(calls, 2);
  second.resolve();
  await latest;
  assert.equal(duplicateNoops, 0);
  assert.equal(coordinator.getState().library, 'ready');
  assert.equal(state.snapshot?.library.sections[0]?.id, 'latest');
});

test('setup composition entry generation prevents an invalidated continuation from replacing re-entry focus', async () => {
  const first = deferred<void>();
  const second = deferred<void>();
  let calls = 0;
  let state = plexState('server-1', [], null);
  const plexController = {
    getState: () => state,
    listLibrarySections: async () => {
      calls++;
      const call = calls;
      await (call === 1 ? first.promise : second.promise);
      state = plexState('server-1', [section(call === 1 ? 'stale' : 'latest', 'movie')], null);
    },
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    setSelectedSection: () => undefined,
  } as unknown as PlexRuntimeController;
  const composition = createSetupComposition({
    plexController,
    channelController: {} as Parameters<typeof createSetupComposition>[0]['channelController'],
    channelSetupBridge: { getRecord: async () => ({ ok: true, requestId: 'record', value: { status: 'missing' } }) } as unknown as Parameters<typeof createSetupComposition>[0]['channelSetupBridge'],
    customController: {} as Parameters<typeof createSetupComposition>[0]['customController'],
    render: () => undefined,
    returnToServer: () => undefined,
    closeSetup: () => undefined,
    tuneChannel: async () => false,
    clearDependentActionState: () => undefined,
    setSetupStage: () => undefined,
    activateSetupRoute: () => undefined,
    loadProfiles: () => undefined,
    enterServerSelection: () => undefined,
  });

  const stale = composition.enter('settings', 'settings-setup');
  await Promise.resolve();
  composition.invalidate();
  const latest = composition.enter('settings', 'settings-setup');
  first.resolve();
  await stale;
  assert.equal(composition.controller.getState().focusIntent, 'setup-back');
  for (let turn = 0; turn < 5 && calls < 2; turn++) await Promise.resolve();
  second.resolve();
  await latest;
  assert.equal(composition.controller.getState().focusIntent, 'plex-dyn-section-latest');
});

test('server-origin Back invalidates a pending library entry before showing server onboarding', async () => {
  const pendingLibraries = deferred<void>();
  let state = plexState('server-1', [], null);
  const events: string[] = [];
  const plexController = {
    getState: () => state,
    listLibrarySections: async () => {
      await pendingLibraries.promise;
      state = plexState('server-1', [section('stale-library', 'movie')], null);
    },
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    setSelectedSection: () => undefined,
  } as unknown as PlexRuntimeController;
  const composition = createSetupComposition({
    plexController,
    channelController: {} as Parameters<typeof createSetupComposition>[0]['channelController'],
    channelSetupBridge: { getRecord: async () => ({ ok: true, requestId: 'record', value: { status: 'missing' } }) } as unknown as Parameters<typeof createSetupComposition>[0]['channelSetupBridge'],
    customController: {} as Parameters<typeof createSetupComposition>[0]['customController'],
    render: () => undefined,
    returnToServer: () => events.push('stage:server'),
    closeSetup: () => events.push('close'),
    tuneChannel: async () => false,
    clearDependentActionState: () => undefined,
    setSetupStage: () => events.push('stage:library'),
    activateSetupRoute: () => events.push('route:channelSetup'),
    loadProfiles: () => undefined,
    enterServerSelection: () => undefined,
  });

  const entry = composition.enter('player', 'player-setup-reminder', true);
  await Promise.resolve();
  assert.equal(composition.runtime.getState().library, 'loading');
  await composition.apply('setupBack');
  assert.equal(composition.runtime.getState().library, 'idle');
  assert.equal(composition.controller.getState().focusIntent, 'setup-select-all');
  assert.equal(events.at(-1), 'stage:server');

  pendingLibraries.resolve();
  await entry;
  assert.equal(composition.controller.getState().owner, 'library');
  assert.equal(composition.controller.getState().focusIntent, 'setup-select-all');
  assert.equal(events.includes('close'), false);
});

test('setup preview coalesces queued cursor changes so the latest cursor performs a real load', async () => {
  let state = plexState('server-1', [section('movies', 'movie')], null);
  const first = deferred<void>();
  const calls: string[] = [];
  const coordinator = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => undefined,
    listLibraryItems: async (id) => {
      calls.push(id);
      if (id === 'movies') await first.promise;
      state = plexState('server-1', [section(id, 'movie')], null, id, id === 'documentaries' ? ['safe-item'] : []);
    },
    getMetadata: async (key) => { calls.push(`metadata:${key}`); },
    onStateChanged: () => undefined,
  });
  const stale = coordinator.loadPreview('movies');
  await Promise.resolve();
  const skipped = coordinator.loadPreview('shows');
  const latest = coordinator.loadPreview('documentaries');
  first.resolve();
  await Promise.all([stale, skipped, latest]);
  assert.equal(coordinator.getState().previewSectionId, 'documentaries');
  assert.equal(coordinator.getState().preview, 'ready');
  assert.deepEqual(calls, ['movies', 'documentaries']);
});

test('setup preview metadata failure is reachable and retry repeats metadata only', async () => {
  let state = plexState('server-1', [section('movies', 'movie')], null, 'movies', ['safe-item']);
  const calls: string[] = [];
  let metadataFails = true;
  const coordinator = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => undefined,
    listLibraryItems: async (id) => { calls.push(`items:${id}`); },
    getMetadata: async (key) => {
      calls.push(`metadata:${key}`);
      state = plexState('server-1', [section('movies', 'movie')], metadataFails ? 'Metadata unavailable.' : null, 'movies', ['safe-item']);
    },
    onStateChanged: () => undefined,
  });

  await coordinator.loadPreview('movies');
  await coordinator.loadPreviewMetadata('safe-item');
  assert.equal(coordinator.getState().preview, 'metadata-error');
  metadataFails = false;
  await coordinator.retryPreview();
  assert.equal(coordinator.getState().preview, 'ready');
  assert.deepEqual(calls, ['items:movies', 'metadata:safe-item', 'metadata:safe-item']);
});

test('setup coordinator maps rejected library, item, and metadata work to terminal states', async () => {
  const state = plexState('server-1', [section('movies', 'movie')], null, 'movies', ['safe-item']);
  const library = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => { throw new Error('library rejected'); },
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    onStateChanged: () => undefined,
  });
  await library.enterLibrary('server-1', state);
  assert.equal(library.getState().library, 'error');

  const items = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => undefined,
    listLibraryItems: async () => { throw new Error('items rejected'); },
    getMetadata: async () => undefined,
    onStateChanged: () => undefined,
  });
  await items.enterLibrary('server-1', state);
  await items.loadPreview('movies');
  assert.equal(items.getState().preview, 'items-error');

  const metadata = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => undefined,
    listLibraryItems: async () => undefined,
    getMetadata: async () => { throw new Error('metadata rejected'); },
    onStateChanged: () => undefined,
  });
  await metadata.enterLibrary('server-1', state);
  await metadata.loadPreview('movies');
  await metadata.loadPreviewMetadata('safe-item');
  assert.equal(metadata.getState().preview, 'metadata-error');
  metadata.collapsePreview();
  assert.equal(metadata.getState().preview, 'collapsed');
  assert.equal(metadata.getState().previewRatingKey, null);
});

test('setup coordinator ignores a rejected operation after invalidation', async () => {
  const state = plexState('server-1', [], null);
  let rejectLoad!: (error: Error) => void;
  const pending = new Promise<void>((_resolve, reject) => { rejectLoad = reject; });
  const coordinator = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: () => pending,
    listLibraryItems: async () => undefined,
    getMetadata: async () => undefined,
    onStateChanged: () => undefined,
  });
  const load = coordinator.enterLibrary('server-1', state);
  await Promise.resolve();
  coordinator.invalidate();
  rejectLoad(new Error('stale rejection'));
  await load;
  assert.equal(coordinator.getState().library, 'idle');
});

test('setup preview serializes metadata requests and performs the latest rating-key load', async () => {
  let state = plexState('server-1', [section('movies', 'movie')], null, 'movies', ['rating-a', 'rating-b']);
  const first = deferred<void>();
  const second = deferred<void>();
  const calls: string[] = [];
  let pending = false;
  let duplicateNoops = 0;
  const coordinator = createSetupRuntimeCoordinator({
    getPlexState: () => state,
    listLibrarySections: async () => undefined,
    listLibraryItems: async () => undefined,
    getMetadata: async (key) => {
      if (pending) { duplicateNoops++; return; }
      pending = true;
      calls.push(key);
      await (key === 'rating-a' ? first.promise : second.promise);
      state = plexState('server-1', [section('movies', 'movie')], key === 'rating-a' ? 'Stale metadata failure.' : null, 'movies', ['rating-a', 'rating-b']);
      pending = false;
    },
    onStateChanged: () => undefined,
  });

  const stale = coordinator.loadPreviewMetadata('rating-a');
  await Promise.resolve();
  const latest = coordinator.loadPreviewMetadata('rating-b');
  assert.deepEqual(calls, ['rating-a']);
  first.resolve();
  await stale;
  assert.equal(coordinator.getState().preview, 'loading');
  assert.equal(coordinator.getState().previewRatingKey, 'rating-b');
  for (let turn = 0; turn < 5 && calls.length < 2; turn++) await Promise.resolve();
  assert.deepEqual(calls, ['rating-a', 'rating-b']);
  second.resolve();
  await latest;
  assert.equal(duplicateNoops, 0);
  assert.equal(coordinator.getState().previewRatingKey, 'rating-b');
  assert.equal(coordinator.getState().preview, 'ready');
});

function section(id: string, type: PlexLibrarySectionSummary['type']): PlexLibrarySectionSummary {
  return { id, title: id, type, contentCount: 1, lastScannedAtMs: 0 };
}

function plexState(serverId: string, sections: readonly PlexLibrarySectionSummary[], errorText: string | null, selectedSectionId: string | null = null, ratingKeys: readonly string[] = []): PlexRuntimeRendererState {
  return {
    ...createPlexRuntimeRendererState(), selectedServerId: serverId, selectedSectionId, errorText,
    snapshot: {
      auth: { state: 'signed-in', pin: null, profile: { accountId: 'account' }, homeUsers: [], credentialStatus: 'present' },
      servers: { status: 'ready', selected: { serverId, name: 'Server', owned: true, connectionCount: 1, hasLocalConnection: true, hasRemoteConnection: false, hasRelayConnection: false, selected: true }, items: [], lastSelection: null },
      library: { status: 'ready', sections, selectedSectionId, items: ratingKeys.map((ratingKey) => ({ ratingKey, type: 'movie', title: ratingKey, sortTitle: ratingKey, summary: '', year: 2026, durationMs: 1, addedAtMs: 0, updatedAtMs: 0 })), search: null, metadata: null },
      lastError: null,
      updatedAtMs: 0,
    },
  };
}
