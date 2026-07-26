import type {
  ChannelSetupApplySummary,
  ChannelSetupOperation,
  ChannelSetupRuntimeError,
  NormalizedChannelSetupConfig,
} from '../../contracts/channel.js';
import type {
  ChannelBuilderCandidateDraft,
  ChannelBuilderCandidateLedgerEntry,
  ChannelBuilderContextBinding,
  ChannelBuilderExistingLedgerEntry,
  ChannelBuilderPlanIdentity,
  ChannelSetupReviewDiff,
  ChannelSetupWarning,
} from '../../domain/channelBuilder/types.js';
import type { ChannelBuilderFacetMaterializationIndex } from '../plex/channelBuilderFacetMaterialization.js';

const RETENTION_MS = 10 * 60 * 1_000;
const TERMINAL_LIMIT = 16;
const PLAN_LIMIT = 4;
const CONSUMED_LIMIT = 16;
const TOMBSTONE_LIMIT = 32;

export type ChannelBuilderReviewedPlanBody = Readonly<{
  planId: string;
  planIdentity: ChannelBuilderPlanIdentity;
  status: 'ready' | 'slow';
  normalizedConfig: NormalizedChannelSetupConfig;
  context: ChannelBuilderContextBinding;
  lineupRevision: number;
  candidateDrafts: readonly ChannelBuilderCandidateDraft[];
  applyCandidateIds: readonly string[];
  retainedMaterializationCandidateIds: readonly string[];
  candidateLedger: readonly ChannelBuilderCandidateLedgerEntry[];
  existingLedger: readonly ChannelBuilderExistingLedgerEntry[];
  diff: ChannelSetupReviewDiff;
  warnings: readonly ChannelSetupWarning[];
  reachedCap: boolean;
  capacity: Readonly<{
    requestedMaxChannels: number;
    effectiveMaxChannels: number;
    availableCreateSlots: number;
  }>;
  materializationIndex: ChannelBuilderFacetMaterializationIndex;
}>;

export type ChannelBuilderOperationHandle = Readonly<{
  operationId: string;
  signal: AbortSignal;
}>;

type OwnedOperation = {
  operation: ChannelSetupOperation;
  controller: AbortController;
  commitStarted: boolean;
  expiresAtMs: number | null;
};

type RetainedPlan = {
  body: ChannelBuilderReviewedPlanBody;
  expiresAtMs: number;
};

type ConsumedPlan = {
  applyOperationId: string;
  expiresAtMs: number;
};

export type ChannelBuilderPlanLookup =
  | Readonly<{ kind: 'available'; body: ChannelBuilderReviewedPlanBody }>
  | Readonly<{ kind: 'consumed' }>
  | Readonly<{ kind: 'expired' }>
  | Readonly<{ kind: 'missing' }>;

export class ChannelBuilderOperationOwner {
  private readonly nowMs: () => number;
  private readonly randomHex128: () => string;
  private readonly releasePlan: (planId: string) => void;
  private readonly operations = new Map<string, OwnedOperation>();
  private readonly plans = new Map<string, RetainedPlan>();
  private readonly consumedPlans = new Map<string, ConsumedPlan>();
  private readonly operationTombstones = new Map<string, number>();
  private readonly planTombstones = new Map<string, number>();
  private activeOperationId: string | null = null;

  constructor(options: Readonly<{
    nowMs?: () => number;
    randomHex128: () => string;
    releasePlan?: (planId: string) => void;
  }>) {
    this.nowMs = options.nowMs ?? Date.now;
    this.randomHex128 = options.randomHex128;
    this.releasePlan = options.releasePlan ?? (() => undefined);
  }

  hasActiveOperation(): boolean {
    return this.activeOperationId !== null;
  }

  start(
    kind: 'review' | 'apply',
    materializationCount = 0,
  ): ChannelBuilderOperationHandle {
    this.prune();
    if (this.activeOperationId !== null) throw activeOperationError();
    const operationId = this.issueId(kind);
    const nowMs = this.nowMs();
    const controller = new AbortController();
    const operation: ChannelSetupOperation =
      kind === 'review'
        ? {
            operationId,
            kind,
            state: 'queued',
            phase: 'discover-facets',
            startedAtMs: nowMs,
            updatedAtMs: nowMs,
            progress: { completed: 0, total: null },
            result: null,
            error: null,
          }
        : {
            operationId,
            kind,
            state: 'queued',
            phase: 'materialize',
            startedAtMs: nowMs,
            updatedAtMs: nowMs,
            progress: { completed: 0, total: materializationCount },
            result: null,
            error: null,
          };
    this.operations.set(operationId, {
      operation,
      controller,
      commitStarted: false,
      expiresAtMs: null,
    });
    this.activeOperationId = operationId;
    return { operationId, signal: controller.signal };
  }

  get(operationId: string): ChannelSetupOperation | null {
    this.prune();
    return cloneOperation(this.operations.get(operationId)?.operation ?? null);
  }

  isOperationExpired(operationId: string): boolean {
    this.prune();
    return this.operationTombstones.has(operationId);
  }

