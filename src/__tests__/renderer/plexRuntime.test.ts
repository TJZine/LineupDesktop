import test from 'node:test';
import assert from 'node:assert/strict';

import {
  containsPlexForbiddenRendererField,
  type PlexIpcResult,
  type PlexRuntimeSnapshot,
} from '../../contracts/plex.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import {
  clickFocusedRendererElement,
  registerRendererFocusTargets,
  syncRendererFocusTargets,
} from '../../renderer/focusDom.js';
import { FocusRegistry } from '../../renderer/navigation.js';
import { createPlexRuntimeController } from '../../renderer/plexRuntimeActions.js';
import { renderPlexRuntimeDom } from '../../renderer/plexRuntimeDom.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';

test('static channel setup markup hosts reachable Plex setup controls', () => {
  const root = { innerHTML: '', querySelector: () => null };
  const documentDouble = {
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  };

  mountStaticRendererDom(documentDouble as unknown as Document);

  assert.match(root.innerHTML, /data-plex-runtime-panel/u);
  assert.match(root.innerHTML, /data-plex-action="requestPin"/u);
  assert.match(root.innerHTML, /data-plex-action="clearSelectedServer"/u);
  assert.match(root.innerHTML, /data-plex-action="clearMetadata"/u);
  assert.match(root.innerHTML, /data-plex-search-query/u);
  assert.match(root.innerHTML, /data-screen="channelSetup"/u);
  assert.doesNotMatch(root.innerHTML, /Fake channel setup controls|data-setup-action|data-setup-steps|data-channel-draft-list/u);
  assert.doesNotMatch(root.innerHTML, /https?:|token|serverUri/u);
});

test('Plex runtime controller applies async setup, server, library, search, and metadata transitions', async () => {
  const calls: string[] = [];
  const states: unknown[] = [];
  const bridge = createBridge({
    getSnapshot: async () => success(snapshotSignedOut()),
    requestPin: async () => {
      calls.push('requestPin');
      return success({ pin: pinSummary(), snapshot: snapshotPinPending() });
    },
    pollPin: async ({ pinId }) => {
      calls.push(`pollPin:${pinId}`);
      return success({ pin: { ...pinSummary(), claimed: true }, profile: profile(), snapshot: snapshotSignedIn() });
    },
    cancelPin: async ({ pinId }) => {
      calls.push(`cancelPin:${pinId}`);
      return success({ pinId, snapshot: snapshotSignedOut() });
    },
    getHomeUsers: async () => success({ users: homeUsers(), snapshot: snapshotSignedIn() }),
    switchHomeUser: async ({ userId, pin }) => {
      calls.push(`switchHomeUser:${userId}:${pin ?? ''}`);
      return success({ profile: profile(), snapshot: snapshotSignedIn() });
    },
    restoreSelectedServer: async () => success({ selection: selectedServer(), snapshot: snapshotServersReady() }),
    refreshServers: async () => success({ servers: servers(), snapshot: snapshotServersReady() }),
    selectServer: async ({ serverId }) => {
      calls.push(`selectServer:${serverId}`);
      return success({ selection: selectedServer(), snapshot: snapshotServersReady() });
    },
    listLibrarySections: async () => success({ sections: sections(), snapshot: snapshotWithSections() }),
    listLibraryItems: async ({ sectionId }) => {
      calls.push(`listLibraryItems:${sectionId}`);
      return success({ sectionId, offset: 0, limit: 24, items: mediaItems(), snapshot: snapshotWithItems() });
    },
    searchLibrary: async ({ query, sectionId }) => {
      calls.push(`searchLibrary:${query}:${sectionId ?? ''}`);
      return success({ query, sectionId: sectionId ?? null, items: mediaItems(), snapshot: snapshotWithSearch(query) });
    },
    getMetadata: async ({ ratingKey }) => {
      calls.push(`getMetadata:${ratingKey}`);
      return success({ item: mediaItems()[0], snapshot: snapshotWithMetadata() });
    },
  });
  const controller = createPlexRuntimeController({
    bridge,
    onStateChanged: (state) => states.push(state),
    scheduler: inertScheduler(),
  });

  await controller.loadSnapshot();
  await controller.requestPin();
  await controller.pollPin();
  controller.setHomeUserPin('1234');
  await controller.getHomeUsers();
  await controller.switchHomeUser('home-1');
  await controller.restoreSelectedServer();
  await controller.refreshServers();
  await controller.selectServer('server-1');
  await controller.listLibrarySections();
  controller.setSelectedSection('section-1');
  await controller.listLibraryItems();
  controller.setSearchQuery('pilot');
  await controller.searchLibrary();
  await controller.getMetadata('rating-1');

  assert.deepEqual(calls, [
    'requestPin',
    'pollPin:42',
    'switchHomeUser:home-1:1234',
    'selectServer:server-1',
    'listLibraryItems:section-1',
    'searchLibrary:pilot:section-1',
    'getMetadata:rating-1',
  ]);
  assert.equal(controller.getState().snapshot?.auth.state, 'signed-in');
  assert.equal(controller.getState().lastMetadata?.title, 'Pilot');
  assert.equal(containsPlexForbiddenRendererField(controller.getState()), false);
  assert.ok(states.length > 0);
});

