import type {
  ChannelSetupBuildProgress,
  ChannelSetupBuildResult,
  ChannelSetupCancelResult,
  ChannelSetupCommitMode,
  ChannelSetupConfig,
  ChannelSetupConfigDraft,
  ChannelSetupOperation,
  ChannelSetupIpcResult,
  ChannelSetupPreview,
  ChannelSetupProgressEnvelope,
  ChannelSetupRecordSummary,
  ChannelSetupReview,
  ChannelSetupSummary,
  ChannelSetupWorkflowError,
  ChannelSetupWorkflowIpcResult,
} from '../contracts/channel.js';

export const CHANNEL_SETUP_ERROR_CODES = [
  'CHANNEL_UNAUTHORIZED',
  'CHANNEL_VALIDATION_FAILED',
  'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
  'CHANNEL_PLEX_REQUIRED',
  'CHANNEL_STORAGE_UNAVAILABLE',
  'CHANNEL_STORAGE_CORRUPT',
  'CHANNEL_STORAGE_UNSUPPORTED_VERSION',
  'CHANNEL_BUILD_ACTIVE',
  'CHANNEL_BUILD_ID_REUSED',
  'CHANNEL_BUILD_ID_CAPACITY',
  'CHANNEL_BUILD_CANCELED',
  'CHANNEL_BUILD_TOO_LATE',
  'CHANNEL_UNKNOWN',
] as const;
export const CHANNEL_SETUP_STATUS_VALUES = ['not-configured', 'configured', 'recovering', 'recovery-failed'] as const;
export const CHANNEL_SETUP_RUNTIME_ERROR_CODES = [
  'CHANNEL_UNAUTHORIZED', 'CHANNEL_VALIDATION_FAILED', 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
  'CHANNEL_PLEX_REQUIRED', 'CHANNEL_STORAGE_UNAVAILABLE', 'CHANNEL_STORAGE_CORRUPT', 'CHANNEL_UNKNOWN',
] as const;
export const CHANNEL_SETUP_OPERATIONS = [
  'getStatus', 'getRecord', 'preview', 'review', 'build', 'cancelBuild', 'commit',
] as const;
export const CHANNEL_SETUP_COMMIT_MODES = ['append', 'replace', 'merge'] as const;
export const CHANNEL_SETUP_STRATEGY_KEYS = [
  'playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors',
] as const;
export const CHANNEL_SETUP_PROGRESS_TASKS = [
  'fetch_playlists', 'fetch_collections', 'fetch_facets', 'scan_library_items', 'build_pending',
  'create_channels', 'apply_channels', 'refresh_guide', 'done',
] as const;
export const CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS = [
  'rawPayload', 'rawPlexPayload', 'headers', 'header', 'authHeaders', 'authHeader', 'rawAuthHeaders',
  'token', 'accessToken', 'refreshToken', 'path', 'filePath', 'localPath', 'url', 'uri', 'endpointUrl',
  'baseUrl', 'tokenizedUrl', 'serverUri', 'connectionUri', 'appPath', 'userDataPath', 'filesystemPath',
  'persistenceFilePath', 'storedChannelData', 'credential', 'secret', 'nativeHandle',
] as const;

const FORBIDDEN_KEYS = new Set(CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS.map(normalizeKey));
const ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const UNSAFE_STRING_PATTERNS = [
  /https?:\/\//iu, /file:\/\//iu, /\b[A-Za-z]:[\\/]/u, /\\\\[A-Za-z0-9._-]+[\\/]/u,
  /\b(?:bearer|token|authorization|headers?)\s*[:=]/iu,
  /\b(?:accessToken|refreshToken|x-plex-token)\b/iu,
] as const;

type RequestFactory = (prefix: string) => string;
type GuardedRequest<T> =
  | { ok: true; requestId: string; payload: T }
  | { ok: false; result: ChannelSetupWorkflowIpcResult<never> };

export function createLegacyChannelSetupEmptyRequest(createRequestId: RequestFactory): {
  requestId: string; payload: Record<string, never>;
} {
  return { requestId: createRequestId('channel-setup-status'), payload: {} };
}

