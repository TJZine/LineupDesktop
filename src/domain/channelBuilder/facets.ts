import {
  CHANNEL_BUILDER_FACET_WARNING_CODES,
  CHANNEL_BUILDER_MAX_CANDIDATES,
  CHANNEL_BUILDER_MAX_WARNINGS,
} from './constants.js';
import { hasExactPlainRecordKeys } from './exactRecord.js';
import {
  channelBuilderIdentityOperations,
  type ChannelBuilderIdentityOperations,
} from './planIdentity.js';
import type {
  ChannelBuilderCandidateContentFilterPlan,
  ChannelBuilderFacetSnapshot,
  ChannelBuilderFacetWarningCode,
  ChannelBuilderStrategyKey,
  ChannelSetupWarning,
} from './types.js';

const bindingPatterns = {
  profile: /^profile-binding:[a-f0-9]{64}$/u,
  server: /^server-binding:[a-f0-9]{64}$/u,
  librarySet: /^library-set-binding:[a-f0-9]{64}$/u,
};
const facetPattern =
  /^(library|playlist|collection|genre|director|year|studio|actor|recently-added):[a-f0-9]{64}$/u;
const sourcePattern = /^source:[a-f0-9]{64}$/u;
const groupPattern = /^tag-group:[a-f0-9]{64}$/u;
const filterPattern = /^content-filters:[a-f0-9]{64}$/u;

const warningCodeSet = new Set<ChannelBuilderFacetWarningCode>(
  CHANNEL_BUILDER_FACET_WARNING_CODES,
);

function validCount(value: unknown, nullable = false): boolean {
  return (
    (nullable && value === null) ||
    (typeof value === 'number' &&
      Number.isFinite(value) &&
      Number.isInteger(value) &&
      value >= 0)
  );
}

function validSafeTitle(value: unknown): boolean {
  return (
    typeof value === 'string' &&
    value.length >= 1 &&
    value.length <= 160 &&
    value === value.trim()
  );
}

export function isValidChannelBuilderCandidateContentFilterPlan(
  plan: ChannelBuilderCandidateContentFilterPlan,
  snapshot: ChannelBuilderFacetSnapshot,
): boolean {
  return isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations(
    channelBuilderIdentityOperations,
    plan,
    snapshot,
  );
}

export function isValidChannelBuilderCandidateContentFilterPlanWithIdentityOperations(
  identityOperations: ChannelBuilderIdentityOperations,
  plan: ChannelBuilderCandidateContentFilterPlan,
  snapshot: ChannelBuilderFacetSnapshot,
): boolean {
  if (
    plan === null ||
    typeof plan !== 'object' ||
    Array.isArray(plan)
  ) {
    return false;
  }
  if (plan.kind === 'none') {
    return (
      hasExactPlainRecordKeys(plan, ['kind', 'contentFilterIdentity']) &&
      plan.contentFilterIdentity === null
    );
  }
  if (
    !filterPattern.test(plan.contentFilterIdentity)
  ) {
    return false;
  }
  if (plan.kind === 'main-index-reference') {
    return (
      hasExactPlainRecordKeys(plan, ['kind', 'contentFilterIdentity', 'facetId']) &&
      /^director:[a-f0-9]{64}$/u.test(plan.facetId) &&
      snapshot.tags.some(
        (tag) =>
          tag.family === 'director' &&
          tag.facetId === plan.facetId &&
          tag.contentFilterIdentity === plan.contentFilterIdentity,
      )
    );
  }
  if (
    plan.kind !== 'inline' ||
    !hasExactPlainRecordKeys(plan, ['kind', 'contentFilterIdentity', 'filters']) ||
    !Array.isArray(plan.filters) ||
    plan.filters.length === 0 ||
    !plan.filters.every(
      (filter) =>
        filter !== null &&
        typeof filter === 'object' &&
        !Array.isArray(filter) &&
        hasExactPlainRecordKeys(filter, ['field', 'operator', 'value']) &&
        typeof filter.value === 'number' &&
        Number.isFinite(filter.value),
    )
  ) {
    return false;
  }
  try {
    return (
      identityOperations.createContentFilterIdentity({
        profileBinding: snapshot.context.profileBinding,
        serverBinding: snapshot.context.serverBinding,
        filters: plan.filters,
      }) === plan.contentFilterIdentity
    );
  } catch {
    return false;
  }
}

