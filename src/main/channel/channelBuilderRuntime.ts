import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupAcceptedOperation,
  type ChannelSetupApplySummary,
  type ChannelSetupCancelResult,
  type ChannelSetupIpcResult,
  type ChannelSetupOperationResult,
  type ChannelSetupRuntimeError,
  type NormalizedChannelSetupConfig,
} from '../../contracts/channel.js';
import { ChannelAuthoringService } from '../../domain/channel/channelAuthoringService.js';
import { cloneChannelForOwnership } from '../../domain/channel/channelDomainClone.js';
import type { ChannelAggregate, ChannelPersistenceStore } from '../../domain/channel/channelPersistenceStore.js';
import type { ChannelConfig, ChannelContentSource, ChannelCreateInput, ChannelUpdateInput } from '../../domain/channel/types.js';
import {
  CHANNEL_BUILDER_STRATEGY_KEYS,
  createContentFilterIdentity,
  createSourceIdentity,
  type ChannelBuilderExistingLineupEntry,
  type ChannelBuilderChannelProvenanceV1,
  type ChannelBuilderSafeSourceReference,
} from '../../domain/channelBuilder/index.js';
import type { DesktopPlexChannelBuilderFacetSource } from '../plex/desktopPlexChannelBuilderFacetSource.js';
import type { ChannelBuilderContextEpochOwner } from './channelBuilderContextEpochOwner.js';
import type {
  ChannelBuilderOperationOwner,
  ChannelBuilderReviewedPlanBody,
} from './channelBuilderOperationOwner.js';
import type { ChannelBuilderPlanningWorker } from './channelBuilderPlanningWorker.js';
import type { ChannelLineupMutationCoordinator } from './channelLineupMutationCoordinator.js';

const REVIEW_DEADLINE_MS = 20_000;
const GUIDE_REFRESH_DEADLINE_MS = 30_000;

export type ChannelBuilderRuntimeOptions = Readonly<{
  store: ChannelPersistenceStore;
  contextOwner: ChannelBuilderContextEpochOwner;
  facetSource: DesktopPlexChannelBuilderFacetSource;
  planningWorker: ChannelBuilderPlanningWorker;
  operationOwner: ChannelBuilderOperationOwner;
  mutationCoordinator: ChannelLineupMutationCoordinator;
  refreshGuide(): Promise<void>;
  randomHex128(): string;
  nowMs?: () => number;
  guideRefreshDeadlineMs?: number;
}>;

export class ChannelBuilderRuntime {
  private readonly store: ChannelPersistenceStore;
  private readonly contextOwner: ChannelBuilderContextEpochOwner;
  private readonly facetSource: DesktopPlexChannelBuilderFacetSource;
  private readonly planningWorker: ChannelBuilderPlanningWorker;
  private readonly operationOwner: ChannelBuilderOperationOwner;
  private readonly mutationCoordinator: ChannelLineupMutationCoordinator;
  private readonly refreshGuide: () => Promise<void>;
  private readonly randomHex128: () => string;
  private readonly nowMs: () => number;
  private readonly guideRefreshDeadlineMs: number;
  private readonly activeApplyByPlan = new Map<string, string>();
  private closed = false;

  constructor(options: ChannelBuilderRuntimeOptions) {
    this.store = options.store;
    this.contextOwner = options.contextOwner;
    this.facetSource = options.facetSource;
    this.planningWorker = options.planningWorker;
    this.operationOwner = options.operationOwner;
    this.mutationCoordinator = options.mutationCoordinator;
    this.refreshGuide = options.refreshGuide;
    this.randomHex128 = options.randomHex128;
    this.nowMs = options.nowMs ?? Date.now;
    this.guideRefreshDeadlineMs =
      options.guideRefreshDeadlineMs ?? GUIDE_REFRESH_DEADLINE_MS;
  }

  startReview(
    requestId: string,
    config: NormalizedChannelSetupConfig,
  ): ChannelSetupIpcResult<ChannelSetupAcceptedOperation> {
    if (this.closed || this.operationOwner.hasActiveOperation()) {
      return channelSetupFailure(requestId, activeOperationError('startReview'));
    }
    let selected;
    try {
      selected = this.contextOwner.capture(config.selectedLibraryIds);
    } catch {
      return channelSetupFailure(requestId, contextError('startReview'));
    }
    let handle;
    try {
      handle = this.operationOwner.start('review');
    } catch {
      return channelSetupFailure(requestId, activeOperationError('startReview'));
    }
    const operation = this.operationOwner.get(handle.operationId);
    if (operation === null) {
      return channelSetupFailure(requestId, unknownError('startReview'));
    }
    void this.runReview(handle.operationId, handle.signal, config, selected).catch(() => {
      if (this.closed) return;
      const current = this.operationOwner.get(handle.operationId);
      if (current === null) return;
      if (current.state === 'canceling') {
        this.operationOwner.markCanceled(handle.operationId);
      } else {
        this.operationOwner.markFailed(handle.operationId, unknownError('startReview'));
      }
    });
    return channelSetupSuccess(requestId, { accepted: true, operation });
  }