test('Plex runtime controller sanitizes failures, cancels pending PIN, and ignores stale commits', async () => {
  const pendingSnapshot = deferred<PlexIpcResult<PlexRuntimeSnapshot>>();
  const calls: string[] = [];
  const bridge = createBridge({
    getSnapshot: () => pendingSnapshot.promise,
    requestPin: async () => success({ pin: pinSummary(), snapshot: snapshotPinPending() }),
    pollPin: async () => success({ pin: pinSummary(), profile: null, snapshot: snapshotPinPending() }),
    cancelPin: async ({ pinId }) => {
      calls.push(`cancelPin:${pinId}`);
      return success({ pinId, snapshot: snapshotSignedOut() });
    },
    getHomeUsers: async () => failure('PLEX_SERVER_UNREACHABLE', 'token and serverUri hidden'),
  });
  const controller = createPlexRuntimeController({
    bridge,
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  const loading = controller.loadSnapshot();
  await controller.cleanup();
  pendingSnapshot.resolve(success(snapshotSignedIn()));
  await loading;
  assert.equal(controller.getState().snapshot, null);
  assert.equal(controller.getState().statusText, 'Cleaned up');

  await controller.requestPin();
  controller.setHomeUserPin('4321');
  await controller.cleanup();
  assert.deepEqual(calls, ['cancelPin:42']);
  assert.equal(controller.getState().snapshot?.auth.pin, null);
  assert.equal(controller.getState().homeUserPin, '');
  assert.equal(controller.getState().pending.cancelPin, false);
  assert.equal(controller.getState().pending.cleanup, false);

  await controller.getHomeUsers();
  assert.equal(controller.getState().errorText, 'The selected Plex server is unreachable.');
  assert.doesNotMatch(JSON.stringify(controller.getState()), /token|serverUri/u);
});

test('Plex runtime controller treats cleared library snapshots as authoritative', async () => {
  const calls: string[] = [];
  let snapshot = snapshotWithMetadata();
  const bridge = createBridge({
    getSnapshot: async () => success(snapshot),
    searchLibrary: async ({ query, sectionId }) => {
      calls.push(`searchLibrary:${query}:${sectionId ?? ''}`);
      return success({ query, sectionId: sectionId ?? null, items: [], snapshot });
    },
  });
  const controller = createPlexRuntimeController({
    bridge,
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  await controller.loadSnapshot();
  assert.equal(controller.getState().selectedSectionId, 'section-1');
  assert.equal(controller.getState().lastMetadata?.ratingKey, 'rating-1');

  snapshot = snapshotSignedOut();
  await controller.loadSnapshot();
  controller.setSearchQuery('pilot');
  await controller.searchLibrary();

  assert.equal(controller.getState().selectedSectionId, null);
  assert.equal(controller.getState().lastMetadata, null);
  assert.deepEqual(calls, ['searchLibrary:pilot:']);
});

test('Plex runtime controller clears nested setup state before route back', async () => {
  const calls: string[] = [];
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      getSnapshot: async () => success(snapshotWithMetadataAndSearch()),
      requestPin: async () => success({ pin: pinSummary(), snapshot: snapshotPinPending() }),
      cancelPin: async ({ pinId }) => {
        calls.push(`cancelPin:${pinId}`);
        return success({ pinId, snapshot: snapshotSignedOut() });
      },
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  await controller.loadSnapshot();
  controller.setSearchQuery('pilot');

  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().lastMetadata, null);
  assert.equal(controller.getState().selectedItemRatingKey, null);

  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().searchQuery, '');
  assert.equal(controller.getState().snapshot?.library.search, null);

  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().snapshot?.library.items.length, 0);

  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().selectedSectionId, null);

  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().selectedServerId, null);

  await controller.requestPin();
  controller.setHomeUserPin('1234');
  assert.equal(await controller.handleBack(), true);
  assert.deepEqual(calls, ['cancelPin:42']);
  assert.equal(controller.getState().snapshot?.auth.pin, null);
  assert.equal(controller.getState().homeUserPin, '');

  assert.equal(await controller.handleBack(), false);
});

test('Plex cleanup clears loaded profile and library snapshot state', async () => {
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      getSnapshot: async () => success(snapshotWithMetadataAndSearch()),
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  await controller.loadSnapshot();
  assert.equal(controller.getState().snapshot?.auth.homeUsers.length, 1);
  assert.equal(controller.getState().snapshot?.library.items.length, 1);
  assert.equal(controller.getState().snapshot?.library.search?.query, 'pilot');
  assert.equal(controller.getState().snapshot?.library.metadata?.ratingKey, 'rating-1');

  await controller.cleanup();

  assert.equal(controller.getState().snapshot?.auth.homeUsers.length, 0);
  assert.equal(controller.getState().snapshot?.library.sections.length, 0);
  assert.equal(controller.getState().snapshot?.library.items.length, 0);
  assert.equal(controller.getState().snapshot?.library.search, null);
  assert.equal(controller.getState().snapshot?.library.metadata, null);
  assert.equal(controller.getState().selectedSectionId, null);
  assert.equal(controller.getState().selectedServerId, null);
  assert.equal(controller.getState().selectedItemRatingKey, null);
  assert.equal(controller.getState().searchQuery, '');
});

