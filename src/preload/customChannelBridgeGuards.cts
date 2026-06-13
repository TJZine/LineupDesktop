import type {
  CustomChannelContentEntryInput,
  CustomChannelDraftInput,
  CustomChannelDraftResult,
  CustomChannelDraftValidationSummary,
  CustomChannelIpcResult,
  CustomChannelListMediaRequest,
  CustomChannelMediaMetadata,
  CustomChannelMediaPage,
  CustomChannelMutationResult,
  CustomChannelOperation,
  CustomChannelSnapshot,
} from '../contracts/customChannels.js';

export const CUSTOM_CHANNEL_OPERATIONS = [
  'getSnapshot',
  'listMedia',
  'getMediaMetadata',
  'validateDraft',
  'saveDraft',
  'deleteChannel',
  'duplicateChannelDraft',
  'reorderChannels',
  'setChannelVisibility',
] as const;
export const CUSTOM_CHANNEL_ERROR_CODES = [
  'CUSTOM_CHANNEL_UNAUTHORIZED',
  'CUSTOM_CHANNEL_VALIDATION_FAILED',
  'CUSTOM_CHANNEL_PLEX_REQUIRED',
  'CUSTOM_CHANNEL_STORAGE_UNAVAILABLE',
  'CUSTOM_CHANNEL_STORAGE_CORRUPT',
  'CUSTOM_CHANNEL_NOT_FOUND',
  'CUSTOM_CHANNEL_STALE_MEDIA',
  'CUSTOM_CHANNEL_ARTWORK_UNAVAILABLE',
  'CUSTOM_CHANNEL_CONFLICT',
  'CUSTOM_CHANNEL_UNKNOWN',
] as const;
export const CUSTOM_CHANNEL_VALIDATION_CODES = [
  'missing-name',
  'duplicate-number',
  'invalid-number',
  'empty-content',
  'duplicate-content',
  'invalid-draft-id',
  'invalid-content',
  'invalid-playback-mode',
  'invalid-block-size',
  'invalid-hidden',
  'invalid-include-watched',
  'invalid-sort-order',
  'invalid-start-time-anchor',
  'max-channels',
  'stale-content',
  'storage-unavailable',
] as const;
export const CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS = [
  'rawPayload',
  'rawPlexPayload',
  'headers',
  'header',
  'authHeaders',
  'authHeader',
  'rawAuthHeaders',
  'token',
  'accessToken',
  'refreshToken',
  'path',
  'filePath',
  'localPath',
  'url',
  'uri',
  'endpointUrl',
  'baseUrl',
  'tokenizedUrl',
  'serverUri',
  'connectionUri',
  'appPath',
  'userDataPath',
  'filesystemPath',
  'persistenceFilePath',
  'credential',
  'secret',
  'nativeHandle',
  'electronApi',
  'nodeApi',
  'thumb',
  'art',
  'banner',
  'clearLogo',
  'imageKey',
  'artworkKey',
  'storedChannelData',
] as const;

const CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS_NORMALIZED = new Set(
  CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS.map(normalizeForbiddenFieldKey),
);
const CUSTOM_CHANNEL_SAFE_ID_PATTERN = /^[A-Za-z0-9._~-]{1,160}$/u;
const CUSTOM_CHANNEL_COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/u;
const CUSTOM_CHANNEL_FORBIDDEN_STRING_PATTERNS = [
  /https?:\/\//iu,
  /file:\/\//iu,
  /(?:^|[\\/\s])\.\.(?:[\\/]|$)/u,
  /^\/(?:Users|private|tmp|var|Volumes|library|metadata|photo|image|transcode|library\/metadata)\b/iu,
  /\/library\/metadata\/[^ \t\r\n]+\/(?:thumb|art|banner|clearLogo)\b/iu,
  /\b[A-Za-z]:[\\/]/u,
  /\\\\[A-Za-z0-9._-]+[\\/]/u,
  /\b(?:bearer|token|authorization|headers?)\s*[:=]/iu,
  /\b(?:accessToken|refreshToken|x-plex-token)\b/iu,
] as const;
const CUSTOM_CHANNEL_MEDIA_TYPES = ['movie', 'show', 'episode', 'collection', 'playlist'] as const;
const CUSTOM_CHANNEL_PLAYBACK_MODES = ['sequential', 'shuffle', 'random', 'block'] as const;
const CUSTOM_CHANNEL_SORT_ORDERS = [
  'title_asc',
  'title_desc',
  'year_asc',
  'year_desc',
  'added_asc',
  'added_desc',
  'duration_asc',
  'duration_desc',
  'episode_order',
] as const;
const CUSTOM_CHANNEL_CONTENT_TYPES = ['library', 'show', 'collection', 'playlist', 'manualItem'] as const;
const CUSTOM_CHANNEL_MAX_CONTENT_ITEMS = 500;

