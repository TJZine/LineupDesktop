import type { EpgPresentationSource, GuideIpcResult } from '../contracts/guide.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import { isSafeArtworkRefId, type ArtworkRef } from '../contracts/artwork.js';

export type GuideBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export type GuideBridgeChannels = {
  getPresentation: string;
  tuneChannel: string;
};

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const MAX_GUIDE_PRESENTATION_DURATION_MS = 7 * 24 * 60 * 60 * 1000;

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
        input.startTimeMs < 0 ||
        typeof input.durationMs !== 'number' ||
        !Number.isFinite(input.durationMs) ||
        input.durationMs <= 0 ||
        input.durationMs > MAX_GUIDE_PRESENTATION_DURATION_MS
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
        return isGuideResult<EpgPresentationSource>(result, requestId, isEpgPresentationSource)
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
      return isGuideResult<never>(result, requestId, isEmptyObject)
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

function isGuideResult<T>(
  value: unknown,
  requestId: string,
  isValue: (candidate: unknown) => candidate is T,
): value is GuideIpcResult<T> {
  if (!isPlainRecord(value)) {
    return false;
  }
  if (typeof value.requestId !== 'string' || value.requestId !== requestId || !REQUEST_ID_PATTERN.test(value.requestId)) {
    return false;
  }
  if (value.ok === true) {
    return hasOnlyKeys(value, ['ok', 'requestId', 'value']) && isValue(value.value);
  }
  if (value.ok === false) {
    return (
      hasOnlyKeys(value, ['ok', 'requestId', 'error']) &&
      isGuideRuntimeError(value.error)
    );
  }
  return false;
}

function isEpgPresentationSource(value: unknown): value is EpgPresentationSource {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['channels', 'nowWatching']) &&
    Array.isArray(value.channels) &&
    value.channels.every(isEpgChannelViewModel) &&
    (value.nowWatching === null || isEpgCurrentProgramViewModel(value.nowWatching))
  );
}

function isEpgChannelViewModel(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'number', 'name', 'programs']) &&
    isSafeString(value.id) &&
    isSafeString(value.number) &&
    isSafeDisplayString(value.name) &&
    Array.isArray(value.programs) &&
    value.programs.every(isEpgProgramViewModel)
  );
}

function isEpgProgramViewModel(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, [
      'id',
      'title',
      'subtitle',
      'description',
      'showTitle',
      'episodeLabel',
      'rating',
      'quality',
      'genres',
      'startsAtMs',
      'endsAtMs',
      'artwork',
    ]) &&
    isSafeString(value.id) &&
    isBoundedSafeDisplayString(value.title, 160) &&
    isSafeDisplayString(value.subtitle) &&
    isBoundedSafeDisplayString(value.description, 600) &&
    isSafeDisplayString(value.showTitle) &&
    isSafeDisplayString(value.episodeLabel) &&
    isSafeDisplayString(value.rating) &&
    Array.isArray(value.quality) &&
    value.quality.every(isSafeDisplayString) &&
    Array.isArray(value.genres) &&
    value.genres.every(isSafeDisplayString) &&
    isFiniteNonNegativeNumber(value.startsAtMs) &&
    isFiniteNonNegativeNumber(value.endsAtMs) &&
    value.endsAtMs > value.startsAtMs &&
    (value.artwork === null || isArtworkRef(value.artwork))
  );
}

function isEpgCurrentProgramViewModel(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['title', 'subtitle', 'channelId', 'startsAtMs', 'endsAtMs']) &&
    isSafeDisplayString(value.title) &&
    isSafeDisplayString(value.subtitle) &&
    isSafeString(value.channelId) &&
    isFiniteNonNegativeNumber(value.startsAtMs) &&
    isFiniteNonNegativeNumber(value.endsAtMs) &&
    value.endsAtMs > value.startsAtMs
  );
}

function isGuideRuntimeError(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    isSafeString(value.code) &&
    isSafeDisplayString(value.message) &&
    typeof value.retryable === 'boolean' &&
    typeof value.recoverable === 'boolean' &&
    isSafeString(value.operation)
  );
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function hasOnlyKeys(value: Record<string, unknown>, allowedKeys: readonly string[]): boolean {
  const allowed = new Set(allowedKeys);
  return allowedKeys.every((key) => Object.hasOwn(value, key)) &&
    Object.keys(value).every((key) => allowed.has(key));
}

function isEmptyObject(value: unknown): value is never {
  return isPlainRecord(value) && Object.keys(value).length === 0;
}

function isSafeString(value: unknown): value is string {
  return typeof value === 'string' &&
    value.length > 0 &&
    value.length <= 120 &&
    REQUEST_ID_PATTERN.test(value);
}

function isSafeDisplayString(value: unknown): value is string {
  return isBoundedSafeDisplayString(value, 2000);
}

function isBoundedSafeDisplayString(value: unknown, maximum: number): value is string {
  return typeof value === 'string' &&
    value.length <= maximum &&
    !/[<>]/u.test(value) &&
    !/https?:\/\//iu.test(value) &&
    !/\b(?:bearer|token|authorization|headers?)\s*[:=]/iu.test(value);
}

function isArtworkRef(value: unknown): value is ArtworkRef {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'kind', 'expiresAtMs', 'altText', 'status']) &&
    isSafeArtworkRefId(value.id) &&
    value.kind === 'poster' &&
    isFiniteNonNegativeNumber(value.expiresAtMs) &&
    Number.isSafeInteger(value.expiresAtMs) &&
    isBoundedSafeDisplayString(value.altText, 160) &&
    (value.status === 'available' || value.status === 'placeholder');
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}