test('Plex cleanup clears its pending flag when cancellation becomes stale', async () => {
  const pendingCancel = deferred<PlexIpcResult<{
    pinId: number;
    snapshot: PlexRuntimeSnapshot;
  }>>();
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      requestPin: async () => success({ pin: pinSummary(), snapshot: snapshotPinPending() }),
      cancelPin: () => pendingCancel.promise,
      getSnapshot: async () => success(snapshotSignedIn()),
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  await controller.requestPin();
  const cleanup = controller.cleanup();
  assert.equal(controller.getState().pending.cleanup, true);

  await controller.loadSnapshot();
  assert.equal(controller.getState().pending.cleanup, true);

  pendingCancel.resolve(success({ pinId: 42, snapshot: snapshotSignedOut() }));
  await cleanup;

  assert.equal(controller.getState().pending.cleanup, false);
});

test('Plex clear and back ignore pending setup operation results', async () => {
  const pendingMetadata = deferred<PlexIpcResult<{
    item: ReturnType<typeof mediaItems>[number];
    snapshot: PlexRuntimeSnapshot;
  }>>();
  const pendingPin = deferred<PlexIpcResult<{
    pin: ReturnType<typeof pinSummary>;
    snapshot: PlexRuntimeSnapshot;
  }>>();
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      getSnapshot: async () => success(snapshotWithItems()),
      getMetadata: () => pendingMetadata.promise,
      requestPin: () => pendingPin.promise,
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  await controller.loadSnapshot();
  const metadataLoad = controller.getMetadata('rating-1');
  assert.equal(controller.getState().pending.getMetadata, true);
  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().selectedItemRatingKey, null);
  assert.equal(controller.getState().pending.getMetadata, false);
  pendingMetadata.resolve(success({ item: mediaItems()[0], snapshot: snapshotWithMetadata() }));
  await metadataLoad;
  assert.equal(controller.getState().lastMetadata, null);
  assert.equal(controller.getState().snapshot?.library.metadata, null);

  const pinRequest = controller.requestPin();
  assert.equal(controller.getState().pending.requestPin, true);
  assert.equal(await controller.handleBack(), true);
  assert.equal(controller.getState().pending.requestPin, false);
  pendingPin.resolve(success({ pin: pinSummary(), snapshot: snapshotPinPending() }));
  await pinRequest;
  assert.equal(controller.getState().snapshot?.auth.pin, null);
  assert.equal(controller.getState().homeUserPin, '');
});

test('Plex runtime controller keeps newer matching operations pending after stale completion', async () => {
  const firstMetadata = deferred<PlexIpcResult<{
    item: ReturnType<typeof mediaItems>[number];
    snapshot: PlexRuntimeSnapshot;
  }>>();
  const secondMetadata = deferred<PlexIpcResult<{
    item: ReturnType<typeof mediaItems>[number];
    snapshot: PlexRuntimeSnapshot;
  }>>();
  let metadataCallCount = 0;
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      getSnapshot: async () => success(snapshotWithItems()),
      getMetadata: () => {
        metadataCallCount += 1;
        return metadataCallCount === 1 ? firstMetadata.promise : secondMetadata.promise;
      },
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  await controller.loadSnapshot();
  const firstLoad = controller.getMetadata('rating-1');
  const secondLoad = controller.getMetadata('rating-2');
  assert.equal(controller.getState().pending.getMetadata, true);

  firstMetadata.resolve(success({ item: mediaItems()[0], snapshot: snapshotWithMetadata() }));
  await firstLoad;
  assert.equal(controller.getState().pending.getMetadata, true);
  assert.equal(controller.getState().lastMetadata, null);

  const secondItem = { ...mediaItems()[0], ratingKey: 'rating-2', title: 'Second Pilot' };
  const secondSnapshotWithItems = snapshotWithItems();
  const secondSnapshot: PlexRuntimeSnapshot = {
    ...secondSnapshotWithItems,
    library: {
      ...secondSnapshotWithItems.library,
      items: [...secondSnapshotWithItems.library.items, secondItem],
      metadata: secondItem,
    },
  };

  secondMetadata.resolve(success({ item: secondItem, snapshot: secondSnapshot }));
  await secondLoad;
  assert.equal(controller.getState().pending.getMetadata, false);
  assert.equal(controller.getState().lastMetadata?.ratingKey, 'rating-2');
  assert.equal(controller.getState().lastMetadata?.title, 'Second Pilot');
});