export function isValidChannelBuilderFacetSnapshot(
  snapshot: ChannelBuilderFacetSnapshot,
): boolean {
  if (
    snapshot === null ||
    typeof snapshot !== 'object' ||
    Array.isArray(snapshot) ||
    !hasExactPlainRecordKeys(snapshot, [
      'context',
      'libraries',
      'playlists',
      'collections',
      'tags',
      'recentlyAdded',
      'aggregate',
    ]) ||
    !hasExactPlainRecordKeys(snapshot.context, [
      'contextEpoch',
      'profileBinding',
      'serverBinding',
      'librarySetBinding',
    ]) ||
    !Number.isSafeInteger(snapshot.context.contextEpoch) ||
    snapshot.context.contextEpoch < 0 ||
    !bindingPatterns.profile.test(snapshot.context.profileBinding) ||
    !bindingPatterns.server.test(snapshot.context.serverBinding) ||
    !bindingPatterns.librarySet.test(snapshot.context.librarySetBinding) ||
    !Array.isArray(snapshot.libraries) ||
    !Array.isArray(snapshot.playlists) ||
    !Array.isArray(snapshot.collections) ||
    !Array.isArray(snapshot.tags) ||
    !Array.isArray(snapshot.recentlyAdded) ||
    !isValidChannelBuilderFacetSnapshotAggregate(snapshot.aggregate)
  ) {
    return false;
  }
  const total =
    snapshot.playlists.length +
    snapshot.collections.length +
    snapshot.tags.length +
    snapshot.recentlyAdded.length;
  if (total > CHANNEL_BUILDER_MAX_CANDIDATES) return false;
  const libraryTypes = new Map(
    snapshot.libraries.map((library) => [
      library.facetId,
      library.mediaType,
    ]),
  );
  for (const facet of snapshot.libraries) {
    if (
      !hasExactPlainRecordKeys(facet, [
        'facetId',
        'sourceIdentity',
        'title',
        'mediaType',
        'contentCount',
      ]) ||
      !/^library:[a-f0-9]{64}$/u.test(facet.facetId) ||
      !sourcePattern.test(facet.sourceIdentity) ||
      !validSafeTitle(facet.title) ||
      !['movie', 'show'].includes(facet.mediaType) ||
      !validCount(facet.contentCount)
    ) return false;
  }
  for (const facet of snapshot.playlists) {
    if (
      !hasExactPlainRecordKeys(facet, [
        'facetId',
        'sourceIdentity',
        'title',
        'itemCount',
        'durationMs',
      ]) ||
      !/^playlist:[a-f0-9]{64}$/u.test(facet.facetId) ||
      !sourcePattern.test(facet.sourceIdentity) ||
      !validSafeTitle(facet.title) ||
      !validCount(facet.itemCount) ||
      !validCount(facet.durationMs)
    ) return false;
  }
  for (const facet of snapshot.collections) {
    if (
      !hasExactPlainRecordKeys(facet, [
        'facetId',
        'sourceIdentity',
        'libraryFacetId',
        'title',
        'itemCount',
      ]) ||
      !/^collection:[a-f0-9]{64}$/u.test(facet.facetId) ||
      !sourcePattern.test(facet.sourceIdentity) ||
      !/^library:[a-f0-9]{64}$/u.test(facet.libraryFacetId) ||
      !validSafeTitle(facet.title) ||
      !validCount(facet.itemCount)
    ) return false;
  }
  for (const facet of snapshot.tags) {
    const ownsTvPeopleBreadth =
      libraryTypes.get(facet.libraryFacetId) === 'show' &&
      (facet.family === 'actor' || facet.family === 'director');
    if (
      !hasExactPlainRecordKeys(facet, [
        'facetId',
        'sourceIdentity',
        'libraryFacetId',
        'family',
        'displayTitle',
        'itemCount',
        'episodeCount',
        'distinctSeriesCount',
        'semanticGroupIdentity',
        'contentFilterIdentity',
        'yearValue',
      ]) ||
      !facetPattern.test(facet.facetId) ||
      !facet.facetId.startsWith(`${facet.family}:`) ||
      !sourcePattern.test(facet.sourceIdentity) ||
      !/^library:[a-f0-9]{64}$/u.test(facet.libraryFacetId) ||
      !validSafeTitle(facet.displayTitle) ||
      !validCount(facet.itemCount, true) ||
      !validCount(facet.episodeCount, true) ||
      !validCount(facet.distinctSeriesCount, true) ||
      (!ownsTvPeopleBreadth &&
        (facet.episodeCount !== null ||
          facet.distinctSeriesCount !== null))
    ) return false;
    if (facet.family === 'year') {
      if (
        facet.semanticGroupIdentity !== null ||
        facet.contentFilterIdentity !== null ||
        (facet.yearValue !== null &&
          (!Number.isFinite(facet.yearValue) ||
            !Number.isInteger(facet.yearValue)))
      ) return false;
    } else if (
      !groupPattern.test(facet.semanticGroupIdentity) ||
      facet.yearValue !== null ||
      (facet.family === 'director'
        ? !filterPattern.test(facet.contentFilterIdentity)
        : facet.contentFilterIdentity !== null)
    ) return false;
  }
  for (const facet of snapshot.recentlyAdded) {
    if (
      !hasExactPlainRecordKeys(facet, [
        'facetId',
        'sourceIdentity',
        'libraryFacetId',
        'itemCount',
      ]) ||
      !/^recently-added:[a-f0-9]{64}$/u.test(facet.facetId) ||
      !sourcePattern.test(facet.sourceIdentity) ||
      !/^library:[a-f0-9]{64}$/u.test(facet.libraryFacetId) ||
      !validCount(facet.itemCount)
    ) return false;
  }
  return true;
}

