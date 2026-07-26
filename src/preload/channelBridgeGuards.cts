import {
  CHANNEL_SETUP_ERROR_CODES,
  CHANNEL_SETUP_OPERATIONS,
  CHANNEL_SETUP_STATUS_VALUES,
  type ChannelSetupAcceptedOperation,
  type ChannelSetupCancelResult,
  type ChannelSetupIpcResult,
  type ChannelSetupOperation,
  type ChannelSetupOperationName,
  type ChannelSetupOperationResult,
  type ChannelSetupSummary,
  type NormalizedChannelSetupConfig,
} from '../contracts/channel.js';
import { normalizeChannelSetupConfig } from '../domain/channelBuilder/config.js';
import { containsChannelBuilderCredentialMarker } from '../domain/channelBuilder/types.js';

const PLAN_ID_PATTERN = /^channel-builder-plan-[a-f0-9]{32}$/u;
const OPERATION_ID_PATTERN = /^channel-builder-(?:review|apply)-[a-f0-9]{32}$/u;
const PUBLIC_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const STRATEGY_KEYS = [
  'collections', 'playlists', 'genres', 'directors', 'decades',
  'recentlyAdded', 'studios', 'actors',
] as const;
const WARNING_CODES = [
  'FACET_UNAVAILABLE', 'FACET_PARTIAL_FAILURE', 'FACET_DISCOVERY_TIMEOUT',
  'FACET_EMPTY', 'FACET_CAP_REACHED', 'FACET_MALFORMED_ENTRIES_OMITTED',
  'TV_PEOPLE_METADATA_INCOMPLETE',
  'EXISTING_SOURCE_UNMATCHABLE', 'MIN_ITEMS_SKIPPED', 'MAX_CHANNELS_REACHED',
  'PLAN_EMPTY', 'MATERIALIZATION_SKIPPED', 'GUIDE_REFRESH_FAILED',
] as const;
const WARNING_PHASES = ['discovery', 'planning', 'materialization', 'refresh'] as const;
const FORBIDDEN_KEYS = new Set([
  'rawpayload', 'rawplexpayload', 'headers', 'header', 'authheaders', 'authheader',
  'rawauthheaders', 'token', 'accesstoken', 'refreshtoken', 'path', 'filepath',
  'localpath', 'url', 'uri', 'endpointurl', 'baseurl', 'tokenizedurl', 'serveruri',
  'connectionuri', 'apppath', 'userdatapath', 'filesystempath',
  'persistencefilepath', 'storedchanneldata', 'credential', 'secret', 'nativehandle',
]);

export type ChannelSetupPreloadRequest<T> =
  | Readonly<{ ok: true; requestId: string; payload: T }>
  | Readonly<{ ok: false; result: ChannelSetupIpcResult<never> }>;

export function createChannelSetupEmptyRequest(): {
  requestId: string;
  payload: Record<string, never>;
} {
  return { requestId: issueRequestId('status'), payload: {} };
}

export function createChannelSetupStartReviewRequest(input: {
  config: NormalizedChannelSetupConfig;
}): ChannelSetupPreloadRequest<{ config: NormalizedChannelSetupConfig }> {
  const requestId = issueRequestId('review');
  if (!isPlainRecord(input) || !hasExactKeys(input, ['config']) || !isPlainRecord(input.config)) {
    return invalidRequest(requestId, 'startReview');
  }
  const normalized = normalizeChannelSetupConfig(input.config, {
    serverId: typeof input.config.serverId === 'string' ? input.config.serverId : '',
    selectedLibraryIds: Array.isArray(input.config.selectedLibraryIds)
      ? input.config.selectedLibraryIds.filter((value): value is string => typeof value === 'string')
      : [],
  });
  return normalized.ok
    ? { ok: true, requestId, payload: { config: normalized.config } }
    : invalidRequest(requestId, 'startReview');
}