test('Plex runtime controller preserves Unicode input while removing controls', async () => {
  const capturedMetadataKeys: string[] = [];
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      getMetadata: async ({ ratingKey }) => {
        capturedMetadataKeys.push(ratingKey);
        return success({ item: mediaItems()[0], snapshot: snapshotWithMetadata() });
      },
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
  });

  controller.setSearchQuery(` \u0000Cafe\u0301 東京 🎬\u0085\n `);
  assert.equal(controller.getState().searchQuery, 'Café 東京 🎬');

  controller.setSearchQuery(`${'界'.repeat(119)}🎬tail`);
  assert.equal(Array.from(controller.getState().searchQuery).length, 120);
  assert.equal(controller.getState().searchQuery.endsWith('🎬'), true);

  await controller.getMetadata(` película-🎬-\u0007rating `);

  assert.deepEqual(capturedMetadataKeys, ['película-🎬-rating']);
});

test('Plex runtime controller records redacted diagnostics for rejected bridge calls', async () => {
  const diagnosticEnvelopes: Array<Parameters<LineupDesktopPreloadApi['diagnostics']['recordRendererEvent']>[0]> = [];
  const controller = createPlexRuntimeController({
    bridge: createBridge({
      requestPin: async () => {
        throw new Error('raw token serverUri failure');
      },
    }),
    onStateChanged: () => undefined,
    scheduler: inertScheduler(),
    recordRendererEvent: async (envelope) => {
      diagnosticEnvelopes.push(envelope);
      return {
        ok: true,
        requestId: envelope.requestId,
        value: {
          schemaVersion: 1,
          id: envelope.requestId,
          timestampMs: 1,
          surface: 'renderer',
          category: 'ipc',
          severity: 'warning',
          status: 'observed',
          operation: envelope.event.operation,
          message: envelope.event.message,
        },
      };
    },
  });

  await controller.requestPin();

  assert.equal(controller.getState().pending.requestPin, false);
  assert.equal(controller.getState().errorText, 'The Plex operation failed.');
  assert.equal(diagnosticEnvelopes.length, 1);
  assert.equal(diagnosticEnvelopes[0]?.event.operation, 'plex.requestPin');
  assert.deepEqual(diagnosticEnvelopes[0]?.event.context, {
    operation: 'requestPin',
    errorName: 'Error',
  });
  assert.doesNotMatch(JSON.stringify(diagnosticEnvelopes), /token|serverUri/u);
});

test('Plex runtime DOM renders safe summaries and disables invalid actions', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = { createElement: () => new ElementDouble() };
  Object.defineProperty(globalThis, 'document', { value: documentDouble, configurable: true });

  try {
    const dom = createPlexDomBindings();
    renderPlexRuntimeDom({
      snapshot: snapshotWithMetadata(),
      selectedSectionId: 'section-1',
      selectedServerId: 'server-1',
      selectedItemRatingKey: 'rating-1',
      searchQuery: '',
      homeUserPin: '',
      statusText: 'Ready',
      errorText: 'Plex sign-in is required.',
      pending: pendingMap(false),
      lastMetadata: mediaItems()[0],
    }, dom);

    assert.match((dom.plexStatusElement as unknown as ElementDouble).textContent, /Ready/u);
    assert.match(collectText(dom.plexItemsElement as unknown as ElementDouble), /Pilot/u);
    assert.match(collectText(dom.plexMetadataElement as unknown as ElementDouble), /45 min/u);
    assert.match(collectText(dom.plexPinElement as unknown as ElementDouble), /Plex sign-in/u);
    assert.equal(dom.plexActionButtons.find((button) => button.dataset.plexAction === 'searchLibrary')?.disabled, true);
    assert.equal(dom.plexActionButtons.find((button) => button.dataset.plexAction === 'clearMetadata')?.disabled, false);
    const renderedText = [
      (dom.plexStatusElement as unknown as ElementDouble).textContent,
      (dom.plexErrorElement as unknown as ElementDouble).textContent,
      collectText(dom.plexPinElement as unknown as ElementDouble),
      collectText(dom.plexItemsElement as unknown as ElementDouble),
      collectText(dom.plexMetadataElement as unknown as ElementDouble),
    ].join(' ');
    assert.doesNotMatch(renderedText, /token|serverUri|\/Users\/|https?:/u);
  } finally {
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
    }
  }
});

test('Plex cleanup clears protected-home PIN input on next render', async () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = { createElement: () => new ElementDouble() };
  Object.defineProperty(globalThis, 'document', { value: documentDouble, configurable: true });

  try {
    const dom = createPlexDomBindings();
    const controller = createPlexRuntimeController({
      bridge: createBridge({
        requestPin: async () => success({ pin: pinSummary(), snapshot: snapshotPinPending() }),
        cancelPin: async ({ pinId }) => success({ pinId, snapshot: snapshotSignedOut() }),
      }),
      onStateChanged: (state) => renderPlexRuntimeDom(state, dom),
      scheduler: inertScheduler(),
    });

    await controller.requestPin();
    controller.setHomeUserPin('2468');
    assert.equal(dom.plexHomeUserPinInput?.value, '2468');

    await controller.cleanup();

    assert.equal(controller.getState().homeUserPin, '');
    assert.equal(dom.plexHomeUserPinInput?.value, '');
    assert.equal(dom.plexActionButtons.find((button) => button.dataset.plexAction === 'pollPin')?.disabled, true);
    assert.equal(dom.plexActionButtons.find((button) => button.dataset.plexAction === 'cancelPin')?.disabled, true);
  } finally {
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
    }
  }
});

