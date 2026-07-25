import test from 'node:test';
import assert from 'node:assert/strict';

import {
  containsCustomChannelForbiddenRendererField,
  type CustomChannelDraftInput,
} from '../../contracts/customChannels.js';
import type {
  ChannelAggregate,
  ChannelAggregateMutationRequest,
  ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import type { ChannelConfig, StoredChannelData } from '../../domain/channel/index.js';
import { encodeStoredChannelData } from '../../domain/channel/storedChannelDataCodec.js';
import { CustomChannelRuntime } from '../../main/channel/customChannelRuntime.js';

test('custom channel runtime returns a safe not-configured snapshot', async () => {
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 123 },
  });

  const result = await runtime.getSnapshot('custom-snapshot-empty');

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value : null, {
    channels: [],
    currentChannelId: null,
    visibleChannelCount: 0,
    hiddenChannelCount: 0,
    maxChannels: 500,
    nextAvailableNumber: 1,
    updatedAtMs: 123,
    storage: { status: 'not-configured', repaired: false },
  });
  assert.equal(containsCustomChannelForbiddenRendererField(result), false);
});

test('custom channel runtime validates and saves a new manual channel', async () => {
  const refreshEvents: unknown[] = [];
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 1_000 },
    generateId: createIdGenerator('custom'),
    onChannelsChanged: (event) => { refreshEvents.push(event); },
  });

  const validation = await runtime.validateDraft('custom-validate', draft());
  const saved = await runtime.saveDraft('custom-save', draft());

  assert.equal(validation.ok, true);
  assert.deepEqual(validation.ok ? validation.value : null, { valid: true, issues: [] });
  assert.equal(saved.ok, true);
  assert.deepEqual(saved.ok ? saved.value.snapshot.channels.map((channel) => ({
    id: channel.id,
    number: channel.number,
    name: channel.name,
    itemCount: channel.itemCount,
    estimatedDurationMs: channel.estimatedDurationMs,
    hidden: channel.hidden,
    isCurrent: channel.isCurrent,
  })) : [], [{
    id: 'custom-1',
    number: 10,
    name: 'Custom Movies',
    itemCount: 1,
    estimatedDurationMs: 90_000,
    hidden: false,
    isCurrent: true,
  }]);
  assert.deepEqual(refreshEvents, [{
    operation: 'saveDraft',
    reason: 'save',
    changedChannelId: 'custom-1',
  }]);
  assert.equal(containsCustomChannelForbiddenRendererField(saved), false);
});

test('custom channel runtime edits existing channels and rejects stale drafts', async () => {
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('previous', 9), channel('existing', 10), channel('next', 11)],
      channelOrder: ['previous', 'existing', 'next'],
      currentChannelId: 'existing',
      savedAt: 10,
    })),
    clock: { now: () => 2_000 },
    generateId: createIdGenerator('unused'),
  });

  const stale = await runtime.saveDraft('custom-stale', {
    ...draft({ id: 'existing', name: 'Stale Edit' }),
    expectedRevision: 'updatedAt:999',
  });
  const missingRevision = await runtime.saveDraft('custom-missing-revision', draft({
    id: 'existing',
    name: 'Missing Revision',
  }));
  const edited = await runtime.saveDraft('custom-edit', {
    ...draft({ id: 'existing', name: 'Edited Movies', hidden: true }),
    expectedRevision: 'updatedAt:1000',
  });

  assert.equal(stale.ok, false);
  assert.equal(stale.ok ? null : stale.error.code, 'CUSTOM_CHANNEL_CONFLICT');
  assert.equal(missingRevision.ok, false);
  assert.equal(missingRevision.ok ? null : missingRevision.error.code, 'CUSTOM_CHANNEL_CONFLICT');
  assert.equal(edited.ok, true);
  assert.deepEqual(edited.ok ? edited.value.snapshot.channels.map((entry) => ({
    id: entry.id,
    name: entry.name,
    hidden: entry.hidden,
  })) : [], [
    { id: 'previous', name: 'Channel previous', hidden: false },
    { id: 'existing', name: 'Edited Movies', hidden: true },
    { id: 'next', name: 'Channel next', hidden: false },
  ]);
  assert.equal(edited.ok ? edited.value.snapshot.currentChannelId : null, 'next');
  assert.equal(containsCustomChannelForbiddenRendererField(edited), false);
});