export function isValidChannelBuilderFacetSnapshotAggregate(
  aggregate: ChannelBuilderFacetSnapshot['aggregate'],
): boolean {
  if (
    !hasExactPlainRecordKeys(aggregate, [
      'status',
      'warningCodes',
      'omittedMalformedCount',
      'omittedCappedCount',
    ]) ||
    !['ready', 'blocked', 'slow'].includes(aggregate.status) ||
    !Array.isArray(aggregate.warningCodes) ||
    aggregate.warningCodes.length > CHANNEL_BUILDER_FACET_WARNING_CODES.length
  ) {
    return false;
  }
  for (let index = 0; index < aggregate.warningCodes.length; index += 1) {
    const code = aggregate.warningCodes[index];
    if (
      !warningCodeSet.has(code) ||
      (index > 0 && aggregate.warningCodes[index - 1]! >= code)
    ) {
      return false;
    }
  }
  const malformedCode = aggregate.warningCodes.includes(
    'FACET_MALFORMED_ENTRIES_OMITTED',
  );
  if (
    !Number.isSafeInteger(aggregate.omittedMalformedCount) ||
    aggregate.omittedMalformedCount < 0 ||
    aggregate.omittedMalformedCount > CHANNEL_BUILDER_MAX_CANDIDATES ||
    (aggregate.omittedMalformedCount > 0) !== malformedCode
  ) {
    return false;
  }
  const capCode = aggregate.warningCodes.includes('FACET_CAP_REACHED');
  if (aggregate.omittedCappedCount === null) return capCode;
  return (
    Number.isSafeInteger(aggregate.omittedCappedCount) &&
    aggregate.omittedCappedCount >= 0 &&
    aggregate.omittedCappedCount <= CHANNEL_BUILDER_MAX_CANDIDATES &&
    ((aggregate.omittedCappedCount === 0 && !capCode) ||
      (aggregate.omittedCappedCount > 0 && capCode))
  );
}

export function convertFacetWarnings(
  aggregate: ChannelBuilderFacetSnapshot['aggregate'],
): readonly ChannelSetupWarning[] {
  if (!isValidChannelBuilderFacetSnapshotAggregate(aggregate)) {
    throw new TypeError('Invalid channel builder facet warning aggregate.');
  }
  return aggregate.warningCodes.map((code) => ({
    code,
    phase: 'discovery' as const,
    strategy: null,
    affectedCount:
      code === 'FACET_MALFORMED_ENTRIES_OMITTED'
        ? aggregate.omittedMalformedCount
        : code === 'FACET_CAP_REACHED'
          ? aggregate.omittedCappedCount
          : null,
  }));
}

export function sortAndDedupeChannelSetupWarnings(
  warnings: readonly ChannelSetupWarning[],
): readonly ChannelSetupWarning[] {
  const grouped = new Map<string, ChannelSetupWarning[]>();
  for (const warning of warnings) {
    const key = `${warning.code}\u0000${warning.phase}\u0000${warning.strategy ?? ''}`;
    const current = grouped.get(key) ?? [];
    current.push(warning);
    grouped.set(key, current);
  }
  const merged = [...grouped.values()].map((group) => {
    const first = group[0]!;
    const affectedCount = group.some((warning) => warning.affectedCount === null)
      ? null
      : group.reduce((total, warning) => {
          const next = total + (warning.affectedCount ?? 0);
          if (!Number.isSafeInteger(next)) {
            throw new RangeError('Channel builder warning count overflow.');
          }
          return next;
        }, 0);
    return { ...first, affectedCount };
  });
  merged.sort((left, right) => {
    const code = compareLexical(left.code, right.code);
    if (code !== 0) return code;
    const phase = compareLexical(left.phase, right.phase);
    if (phase !== 0) return phase;
    return compareLexical(left.strategy ?? '', right.strategy ?? '');
  });
  return merged.slice(0, CHANNEL_BUILDER_MAX_WARNINGS);
}

export function strategyWarning(
  code: 'MIN_ITEMS_SKIPPED' | 'MAX_CHANNELS_REACHED',
  strategy: ChannelBuilderStrategyKey,
  affectedCount: number,
): ChannelSetupWarning {
  return { code, phase: 'planning', strategy, affectedCount };
}

function compareLexical(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
