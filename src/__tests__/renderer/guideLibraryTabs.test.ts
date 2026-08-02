import assert from 'node:assert/strict';
import test from 'node:test';

import { guideLibraryFocusId, guideLibraryTabsDom, projectGuideLibraryTabsPending, shouldRenderGuideLibraryTabs } from '../../renderer/epg/guideDom.js';
import { registerRendererFocusTargets, shouldYieldGuideProgramDirectionToFocusGraph } from '../../renderer/focusDom.js';
import { FocusRegistry, type FocusState } from '../../renderer/navigation.js';
import { createGuideLibraryFilterController } from '../../renderer/guidePresentation.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import type { GuideIpcResult, GuideLibraryFilterState } from '../../contracts/guide.js';

class ElementStub {
  className = '';
  dataset: Record<string, string> = {};
  attributes = new Map<string, string>();
  children: ElementStub[] = [];
  textContent = '';
  tabIndex = 0;
  constructor(readonly tagName: string) {}
  setAttribute(name: string, value: string) { this.attributes.set(name, value); }
  append(...children: ElementStub[]) { this.children.push(...children); }
}

test('Guide library tabs expose accessible All/library selection with stable focus ids', () => {
  const previous = globalThis.document;
  globalThis.document = { createElement: (tag: string) => new ElementStub(tag) } as never;
  try {
    const tabs = guideLibraryTabsDom({
      scopeToken: 'scope', revision: 2, selectedLibraryId: 'library-b', persistenceStatus: 'ready',
      libraries: [
        { id: 'library-a', name: 'Alpha', contentKind: 'show' },
        { id: 'library-b', name: 'Beta', contentKind: 'movie' },
      ],
    }) as unknown as ElementStub;
    assert.equal(tabs.attributes.get('role'), 'tablist');
    assert.deepEqual(tabs.children.map((tab) => tab.textContent), ['All', 'Alpha', 'Beta']);
    assert.deepEqual(tabs.children.map((tab) => tab.attributes.get('aria-selected')), ['false', 'false', 'true']);
    assert.equal(tabs.children[2]?.dataset.focusId, guideLibraryFocusId('library-b'));
    assert.equal(tabs.children[2]?.tabIndex, 0);
  } finally {
    globalThis.document = previous;
  }
});

test('Guide library tabs stay hidden when disabled or fewer than two libraries are eligible', () => {
  const none = {
    scopeToken: 'scope', revision: 0, selectedLibraryId: null, persistenceStatus: 'ready' as const, libraries: [],
  };
  const one = { ...none, libraries: [{ id: 'library-a', name: 'Alpha', contentKind: 'show' as const }] };
  const two = { ...one, libraries: [...one.libraries, { id: 'library-b', name: 'Beta', contentKind: 'movie' as const }] };
  assert.equal(shouldRenderGuideLibraryTabs(true, none), false);
  assert.equal(shouldRenderGuideLibraryTabs(true, one), false);
  assert.equal(shouldRenderGuideLibraryTabs(false, two), false);
  assert.equal(shouldRenderGuideLibraryTabs(true, two), true);
});

test('Guide library tabs join the real focus graph from first row and return to selected program', () => {
  const elements = [
    focusElement(guideLibraryFocusId(null), { ariaSelected: 'false' }),
    focusElement(guideLibraryFocusId('library-a'), { ariaSelected: 'true' }),
    focusElement(guideLibraryFocusId('library-b'), { ariaSelected: 'false' }),
    focusElement('guide-program-a--1', { channelId: 'channel-a' }),
    focusElement('guide-program-a--2', { channelId: 'channel-a' }),
    focusElement('guide-program-b--1', { channelId: 'channel-b', selectedProgram: true }),
  ];
  const registry = new FocusRegistry();
  registerRendererFocusTargets(registry, {
    fullscreenButton: null, routeActionButtons: [], epgActionButtons: [], settingsActionButtons: [], setupActionButtons: [],
    plexActionButtons: [], focusableElements: elements, overlayActionButtons: [],
  } as unknown as RendererDomBindings);
  let state: FocusState = { activeRoute: 'guide', activeId: 'guide-program-a--1' };
  assert.equal(shouldYieldGuideProgramDirectionToFocusGraph(state.activeId!, 'up', elements), true);
  state = registry.move(state, 'up').state;
  assert.equal(state.activeId, guideLibraryFocusId('library-a'));
  state = registry.move(state, 'left').state;
  assert.equal(state.activeId, guideLibraryFocusId(null));
  state = registry.move(state, 'right').state;
  assert.equal(state.activeId, guideLibraryFocusId('library-a'));
  state = registry.move(state, 'down').state;
  assert.equal(state.activeId, 'guide-program-b--1');
  assert.equal(shouldYieldGuideProgramDirectionToFocusGraph('guide-program-b--1', 'up', elements), false);
});