test('custom mutations preserve builder metadata and clear only modified provenance identities', async () => {
  let aggregate = {
    storedChannelData: storedData({
      channels: [channel('existing', 10), channel('other', 11)],
      channelOrder: ['existing', 'other'],
      currentChannelId: 'existing',
      savedAt: 10,
    }),
    currentChannelId: 'existing',
    lineupRevision: 7,
    channelBuilderState: {
      schemaVersion: 1,
      normalizedConfig: { sentinel: 'config' },
      completedAtMs: 900,
      profileBinding: 'profile',
      serverBinding: 'server',
      librarySetBinding: 'libraries',
      channelProvenance: {
        existing: { marker: 'existing' },
        other: { marker: 'other' },
      },
    },
  } as unknown as ChannelAggregate;
  const storage = {
    ...createMemoryStorage(null),
    readChannelAggregate: async () => aggregate,
    mutateChannelAggregate: async (request: ChannelAggregateMutationRequest) => {
      const next = request.mutate(aggregate);
      if (request.onCommitBarrier() === 'cancel') return { status: 'canceled' as const };
      aggregate = { ...next, lineupRevision: aggregate.lineupRevision + 1 };
      return { status: 'committed' as const, aggregate };
    },
  };
  const runtime = new CustomChannelRuntime({
    storage,
    clock: { now: () => 2_000 },
    generateId: createIdGenerator('unused'),
  });

  const edited = await runtime.saveDraft('custom-edit-provenance', {
    ...draft({ id: 'existing', name: 'Edited Movies' }),
    expectedRevision: 'updatedAt:1000',
  });
  assert.equal(edited.ok, true);
  assert.equal(aggregate.lineupRevision, 8);
  assert.equal(aggregate.channelBuilderState?.completedAtMs, 900);
  assert.equal(
    Object.hasOwn(aggregate.channelBuilderState?.channelProvenance ?? {}, 'existing'),
    false,
  );
  assert.equal(
    Object.hasOwn(aggregate.channelBuilderState?.channelProvenance ?? {}, 'other'),
    true,
  );

  const deleted = await runtime.deleteChannel('custom-delete-provenance', {
    channelId: 'other',
    confirm: true,
  });
  assert.equal(deleted.ok, true);
  assert.equal(aggregate.lineupRevision, 9);
  assert.equal(
    Object.hasOwn(aggregate.channelBuilderState?.channelProvenance ?? {}, 'other'),
    false,
  );
});

test('custom channel runtime serializes concurrent saves against latest state', async () => {
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 3_000 },
    generateId: createIdGenerator('serialized'),
  });

  const [first, second] = await Promise.all([
    runtime.saveDraft('custom-save-one', draft({ number: 11, name: 'One' })),
    runtime.saveDraft('custom-save-two', draft({ number: 12, name: 'Two' })),
  ]);
  const snapshot = await runtime.getSnapshot('custom-after-concurrent');

  assert.equal(first.ok, true);
  assert.equal(second.ok, true);
  assert.deepEqual(snapshot.ok ? snapshot.value.channels.map((entry) => entry.name) : [], ['One', 'Two']);
  assert.equal(containsCustomChannelForbiddenRendererField(snapshot), false);
});

test('custom channel runtime deletes with confirmation and rejects invalid reorders', async () => {
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('one', 1), channel('two', 2)],
      channelOrder: ['one', 'two'],
      currentChannelId: 'one',
      savedAt: 10,
    })),
    clock: { now: () => 4_000 },
  });

  const blockedDelete = await runtime.deleteChannel('custom-delete-blocked', {
    channelId: 'one',
    confirm: false,
  });
  const invalidReorder = await runtime.reorderChannels('custom-reorder-invalid', ['two']);
  const deleted = await runtime.deleteChannel('custom-delete', {
    channelId: 'one',
    confirm: true,
  });

  assert.equal(blockedDelete.ok, false);
  assert.equal(blockedDelete.ok ? null : blockedDelete.error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(invalidReorder.ok, false);
  assert.equal(invalidReorder.ok ? null : invalidReorder.error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(deleted.ok, true);
  assert.deepEqual(deleted.ok ? deleted.value.snapshot.channels.map((entry) => entry.id) : [], ['two']);
  assert.equal(deleted.ok ? deleted.value.snapshot.currentChannelId : null, 'two');
});