  markRunning(
    operationId: string,
    phase: 'discover-facets' | 'plan' | 'materialize' | 'persist' | 'refresh-guide',
    progress: Readonly<{ completed: number; total: number | null }>,
  ): void {
    const owned = this.requireActive(operationId);
    if (
      owned.operation.phase === phase &&
      progress.completed < owned.operation.progress.completed
    ) {
      throw new Error('Channel Builder operation progress cannot move backward.');
    }
    owned.operation = {
      ...owned.operation,
      state: 'running',
      phase,
      updatedAtMs: this.nextUpdatedAt(owned),
      progress: { ...progress },
      result: null,
      error: null,
    } as ChannelSetupOperation;
  }

  markReviewReady(
    operationId: string,
    result: Extract<ChannelSetupOperation, { state: 'review-ready' }>['result'],
  ): void {
    const owned = this.requireActive(operationId);
    owned.operation = {
      ...owned.operation,
      kind: 'review',
      state: 'review-ready',
      phase: 'review-ready',
      updatedAtMs: this.nextUpdatedAt(owned),
      result,
      error: null,
      progress: { completed: 1, total: 1 },
    };
    this.finish(owned);
  }

  markApplySucceeded(
    operationId: string,
    summary: ChannelSetupApplySummary,
    guideRefresh: 'completed' | 'failed',
  ): void {
    const owned = this.requireActive(operationId);
    owned.operation = {
      ...owned.operation,
      kind: 'apply',
      state: 'succeeded',
      phase: 'done',
      updatedAtMs: this.nextUpdatedAt(owned),
      result: { kind: 'apply', commit: 'committed', summary, guideRefresh },
      error: null,
      progress: { completed: 1, total: 1 },
    };
    this.finish(owned);
  }

  markFailed(operationId: string, error: ChannelSetupRuntimeError): void {
    const owned = this.requireActive(operationId);
    owned.operation = {
      ...owned.operation,
      state: 'failed',
      phase: 'done',
      updatedAtMs: this.nextUpdatedAt(owned),
      result: null,
      error,
      progress: { completed: 1, total: 1 },
    } as ChannelSetupOperation;
    this.finish(owned);
  }

  markCanceled(operationId: string): void {
    const owned = this.requireActive(operationId);
    owned.operation = {
      ...owned.operation,
      state: 'canceled',
      phase: 'done',
      updatedAtMs: this.nextUpdatedAt(owned),
      result: { kind: 'canceled' },
      error: null,
      progress: { completed: 1, total: 1 },
    } as ChannelSetupOperation;
    this.finish(owned);
  }

  cancel(operationId: string): Readonly<{
    accepted: boolean;
    reason: null | 'already-terminal' | 'commit-started';
    operation: ChannelSetupOperation;
  }> | null {
    const owned = this.operations.get(operationId);
    if (owned === undefined) return null;
    if (owned.operation.state === 'canceled') {
      return { accepted: true, reason: null, operation: cloneOperation(owned.operation)! };
    }
    if (isTerminal(owned.operation)) {
      return {
        accepted: false,
        reason: 'already-terminal',
        operation: cloneOperation(owned.operation)!,
      };
    }
    if (owned.commitStarted) {
      return {
        accepted: false,
        reason: 'commit-started',
        operation: cloneOperation(owned.operation)!,
      };
    }
    if (owned.operation.state !== 'canceling') {
      owned.controller.abort();
      owned.operation = {
        ...owned.operation,
        state: 'canceling',
        updatedAtMs: this.nextUpdatedAt(owned),
      } as ChannelSetupOperation;
    }
    return { accepted: true, reason: null, operation: cloneOperation(owned.operation)! };
  }

  beginCommit(operationId: string): 'proceed' | 'cancel' {
    const owned = this.requireActive(operationId);
    if (owned.controller.signal.aborted) return 'cancel';
    owned.commitStarted = true;
    return 'proceed';
  }

  retainPlan(body: ChannelBuilderReviewedPlanBody): void {
    this.prune();
    if (this.plans.has(body.planId) || this.consumedPlans.has(body.planId)) {
      throw new Error('Channel Builder plan identity collision.');
    }
    while (this.plans.size >= PLAN_LIMIT) {
      const oldest = this.plans.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      this.expirePlan(oldest);
    }
    this.plans.set(body.planId, {
      body,
      expiresAtMs: this.nowMs() + RETENTION_MS,
    });
  }

  lookupPlan(planId: string): ChannelBuilderPlanLookup {
    this.prune();
    if (this.consumedPlans.has(planId)) return { kind: 'consumed' };
    const retained = this.plans.get(planId);
    if (retained !== undefined) return { kind: 'available', body: retained.body };
    if (this.planTombstones.has(planId)) return { kind: 'expired' };
    return { kind: 'missing' };
  }

  invalidatePlan(planId: string): void {
    this.expirePlan(planId);
  }