export type CustomChannelPreloadRequest<TPayload, TValue> =
  | { ok: true; requestId: string; payload: TPayload }
  | { ok: false; result: CustomChannelIpcResult<TValue> };

export function createCustomChannelEmptyRequest(operation: CustomChannelOperation): {
  requestId: string;
  payload: Record<string, never>;
} {
  return { requestId: customChannelRequestId(operation), payload: {} };
}

export function createCustomChannelListMediaRequest(
  input: CustomChannelListMediaRequest['payload'],
): CustomChannelPreloadRequest<CustomChannelListMediaRequest['payload'], CustomChannelMediaPage> {
  const requestId = customChannelRequestId('listMedia');
  if (
    !isPlainRecord(input) ||
    hasForbiddenCustomChannelField(input) ||
    !hasOnlyKeys(input, ['sourceType', 'sourceId', 'query', 'offset', 'limit', 'mediaTypes', 'draftContent']) ||
    (input.sourceType !== 'library' && input.sourceType !== 'search') ||
    (input.sourceId !== undefined && !isSafeCustomChannelId(input.sourceId)) ||
    (input.query !== undefined && !isSafeDisplayString(input.query, 128)) ||
    (input.offset !== undefined && !isFiniteIntegerInRange(input.offset, 0, 50_000)) ||
    (input.limit !== undefined && !isFiniteIntegerInRange(input.limit, 1, 100)) ||
    (input.mediaTypes !== undefined && (!Array.isArray(input.mediaTypes) || !input.mediaTypes.every(isCustomChannelMediaType))) ||
    (input.draftContent !== undefined && !isCustomChannelContentArray(input.draftContent))
  ) {
    return customChannelPreloadValidationFailure(requestId, 'listMedia', 'Custom channel media request payload is invalid.');
  }
  return {
    ok: true,
    requestId,
    payload: {
      sourceType: input.sourceType,
      ...(input.sourceId === undefined ? {} : { sourceId: input.sourceId }),
      ...(input.query === undefined ? {} : { query: input.query }),
      ...(input.offset === undefined ? {} : { offset: input.offset }),
      ...(input.limit === undefined ? {} : { limit: input.limit }),
      ...(input.mediaTypes === undefined ? {} : { mediaTypes: [...input.mediaTypes] }),
      ...(input.draftContent === undefined ? {} : { draftContent: cloneContent(input.draftContent) }),
    },
  };
}

export function createCustomChannelMetadataRequest(input: { ratingKey: string }): CustomChannelPreloadRequest<
  { ratingKey: string },
  CustomChannelMediaMetadata
> {
  const requestId = customChannelRequestId('getMediaMetadata');
  if (
    !isPlainRecord(input) ||
    hasForbiddenCustomChannelField(input) ||
    !hasOnlyKeys(input, ['ratingKey']) ||
    !isSafeCustomChannelId(input.ratingKey)
  ) {
    return customChannelPreloadValidationFailure(
      requestId,
      'getMediaMetadata',
      'Custom channel metadata request payload is invalid.',
    );
  }
  return { ok: true, requestId, payload: { ratingKey: input.ratingKey } };
}

export function createCustomChannelDraftRequest<TValue>(
  operation: 'validateDraft' | 'saveDraft',
  input: CustomChannelDraftInput,
): CustomChannelPreloadRequest<CustomChannelDraftInput, TValue> {
  const requestId = customChannelRequestId(operation);
  if (!isCustomChannelDraftInput(input)) {
    return customChannelPreloadValidationFailure(
      requestId,
      operation,
      'Custom channel draft payload is invalid.',
    );
  }
  return { ok: true, requestId, payload: { ...input, content: cloneContent(input.content) } };
}