test("Guide All sentinel and concrete public library id 'all' remain injective in D-pad navigation", () => {
  const previous = globalThis.document;
  globalThis.document = { createElement: (tag: string) => new ElementStub(tag) } as never;
  let tabs: ElementStub;
  try {
    tabs = guideLibraryTabsDom({
      scopeToken: 'scope', revision: 0, selectedLibraryId: 'all', persistenceStatus: 'ready',
      libraries: [
        { id: 'all', name: 'Concrete All', contentKind: 'show' },
        { id: 'other', name: 'Other', contentKind: 'movie' },
      ],
    }) as unknown as ElementStub;
  } finally {
    globalThis.document = previous;
  }
  const sentinel = tabs.children[0]!.dataset.focusId!;
  const concreteAll = tabs.children[1]!.dataset.focusId!;
  assert.notEqual(sentinel, concreteAll);
  assert.equal(sentinel, guideLibraryFocusId(null));
  assert.equal(concreteAll, guideLibraryFocusId('all'));
  assert.match(sentinel, /^[a-z0-9-]+$/u);
  assert.match(concreteAll, /^[a-z0-9-]+$/u);
  const elements = [
    focusElement(sentinel, { ariaSelected: 'false' }),
    focusElement(concreteAll, { ariaSelected: 'true' }),
    focusElement(guideLibraryFocusId('other'), { ariaSelected: 'false' }),
    focusElement('guide-program-a--1', { channelId: 'channel-a', selectedProgram: true }),
  ];
  const registry = new FocusRegistry();
  registerRendererFocusTargets(registry, {
    fullscreenButton: null, routeActionButtons: [], epgActionButtons: [], settingsActionButtons: [], setupActionButtons: [],
    plexActionButtons: [], focusableElements: elements, overlayActionButtons: [],
  } as unknown as RendererDomBindings);
  let state: FocusState = { activeRoute: 'guide', activeId: 'guide-program-a--1' };
  state = registry.move(state, 'up').state;
  assert.equal(state.activeId, concreteAll);
  state = registry.move(state, 'left').state;
  assert.equal(state.activeId, sentinel);
  state = registry.move(state, 'right').state;
  assert.equal(state.activeId, concreteAll);
  state = registry.move(state, 'down').state;
  assert.equal(state.activeId, 'guide-program-a--1');
});