  consumePlan(planId: string, applyOperationId: string): ChannelBuilderReviewedPlanBody {
    this.prune();
    if (this.consumedPlans.size >= CONSUMED_LIMIT) throw consumedCapacityError();
    const retained = this.plans.get(planId);
    if (retained === undefined) throw new Error('Channel Builder plan is unavailable.');
    this.plans.delete(planId);
    this.consumedPlans.set(planId, {
      applyOperationId,
      expiresAtMs: this.nowMs() + RETENTION_MS,
    });
    return retained.body;
  }

  hasConsumedPlanCapacity(): boolean {
    this.prune();
    return this.consumedPlans.size >= CONSUMED_LIMIT;
  }

  issuePlanId(): string {
    return this.issueOpaqueId('channel-builder-plan-');
  }

  shutdown(): void {
    for (const owned of this.operations.values()) {
      if (!isTerminal(owned.operation)) owned.controller.abort();
    }
    for (const planId of [...this.plans.keys()]) this.expirePlan(planId);
    this.operations.clear();
    this.consumedPlans.clear();
    this.operationTombstones.clear();
    this.planTombstones.clear();
    this.activeOperationId = null;
  }

  private requireActive(operationId: string): OwnedOperation {
    if (this.activeOperationId !== operationId) {
      throw new Error('Channel Builder operation is not active.');
    }
    const owned = this.operations.get(operationId);
    if (owned === undefined) throw new Error('Channel Builder operation is unavailable.');
    return owned;
  }

  private nextUpdatedAt(owned: OwnedOperation): number {
    return Math.max(this.nowMs(), owned.operation.updatedAtMs + 1);
  }

  private finish(owned: OwnedOperation): void {
    this.activeOperationId = null;
    owned.expiresAtMs = this.nowMs() + RETENTION_MS;
    this.prune();
  }

  private issueId(kind: 'review' | 'apply'): string {
    return this.issueOpaqueId(`channel-builder-${kind}-`);
  }

  private issueOpaqueId(prefix: string): string {
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const hex = this.randomHex128();
      if (!/^[a-f0-9]{32}$/u.test(hex)) break;
      const id = `${prefix}${hex}`;
      if (
        !this.operations.has(id) &&
        !this.plans.has(id) &&
        !this.consumedPlans.has(id) &&
        !this.operationTombstones.has(id) &&
        !this.planTombstones.has(id)
      ) {
        return id;
      }
    }
    throw activeOperationError();
  }

  private expirePlan(planId: string): void {
    const retained = this.plans.get(planId);
    if (retained === undefined) return;
    this.plans.delete(planId);
    try {
      retained.body.materializationIndex.dispose();
    } finally {
      this.releasePlan(planId);
    }
    this.addTombstone(this.planTombstones, planId);
  }

  private prune(): void {
    const nowMs = this.nowMs();
    for (const [planId, retained] of this.plans) {
      if (retained.expiresAtMs <= nowMs) this.expirePlan(planId);
    }
    for (const [planId, consumed] of this.consumedPlans) {
      if (consumed.expiresAtMs <= nowMs) {
        this.consumedPlans.delete(planId);
        this.addTombstone(this.planTombstones, planId);
      }
    }
    for (const [operationId, owned] of this.operations) {
      if (owned.expiresAtMs !== null && owned.expiresAtMs <= nowMs) {
        this.operations.delete(operationId);
        this.addTombstone(this.operationTombstones, operationId);
      }
    }
    for (const [id, expiresAtMs] of this.planTombstones) {
      if (expiresAtMs <= nowMs) this.planTombstones.delete(id);
    }
    for (const [id, expiresAtMs] of this.operationTombstones) {
      if (expiresAtMs <= nowMs) this.operationTombstones.delete(id);
    }
    this.trimTerminalOperations();
  }

  private trimTerminalOperations(): void {
    const terminal = [...this.operations.entries()].filter(([, owned]) =>
      isTerminal(owned.operation));
    while (terminal.length > TERMINAL_LIMIT) {
      const entry = terminal.shift();
      if (entry === undefined) break;
      this.operations.delete(entry[0]);
      this.addTombstone(this.operationTombstones, entry[0]);
    }
  }

  private addTombstone(target: Map<string, number>, id: string): void {
    target.set(id, this.nowMs() + RETENTION_MS);
    while (target.size > TOMBSTONE_LIMIT) {
      const oldest = target.keys().next().value as string | undefined;
      if (oldest === undefined) break;
      target.delete(oldest);
    }
  }
}

function isTerminal(operation: ChannelSetupOperation): boolean {
  return (
    operation.state === 'review-ready' ||
    operation.state === 'succeeded' ||
    operation.state === 'canceled' ||
    operation.state === 'failed'
  );
}

function cloneOperation(operation: ChannelSetupOperation | null): ChannelSetupOperation | null {
  return operation === null ? null : globalThis.structuredClone(operation);
}

function activeOperationError(): Error & { code: 'CHANNEL_BUSY' } {
  return Object.assign(new Error('Another channel setup operation is active.'), {
    code: 'CHANNEL_BUSY' as const,
  });
}

function consumedCapacityError(): Error & { code: 'CHANNEL_BUSY' } {
  return Object.assign(new Error('Channel Builder consumed plan capacity is full.'), {
    code: 'CHANNEL_BUSY' as const,
  });
}