export function createLegacyChannelSetupCommitRequest(
  input: unknown,
  createRequestId: RequestFactory,
): { ok: true; requestId: string; payload: { mode: ChannelSetupCommitMode; sectionIds: readonly string[]; confirmReplace?: boolean } } |
  { ok: false; result: ChannelSetupIpcResult<ChannelSetupSummary> } {
  const requestId = createRequestId('channel-setup-commit');
  if (!isPlainRecord(input) || !hasExactShape(input, ['mode', 'sectionIds'], ['confirmReplace']) ||
    (input.mode !== 'append' && input.mode !== 'replace') || !isSelectedIds(input.sectionIds) ||
    (input.confirmReplace !== undefined && typeof input.confirmReplace !== 'boolean')) {
    return { ok: false, result: legacyValidationFailure(requestId, 'commit', 'Channel setup request payload is invalid.') };
  }
  return { ok: true, requestId, payload: {
    mode: input.mode, sectionIds: [...input.sectionIds],
    ...(input.confirmReplace === undefined ? {} : { confirmReplace: input.confirmReplace }),
  } };
}

export function isLegacyChannelSetupResult(
  value: unknown,
  requestId: string,
  operation: 'getStatus' | 'commit',
): value is ChannelSetupIpcResult<ChannelSetupSummary> {
  if (!isPlainRecord(value) || hasForbidden(value) || value.requestId !== requestId) return false;
  if (value.ok === true) return hasExactShape(value, ['ok', 'requestId', 'value']) && isLegacySummary(value.value);
  return value.ok === false && hasExactShape(value, ['ok', 'requestId', 'error']) &&
    isPlainRecord(value.error) && hasExactShape(value.error, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    isStringInSet(value.error.code, CHANNEL_SETUP_RUNTIME_ERROR_CODES) && isSafeText(value.error.message, 1, 160) &&
    typeof value.error.retryable === 'boolean' && typeof value.error.recoverable === 'boolean' && value.error.operation === operation;
}

export function legacyValidationFailure(
  requestId: string,
  operation: 'getStatus' | 'commit',
  message = 'Channel setup result is invalid.',
): ChannelSetupIpcResult<ChannelSetupSummary> {
  return { ok: false, requestId, error: {
    code: 'CHANNEL_VALIDATION_FAILED', message, retryable: false, recoverable: false, operation,
  } };
}

export function createChannelSetupEmptyRequest(
  operation: Extract<ChannelSetupOperation, 'getRecord'>,
  createRequestId: RequestFactory,
): GuardedRequest<Record<string, never>> {
  return { ok: true, requestId: createRequestId(`channel-setup-${operation}`), payload: {} };
}

export function createChannelSetupConfigRequest(
  operation: Extract<ChannelSetupOperation, 'preview' | 'review'>,
  input: unknown,
  createRequestId: RequestFactory,
): GuardedRequest<{ config: ChannelSetupConfigDraft }> {
  const requestId = createRequestId(`channel-setup-${operation}`);
  return isConfigDraft(input)
    ? { ok: true, requestId, payload: { config: cloneConfigDraft(input) } }
    : { ok: false, result: channelSetupValidationFailure(requestId, operation, 'Channel setup request payload is invalid.') };
}

export function createChannelSetupBuildRequest(
  input: unknown,
  createRequestId: RequestFactory,
): GuardedRequest<{ buildId: string; config: ChannelSetupConfigDraft; confirmReplace: boolean }> {
  const requestId = createRequestId('channel-setup-build');
  if (!isPlainRecord(input) || !hasExactShape(input, ['buildId', 'config', 'confirmReplace']) ||
    !isSafeId(input.buildId) || !isConfigDraft(input.config) || typeof input.confirmReplace !== 'boolean') {
    return { ok: false, result: channelSetupValidationFailure(requestId, 'build', 'Channel setup request payload is invalid.') };
  }
  return { ok: true, requestId, payload: {
    buildId: input.buildId,
    config: cloneConfigDraft(input.config),
    confirmReplace: input.confirmReplace,
  } };
}

export function createChannelSetupCancelRequest(
  input: unknown,
  createRequestId: RequestFactory,
): GuardedRequest<{ buildId: string }> {
  const requestId = createRequestId('channel-setup-cancel');
  if (!isPlainRecord(input) || !hasExactShape(input, ['buildId']) || !isSafeId(input.buildId)) {
    return { ok: false, result: channelSetupValidationFailure(requestId, 'cancelBuild', 'Channel setup request payload is invalid.') };
  }
  return { ok: true, requestId, payload: { buildId: input.buildId } };
}

export function isChannelSetupRecordResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupWorkflowIpcResult<ChannelSetupRecordSummary> {
  return isWorkflowResult(value, requestId, 'getRecord', isRecordSummary);
}

export function isChannelSetupPreviewResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupWorkflowIpcResult<ChannelSetupPreview> {
  return isWorkflowResult(value, requestId, 'preview', isPreview);
}

export function isChannelSetupReviewResult(
  value: unknown,
  requestId: string,
): value is ChannelSetupWorkflowIpcResult<ChannelSetupReview> {
  return isWorkflowResult(value, requestId, 'review', isReview);
}

export function isChannelSetupBuildResult(
  value: unknown,
  requestId: string,
  buildId?: string,
): value is ChannelSetupWorkflowIpcResult<ChannelSetupBuildResult> {
  return isWorkflowResult(value, requestId, 'build', (candidate): candidate is ChannelSetupBuildResult =>
    isBuildResult(candidate) && (buildId === undefined || candidate.buildId === buildId));
}

export function isChannelSetupCancelResult(
  value: unknown,
  requestId: string,
  buildId?: string,
): value is ChannelSetupWorkflowIpcResult<ChannelSetupCancelResult> {
  return isWorkflowResult(value, requestId, 'cancelBuild', (candidate): candidate is ChannelSetupCancelResult =>
    isCancelResult(candidate) && (buildId === undefined || candidate.buildId === buildId));
}

export function isChannelSetupProgressEnvelope(
  value: unknown,
  buildId: string,
  buildRequestId: string,
): value is ChannelSetupProgressEnvelope {
  return isPlainRecord(value) && !hasForbidden(value) &&
    hasExactShape(value, ['buildId', 'buildRequestId', 'sequence', 'progress']) &&
    value.buildId === buildId && value.buildRequestId === buildRequestId &&
    isInteger(value.sequence, 1) && isProgress(value.progress);
}

export function channelSetupValidationFailure<T>(
  requestId: string,
  operation: ChannelSetupOperation,
  message = 'Channel setup result is invalid.',
): ChannelSetupWorkflowIpcResult<T> {
  return { ok: false, requestId, error: {
    code: 'CHANNEL_VALIDATION_FAILED', message, retryable: false, recoverable: false, operation,
  } };
}

function isWorkflowResult<T>(
  value: unknown,
  requestId: string,
  operation: ChannelSetupOperation,
  isValue: (candidate: unknown) => candidate is T,
): value is ChannelSetupWorkflowIpcResult<T> {
  if (!isPlainRecord(value) || hasForbidden(value) || value.requestId !== requestId) return false;
  if (value.ok === true) return hasExactShape(value, ['ok', 'requestId', 'value']) && isValue(value.value);
  return value.ok === false && hasExactShape(value, ['ok', 'requestId', 'error']) &&
    isWorkflowError(value.error, operation);
}

function isWorkflowError(value: unknown, operation: ChannelSetupOperation): value is ChannelSetupWorkflowError {
  return isPlainRecord(value) && hasExactShape(value, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    isStringInSet(value.code, CHANNEL_SETUP_ERROR_CODES) && isSafeText(value.message, 1, 160) &&
    typeof value.retryable === 'boolean' && typeof value.recoverable === 'boolean' && value.operation === operation;
}

function isLegacySummary(value: unknown): value is ChannelSetupSummary {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, [
    'status', 'channelCount', 'currentChannelId', 'currentChannelNumber', 'currentChannelName',
    'channelNumbers', 'channels', 'updatedAtMs', 'recovery',
  ]) && ['not-configured', 'configured', 'recovering', 'recovery-failed'].includes(String(value.status)) &&
    isInteger(value.channelCount, 0) && (value.currentChannelId === null || isSafeId(value.currentChannelId)) &&
    (value.currentChannelNumber === null || isInteger(value.currentChannelNumber, 1, 500)) &&
    (value.currentChannelName === null || isSafeText(value.currentChannelName)) &&
    Array.isArray(value.channelNumbers) && value.channelNumbers.every((number) => isInteger(number, 1, 500)) &&
    Array.isArray(value.channels) && value.channels.every(isLegacyChannelSummary) && isInteger(value.updatedAtMs, 0) &&
    isPlainRecord(value.recovery) && hasExactShape(value.recovery, ['loaded', 'repaired']) &&
    typeof value.recovery.loaded === 'boolean' && typeof value.recovery.repaired === 'boolean';
}

function isLegacyChannelSummary(value: unknown): boolean {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, [
    'id', 'number', 'name', 'sourceLibraryId', 'sourceLibraryName', 'itemCount',
  ]) && isSafeId(value.id) && isInteger(value.number, 1, 500) && isSafeText(value.name) &&
    (value.sourceLibraryId === null || isSafeId(value.sourceLibraryId)) &&
    (value.sourceLibraryName === null || isSafeText(value.sourceLibraryName)) && isInteger(value.itemCount, 0);
}