  getOperation(
    requestId: string,
    operationId: string,
  ): ChannelSetupIpcResult<ChannelSetupOperationResult> {
    const operation = this.operationOwner.get(operationId);
    if (operation !== null) return channelSetupSuccess(requestId, { operation });
    return channelSetupFailure(
      requestId,
      this.operationOwner.isOperationExpired(operationId)
        ? operationExpiredError('getOperation')
        : operationMissingError('getOperation'),
    );
  }

  startApply(
    requestId: string,
    input: Readonly<{ planId: string; confirmReplace: boolean }>,
  ): ChannelSetupIpcResult<ChannelSetupAcceptedOperation> {
    if (this.closed || this.operationOwner.hasActiveOperation()) {
      return channelSetupFailure(requestId, activeOperationError('startApply'));
    }
    const lookup = this.operationOwner.lookupPlan(input.planId);
    if (lookup.kind !== 'available') {
      return channelSetupFailure(requestId, planLookupError(lookup.kind));
    }
    const body = lookup.body;
    if (this.operationOwner.hasConsumedPlanCapacity()) {
      return channelSetupFailure(requestId, consumedCapacityError());
    }
    if (
      (body.normalizedConfig.buildMode === 'replace') !== input.confirmReplace
    ) {
      return channelSetupFailure(requestId, replaceConfirmationError());
    }
    try {
      this.contextOwner.assertCurrent(
        body.context,
        body.normalizedConfig.selectedLibraryIds.map((libraryId) => {
          const captured = this.contextOwner.capture([libraryId]);
          return captured.selectedLibraryPairs[0]!;
        }),
      );
    } catch {
      return channelSetupFailure(requestId, contextError('startApply'));
    }
    let handle;
    try {
      handle = this.operationOwner.start(
        'apply',
        body.applyCandidateIds.length +
          body.retainedMaterializationCandidateIds.length,
      );
    } catch {
      return channelSetupFailure(requestId, activeOperationError('startApply'));
    }
    this.operationOwner.consumePlan(input.planId, handle.operationId);
    this.activeApplyByPlan.set(input.planId, handle.operationId);
    const operation = this.operationOwner.get(handle.operationId);
    if (operation === null) {
      return channelSetupFailure(requestId, unknownError('startApply'));
    }
    void this.runApply(handle.operationId, handle.signal, body).catch((error: unknown) => {
      if (this.closed) return;
      const current = this.operationOwner.get(handle.operationId);
      if (current === null) return;
      if (current.state === 'canceling') {
        this.operationOwner.markCanceled(handle.operationId);
      } else {
        this.operationOwner.markFailed(
          handle.operationId,
          isChannelSetupRuntimeError(error) ? error : applyRejectionError(),
        );
      }
    });
    return channelSetupSuccess(requestId, { accepted: true, operation });
  }

  cancel(
    requestId: string,
    operationId: string,
  ): ChannelSetupIpcResult<ChannelSetupCancelResult> {
    const result = this.operationOwner.cancel(operationId);
    if (result !== null) return channelSetupSuccess(requestId, result);
    return channelSetupFailure(
      requestId,
      this.operationOwner.isOperationExpired(operationId)
        ? operationExpiredError('cancel')
        : operationMissingError('cancel'),
    );
  }

  shutdown(): void {
    if (this.closed) return;
    this.closed = true;
    this.operationOwner.shutdown();
    this.planningWorker.shutdown();
    this.contextOwner.shutdown();
  }

