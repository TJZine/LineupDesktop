import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlexRuntimeSnapshot } from '../../contracts/plex.js';
import type { PlexConnection } from '../../main/plex/discovery/types.js';
import { DesktopPlexLibraryOperationExecutor } from '../../main/plex/desktopPlexLibraryOperationExecutor.js';
import { failureResult } from '../../main/plex/desktopPlexRuntimeSupport.js';
import { LivePlexTransportError, type LivePlexLibraryTransport } from '../../main/plex/livePlexTransport.js';
import { PlexRuntimeOperationOwner } from '../../main/plex/plexRuntimeOperationOwner.js';
import { deferred } from '../helpers/deferred.js';

test('plex runtime operation owner records diagnostics and suppresses stale snapshot mutation', async () => {
  let snapshot = createSnapshot();
  const diagnostics: string[] = [];
  const owner = new PlexRuntimeOperationOwner({
    commitSnapshot: (update) => {
      snapshot = update(snapshot);
    },
    fail: (requestId, error, options) => failureResult(requestId, error, options),
    recordDiagnostic: (operation, status, code) => {
      diagnostics.push([operation, status, code].filter(Boolean).join(':'));
    },
  });
  const firstGate = deferred<void>();
  const first = owner.run('request-old', 'listLibrarySections', async ({ commit }) => {
    await firstGate.promise;
    commit((current) => ({ ...current, updatedAtMs: 99 }));
    return { value: 'old' };
  });
  const second = await owner.run('request-new', 'listLibrarySections', async ({ commit }) => {
    commit((current) => ({ ...current, updatedAtMs: 2 }));
    return { value: 'new' };
  });

  firstGate.resolve();
  const stale = await first;

  assert.equal(second.ok, true);
  assert.equal(stale.ok, false);
  assert.equal(stale.ok ? '' : stale.error.code, 'PLEX_STALE_RESULT');
  assert.equal(stale.ok ? false : stale.stale, true);
  assert.equal(snapshot.updatedAtMs, 2);
  assert.deepEqual(diagnostics, [
    'listLibrarySections:started',
    'listLibrarySections:started',
    'listLibrarySections:succeeded',
    'listLibrarySections:failed:PLEX_STALE_RESULT',
  ]);
});

test('plex runtime operation owner cancels aborted in-flight work without mutating failure snapshot', async () => {
  let failureMutated = false;
  const diagnostics: string[] = [];
  const owner = new PlexRuntimeOperationOwner({
    commitSnapshot: () => undefined,
    fail: (requestId, error, options) => {
      failureMutated = options?.mutateSnapshot !== false;
      return failureResult(requestId, error, options);
    },
    recordDiagnostic: (operation, status, code) => {
      diagnostics.push([operation, status, code].filter(Boolean).join(':'));
    },
  });
  const gate = deferred<void>();
  const pending = owner.run('poll-old', 'pollPin:7', async ({ signal }) => {
    await gate.promise;
    if (signal.aborted) {
      throw new LivePlexTransportError('aborted', 'Plex request was aborted');
    }
    return { value: 'old' };
  });

  owner.abort('pollPin:7');
  gate.resolve();
  const cancelled = await pending;

  assert.equal(cancelled.ok, false);
  assert.equal(cancelled.ok ? '' : cancelled.error.code, 'PLEX_CANCELLED');
  assert.equal(cancelled.ok ? false : cancelled.cancelled, true);
  assert.equal(failureMutated, false);
  assert.deepEqual(diagnostics, ['pollPin:started', 'pollPin:cancelled:PLEX_CANCELLED']);
});

test('plex runtime operation owner invalidates ownership before aborting work', async () => {
  let snapshot = createSnapshot();
  const diagnostics: string[] = [];
  const owner = new PlexRuntimeOperationOwner({
    commitSnapshot: (update) => {
      snapshot = update(snapshot);
    },
    fail: (requestId, error, options) => failureResult(requestId, error, options),
    recordDiagnostic: (operation, status, code) => {
      diagnostics.push([operation, status, code].filter(Boolean).join(':'));
    },
  });
  const gate = deferred<void>();
  const pending = owner.run('poll-old', 'pollPin:8', async ({ commit }) => {
    await gate.promise;
    commit((current) => ({ ...current, updatedAtMs: 123 }));
    return { value: 'old' };
  });

  owner.abort('pollPin:8');
  gate.resolve();
  const result = await pending;

  assert.equal(result.ok, false);
  assert.equal(result.ok ? '' : result.error.code, 'PLEX_STALE_RESULT');
  assert.equal(result.ok ? false : result.stale, true);
  assert.equal(snapshot.updatedAtMs, 1);
  assert.deepEqual(diagnostics, [
    'pollPin:started',
    'pollPin:failed:PLEX_STALE_RESULT',
  ]);
});