function isRecordSummary(value: unknown): value is ChannelSetupRecordSummary {
  if (!isPlainRecord(value) || hasForbidden(value) || typeof value.status !== 'string') return false;
  if (value.status === 'ready') return hasExactShape(value, ['status', 'config', 'createdAtMs', 'updatedAtMs']) &&
    isConfig(value.config) && isInteger(value.createdAtMs, 0) && isInteger(value.updatedAtMs, 0);
  return ['missing', 'corrupt', 'unsupported-version', 'unavailable'].includes(value.status) &&
    hasExactShape(value, ['status']);
}

function isPreview(value: unknown): value is ChannelSetupPreview {
  if (!isPlainRecord(value) || hasForbidden(value) ||
    !hasExactShape(value, [
      'status', 'config', 'estimates', 'eligibleGeneratedCount', 'selectedGeneratedCount',
      'droppedByMinItemsCount', 'droppedByPlanCapCount', 'reachedMaxChannels', 'warnings',
    ], ['message', 'failureReason'])) return false;
  return (value.status === 'ready' || value.status === 'blocked' || value.status === 'slow') &&
    isConfig(value.config) && isEstimates(value.estimates) &&
    isInteger(value.eligibleGeneratedCount, 0) && isInteger(value.selectedGeneratedCount, 0) &&
    isInteger(value.droppedByMinItemsCount, 0) && isInteger(value.droppedByPlanCapCount, 0) &&
    typeof value.reachedMaxChannels === 'boolean' && isSafeTextArray(value.warnings) &&
    (value.message === undefined || isSafeText(value.message, 1, 160)) &&
    (value.failureReason === undefined || ['unsupported', 'empty', 'timeout', 'error', 'transient'].includes(String(value.failureReason)));
}