test('custom channel runtime reorders and changes visibility with hidden-aware fallback', async () => {
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('one', 1), channel('two', 2), channel('three', 3)],
      channelOrder: ['one', 'two', 'three'],
      currentChannelId: 'one',
      savedAt: 10,
    })),
    clock: { now: () => 5_000 },
  });

  const reordered = await runtime.reorderChannels('custom-reorder', ['two', 'one', 'three']);
  const hidden = await runtime.setChannelVisibility('custom-hide', { channelId: 'one', hidden: true });

  assert.equal(reordered.ok, true);
  assert.deepEqual(reordered.ok ? reordered.value.snapshot.channels.map((entry) => entry.id) : [], ['two', 'one', 'three']);
  assert.equal(hidden.ok, true);
  assert.equal(hidden.ok ? hidden.value.snapshot.currentChannelId : null, 'three');
  assert.deepEqual(hidden.ok ? {
    visible: hidden.value.snapshot.visibleChannelCount,
    hidden: hidden.value.snapshot.hiddenChannelCount,
  } : null, { visible: 2, hidden: 1 });
});

test('custom channel runtime falls back to previous visible channel or null when hiding current', async () => {
  const previousRuntime = new CustomChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('one', 1), channel('two', 2), channel('three', 3, true)],
      channelOrder: ['one', 'two', 'three'],
      currentChannelId: 'two',
      savedAt: 10,
    })),
    clock: { now: () => 5_500 },
  });
  const allHiddenRuntime = new CustomChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('one', 1, true), channel('two', 2)],
      channelOrder: ['one', 'two'],
      currentChannelId: 'two',
      savedAt: 10,
    })),
    clock: { now: () => 5_600 },
  });

  const previous = await previousRuntime.setChannelVisibility('custom-hide-previous', {
    channelId: 'two',
    hidden: true,
  });
  const none = await allHiddenRuntime.setChannelVisibility('custom-hide-none', {
    channelId: 'two',
    hidden: true,
  });

  assert.equal(previous.ok, true);
  assert.equal(previous.ok ? previous.value.snapshot.currentChannelId : null, 'one');
  assert.equal(none.ok, true);
  assert.equal(none.ok ? none.value.snapshot.currentChannelId : 'not-null', null);
});

test('custom channel runtime duplicates an existing channel into a valid draft', async () => {
  const runtime = new CustomChannelRuntime({
    storage: createMemoryStorage(storedData({
      channels: [channel('one', 1, true)],
      channelOrder: ['one'],
      currentChannelId: 'one',
      savedAt: 10,
    })),
    clock: { now: () => 6_000 },
  });

  const duplicate = await runtime.duplicateChannelDraft('custom-duplicate', 'one');

  assert.equal(duplicate.ok, true);
  assert.equal(duplicate.ok ? duplicate.value.validation.valid : false, true);
  assert.deepEqual(duplicate.ok ? {
    number: duplicate.value.draft.number,
    name: duplicate.value.draft.name,
    hidden: duplicate.value.draft.hidden,
    contentCount: duplicate.value.draft.content.length,
  } : null, { number: 2, name: 'Channel one Copy', hidden: false, contentCount: 1 });
  assert.equal(containsCustomChannelForbiddenRendererField(duplicate), false);
});

test('custom channel runtime maps write and refresh failures to safe results', async () => {
  const diagnostics: unknown[] = [];
  const writeFailed = new CustomChannelRuntime({
    storage: {
      ...createMemoryStorage(null),
      mutateChannelAggregate: async () => {
        throw new Error('EACCES /Users/private/channels.json token=secret');
      },
      readStoredChannelData: async () => null,
      writeStoredChannelData: async () => {
        throw new Error('EACCES /Users/private/channels.json token=secret');
      },
      clearStoredChannelData: async () => undefined,
      readCurrentChannelId: async () => null,
      writeCurrentChannelId: async () => undefined,
    },
    clock: { now: () => 6_500 },
    logger: { warn: (_message, detail) => { diagnostics.push(detail); } },
  });
  const refreshFailed = new CustomChannelRuntime({
    storage: createMemoryStorage(null),
    clock: { now: () => 6_600 },
    generateId: createIdGenerator('refresh'),
    logger: { warn: (_message, detail) => { diagnostics.push(detail); } },
    onChannelsChanged: () => {
      throw new Error('refresh failed token=secret');
    },
  });

  const writeResult = await writeFailed.saveDraft('custom-write-failed', draft());
  const refreshResult = await refreshFailed.saveDraft('custom-refresh-failed', draft());

  assert.equal(writeResult.ok, false);
  assert.equal(writeResult.ok ? null : writeResult.error.code, 'CUSTOM_CHANNEL_STORAGE_UNAVAILABLE');
  assert.equal(containsCustomChannelForbiddenRendererField(writeResult), false);
  assert.equal(refreshResult.ok, true);
  assert.equal(refreshResult.ok ? refreshResult.value.snapshot.channels[0]?.id : null, 'refresh-1');
  assert.equal(containsCustomChannelForbiddenRendererField(refreshResult), false);
  assert.doesNotMatch(JSON.stringify(writeResult), /EACCES|Users|channels\.json|token|secret/u);
  assert.doesNotMatch(JSON.stringify(refreshResult), /token|secret/u);
  assert.doesNotMatch(JSON.stringify(diagnostics), /EACCES|Users|channels\.json|token|secret/u);
  assert.match(JSON.stringify(diagnostics), /refresh-1/u);
});

