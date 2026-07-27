import test from 'node:test';
import { setImmediate, setTimeout } from 'node:timers';
import assert from 'node:assert/strict';
import process from 'node:process';

import {
  createDefaultChannelSetupConfig,
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
  createSourceIdentity,
} from '../../domain/channelBuilder/index.js';
import type { ChannelAggregate } from '../../domain/channel/channelPersistenceStore.js';
import {
  ChannelBuilderOperationOwner,
  type ChannelBuilderReviewedPlanBody,
} from '../../main/channel/channelBuilderOperationOwner.js';
import {
  ChannelBuilderRuntime,
  type ChannelBuilderRuntimeOptions,
} from '../../main/channel/channelBuilderRuntime.js';
import { deferred } from '../helpers/deferred.js';

test('operation owner enforces one active operation and idempotent cancel lifecycle', () => {
  const ids = idSource();
  const owner = new ChannelBuilderOperationOwner({ randomHex128: ids });
  const handle = owner.start('review');
  assert.throws(() => owner.start('apply'), hasCode('CHANNEL_BUSY'));
  owner.markRunning(handle.operationId, 'discover-facets', { completed: 0, total: null });
  const firstCancel = owner.cancel(handle.operationId);
  const repeatedCancel = owner.cancel(handle.operationId);
  assert.equal(firstCancel?.accepted, true);
  assert.equal(firstCancel?.operation.state, 'canceling');
  assert.deepEqual(repeatedCancel, firstCancel);
  owner.markCanceled(handle.operationId);
  const terminalCancel = owner.cancel(handle.operationId);
  assert.equal(terminalCancel?.accepted, true);
  assert.equal(terminalCancel?.operation.state, 'canceled');

  const apply = owner.start('apply');
  assert.equal(owner.beginCommit(apply.operationId), 'proceed');
  const rejectedCancel = owner.cancel(apply.operationId);
  assert.equal(rejectedCancel?.accepted, false);
  assert.equal(rejectedCancel?.reason, 'commit-started');
  owner.markFailed(apply.operationId, {
    code: 'CHANNEL_UNKNOWN',
    message: 'Channel setup could not complete the request.',
    retryable: true,
    recoverable: true,
    operation: 'startApply',
  });
  assert.deepEqual(owner.cancel(apply.operationId)?.reason, 'already-terminal');
  owner.shutdown();
});

test('operation owner advances exact phase-local progress and rejects regression', () => {
  const owner = new ChannelBuilderOperationOwner({
    nowMs: () => 10,
    randomHex128: idSource(),
  });
  const review = owner.start('review');
  owner.markRunning(review.operationId, 'discover-facets', {
    completed: 2,
    total: null,
  });
  const discovery = owner.get(review.operationId);
  assert.deepEqual(discovery?.progress, { completed: 2, total: null });
  assert.equal(discovery?.updatedAtMs, 11);
  assert.throws(
    () => owner.markRunning(review.operationId, 'discover-facets', {
      completed: 1,
      total: null,
    }),
    /cannot move backward/u,
  );
  owner.markRunning(review.operationId, 'plan', { completed: 0, total: 1 });
  const planBefore = owner.get(review.operationId);
  owner.markRunning(review.operationId, 'plan', { completed: 1, total: 1 });
  const planAfter = owner.get(review.operationId);
  assert.equal(planAfter!.updatedAtMs > planBefore!.updatedAtMs, true);
  owner.markFailed(review.operationId, {
    code: 'CHANNEL_UNKNOWN',
    message: 'Channel setup could not complete the request.',
    retryable: true,
    recoverable: true,
    operation: 'startReview',
  });
  assert.deepEqual(owner.get(review.operationId)?.progress, {
    completed: 1,
    total: 1,
  });

  const apply = owner.start('apply', 3);
  assert.deepEqual(owner.get(apply.operationId)?.progress, {
    completed: 0,
    total: 3,
  });
  owner.markRunning(apply.operationId, 'materialize', { completed: 2, total: 3 });
  owner.markRunning(apply.operationId, 'persist', { completed: 0, total: 1 });
  owner.markRunning(apply.operationId, 'persist', { completed: 1, total: 1 });
  owner.markRunning(apply.operationId, 'refresh-guide', { completed: 0, total: 1 });
  owner.markRunning(apply.operationId, 'refresh-guide', { completed: 1, total: 1 });
  owner.markCanceled(apply.operationId);
  assert.deepEqual(owner.get(apply.operationId)?.progress, {
    completed: 1,
    total: 1,
  });
});

