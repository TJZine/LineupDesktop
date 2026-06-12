import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  containsCustomChannelForbiddenRendererField,
  customChannelFailure,
  customChannelSuccess,
  type CustomChannelContentEntryInput,
  type CustomChannelDraftInput,
  type CustomChannelErrorCode,
  type CustomChannelGetMediaMetadataRequest,
  type CustomChannelListMediaRequest,
  type CustomChannelOperation,
} from '../../contracts/customChannels.js';
import {
  LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL,
} from '../../contracts/ipc.js';
import type { CustomChannelRuntime } from './customChannelRuntime.js';
import type { CustomChannelMediaPicker } from './customChannelMediaPicker.js';

type CustomChannelIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterCustomChannelIpcHandlersOptions {
  runtime: CustomChannelRuntime;
  mediaPicker: CustomChannelMediaPicker;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  ipcMain?: CustomChannelIpcMain;
}

export type CustomChannelIpcTeardown = () => Promise<void>;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const SAFE_ID_PATTERN = /^[A-Za-z0-9._~-]{1,160}$/u;
const COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/u;
const MEDIA_TYPES = ['movie', 'show', 'episode', 'collection', 'playlist'] as const;
const PLAYBACK_MODES = ['sequential', 'shuffle', 'random', 'block'] as const;
const SORT_ORDERS = [
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
const MAX_CONTENT_ITEMS = 500;

export function registerCustomChannelIpcHandlers(
  options: RegisterCustomChannelIpcHandlersOptions,
): CustomChannelIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'getSnapshot');
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'getSnapshot');
    if (!request.ok) return validationResult(request.requestId, 'getSnapshot');
    return options.runtime.getSnapshot(request.requestId);
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL, async (event, payload: unknown) => {
    const request = readListMediaRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'listMedia');
    if (!request.ok) return validationResult(request.requestId, 'listMedia');
    try {
      const result = await options.mediaPicker.listMedia(request.requestId, request.payload);
      return result.ok
        ? customChannelSuccess(request.requestId, result.value)
        : customChannelFailure(request.requestId, result.error);
    } catch {
      return failureResult(request.requestId, 'listMedia', 'CUSTOM_CHANNEL_UNKNOWN');
    }
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL, async (event, payload: unknown) => {
    const request = readMetadataRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'getMediaMetadata');
    if (!request.ok) return validationResult(request.requestId, 'getMediaMetadata');
    try {
      const result = await options.mediaPicker.getMediaMetadata(request.requestId, request.payload.ratingKey);
      return result.ok
        ? customChannelSuccess(request.requestId, result.value)
        : customChannelFailure(request.requestId, result.error);
    } catch {
      return failureResult(request.requestId, 'getMediaMetadata', 'CUSTOM_CHANNEL_UNKNOWN');
    }
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL, (event, payload: unknown) => {
    const request = readDraftRequest(payload, options, 'validateDraft');
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'validateDraft');
    if (!request.ok) return validationResult(request.requestId, 'validateDraft');
    return options.runtime.validateDraft(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL, (event, payload: unknown) => {
    const request = readDraftRequest(payload, options, 'saveDraft');
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'saveDraft');
    if (!request.ok) return validationResult(request.requestId, 'saveDraft');
    return options.runtime.saveDraft(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL, (event, payload: unknown) => {
    const request = readDeleteRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'deleteChannel');
    if (!request.ok) return validationResult(request.requestId, 'deleteChannel');
    return options.runtime.deleteChannel(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL, (event, payload: unknown) => {
    const request = readChannelIdRequest(payload, options, 'duplicateChannelDraft');
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'duplicateChannelDraft');
    if (!request.ok) return validationResult(request.requestId, 'duplicateChannelDraft');
    return options.runtime.duplicateChannelDraft(request.requestId, request.payload.channelId);
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL, (event, payload: unknown) => {
    const request = readReorderRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'reorderChannels');
    if (!request.ok) return validationResult(request.requestId, 'reorderChannels');
    return options.runtime.reorderChannels(request.requestId, request.payload.channelIds);
  });

  ipcMain.handle(LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL, (event, payload: unknown) => {
    const request = readVisibilityRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) return unauthorizedResult(request.requestId, 'setChannelVisibility');
    if (!request.ok) return validationResult(request.requestId, 'setChannelVisibility');
    return options.runtime.setChannelVisibility(request.requestId, request.payload);
  });

  return async () => {
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL);
    ipcMain.removeHandler(LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL);
  };
}