export function createCustomChannelDeleteRequest(input: { channelId: string; confirm: boolean }): CustomChannelPreloadRequest<
  { channelId: string; confirm: boolean },
  CustomChannelMutationResult
> {
  const requestId = customChannelRequestId('deleteChannel');
  if (
    !isPlainRecord(input) ||
    hasForbiddenCustomChannelField(input) ||
    !hasOnlyKeys(input, ['channelId', 'confirm']) ||
    !isSafeCustomChannelId(input.channelId) ||
    typeof input.confirm !== 'boolean'
  ) {
    return customChannelPreloadValidationFailure(requestId, 'deleteChannel', 'Custom channel delete request payload is invalid.');
  }
  return { ok: true, requestId, payload: { channelId: input.channelId, confirm: input.confirm } };
}

export function createCustomChannelDuplicateDraftRequest(input: { channelId: string }): CustomChannelPreloadRequest<
  { channelId: string },
  CustomChannelDraftResult
> {
  const requestId = customChannelRequestId('duplicateChannelDraft');
  if (
    !isPlainRecord(input) ||
    hasForbiddenCustomChannelField(input) ||
    !hasOnlyKeys(input, ['channelId']) ||
    !isSafeCustomChannelId(input.channelId)
  ) {
    return customChannelPreloadValidationFailure(
      requestId,
      'duplicateChannelDraft',
      'Custom channel duplicate request payload is invalid.',
    );
  }
  return { ok: true, requestId, payload: { channelId: input.channelId } };
}

export function createCustomChannelReorderRequest(input: { channelIds: readonly string[] }): CustomChannelPreloadRequest<
  { channelIds: readonly string[] },
  CustomChannelMutationResult
> {
  const requestId = customChannelRequestId('reorderChannels');
  if (
    !isPlainRecord(input) ||
    hasForbiddenCustomChannelField(input) ||
    !hasOnlyKeys(input, ['channelIds']) ||
    !Array.isArray(input.channelIds) ||
    input.channelIds.length === 0 ||
    input.channelIds.length > 500 ||
    !input.channelIds.every(isSafeCustomChannelId) ||
    new Set(input.channelIds).size !== input.channelIds.length
  ) {
    return customChannelPreloadValidationFailure(requestId, 'reorderChannels', 'Custom channel reorder request payload is invalid.');
  }
  return { ok: true, requestId, payload: { channelIds: [...input.channelIds] } };
}

export function createCustomChannelVisibilityRequest(input: { channelId: string; hidden: boolean }): CustomChannelPreloadRequest<
  { channelId: string; hidden: boolean },
  CustomChannelMutationResult
> {
  const requestId = customChannelRequestId('setChannelVisibility');
  if (
    !isPlainRecord(input) ||
    hasForbiddenCustomChannelField(input) ||
    !hasOnlyKeys(input, ['channelId', 'hidden']) ||
    !isSafeCustomChannelId(input.channelId) ||
    typeof input.hidden !== 'boolean'
  ) {
    return customChannelPreloadValidationFailure(
      requestId,
      'setChannelVisibility',
      'Custom channel visibility request payload is invalid.',
    );
  }
  return { ok: true, requestId, payload: { channelId: input.channelId, hidden: input.hidden } };
}

export function isCustomChannelSnapshotResult(
  value: unknown,
  requestId: string,
): value is CustomChannelIpcResult<CustomChannelSnapshot> {
  return isCustomChannelResult(value, requestId, isCustomChannelSnapshot);
}

export function isCustomChannelMediaPageResult(
  value: unknown,
  requestId: string,
): value is CustomChannelIpcResult<CustomChannelMediaPage> {
  return isCustomChannelResult(value, requestId, isCustomChannelMediaPage);
}

export function isCustomChannelMetadataResult(
  value: unknown,
  requestId: string,
): value is CustomChannelIpcResult<CustomChannelMediaMetadata> {
  return isCustomChannelResult(value, requestId, isCustomChannelMediaMetadata);
}

export function isCustomChannelValidationResult(
  value: unknown,
  requestId: string,
): value is CustomChannelIpcResult<CustomChannelDraftValidationSummary> {
  return isCustomChannelResult(value, requestId, isCustomChannelDraftValidationSummary);
}

export function isCustomChannelMutationResult(
  value: unknown,
  requestId: string,
): value is CustomChannelIpcResult<CustomChannelMutationResult> {
  return isCustomChannelResult(value, requestId, isCustomChannelMutationValue);
}

