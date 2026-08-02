import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import type {
  ChannelSetupCancelRequest,
  ChannelSetupGetOperationRequest,
  ChannelSetupGetStatusRequest,
  ChannelSetupStartApplyRequest,
  ChannelSetupStartReviewRequest,
} from '../../contracts/channel.js';
import {
  channelSetupFailure,
} from '../../contracts/channel.js';
import {
  LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL,
  LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
  LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL,
  LINEUP_PLAYER_TUNE_CHANNEL,
} from '../../contracts/ipc.js';
import type { ChannelRuntime } from './channelRuntime.js';
import type { GuideRuntime } from './guideRuntime.js';
import {
  ChannelPublicReferenceConsistencyError,
  type ChannelPublicReferenceOwner,
} from './channelPublicReferenceOwner.js';
import type { GuideIpcResult, GuideRuntimeError } from '../../contracts/guide.js';
import {
  DesktopGuidePreferencesCommitCurrentnessError,
  DesktopGuidePreferencesStoreError,
} from './desktopGuidePreferencesStore.js';
import { LivePlexTransportError } from '../plex/livePlexTransport.js';
import {
  channelBuilderRequestError,
  readChannelSetupEmptyRequest,
  readChannelSetupOperationRequest,
  readChannelSetupStartApplyRequest,
  readChannelSetupStartReviewRequest,
} from './channelBuilderIpcValidation.js';

type ChannelIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterChannelIpcHandlersOptions {
  runtime: ChannelRuntime;
  guideRuntime?: GuideRuntime;
  publicReferenceOwner?: ChannelPublicReferenceOwner;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  ipcMain?: ChannelIpcMain;
}

export type ChannelIpcTeardown = () => Promise<void>;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const MAX_GUIDE_PRESENTATION_DURATION_MS = 7 * 24 * 60 * 60 * 1000;