test('operation owner retains four plans, expires the oldest, and tracks consumption', () => {
  let nowMs = 1;
  const releasedPlanIds: string[] = [];
  const owner = new ChannelBuilderOperationOwner({
    nowMs: () => nowMs,
    randomHex128: idSource(),
    releasePlan: (planId) => releasedPlanIds.push(planId),
  });
  const bodies = Array.from({ length: 5 }, (_, index) =>
    reviewedBody(`channel-builder-plan-${(index + 1).toString(16).padStart(32, '0')}`),
  );
  for (const body of bodies) owner.retainPlan(body);
  assert.equal(owner.lookupPlan(bodies[0]!.planId).kind, 'expired');
  assert.equal(bodies[0]!.materializationIndex.materialize, disposedMaterialize);
  assert.deepEqual(releasedPlanIds, [bodies[0]!.planId]);
  const apply = owner.start('apply');
  const consumed = owner.consumePlan(bodies[1]!.planId, apply.operationId);
  assert.equal(consumed.planId, bodies[1]!.planId);
  assert.equal(owner.lookupPlan(bodies[1]!.planId).kind, 'consumed');
  owner.markCanceled(apply.operationId);

  nowMs += 10 * 60 * 1_000 + 1;
  assert.equal(owner.lookupPlan(bodies[2]!.planId).kind, 'expired');
  assert.deepEqual(releasedPlanIds, [
    bodies[0]!.planId,
    bodies[2]!.planId,
    bodies[3]!.planId,
    bodies[4]!.planId,
  ]);
  const shutdownBody = reviewedBody(
    `channel-builder-plan-${'6'.padStart(32, '0')}`,
  );
  owner.retainPlan(shutdownBody);
  owner.shutdown();
  assert.deepEqual(releasedPlanIds, [
    bodies[0]!.planId,
    bodies[2]!.planId,
    bodies[3]!.planId,
    bodies[4]!.planId,
    shutdownBody.planId,
  ]);
});

test('builder runtime releases every apply resource after early context and revision failures', async () => {
  for (const failure of ['context', 'revision'] as const) {
    let assertCalls = 0;
    let disposeCalls = 0;
    const releasedPlanIds: string[] = [];
    const base = reviewedBody(
      `channel-builder-plan-${failure === 'context' ? 'c' : 'd'}`.padEnd(53, failure === 'context' ? 'c' : 'd'),
    );
    const body: ChannelBuilderReviewedPlanBody = {
      ...base,
      normalizedConfig: { ...base.normalizedConfig, buildMode: 'append' },
      materializationIndex: {
        ...base.materializationIndex,
        dispose: () => {
          disposeCalls += 1;
        },
      },
    };
    const operationOwner = new ChannelBuilderOperationOwner({
      randomHex128: idSource(),
      releasePlan: (planId) => releasedPlanIds.push(planId),
    });
    operationOwner.retainPlan(body);
    const runtime = new ChannelBuilderRuntime({
      store: {
        readChannelAggregate: async () => ({
          storedChannelData: null,
          currentChannelId: null,
          lineupRevision: failure === 'revision' ? 1 : 0,
          channelBuilderState: null,
        }),
      },
      contextOwner: {
        capture: () => ({
          context: body.context,
          selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
        }),
        assertCurrent: () => {
          assertCalls += 1;
          if (failure === 'context' && assertCalls === 2) {
            throw new Error('stale context');
          }
        },
        retain: () => undefined,
        release: (planId: string) => releasedPlanIds.push(planId),
        shutdown: () => undefined,
      },
      facetSource: {},
      planningWorker: { shutdown: () => undefined },
      operationOwner,
      mutationCoordinator: {},
      refreshGuide: async () => undefined,
      randomHex128: () => 'a'.repeat(32),
    } as unknown as ChannelBuilderRuntimeOptions);

    const accepted = runtime.startApply(`request-${failure}`, {
      planId: body.planId,
      confirmReplace: false,
    });
    assert.equal(accepted.ok, true);
    if (!accepted.ok) continue;
    const operationId = accepted.value.operation.operationId;
    await waitFor(() => operationOwner.get(operationId)?.state === 'failed');

    assert.equal(operationOwner.hasActiveOperation(), false);
    assert.equal(disposeCalls, 1);
    assert.deepEqual(releasedPlanIds, [body.planId]);
    runtime.shutdown();
    assert.equal(disposeCalls, 1);
    assert.deepEqual(releasedPlanIds, [body.planId]);
  }
});

