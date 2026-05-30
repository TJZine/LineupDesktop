import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import type {
  ChannelSetupEmptyRequest,
  ChannelSetupIpcResult,
  ChannelSetupSummary,
  ChannelSetupCommitMode,
  ChannelSetupCommitRequest,
} from '../../contracts/channel.js';
import {
  channelSetupFailure,
} from '../../contracts/channel.js';
import {
  LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
} from '../../contracts/ipc.js';
import type { ChannelRuntime } from './channelRuntime.js';

type ChannelIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterChannelIpcHandlersOptions {
  runtime: ChannelRuntime;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  ipcMain?: ChannelIpcMain;
}

export type ChannelIpcTeardown = () => Promise<void>;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;

export function registerChannelIpcHandlers(
  options: RegisterChannelIpcHandlersOptions,
): ChannelIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();

  ipcMain.handle(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL, (event, payload: unknown) => {
    const request = readEmptyRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId);
    }
    if (!request.ok) {
      return validationResult(request.requestId);
    }
    return options.runtime.getStatus(request.requestId);
  });

  ipcMain.handle(LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL, (event, payload: unknown) => {
    const request = readCommitRequest(payload, options);
    if (!options.isAuthorizedEvent(event)) {
      return unauthorizedResult(request.requestId, 'commit');
    }
    if (!request.ok) {
      return validationResult(request.requestId, 'commit');
    }
    return options.runtime.commit(request.requestId, request.payload);
  });

  return async () => {
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL);
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL);
  };
}

type ReadRequestResult =
  | { ok: true; requestId: string; payload: Record<string, never> }
  | { ok: false; requestId: string; payload: Partial<Record<string, never>> };

function readEmptyRequest(
  value: unknown,
  options: Pick<RegisterChannelIpcHandlersOptions, 'createRequestId'>,
): ReadRequestResult {
  const fallbackRequestId = options.createRequestId('channel-setup-status');
  if (!isPlainRecord(value)) {
    return { ok: false, requestId: fallbackRequestId, payload: {} };
  }
  const requestId =
    typeof value.requestId === 'string' && REQUEST_ID_PATTERN.test(value.requestId)
      ? value.requestId
      : fallbackRequestId;
  if (
    typeof value.requestId !== 'string' ||
    !REQUEST_ID_PATTERN.test(value.requestId) ||
    !isPlainRecord(value.payload) ||
    !hasOnlyKeys(value, ['requestId', 'payload']) ||
    Object.keys(value.payload).length !== 0
  ) {
    return { ok: false, requestId, payload: {} };
  }
  return { ok: true, requestId, payload: value.payload as Record<string, never> };
}

type ReadCommitRequestResult =
  | { ok: true; requestId: string; payload: ChannelSetupCommitRequest['payload'] }
  | { ok: false; requestId: string; payload: Partial<ChannelSetupCommitRequest['payload']> };

function readCommitRequest(
  value: unknown,
  options: Pick<RegisterChannelIpcHandlersOptions, 'createRequestId'>,
): ReadCommitRequestResult {
  const fallbackRequestId = options.createRequestId('channel-setup-commit');
  if (!isPlainRecord(value)) {
    return { ok: false, requestId: fallbackRequestId, payload: {} };
  }
  const requestId =
    typeof value.requestId === 'string' && REQUEST_ID_PATTERN.test(value.requestId)
      ? value.requestId
      : fallbackRequestId;
  if (
    typeof value.requestId !== 'string' ||
    !REQUEST_ID_PATTERN.test(value.requestId) ||
    !isPlainRecord(value.payload) ||
    !hasOnlyKeys(value, ['requestId', 'payload']) ||
    !hasOnlyKeys(value.payload, ['mode', 'sectionIds', 'confirmReplace']) ||
    !isCommitMode(value.payload.mode) ||
    !Array.isArray(value.payload.sectionIds) ||
    value.payload.sectionIds.length === 0 ||
    value.payload.sectionIds.length > 24 ||
    !value.payload.sectionIds.every(isSafeChannelId) ||
    (
      value.payload.confirmReplace !== undefined &&
      typeof value.payload.confirmReplace !== 'boolean'
    )
  ) {
    return { ok: false, requestId, payload: {} };
  }
  return {
    ok: true,
    requestId,
    payload: {
      mode: value.payload.mode,
      sectionIds: [...value.payload.sectionIds],
      ...(value.payload.confirmReplace === undefined ? {} : { confirmReplace: value.payload.confirmReplace }),
    },
  };
}

function unauthorizedResult(
  requestId: string,
  operation: 'getStatus' | 'commit' = 'getStatus',
): ChannelSetupIpcResult<ChannelSetupSummary> {
  return channelSetupFailure(requestId, {
    code: 'CHANNEL_UNAUTHORIZED',
    message: 'Channel setup request is not authorized.',
    retryable: false,
    recoverable: false,
    operation,
  });
}

function validationResult(
  requestId: string,
  operation: 'getStatus' | 'commit' = 'getStatus',
): ChannelSetupIpcResult<ChannelSetupSummary> {
  return channelSetupFailure(requestId, {
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Channel setup request payload is invalid.',
    retryable: false,
    recoverable: false,
    operation,
  });
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasOnlyKeys(value: object, requiredKeys: readonly string[]): boolean {
  const allowed = new Set(requiredKeys);
  return requiredKeys.filter((key) => key !== 'confirmReplace').every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function isCommitMode(value: unknown): value is ChannelSetupCommitMode {
  return value === 'append' || value === 'replace';
}

function isSafeChannelId(value: unknown): value is string {
  return typeof value === 'string' &&
    value.trim() === value &&
    value.length > 0 &&
    value.length <= 120 &&
    REQUEST_ID_PATTERN.test(value);
}

function getElectronIpcMain(): ChannelIpcMain {
  const require = createRequire(import.meta.url);
  return require('electron').ipcMain as ChannelIpcMain;
}

export type ChannelIpcRequestEnvelope = ChannelSetupEmptyRequest | ChannelSetupCommitRequest;