test('Plex cleanup clears stale PIN UI when bridge cancellation is unavailable', async () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const documentDouble = { createElement: () => new ElementDouble() };
  Object.defineProperty(globalThis, 'document', { value: documentDouble, configurable: true });

  try {
    for (const cancelPin of [
      async () => null as unknown as Awaited<ReturnType<LineupDesktopPreloadApi['plex']['cancelPin']>>,
      async (): ReturnType<LineupDesktopPreloadApi['plex']['cancelPin']> => {
        throw new Error('cancel unavailable');
      },
    ]) {
      const dom = createPlexDomBindings();
      const controller = createPlexRuntimeController({
        bridge: createBridge({
          requestPin: async () => success({ pin: pinSummary(), snapshot: snapshotPinPending() }),
          cancelPin,
        }),
        onStateChanged: (state) => renderPlexRuntimeDom(state, dom),
        scheduler: inertScheduler(),
      });

      await controller.requestPin();
      controller.setHomeUserPin('1357');
      assert.match(collectText(dom.plexPinElement as unknown as ElementDouble), /ABCD/u);

      await controller.cleanup();

      assert.equal(controller.getState().snapshot?.auth.pin, null);
      assert.equal(controller.getState().homeUserPin, '');
      assert.match(
        collectText(dom.plexPinElement as unknown as ElementDouble),
        /Start Plex sign-in/u,
      );
      assert.equal(dom.plexActionButtons.find((button) => button.dataset.plexAction === 'pollPin')?.disabled, true);
      assert.equal(dom.plexActionButtons.find((button) => button.dataset.plexAction === 'cancelPin')?.disabled, true);
    }
  } finally {
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
    }
  }
});

test('Plex focus targets are registered on the channel setup route', () => {
  const registry = new FocusRegistry();
  const load = new FocusElementDouble('plex-load', 'loadSnapshot');
  const searchInput = new FocusElementDouble('plex-search-query');
  const dom = createPlexDomBindings({
    plexActionButtons: [load as unknown as HTMLButtonElement],
    focusableElements: [load, searchInput] as unknown as HTMLElement[],
  });

  registerRendererFocusTargets(registry, dom);
  const state = registry.createInitialState('channelSetup');
  const focusedInput = registry.focusTarget(state, 'plex-search-query');

  assert.equal(focusedInput.changed, true);
  assert.deepEqual(focusedInput.state, {
    activeRoute: 'channelSetup',
    activeId: 'plex-search-query',
  });
});

test('dynamic Plex buttons receive stable focus ids and are reachable by OK focus activation', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const originalButton = Reflect.get(globalThis, 'HTMLButtonElement') as typeof HTMLButtonElement | undefined;
  const documentDouble = { createElement: () => new ElementDouble() };
  Object.defineProperty(globalThis, 'document', { value: documentDouble, configurable: true });
  Object.defineProperty(globalThis, 'HTMLButtonElement', { value: ElementDouble, configurable: true });

  try {
    const registry = new FocusRegistry();
    const dom = createPlexDomBindings();
    renderPlexRuntimeDom({
      snapshot: {
        ...snapshotWithMetadata(),
        auth: { ...snapshotWithMetadata().auth, homeUsers: [{ ...homeUsers()[0], id: 'home/user 1' }] },
        servers: {
          ...snapshotWithMetadata().servers,
          items: [{ ...servers()[0], serverId: 'server/one' }],
        },
        library: {
          ...snapshotWithMetadata().library,
          sections: [{ ...sections()[0], id: 'section/one' }],
          items: [{ ...mediaItems()[0], ratingKey: 'rating/key 1' }],
        },
      },
      selectedSectionId: 'section/one',
      selectedServerId: 'server/one',
      selectedItemRatingKey: 'rating/key 1',
      searchQuery: '',
      homeUserPin: '',
      statusText: 'Ready',
      errorText: null,
      pending: pendingMap(false),
      lastMetadata: null,
    }, dom);

    syncRendererFocusTargets(registry, dom);

    const homeButton = firstChild(dom.plexHomeUsersElement);
    const serverButton = firstChild(dom.plexServersElement);
    const sectionButton = firstChild(dom.plexSectionsElement);
    const itemButton = firstChild(dom.plexItemsElement);
    const focusIds = [
      homeButton.dataset.focusId,
      serverButton.dataset.focusId,
      sectionButton.dataset.focusId,
      itemButton.dataset.focusId,
    ].map((focusId) => {
      assert.ok(focusId);
      return focusId;
    });
    assert.equal(focusIds[0]?.startsWith('plex-dyn-home-'), true);
    assert.equal(focusIds[1]?.startsWith('plex-dyn-server-'), true);
    assert.equal(focusIds[2]?.startsWith('plex-dyn-section-'), true);
    assert.equal(focusIds[3]?.startsWith('plex-dyn-item-'), true);
    assert.equal(new Set(focusIds).size, focusIds.length);

    const initial = registry.createInitialState('channelSetup');
    const focused = registry.focusTarget(initial, itemButton.dataset.focusId);
    assert.equal(focused.changed, true);
    clickFocusedRendererElement(focused.state, dom);
    assert.equal(itemButton.clickCount, 1);

    renderPlexRuntimeDom({
      snapshot: snapshotSignedOut(),
      selectedSectionId: null,
      selectedServerId: null,
      selectedItemRatingKey: null,
      searchQuery: '',
      homeUserPin: '',
      statusText: 'Ready',
      errorText: null,
      pending: pendingMap(false),
      lastMetadata: null,
    }, dom);
    syncRendererFocusTargets(registry, dom);
    const staleFocus = registry.focusTarget(focused.state, itemButton.dataset.focusId);
    assert.notEqual(staleFocus.state.activeId, itemButton.dataset.focusId);
  } finally {
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
    }
    if (originalButton === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLButtonElement');
    } else {
      Object.defineProperty(globalThis, 'HTMLButtonElement', { value: originalButton, configurable: true });
    }
  }
});