  private async runReview(
    operationId: string,
    signal: AbortSignal,
    config: NormalizedChannelSetupConfig,
    selected: ReturnType<ChannelBuilderContextEpochOwner['capture']>,
  ): Promise<void> {
    let materializationIndex:
      | ChannelBuilderReviewedPlanBody['materializationIndex']
      | null = null;
    let temporaryContextRetained = false;
    try {
      this.operationOwner.markRunning(operationId, 'discover-facets', {
        completed: 0,
        total: null,
      });
      const aggregate = await this.store.readChannelAggregate();
      if (this.closed) return;
      this.contextOwner.assertCurrent(selected.context, selected.selectedLibraryPairs);
      const discovered = await this.facetSource.discover({
        normalizedConfig: config,
        context: selected.context,
        deadlineAtMs: this.nowMs() + REVIEW_DEADLINE_MS,
        signal,
      });
      if (this.closed) {
        discovered.materializationIndex?.dispose();
        return;
      }
      if (signal.aborted || discovered.kind === 'canceled') {
        this.operationOwner.markCanceled(operationId);
        return;
      }
      if (discovered.kind === 'failed') {
        this.operationOwner.markFailed(
          operationId,
          discoveryError(discovered.error.code),
        );
        return;
      }
      if (discovered.materializationIndex === null || discovered.snapshot === null) {
        this.operationOwner.markFailed(operationId, unknownError('startReview'));
        return;
      }
      materializationIndex = discovered.materializationIndex;
      this.contextOwner.assertCurrent(selected.context, selected.selectedLibraryPairs);
      this.contextOwner.retain({
        planId: operationId,
        context: selected.context,
        selectedLibraryPairs: selected.selectedLibraryPairs,
        invalidate: () => {
          this.operationOwner.cancel(operationId);
        },
      });
      temporaryContextRetained = true;
      this.operationOwner.markRunning(operationId, 'plan', {
        completed: 0,
        total: 1,
      });
      const output = await this.planningWorker.plan(
        {
          normalizedConfig: config,
          facetSnapshot: discovered.snapshot,
          existingLineup: projectExistingLineup(aggregate, selected.context),
          clock: { nowMs: this.nowMs() },
          seed: operationId,
        },
        signal,
      );
      if (this.closed) return;
      this.operationOwner.markRunning(operationId, 'plan', {
        completed: 1,
        total: 1,
      });
      if (signal.aborted) {
        this.operationOwner.markCanceled(operationId);
        return;
      }
      this.contextOwner.assertCurrent(selected.context, selected.selectedLibraryPairs);
      this.contextOwner.release(operationId);
      temporaryContextRetained = false;
      if (output.status === 'blocked') {
        this.operationOwner.markReviewReady(operationId, {
          kind: 'review',
          planId: null,
          contextEpoch: selected.context.contextEpoch,
          lineupRevision: aggregate.lineupRevision,
          status: 'blocked',
          diff: output.diff,
          warnings: output.warnings,
          reachedCap: output.reachedCap,
        });
        return;
      }
      const planId = this.operationOwner.issuePlanId();
      const body: ChannelBuilderReviewedPlanBody = {
      planId,
      planIdentity: output.planIdentity,
      status: output.status,
      normalizedConfig: config,
      context: selected.context,
      lineupRevision: aggregate.lineupRevision,
      candidateDrafts: output.candidateDrafts,
      applyCandidateIds: output.applyCandidateIds,
      retainedMaterializationCandidateIds: output.retainedMaterializationCandidateIds,
      candidateLedger: output.candidateLedger,
      existingLedger: output.existingLedger,
      diff: output.diff,
      warnings: output.warnings,
      reachedCap: output.reachedCap,
      capacity: output.capacity,
        materializationIndex,
      };
      this.operationOwner.retainPlan(body);
      materializationIndex = null;
      try {
        this.contextOwner.retain({
          planId,
          context: selected.context,
          selectedLibraryPairs: selected.selectedLibraryPairs,
          invalidate: () => {
            this.operationOwner.invalidatePlan(planId);
            const activeApplyId = this.activeApplyByPlan.get(planId);
            if (activeApplyId !== undefined) this.operationOwner.cancel(activeApplyId);
          },
        });
        this.operationOwner.markReviewReady(operationId, {
          kind: 'review',
          planId,
          contextEpoch: selected.context.contextEpoch,
          lineupRevision: aggregate.lineupRevision,
          status: output.status,
          diff: output.diff,
          warnings: output.warnings,
          reachedCap: output.reachedCap,
        });
      } catch (error) {
        this.contextOwner.release(planId);
        this.operationOwner.invalidatePlan(planId);
        throw error;
      }
    } finally {
      if (temporaryContextRetained) this.contextOwner.release(operationId);
      materializationIndex?.dispose();
    }
  }