test('builder runtime shutdown settles a pending review read without unhandled rejection or late work', async () => {
  const read = deferred<ChannelAggregate>();
  const body = reviewedBody(`channel-builder-plan-${'8'.repeat(32)}`);
  let discoverCalls = 0;
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: idSource(),
  });
  const runtime = new ChannelBuilderRuntime({
    store: { readChannelAggregate: async () => read.promise },
    contextOwner: {
      capture: () => ({
        context: body.context,
        selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
      }),
      assertCurrent: () => undefined,
      retain: () => undefined,
      release: () => undefined,
      shutdown: () => undefined,
    },
    facetSource: {
      discover: async () => {
        discoverCalls += 1;
        throw new Error('Discovery must not start after shutdown.');
      },
    },
    planningWorker: { shutdown: () => undefined },
    operationOwner,
    mutationCoordinator: {},
    refreshGuide: async () => undefined,
    randomHex128: () => 'a'.repeat(32),
  } as unknown as ChannelBuilderRuntimeOptions);

  const unhandled = await captureUnhandledRejections(async () => {
    const accepted = runtime.startReview(
      'pending-review-shutdown',
      body.normalizedConfig,
    );
    assert.equal(accepted.ok, true);
    runtime.shutdown();

    const rejected = runtime.startReview(
      'review-after-shutdown',
      body.normalizedConfig,
    );
    assert.equal(rejected.ok, false);
    if (!rejected.ok) assert.equal(rejected.error.code, 'CHANNEL_BUSY');

    read.resolve({
      storedChannelData: null,
      currentChannelId: null,
      lineupRevision: 0,
      channelBuilderState: null,
    });
    await settleAsyncWork();
  });

  assert.deepEqual(unhandled, []);
  assert.equal(discoverCalls, 0);
  assert.equal(operationOwner.hasActiveOperation(), false);
});

test('builder runtime shutdown settles a pending apply read and releases consumed resources', async () => {
  const read = deferred<ChannelAggregate>();
  const base = readyAppendBody();
  let disposeCalls = 0;
  let mutationCalls = 0;
  const releasedPlanIds: string[] = [];
  const body: ChannelBuilderReviewedPlanBody = {
    ...base,
    materializationIndex: {
      ...base.materializationIndex,
      dispose: () => {
        disposeCalls += 1;
      },
    },
  };
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: idSource(),
  });
  operationOwner.retainPlan(body);
  const runtime = new ChannelBuilderRuntime({
    store: { readChannelAggregate: async () => read.promise },
    contextOwner: {
      capture: () => ({
        context: body.context,
        selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
      }),
      assertCurrent: () => undefined,
      retain: () => undefined,
      release: (planId: string) => releasedPlanIds.push(planId),
      shutdown: () => undefined,
    },
    facetSource: {},
    planningWorker: { shutdown: () => undefined },
    operationOwner,
    mutationCoordinator: {
      mutateBuilderLineup: async () => {
        mutationCalls += 1;
        throw new Error('Mutation must not start after shutdown.');
      },
    },
    refreshGuide: async () => undefined,
    randomHex128: () => 'a'.repeat(32),
  } as unknown as ChannelBuilderRuntimeOptions);

  const unhandled = await captureUnhandledRejections(async () => {
    const accepted = runtime.startApply('pending-apply-shutdown', {
      planId: body.planId,
      confirmReplace: false,
    });
    assert.equal(accepted.ok, true);
    runtime.shutdown();

    const rejected = runtime.startApply('apply-after-shutdown', {
      planId: body.planId,
      confirmReplace: false,
    });
    assert.equal(rejected.ok, false);
    if (!rejected.ok) assert.equal(rejected.error.code, 'CHANNEL_BUSY');

    read.resolve({
      storedChannelData: null,
      currentChannelId: null,
      lineupRevision: 0,
      channelBuilderState: null,
    });
    await settleAsyncWork();
  });

  assert.deepEqual(unhandled, []);
  assert.equal(mutationCalls, 0);
  assert.equal(disposeCalls, 1);
  assert.deepEqual(releasedPlanIds, [body.planId]);
  assert.equal(operationOwner.hasActiveOperation(), false);
  runtime.shutdown();
  assert.equal(disposeCalls, 1);
});