test('dynamic Plex Home focus ids do not collide with static home controls', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  const originalButton = Reflect.get(globalThis, 'HTMLButtonElement') as typeof HTMLButtonElement | undefined;
  const documentDouble = { createElement: () => new ElementDouble() };
  Object.defineProperty(globalThis, 'document', { value: documentDouble, configurable: true });
  Object.defineProperty(globalThis, 'HTMLButtonElement', { value: ElementDouble, configurable: true });

  try {
    const registry = new FocusRegistry();
    const staticPinInput = new FocusElementDouble('plex-home-pin');
    const staticUsersButton = new FocusElementDouble('plex-home-users', 'getHomeUsers');
    const dom = createPlexDomBindings({
      plexActionButtons: [staticUsersButton as unknown as HTMLButtonElement],
      focusableElements: [staticPinInput, staticUsersButton] as unknown as HTMLElement[],
    });
    renderPlexRuntimeDom({
      snapshot: {
        ...snapshotSignedIn(),
        auth: {
          ...snapshotSignedIn().auth,
          homeUsers: [
            { ...homeUsers()[0], id: 'pin', title: 'PIN user' },
            { ...homeUsers()[0], id: 'users', title: 'Users user' },
          ],
        },
      },
      selectedSectionId: null,
      selectedServerId: null,
      selectedItemRatingKey: null,
      searchQuery: '',
      homeUserPin: '',
      statusText: 'Ready',
      errorText: null,
      pending: pendingMap(false),
      lastMetadata: null,
    }, dom);

    syncRendererFocusTargets(registry, dom);

    const pinUserButton = childAt(dom.plexHomeUsersElement, 0);
    const usersUserButton = childAt(dom.plexHomeUsersElement, 1);
    assert.equal(pinUserButton.dataset.focusId, 'plex-dyn-home-pin');
    assert.equal(usersUserButton.dataset.focusId, 'plex-dyn-home-users');

    const initial = registry.createInitialState('channelSetup');
    const focusedPinUser = registry.focusTarget(initial, 'plex-dyn-home-pin');
    assert.equal(focusedPinUser.changed, true);
    clickFocusedRendererElement(focusedPinUser.state, dom);
    assert.equal(pinUserButton.clickCount, 1);
    assert.equal(staticPinInput.clickCount, 0);

    const focusedUsersUser = registry.focusTarget(focusedPinUser.state, 'plex-dyn-home-users');
    assert.equal(focusedUsersUser.changed, true);
    clickFocusedRendererElement(focusedUsersUser.state, dom);
    assert.equal(usersUserButton.clickCount, 1);
    assert.equal(staticUsersButton.clickCount, 0);
  } finally {
    if (originalDocument === undefined) {
      Reflect.deleteProperty(globalThis, 'document');
    } else {
      Object.defineProperty(globalThis, 'document', { value: originalDocument, configurable: true });
    }
    if (originalButton === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLButtonElement');
    } else {
      Object.defineProperty(globalThis, 'HTMLButtonElement', { value: originalButton, configurable: true });
    }
  }
});

class ElementDouble {
  hidden = false;
  disabled = false;
  textContent = '';
  value = '';
  type = '';
  clickCount = 0;
  readonly dataset: Record<string, string> = {};
  readonly children: ElementDouble[] = [];

  append(...children: ElementDouble[]): void {
    this.children.push(...children);
  }

  replaceChildren(...children: ElementDouble[]): void {
    this.children.splice(0, this.children.length, ...children);
  }

  click(): void {
    this.clickCount += 1;
  }

  closest(): object {
    return { dataset: { screen: 'channelSetup' } };
  }

  querySelectorAll(selector: string): ElementDouble[] {
    if (selector !== '[data-focus-id]') {
      return [];
    }
    return this.children.flatMap((child) => [
      ...(child.dataset.focusId === undefined ? [] : [child]),
      ...child.querySelectorAll(selector),
    ]);
  }