export function isCustomChannelDraftResult(
  value: unknown,
  requestId: string,
): value is CustomChannelIpcResult<CustomChannelDraftResult> {
  return isCustomChannelResult(value, requestId, isCustomChannelDraftValue);
}

export function customChannelValidationFailure<TValue>(
  requestId: string,
  operation: CustomChannelOperation,
  message = 'Custom channel result is invalid.',
): CustomChannelIpcResult<TValue> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'CUSTOM_CHANNEL_VALIDATION_FAILED',
      message,
      retryable: false,
      recoverable: false,
      operation,
    },
  };
}

function isCustomChannelResult<TValue>(
  value: unknown,
  requestId: string,
  isValue: (candidate: unknown) => candidate is TValue,
): value is CustomChannelIpcResult<TValue> {
  if (!isPlainRecord(value) || hasForbiddenCustomChannelField(value)) return false;
  if (value.ok === true) {
    return hasOnlyKeys(value, ['ok', 'requestId', 'value']) &&
      value.requestId === requestId &&
      isValue(value.value);
  }
  return value.ok === false &&
    hasOnlyKeys(value, ['ok', 'requestId', 'error']) &&
    value.requestId === requestId &&
    isCustomChannelError(value.error);
}

function isCustomChannelSnapshot(value: unknown): value is CustomChannelSnapshot {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, [
      'channels',
      'currentChannelId',
      'visibleChannelCount',
      'hiddenChannelCount',
      'maxChannels',
      'nextAvailableNumber',
      'updatedAtMs',
      'storage',
    ]) &&
    Array.isArray(value.channels) &&
    value.channels.every(isCustomChannelSummary) &&
    isNullableSafeId(value.currentChannelId) &&
    isFiniteIntegerInRange(value.visibleChannelCount, 0, 500) &&
    isFiniteIntegerInRange(value.hiddenChannelCount, 0, 500) &&
    isFiniteIntegerInRange(value.maxChannels, 1, 500) &&
    (value.nextAvailableNumber === null || isFiniteIntegerInRange(value.nextAvailableNumber, 1, 500)) &&
    isFiniteIntegerInRange(value.updatedAtMs, 0, Number.MAX_SAFE_INTEGER) &&
    isCustomChannelStorageSummary(value.storage);
}

function isCustomChannelSummary(value: unknown): boolean {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, [
      'id',
      'number',
      'name',
      'description',
      'itemCount',
      'estimatedDurationMs',
      'sourceSummary',
      'playbackMode',
      'hidden',
      'updatedAtMs',
      'isCurrent',
    ]) &&
    isSafeCustomChannelId(value.id) &&
    isFiniteIntegerInRange(value.number, 1, 500) &&
    isSafeDisplayString(value.name, 120) &&
    isNullableSafeDisplayString(value.description, 500) &&
    isFiniteIntegerInRange(value.itemCount, 0, Number.MAX_SAFE_INTEGER) &&
    isFiniteIntegerInRange(value.estimatedDurationMs, 0, Number.MAX_SAFE_INTEGER) &&
    isSafeDisplayString(value.sourceSummary, 200) &&
    isStringInSet(value.playbackMode, CUSTOM_CHANNEL_PLAYBACK_MODES) &&
    typeof value.hidden === 'boolean' &&
    isFiniteIntegerInRange(value.updatedAtMs, 0, Number.MAX_SAFE_INTEGER) &&
    typeof value.isCurrent === 'boolean';
}

function isCustomChannelStorageSummary(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['status', 'repaired']) &&
    isStringInSet(value.status, ['ready', 'not-configured', 'unavailable', 'corrupt'] as const) &&
    typeof value.repaired === 'boolean';
}

function isCustomChannelMediaPage(value: unknown): value is CustomChannelMediaPage {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, ['items', 'offset', 'limit', 'total', 'hasMore']) &&
    Array.isArray(value.items) &&
    value.items.length <= 100 &&
    value.items.every(isCustomChannelMediaCard) &&
    isFiniteIntegerInRange(value.offset, 0, 50_000) &&
    isFiniteIntegerInRange(value.limit, 1, 100) &&
    (value.total === null || isFiniteIntegerInRange(value.total, 0, Number.MAX_SAFE_INTEGER)) &&
    typeof value.hasMore === 'boolean';
}

