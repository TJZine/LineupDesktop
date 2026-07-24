import {
  CHANNEL_BUILDER_MAX_CANDIDATES,
  CHANNEL_BUILDER_MAX_CHANNELS,
  CHANNEL_BUILDER_MAX_EXISTING_LINEUP,
} from './constants.js';
import {
  convertFacetWarnings,
  isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations,
  isValidChannelBuilderFacetSnapshot,
  sortAndDedupeChannelSetupWarnings,
  strategyWarning,
} from './facets.js';
import { normalizeChannelSetupConfig } from './config.js';
import {
  channelBuilderIdentityOperations,
  type ChannelBuilderIdentityOperations,
  type CandidateIdentityTuple,
} from './planIdentity.js';
import {
  buildStrategyCandidatesWithIdentityOperations,
  type GeneratedChannelBuilderCandidate,
} from './strategyBuilders.js';
import {
  projectChannelBuilderSafeDisplayString,
  type ChannelBuilderCandidateDraft,
  type ChannelBuilderCandidateId,
  type ChannelBuilderCandidateLedgerEntry,
  type ChannelBuilderExistingLedgerEntry,
  type ChannelBuilderExistingLineupEntry,
  type ChannelBuilderPlannerInput,
  type ChannelBuilderPlannerOutput,
  type ChannelBuilderStrategyKey,
  type ChannelSetupReviewDiff,
  type ChannelSetupWarning,
} from './types.js';

type DraftWithIdentityBytes = Readonly<{
  draft: ChannelBuilderCandidateDraft;
  identityBytes: string | null;
  meetsMinimumItems: boolean;
}>;

function validateInput(input: ChannelBuilderPlannerInput): void {
  const normalized = normalizeChannelSetupConfig(input.normalizedConfig, {
    serverId: input.normalizedConfig.serverId,
    selectedLibraryIds: input.normalizedConfig.selectedLibraryIds,
  });
  if (
    !normalized.ok ||
    !isValidChannelBuilderFacetSnapshot(input.facetSnapshot) ||
    !Number.isSafeInteger(input.clock.nowMs) ||
    input.clock.nowMs < 0 ||
    input.seed.normalize('NFC').trim().length === 0 ||
    input.existingLineup.length > CHANNEL_BUILDER_MAX_EXISTING_LINEUP ||
    input.facetSnapshot.libraries.length > CHANNEL_BUILDER_MAX_CANDIDATES
  ) {
    throw new TypeError('Invalid channel builder planner input.');
  }
  const ids = new Set<string>();
  for (const entry of input.existingLineup) {
    if (
      entry.id.length === 0 ||
      entry.id !== entry.id.trim() ||
      entry.name.length === 0 ||
      (entry.contentFilterIdentity !== null &&
        !/^content-filters:[a-f0-9]{64}$/u.test(
          entry.contentFilterIdentity,
        )) ||
      !Number.isInteger(entry.number) ||
      entry.number < 1 ||
      entry.number > CHANNEL_BUILDER_MAX_CHANNELS ||
      ids.has(entry.id)
    ) {
      throw new TypeError('Invalid existing channel builder lineup.');
    }
    ids.add(entry.id);
  }
}