export function registerChannelIpcHandlers(
  options: RegisterChannelIpcHandlersOptions,
): ChannelIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();

  ipcMain.handle(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL, (event, payload: unknown) => {
    const request = readChannelSetupEmptyRequest(
      payload,
      options.createRequestId('channel-setup-status'),
    );
    if (!isAuthorizedChannelEvent(options, event)) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('getStatus', 'unauthorized'));
    }
    if (!request.ok) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('getStatus', 'validation'));
    }
    return options.runtime.getStatus(request.requestId);
  });

  ipcMain.handle(LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL, (event, payload: unknown) => {
    const request = readChannelSetupStartReviewRequest(
      payload,
      options.createRequestId('channel-setup-review'),
    );
    if (!isAuthorizedChannelEvent(options, event)) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('startReview', 'unauthorized'));
    }
    if (!request.ok) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('startReview', 'validation'));
    }
    return options.runtime.startReview(request.requestId, request.payload.config);
  });

  ipcMain.handle(LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL, (event, payload: unknown) => {
    const request = readChannelSetupStartApplyRequest(
      payload,
      options.createRequestId('channel-setup-apply'),
    );
    if (!isAuthorizedChannelEvent(options, event)) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('startApply', 'unauthorized'));
    }
    if (!request.ok) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('startApply', 'validation'));
    }
    return options.runtime.startApply(request.requestId, request.payload);
  });

  ipcMain.handle(LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL, (event, payload: unknown) => {
    const request = readChannelSetupOperationRequest(
      payload,
      options.createRequestId('channel-setup-operation'),
    );
    if (!isAuthorizedChannelEvent(options, event)) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('getOperation', 'unauthorized'));
    }
    if (!request.ok) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('getOperation', 'validation'));
    }
    return options.runtime.getOperation(request.requestId, request.payload.operationId);
  });

  ipcMain.handle(LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL, (event, payload: unknown) => {
    const request = readChannelSetupOperationRequest(
      payload,
      options.createRequestId('channel-setup-cancel'),
    );
    if (!isAuthorizedChannelEvent(options, event)) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('cancel', 'unauthorized'));
    }
    if (!request.ok) {
      return channelSetupFailure(request.requestId, channelBuilderRequestError('cancel', 'validation'));
    }
    return options.runtime.cancel(request.requestId, request.payload.operationId);
  });

  if (options.guideRuntime && options.publicReferenceOwner) {
    const guideRuntime = options.guideRuntime;
    const publicReferenceOwner = options.publicReferenceOwner;

    ipcMain.handle(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL, async (event, payload: unknown) => {
      const request = readPresentationRequest(payload, options);
      if (!isAuthorizedChannelEvent(options, event)) {
        return unauthorizedGuideResult(request.requestId, 'getPresentation');
      }
      if (!request.ok) {
        return validationGuideResult(request.requestId, 'getPresentation');
      }
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          const generationA = await options.runtime.loadPublicReferenceGeneration();
          const value = await guideRuntime.getPagedPresentation({
            startTimeMs: request.payload.startTimeMs,
            durationMs: request.payload.durationMs,
            channelOffset: request.payload.channelOffset,
            channelLimit: request.payload.channelLimit,
            generation: generationA,
            publicReferenceOwner,
          });
          const generationB = await options.runtime.loadPublicReferenceGeneration();
          if (generationA.fingerprint !== generationB.fingerprint ||
            !guideRuntime.isPreferenceScopeCurrent(value.libraryFilter.scopeToken)) continue;
          return { ok: true, value, requestId: request.requestId };
        } catch (error: unknown) {
          if (error instanceof ChannelPublicReferenceConsistencyError) continue;
          return {
            ok: false,
            requestId: request.requestId,
            error: mapGuidePresentationError(error),
          };
        }
      }
      return {
        ok: false,
        requestId: request.requestId,
        error: {
          code: 'GUIDE_PRESENTATION_STALE',
          message: 'Guide changed while loading. Try again.',
          retryable: true,
          recoverable: true,
          operation: 'getPresentation',
        },
      };
    });

    ipcMain.handle(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL, async (event, payload: unknown) => {
      const request = readSetLibraryFilterRequest(payload, options);
      if (!isAuthorizedChannelEvent(options, event)) return unauthorizedGuideResult(request.requestId, 'setLibraryFilter');
      if (!request.ok) return validationGuideResult(request.requestId, 'setLibraryFilter');
      try {
        const generation = await options.runtime.loadPublicReferenceGeneration();
        const value = await guideRuntime.setLibraryFilter({
          generation,
          publicReferenceOwner,
          expectedScopeToken: request.payload.expectedScopeToken,
          expectedRevision: request.payload.expectedRevision,
          libraryId: request.payload.libraryId,
          isCommitCurrent: () => isAuthorizedChannelEvent(options, event),
        });
        const currentGeneration = await options.runtime.loadPublicReferenceGeneration();
        if (currentGeneration.fingerprint !== generation.fingerprint ||
          !guideRuntime.isPreferenceScopeCurrent(value.scopeToken)) {
          return { ok: false, requestId: request.requestId, error: mapGuideFilterCode('GUIDE_FILTER_SCOPE_STALE') };
        }
        return { ok: true, value, requestId: request.requestId };
      } catch (error: unknown) {
        return error instanceof DesktopGuidePreferencesCommitCurrentnessError
          ? unauthorizedGuideResult(request.requestId, 'setLibraryFilter')
          : error instanceof DesktopGuidePreferencesStoreError
          ? { ok: false, requestId: request.requestId, error: mapGuideFilterError(error) }
          : validationGuideResult(request.requestId, 'setLibraryFilter');
      }
    });

    ipcMain.handle(LINEUP_PLAYER_TUNE_CHANNEL, async (event, payload: unknown) => {
      const request = readTuneRequest(payload, options);
      if (!isAuthorizedChannelEvent(options, event)) {
        return unauthorizedGuideResult(request.requestId, 'tuneChannel');
      }
      if (!request.ok) {
        return validationGuideResult(request.requestId, 'tuneChannel');
      }
      try {
        const generation = await options.runtime.loadPublicReferenceGeneration();
        const rawChannelId = publicReferenceOwner.resolveChannel(
          generation,
          request.payload.channelId,
        );
        if (rawChannelId === null) {
          return validationGuideResult(request.requestId, 'tuneChannel');
        }
        await guideRuntime.tuneChannel(rawChannelId);
        return { ok: true, value: {}, requestId: request.requestId };
      } catch {
        return {
          ok: false,
          requestId: request.requestId,
          error: {
            code: 'GUIDE_TUNE_FAILED',
            message: 'Channel could not be tuned.',
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
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL);
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL);
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL);
    ipcMain.removeHandler(LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL);
    if (options.guideRuntime) {
      ipcMain.removeHandler(LINEUP_GUIDE_GET_PRESENTATION_CHANNEL);
      ipcMain.removeHandler(LINEUP_GUIDE_SET_LIBRARY_FILTER_CHANNEL);
      ipcMain.removeHandler(LINEUP_PLAYER_TUNE_CHANNEL);
    }
  };
}

