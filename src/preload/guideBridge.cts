import type { EpgPresentationSource, GuideIpcResult } from '../contracts/guide.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';

export type GuideBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export type GuideBridgeChannels = {
  getPresentation: string;
  tuneChannel: string;
};

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;

export function createGuideBridge(
  invoke: GuideBridgeInvoke,
  channels: GuideBridgeChannels,
  createRequestId: (prefix: string) => string,
): LineupDesktopPreloadApi['guide'] {
  return {
    getPresentation: async (input) => {
      const requestId = createRequestId('guide-presentation');
      if (
        typeof input !== 'object' ||
        input === null ||
        typeof input.startTimeMs !== 'number' ||
        !Number.isFinite(input.startTimeMs) ||
        typeof input.durationMs !== 'number' ||
        !Number.isFinite(input.durationMs)
      ) {
        return guideValidationFailure(requestId, 'getPresentation', 'Invalid presentation time range options.');
      }
      try {
        const result = await invoke(channels.getPresentation, {
          requestId,
          payload: {
            startTimeMs: input.startTimeMs,
            durationMs: input.durationMs,
          },
        });
        return isGuideResult<EpgPresentationSource>(result)
          ? result
          : guideValidationFailure(requestId, 'getPresentation', 'Invalid guide result envelope received.');
      } catch {
        return guideValidationFailure(requestId, 'getPresentation', 'Internal IPC invoke failed.');
      }
    },
  };
}

export function createPlayerTuneBridge(
  invoke: GuideBridgeInvoke,
  channelName: string,
  createRequestId: (prefix: string) => string,
): (input: { channelId: string }) => Promise<GuideIpcResult<never>> {
  return async (input) => {
    const requestId = createRequestId('player-tune');
    if (
      typeof input !== 'object' ||
      input === null ||
      typeof input.channelId !== 'string' ||
      input.channelId.trim().length === 0 ||
      input.channelId.length > 120 ||
      !REQUEST_ID_PATTERN.test(input.channelId)
    ) {
      return guideValidationFailure(requestId, 'tuneChannel', 'Invalid channel ID parameter.');
    }
    try {
      const result = await invoke(channelName, {
        requestId,
        payload: {
          channelId: input.channelId,
        },
      });
      return isGuideResult<never>(result)
        ? result
        : guideValidationFailure(requestId, 'tuneChannel', 'Invalid tuning result envelope received.');
    } catch {
      return guideValidationFailure(requestId, 'tuneChannel', 'Internal IPC invoke failed.');
    }
  };
}

function guideValidationFailure<T>(
  requestId: string,
  operation: string,
  message = 'Request is invalid.',
): GuideIpcResult<T> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'GUIDE_VALIDATION_FAILED',
      message,
      retryable: false,
      recoverable: false,
      operation,
    },
  };
}

function isGuideResult<T>(value: unknown): value is GuideIpcResult<T> {
  if (typeof value !== 'object' || value === null) {
    return false;
  }
  const record = value as Record<string, unknown>;
  if (typeof record.requestId !== 'string') {
    return false;
  }
  if (record.ok === true) {
    return 'value' in record;
  }
  if (record.ok === false) {
    return (
      typeof record.error === 'object' &&
      record.error !== null &&
      typeof (record.error as any).code === 'string' &&
      typeof (record.error as any).message === 'string'
    );
  }
  return false;
}