test('Guide library filter controller owns exact CAS, pending exclusion, success refresh, and conflict settlement', async () => {
  const requests: Array<{ input: { expectedScopeToken: string; expectedRevision: number; libraryId: string | null }; deferred: Deferred<GuideIpcResult<GuideLibraryFilterState>> }> = [];
  let filter = filterState();
  let activeRoute: 'guide' | 'player' = 'guide';
  let refreshes = 0;
  let pageCancels = 0;
  let pendingChanges = 0;
  const failures: string[] = [];
  const controller = createGuideLibraryFilterController({
    guide: {
      setLibraryFilter: async (input: { expectedScopeToken: string; expectedRevision: number; libraryId: string | null }) => {
        const deferred = createDeferred<GuideIpcResult<GuideLibraryFilterState>>();
        requests.push({ input, deferred });
        return deferred.promise;
      },
    } as never,
    getActiveRoute: () => activeRoute,
    getFilter: () => filter,
    applyFilter: (next) => { filter = next; },
    refresh: () => { refreshes += 1; },
    cancelPage: () => { pageCancels += 1; },
    handleFailure: (message) => failures.push(message),
    onPendingChanged: () => { pendingChanges += 1; },
  });
  assert.equal(controller.select('library-b'), true);
  assert.equal(controller.isPending(), true);
  assert.equal(controller.select(null), false);
  assert.deepEqual(requests[0]?.input, { expectedScopeToken: 'scope', expectedRevision: 3, libraryId: 'library-b' });
  assert.equal(pageCancels, 1);
  requests[0]?.deferred.resolve({
    ok: false, requestId: 'request', error: {
      code: 'GUIDE_FILTER_REVISION_CONFLICT', message: 'Guide filter changed. Refresh and try again.',
      retryable: true, recoverable: true, operation: 'setLibraryFilter',
    },
  });
  await settle();
  assert.equal(controller.isPending(), false);
  assert.deepEqual(failures, ['Guide filter changed. Refresh and try again.']);
  assert.equal(refreshes, 0);

  assert.equal(controller.select('library-b'), true);
  const accepted = { ...filterState(), revision: 4, selectedLibraryId: 'library-b' };
  requests[1]?.deferred.resolve({ ok: true, requestId: 'request', value: accepted });
  await settle();
  assert.equal(filter.selectedLibraryId, 'library-b');
  assert.equal(refreshes, 1);
  assert.equal(pendingChanges, 4);

  assert.equal(controller.select(null), true);
  filter = { ...filter, scopeToken: 'replacement-scope' };
  requests[2]?.deferred.resolve({ ok: true, requestId: 'request', value: { ...accepted, revision: 5, selectedLibraryId: null } });
  await settle();
  assert.equal(filter.scopeToken, 'replacement-scope');
  assert.equal(refreshes, 1);

  assert.equal(controller.select(null), true);
  activeRoute = 'player';
  controller.cancel();
  requests[3]?.deferred.resolve({ ok: true, requestId: 'request', value: { ...filter, revision: 5, selectedLibraryId: null } });
  await settle();
  assert.equal(filter.selectedLibraryId, 'library-b');
  assert.equal(refreshes, 1);
});

test('Guide pending tabs retain focus custody while blocking repeat activation', () => {
  const tabs = [pendingTab(), pendingTab()];
  const root = { querySelectorAll: () => tabs } as unknown as HTMLElement;
  projectGuideLibraryTabsPending(root, true);
  for (const tab of tabs) {
    assert.equal(tab.attributes.get('aria-disabled'), 'true');
    assert.equal(tab.attributes.get('aria-busy'), 'true');
    assert.equal(tab.dataset.overlayBusyFocusCustody, 'true');
  }
  projectGuideLibraryTabsPending(root, false);
  for (const tab of tabs) {
    assert.equal(tab.attributes.get('aria-disabled'), 'false');
    assert.equal(tab.attributes.has('aria-busy'), false);
    assert.equal(tab.dataset.overlayBusyFocusCustody, undefined);
  }
});

function filterState(): GuideLibraryFilterState {
  return {
    scopeToken: 'scope', revision: 3, selectedLibraryId: 'library-a', persistenceStatus: 'ready',
    libraries: [
      { id: 'library-a', name: 'Alpha', contentKind: 'show' },
      { id: 'library-b', name: 'Beta', contentKind: 'movie' },
    ],
  };
}

function focusElement(
  focusId: string,
  options: { ariaSelected?: string; channelId?: string; selectedProgram?: boolean },
): HTMLElement {
  return {
    dataset: {
      focusId,
      ...(options.channelId === undefined ? {} : { guideChannelId: options.channelId }),
      ...(options.selectedProgram === undefined ? {} : { selectedProgram: String(options.selectedProgram) }),
    },
    getAttribute: (name: string) => name === 'aria-selected' ? options.ariaSelected ?? null : 'false',
    closest: (selector: string) => selector === '[data-screen]' ? { dataset: { screen: 'guide' } } : null,
  } as unknown as HTMLElement;
}

interface Deferred<T> { promise: Promise<T>; resolve(value: T): void }
function createDeferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  return { promise: new Promise<T>((done) => { resolve = done; }), resolve };
}
async function settle(): Promise<void> { await Promise.resolve(); await Promise.resolve(); }
function pendingTab() {
  return {
    dataset: {} as Record<string, string>,
    attributes: new Map<string, string>(),
    setAttribute(name: string, value: string) { this.attributes.set(name, value); },
    removeAttribute(name: string) { this.attributes.delete(name); },
  };
}