  private async runApply(
    operationId: string,
    signal: AbortSignal,
    body: ChannelBuilderReviewedPlanBody,
  ): Promise<void> {
    try {
      this.assertPlanContext(body);
      const before = await this.store.readChannelAggregate();
      if (this.closed) return;
      if (signal.aborted) {
        this.operationOwner.markCanceled(operationId);
        return;
      }
      if (before.lineupRevision !== body.lineupRevision) {
        this.operationOwner.markFailed(operationId, lineupConflictError());
        return;
      }
      this.operationOwner.markRunning(operationId, 'materialize', {
        completed: 0,
        total:
          body.applyCandidateIds.length + body.retainedMaterializationCandidateIds.length,
      });
      const requested = new Set([
        ...body.applyCandidateIds,
        ...body.retainedMaterializationCandidateIds,
      ]);
      const candidates = new Map(body.candidateDrafts.map((candidate) => [candidate.candidateId, candidate]));
      const ready = new Map<string, ChannelCreateInput>();
      const skipped = new Set<string>();
      let completed = 0;
      for (const ledger of body.candidateLedger) {
        if (!requested.has(ledger.candidateId)) continue;
        if (signal.aborted) {
          this.operationOwner.markCanceled(operationId);
          return;
        }
        const candidate = candidates.get(ledger.candidateId);
        if (candidate === undefined) throw materializationInvalidError();
        const result = await body.materializationIndex.materialize({
          candidate,
          expectedContext: body.context,
          signal,
        });
        if (this.closed) return;
        if (signal.aborted) {
          this.operationOwner.markCanceled(operationId);
          return;
        }
        completed += 1;
        this.operationOwner.markRunning(operationId, 'materialize', {
          completed,
          total: requested.size,
        });
        if (result.status === 'ready' && result.candidateId === ledger.candidateId) {
          ready.set(ledger.candidateId, result.createInput);
          continue;
        }
        if (
          result.status === 'skipped' &&
          ledger.classification === 'new-apply'
        ) {
          skipped.add(ledger.candidateId);
          continue;
        }
        if (result.status === 'canceled') {
          this.operationOwner.markCanceled(operationId);
          return;
        }
        throw materializationOutcomeError(result);
      }
      if (body.normalizedConfig.buildMode === 'replace' && ready.size === 0) {
        this.operationOwner.markFailed(operationId, replacementEmptyError());
        return;
      }
      this.assertPlanContext(body);
      const applied: {
        value: ReturnType<typeof buildAppliedAggregate> | null;
      } = { value: null };
      this.operationOwner.markRunning(operationId, 'persist', {
        completed: 0,
        total: 1,
      });
      const mutation = await this.mutationCoordinator.mutateBuilderLineup({
        expectedLineupRevision: body.lineupRevision,
        mutate: (latest) => {
          applied.value = buildAppliedAggregate({
            before: latest,
            body,
            ready,
            skipped,
            nowMs: this.nowMs(),
            randomHex128: this.randomHex128,
          });
          return applied.value.aggregate;
        },
        onCommitBarrier: () => this.operationOwner.beginCommit(operationId),
      });
      if (this.closed) return;
      if (mutation.status === 'conflict') {
        this.operationOwner.markFailed(operationId, lineupConflictError());
        return;
      }
      if (mutation.status === 'canceled') {
        this.operationOwner.markCanceled(operationId);
        return;
      }
      if (applied.value === null) {
        throw new Error('Channel Builder aggregate mutation did not run.');
      }
      this.operationOwner.markRunning(operationId, 'persist', {
        completed: 1,
        total: 1,
      });
      this.operationOwner.markRunning(operationId, 'refresh-guide', {
        completed: 0,
        total: 1,
      });
      let guideRefresh: 'completed' | 'failed' = 'completed';
      if (
        !(await refreshGuideWithinDeadline(
          this.refreshGuide,
          this.guideRefreshDeadlineMs,
        ))
      ) {
        guideRefresh = 'failed';
      }
      if (this.closed) return;
      this.operationOwner.markRunning(operationId, 'refresh-guide', {
        completed: 1,
        total: 1,
      });
      this.operationOwner.markApplySucceeded(
        operationId,
        guideRefresh === 'failed'
          ? withGuideRefreshWarning(applied.value.summary)
          : applied.value.summary,
        guideRefresh,
      );
    } finally {
      this.activeApplyByPlan.delete(body.planId);
      try {
        this.contextOwner.release(body.planId);
      } finally {
        body.materializationIndex.dispose();
      }
    }
  }

  private assertPlanContext(body: ChannelBuilderReviewedPlanBody): void {
    const selected = this.contextOwner.capture(
      body.normalizedConfig.selectedLibraryIds,
    );
    this.contextOwner.assertCurrent(body.context, selected.selectedLibraryPairs);
  }
}

async function refreshGuideWithinDeadline(
  refreshGuide: () => Promise<void>,
  deadlineMs: number,
): Promise<boolean> {
  let timeout: ReturnType<typeof globalThis.setTimeout> | null = null;
  try {
    return await Promise.race([
      Promise.resolve()
        .then(refreshGuide)
        .then(
          () => true,
          () => false,
        ),
      new Promise<boolean>((resolve) => {
        timeout = globalThis.setTimeout(() => resolve(false), deadlineMs);
      }),
    ]);
  } finally {
    if (timeout !== null) globalThis.clearTimeout(timeout);
  }
}