function toDrafts(
  identityOperations: ChannelBuilderIdentityOperations,
  generated: readonly GeneratedChannelBuilderCandidate[],
  input: ChannelBuilderPlannerInput,
): readonly DraftWithIdentityBytes[] {
  const occurrences = new Map<string, number>();
  const requiresIdentityBytes =
    input.normalizedConfig.buildMode !== 'replace' &&
    input.existingLineup.length > 0;
  return generated.map((candidate) => {
    if (
      !isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations(
        identityOperations,
        candidate.contentFilterPlan,
        input.facetSnapshot,
      )
    ) {
      throw new TypeError('Invalid channel builder candidate content filter plan.');
    }
    const origin = {
      profileBinding: input.facetSnapshot.context.profileBinding,
      serverBinding: input.facetSnapshot.context.serverBinding,
      librarySetBinding: input.facetSnapshot.context.librarySetBinding,
    };
    const identityInput = {
      origin,
      sourceReference: candidate.sourceReference,
      contentFilterIdentity: candidate.contentFilterPlan.contentFilterIdentity,
      sortOrder: candidate.sortOrder,
      lineupReplicaIndex: candidate.lineupReplicaIndex,
      isPlaybackModeVariant: candidate.isPlaybackModeVariant,
      playbackMode: candidate.playbackMode,
      blockSize: candidate.blockSize,
    };
    const identityTuple = requiresIdentityBytes
      ? identityOperations.createCandidateIdentityTuple(identityInput)
      : null;
    const candidateIdentity =
      identityTuple?.identity ??
      identityOperations.createCandidateIdentity(identityInput);
    const occurrenceKey = `${candidate.strategy}\u0000${candidateIdentity}`;
    const occurrence = occurrences.get(occurrenceKey) ?? 0;
    occurrences.set(occurrenceKey, occurrence + 1);
    const candidateId = identityOperations.createCandidateId({
      seed: input.seed,
      strategy: candidate.strategy,
      candidateIdentity,
      occurrence,
    });
    const draft: ChannelBuilderCandidateDraft = {
      candidateId,
      candidateIdentity,
      origin,
      strategy: candidate.strategy,
      displayName: candidate.displayName,
      sourceReference: candidate.sourceReference,
      estimatedItemCount: candidate.estimatedItemCount,
      playbackMode: candidate.playbackMode,
      shuffleSeed: candidate.shuffleSeed,
      contentFilterPlan: candidate.contentFilterPlan,
      sortOrder: candidate.sortOrder,
      blockSize: candidate.blockSize,
      buildStrategy: candidate.buildStrategy,
      sourceLibraryId: candidate.sourceLibraryId,
      sourceLibraryName: candidate.sourceLibraryName,
      lineupReplicaIndex: candidate.lineupReplicaIndex,
      isPlaybackModeVariant: candidate.isPlaybackModeVariant,
    };
    return {
      draft,
      identityBytes: identityTuple?.bytes ?? null,
      meetsMinimumItems: candidate.meetsMinimumItems,
    };
  });
}

function existingCandidateTuple(
  identityOperations: ChannelBuilderIdentityOperations,
  entry: ChannelBuilderExistingLineupEntry,
  input: ChannelBuilderPlannerInput,
): CandidateIdentityTuple | null {
  if (entry.sourceDisposition !== 'matchable' || entry.builderProvenance === null) {
    return null;
  }
  const marker = entry.builderProvenance;
  const context = input.facetSnapshot.context;
  if (
    marker.schemaVersion !== 1 ||
    marker.identityVersion !== 1 ||
    marker.profileBinding !== context.profileBinding ||
    marker.serverBinding !== context.serverBinding ||
    marker.librarySetBinding !== context.librarySetBinding ||
    marker.sourceIdentity !== entry.sourceReference.sourceIdentity
  ) {
    return null;
  }
  const identityInput = {
    origin: {
      profileBinding: context.profileBinding,
      serverBinding: context.serverBinding,
      librarySetBinding: context.librarySetBinding,
    },
    sourceReference: entry.sourceReference,
    contentFilterIdentity: entry.contentFilterIdentity,
    sortOrder: entry.sortOrder ?? null,
    lineupReplicaIndex: entry.lineupReplicaIndex ?? null,
    isPlaybackModeVariant: entry.isPlaybackModeVariant ?? null,
    playbackMode: entry.playbackMode,
    blockSize: entry.blockSize ?? null,
  };
  const tuple = identityOperations.createCandidateIdentityTuple(identityInput);
  if (tuple.identity !== marker.candidateIdentity) return null;
  return tuple;
}

function buildMatches(
  identityOperations: ChannelBuilderIdentityOperations,
  drafts: readonly DraftWithIdentityBytes[],
  input: ChannelBuilderPlannerInput,
): Readonly<{
  candidateToExisting: ReadonlyMap<ChannelBuilderCandidateId, string>;
  existingToCandidate: ReadonlyMap<string, ChannelBuilderCandidateId>;
}> {
  const candidateToExisting = new Map<ChannelBuilderCandidateId, string>();
  const existingToCandidate = new Map<string, ChannelBuilderCandidateId>();
  if (input.normalizedConfig.buildMode === 'replace') {
    return { candidateToExisting, existingToCandidate };
  }
  const candidatesByIdentity = new Map<string, DraftWithIdentityBytes[]>();
  for (const draft of drafts) {
    if (!draft.meetsMinimumItems) continue;
    const key = draft.draft.candidateIdentity;
    const queue = candidatesByIdentity.get(key) ?? [];
    queue.push(draft);
    candidatesByIdentity.set(key, queue);
  }
  for (const existing of input.existingLineup) {
    const tuple = existingCandidateTuple(identityOperations, existing, input);
    if (tuple === null) continue;
    const queue = candidatesByIdentity.get(tuple.identity);
    if (!queue) continue;
    const matchIndex = identityOperations.findByteEqualCandidateTupleIndex(
      queue.map((candidate) => {
        if (candidate.identityBytes === null) {
          throw new Error('Candidate identity bytes invariant failed.');
        }
        return {
          identity: candidate.draft.candidateIdentity,
          bytes: candidate.identityBytes,
        };
      }),
      tuple,
    );
    if (matchIndex < 0) continue;
    const [candidate] = queue.splice(matchIndex, 1);
    if (!candidate) throw new Error('Candidate tuple queue invariant failed.');
    candidateToExisting.set(candidate.draft.candidateId, existing.id);
    existingToCandidate.set(existing.id, candidate.draft.candidateId);
  }
  return { candidateToExisting, existingToCandidate };
}