type ReadResult<TPayload> =
  | { ok: true; requestId: string; payload: TPayload }
  | { ok: false; requestId: string; payload: Partial<TPayload> };

function readEnvelope(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
  operation: CustomChannelOperation,
): { ok: true; requestId: string; payload: Record<string, unknown> } | { ok: false; requestId: string; payload: Record<string, unknown> } {
  const fallbackRequestId = options.createRequestId(`custom-channel-${operation}`);
  if (!isPlainRecord(value)) return { ok: false, requestId: fallbackRequestId, payload: {} };
  const requestId = typeof value.requestId === 'string' && REQUEST_ID_PATTERN.test(value.requestId)
    ? value.requestId
    : fallbackRequestId;
  if (
    typeof value.requestId !== 'string' ||
    !REQUEST_ID_PATTERN.test(value.requestId) ||
    !hasOnlyKeys(value, ['requestId', 'payload']) ||
    !isPlainRecord(value.payload) ||
    containsCustomChannelForbiddenRendererField(value.payload)
  ) {
    return { ok: false, requestId, payload: {} };
  }
  return { ok: true, requestId, payload: value.payload };
}

function readEmptyRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
  operation: 'getSnapshot',
): ReadResult<Record<string, never>> {
  const envelope = readEnvelope(value, options, operation);
  if (!envelope.ok || Object.keys(envelope.payload).length !== 0) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: {} };
}

function readListMediaRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
): ReadResult<CustomChannelListMediaRequest['payload']> {
  const envelope = readEnvelope(value, options, 'listMedia');
  if (
    !envelope.ok ||
    !hasOnlyKeys(envelope.payload, ['sourceType', 'sourceId', 'query', 'offset', 'limit', 'mediaTypes', 'draftContent']) ||
    (envelope.payload.sourceType !== 'library' && envelope.payload.sourceType !== 'search') ||
    (envelope.payload.sourceId !== undefined && !isSafeId(envelope.payload.sourceId)) ||
    (envelope.payload.query !== undefined && !isSafeDisplayString(envelope.payload.query, 128)) ||
    (envelope.payload.offset !== undefined && !isIntegerInRange(envelope.payload.offset, 0, 50_000)) ||
    (envelope.payload.limit !== undefined && !isIntegerInRange(envelope.payload.limit, 1, 100)) ||
    (envelope.payload.mediaTypes !== undefined &&
      (!Array.isArray(envelope.payload.mediaTypes) || !envelope.payload.mediaTypes.every(isMediaType))) ||
    (envelope.payload.draftContent !== undefined && !isContentArray(envelope.payload.draftContent))
  ) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return {
    ok: true,
    requestId: envelope.requestId,
    payload: {
      sourceType: envelope.payload.sourceType,
      ...(envelope.payload.sourceId === undefined ? {} : { sourceId: envelope.payload.sourceId }),
      ...(envelope.payload.query === undefined ? {} : { query: envelope.payload.query }),
      ...(envelope.payload.offset === undefined ? {} : { offset: envelope.payload.offset }),
      ...(envelope.payload.limit === undefined ? {} : { limit: envelope.payload.limit }),
      ...(envelope.payload.mediaTypes === undefined ? {} : { mediaTypes: [...envelope.payload.mediaTypes] }),
      ...(envelope.payload.draftContent === undefined ? {} : { draftContent: cloneContent(envelope.payload.draftContent) }),
    },
  };
}

function readMetadataRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
): ReadResult<CustomChannelGetMediaMetadataRequest['payload']> {
  const envelope = readEnvelope(value, options, 'getMediaMetadata');
  if (
    !envelope.ok ||
    !hasOnlyKeys(envelope.payload, ['ratingKey']) ||
    !isSafeId(envelope.payload.ratingKey)
  ) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: { ratingKey: envelope.payload.ratingKey } };
}

function readDraftRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
  operation: 'validateDraft' | 'saveDraft',
): ReadResult<CustomChannelDraftInput> {
  const envelope = readEnvelope(value, options, operation);
  if (!envelope.ok || !isDraftInput(envelope.payload)) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: { ...envelope.payload, content: cloneContent(envelope.payload.content) } };
}

function readDeleteRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
): ReadResult<{ channelId: string; confirm: boolean }> {
  const envelope = readEnvelope(value, options, 'deleteChannel');
  if (
    !envelope.ok ||
    !hasOnlyKeys(envelope.payload, ['channelId', 'confirm']) ||
    !isSafeId(envelope.payload.channelId) ||
    typeof envelope.payload.confirm !== 'boolean'
  ) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return {
    ok: true,
    requestId: envelope.requestId,
    payload: { channelId: envelope.payload.channelId, confirm: envelope.payload.confirm },
  };
}

function readChannelIdRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
  operation: 'duplicateChannelDraft',
): ReadResult<{ channelId: string }> {
  const envelope = readEnvelope(value, options, operation);
  if (
    !envelope.ok ||
    !hasOnlyKeys(envelope.payload, ['channelId']) ||
    !isSafeId(envelope.payload.channelId)
  ) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: { channelId: envelope.payload.channelId } };
}

function readReorderRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
): ReadResult<{ channelIds: readonly string[] }> {
  const envelope = readEnvelope(value, options, 'reorderChannels');
  if (
    !envelope.ok ||
    !hasOnlyKeys(envelope.payload, ['channelIds']) ||
    !Array.isArray(envelope.payload.channelIds) ||
    envelope.payload.channelIds.length === 0 ||
    envelope.payload.channelIds.length > 500 ||
    !envelope.payload.channelIds.every(isSafeId)
  ) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: { channelIds: [...envelope.payload.channelIds] } };
}

function readVisibilityRequest(
  value: unknown,
  options: Pick<RegisterCustomChannelIpcHandlersOptions, 'createRequestId'>,
): ReadResult<{ channelId: string; hidden: boolean }> {
  const envelope = readEnvelope(value, options, 'setChannelVisibility');
  if (
    !envelope.ok ||
    !hasOnlyKeys(envelope.payload, ['channelId', 'hidden']) ||
    !isSafeId(envelope.payload.channelId) ||
    typeof envelope.payload.hidden !== 'boolean'
  ) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return {
    ok: true,
    requestId: envelope.requestId,
    payload: { channelId: envelope.payload.channelId, hidden: envelope.payload.hidden },
  };
}

function unauthorizedResult(requestId: string, operation: CustomChannelOperation) {
  return customChannelFailure(requestId, {
    code: 'CUSTOM_CHANNEL_UNAUTHORIZED',
    message: 'Custom channel request is not authorized.',
    retryable: false,
    recoverable: false,
    operation,
  });
}