function isAuthorizedChannelEvent(
  options: Pick<RegisterChannelIpcHandlersOptions, 'isAuthorizedEvent'>,
  event: IpcMainInvokeEvent,
): boolean {
  try {
    return options.isAuthorizedEvent(event);
  } catch {
    return false;
  }
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

function getElectronIpcMain(): ChannelIpcMain {
  const require = createRequire(import.meta.url);
  return require('electron').ipcMain as ChannelIpcMain;
}

export type ChannelIpcRequestEnvelope =
  | ChannelSetupGetStatusRequest
  | ChannelSetupStartReviewRequest
  | ChannelSetupStartApplyRequest
  | ChannelSetupGetOperationRequest
  | ChannelSetupCancelRequest;

type ReadPresentationRequestResult =
  | { ok: true; requestId: string; payload: { startTimeMs: number; durationMs: number; channelOffset: number; channelLimit: number } }
  | { ok: false; requestId: string; payload: Partial<{ startTimeMs: number; durationMs: number; channelOffset: number; channelLimit: number }> };

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
    !hasOnlyOptionalKeys(value.payload, ['startTimeMs', 'durationMs'], ['channelOffset', 'channelLimit']) ||
    typeof value.payload.startTimeMs !== 'number' ||
    !Number.isFinite(value.payload.startTimeMs) ||
    value.payload.startTimeMs < 0 ||
    typeof value.payload.durationMs !== 'number' ||
    !Number.isFinite(value.payload.durationMs) ||
    value.payload.durationMs <= 0 ||
    value.payload.durationMs > MAX_GUIDE_PRESENTATION_DURATION_MS ||
    (value.payload.channelOffset !== undefined && (typeof value.payload.channelOffset !== 'number' || !Number.isSafeInteger(value.payload.channelOffset) || value.payload.channelOffset < 0)) ||
    (value.payload.channelLimit !== undefined && (typeof value.payload.channelLimit !== 'number' || !Number.isSafeInteger(value.payload.channelLimit) || value.payload.channelLimit < 1 || value.payload.channelLimit > 24))
  ) {
    return { ok: false, requestId, payload: {} };
  }
  return {
    ok: true,
    requestId,
    payload: {
      startTimeMs: value.payload.startTimeMs,
      durationMs: value.payload.durationMs,
      channelOffset: typeof value.payload.channelOffset === 'number' ? value.payload.channelOffset : 0,
      channelLimit: typeof value.payload.channelLimit === 'number' ? value.payload.channelLimit : 9,
    },
  };
}

function readErrorMessage(error: unknown): string | null {
  if (error instanceof Error) {
    return error.message;
  }
  return null;
}