export function createChannelSetupStartApplyRequest(input: {
  planId: string;
  confirmReplace: boolean;
}): ChannelSetupPreloadRequest<{ planId: string; confirmReplace: boolean }> {
  const requestId = issueRequestId('apply');
  return isPlainRecord(input) &&
    hasExactKeys(input, ['planId', 'confirmReplace']) &&
    typeof input.planId === 'string' &&
    PLAN_ID_PATTERN.test(input.planId) &&
    typeof input.confirmReplace === 'boolean'
    ? { ok: true, requestId, payload: { ...input } }
    : invalidRequest(requestId, 'startApply');
}

export function createChannelSetupOperationRequest(
  input: { operationId: string },
  operation: 'getOperation' | 'cancel',
): ChannelSetupPreloadRequest<{ operationId: string }> {
  const requestId = issueRequestId(operation);
  return isPlainRecord(input) &&
    hasExactKeys(input, ['operationId']) &&
    typeof input.operationId === 'string' &&
    OPERATION_ID_PATTERN.test(input.operationId)
    ? { ok: true, requestId, payload: { operationId: input.operationId } }
    : invalidRequest(requestId, operation);
}

export function isChannelSetupSummaryResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupIpcResult<ChannelSetupSummary> {
  return isResult(value, requestId, isChannelSetupSummary);
}

export function isChannelSetupAcceptedResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupIpcResult<ChannelSetupAcceptedOperation> {
  return isResult(
    value,
    requestId,
    (result): result is ChannelSetupAcceptedOperation =>
      isPlainRecord(result) &&
      hasExactKeys(result, ['accepted', 'operation']) &&
      result.accepted === true &&
      isChannelSetupOperation(result.operation),
  );
}

export function isChannelSetupOperationResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupIpcResult<ChannelSetupOperationResult> {
  return isResult(
    value,
    requestId,
    (result): result is ChannelSetupOperationResult =>
      isPlainRecord(result) &&
      hasExactKeys(result, ['operation']) &&
      isChannelSetupOperation(result.operation),
  );
}

export function isChannelSetupCancelResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupIpcResult<ChannelSetupCancelResult> {
  return isResult(
    value,
    requestId,
    (result): result is ChannelSetupCancelResult =>
      isPlainRecord(result) &&
      hasExactKeys(result, ['accepted', 'reason', 'operation']) &&
      typeof result.accepted === 'boolean' &&
      (
        result.reason === null ||
        result.reason === 'already-terminal' ||
        result.reason === 'commit-started'
      ) &&
      isChannelSetupOperation(result.operation),
  );
}

export function channelSetupValidationFailure<T>(
  requestId: string,
  operation: ChannelSetupOperationName,
): ChannelSetupIpcResult<T> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'CHANNEL_VALIDATION_FAILED',
      message: 'Channel setup result is invalid.',
      retryable: false,
      recoverable: true,
      operation,
    },
  };
}

function isResult<T>(
  value: unknown,
  requestId: string,
  isValue: (input: unknown) => input is T,
): value is ChannelSetupIpcResult<T> {
  if (!isPlainRecord(value) || hasForbiddenField(value)) return false;
  if (value.ok === true) {
    return hasExactKeys(value, ['ok', 'requestId', 'value']) &&
      value.requestId === requestId &&
      isValue(value.value);
  }
  return value.ok === false &&
    hasExactKeys(value, ['ok', 'requestId', 'error']) &&
    value.requestId === requestId &&
    isChannelSetupError(value.error);
}