function projectExistingLineup(
  aggregate: ChannelAggregate,
  context: ReturnType<ChannelBuilderContextEpochOwner['capture']>['context'],
): readonly ChannelBuilderExistingLineupEntry[] {
  const provenance = aggregate.channelBuilderState?.channelProvenance;
  return (aggregate.storedChannelData?.channels ?? []).map((channel) => {
    const common = {
      id: channel.id,
      number: channel.number,
      name: channel.name,
      playbackMode: channel.playbackMode,
      contentFilterIdentity: createContentFilterIdentity({
        profileBinding: context.profileBinding,
        serverBinding: context.serverBinding,
        filters: channel.contentFilters,
      }),
      ...(channel.sortOrder === undefined ? {} : { sortOrder: channel.sortOrder }),
      ...(channel.blockSize === undefined ? {} : { blockSize: channel.blockSize }),
      ...(channel.lineupReplicaIndex === undefined
        ? {}
        : { lineupReplicaIndex: channel.lineupReplicaIndex }),
      ...(channel.isPlaybackModeVariant === undefined
        ? {}
        : { isPlaybackModeVariant: channel.isPlaybackModeVariant }),
      ...(channel.isAutoGenerated === undefined
        ? {}
        : { isAutoGenerated: channel.isAutoGenerated }),
    };
    try {
      return {
        ...common,
        sourceDisposition: 'matchable' as const,
        sourceReference: projectSourceReference(channel.contentSource),
        builderProvenance:
          provenance !== undefined &&
          Object.prototype.hasOwnProperty.call(provenance, channel.id)
            ? provenance[channel.id] ?? null
            : null,
      };
    } catch {
      return {
        ...common,
        sourceDisposition: 'retained-unmatchable' as const,
        sourceReference: null,
        builderProvenance: null,
      };
    }
  });
}

function projectSourceReference(source: ChannelContentSource): ChannelBuilderSafeSourceReference {
  const sourceIdentity = createSourceIdentity(source);
  if (source.type === 'mixed') {
    return {
      kind: 'mixed',
      sourceIdentity,
      mixMode: source.mixMode,
      sources: source.sources.map(projectSourceReference),
    };
  }
  if (source.type === 'manual') {
    return {
      kind: 'manual',
      sourceIdentity,
      items: source.items.map((item) => ({
        kind: 'facet',
        facetId: null,
        sourceIdentity: createSourceIdentity({ type: 'manual', items: [item] }),
      })),
    };
  }
  return { kind: 'facet', facetId: null, sourceIdentity };
}