test('plex runtime operation owner invalidates ownership before replacement abort listeners run', async () => {
  let snapshot = createSnapshot();
  const staleErrors: string[] = [];
  const owner = new PlexRuntimeOperationOwner({
    commitSnapshot: (update) => {
      snapshot = update(snapshot);
    },
    fail: (requestId, error, options) => failureResult(requestId, error, options),
    recordDiagnostic: () => undefined,
  });
  const firstGate = deferred<void>();
  const first = owner.run('request-old', 'listLibrarySections', async ({ signal, commit }) => {
    signal.addEventListener('abort', () => {
      try {
        commit((current) => ({ ...current, updatedAtMs: 99 }));
      } catch (error) {
        staleErrors.push(error instanceof Error ? error.constructor.name : String(error));
      }
    });
    await firstGate.promise;
    if (signal.aborted) {
      throw new LivePlexTransportError('aborted', 'Plex request was aborted');
    }
    return { value: 'old' };
  });

  const second = await owner.run('request-new', 'listLibrarySections', async ({ commit }) => {
    commit((current) => ({ ...current, updatedAtMs: 2 }));
    return { value: 'new' };
  });
  firstGate.resolve();
  const cancelled = await first;

  assert.equal(second.ok, true);
  assert.equal(cancelled.ok, false);
  assert.equal(cancelled.ok ? '' : cancelled.error.code, 'PLEX_CANCELLED');
  assert.ok(staleErrors.length > 0);
  assert.equal(staleErrors.every((entry) => entry.length > 0), true);
  assert.equal(snapshot.updatedAtMs, 2);
});

test('plex runtime operation owner invalidates ownership before abortExcept listeners run', async () => {
  let snapshot = createSnapshot();
  const staleErrors: string[] = [];
  const owner = new PlexRuntimeOperationOwner({
    commitSnapshot: (update) => {
      snapshot = update(snapshot);
    },
    fail: (requestId, error, options) => failureResult(requestId, error, options),
    recordDiagnostic: () => undefined,
  });
  const abortedGate = deferred<void>();
  const keptGate = deferred<void>();
  const aborted = owner.run('request-aborted', 'pollPin:aborted', async ({ signal, commit }) => {
    signal.addEventListener('abort', () => {
      try {
        commit((current) => ({ ...current, updatedAtMs: 99 }));
      } catch (error) {
        staleErrors.push(error instanceof Error ? error.constructor.name : String(error));
      }
    });
    await abortedGate.promise;
    if (signal.aborted) {
      throw new LivePlexTransportError('aborted', 'Plex request was aborted');
    }
    return { value: 'aborted' };
  });
  const kept = owner.run('request-kept', 'pollPin:kept', async ({ commit }) => {
    await keptGate.promise;
    commit((current) => ({ ...current, updatedAtMs: 3 }));
    return { value: 'kept' };
  });

  owner.abortExcept('pollPin:kept');
  abortedGate.resolve();
  keptGate.resolve();
  const cancelled = await aborted;
  const keptResult = await kept;

  assert.equal(cancelled.ok, false);
  assert.equal(cancelled.ok ? '' : cancelled.error.code, 'PLEX_CANCELLED');
  assert.equal(keptResult.ok, true);
  assert.ok(staleErrors.length > 0);
  assert.equal(staleErrors.every((entry) => entry.length > 0), true);
  assert.equal(snapshot.updatedAtMs, 3);
});

test('desktop plex library operation executor preserves requested-limit pagination and safe summaries', async () => {
  const transport = new FakeLibraryTransport([
    mediaPayload([
      rawItem('item-1', 'Item 1'),
      rawItem('item-2', 'Item 2'),
      rawItem('item-3', 'Item 3'),
      rawItem('item-4', 'Item 4'),
    ]),
  ]);
  const executor = new DesktopPlexLibraryOperationExecutor(transport);

  const result = await executor.listItems(
    { sectionId: '1', limit: 3, sort: 'titleSort:asc', filter: { type: 1 }, includeCollections: true },
    createLibraryContext(),
  );

  assert.deepEqual(result.items.map((item) => item.ratingKey), ['item-1', 'item-2', 'item-3']);
  assert.deepEqual(result, {
    offset: 0,
    limit: 3,
    items: result.items,
  });
  assert.deepEqual(transport.listItemsRequests.map(({ offset, limit, sort, filter, includeCollections }) => ({
    offset,
    limit,
    sort,
    filter,
    includeCollections,
  })), [
    {
      offset: 0,
      limit: 3,
      sort: 'titleSort:asc',
      filter: { type: 1 },
      includeCollections: true,
    },
  ]);
  assert.equal(JSON.stringify(result).includes('MediaContainer'), false);
});