function isChannelSetupSummary(value: unknown): value is ChannelSetupSummary {
  if (!isPlainRecord(value) ||
    !hasExactKeys(value, [
      'status', 'lineupRevision', 'channelCount', 'currentChannelId',
      'currentChannelNumber', 'currentChannelName', 'channelNumbers', 'channels',
      'builder', 'updatedAtMs', 'recovery',
    ]) ||
    !includes(CHANNEL_SETUP_STATUS_VALUES, value.status) ||
    !isCount(value.lineupRevision) ||
    !isBoundedCount(value.channelCount, 500) ||
    !isNullableString(value.currentChannelId, 120) ||
    (value.currentChannelNumber !== null && !isChannelNumber(value.currentChannelNumber)) ||
    !isNullableString(value.currentChannelName, 160) ||
    !Array.isArray(value.channelNumbers) ||
    !value.channelNumbers.every(isChannelNumber) ||
    !Array.isArray(value.channels) ||
    value.channels.length !== value.channelCount ||
    !value.channels.every(isChannelSummary) ||
    !isBuilderSummary(value.builder) ||
    !isTimestamp(value.updatedAtMs) ||
    !isPlainRecord(value.recovery) ||
    !hasExactKeys(value.recovery, ['loaded', 'repaired']) ||
    typeof value.recovery.loaded !== 'boolean' ||
    typeof value.recovery.repaired !== 'boolean' ||
    (value.recovery.repaired && !value.recovery.loaded)
  ) return false;
  const channels = value.channels as Array<Record<string, unknown>>;
  if (
    value.channelNumbers.length !== channels.length ||
    value.channelNumbers.some((number, index) => number !== channels[index]?.number) ||
    new Set(value.channelNumbers).size !== value.channelNumbers.length
  ) return false;
  const builder = value.builder as Record<string, unknown>;
  if (
    (value.status === 'not-configured' && builder.completion !== 'unknown') ||
    (value.status === 'configured' && builder.completion !== 'complete')
  ) return false;
  const currentValues = [
    value.currentChannelId,
    value.currentChannelNumber,
    value.currentChannelName,
  ];
  if (currentValues.every((entry) => entry === null)) return true;
  if (currentValues.some((entry) => entry === null)) return false;
  return channels.some((channel) =>
    channel.id === value.currentChannelId &&
    channel.number === value.currentChannelNumber &&
    channel.name === value.currentChannelName);
}

function isChannelSummary(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasExactKeys(value, [
      'id', 'number', 'name', 'sourceLibraryId', 'sourceLibraryName', 'itemCount',
    ]) &&
    isNullableString(value.id, 120) && value.id !== null &&
    isChannelNumber(value.number) &&
    typeof value.name === 'string' && value.name.length > 0 && value.name.length <= 160 &&
    isNullableString(value.sourceLibraryId, 120) &&
    isNullableString(value.sourceLibraryName, 160) &&
    isFiniteNonNegative(value.itemCount);
}

function isBuilderSummary(value: unknown): boolean {
  if (!isPlainRecord(value) ||
    !hasExactKeys(value, ['completion', 'normalizedConfig', 'completedAtMs'])) return false;
  if (value.completion === 'unknown') {
    return value.normalizedConfig === null && value.completedAtMs === null;
  }
  return value.completion === 'complete' &&
    isPlainRecord(value.normalizedConfig) &&
    isFiniteNonNegative(value.completedAtMs);
}