function buildAppliedAggregate(input: Readonly<{
  before: ChannelAggregate;
  body: ChannelBuilderReviewedPlanBody;
  ready: ReadonlyMap<string, ChannelCreateInput>;
  skipped: ReadonlySet<string>;
  nowMs: number;
  randomHex128(): string;
}>): Readonly<{ aggregate: ChannelAggregate; summary: ChannelSetupApplySummary }> {
  const beforeChannels = input.before.storedChannelData?.channels ?? [];
  const beforeIds = new Set(beforeChannels.map((channel) => channel.id));
  const occupiedIds = new Set(beforeIds);
  const allocatedIds = new Map<string, string>();
  for (const ledger of input.body.candidateLedger) {
    if (ledger.classification !== 'new-apply' || !input.ready.has(ledger.candidateId)) continue;
    allocatedIds.set(
      ledger.candidateId,
      allocateChannelId(occupiedIds, input.randomHex128),
    );
  }
  const allocationQueue = [...allocatedIds.values()];
  const authoring = new ChannelAuthoringService({
    generateId: () => {
      const id = allocationQueue.shift();
      if (id === undefined) throw allocationError();
      return id;
    },
    now: () => input.nowMs,
  });
  const channels =
    input.body.normalizedConfig.buildMode === 'replace'
      ? []
      : beforeChannels.map(cloneChannelForOwnership);
  const provenance = Object.create(null) as Record<
    string,
    ChannelBuilderChannelProvenanceV1
  >;
  if (input.body.normalizedConfig.buildMode !== 'replace') {
    for (const [channelId, marker] of Object.entries(
      input.before.channelBuilderState?.channelProvenance ?? {},
    )) {
      provenance[channelId] = { ...marker };
    }
  }
  const candidates = new Map(
    input.body.candidateDrafts.map((candidate) => [candidate.candidateId, candidate]),
  );
  const ledgersByCandidate = new Map(
    input.body.candidateLedger.map((ledger) => [ledger.candidateId, ledger]),
  );
  for (const ledger of input.body.candidateLedger) {
    const createInput = input.ready.get(ledger.candidateId);
    const candidate = candidates.get(ledger.candidateId);
    if (createInput === undefined || candidate === undefined) continue;
    if (ledger.classification === 'matched-retained') {
      if (
        input.body.normalizedConfig.buildMode !== 'merge' ||
        ledger.retainedChannelId === null
      ) {
        throw materializationInvalidError();
      }
      const index = channels.findIndex((channel) => channel.id === ledger.retainedChannelId);
      if (index < 0) throw materializationInvalidError();
      channels[index] = updateMatchedChannel(
        authoring,
        channels[index]!,
        channels,
        candidate,
        createInput,
      );
      provenance[ledger.retainedChannelId] = markerForCandidate(input.body, candidate);
      continue;
    }
    if (ledger.classification !== 'new-apply') continue;
    const created = authoring.createChannel(createInput, channels);
    if (created.id !== allocatedIds.get(ledger.candidateId)) throw allocationError();
    channels.push(created);
    provenance[created.id] = markerForCandidate(input.body, candidate);
  }
  channels.sort((left, right) => left.number - right.number);
  if (new Set(channels.map((channel) => channel.number)).size !== channels.length) {
    throw materializationInvalidError();
  }
  const channelOrder = channels.map((channel) => channel.id);
  const finalIds = new Set(channelOrder);
  const createdIds = channelOrder.filter((id) => !beforeIds.has(id));
  const currentChannelId =
    input.before.currentChannelId !== null && finalIds.has(input.before.currentChannelId)
      ? input.before.currentChannelId
      : createdIds[0] ?? channelOrder[0] ?? null;
  const warnings = [...input.body.warnings];
  if (input.skipped.size > 0) {
    warnings.push({
      code: 'MATERIALIZATION_SKIPPED',
      phase: 'materialization',
      strategy: null,
      affectedCount: input.skipped.size,
    });
  }
  const byStrategy = Object.fromEntries(
    CHANNEL_BUILDER_STRATEGY_KEYS.map((strategy) => [
      strategy,
      { created: 0, skipped: 0 },
    ]),
  ) as Record<(typeof CHANNEL_BUILDER_STRATEGY_KEYS)[number], { created: number; skipped: number }>;
  for (const candidate of input.body.candidateDrafts) {
    const ledger = ledgersByCandidate.get(candidate.candidateId);
    if (ledger === undefined || ledger.classification === 'matched-retained') continue;
    if (ledger.classification === 'new-apply' && input.ready.has(candidate.candidateId)) {
      byStrategy[candidate.strategy].created += 1;
    } else {
      byStrategy[candidate.strategy].skipped += 1;
    }
  }
  const summary: ChannelSetupApplySummary = {
    created: createdIds.length,
    removed: [...beforeIds].filter((id) => !finalIds.has(id)).length,
    unchanged: [...beforeIds].filter((id) => finalIds.has(id)).length,
    skipped: Object.values(byStrategy).reduce((sum, entry) => sum + entry.skipped, 0),
    finalChannelCount: channels.length,
    reachedMaxChannels: input.body.candidateLedger.some(
      (entry) => entry.exclusion === 'configured-capacity',
    ),
    watchChannelId: createdIds[0] ?? null,
    byStrategy,
    warnings: normalizeWarnings(warnings),
  };
  return {
    aggregate: {
      storedChannelData: {
        channels,
        channelOrder,
        currentChannelId,
        savedAt: input.nowMs,
      },
      currentChannelId,
      lineupRevision: input.before.lineupRevision,
      channelBuilderState: {
        schemaVersion: 1,
        normalizedConfig: input.body.normalizedConfig,
        completedAtMs: input.nowMs,
        profileBinding: input.body.context.profileBinding,
        serverBinding: input.body.context.serverBinding,
        librarySetBinding: input.body.context.librarySetBinding,
        channelProvenance: provenance,
      },
    },
    summary,
  };
}