test('review context churn aborts worker planning and disposes its unretained index', async () => {
  const body = reviewedBody(`channel-builder-plan-${'7'.repeat(32)}`);
  let invalidate: (() => void) | null = null;
  let disposeCalls = 0;
  let workerAbortObserved = false;
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: idSource(),
  });
  const runtime = new ChannelBuilderRuntime({
    store: { readChannelAggregate: async () => hostileAggregate('existing') },
    contextOwner: {
      capture: () => ({
        context: body.context,
        selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
      }),
      assertCurrent: () => undefined,
      retain: (registration: { invalidate(): void }) => {
        invalidate = registration.invalidate;
      },
      release: () => undefined,
      shutdown: () => undefined,
    },
    facetSource: {
      discover: async () => ({
        kind: 'ready',
        snapshot: {
          context: body.context,
          libraries: [],
          playlists: [],
          collections: [],
          tags: [],
          recentlyAdded: [],
          aggregate: {
            status: 'ready',
            warningCodes: [],
            omittedMalformedCount: 0,
            omittedCappedCount: 0,
          },
        },
        materializationIndex: {
          ...body.materializationIndex,
          dispose: () => {
            disposeCalls += 1;
          },
        },
      }),
    },
    planningWorker: {
      plan: async (_input: unknown, signal: AbortSignal) =>
        await new Promise<never>((_resolve, reject) => {
          signal.addEventListener('abort', () => {
            workerAbortObserved = true;
            reject(new Error('aborted'));
          }, { once: true });
        }),
      shutdown: () => undefined,
    },
    operationOwner,
    mutationCoordinator: {},
    refreshGuide: async () => undefined,
    randomHex128: () => 'a'.repeat(32),
    nowMs: () => 100,
  } as unknown as ChannelBuilderRuntimeOptions);

  const accepted = runtime.startReview('review-context-churn', body.normalizedConfig);
  assert.equal(accepted.ok, true);
  if (!accepted.ok) return;
  await waitFor(() => invalidate !== null);
  invalidate!();
  await waitFor(
    () => operationOwner.get(accepted.value.operation.operationId)?.state === 'canceled',
  );
  assert.equal(workerAbortObserved, true);
  assert.equal(disposeCalls, 1);
  runtime.shutdown();
  assert.equal(disposeCalls, 1);
});

test('builder runtime applies an append plan through the aggregate barrier and refreshes guide', async () => {
  const before: ChannelAggregate = {
    storedChannelData: null,
    currentChannelId: null,
    lineupRevision: 0,
    channelBuilderState: null,
  };
  const committed: { value: ChannelAggregate | null } = { value: null };
  const latest = hostileAggregate('concurrent-channel');
  let refreshCalls = 0;
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: idSource(),
  });
  const body = readyAppendBody();
  operationOwner.retainPlan(body);
  const contextOwner = {
    capture: () => ({
      context: body.context,
      selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
    }),
    assertCurrent: () => undefined,
    retain: () => undefined,
    release: () => undefined,
    shutdown: () => undefined,
  };
  const runtime = new ChannelBuilderRuntime({
    store: {
      readChannelAggregate: async () => before,
    },
    contextOwner,
    facetSource: {},
    planningWorker: { shutdown: () => undefined },
    operationOwner,
    mutationCoordinator: {
      mutateBuilderLineup: async (input: {
        onCommitBarrier(): 'proceed' | 'cancel';
        mutate(current: Readonly<ChannelAggregate>): ChannelAggregate;
      }) => {
        assert.equal(input.onCommitBarrier(), 'proceed');
        committed.value = input.mutate(latest);
        return { status: 'committed', aggregate: committed.value };
      },
    },
    refreshGuide: async () => {
      refreshCalls += 1;
    },
    randomHex128: () => 'a'.repeat(32),
    nowMs: () => 100,
  } as unknown as ChannelBuilderRuntimeOptions);
  const accepted = runtime.startApply('request', {
    planId: body.planId,
    confirmReplace: false,
  });
  assert.equal(accepted.ok, true);
  if (!accepted.ok) return;
  const operationId = accepted.value.operation.operationId;
  await waitFor(() => operationOwner.get(operationId)?.state === 'succeeded');
  const terminal = operationOwner.get(operationId);
  assert.equal(terminal?.state, 'succeeded');
  if (terminal?.state !== 'succeeded') return;
  assert.equal(terminal.result.summary.created, 1);
  assert.equal(terminal.result.summary.watchChannelId, `channel-builder-${'a'.repeat(32)}`);
  assert.equal(committed.value?.lineupRevision, 0);
  assert.deepEqual(committed.value?.storedChannelData?.channelOrder, [
    'concurrent-channel',
    `channel-builder-${'a'.repeat(32)}`,
  ]);
  assert.equal(committed.value?.currentChannelId, 'concurrent-channel');
  assert.equal(refreshCalls, 1);
  runtime.shutdown();
});