function isChannelSetupOperation(value: unknown): value is ChannelSetupOperation {
  if (!isPlainRecord(value) || hasForbiddenField(value)) return false;
  if (!hasExactKeys(value, [
    'operationId', 'kind', 'state', 'phase', 'startedAtMs', 'updatedAtMs',
    'progress', 'result', 'error',
  ])) return false;
  if (
    typeof value.operationId !== 'string' ||
    !OPERATION_ID_PATTERN.test(value.operationId) ||
    (value.kind !== 'review' && value.kind !== 'apply') ||
    !value.operationId.startsWith(`channel-builder-${value.kind}-`) ||
    !isTimestamp(value.startedAtMs) ||
    !isTimestamp(value.updatedAtMs) ||
    value.updatedAtMs < value.startedAtMs ||
    !isProgress(value.progress)
  ) return false;
  if (value.state === 'failed') {
    return value.phase === 'done' &&
      isUnitProgress(value.progress, 1) &&
      value.result === null &&
      isChannelSetupError(value.error);
  }
  if (value.state === 'canceled') {
    return value.phase === 'done' && isUnitProgress(value.progress, 1) &&
      value.error === null &&
      isPlainRecord(value.result) && hasExactKeys(value.result, ['kind']) &&
      value.result.kind === 'canceled';
  }
  if (value.state === 'review-ready') {
    return value.kind === 'review' && value.phase === 'review-ready' &&
      isUnitProgress(value.progress, 1) &&
      value.error === null && isReviewResult(value.result);
  }
  if (value.state === 'succeeded') {
    return value.kind === 'apply' && value.phase === 'done' &&
      isUnitProgress(value.progress, 1) &&
      value.error === null && isApplyResult(value.result);
  }
  if (
    value.state !== 'queued' &&
    value.state !== 'running' &&
    value.state !== 'canceling'
  ) return false;
  if (value.result !== null || value.error !== null) return false;
  if (value.kind === 'review') {
    if (value.state === 'queued') {
      return value.phase === 'discover-facets' &&
        value.progress.total === null &&
        value.progress.completed === 0;
    }
    if (value.phase === 'discover-facets') return value.progress.total === null;
    return value.phase === 'plan' && isUnitProgress(value.progress);
  }
  if (value.state === 'queued' || value.state === 'canceling') {
    return value.phase === 'materialize' && value.progress.total !== null;
  }
  if (value.phase === 'materialize') return value.progress.total !== null;
  return (
    value.phase === 'persist' || value.phase === 'refresh-guide'
  ) && isUnitProgress(value.progress);
}

function isReviewResult(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasExactKeys(value, [
      'kind', 'planId', 'contextEpoch', 'lineupRevision', 'status', 'diff',
      'warnings', 'reachedCap',
    ]) &&
    value.kind === 'review' &&
    (value.planId === null || (typeof value.planId === 'string' && PLAN_ID_PATTERN.test(value.planId))) &&
    isCount(value.contextEpoch) &&
    isCount(value.lineupRevision) &&
    (value.status === 'ready' || value.status === 'slow' || value.status === 'blocked') &&
    (
      (value.status === 'blocked' && value.planId === null) ||
      (value.status !== 'blocked' && value.planId !== null)
    ) &&
    isReviewDiff(value.diff) &&
    isWarnings(value.warnings) &&
    typeof value.reachedCap === 'boolean';
}

function isApplyResult(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasExactKeys(value, ['kind', 'commit', 'summary', 'guideRefresh']) &&
    value.kind === 'apply' &&
    value.commit === 'committed' &&
    isApplySummary(value.summary) &&
    (value.guideRefresh === 'completed' || value.guideRefresh === 'failed');
}

function isReviewDiff(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasExactKeys(value, ['summary', 'samples']) &&
    isPlainRecord(value.summary) &&
    hasExactKeys(value.summary, ['created', 'removed', 'unchanged']) &&
    isBoundedCount(value.summary.created, 50_000) &&
    isBoundedCount(value.summary.removed, 50_000) &&
    isBoundedCount(value.summary.unchanged, 50_000) &&
    isPlainRecord(value.samples) &&
    hasExactKeys(value.samples, ['created', 'removed', 'unchanged']) &&
    isDisplaySamples(value.samples.created) &&
    isDisplaySamples(value.samples.removed) &&
    isDisplaySamples(value.samples.unchanged);
}

function isDisplaySamples(value: unknown): boolean {
  return Array.isArray(value) && value.length <= 6 &&
    value.every((entry) =>
      typeof entry === 'string' && entry.length >= 1 && entry.length <= 160);
}

function isWarnings(value: unknown): boolean {
  return Array.isArray(value) && value.length <= 50 && value.every((warning) =>
    isPlainRecord(warning) &&
    hasExactKeys(warning, ['code', 'phase', 'strategy', 'affectedCount']) &&
    includes(WARNING_CODES, warning.code) &&
    includes(WARNING_PHASES, warning.phase) &&
    (warning.strategy === null || includes(STRATEGY_KEYS, warning.strategy)) &&
    (warning.affectedCount === null || isBoundedCount(warning.affectedCount, 50_000)));
}