function updateMatchedChannel(
  authoring: ChannelAuthoringService,
  current: ChannelConfig,
  channels: readonly ChannelConfig[],
  candidate: ChannelBuilderReviewedPlanBody['candidateDrafts'][number],
  createInput: ChannelCreateInput,
): ChannelConfig {
  const updates: ChannelUpdateInput = {
    contentSource: createInput.contentSource,
    playbackMode: candidate.playbackMode,
    shuffleSeed: candidate.shuffleSeed,
    ...(current.isAutoGenerated === true ? { name: candidate.displayName } : {}),
    ...(createInput.contentFilters === undefined
      ? {}
      : { contentFilters: createInput.contentFilters }),
    ...(candidate.sortOrder === null ? {} : { sortOrder: candidate.sortOrder }),
    ...(candidate.blockSize === null ? {} : { blockSize: candidate.blockSize }),
    ...(candidate.buildStrategy === null
      ? {}
      : { buildStrategy: candidate.buildStrategy }),
    ...(candidate.sourceLibraryId === null
      ? {}
      : { sourceLibraryId: candidate.sourceLibraryId }),
    ...(candidate.sourceLibraryName === null
      ? {}
      : { sourceLibraryName: candidate.sourceLibraryName }),
    ...(candidate.lineupReplicaIndex === null
      ? {}
      : { lineupReplicaIndex: candidate.lineupReplicaIndex }),
    ...(candidate.isPlaybackModeVariant === null
      ? {}
      : { isPlaybackModeVariant: candidate.isPlaybackModeVariant }),
  };
  const updated = cloneChannelForOwnership(
    authoring.updateChannel(current, updates, channels),
  );
  if (candidate.contentFilterPlan.kind === 'none') delete updated.contentFilters;
  if (candidate.sortOrder === null) delete updated.sortOrder;
  if (candidate.blockSize === null) delete updated.blockSize;
  if (candidate.buildStrategy === null) delete updated.buildStrategy;
  if (candidate.sourceLibraryId === null) delete updated.sourceLibraryId;
  if (candidate.sourceLibraryName === null) delete updated.sourceLibraryName;
  if (candidate.lineupReplicaIndex === null) delete updated.lineupReplicaIndex;
  if (candidate.isPlaybackModeVariant === null) delete updated.isPlaybackModeVariant;
  return updated;
}

function markerForCandidate(
  body: ChannelBuilderReviewedPlanBody,
  candidate: ChannelBuilderReviewedPlanBody['candidateDrafts'][number],
): ChannelBuilderChannelProvenanceV1 {
  return {
    schemaVersion: 1,
    identityVersion: 1,
    profileBinding: body.context.profileBinding,
    serverBinding: body.context.serverBinding,
    librarySetBinding: body.context.librarySetBinding,
    sourceIdentity: candidate.sourceReference.sourceIdentity,
    candidateIdentity: candidate.candidateIdentity,
  };
}

function allocateChannelId(
  occupied: Set<string>,
  randomHex128: () => string,
): string {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const hex = randomHex128();
    if (!/^[a-f0-9]{32}$/u.test(hex)) throw allocationError();
    const id = `channel-builder-${hex}`;
    if (!occupied.has(id)) {
      occupied.add(id);
      return id;
    }
  }
  throw allocationError();
}

function normalizeWarnings(
  warnings: readonly ChannelSetupApplySummary['warnings'][number][],
): ChannelSetupApplySummary['warnings'] {
  const grouped = new Map<string, ChannelSetupApplySummary['warnings'][number]>();
  for (const warning of warnings) {
    const key = `${warning.code}\u0000${warning.phase}\u0000${warning.strategy ?? ''}`;
    const prior = grouped.get(key);
    grouped.set(
      key,
      prior === undefined
        ? { ...warning }
        : {
            ...warning,
            affectedCount:
              prior.affectedCount === null || warning.affectedCount === null
                ? null
                : prior.affectedCount + warning.affectedCount,
          },
    );
  }
  return [...grouped.values()]
    .sort(
      (left, right) =>
        left.code.localeCompare(right.code) ||
        left.phase.localeCompare(right.phase) ||
        (left.strategy ?? '').localeCompare(right.strategy ?? ''),
    )
    .slice(0, 50);
}

function withGuideRefreshWarning(
  summary: ChannelSetupApplySummary,
): ChannelSetupApplySummary {
  const refreshWarning = {
    code: 'GUIDE_REFRESH_FAILED' as const,
    phase: 'refresh' as const,
    strategy: null,
    affectedCount: 1,
  };
  const normalized = normalizeWarnings([...summary.warnings, refreshWarning]);
  const containsRefresh = normalized.some(
    (warning) =>
      warning.code === refreshWarning.code &&
      warning.phase === refreshWarning.phase,
  );
  return {
    ...summary,
    warnings: containsRefresh
      ? normalized
      : [...normalized.slice(0, 49), refreshWarning].sort(
          (left, right) =>
            left.code.localeCompare(right.code) ||
            left.phase.localeCompare(right.phase) ||
            (left.strategy ?? '').localeCompare(right.strategy ?? ''),
        ),
  };
}

