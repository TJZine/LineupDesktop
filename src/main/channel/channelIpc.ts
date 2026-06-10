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
  LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
  LINEUP_PLAYER_TUNE_CHANNEL,
} from '../../contracts/ipc.js';
import type { ChannelRuntime } from './channelRuntime.js';
import type { GuideRuntime } from './guideRuntime.js';
import type { GuideIpcResult } from '../../contracts/guide.js';

type ChannelIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterChannelIpcHandlersOptions {
  runtime: ChannelRuntime;
  guideRuntime?: GuideRuntime;
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

  if (options.guideRuntime) {
    const guideRuntime = options.guideRuntime;

    ipcMain.handle(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL, async (event, payload: unknown) => {
      const request = readPresentationRequest(payload, options);
      if (!options.isAuthorizedEvent(event)) {
        return unauthorizedGuideResult(request.requestId, 'getPresentation');
      }
      if (!request.ok) {
        return validationGuideResult(request.requestId, 'getPresentation');
      }
      try {
        const value = await guideRuntime.getPresentation(
          request.payload.startTimeMs,
          request.payload.durationMs,
        );
        return { ok: true, value, requestId: request.requestId };
      } catch (error: any) {
        return {
          ok: false,
          requestId: request.requestId,
          error: {
            code: 'GUIDE_PRESENTATION_FAILED',
            message: error?.message || 'Failed to fetch guide presentation.',
            retryable: true,
            recoverable: true,
            operation: 'getPresentation',
          },
        };
      }
    });

    ipcMain.handle(LINEUP_PLAYER_TUNE_CHANNEL, async (event, payload: unknown) => {
      const request = readTuneRequest(payload, options);
      if (!options.isAuthorizedEvent(event)) {
        return unauthorizedGuideResult(request.requestId, 'tuneChannel');
      }
      if (!request.ok) {
        return validationGuideResult(request.requestId, 'tuneChannel');
      }
      try {
        await guideRuntime.tuneChannel(request.payload.channelId);
        return { ok: true, value: {}, requestId: request.requestId };
      } catch (error: any) {
        return {
          ok: false,
          requestId: request.requestId,
          error: {
            code: 'CHANNEL_TUNING_FAILED',
            message: error?.message || 'Failed to tune channel.',
            retryable: true,
            recoverable: true,
            operation: 'tuneChannel',
          },
        };
      }
    });
  }

  return async () => {
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL);
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_COMMIT_CHANNEL);
    if (options.guideRuntime) {
      ipcMain.removeHandler(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL);
      ipcMain.removeHandler(LINEUP_PLAYER_TUNE_CHANNEL);
    }
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

type ReadPresentationRequestResult =
  | { ok: true; requestId: string; payload: { startTimeMs: number; durationMs: number } }
  | { ok: false; requestId: string; payload: Partial<{ startTimeMs: number; durationMs: number }> };

function readPresentationRequest(
  value: unknown,
  options: Pick<RegisterChannelIpcHandlersOptions, 'createRequestId'>,
): ReadPresentationRequestResult {
  const fallbackRequestId = options.createRequestId('guide-presentation');
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
    !hasOnlyKeys(value.payload, ['startTimeMs', 'durationMs']) ||
    typeof value.payload.startTimeMs !== 'number' ||
    !Number.isFinite(value.payload.startTimeMs) ||
    typeof value.payload.durationMs !== 'number' ||
    !Number.isFinite(value.payload.durationMs)
  ) {
    return { ok: false, requestId, payload: {} };
  }
  return {
    ok: true,
    requestId,
    payload: {
      startTimeMs: value.payload.startTimeMs,
      durationMs: value.payload.durationMs,
    },
  };
}

type ReadTuneRequestResult =
  | { ok: true; requestId: string; payload: { channelId: string } }
  | { ok: false; requestId: string; payload: Partial<{ channelId: string }> };

function readTuneRequest(
  value: unknown,
  options: Pick<RegisterChannelIpcHandlersOptions, 'createRequestId'>,
): ReadTuneRequestResult {
  const fallbackRequestId = options.createRequestId('player-tune');
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
    !hasOnlyKeys(value.payload, ['channelId']) ||
    typeof value.payload.channelId !== 'string' ||
    value.payload.channelId.trim().length === 0
  ) {
    return { ok: false, requestId, payload: {} };
  }
  return {
    ok: true,
    requestId,
    payload: {
      channelId: value.payload.channelId,
    },
  };
}

function unauthorizedGuideResult(
  requestId: string,
  operation: 'getPresentation' | 'tuneChannel',
): GuideIpcResult<never> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'GUIDE_UNAUTHORIZED',
      message: 'Guide request is not authorized.',
      retryable: false,
      recoverable: false,
      operation,
    },
  };
}

function validationGuideResult(
  requestId: string,
  operation: 'getPresentation' | 'tuneChannel',
): GuideIpcResult<never> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'GUIDE_VALIDATION_FAILED',
      message: 'Guide request payload is invalid.',
      retryable: false,
      recoverable: false,
      operation,
    },
  };
}