function mapGuidePresentationError(error: unknown): GuideRuntimeError {
  if (error instanceof LivePlexTransportError) {
    const isAuthError = error.code === 'auth-required' || error.code === 'auth-invalid';
    const isNotFoundError = error.code === 'resource-not-found';
    return {
      code: isAuthError
        ? 'GUIDE_AUTH_FAILED'
        : isNotFoundError
          ? 'GUIDE_CHANNEL_NOT_FOUND'
          : 'GUIDE_TRANSPORT_ERROR',
      message: readErrorMessage(error) || 'Failed to fetch guide presentation.',
      retryable: error.retryable,
      recoverable: true,
      operation: 'getPresentation',
    };
  }

  return {
    code: 'GUIDE_PRESENTATION_FAILED',
    message: 'Guide presentation could not be projected.',
    retryable: true,
    recoverable: true,
    operation: 'getPresentation',
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
    value.payload.channelId.trim().length === 0 ||
    value.payload.channelId.length > 120 ||
    !REQUEST_ID_PATTERN.test(value.payload.channelId)
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
  operation: 'getPresentation' | 'setLibraryFilter' | 'tuneChannel',
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
  operation: 'getPresentation' | 'setLibraryFilter' | 'tuneChannel',
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

type ReadSetLibraryFilterResult =
  | { ok: true; requestId: string; payload: { expectedScopeToken: string; expectedRevision: number; libraryId: string | null } }
  | { ok: false; requestId: string; payload: Record<string, never> };

function readSetLibraryFilterRequest(
  value: unknown,
  options: Pick<RegisterChannelIpcHandlersOptions, 'createRequestId'>,
): ReadSetLibraryFilterResult {
  const fallbackRequestId = options.createRequestId('guide-library-filter');
  if (!isPlainRecord(value)) return { ok: false, requestId: fallbackRequestId, payload: {} };
  const requestId = typeof value.requestId === 'string' && REQUEST_ID_PATTERN.test(value.requestId)
    ? value.requestId : fallbackRequestId;
  if (typeof value.requestId !== 'string' || !REQUEST_ID_PATTERN.test(value.requestId) ||
    !isPlainRecord(value.payload) || !hasOnlyKeys(value, ['requestId', 'payload']) ||
    !hasOnlyKeys(value.payload, ['expectedScopeToken', 'expectedRevision', 'libraryId']) ||
    typeof value.payload.expectedScopeToken !== 'string' || !REQUEST_ID_PATTERN.test(value.payload.expectedScopeToken) ||
    typeof value.payload.expectedRevision !== 'number' || !Number.isSafeInteger(value.payload.expectedRevision) || value.payload.expectedRevision < 0 ||
    !(value.payload.libraryId === null || (typeof value.payload.libraryId === 'string' && REQUEST_ID_PATTERN.test(value.payload.libraryId)))) {
    return { ok: false, requestId, payload: {} };
  }
  return { ok: true, requestId, payload: {
    expectedScopeToken: value.payload.expectedScopeToken,
    expectedRevision: value.payload.expectedRevision,
    libraryId: value.payload.libraryId,
  } };
}

function mapGuideFilterError(error: DesktopGuidePreferencesStoreError): GuideRuntimeError {
  return mapGuideFilterCode(error.code);
}

function mapGuideFilterCode(code: DesktopGuidePreferencesStoreError['code']): GuideRuntimeError {
  const retryable = code !== 'GUIDE_FILTER_UNSUPPORTED_VERSION' && code !== 'GUIDE_FILTER_REVISION_EXHAUSTED';
  return {
    code,
    message: code === 'GUIDE_FILTER_SCOPE_STALE' ? 'Guide scope changed. Refresh and try again.'
      : code === 'GUIDE_FILTER_REVISION_CONFLICT' ? 'Guide filter changed. Refresh and try again.'
        : code === 'GUIDE_FILTER_UNSUPPORTED_VERSION' ? 'Guide preferences use an unsupported version.'
          : code === 'GUIDE_FILTER_REVISION_EXHAUSTED' ? 'Guide preference revision is exhausted.'
            : 'Guide preferences could not be saved.',
    retryable,
    recoverable: retryable,
    operation: 'setLibraryFilter',
  };
}

function hasOnlyOptionalKeys(value: Record<string, unknown>, required: readonly string[], optional: readonly string[]): boolean {
  const allowed = new Set([...required, ...optional]);
  return required.every((key) => Object.hasOwn(value, key)) && Object.keys(value).every((key) => allowed.has(key));
}