  toggleAttribute(): void {
    return;
  }
}

class FocusElementDouble extends ElementDouble {
  constructor(focusId: string, plexAction?: string) {
    super();
    this.dataset.focusId = focusId;
    if (plexAction !== undefined) {
      this.dataset.plexAction = plexAction;
    }
  }

  closest(): object {
    return { dataset: { screen: 'channelSetup' } };
  }
}

function createPlexDomBindings(overrides: Partial<RendererDomBindings> = {}): RendererDomBindings {
  const actions = [
    'searchLibrary',
    'pollPin',
    'cancelPin',
    'listLibraryItems',
    'clearMetadata',
    'clearSearch',
    'clearItems',
    'clearSelectedSection',
    'clearSelectedServer',
    'clearPinSubflow',
  ].map((action) => {
    const button = new ElementDouble();
    button.dataset.plexAction = action;
    return button as unknown as HTMLButtonElement;
  });
  return {
    statusElement: null,
    capabilitiesElement: null,
    fullscreenButton: null,
    routeTitleElement: null,
    routeStatusElement: null,
    routeButtons: [],
    routeActionButtons: [],
    settingsActionButtons: [],
    setupActionButtons: [],
    epgActionButtons: [],
    overlayActionButtons: [],
    screens: [],
    focusableElements: [],
    currentChannelElement: null,
    currentProgramElement: null,
    currentWindowElement: null,
    channelListElement: null,
    epgGridElement: null,
    epgDetailChannelElement: null,
    epgDetailTitleElement: null,
    epgDetailTimeElement: null,
    settingsSourceElement: null,
    settingsChannelsElement: null,
    settingsStateElement: null,
    settingsSectionsElement: null,
    channelSetupSourceElement: null,
    channelSetupEnabledElement: null,
    channelSetupBlocksElement: null,
    setupStepsElement: null,
    channelDraftListElement: null,
    setupValidationElement: null,
    plexPanelElement: new ElementDouble() as unknown as HTMLElement,
    plexActionButtons: actions,
    plexStatusElement: new ElementDouble() as unknown as HTMLElement,
    plexErrorElement: new ElementDouble() as unknown as HTMLElement,
    plexAccountStateElement: new ElementDouble() as unknown as HTMLElement,
    plexServerStateElement: new ElementDouble() as unknown as HTMLElement,
    plexLibraryStateElement: new ElementDouble() as unknown as HTMLElement,
    plexPinElement: new ElementDouble() as unknown as HTMLElement,
    plexHomeUserPinInput: new ElementDouble() as unknown as HTMLInputElement,
    plexSearchQueryInput: new ElementDouble() as unknown as HTMLInputElement,
    plexHomeUsersElement: new ElementDouble() as unknown as HTMLElement,
    plexServersElement: new ElementDouble() as unknown as HTMLElement,
    plexSectionsElement: new ElementDouble() as unknown as HTMLElement,
    plexItemsElement: new ElementDouble() as unknown as HTMLElement,
    plexMetadataElement: new ElementDouble() as unknown as HTMLElement,
    overlayElements: [],
    overlayStackElement: null,
    overlayNowPlayingTitleElement: null,
    overlayNowPlayingSubtitleElement: null,
    overlayNowPlayingChannelElement: null,
    overlayNowPlayingStatusElement: null,
    overlayProgressElement: null,
    overlayMiniGuideElement: null,
    overlayChannelNumberElement: null,
    overlayChannelBadgeNumberElement: null,
    overlayChannelBadgeNameElement: null,
    overlayChannelBadgeProgramElement: null,
    overlayAudioLabelElement: null,
    overlaySubtitleLabelElement: null,
    overlayVolumeLabelElement: null,
    overlayRateLabelElement: null,
    ...overrides,
  };
}

function createBridge(
  overrides: Partial<LineupDesktopPreloadApi['plex']>,
): LineupDesktopPreloadApi['plex'] {
  const missing = async (): Promise<never> => {
    throw new Error('missing bridge method');
  };
  return {
    getSnapshot: missing,
    requestPin: missing,
    pollPin: missing,
    cancelPin: missing,
    getHomeUsers: missing,
    switchHomeUser: missing,
    restoreSelectedServer: missing,
    refreshServers: missing,
    selectServer: missing,
    listLibrarySections: missing,
    listLibraryItems: missing,
    searchLibrary: missing,
    getMetadata: missing,
    ...overrides,
  };
}

function success<TValue>(value: TValue): PlexIpcResult<TValue> {
  return { ok: true, value, requestId: 'renderer-test' };
}

function failure<TValue>(
  code: Extract<PlexIpcResult<TValue>, { ok: false }>['error']['code'],
  message: string,
): PlexIpcResult<TValue> {
  return {
    ok: false,
    requestId: 'renderer-test',
    error: {
      code,
      message,
      retryable: false,
      recoverable: true,
      operation: 'getHomeUsers',
    },
  };
}

