import type {
  ChannelBuilderCandidateDraft,
  ChannelBuilderContextBinding,
  ChannelBuilderFacetId,
  ChannelBuilderSafeSourceReference,
  ChannelBuilderSourceIdentity,
  ChannelBuilderStrategyKey,
  ChannelSetupWarning,
} from '../../domain/channelBuilder/types.js';
import {
  createCandidateIdentity,
  createContentFilterIdentity,
  createSourceIdentity,
} from '../../domain/channelBuilder/index.js';
import { isValidContentSource } from '../../domain/channel/channelContentSourceValidator.js';
import {
  isValidBuildStrategy,
  isValidContentFilterArray,
  isValidPlaybackMode,
  isValidSortOrder,
} from '../../domain/channel/channelValueValidators.js';
import type {
  ChannelContentSource,
  ChannelCreateInput,
  ContentFilter,
} from '../../domain/channel/types.js';

export type ChannelBuilderFacetIndexEntry = Readonly<{
  facetId: ChannelBuilderFacetId;
  sourceIdentity: ChannelBuilderSourceIdentity;
  source: ChannelContentSource;
  family:
    | 'library'
    | 'playlist'
    | 'collection'
    | 'genre'
    | 'director'
    | 'year'
    | 'studio'
    | 'actor'
    | 'recently-added';
  tagValue: string | null;
  semanticGroupIdentity: string | null;
  contentFilterIdentity: string | null;
  yearValue: number | null;
}>;

export type ChannelBuilderFacetMaterializationResult =
  | Readonly<{ status: 'ready'; candidateId: string; createInput: ChannelCreateInput }>
  | Readonly<{
      status: 'skipped';
      candidateId: string;
      reason: 'facet-unavailable' | 'source-member-unavailable';
      warning: ChannelSetupWarning;
    }>
  | Readonly<{
      status: 'failed';
      candidateId: string;
      reason:
        | 'context-changed'
        | 'source-member-mismatch'
        | 'invalid-materialization'
        | 'index-disposed';
      error: Readonly<{
        code: 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_VALIDATION_FAILED' | 'CHANNEL_PLAN_EXPIRED';
        retryable: boolean;
      }>;
    }>
  | Readonly<{ status: 'canceled'; candidateId: string }>;

export interface ChannelBuilderFacetMaterializationIndex {
  readonly context: ChannelBuilderContextBinding;
  materialize(input: Readonly<{
    candidate: ChannelBuilderCandidateDraft;
    expectedContext: ChannelBuilderContextBinding;
    signal: AbortSignal;
  }>): Promise<ChannelBuilderFacetMaterializationResult>;
  dispose(): void;
}

class MutableMaterializationIndex implements ChannelBuilderFacetMaterializationIndex {
  readonly context: ChannelBuilderContextBinding;
  #entries: Map<string, ChannelBuilderFacetIndexEntry> | null;

  constructor(context: ChannelBuilderContextBinding, entries: readonly ChannelBuilderFacetIndexEntry[]) {
    this.context = Object.freeze({ ...context });
    this.#entries = new Map(entries.map((entry) => [entry.facetId, entry]));
  }

  dispose(): void {
    this.#entries?.clear();
    this.#entries = null;
  }