function isCustomChannelMediaCard(value: unknown): boolean {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, [
      'ratingKey',
      'type',
      'title',
      'subtitle',
      'year',
      'durationMs',
      'parentTitle',
      'seasonNumber',
      'episodeNumber',
      'contentRating',
      'source',
      'artwork',
      'availability',
    ]) &&
    isSafeCustomChannelId(value.ratingKey) &&
    isCustomChannelMediaType(value.type) &&
    isSafeDisplayString(value.title, 240) &&
    isSafeDisplayString(value.subtitle, 240) &&
    (value.year === null || isFiniteIntegerInRange(value.year, 1800, 3000)) &&
    (value.durationMs === null || isFiniteIntegerInRange(value.durationMs, 0, Number.MAX_SAFE_INTEGER)) &&
    (value.parentTitle === undefined || isSafeDisplayString(value.parentTitle, 240)) &&
    (value.seasonNumber === undefined || isFiniteIntegerInRange(value.seasonNumber, 0, 10_000)) &&
    (value.episodeNumber === undefined || isFiniteIntegerInRange(value.episodeNumber, 0, 10_000)) &&
    (value.contentRating === undefined || isSafeDisplayString(value.contentRating, 40)) &&
    isCustomChannelSourceRef(value.source) &&
    (value.artwork === undefined || isArtworkRef(value.artwork)) &&
    isStringInSet(value.availability, ['available', 'stale', 'unsupported'] as const);
}

function isCustomChannelMediaMetadata(value: unknown): value is CustomChannelMediaMetadata {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, [
      'ratingKey',
      'type',
      'title',
      'subtitle',
      'summary',
      'year',
      'durationMs',
      'parentTitle',
      'seasonNumber',
      'episodeNumber',
      'contentRating',
      'genres',
      'artwork',
      'availability',
    ]) &&
    isCustomChannelMediaCard({
      ratingKey: value.ratingKey,
      type: value.type,
      title: value.title,
      subtitle: value.subtitle,
      year: value.year,
      durationMs: value.durationMs,
      parentTitle: value.parentTitle,
      seasonNumber: value.seasonNumber,
      episodeNumber: value.episodeNumber,
      contentRating: value.contentRating,
      source: { sourceType: 'search', sourceId: 'metadata', title: 'Metadata' },
      artwork: value.artwork,
      availability: value.availability,
    }) &&
    isNullableSafeDisplayString(value.summary, 5000) &&
    Array.isArray(value.genres) &&
    value.genres.length <= 50 &&
    value.genres.every((genre) => isSafeDisplayString(genre, 80));
}

function isCustomChannelSourceRef(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['sourceType', 'sourceId', 'title']) &&
    (value.sourceType === 'library' || value.sourceType === 'search') &&
    isSafeCustomChannelId(value.sourceId) &&
    isSafeDisplayString(value.title, 240);
}

function isArtworkRef(value: unknown): boolean {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, ['id', 'kind', 'expiresAtMs', 'altText', 'status']) &&
    isSafeCustomChannelId(value.id) &&
    isStringInSet(value.kind, ['poster', 'background', 'logo'] as const) &&
    isFiniteIntegerInRange(value.expiresAtMs, 0, Number.MAX_SAFE_INTEGER) &&
    isSafeDisplayString(value.altText, 240) &&
    isStringInSet(value.status, ['available', 'placeholder'] as const);
}

function isCustomChannelDraftValidationSummary(value: unknown): value is CustomChannelDraftValidationSummary {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, ['valid', 'issues']) &&
    typeof value.valid === 'boolean' &&
    Array.isArray(value.issues) &&
    value.issues.length <= 100 &&
    value.issues.every(isCustomChannelValidationIssue);
}

function isCustomChannelValidationIssue(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'field', 'contentIndex']) &&
    isStringInSet(value.code, CUSTOM_CHANNEL_VALIDATION_CODES) &&
    isSafeDisplayString(value.message, 240) &&
    (value.field === null || isSafeDisplayString(value.field, 120)) &&
    (value.contentIndex === undefined || isFiniteIntegerInRange(value.contentIndex, 0, CUSTOM_CHANNEL_MAX_CONTENT_ITEMS));
}

