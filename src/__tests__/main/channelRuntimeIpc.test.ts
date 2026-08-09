import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL,
  LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
  LINEUP_GUIDE_CANCEL_PRESENTATION_CHANNEL,
} from '../../contracts/ipc.js';
import type {
  ChannelAggregate,
  ChannelAggregateMutationRequest,
  ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import { registerChannelIpcHandlers } from '../../main/channel/channelIpc.js';
import {
  ChannelPublicReferenceConsistencyError,
  ChannelPublicReferenceOwner,
} from '../../main/channel/channelPublicReferenceOwner.js';
import { GuidePresentationCurrentnessError } from '../../main/channel/guideRuntime.js';
import { ChannelRuntime } from '../../main/channel/channelRuntime.js';

test('ChannelRuntime status uses public references and exact builder metadata', async () => {
  const aggregate: ChannelAggregate = {
    storedChannelData: {
      channels: [{
        id: 'token-secret',
        number: 1,
        name: '',
        contentSource: {
          type: 'manual',
          items: [{ ratingKey: 'item', title: 'Item', durationMs: 1_000 }],
        },
        playbackMode: 'sequential',
        startTimeAnchor: 1,
        skipIntros: false,
        skipCredits: false,
        createdAt: 1,
        updatedAt: 1,
        lastContentRefresh: 1,
        itemCount: 1,
        totalDurationMs: 1_000,
      }],
      channelOrder: ['token-secret'],
      currentChannelId: 'token-secret',
      savedAt: 1,
    },
    currentChannelId: 'token-secret',
    lineupRevision: 3,
    channelBuilderState: null,
  };
  const runtime = new ChannelRuntime({
    storage: memoryStorage(aggregate),
    builderRuntime: {
      startReview: () => assert.fail('unexpected'),
      startApply: () => assert.fail('unexpected'),
      getOperation: () => assert.fail('unexpected'),
      cancel: () => assert.fail('unexpected'),
      shutdown: () => undefined,
    } as never,
    publicReferenceOwner: new ChannelPublicReferenceOwner(),
    clock: { now: () => 10 },
  });

  const result = await runtime.getStatus('request');
  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.equal(result.value.lineupRevision, 3);
  assert.equal(result.value.status, 'not-configured');
  assert.match(result.value.channels[0]?.id ?? '', /^legacy-channel-/u);
  assert.equal(result.value.channels[0]?.name, 'Untitled channel');
  assert.deepEqual(result.value.builder, {
    completion: 'unknown',
    normalizedConfig: null,
    completedAtMs: null,
  });
});

test('Guide presentation retries consistency failures but maps projection failures immediately', async () => {
  for (const scenario of ['consistency', 'projection'] as const) {
    const handlers = new Map<string, (event: never, payload: unknown) => Promise<unknown>>();
    let generationLoads = 0;
    let presentationLoads = 0;
    registerChannelIpcHandlers({
      runtime: {
        loadPublicReferenceGeneration: async () => {
          generationLoads += 1;
          return {
            lineupRevision: 1,
            channels: [],
            currentChannelId: null,
            fingerprint: 'same',
          };
        },
      } as never,
      guideRuntime: {
        isPreferenceScopeCurrent: () => true,
        getPagedPresentation: async () => {
          presentationLoads += 1;
          if (scenario === 'consistency') {
            throw new ChannelPublicReferenceConsistencyError();
          }
          throw new Error('genuine projection failure');
        },
      } as never,
      publicReferenceOwner: {} as never,
      isAuthorizedEvent: () => true,
      createRequestId: () => 'fallback',
      ipcMain: {
        handle: (channel, handler) => {
          handlers.set(channel, handler as never);
        },
        removeHandler: () => undefined,
      },
    });
    const result = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(
      undefined as never,
      {
        requestId: `guide-${scenario}`,
        payload: { startTimeMs: 0, durationMs: 60_000 },
      },
    ) as { ok: boolean; error: { code: string } };
    assert.equal(result.ok, false);
    assert.equal(
      result.error.code,
      scenario === 'consistency'
        ? 'GUIDE_PRESENTATION_STALE'
        : 'GUIDE_PRESENTATION_FAILED',
    );
    assert.equal(presentationLoads, scenario === 'consistency' ? 3 : 1);
    assert.equal(generationLoads, scenario === 'consistency' ? 3 : 1);
  }
});

test('Guide cancellation is sender-bound, aborts main-owned work, and settles safely', async () => {
  const handlers = new Map<string, (event: never, payload: unknown) => Promise<unknown> | unknown>();
  const sender = {};
  const otherSender = {};
  let signal: AbortSignal | undefined;
  const teardown = registerChannelIpcHandlers({
    runtime: {
      loadPublicReferenceGeneration: async () => ({
        lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'same',
      }),
    } as never,
    guideRuntime: {
      isPreferenceScopeCurrent: () => true,
      getPagedPresentation: async (input: { signal?: AbortSignal }) => {
        signal = input.signal;
        await new Promise<void>((_resolve, reject) => {
          input.signal?.addEventListener('abort', () => reject(new Error('private abort detail')), { once: true });
        });
        throw new Error('unreachable');
      },
    } as never,
    publicReferenceOwner: {} as never,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain: {
      handle: (channel, handler) => handlers.set(channel, handler as never),
      removeHandler: () => undefined,
    },
  });
  const request = { requestId: 'guide-cancel-owner', payload: { startTimeMs: 0, durationMs: 60_000 } };
  const pending = handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!({ sender } as never, request) as Promise<unknown>;
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(signal?.aborted, false);

  const unauthorized = await handlers.get(LINEUP_GUIDE_CANCEL_PRESENTATION_CHANNEL)!({ sender: otherSender } as never, {
    requestId: request.requestId, payload: {},
  }) as { ok: boolean; error: { code: string } };
  assert.equal(unauthorized.ok, false);
  assert.equal(unauthorized.error.code, 'GUIDE_UNAUTHORIZED');
  assert.equal(signal?.aborted, false);

  const cancelled = await handlers.get(LINEUP_GUIDE_CANCEL_PRESENTATION_CHANNEL)!({ sender } as never, {
    requestId: request.requestId, payload: {},
  }) as { ok: boolean; value: object };
  assert.deepEqual(cancelled, { ok: true, value: {}, requestId: request.requestId });
  assert.equal(signal?.aborted, true);
  const result = await pending as { ok: boolean; error: { code: string; message: string } };
  assert.equal(result.ok, false);
  assert.deepEqual(result.error, {
    code: 'GUIDE_PRESENTATION_CANCELLED', message: 'Guide refresh was cancelled.',
    retryable: true, recoverable: true, operation: 'getPresentation',
  });
  await teardown();
});

test('Guide cancellation rejects malformed payloads and unauthorized events without aborting work', async () => {
  const harness = createCancellationHarness();
  const pending = harness.get('guide-validation', harness.sender);
  await settleMicrotasks();

  const malformed = await harness.cancel('guide-validation', harness.sender, { extra: true });
  assert.equal(malformed.ok, false);
  assert.equal(malformed.error?.code, 'GUIDE_VALIDATION_FAILED');
  assert.equal(harness.signals[0]?.aborted, false);

  harness.authorized = false;
  const unauthorized = await harness.cancel('guide-validation', harness.sender);
  assert.equal(unauthorized.ok, false);
  assert.equal(unauthorized.error?.code, 'GUIDE_UNAUTHORIZED');
  assert.equal(harness.signals[0]?.aborted, false);

  harness.authorized = true;
  await harness.cancel('guide-validation', harness.sender);
  await pending;
  await harness.teardown();
});

test('Guide presentation aborts on sender destruction and channel IPC teardown', async () => {
  const destroyedHarness = createCancellationHarness();
  const destroyed = destroyedHarness.get('guide-destroyed', destroyedHarness.sender);
  await settleMicrotasks();
  destroyedHarness.sender.emitDestroyed();
  const destroyedResult = await destroyed;
  assert.equal(destroyedHarness.signals[0]?.aborted, true);
  assert.equal(destroyedResult.error?.code, 'GUIDE_PRESENTATION_CANCELLED');
  await destroyedHarness.teardown();

  const teardownHarness = createCancellationHarness();
  const tornDown = teardownHarness.get('guide-teardown', teardownHarness.sender);
  await settleMicrotasks();
  await teardownHarness.teardown();
  const teardownResult = await tornDown;
  assert.equal(teardownHarness.signals[0]?.aborted, true);
  assert.equal(teardownResult.error?.code, 'GUIDE_PRESENTATION_CANCELLED');
});

test('Guide presentation main timeout aborts owned work and returns the fixed settlement', async (t) => {
  let timeoutCallback: (() => void) | null = null;
  const originalSetTimeout = globalThis.setTimeout;
  const originalClearTimeout = globalThis.clearTimeout;
  globalThis.setTimeout = ((callback: () => void) => {
    timeoutCallback = callback;
    return 1 as never;
  }) as unknown as typeof globalThis.setTimeout;
  globalThis.clearTimeout = (() => undefined) as typeof globalThis.clearTimeout;
  t.after(() => {
    globalThis.setTimeout = originalSetTimeout;
    globalThis.clearTimeout = originalClearTimeout;
  });
  const harness = createCancellationHarness();
  const pending = harness.get('guide-timeout', harness.sender);
  await settleMicrotasks();
  assert.equal(harness.signals[0]?.aborted, false);
  assert.ok(timeoutCallback);

  (timeoutCallback as () => void)();

  const result = await pending;
  assert.equal(harness.signals[0]?.aborted, true);
  assert.deepEqual(result.error, {
    code: 'GUIDE_PRESENTATION_CANCELLED', message: 'Guide refresh was cancelled.',
    retryable: true, recoverable: true, operation: 'getPresentation',
  });
  await harness.teardown();
});

test('Guide cancel-settle-new same-id race retains cancellation custody for the replacement', async () => {
  const harness = createCancellationHarness();
  const first = harness.get('guide-reused', harness.sender);
  await settleMicrotasks();
  await harness.cancel('guide-reused', harness.sender);
  const second = harness.get('guide-reused', harness.sender);
  await settleMicrotasks();
  assert.equal(harness.signals.length, 2);
  assert.equal(harness.signals[0]?.aborted, true);
  assert.equal(harness.signals[1]?.aborted, false);
  await first;

  const replacementCancel = await harness.cancel('guide-reused', harness.sender);
  assert.equal(replacementCancel.ok, true);
  const secondResult = await second;
  assert.equal(harness.signals[1]?.aborted, true);
  assert.equal(secondResult.error?.code, 'GUIDE_PRESENTATION_CANCELLED');
  await harness.teardown();
});

test('Guide sustained cancellation keeps at most one non-aborted privileged request', async () => {
  const harness = createCancellationHarness();
  for (let index = 0; index < 20; index += 1) {
    const requestId = `guide-bounded-${String(index)}`;
    const pending = harness.get(requestId, harness.sender);
    await settleMicrotasks();
    assert.ok(harness.signals.filter((signal) => !signal.aborted).length <= 1);
    await harness.cancel(requestId, harness.sender);
    const result = await pending;
    assert.equal(result.error?.code, 'GUIDE_PRESENTATION_CANCELLED');
    assert.equal(harness.signals.filter((signal) => !signal.aborted).length, 0);
  }
  assert.equal(harness.signals.length, 20);
  await harness.teardown();
});

test('Guide presentation retries the Settings currentness sentinel independently', async () => {
  const handlers = new Map<string, (event: never, payload: unknown) => Promise<unknown>>();
  let presentationLoads = 0;
  registerChannelIpcHandlers({
    runtime: {
      loadPublicReferenceGeneration: async () => ({ lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'same' }),
    } as never,
    guideRuntime: {
      isPreferenceScopeCurrent: () => true,
      getPagedPresentation: async () => {
        presentationLoads += 1;
        if (presentationLoads < 3) throw new GuidePresentationCurrentnessError();
        return {
          channels: [],
          nowWatching: null,
          channelWindow: { offset: 0, total: 0 },
          libraryFilter: { scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
          minimumStartTimeMs: 0,
        };
      },
    } as never,
    publicReferenceOwner: {} as never,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain: {
      handle: (channel, handler) => { handlers.set(channel, handler as never); },
      removeHandler: () => undefined,
    },
  });
  const result = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(
    undefined as never,
    { requestId: 'guide-settings-currentness', payload: { startTimeMs: 0, durationMs: 60_000 } },
  ) as { ok: boolean };
  assert.equal(result.ok, true);
  assert.equal(presentationLoads, 3);
});

test('Guide presentation exhausts the Settings currentness retry budget as stale', async () => {
  const handlers = new Map<string, (event: never, payload: unknown) => Promise<unknown>>();
  let presentationLoads = 0;
  registerChannelIpcHandlers({
    runtime: {
      loadPublicReferenceGeneration: async () => ({ lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'same' }),
    } as never,
    guideRuntime: {
      isPreferenceScopeCurrent: () => true,
      getPagedPresentation: async () => {
        presentationLoads += 1;
        throw new GuidePresentationCurrentnessError();
      },
    } as never,
    publicReferenceOwner: {} as never,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain: {
      handle: (channel, handler) => { handlers.set(channel, handler as never); },
      removeHandler: () => undefined,
    },
  });
  const result = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(
    undefined as never,
    { requestId: 'guide-settings-currentness-exhausted', payload: { startTimeMs: 0, durationMs: 60_000 } },
  ) as { ok: boolean; error: { code: string } };
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'GUIDE_PRESENTATION_STALE');
  assert.equal(presentationLoads, 3);
});

test('Guide presentation retries a public-reference consistency failure independently before success', async () => {
  const handlers = new Map<string, (event: never, payload: unknown) => Promise<unknown>>();
  let presentationLoads = 0;
  registerChannelIpcHandlers({
    runtime: {
      loadPublicReferenceGeneration: async () => ({ lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'same' }),
    } as never,
    guideRuntime: {
      isPreferenceScopeCurrent: () => true,
      getPagedPresentation: async () => {
        presentationLoads += 1;
        if (presentationLoads === 1) throw new ChannelPublicReferenceConsistencyError();
        return {
          channels: [],
          nowWatching: null,
          channelWindow: { offset: 0, total: 0 },
          libraryFilter: { scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
          minimumStartTimeMs: 0,
        };
      },
    } as never,
    publicReferenceOwner: {} as never,
    isAuthorizedEvent: () => true,
    createRequestId: () => 'fallback',
    ipcMain: {
      handle: (channel, handler) => { handlers.set(channel, handler as never); },
      removeHandler: () => undefined,
    },
  });
  const result = await handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!(
    undefined as never,
    { requestId: 'guide-reference-retry-success', payload: { startTimeMs: 0, durationMs: 60_000 } },
  ) as { ok: boolean };
  assert.equal(result.ok, true);
  assert.equal(presentationLoads, 2);
});

test('channel IPC registers and removes exactly the five setup handlers', async () => {
  const handlers = new Map<string, (event: never, payload: unknown) => unknown>();
  const removed: string[] = [];
  const teardown = registerChannelIpcHandlers({
    runtime: {
      getStatus: async () => ({ ok: false, requestId: 'x', error: {} }),
      startReview: () => ({ ok: false, requestId: 'x', error: {} }),
      startApply: () => ({ ok: false, requestId: 'x', error: {} }),
      getOperation: () => ({ ok: false, requestId: 'x', error: {} }),
      cancel: () => ({ ok: false, requestId: 'x', error: {} }),
    } as never,
    isAuthorizedEvent: () => true,
    createRequestId: (prefix) => `${prefix}-request`,
    ipcMain: {
      handle: (channel, handler) => {
        handlers.set(channel, handler as never);
      },
      removeHandler: (channel) => {
        removed.push(channel);
      },
    },
  });
  const expected = [
    LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
    LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL,
    LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL,
    LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL,
    LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL,
  ];
  assert.deepEqual([...handlers.keys()], expected);
  await teardown();
  assert.deepEqual(removed, expected);
});

type GuideCancellationResult = {
  ok: boolean;
  error?: { code: string; message: string; retryable: boolean; recoverable: boolean; operation: string };
};

class FakeGuideSender {
  private readonly destroyedListeners = new Set<() => void>();

  once(event: string, listener: () => void): void {
    if (event === 'destroyed') this.destroyedListeners.add(listener);
  }

  removeListener(event: string, listener: () => void): void {
    if (event === 'destroyed') this.destroyedListeners.delete(listener);
  }

  emitDestroyed(): void {
    const listeners = [...this.destroyedListeners];
    this.destroyedListeners.clear();
    listeners.forEach((listener) => listener());
  }
}

type GuideCancellationHarness = {
  sender: FakeGuideSender;
  signals: AbortSignal[];
  authorized: boolean;
  get(requestId: string, sender: FakeGuideSender): Promise<GuideCancellationResult>;
  cancel(requestId: string, sender: FakeGuideSender, payload?: Record<string, unknown>): Promise<GuideCancellationResult>;
  teardown(): Promise<void>;
};

function createCancellationHarness(): GuideCancellationHarness {
  const handlers = new Map<string, (event: never, payload: unknown) => Promise<unknown> | unknown>();
  const sender = new FakeGuideSender();
  const signals: AbortSignal[] = [];
  const harness: GuideCancellationHarness = {
    sender,
    signals,
    authorized: true,
    get(requestId: string, requestSender: FakeGuideSender) {
      return handlers.get(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL)!({ sender: requestSender } as never, {
        requestId, payload: { startTimeMs: 0, durationMs: 60_000 },
      }) as Promise<GuideCancellationResult>;
    },
    async cancel(
      requestId: string,
      requestSender: FakeGuideSender,
      payload: Record<string, unknown> = {},
    ) {
      return await handlers.get(LINEUP_GUIDE_CANCEL_PRESENTATION_CHANNEL)!({ sender: requestSender } as never, {
        requestId, payload,
      }) as GuideCancellationResult;
    },
    teardown: async () => undefined,
  };
  const teardown = registerChannelIpcHandlers({
    runtime: {
      loadPublicReferenceGeneration: async () => ({
        lineupRevision: 1, channels: [], currentChannelId: null, fingerprint: 'same',
      }),
    } as never,
    guideRuntime: {
      isPreferenceScopeCurrent: () => true,
      getPagedPresentation: async ({ signal }: { signal: AbortSignal }) => {
        signals.push(signal);
        await new Promise<void>((_resolve, reject) => {
          signal.addEventListener('abort', () => reject(new Error('private abort detail')), { once: true });
        });
        throw new Error('unreachable');
      },
    } as never,
    publicReferenceOwner: {} as never,
    isAuthorizedEvent: () => harness.authorized,
    createRequestId: () => 'fallback',
    ipcMain: {
      handle: (channel, handler) => handlers.set(channel, handler as never),
      removeHandler: () => undefined,
    },
  });
  harness.teardown = teardown;
  return harness;
}

async function settleMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

function memoryStorage(initial: ChannelAggregate): ChannelPersistenceStoragePort {
  let aggregate = initial;
  return {
    readStoredChannelData: async () =>
      aggregate.storedChannelData === null ? null : JSON.stringify(aggregate.storedChannelData),
    writeStoredChannelData: async () => undefined,
    clearStoredChannelData: async () => undefined,
    readCurrentChannelId: async () => aggregate.currentChannelId,
    writeCurrentChannelId: async () => undefined,
    readChannelAggregate: async () => aggregate,
    mutateChannelAggregate: async (request: ChannelAggregateMutationRequest) => {
      if (
        request.kind === 'builder-lineup' &&
        request.expectedLineupRevision !== aggregate.lineupRevision
      ) {
        return { status: 'conflict', actualLineupRevision: aggregate.lineupRevision };
      }
      if (request.onCommitBarrier() === 'cancel') return { status: 'canceled' };
      aggregate = request.mutate(aggregate);
      return { status: 'committed', aggregate };
    },
  };
}