function validationResult(requestId: string, operation: CustomChannelOperation) {
  return failureResult(requestId, operation, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
}

function failureResult(
  requestId: string,
  operation: CustomChannelOperation,
  code: CustomChannelErrorCode,
) {
  return customChannelFailure(requestId, {
    code,
    message: code === 'CUSTOM_CHANNEL_VALIDATION_FAILED'
      ? 'Custom channel request payload is invalid.'
      : 'Custom channel request failed.',
    retryable: code === 'CUSTOM_CHANNEL_UNKNOWN',
    recoverable: code === 'CUSTOM_CHANNEL_UNKNOWN',
    operation,
  });
}

function isDraftInput(value: unknown): value is CustomChannelDraftInput {
  return isPlainRecord(value) &&
    !containsCustomChannelForbiddenRendererField(value) &&
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
    (value.id === undefined || isSafeId(value.id)) &&
    (value.expectedRevision === undefined || isSafeDisplayString(value.expectedRevision, 160)) &&
    isIntegerInRange(value.number, 1, 500) &&
    isSafeDisplayString(value.name, 120) &&
    (value.description === undefined || isSafeDisplayString(value.description, 500)) &&
    (value.color === undefined || (typeof value.color === 'string' && COLOR_PATTERN.test(value.color))) &&
    (value.icon === undefined || isSafeDisplayString(value.icon, 80)) &&
    typeof value.hidden === 'boolean' &&
    isContentArray(value.content) &&
    isStringInSet(value.playbackMode, PLAYBACK_MODES) &&
    (value.blockSize === undefined || isIntegerInRange(value.blockSize, 1, 1000)) &&
    (value.sortOrder === undefined || isStringInSet(value.sortOrder, SORT_ORDERS)) &&
    (value.includeWatched === undefined || typeof value.includeWatched === 'boolean') &&
    (value.startTimeAnchor === undefined || isIntegerInRange(value.startTimeAnchor, 0, Number.MAX_SAFE_INTEGER)) &&
    (value.skipIntros === undefined || typeof value.skipIntros === 'boolean') &&
    (value.skipCredits === undefined || typeof value.skipCredits === 'boolean');
}

function isContentArray(value: unknown): value is readonly CustomChannelContentEntryInput[] {
  return Array.isArray(value) &&
    value.length <= MAX_CONTENT_ITEMS &&
    value.every(isContentEntry);
}

function isContentEntry(value: unknown): value is CustomChannelContentEntryInput {
  if (!isPlainRecord(value) || containsCustomChannelForbiddenRendererField(value)) return false;
  if (value.type === 'library') {
    return hasOnlyKeys(value, ['type', 'sourceId', 'title', 'mediaType', 'includeWatched']) &&
      isSafeId(value.sourceId) &&
      isSafeDisplayString(value.title, 240) &&
      (value.mediaType === 'movie' || value.mediaType === 'show') &&
      (value.includeWatched === undefined || typeof value.includeWatched === 'boolean');
  }
  if (value.type === 'show') {
    return hasOnlyKeys(value, ['type', 'sourceId', 'title', 'seasonFilter']) &&
      isSafeId(value.sourceId) &&
      isSafeDisplayString(value.title, 240) &&
      (value.seasonFilter === undefined ||
        (Array.isArray(value.seasonFilter) && value.seasonFilter.length <= 100 &&
          value.seasonFilter.every((season) => isIntegerInRange(season, 0, 10_000))));
  }
  if (value.type === 'collection' || value.type === 'playlist') {
    return hasOnlyKeys(value, ['type', 'sourceId', 'title']) &&
      isSafeId(value.sourceId) &&
      isSafeDisplayString(value.title, 240);
  }
  if (value.type !== 'manualItem') return false;
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
    isSafeId(value.ratingKey) &&
    isSafeDisplayString(value.title, 240) &&
    isIntegerInRange(value.durationMs, 0, Number.MAX_SAFE_INTEGER) &&
    (value.mediaType === 'movie' || value.mediaType === 'episode') &&
    (value.parentTitle === undefined || isSafeDisplayString(value.parentTitle, 240)) &&
    (value.year === undefined || isIntegerInRange(value.year, 1800, 3000)) &&
    (value.seasonNumber === undefined || isIntegerInRange(value.seasonNumber, 0, 10_000)) &&
    (value.episodeNumber === undefined || isIntegerInRange(value.episodeNumber, 0, 10_000));
}

function cloneContent(
  content: readonly CustomChannelContentEntryInput[],
): readonly CustomChannelContentEntryInput[] {
  return content.map((entry) => ({ ...entry }));
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

function isSafeId(value: unknown): value is string {
  return typeof value === 'string' &&
    value.trim() === value &&
    SAFE_ID_PATTERN.test(value);
}

function isSafeDisplayString(value: unknown, maxLength: number): value is string {
  return typeof value === 'string' &&
    value.length <= maxLength &&
    !/[<>]/u.test(value);
}

function isIntegerInRange(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' &&
    Number.isFinite(value) &&
    Number.isInteger(value) &&
    value >= min &&
    value <= max;
}

function isStringInSet<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === 'string' && values.includes(value as T);
}

function isMediaType(value: unknown): boolean {
  return isStringInSet(value, MEDIA_TYPES);
}

function getElectronIpcMain(): CustomChannelIpcMain {
  const require = createRequire(import.meta.url);
  return require('electron').ipcMain as CustomChannelIpcMain;
}