function activeOperationError(
  operation: 'startReview' | 'startApply',
): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_BUSY',
    message: 'Another channel setup operation is active. Try again.',
    retryable: true,
    recoverable: true,
    operation,
  };
}

function planLookupError(
  kind: Exclude<ReturnType<ChannelBuilderOperationOwner['lookupPlan']>['kind'], 'available'>,
): ChannelSetupRuntimeError {
  if (kind === 'consumed') {
    return {
      code: 'CHANNEL_PLAN_ALREADY_USED',
      message: 'Channel setup review was already used. Review again.',
      retryable: false,
      recoverable: true,
      operation: 'startApply',
    };
  }
  if (kind === 'expired') {
    return {
      code: 'CHANNEL_PLAN_EXPIRED',
      message: 'Channel setup review expired. Review and try again.',
      retryable: true,
      recoverable: true,
      operation: 'startApply',
    };
  }
  return {
    code: 'CHANNEL_PLAN_NOT_FOUND',
    message: 'Channel setup review was not found. Review again.',
    retryable: false,
    recoverable: true,
    operation: 'startApply',
  };
}

function replaceConfirmationError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
    message: 'Replacing channels requires confirmation.',
    retryable: false,
    recoverable: true,
    operation: 'startApply',
  };
}

function consumedCapacityError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_BUSY',
    message: 'Channel setup is retaining too many recently consumed reviews. Try again.',
    retryable: true,
    recoverable: true,
    operation: 'startApply',
  };
}

function lineupConflictError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_LINEUP_CONFLICT',
    message: 'Channels changed after review. Review and try again.',
    retryable: true,
    recoverable: true,
    operation: 'startApply',
  };
}

function replacementEmptyError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_REPLACEMENT_EMPTY',
    message: 'No replacement channels remained available. Review and try again.',
    retryable: true,
    recoverable: true,
    operation: 'startApply',
  };
}

function materializationInvalidError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Channel setup could not validate the reviewed plan.',
    retryable: false,
    recoverable: true,
    operation: 'startApply',
  };
}

function applyRejectionError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_UNKNOWN',
    message: 'Channel setup could not complete the reviewed plan.',
    retryable: true,
    recoverable: true,
    operation: 'startApply',
  };
}

function allocationError(): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_UNKNOWN',
    message: 'Channel setup could not allocate channel identifiers.',
    retryable: true,
    recoverable: true,
    operation: 'startApply',
  };
}

function materializationOutcomeError(
  result: Readonly<{ status: string; reason?: unknown }>,
): ChannelSetupRuntimeError {
  if (
    result.reason === 'context-changed' ||
    result.reason === 'source-member-mismatch' ||
    result.status === 'skipped'
  ) {
    return contextError('startApply');
  }
  if (result.reason === 'index-disposed') {
    return {
      code: 'CHANNEL_PLAN_EXPIRED',
      message: 'Channel setup review expired. Review and try again.',
      retryable: true,
      recoverable: true,
      operation: 'startApply',
    };
  }
  if (result.reason === 'invalid-materialization') {
    return materializationInvalidError();
  }
  return applyRejectionError();
}

function isChannelSetupRuntimeError(value: unknown): value is ChannelSetupRuntimeError {
  return (
    typeof value === 'object' &&
    value !== null &&
    'code' in value &&
    'message' in value &&
    'retryable' in value &&
    'recoverable' in value &&
    'operation' in value
  );
}

function contextError(operation: 'startReview' | 'startApply'): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_CONTEXT_CHANGED',
    message: 'Channel context changed. Review and try again.',
    retryable: true,
    recoverable: true,
    operation,
  };
}

function unknownError(operation: 'startReview' | 'startApply'): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_UNKNOWN',
    message: 'Channel setup could not complete the request.',
    retryable: true,
    recoverable: true,
    operation,
  };
}

function discoveryError(
  code: 'CHANNEL_PLEX_REQUIRED' | 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_UNKNOWN',
): ChannelSetupRuntimeError {
  if (code === 'CHANNEL_CONTEXT_CHANGED') return contextError('startReview');
  if (code === 'CHANNEL_PLEX_REQUIRED') {
    return {
      code,
      message: 'Connect to Plex and select a server and libraries before building channels.',
      retryable: true,
      recoverable: true,
      operation: 'startReview',
    };
  }
  return unknownError('startReview');
}

function operationMissingError(
  operation: 'getOperation' | 'cancel',
): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_OPERATION_NOT_FOUND',
    message: 'Channel setup operation was not found.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function operationExpiredError(
  operation: 'getOperation' | 'cancel',
): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_OPERATION_EXPIRED',
    message: 'Channel setup operation expired.',
    retryable: false,
    recoverable: true,
    operation,
  };
}
