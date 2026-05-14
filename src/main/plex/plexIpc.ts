import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_PLEX_CANCEL_PIN_CHANNEL,
  LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
  LINEUP_PLEX_GET_METADATA_CHANNEL,
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
  LINEUP_PLEX_SELECT_SERVER_CHANNEL,
  LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
} from '../../contracts/ipc.js';
import type {
  PlexCancelPinRequest,
  PlexCancelPinValue,
  PlexEmptyRequest,
  PlexGetMetadataRequest,
  PlexGetMetadataValue,
  PlexGetHomeUsersValue,
  PlexIpcRequest,
  PlexIpcResult,
  PlexListLibraryItemsRequest,
  PlexListLibraryItemsValue,
  PlexListLibrarySectionsValue,
  PlexPollPinRequest,
  PlexPollPinValue,
  PlexRefreshServersValue,
  PlexRequestPinValue,
  PlexRestoreSelectedServerValue,
  PlexRuntimeError,
  PlexRuntimeOperation,
  PlexRuntimeSnapshot,
  PlexSearchLibraryRequest,
  PlexSearchLibraryValue,
  PlexSelectServerRequest,
  PlexSelectServerValue,
  PlexSwitchHomeUserRequest,
  PlexSwitchHomeUserValue,
} from '../../contracts/plex.js';
import type { DesktopPlexRuntime } from './desktopPlexRuntime.js';

type PlexIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterPlexIpcHandlersOptions {
  runtime: DesktopPlexRuntime;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  ipcMain?: PlexIpcMain;
}

export type PlexIpcTeardown = () => Promise<void>;

const PLEX_IPC_CHANNELS = [
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_CANCEL_PIN_CHANNEL,
  LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
  LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
  LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
  LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
  LINEUP_PLEX_SELECT_SERVER_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
  LINEUP_PLEX_GET_METADATA_CHANNEL,
] as const;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;

export function registerPlexIpcHandlers(options: RegisterPlexIpcHandlersOptions): PlexIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();

  ipcMain.handle(LINEUP_PLEX_GET_SNAPSHOT_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'getSnapshot');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'getSnapshot');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'getSnapshot');
    }
    return options.runtime.getSnapshot(request.requestId);
  });

  ipcMain.handle(LINEUP_PLEX_REQUEST_PIN_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'requestPin');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'requestPin');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'requestPin');
    }
    return options.runtime.requestPin(request.requestId);
  });

  ipcMain.handle(LINEUP_PLEX_POLL_PIN_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexPollPinRequest['payload']>(payload, options, 'pollPin');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'pollPin');
    }
    if (!request.ok || !hasOnlyKeys(request.payload, ['pinId']) || !isPositiveInteger(request.payload.pinId)) {
      return validationResult(request.requestId, 'pollPin');
    }
    return options.runtime.pollPin(request.requestId, request.payload.pinId);
  });

  ipcMain.handle(LINEUP_PLEX_CANCEL_PIN_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexCancelPinRequest['payload']>(payload, options, 'cancelPin');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'cancelPin');
    }
    if (!request.ok || !hasOnlyKeys(request.payload, ['pinId']) || !isPositiveInteger(request.payload.pinId)) {
      return validationResult(request.requestId, 'cancelPin');
    }
    return options.runtime.cancelPin(request.requestId, request.payload.pinId);
  });

  ipcMain.handle(LINEUP_PLEX_GET_HOME_USERS_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'getHomeUsers');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'getHomeUsers');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'getHomeUsers');
    }
    return options.runtime.getHomeUsers(request.requestId);
  });

  ipcMain.handle(LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexSwitchHomeUserRequest['payload']>(
      payload,
      options,
      'switchHomeUser',
    );
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'switchHomeUser');
    }
    if (
      !request.ok ||
      !hasOnlyKeys(request.payload, ['userId'], ['pin']) ||
      !isNonEmptyString(request.payload.userId) ||
      !isOptionalShortString(request.payload.pin)
    ) {
      return validationResult(request.requestId, 'switchHomeUser');
    }
    return options.runtime.switchHomeUser(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'restoreSelectedServer');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'restoreSelectedServer');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'restoreSelectedServer');
    }
    return options.runtime.restoreSelectedServer(request.requestId);
  });

  ipcMain.handle(LINEUP_PLEX_REFRESH_SERVERS_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'refreshServers');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'refreshServers');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'refreshServers');
    }
    return options.runtime.refreshServers(request.requestId);
  });

  ipcMain.handle(LINEUP_PLEX_SELECT_SERVER_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexSelectServerRequest['payload']>(payload, options, 'selectServer');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'selectServer');
    }
    if (!request.ok || !hasOnlyKeys(request.payload, ['serverId']) || !isNonEmptyString(request.payload.serverId)) {
      return validationResult(request.requestId, 'selectServer');
    }
    return options.runtime.selectServer(request.requestId, request.payload.serverId);
  });

  ipcMain.handle(LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options, 'listLibrarySections');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'listLibrarySections');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'listLibrarySections');
    }
    return options.runtime.listLibrarySections(request.requestId);
  });

  ipcMain.handle(LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexListLibraryItemsRequest['payload']>(
      payload,
      options,
      'listLibraryItems',
    );
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'listLibraryItems');
    }
    if (
      !request.ok ||
      !hasOnlyKeys(request.payload, ['sectionId'], ['offset', 'limit', 'sort']) ||
      !isNonEmptyString(request.payload.sectionId) ||
      !isOptionalFiniteNumber(request.payload.offset) ||
      !isOptionalFiniteNumber(request.payload.limit) ||
      !isOptionalShortString(request.payload.sort)
    ) {
      return validationResult(request.requestId, 'listLibraryItems');
    }
    return options.runtime.listLibraryItems(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexSearchLibraryRequest['payload']>(payload, options, 'searchLibrary');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'searchLibrary');
    }
    if (
      !request.ok ||
      !hasOnlyKeys(request.payload, ['query'], ['sectionId', 'limit']) ||
      !isNonEmptyString(request.payload.query) ||
      !isOptionalShortString(request.payload.sectionId) ||
      !isOptionalFiniteNumber(request.payload.limit)
    ) {
      return validationResult(request.requestId, 'searchLibrary');
    }
    return options.runtime.searchLibrary(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_PLEX_GET_METADATA_CHANNEL, (event, payload: unknown) => {
    const request = readPayloadRequest<PlexGetMetadataRequest['payload']>(payload, options, 'getMetadata');
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'getMetadata');
    }
    if (
      !request.ok ||
      !hasOnlyKeys(request.payload, ['ratingKey']) ||
      !isNonEmptyString(request.payload.ratingKey)
    ) {
      return validationResult(request.requestId, 'getMetadata');
    }
    return options.runtime.getMetadata(request.requestId, request.payload.ratingKey);
  });

  return async () => {
    await options.runtime.shutdown();
    for (const channel of PLEX_IPC_CHANNELS) {
      ipcMain.removeHandler(channel);
    }
  };
}