function isReview(value: unknown): value is ChannelSetupReview {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, ['preview', 'diff']) &&
    isPreview(value.preview) && isPlainRecord(value.diff) && hasExactShape(value.diff, ['summary', 'samples']) &&
    isDiffSummary(value.diff.summary) && isDiffSamples(value.diff.samples);
}

function isDiffSummary(value: unknown): boolean {
  return isPlainRecord(value) && hasExactShape(value, ['created', 'removed', 'unchanged']) &&
    isInteger(value.created, 0) && isInteger(value.removed, 0) && isInteger(value.unchanged, 0);
}

function isDiffSamples(value: unknown): boolean {
  return isPlainRecord(value) && hasExactShape(value, ['created', 'removed', 'unchanged']) &&
    isSafeTextArray(value.created) && isSafeTextArray(value.removed) && isSafeTextArray(value.unchanged);
}

function isBuildResult(value: unknown): value is ChannelSetupBuildResult {
  if (!isPlainRecord(value) || hasForbidden(value) || !isSafeId(value.buildId) || !isBuildCounts(value.counts) ||
    !isSafeTextArray(value.warnings)) return false;
  if (value.kind === 'canceled') return hasExactShape(value, ['kind', 'buildId', 'counts', 'warnings']);
  if (value.kind === 'failed') return hasExactShape(value, ['kind', 'buildId', 'counts', 'warnings', 'error']) &&
    isWorkflowError(value.error, 'build');
  return (value.kind === 'committed' || value.kind === 'committed-with-record-warning') &&
    hasExactShape(value, ['kind', 'buildId', 'counts', 'warnings', 'guideRefresh']) && isGuideRefresh(value.guideRefresh);
}

