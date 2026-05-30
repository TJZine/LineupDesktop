import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import type {
  ChannelSetupEmptyRequest,
  ChannelSetupIpcResult,
  ChannelSetupSummary,
} from '../../contracts/channel.js';
import {
  channelSetupFailure,
} from '../../contracts/channel.js';
import { LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL } from '../../contracts/ipc.js';
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

  return async () => {
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL);
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

function unauthorizedResult(requestId: string): ChannelSetupIpcResult<ChannelSetupSummary> {
  return channelSetupFailure(requestId, {
    code: 'CHANNEL_UNAUTHORIZED',
    message: 'Channel setup request is not authorized.',
    retryable: false,
    recoverable: false,
    operation: 'getStatus',
  });
}

function validationResult(requestId: string): ChannelSetupIpcResult<ChannelSetupSummary> {
  return channelSetupFailure(requestId, {
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Channel setup request payload is invalid.',
    retryable: false,
    recoverable: false,
    operation: 'getStatus',
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
  return requiredKeys.every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function getElectronIpcMain(): ChannelIpcMain {
  const require = createRequire(import.meta.url);
  return require('electron').ipcMain as ChannelIpcMain;
}

export type ChannelIpcRequestEnvelope = ChannelSetupEmptyRequest;