test('custom channel runtime reports storage failures without leaking details', async () => {
  const runtime = new CustomChannelRuntime({
    storage: {
      ...createMemoryStorage(null),
      readStoredChannelData: async () => {
        throw new Error('EACCES /Users/private/channels.json token=secret');
      },
      writeStoredChannelData: async () => undefined,
      clearStoredChannelData: async () => undefined,
      readCurrentChannelId: async () => null,
      writeCurrentChannelId: async () => undefined,
    },
    clock: { now: () => 7_000 },
  });

  const result = await runtime.getSnapshot('custom-storage-failed');

  assert.equal(result.ok, false);
  assert.equal(result.ok ? null : result.error.code, 'CUSTOM_CHANNEL_STORAGE_UNAVAILABLE');
  assert.equal(containsCustomChannelForbiddenRendererField(result), false);
  assert.doesNotMatch(JSON.stringify(result), /EACCES|Users|channels\.json|token|secret/u);
});

function draft(overrides: Partial<CustomChannelDraftInput> = {}): CustomChannelDraftInput {
  return {
    number: 10,
    name: 'Custom Movies',
    hidden: false,
    playbackMode: 'sequential',
    content: [{
      type: 'manualItem',
      ratingKey: 'movie-1',
      title: 'Movie One',
      durationMs: 90_000,
      mediaType: 'movie',
    }],
    ...overrides,
  };
}

function createMemoryStorage(initial: StoredChannelData | null): ChannelPersistenceStoragePort {
  let data = initial === null ? null : encodeStoredChannelData(initial);
  let currentChannelId = initial?.currentChannelId ?? null;
  let revision = 0;
  return {
    readStoredChannelData: async () => data,
    writeStoredChannelData: async (encoded) => {
      data = encoded;
      currentChannelId = JSON.parse(encoded).currentChannelId as string | null;
    },
    clearStoredChannelData: async () => {
      data = null;
      currentChannelId = null;
    },
    readCurrentChannelId: async () => currentChannelId,
    writeCurrentChannelId: async (channelId) => {
      currentChannelId = channelId;
    },
    readChannelAggregate: async () => ({
      storedChannelData: data === null ? null : JSON.parse(data) as StoredChannelData,
      currentChannelId,
      lineupRevision: revision,
      channelBuilderState: null,
    }),
    mutateChannelAggregate: async (request) => {
      if (request.kind === 'builder-lineup' && request.expectedLineupRevision !== revision) {
        return { status: 'conflict', actualLineupRevision: revision };
      }
      if (request.onCommitBarrier() === 'cancel') return { status: 'canceled' };
      const next = request.mutate({
        storedChannelData: data === null ? null : JSON.parse(data) as StoredChannelData,
        currentChannelId,
        lineupRevision: revision,
        channelBuilderState: null,
      });
      data = next.storedChannelData === null ? null : encodeStoredChannelData(next.storedChannelData);
      currentChannelId = next.currentChannelId;
      revision = next.lineupRevision;
      return { status: 'committed', aggregate: next };
    },
  };
}

function storedData(data: StoredChannelData): StoredChannelData {
  return data;
}

function channel(id: string, number: number, hidden = false): ChannelConfig {
  return {
    id,
    number,
    name: `Channel ${id}`,
    contentSource: {
      type: 'manual',
      items: [{ ratingKey: `manual-item-${id}`, title: `Item ${id}`, durationMs: 60_000 }],
    },
    playbackMode: 'sequential',
    startTimeAnchor: 1_000,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1_000,
    updatedAt: 1_000,
    lastContentRefresh: 0,
    itemCount: 1,
    totalDurationMs: 60_000,
    hidden,
  };
}

function createIdGenerator(prefix: string): () => string {
  let counter = 0;
  return () => `${prefix}-${++counter}`;
}