function isApplySummary(value: unknown): boolean {
  if (!isPlainRecord(value) || !hasExactKeys(value, [
    'created', 'removed', 'unchanged', 'skipped', 'finalChannelCount',
    'reachedMaxChannels', 'watchChannelId', 'byStrategy', 'warnings',
  ])) return false;
  if (
    !isBoundedCount(value.created, 50_000) ||
    !isBoundedCount(value.removed, 50_000) ||
    !isBoundedCount(value.unchanged, 50_000) ||
    !isBoundedCount(value.skipped, 50_000) ||
    !isBoundedCount(value.finalChannelCount, 500) ||
    typeof value.reachedMaxChannels !== 'boolean' ||
    (value.watchChannelId !== null &&
      (typeof value.watchChannelId !== 'string' ||
        !PUBLIC_ID_PATTERN.test(value.watchChannelId))) ||
    !isWarnings(value.warnings) ||
    !isPlainRecord(value.byStrategy) ||
    !hasExactKeys(value.byStrategy, STRATEGY_KEYS)
  ) return false;
  const byStrategy = value.byStrategy as Record<string, unknown>;
  return STRATEGY_KEYS.every((strategy) => {
    const entry = byStrategy[strategy];
    return isPlainRecord(entry) &&
      hasExactKeys(entry, ['created', 'skipped']) &&
      isBoundedCount(entry.created, 50_000) &&
      isBoundedCount(entry.skipped, 50_000);
  });
}

function isProgress(value: unknown): value is Record<string, unknown> {
  return isPlainRecord(value) &&
    hasExactKeys(value, ['completed', 'total']) &&
    isBoundedCount(value.completed, 50_000) &&
    (value.total === null || isBoundedCount(value.total, 50_000)) &&
    (value.total === null || (value.completed as number) <= (value.total as number));
}

function isUnitProgress(
  value: Record<string, unknown>,
  completed?: 0 | 1,
): boolean {
  return value.total === 1 &&
    (value.completed === 0 || value.completed === 1) &&
    (completed === undefined || value.completed === completed);
}

function isTimestamp(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function isChannelSetupError(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasExactKeys(value, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    includes(CHANNEL_SETUP_ERROR_CODES, value.code) &&
    typeof value.message === 'string' &&
    value.message.length >= 1 &&
    value.message.length <= 160 &&
    !containsChannelBuilderCredentialMarker(value.message) &&
    typeof value.retryable === 'boolean' &&
    typeof value.recoverable === 'boolean' &&
    includes(CHANNEL_SETUP_OPERATIONS, value.operation);
}

function invalidRequest(
  requestId: string,
  operation: ChannelSetupOperationName,
): ChannelSetupPreloadRequest<never> {
  return { ok: false, result: channelSetupValidationFailure(requestId, operation) };
}

function issueRequestId(operation: string): string {
  return `channel-setup-${operation}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasExactKeys(value: object, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const sorted = [...expected].sort();
  return actual.length === sorted.length &&
    actual.every((key, index) => key === sorted[index]);
}

function hasForbiddenField(value: unknown, seen = new Set<object>()): boolean {
  if (value === null || typeof value !== 'object') return false;
  if (seen.has(value)) return true;
  seen.add(value);
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_KEYS.has(key.toLowerCase()) || hasForbiddenField(child, seen)) return true;
  }
  return false;
}

function includes(values: readonly string[], value: unknown): boolean {
  return typeof value === 'string' && values.includes(value);
}

function isCount(value: unknown): boolean {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function isBoundedCount(value: unknown, maximum: number): boolean {
  return isCount(value) && (value as number) <= maximum;
}

function isFiniteNonNegative(value: unknown): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function isChannelNumber(value: unknown): boolean {
  return Number.isInteger(value) && (value as number) >= 1 && (value as number) <= 500;
}

function isNullableString(value: unknown, maxLength: number): boolean {
  return value === null || (typeof value === 'string' && value.length <= maxLength);
}