test('builder apply bounds a never-settling post-commit guide refresh and releases the next review', async () => {
  const refresh = deferred<void>();
  let disposeCalls = 0;
  const releasedPlanIds: string[] = [];
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: idSource(),
  });
  const base = readyAppendBody();
  const body: ChannelBuilderReviewedPlanBody = {
    ...base,
    materializationIndex: {
      ...base.materializationIndex,
      dispose: () => {
        disposeCalls += 1;
      },
    },
  };
  operationOwner.retainPlan(body);
  const runtime = new ChannelBuilderRuntime({
    store: {
      readChannelAggregate: async () => ({
        storedChannelData: null,
        currentChannelId: null,
        lineupRevision: 0,
        channelBuilderState: null,
      }),
    },
    contextOwner: {
      capture: () => ({
        context: body.context,
        selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
      }),
      assertCurrent: () => undefined,
      retain: () => undefined,
      release: (planId: string) => releasedPlanIds.push(planId),
      shutdown: () => undefined,
    },
    facetSource: {},
    planningWorker: { shutdown: () => undefined },
    operationOwner,
    mutationCoordinator: {
      mutateBuilderLineup: async (input: {
        onCommitBarrier(): 'proceed' | 'cancel';
        mutate(current: Readonly<ChannelAggregate>): ChannelAggregate;
      }) => {
        assert.equal(input.onCommitBarrier(), 'proceed');
        const aggregate = input.mutate({
          storedChannelData: null,
          currentChannelId: null,
          lineupRevision: 0,
          channelBuilderState: null,
        });
        return { status: 'committed', aggregate };
      },
    },
    refreshGuide: async () => refresh.promise,
    guideRefreshDeadlineMs: 0,
    randomHex128: () => 'b'.repeat(32),
    nowMs: () => 100,
  } as unknown as ChannelBuilderRuntimeOptions);

  const accepted = runtime.startApply('apply-never-refreshes', {
    planId: body.planId,
    confirmReplace: false,
  });
  assert.equal(accepted.ok, true);
  if (!accepted.ok) return;
  const operationId = accepted.value.operation.operationId;
  await waitFor(() => operationOwner.get(operationId)?.state === 'succeeded');

  const terminal = operationOwner.get(operationId);
  assert.equal(terminal?.state, 'succeeded');
  if (terminal?.state !== 'succeeded') return;
  assert.equal(terminal.result.commit, 'committed');
  assert.equal(terminal.result.guideRefresh, 'failed');
  assert.equal(
    terminal.result.summary.warnings.some(
      (warning) =>
        warning.code === 'GUIDE_REFRESH_FAILED' && warning.phase === 'refresh',
    ),
    true,
  );
  assert.equal(operationOwner.hasActiveOperation(), false);
  assert.equal(disposeCalls, 1);
  assert.deepEqual(releasedPlanIds, [body.planId]);

  const nextReview = runtime.startReview(
    'review-after-refresh-timeout',
    body.normalizedConfig,
  );
  assert.equal(nextReview.ok, true);
  if (nextReview.ok) {
    await waitFor(
      () =>
        operationOwner.get(nextReview.value.operation.operationId)?.state ===
        'failed',
    );
  }
  runtime.shutdown();
  assert.equal(disposeCalls, 1);
});