function isCustomChannelMutationValue(value: unknown): value is CustomChannelMutationResult {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, ['snapshot', 'changedChannelId', 'currentChannelId']) &&
    isCustomChannelSnapshot(value.snapshot) &&
    isNullableSafeId(value.changedChannelId) &&
    isNullableSafeId(value.currentChannelId);
}

function isCustomChannelDraftValue(value: unknown): value is CustomChannelDraftResult {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, ['draft', 'validation']) &&
    isCustomChannelDraftInput(value.draft) &&
    isCustomChannelDraftValidationSummary(value.validation);
}

function isCustomChannelDraftInput(value: unknown): value is CustomChannelDraftInput {
  return isPlainRecord(value) &&
    !hasForbiddenCustomChannelField(value) &&
    hasOnlyKeys(value, [
      'id',
      'expectedRevision',
      'number',
      'name',
      'description',
      'color',
      'icon',
      'hidden',
      'content',
      'playbackMode',
      'blockSize',
      'sortOrder',
      'includeWatched',
      'startTimeAnchor',
      'skipIntros',
      'skipCredits',
    ]) &&
    (value.id === undefined || isSafeCustomChannelId(value.id)) &&
    (value.expectedRevision === undefined || isSafeDisplayString(value.expectedRevision, 160)) &&
    isFiniteIntegerInRange(value.number, 1, 500) &&
    isSafeDisplayString(value.name, 120) &&
    (value.description === undefined || isSafeDisplayString(value.description, 500)) &&
    (value.color === undefined || (typeof value.color === 'string' && CUSTOM_CHANNEL_COLOR_PATTERN.test(value.color))) &&
    (value.icon === undefined || isSafeDisplayString(value.icon, 80)) &&
    typeof value.hidden === 'boolean' &&
    isCustomChannelContentArray(value.content) &&
    isStringInSet(value.playbackMode, CUSTOM_CHANNEL_PLAYBACK_MODES) &&
    (value.blockSize === undefined || isFiniteIntegerInRange(value.blockSize, 1, 1000)) &&
    (value.sortOrder === undefined || isStringInSet(value.sortOrder, CUSTOM_CHANNEL_SORT_ORDERS)) &&
    (value.includeWatched === undefined || typeof value.includeWatched === 'boolean') &&
    (value.startTimeAnchor === undefined || isFiniteIntegerInRange(value.startTimeAnchor, 0, Number.MAX_SAFE_INTEGER)) &&
    (value.skipIntros === undefined || typeof value.skipIntros === 'boolean') &&
    (value.skipCredits === undefined || typeof value.skipCredits === 'boolean');
}

function isCustomChannelContentArray(value: unknown): value is readonly CustomChannelContentEntryInput[] {
  return Array.isArray(value) &&
    value.length <= CUSTOM_CHANNEL_MAX_CONTENT_ITEMS &&
    value.every(isCustomChannelContentEntry);
}

function isCustomChannelContentEntry(value: unknown): value is CustomChannelContentEntryInput {
  if (
    !isPlainRecord(value) ||
    hasForbiddenCustomChannelField(value) ||
    !isStringInSet(value.type, CUSTOM_CHANNEL_CONTENT_TYPES)
  ) {
    return false;
  }
  if (value.type === 'library') {
    return hasOnlyKeys(value, ['type', 'sourceId', 'title', 'mediaType', 'includeWatched']) &&
      isSafeCustomChannelId(value.sourceId) &&
      isSafeDisplayString(value.title, 240) &&
      (value.mediaType === 'movie' || value.mediaType === 'show') &&
      (value.includeWatched === undefined || typeof value.includeWatched === 'boolean');
  }
  if (value.type === 'show') {
    return hasOnlyKeys(value, ['type', 'sourceId', 'title', 'seasonFilter']) &&
      isSafeCustomChannelId(value.sourceId) &&
      isSafeDisplayString(value.title, 240) &&
      (value.seasonFilter === undefined ||
        (Array.isArray(value.seasonFilter) && value.seasonFilter.length <= 100 &&
          value.seasonFilter.every((season) => isFiniteIntegerInRange(season, 0, 10_000))));
  }
  if (value.type === 'collection' || value.type === 'playlist') {
    return hasOnlyKeys(value, ['type', 'sourceId', 'title']) &&
      isSafeCustomChannelId(value.sourceId) &&
      isSafeDisplayString(value.title, 240);
  }
  return hasOnlyKeys(value, [
    'type',
    'ratingKey',
    'title',
    'durationMs',
    'mediaType',
    'parentTitle',
    'year',
    'seasonNumber',
    'episodeNumber',
  ]) &&
    isSafeCustomChannelId(value.ratingKey) &&
    isSafeDisplayString(value.title, 240) &&
    isFiniteIntegerInRange(value.durationMs, 0, Number.MAX_SAFE_INTEGER) &&
    (value.mediaType === 'movie' || value.mediaType === 'episode') &&
    (value.parentTitle === undefined || isSafeDisplayString(value.parentTitle, 240)) &&
    (value.year === undefined || isFiniteIntegerInRange(value.year, 1800, 3000)) &&
    (value.seasonNumber === undefined || isFiniteIntegerInRange(value.seasonNumber, 0, 10_000)) &&
    (value.episodeNumber === undefined || isFiniteIntegerInRange(value.episodeNumber, 0, 10_000));
}