  async materialize(input: Readonly<{
    candidate: ChannelBuilderCandidateDraft;
    expectedContext: ChannelBuilderContextBinding;
    signal: AbortSignal;
  }>): Promise<ChannelBuilderFacetMaterializationResult> {
    const candidateId = input.candidate.candidateId;
    if (this.#entries === null) return failedMaterialization(candidateId, 'index-disposed');
    if (input.signal.aborted) return { status: 'canceled', candidateId };
    if (!equalContext(this.context, input.expectedContext) || !equalOrigin(this.context, input.candidate.origin)) {
      return failedMaterialization(candidateId, 'context-changed');
    }
    try {
      const candidateIdentity = createCandidateIdentity({
        origin: input.candidate.origin,
        sourceReference: input.candidate.sourceReference,
        contentFilterIdentity: input.candidate.contentFilterPlan.contentFilterIdentity,
        sortOrder: input.candidate.sortOrder,
        lineupReplicaIndex: input.candidate.lineupReplicaIndex,
        isPlaybackModeVariant: input.candidate.isPlaybackModeVariant,
        playbackMode: input.candidate.playbackMode,
        blockSize: input.candidate.blockSize,
      });
      if (candidateIdentity !== input.candidate.candidateIdentity) {
        return failedMaterialization(candidateId, 'source-member-mismatch');
      }
      const sourceResult = resolveSource(input.candidate.sourceReference, this.#entries);
      if (sourceResult === null) {
        return skippedMaterialization(
          candidateId,
          input.candidate.sourceReference.kind === 'mixed'
            ? 'source-member-unavailable'
            : 'facet-unavailable',
          input.candidate.strategy,
        );
      }
      if (sourceResult === false) return failedMaterialization(candidateId, 'source-member-mismatch');
      const filters = resolveFilters(input.candidate, this.context, this.#entries);
      if (filters === false) return failedMaterialization(candidateId, 'invalid-materialization');
      const createInput = createInputFromCandidate(input.candidate, sourceResult, filters);
      return { status: 'ready', candidateId, createInput };
    } catch {
      return failedMaterialization(candidateId, 'invalid-materialization');
    }
  }
}

function resolveSource(
  reference: ChannelBuilderSafeSourceReference,
  entries: ReadonlyMap<string, ChannelBuilderFacetIndexEntry>,
): ChannelContentSource | null | false {
  if (reference.kind === 'manual') return false;
  if (reference.kind === 'mixed') {
    const sources: ChannelContentSource[] = [];
    for (const child of reference.sources) {
      const resolved = resolveSource(child, entries);
      if (resolved === null || resolved === false) return resolved;
      sources.push(resolved);
    }
    const mixed: ChannelContentSource = {
      type: 'mixed',
      mixMode: reference.mixMode,
      sources,
    };
    return createSourceIdentity(mixed) === reference.sourceIdentity ? mixed : false;
  }
  if (reference.facetId === null) return false;
  const entry = entries.get(reference.facetId);
  if (entry === undefined) return null;
  if (
    entry.sourceIdentity !== reference.sourceIdentity ||
    createSourceIdentity(entry.source) !== entry.sourceIdentity
  ) return false;
  return cloneSource(entry.source);
}

function resolveFilters(
  candidate: ChannelBuilderCandidateDraft,
  context: ChannelBuilderContextBinding,
  entries: ReadonlyMap<string, ChannelBuilderFacetIndexEntry>,
): ContentFilter[] | undefined | false {
  const plan = candidate.contentFilterPlan;
  if (plan.kind === 'none') return undefined;
  if (plan.kind === 'inline') {
    if (
      plan.filters.length === 0 ||
      !plan.filters.every((filter) => typeof filter.value === 'number' && Number.isFinite(filter.value))
    ) return false;
    const filters = plan.filters.map((filter) => ({ ...filter }));
    return createContentFilterIdentity({
      profileBinding: context.profileBinding,
      serverBinding: context.serverBinding,
      filters,
    }) === plan.contentFilterIdentity
      ? filters
      : false;
  }
  const entry = entries.get(plan.facetId);
  if (
    entry === undefined ||
    entry.family !== 'director' ||
    entry.tagValue === null ||
    entry.contentFilterIdentity !== plan.contentFilterIdentity
  ) return false;
  const filters: ContentFilter[] = [{
    field: 'director',
    operator: 'eq',
    value: entry.tagValue,
  }];
  return createContentFilterIdentity({
    profileBinding: context.profileBinding,
    serverBinding: context.serverBinding,
    filters,
  }) === plan.contentFilterIdentity
    ? filters
    : false;
}

function createInputFromCandidate(
  candidate: ChannelBuilderCandidateDraft,
  contentSource: ChannelContentSource,
  contentFilters: ContentFilter[] | undefined,
): ChannelCreateInput {
  if (
    !isValidContentSource(contentSource) ||
    !isValidPlaybackMode(candidate.playbackMode) ||
    !Number.isInteger(candidate.shuffleSeed) ||
    (candidate.sortOrder !== null && !isValidSortOrder(candidate.sortOrder)) ||
    (candidate.buildStrategy !== null && !isValidBuildStrategy(candidate.buildStrategy)) ||
    (contentFilters !== undefined && (!isValidContentFilterArray(contentFilters) || contentFilters.length === 0))
  ) throw new Error('Invalid materialization');
  return {
    contentSource,
    name: candidate.displayName,
    playbackMode: candidate.playbackMode,
    shuffleSeed: candidate.shuffleSeed,
    isAutoGenerated: true,
    ...(contentFilters !== undefined ? { contentFilters } : {}),
    ...(candidate.sortOrder !== null ? { sortOrder: candidate.sortOrder } : {}),
    ...(candidate.blockSize !== null ? { blockSize: candidate.blockSize } : {}),
    ...(candidate.buildStrategy !== null ? { buildStrategy: candidate.buildStrategy } : {}),
    ...(candidate.sourceLibraryId !== null ? { sourceLibraryId: candidate.sourceLibraryId } : {}),
    ...(candidate.sourceLibraryName !== null ? { sourceLibraryName: candidate.sourceLibraryName } : {}),
    ...(candidate.lineupReplicaIndex !== null ? { lineupReplicaIndex: candidate.lineupReplicaIndex } : {}),
    ...(candidate.isPlaybackModeVariant !== null
      ? { isPlaybackModeVariant: candidate.isPlaybackModeVariant }
      : {}),
  };
}

function cloneSource(source: ChannelContentSource): ChannelContentSource {
  if (source.type === 'mixed') {
    return { ...source, sources: source.sources.map(cloneSource) };
  }
  if (source.type === 'library') {
    return {
      ...source,
      ...(source.libraryFilter === undefined
        ? {}
        : { libraryFilter: { ...source.libraryFilter } }),
    };
  }
  return { ...source };
}

function equalContext(left: ChannelBuilderContextBinding, right: ChannelBuilderContextBinding): boolean {
  return (
    left.contextEpoch === right.contextEpoch &&
    left.profileBinding === right.profileBinding &&
    left.serverBinding === right.serverBinding &&
    left.librarySetBinding === right.librarySetBinding
  );
}

function equalOrigin(context: ChannelBuilderContextBinding, origin: ChannelBuilderCandidateDraft['origin']): boolean {
  return (
    context.profileBinding === origin.profileBinding &&
    context.serverBinding === origin.serverBinding &&
    context.librarySetBinding === origin.librarySetBinding
  );
}

function skippedMaterialization(
  candidateId: string,
  reason: 'facet-unavailable' | 'source-member-unavailable',
  strategy: ChannelBuilderStrategyKey,
): ChannelBuilderFacetMaterializationResult {
  return {
    status: 'skipped',
    candidateId,
    reason,
    warning: {
      code: 'MATERIALIZATION_SKIPPED',
      phase: 'materialization',
      strategy,
      affectedCount: 1,
    },
  };
}

function failedMaterialization(
  candidateId: string,
  reason: 'context-changed' | 'source-member-mismatch' | 'invalid-materialization' | 'index-disposed',
): ChannelBuilderFacetMaterializationResult {
  const error: Readonly<{
    code: 'CHANNEL_CONTEXT_CHANGED' | 'CHANNEL_VALIDATION_FAILED' | 'CHANNEL_PLAN_EXPIRED';
    retryable: boolean;
  }> =
    reason === 'invalid-materialization'
      ? { code: 'CHANNEL_VALIDATION_FAILED', retryable: false }
      : reason === 'index-disposed'
        ? { code: 'CHANNEL_PLAN_EXPIRED', retryable: true }
        : { code: 'CHANNEL_CONTEXT_CHANGED', retryable: true };
  return { status: 'failed', candidateId, reason, error };
}


export function createChannelBuilderFacetMaterializationIndex(
  context: ChannelBuilderContextBinding,
  entries: readonly ChannelBuilderFacetIndexEntry[],
): ChannelBuilderFacetMaterializationIndex {
  return new MutableMaterializationIndex(context, entries);
}