test('review projection cannot inherit provenance for hostile channel ids', async () => {
  const body = reviewedBody(`channel-builder-plan-${'e'.repeat(32)}`);
  const projection: { value:
    | readonly Readonly<{ id: string; builderProvenance: unknown }>[]
    | null } = { value: null };
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: idSource(),
  });
  const runtime = new ChannelBuilderRuntime({
    store: {
      readChannelAggregate: async () => hostileAggregate('__proto__'),
    },
    contextOwner: {
      capture: () => ({
        context: body.context,
        selectedLibraryPairs: [{ libraryId: 'library', libraryUuid: 'uuid' }],
      }),
      assertCurrent: () => undefined,
      retain: () => undefined,
      release: () => undefined,
      shutdown: () => undefined,
    },
    facetSource: {
      discover: async () => ({
        kind: 'ready',
        snapshot: {
          context: body.context,
          libraries: [],
          playlists: [],
          collections: [],
          tags: [],
          recentlyAdded: [],
          aggregate: {
            status: 'ready',
            warningCodes: [],
            omittedMalformedCount: 0,
            omittedCappedCount: 0,
          },
        },
        materializationIndex: body.materializationIndex,
      }),
    },
    planningWorker: {
      plan: async (input: {
        existingLineup: readonly Readonly<{
          id: string;
          builderProvenance: unknown;
        }>[];
      }) => {
        projection.value = input.existingLineup;
        return blockedPlanOutput();
      },
      shutdown: () => undefined,
    },
    operationOwner,
    mutationCoordinator: {},
    refreshGuide: async () => undefined,
    randomHex128: () => 'a'.repeat(32),
    nowMs: () => 100,
  } as unknown as ChannelBuilderRuntimeOptions);

  const accepted = runtime.startReview('request', body.normalizedConfig);
  assert.equal(accepted.ok, true);
  if (!accepted.ok) return;
  await waitFor(
    () => operationOwner.get(accepted.value.operation.operationId)?.state === 'review-ready',
  );
  assert.deepEqual(projection.value?.map((entry) => ({
    id: entry.id,
    builderProvenance: entry.builderProvenance,
  })), [{ id: '__proto__', builderProvenance: null }]);
  runtime.shutdown();
});