function isBuildCounts(value: unknown): boolean {
  const countKeys = ['plannedGeneratedCount', 'createdCount', 'updatedCount', 'preservedCount', 'removedCount', 'skippedCount', 'errorCount'];
  return isPlainRecord(value) && hasExactShape(value, [...countKeys, 'reachedMaxChannels', 'channelNumberCapacityExhausted']) &&
    countKeys.every((key) => isInteger(value[key], 0)) && typeof value.reachedMaxChannels === 'boolean' &&
    typeof value.channelNumberCapacityExhausted === 'boolean';
}

function isGuideRefresh(value: unknown): boolean {
  if (!isPlainRecord(value) || typeof value.kind !== 'string') return false;
  if (value.kind === 'completed') return hasExactShape(value, ['kind']);
  return (value.kind === 'failed' || value.kind === 'interrupted') && hasExactShape(value, ['kind', 'message']) &&
    isSafeText(value.message, 1, 160);
}

function isCancelResult(value: unknown): value is ChannelSetupCancelResult {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, ['buildId', 'status']) &&
    isSafeId(value.buildId) && (value.status === 'accepted' || value.status === 'too-late' || value.status === 'not-active');
}

function isProgress(value: unknown): value is ChannelSetupBuildProgress {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, ['task', 'current', 'total', 'label', 'detail']) &&
    isStringInSet(value.task, CHANNEL_SETUP_PROGRESS_TASKS) && isInteger(value.current, 0) &&
    (value.total === null || isInteger(value.total, 0)) && isSafeText(value.label, 1, 160) && isSafeText(value.detail, 1, 160);
}

function isEstimates(value: unknown): boolean {
  const keys = ['total', ...CHANNEL_SETUP_STRATEGY_KEYS];
  return isPlainRecord(value) && hasExactShape(value, keys) && keys.every((key) => isInteger(value[key], 0));
}

function isConfig(value: unknown): value is ChannelSetupConfig {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, [
    'selectedLibraryIds', 'maxChannels', 'buildMode', 'strategyConfig', 'channelExpansion', 'seriesOrdering',
    'actorStudioCombineMode', 'minItemsPerChannel',
  ]) && isSelectedIds(value.selectedLibraryIds) && isInteger(value.maxChannels, 1, 500) &&
    isStringInSet(value.buildMode, CHANNEL_SETUP_COMMIT_MODES) && isNormalizedStrategies(value.strategyConfig) &&
    isExpansion(value.channelExpansion, true) && isSeriesOrdering(value.seriesOrdering, true) &&
    (value.actorStudioCombineMode === 'separate' || value.actorStudioCombineMode === 'combined') &&
    isInteger(value.minItemsPerChannel, 1);
}

function isConfigDraft(value: unknown): value is ChannelSetupConfigDraft {
  return isPlainRecord(value) && !hasForbidden(value) && hasExactShape(value, [
    'selectedLibraryIds', 'maxChannels', 'buildMode', 'strategyConfig', 'actorStudioCombineMode', 'minItemsPerChannel',
  ], ['channelExpansion', 'seriesOrdering']) && isSelectedIds(value.selectedLibraryIds) &&
    isInteger(value.maxChannels, 1, 500) && isStringInSet(value.buildMode, CHANNEL_SETUP_COMMIT_MODES) &&
    isDraftStrategies(value.strategyConfig) && (value.channelExpansion === undefined || isExpansion(value.channelExpansion, false)) &&
    (value.seriesOrdering === undefined || isSeriesOrdering(value.seriesOrdering, false)) &&
    (value.actorStudioCombineMode === 'separate' || value.actorStudioCombineMode === 'combined') &&
    isInteger(value.minItemsPerChannel, 1);
}

function isNormalizedStrategies(value: unknown): boolean {
  return isPlainRecord(value) && hasExactShape(value, CHANNEL_SETUP_STRATEGY_KEYS) &&
    CHANNEL_SETUP_STRATEGY_KEYS.every((key) => isStrategy(value[key], true));
}

function isDraftStrategies(value: unknown): boolean {
  return isPlainRecord(value) && Object.keys(value).every((key) =>
    (CHANNEL_SETUP_STRATEGY_KEYS as readonly string[]).includes(key) && isStrategy(value[key], false));
}