function warningCountsByStrategy(
  drafts: readonly DraftWithIdentityBytes[],
  predicate: (draft: DraftWithIdentityBytes) => boolean,
  code: 'MIN_ITEMS_SKIPPED' | 'MAX_CHANNELS_REACHED',
): readonly ChannelSetupWarning[] {
  const counts = new Map<ChannelBuilderStrategyKey, number>();
  for (const draft of drafts) {
    if (!predicate(draft)) continue;
    counts.set(draft.draft.strategy, (counts.get(draft.draft.strategy) ?? 0) + 1);
  }
  return [...counts.entries()].map(([strategy, count]) =>
    strategyWarning(code, strategy, count),
  );
}

function buildReviewDiff(
  input: ChannelBuilderPlannerInput,
  drafts: readonly DraftWithIdentityBytes[],
  candidateLedger: readonly ChannelBuilderCandidateLedgerEntry[],
): ChannelSetupReviewDiff {
  const createdNames = candidateLedger
    .filter((entry) => entry.classification === 'new-apply')
    .map((entry) => drafts[entry.ordinal]!.draft.displayName);
  const existingNames = input.existingLineup.map((entry) =>
    projectChannelBuilderSafeDisplayString(entry.name, {
      fallback: 'Untitled channel',
      maxUtf16Units: 160,
    }),
  );
  if (input.normalizedConfig.buildMode === 'replace') {
    return {
      summary: {
        created: createdNames.length,
        removed: input.existingLineup.length,
        unchanged: 0,
      },
      samples: {
        created: createdNames.slice(0, 6),
        removed: existingNames.slice(0, 6),
        unchanged: [],
      },
    };
  }
  return {
    summary: {
      created: createdNames.length,
      removed: 0,
      unchanged: input.existingLineup.length,
    },
    samples: {
      created: createdNames.slice(0, 6),
      removed: [],
      unchanged: existingNames.slice(0, 6),
    },
  };
}

function existingIdentityProjection(
  identityOperations: ChannelBuilderIdentityOperations,
  entry: ChannelBuilderExistingLineupEntry,
): unknown {
  return {
    id: identityOperations.createPersistedStringV1(entry.id),
    number: entry.number,
    name: identityOperations.createPersistedStringV1(entry.name),
    sourceDisposition: entry.sourceDisposition,
    sourceReference: entry.sourceReference,
    playbackMode: entry.playbackMode,
    builderProvenance: entry.builderProvenance,
    ...(entry.isAutoGenerated !== undefined
      ? { isAutoGenerated: entry.isAutoGenerated }
      : {}),
    contentFilterIdentity: entry.contentFilterIdentity,
    ...(entry.sortOrder !== undefined ? { sortOrder: entry.sortOrder } : {}),
    ...(entry.blockSize !== undefined ? { blockSize: entry.blockSize } : {}),
    ...(entry.lineupReplicaIndex !== undefined
      ? { lineupReplicaIndex: entry.lineupReplicaIndex }
      : {}),
    ...(entry.isPlaybackModeVariant !== undefined
      ? { isPlaybackModeVariant: entry.isPlaybackModeVariant }
      : {}),
  };
}