function reviewedBody(planId: string): ChannelBuilderReviewedPlanBody {
  const config = createDefaultChannelSetupConfig({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  if (!config.ok) throw new Error('Operation fixture config failed.');
  const materializationIndex = {
    context: {
      contextEpoch: 1,
      profileBinding: createProfileBinding('profile'),
      serverBinding: createServerBinding('server'),
      librarySetBinding: createLibrarySetBinding([
        { libraryId: 'library', libraryUuid: 'uuid' },
      ]),
    },
    materialize: async () => ({
      status: 'failed' as const,
      candidateId: `candidate:${'1'.repeat(64)}` as const,
      reason: 'index-disposed' as const,
      error: {
        code: 'CHANNEL_PLAN_EXPIRED' as const,
        retryable: true,
      },
    }),
    dispose() {
      this.materialize = disposedMaterialize;
    },
  };
  return {
    planId,
    planIdentity: `plan-identity:${'1'.repeat(64)}`,
    status: 'ready',
    normalizedConfig: config.config,
    context: materializationIndex.context,
    lineupRevision: 0,
    candidateDrafts: [],
    applyCandidateIds: [],
    retainedMaterializationCandidateIds: [],
    candidateLedger: [],
    existingLedger: [],
    diff: {
      summary: { created: 0, removed: 0, unchanged: 0 },
      samples: { created: [], removed: [], unchanged: [] },
    },
    warnings: [],
    reachedCap: false,
    capacity: {
      requestedMaxChannels: 200,
      effectiveMaxChannels: 200,
      availableCreateSlots: 200,
    },
    materializationIndex,
  };
}

function readyAppendBody(): ChannelBuilderReviewedPlanBody {
  const base = reviewedBody(`channel-builder-plan-${'f'.repeat(32)}`);
  const source = {
    type: 'library' as const,
    libraryId: 'library',
    libraryType: 'movie' as const,
    includeWatched: true,
  };
  const sourceIdentity = createSourceIdentity(source);
  const candidateId = `candidate:${'2'.repeat(64)}` as const;
  const candidate = {
    candidateId,
    candidateIdentity: `candidate-identity:${'3'.repeat(64)}` as const,
    origin: {
      profileBinding: base.context.profileBinding,
      serverBinding: base.context.serverBinding,
      librarySetBinding: base.context.librarySetBinding,
    },
    strategy: 'collections' as const,
    displayName: 'Movies',
    sourceReference: { kind: 'facet' as const, facetId: null, sourceIdentity },
    estimatedItemCount: 10,
    playbackMode: 'shuffle' as const,
    shuffleSeed: 1,
    contentFilterPlan: { kind: 'none' as const, contentFilterIdentity: null },
    sortOrder: null,
    blockSize: null,
    buildStrategy: null,
    sourceLibraryId: 'library',
    sourceLibraryName: 'Movies',
    lineupReplicaIndex: null,
    isPlaybackModeVariant: null,
  };
  return {
    ...base,
    normalizedConfig: { ...base.normalizedConfig, buildMode: 'append' },
    candidateDrafts: [candidate],
    applyCandidateIds: [candidateId],
    candidateLedger: [
      {
        ordinal: 0,
        candidateId,
        strategy: 'collections',
        sourceIdentity,
        classification: 'new-apply',
        exclusion: null,
        retainedChannelId: null,
      },
    ],
    materializationIndex: {
      context: base.context,
      materialize: async () => ({
        status: 'ready',
        candidateId,
        createInput: {
          name: 'Movies',
          contentSource: source,
          playbackMode: 'shuffle',
          shuffleSeed: 1,
          sourceLibraryId: 'library',
          sourceLibraryName: 'Movies',
        },
      }),
      dispose: () => undefined,
    },
  };
}

function hostileAggregate(channelId: string): ChannelAggregate {
  return {
    storedChannelData: {
      channels: [{
        id: channelId,
        number: 1,
        name: 'Hostile',
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
      channelOrder: [channelId],
      currentChannelId: channelId,
      savedAt: 1,
    },
    currentChannelId: channelId,
    lineupRevision: 0,
    channelBuilderState: null,
  };
}

function blockedPlanOutput() {
  return {
    status: 'blocked' as const,
    planIdentity: `plan-identity:${'9'.repeat(64)}` as const,
    candidateDrafts: [],
    applyCandidateIds: [],
    retainedMaterializationCandidateIds: [],
    candidateLedger: [],
    existingLedger: [],
    diff: {
      summary: { created: 0, removed: 0, unchanged: 1 },
      samples: { created: [], removed: [], unchanged: [] },
    },
    warnings: [{
      code: 'PLAN_EMPTY' as const,
      phase: 'planning' as const,
      strategy: null,
      affectedCount: 0,
    }],
    reachedCap: false,
    capacity: {
      requestedMaxChannels: 200,
      effectiveMaxChannels: 200,
      availableCreateSlots: 200,
    },
  };
}

const disposedMaterialize = async () => ({
  status: 'failed' as const,
  candidateId: `candidate:${'1'.repeat(64)}` as const,
  reason: 'index-disposed' as const,
  error: { code: 'CHANNEL_PLAN_EXPIRED' as const, retryable: true },
});

function idSource(): () => string {
  let value = 0;
  return () => (++value).toString(16).padStart(32, '0');
}

function hasCode(code: string): (error: unknown) => boolean {
  return (error) =>
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === code;
}

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) return;
    await new Promise<void>((resolve) => setTimeout(resolve, 0));
  }
  assert.fail('Timed out waiting for builder operation.');
}

async function captureUnhandledRejections(
  run: () => Promise<void>,
): Promise<readonly unknown[]> {
  const unhandled: unknown[] = [];
  const listener = (error: unknown): void => {
    unhandled.push(error);
  };
  process.on('unhandledRejection', listener);
  try {
    await run();
    await settleAsyncWork();
    return unhandled;
  } finally {
    process.off('unhandledRejection', listener);
  }
}

async function settleAsyncWork(): Promise<void> {
  await new Promise<void>((resolve) => setImmediate(resolve));
  await new Promise<void>((resolve) => setImmediate(resolve));
}