function isCustomChannelError(value: unknown): boolean {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    isStringInSet(value.code, CUSTOM_CHANNEL_ERROR_CODES) &&
    isSafeDisplayString(value.message, 200) &&
    typeof value.retryable === 'boolean' &&
    typeof value.recoverable === 'boolean' &&
    isStringInSet(value.operation, CUSTOM_CHANNEL_OPERATIONS);
}

function cloneContent(
  content: readonly CustomChannelContentEntryInput[],
): readonly CustomChannelContentEntryInput[] {
  return content.map((entry) => (
    entry.type === 'show' && entry.seasonFilter !== undefined
      ? { ...entry, seasonFilter: [...entry.seasonFilter] }
      : { ...entry }
  ));
}

function customChannelPreloadValidationFailure<TPayload, TValue>(
  requestId: string,
  operation: CustomChannelOperation,
  message: string,
): CustomChannelPreloadRequest<TPayload, TValue> {
  return {
    ok: false,
    result: customChannelValidationFailure(requestId, operation, message),
  };
}

function customChannelRequestId(operation: CustomChannelOperation): string {
  return `custom-channel-${operation}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function hasForbiddenCustomChannelField(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(hasForbiddenCustomChannelField);
  if (typeof value === 'string') {
    return CUSTOM_CHANNEL_FORBIDDEN_STRING_PATTERNS.some((pattern) => pattern.test(value));
  }
  if (!isPlainRecord(value)) return false;
  return Object.entries(value).some(([key, entry]) => (
    CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS_NORMALIZED.has(normalizeForbiddenFieldKey(key)) ||
    hasForbiddenCustomChannelField(entry)
  ));
}

function normalizeForbiddenFieldKey(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/gu, '');
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasOnlyKeys(value: object, allowedKeys: readonly string[]): boolean {
  const allowed = new Set(allowedKeys);
  return Object.keys(value).every((key) => allowed.has(key));
}

function isStringInSet<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === 'string' && values.includes(value as T);
}

function isCustomChannelMediaType(value: unknown): boolean {
  return isStringInSet(value, CUSTOM_CHANNEL_MEDIA_TYPES);
}

function isSafeCustomChannelId(value: unknown): value is string {
  return typeof value === 'string' &&
    value.trim() === value &&
    CUSTOM_CHANNEL_SAFE_ID_PATTERN.test(value) &&
    !CUSTOM_CHANNEL_FORBIDDEN_STRING_PATTERNS.some((pattern) => pattern.test(value));
}

function isNullableSafeId(value: unknown): value is string | null {
  return value === null || isSafeCustomChannelId(value);
}

function isSafeDisplayString(value: unknown, maxLength: number): value is string {
  return typeof value === 'string' &&
    value.length <= maxLength &&
    !/[<>]/u.test(value) &&
    !CUSTOM_CHANNEL_FORBIDDEN_STRING_PATTERNS.some((pattern) => pattern.test(value));
}

function isNullableSafeDisplayString(value: unknown, maxLength: number): value is string | null {
  return value === null || isSafeDisplayString(value, maxLength);
}

function isFiniteIntegerInRange(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' &&
    Number.isFinite(value) &&
    Number.isInteger(value) &&
    value >= min &&
    value <= max;
}