function deferred<TValue>(): {
  promise: Promise<TValue>;
  resolve: (value: TValue) => void;
} {
  let resolve: (value: TValue) => void = () => undefined;
  const promise = new Promise<TValue>((innerResolve) => {
    resolve = innerResolve;
  });
  return { promise, resolve };
}

function inertScheduler() {
  return {
    setTimeout: () => 1,
    clearTimeout: () => undefined,
  };
}

function pendingMap(value: boolean) {
  return {
    getSnapshot: value,
    requestPin: value,
    pollPin: value,
    cancelPin: value,
    getHomeUsers: value,
    switchHomeUser: value,
    restoreSelectedServer: value,
    refreshServers: value,
    selectServer: value,
    listLibrarySections: value,
    listLibraryItems: value,
    searchLibrary: value,
    getMetadata: value,
    pollPinLoop: value,
    cleanup: value,
  };
}

function snapshotSignedOut(): PlexRuntimeSnapshot {
  return {
    auth: {
      state: 'signed-out',
      pin: null,
      profile: null,
      homeUsers: [],
      credentialStatus: 'missing',
    },
    servers: { status: 'idle', selected: null, items: [], lastSelection: null },
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

function snapshotPinPending(): PlexRuntimeSnapshot {
  return {
    ...snapshotSignedOut(),
    auth: {
      state: 'pin-pending',
      pin: pinSummary(),
      profile: null,
      homeUsers: [],
      credentialStatus: 'missing',
    },
  };
}

function snapshotSignedIn(): PlexRuntimeSnapshot {
  return {
    ...snapshotSignedOut(),
    auth: {
      state: 'signed-in',
      pin: null,
      profile: profile(),
      homeUsers: homeUsers(),
      credentialStatus: 'present',
    },
  };
}

function snapshotServersReady(): PlexRuntimeSnapshot {
  return {
    ...snapshotSignedIn(),
    servers: {
      status: 'ready',
      selected: servers()[0],
      items: servers(),
      lastSelection: selectedServer(),
    },
  };
}

function snapshotWithSections(): PlexRuntimeSnapshot {
  return {
    ...snapshotServersReady(),
    library: {
      status: 'ready',
      sections: sections(),
      selectedSectionId: 'section-1',
      items: [],
      search: null,
      metadata: null,
    },
  };
}

function snapshotWithItems(): PlexRuntimeSnapshot {
  return {
    ...snapshotWithSections(),
    library: {
      ...snapshotWithSections().library,
      items: mediaItems(),
    },
  };
}

function snapshotWithSearch(query: string): PlexRuntimeSnapshot {
  return {
    ...snapshotWithItems(),
    library: {
      ...snapshotWithItems().library,
      search: { query, items: mediaItems() },
    },
  };
}

function snapshotWithMetadata(): PlexRuntimeSnapshot {
  return {
    ...snapshotWithItems(),
    library: {
      ...snapshotWithItems().library,
      metadata: mediaItems()[0],
    },
  };
}

function snapshotWithMetadataAndSearch(): PlexRuntimeSnapshot {
  return {
    ...snapshotWithMetadata(),
    library: {
      ...snapshotWithMetadata().library,
      search: { query: 'pilot', items: mediaItems() },
    },
  };
}

function pinSummary() {
  return {
    id: 42,
    code: 'ABCD',
    expiresAtMs: Date.UTC(2026, 4, 14, 12, 0, 0),
    claimed: false,
  };
}

function profile() {
  return {
    accountId: 'account-1',
    username: 'user',
    displayName: 'Profile',
  };
}

function homeUsers() {
  return [{ id: 'home-1', title: 'Profile', admin: false, protected: true }];
}

function servers() {
  return [{
    serverId: 'server-1',
    name: 'Server',
    owned: true,
    connectionCount: 1,
    hasLocalConnection: true,
    hasRemoteConnection: false,
    hasRelayConnection: false,
    selected: true,
    health: {
      status: 'ok' as const,
      connectionKind: 'local' as const,
      testedAtMs: 1,
    },
  }];
}

function selectedServer() {
  return { kind: 'selected' as const, server: servers()[0], persisted: true };
}

function sections() {
  return [{
    id: 'section-1',
    title: 'Movies',
    type: 'movie' as const,
    contentCount: 1,
    lastScannedAtMs: 1,
  }];
}

function mediaItems() {
  return [{
    ratingKey: 'rating-1',
    type: 'movie' as const,
    title: 'Pilot',
    sortTitle: 'Pilot',
    summary: 'Metadata summary.',
    year: 2026,
    durationMs: 2_700_000,
    addedAtMs: 1,
    updatedAtMs: 1,
    genres: ['Drama'],
  }];
}

function collectText(element: ElementDouble): string {
  return [element.textContent, ...element.children.map(collectText)].join(' ');
}

function firstChild(element: HTMLElement | null): ElementDouble {
  return childAt(element, 0);
}

function childAt(element: HTMLElement | null, index: number): ElementDouble {
  assert.ok(element);
  const child = (element as unknown as ElementDouble).children[index];
  assert.ok(child);
  return child;
}