function outputIdentityProjection(
  identityOperations: ChannelBuilderIdentityOperations,
  output: Omit<ChannelBuilderPlannerOutput, 'planIdentity'>,
): unknown {
  return {
    ...output,
    candidateLedger: output.candidateLedger.map((entry) => ({
      ...entry,
      retainedChannelId:
        entry.retainedChannelId === null
          ? null
          : identityOperations.createPersistedStringV1(entry.retainedChannelId),
    })),
    existingLedger: output.existingLedger.map((entry) => ({
      ...entry,
      existingChannelId: identityOperations.createPersistedStringV1(
        entry.existingChannelId,
      ),
    })),
  };
}

export function buildChannelSetupPlan(
  input: ChannelBuilderPlannerInput,
): ChannelBuilderPlannerOutput {
  return buildChannelSetupPlanWithIdentityOperations(
    channelBuilderIdentityOperations,
    input,
  );
}

function buildChannelSetupPlanWithIdentityOperations(
  identityOperations: ChannelBuilderIdentityOperations,
  input: ChannelBuilderPlannerInput,
): ChannelBuilderPlannerOutput {
  validateInput(input);
  const generated = buildStrategyCandidatesWithIdentityOperations(
    identityOperations,
    {
      normalizedConfig: input.normalizedConfig,
      facetSnapshot: input.facetSnapshot,
      seed: input.seed,
    },
  );
  const drafts = toDrafts(identityOperations, generated, input);
  const matches = buildMatches(identityOperations, drafts, input);
  const requestedMaxChannels = input.normalizedConfig.maxChannels;
  const effectiveMaxChannels = Math.min(requestedMaxChannels, CHANNEL_BUILDER_MAX_CHANNELS);
  const occupiedNumbers = new Set(input.existingLineup.map((entry) => entry.number));
  const availableCreateSlots =
    input.normalizedConfig.buildMode === 'replace'
      ? Math.min(effectiveMaxChannels, CHANNEL_BUILDER_MAX_CHANNELS)
      : Math.min(
          Math.max(0, effectiveMaxChannels - input.existingLineup.length),
          CHANNEL_BUILDER_MAX_CHANNELS - occupiedNumbers.size,
        );
  let configuredRemaining =
    input.normalizedConfig.buildMode === 'replace'
      ? effectiveMaxChannels
      : Math.max(0, effectiveMaxChannels - input.existingLineup.length);
  let numberRemaining =
    input.normalizedConfig.buildMode === 'replace'
      ? CHANNEL_BUILDER_MAX_CHANNELS
      : CHANNEL_BUILDER_MAX_CHANNELS - occupiedNumbers.size;
  const candidateLedger: ChannelBuilderCandidateLedgerEntry[] = [];
  for (let ordinal = 0; ordinal < drafts.length; ordinal += 1) {
    const candidate = drafts[ordinal]!;
    const retainedChannelId =
      matches.candidateToExisting.get(candidate.draft.candidateId) ?? null;
    if (!candidate.meetsMinimumItems) {
      candidateLedger.push({
        ordinal,
        candidateId: candidate.draft.candidateId,
        strategy: candidate.draft.strategy,
        sourceIdentity: candidate.draft.sourceReference.sourceIdentity,
        classification: 'excluded',
        exclusion: 'minimum-items',
        retainedChannelId: null,
      });
    } else if (retainedChannelId !== null) {
      candidateLedger.push({
        ordinal,
        candidateId: candidate.draft.candidateId,
        strategy: candidate.draft.strategy,
        sourceIdentity: candidate.draft.sourceReference.sourceIdentity,
        classification: 'matched-retained',
        exclusion: null,
        retainedChannelId,
      });
    } else if (configuredRemaining <= 0) {
      candidateLedger.push({
        ordinal,
        candidateId: candidate.draft.candidateId,
        strategy: candidate.draft.strategy,
        sourceIdentity: candidate.draft.sourceReference.sourceIdentity,
        classification: 'excluded',
        exclusion: 'configured-capacity',
        retainedChannelId: null,
      });
    } else if (numberRemaining <= 0) {
      candidateLedger.push({
        ordinal,
        candidateId: candidate.draft.candidateId,
        strategy: candidate.draft.strategy,
        sourceIdentity: candidate.draft.sourceReference.sourceIdentity,
        classification: 'excluded',
        exclusion: 'channel-number-capacity',
        retainedChannelId: null,
      });
    } else {
      candidateLedger.push({
        ordinal,
        candidateId: candidate.draft.candidateId,
        strategy: candidate.draft.strategy,
        sourceIdentity: candidate.draft.sourceReference.sourceIdentity,
        classification: 'new-apply',
        exclusion: null,
        retainedChannelId: null,
      });
      configuredRemaining -= 1;
      numberRemaining -= 1;
    }
  }
  const existingLedger: ChannelBuilderExistingLedgerEntry[] = input.existingLineup.map(
    (entry, ordinal) => {
      const matchedCandidateId = matches.existingToCandidate.get(entry.id) ?? null;
      return {
        ordinal,
        existingChannelId: entry.id,
        disposition:
          input.normalizedConfig.buildMode === 'replace'
            ? 'replace-remove'
            : matchedCandidateId === null
              ? 'unmatched-retained'
              : 'matched-retained',
        matchedCandidateId,
      };
    },
  );
  const applyCandidateIds = candidateLedger
    .filter((entry) => entry.classification === 'new-apply')
    .map((entry) => entry.candidateId);
  const retainedMaterializationCandidateIds =
    input.normalizedConfig.buildMode === 'merge'
      ? candidateLedger
          .filter((entry) => entry.classification === 'matched-retained')
          .map((entry) => entry.candidateId)
      : [];
  const configuredExclusions = candidateLedger.filter(
    (entry) => entry.exclusion === 'configured-capacity',
  );
  const pureCandidateCount = candidateLedger.filter(
    (entry) => entry.exclusion !== 'minimum-items',
  ).length;
  const planEmpty = pureCandidateCount === 0;
  const blocked = planEmpty || input.facetSnapshot.aggregate.status === 'blocked';
  let warnings: readonly ChannelSetupWarning[];
  if (planEmpty) {
    warnings = [
      {
        code: 'PLAN_EMPTY',
        phase: 'planning',
        strategy: null,
        affectedCount: 0,
      },
    ];
  } else {
    const unmatchableCount = input.existingLineup.filter(
      (entry) => entry.sourceDisposition === 'retained-unmatchable',
    ).length;
    const configuredExcludedIds = new Set(
      configuredExclusions.map((entry) => entry.candidateId),
    );
    warnings = sortAndDedupeChannelSetupWarnings([
      ...convertFacetWarnings(input.facetSnapshot.aggregate),
      ...warningCountsByStrategy(
        drafts,
        (draft) => !draft.meetsMinimumItems,
        'MIN_ITEMS_SKIPPED',
      ),
      ...warningCountsByStrategy(
        drafts,
        (draft) => configuredExcludedIds.has(draft.draft.candidateId),
        'MAX_CHANNELS_REACHED',
      ),
      ...(unmatchableCount > 0
        ? [
            {
              code: 'EXISTING_SOURCE_UNMATCHABLE' as const,
              phase: 'planning' as const,
              strategy: null,
              affectedCount: unmatchableCount,
            },
          ]
        : []),
    ]);
  }
  const diff = buildReviewDiff(input, drafts, candidateLedger);
  const status = blocked
    ? 'blocked'
    : input.facetSnapshot.aggregate.status === 'slow'
      ? 'slow'
      : 'ready';
  const outputWithoutIdentity = {
    status,
    candidateDrafts: drafts.map(({ draft }) => draft),
    applyCandidateIds: blocked ? [] : applyCandidateIds,
    retainedMaterializationCandidateIds: blocked
      ? []
      : retainedMaterializationCandidateIds,
    candidateLedger,
    existingLedger,
    diff,
    warnings,
    reachedCap: configuredExclusions.length > 0,
    capacity: {
      requestedMaxChannels,
      effectiveMaxChannels,
      availableCreateSlots,
    },
  } satisfies Omit<ChannelBuilderPlannerOutput, 'planIdentity'>;
  const planIdentity = identityOperations.createPlanIdentity(
    {
      normalizedConfig: input.normalizedConfig,
      facetSnapshot: input.facetSnapshot,
      existingLineup: input.existingLineup.map((entry) =>
        existingIdentityProjection(identityOperations, entry),
      ),
      clock: input.clock,
      seed: input.seed,
    } as never,
    outputIdentityProjection(identityOperations, outputWithoutIdentity) as never,
  );
  return { planIdentity, ...outputWithoutIdentity };
}

export function createChannelSetupPlanner(
  identityOperations: ChannelBuilderIdentityOperations,
): (input: ChannelBuilderPlannerInput) => ChannelBuilderPlannerOutput {
  return (input) =>
    buildChannelSetupPlanWithIdentityOperations(identityOperations, input);
}
