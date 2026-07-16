import test from 'node:test';
import assert from 'node:assert/strict';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { renderCustomChannelWorkspace } from '../../renderer/customChannels/dom.js';
import type { CustomChannelRendererState } from '../../renderer/customChannels/controller.js';

class ElementDouble {
  textContent = '';
  className = '';
  type = '';
  disabled = false;
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  readonly children: ElementDouble[] = [];

  append(...children: ElementDouble[]): void {
    this.children.push(...children);
  }

  replaceChildren(...children: ElementDouble[]): void {
    this.children.splice(0, this.children.length, ...children);
  }

  setAttribute(name: string, value: string): void {
    this.attributes.set(name, value);
  }
}

test('custom channel DOM renders safe channel media and draft controls', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      createElement: () => new ElementDouble(),
    },
  });
  try {
    const status = new ElementDouble();
    const list = new ElementDouble();
    const media = new ElementDouble();
    const draft = new ElementDouble();
    renderCustomChannelWorkspace(createState(), {
      customChannelStatusElement: status as unknown as HTMLElement,
      customChannelListElement: list as unknown as HTMLElement,
      customChannelMediaElement: media as unknown as HTMLElement,
      customChannelDraftElement: draft as unknown as HTMLElement,
      customChannelNameInput: { value: '' } as HTMLInputElement,
      customChannelNumberInput: { value: '' } as HTMLInputElement,
      customChannelSearchInput: { value: '' } as HTMLInputElement,
    } as RendererDomBindings);

    assert.equal(status.textContent, '1 visible / 0 hidden');
    assert.equal(list.children.length, 1);
    assert.equal(media.children.length, 1);
    assert.equal(draft.children.length, 3);
    const rowActions = list.children[0]?.children.at(-1);
    assert.deepEqual(rowActions?.children.map((button) => button.dataset.customChannelAction), [
      'duplicateChannel', 'toggleChannelVisibility', 'requestDeleteChannel',
    ]);

    const mediaCard = media.children[0];
    const mediaActions = mediaCard?.children.at(-1);
    const detailsButton = mediaActions?.children[0];
    const addButton = mediaActions?.children[1];
    assert.equal(detailsButton?.dataset.customChannelAction, 'openMetadata');
    assert.equal(addButton?.dataset.customChannelAction, 'addMedia');
    assert.equal(addButton?.dataset.customChannelDetail, 'rating-1');
    assert.equal(addButton?.dataset.focusId, 'custom-media-add-rating-1');

    const serialized = JSON.stringify({ list, media, draft });
    assert.doesNotMatch(serialized, /token|serverUri|https?:|file:\/\//u);
  } finally {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: originalDocument,
    });
  }
});

test('custom channel DOM marks already added media and keeps deletion as a list-level request', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      createElement: () => new ElementDouble(),
    },
  });
  try {
    const list = new ElementDouble();
    const media = new ElementDouble();
    const draft = new ElementDouble();
    renderCustomChannelWorkspace({
      ...createState(),
      deleteConfirmationChannelId: 'channel-1',
    }, {
      customChannelStatusElement: new ElementDouble() as unknown as HTMLElement,
      customChannelListElement: list as unknown as HTMLElement,
      customChannelMediaElement: media as unknown as HTMLElement,
      customChannelDraftElement: draft as unknown as HTMLElement,
    } as RendererDomBindings);

    const addButton = media.children[0]?.children.at(-1)?.children[1];
    assert.equal(addButton?.disabled, true);
    assert.equal(addButton?.textContent, 'Added');
    assert.equal(addButton?.attributes.get('aria-pressed'), 'true');

    const channelActions = list.children[0]?.children.at(-1);
    const deleteButton = channelActions?.children.at(-1);
    assert.equal(deleteButton?.dataset.customChannelAction, 'requestDeleteChannel');
    assert.equal(deleteButton?.textContent, 'Delete');
  } finally {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: originalDocument,
    });
  }
});

test('custom channel DOM renders metadata panel with safe close action', () => {
  const originalDocument = Reflect.get(globalThis, 'document') as Document | undefined;
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      createElement: () => new ElementDouble(),
    },
  });
  try {
    const media = new ElementDouble();
    renderCustomChannelWorkspace({
      ...createState(),
      metadata: {
        ratingKey: 'rating-1',
        type: 'movie',
        title: 'Movie One',
        subtitle: '2026',
        summary: 'Safe summary.',
        year: 2026,
        durationMs: 7_200_000,
        genres: [],
        availability: 'available',
      },
    }, {
      customChannelStatusElement: new ElementDouble() as unknown as HTMLElement,
      customChannelListElement: new ElementDouble() as unknown as HTMLElement,
      customChannelMediaElement: media as unknown as HTMLElement,
      customChannelDraftElement: new ElementDouble() as unknown as HTMLElement,
    } as RendererDomBindings);

    const metadata = media.children[0];
    const closeButton = metadata?.children.at(-1);
    assert.equal(metadata?.className, 'custom-media-metadata');
    assert.equal(closeButton?.dataset.customChannelAction, 'closeMetadata');
    assert.equal(closeButton?.dataset.focusId, 'custom-media-close-details');
  } finally {
    Object.defineProperty(globalThis, 'document', {
      configurable: true,
      value: originalDocument,
    });
  }
});

function createState(): CustomChannelRendererState {
  return {
    snapshot: {
      channels: [{
        id: 'channel-1',
        number: 101,
        name: 'Safe Channel',
        description: null,
        itemCount: 1,
        estimatedDurationMs: 7_200_000,
        sourceSummary: 'Manual items',
        playbackMode: 'sequential',
        hidden: false,
        updatedAtMs: 1,
        isCurrent: true,
      }],
      currentChannelId: 'channel-1',
      visibleChannelCount: 1,
      hiddenChannelCount: 0,
      maxChannels: 500,
      nextAvailableNumber: 102,
      updatedAtMs: 1,
      storage: { status: 'ready', repaired: false },
    },
    mediaPage: {
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
    },
    metadata: null,
    draft: {
      number: 102,
      name: 'Draft Channel',
      hidden: false,
      content: [{
        type: 'manualItem',
        ratingKey: 'rating-1',
        title: 'Movie One',
        durationMs: 7_200_000,
        mediaType: 'movie',
      }],
      playbackMode: 'sequential',
    },
    validation: null,
    pending: false,
    mediaPending: false,
    metadataPending: false,
    lastError: null,
    query: '',
    mediaTypeFilter: 'all',
    deleteConfirmationChannelId: null,
    lastSavedChannelId: null,
    pendingAction: null,
    pendingChannelId: null,
  };
}