test('desktop plex library operation executor follows full pages until a short page', async () => {
  const transport = new FakeLibraryTransport([
    mediaPayload(Array.from({ length: 100 }, (_, index) => rawItem(`item-${index + 1}`, `Item ${index + 1}`))),
    mediaPayload([rawItem('item-101', 'Item 101'), rawItem('item-102', 'Item 102')]),
  ]);
  const executor = new DesktopPlexLibraryOperationExecutor(transport);

  const result = await executor.listItems({ sectionId: '1', offset: 5 }, createLibraryContext());

  assert.equal(result.items.length, 102);
  assert.deepEqual(transport.listItemsRequests.map(({ offset, limit }) => ({ offset, limit })), [
    { offset: 5, limit: 100 },
    { offset: 105, limit: 100 },
  ]);
});

function createSnapshot(): PlexRuntimeSnapshot {
  return {
    auth: {
      state: 'signed-out',
      pin: null,
      profile: null,
      homeUsers: [],
      credentialStatus: 'missing',
    },
    servers: {
      status: 'idle',
      selected: null,
      items: [],
      lastSelection: null,
    },
    library: {
      status: 'idle',
      sections: [],
      selectedSectionId: null,
      items: [],
      search: null,
      metadata: null,
    },
    lastError: null,
    updatedAtMs: 1,
  };
}

function createLibraryContext() {
  return {
    connection: {
      uri: 'https://plex.example.test',
      local: true,
      relay: false,
      protocol: 'https',
      address: 'plex.example.test',
      port: 443,
      latencyMs: 12,
    } satisfies PlexConnection,
    token: 'main-owned-token',
    signal: new AbortController().signal,
  };
}

class FakeLibraryTransport implements LivePlexLibraryTransport {
  readonly listItemsRequests: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0][] = [];

  constructor(private readonly listItemsResponses: unknown[]) {}

  async listLibrarySections(): ReturnType<LivePlexLibraryTransport['listLibrarySections']> {
    return { kind: 'json', data: { MediaContainer: { Directory: [] } } };
  }

  async listLibraryItems(
    input: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0],
  ): ReturnType<LivePlexLibraryTransport['listLibraryItems']> {
    this.listItemsRequests.push(input);
    const response = this.listItemsResponses.shift();
    assert.ok(response, 'expected queued list items response');
    return response as Awaited<ReturnType<LivePlexLibraryTransport['listLibraryItems']>>;
  }

  async searchLibrary(): ReturnType<LivePlexLibraryTransport['searchLibrary']> {
    return { kind: 'json', data: { MediaContainer: { Hub: [] } } };
  }

  async getMetadata(): ReturnType<LivePlexLibraryTransport['getMetadata']> {
    return { kind: 'json', data: { MediaContainer: { Metadata: [] } } };
  }

  async getCollectionItems(): ReturnType<LivePlexLibraryTransport['getCollectionItems']> {
    return { kind: 'json', data: { MediaContainer: { Metadata: [] } } };
  }

  async getShowEpisodes(): ReturnType<LivePlexLibraryTransport['getShowEpisodes']> {
    return { kind: 'json', data: { MediaContainer: { Metadata: [] } } };
  }

  async getPlaylistItems(): ReturnType<LivePlexLibraryTransport['getPlaylistItems']> {
    return { kind: 'json', data: { MediaContainer: { Metadata: [] } } };
  }

  async stopTranscodeSession(): ReturnType<LivePlexLibraryTransport['stopTranscodeSession']> {
    return undefined;
  }
}

function mediaPayload(metadata: unknown[]) {
  return {
    kind: 'json',
    data: { MediaContainer: { Metadata: metadata } },
  };
}

function rawItem(ratingKey: string, title: string) {
  return {
    ratingKey,
    key: `/library/metadata/${ratingKey}`,
    type: 'movie',
    title,
    titleSort: title,
    summary: 'Summary',
    year: 2026,
    duration: 1_000,
    addedAt: 1,
    updatedAt: 2,
  };
}