type ReadRequestResult<TPayload> =
  | { ok: true; requestId: string; payload: TPayload }
  | { ok: false; requestId: string; payload: Partial<TPayload> };

function readEmptyRequest(
  payload: unknown,
  options: Pick<RegisterPlexIpcHandlersOptions, 'createRequestId'>,
  operation: PlexRuntimeOperation,
): ReadRequestResult<Record<string, never>> {
  const request = readPayloadRequest<Record<string, never>>(payload, options, operation);
  if (!request.ok) {
    return request;
  }
  return Object.keys(request.payload).length === 0
    ? request
    : { ok: false, requestId: request.requestId, payload: request.payload };
}

function readPayloadRequest<TPayload>(
  value: unknown,
  options: Pick<RegisterPlexIpcHandlersOptions, 'createRequestId'>,
  operation: PlexRuntimeOperation,
): ReadRequestResult<TPayload> {
  const fallbackRequestId = options.createRequestId(`plex-${operation}`);
  if (!isPlainRecord(value)) {
    return { ok: false, requestId: fallbackRequestId, payload: {} as Partial<TPayload> };
  }
  const requestId =
    typeof value.requestId === 'string' && REQUEST_ID_PATTERN.test(value.requestId)
      ? value.requestId
      : fallbackRequestId;
  if (
    typeof value.requestId !== 'string' ||
    !REQUEST_ID_PATTERN.test(value.requestId) ||
    !isPlainRecord(value.payload) ||
    !hasOnlyKeys(value, ['requestId', 'payload'])
  ) {
    return { ok: false, requestId, payload: {} as Partial<TPayload> };
  }
  return { ok: true, requestId, payload: value.payload as TPayload };
}

function unauthorizedResult<T>(requestId: string, operation: PlexRuntimeOperation): PlexIpcResult<T> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'PLEX_UNAUTHORIZED',
      message: 'Plex request is not authorized.',
      retryable: false,
      recoverable: false,
      operation,
    },
  };
}

function validationResult<T>(requestId: string, operation: PlexRuntimeOperation): PlexIpcResult<T> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'PLEX_VALIDATION_FAILED',
      message: 'Plex request payload is invalid.',
      retryable: false,
      recoverable: false,
      operation,
    } satisfies PlexRuntimeError,
  };
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasOnlyKeys(
  value: object,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  return requiredKeys.every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0 && Math.floor(value) === value;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= 256;
}

function isOptionalShortString(value: unknown): value is string | null | undefined {
  return value === undefined || value === null || (typeof value === 'string' && value.length <= 256);
}

function isOptionalFiniteNumber(value: unknown): value is number | undefined {
  return value === undefined || (typeof value === 'number' && Number.isFinite(value));
}

function getElectronIpcMain(): PlexIpcMain {
  const require = createRequire(import.meta.url);
  return require('electron').ipcMain as PlexIpcMain;
}

export type PlexIpcResultValue =
  | PlexRuntimeSnapshot
  | PlexRequestPinValue
  | PlexPollPinValue
  | PlexCancelPinValue
  | PlexGetHomeUsersValue
  | PlexSwitchHomeUserValue
  | PlexRestoreSelectedServerValue
  | PlexRefreshServersValue
  | PlexSelectServerValue
  | PlexListLibrarySectionsValue
  | PlexListLibraryItemsValue
  | PlexSearchLibraryValue
  | PlexGetMetadataValue;

export type PlexIpcRequestEnvelope =
  | PlexEmptyRequest
  | PlexPollPinRequest
  | PlexCancelPinRequest
  | PlexSwitchHomeUserRequest
  | PlexSelectServerRequest
  | PlexListLibraryItemsRequest
  | PlexSearchLibraryRequest
  | PlexGetMetadataRequest
  | PlexIpcRequest<Record<string, never>>;