function isStrategy(value: unknown, required: boolean): boolean {
  if (!isPlainRecord(value)) return false;
  const requiredKeys = required ? ['enabled', 'priority', 'scope'] : [];
  if (!hasExactShape(value, requiredKeys, required ? [] : ['enabled', 'priority', 'scope'])) return false;
  return (value.enabled === undefined || typeof value.enabled === 'boolean') &&
    (value.priority === undefined || isInteger(value.priority, 1)) &&
    (value.scope === undefined || value.scope === 'per-library' || value.scope === 'cross-library');
}

function isExpansion(value: unknown, required: boolean): boolean {
  if (!isPlainRecord(value)) return false;
  const keys = ['addAlternateLineups', 'alternateLineupCopies', 'variantType', 'variantBlockSize'];
  if (!hasExactShape(value, required ? keys : [], required ? [] : keys)) return false;
  return (value.addAlternateLineups === undefined || typeof value.addAlternateLineups === 'boolean') &&
    (value.alternateLineupCopies === undefined || isInteger(value.alternateLineupCopies, 1, 3)) &&
    (value.variantType === undefined || value.variantType === 'none' || value.variantType === 'sequential' || value.variantType === 'block') &&
    (value.variantBlockSize === undefined || isInteger(value.variantBlockSize, 2, 5));
}

function isSeriesOrdering(value: unknown, required: boolean): boolean {
  if (!isPlainRecord(value)) return false;
  const keys = ['basePlaybackMode', 'baseBlockSize'];
  if (!hasExactShape(value, required ? keys : [], required ? [] : keys)) return false;
  return (value.basePlaybackMode === undefined || value.basePlaybackMode === 'shuffle' || value.basePlaybackMode === 'sequential' || value.basePlaybackMode === 'block') &&
    (value.baseBlockSize === undefined || isInteger(value.baseBlockSize, 2, 5));
}

function isSelectedIds(value: unknown): value is readonly string[] {
  return Array.isArray(value) && value.length > 0 && value.length <= 24 && value.every(isSafeId) &&
    new Set(value).size === value.length;
}

function cloneConfigDraft(value: ChannelSetupConfigDraft): ChannelSetupConfigDraft {
  return {
    selectedLibraryIds: [...value.selectedLibraryIds], maxChannels: value.maxChannels, buildMode: value.buildMode,
    strategyConfig: Object.fromEntries(Object.entries(value.strategyConfig).map(([key, strategy]) => [key, { ...strategy }])),
    ...(value.channelExpansion === undefined ? {} : { channelExpansion: { ...value.channelExpansion } }),
    ...(value.seriesOrdering === undefined ? {} : { seriesOrdering: { ...value.seriesOrdering } }),
    actorStudioCombineMode: value.actorStudioCombineMode, minItemsPerChannel: value.minItemsPerChannel,
  };
}

function hasForbidden(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(hasForbidden);
  if (typeof value === 'string') return UNSAFE_STRING_PATTERNS.some((pattern) => pattern.test(value));
  if (!isPlainRecord(value)) return false;
  return Object.entries(value).some(([key, child]) => FORBIDDEN_KEYS.has(normalizeKey(key)) || hasForbidden(child));
}

function normalizeKey(value: string): string { return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, ''); }
function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && Object.getPrototypeOf(value) === Object.prototype;
}
function hasExactShape(value: object, required: readonly string[], optional: readonly string[] = []): boolean {
  const allowed = new Set([...required, ...optional]);
  return required.every((key) => Object.hasOwn(value, key)) && Object.keys(value).every((key) => allowed.has(key));
}
function isStringInSet<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === 'string' && values.includes(value as T);
}
function isSafeId(value: unknown): value is string { return typeof value === 'string' && ID_PATTERN.test(value); }
function isSafeText(value: unknown, minimum = 0, maximum = 160): value is string {
  return typeof value === 'string' && value.length >= minimum && value.length <= maximum &&
    !UNSAFE_STRING_PATTERNS.some((pattern) => pattern.test(value)) && !/[<>]/u.test(value);
}
function isSafeTextArray(value: unknown): value is readonly string[] {
  return Array.isArray(value) && value.length <= 500 && value.every((item) => isSafeText(item));
}
function isInteger(value: unknown, minimum: number, maximum = Number.MAX_SAFE_INTEGER): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}
