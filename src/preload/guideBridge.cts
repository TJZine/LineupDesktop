import type { GuideLibraryFilterState, GuideIpcResult, GuidePresentationSource } from '../contracts/guide.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import { isSafeArtworkRefId, type ArtworkRef, type GuideArtworkSet } from '../contracts/artwork.js';

export type GuideBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export type GuideBridgeChannels = {
  getPresentation: string;
  cancelPresentation: string;
  setLibraryFilter: string;
  tuneChannel: string;
};

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const MAX_GUIDE_PRESENTATION_DURATION_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_GUIDE_CHANNELS = 24;
const MAX_GUIDE_PROGRAMS_PER_CHANNEL = 200;
const MAX_GUIDE_PROGRAMS = 1_000;

type GuideOperation = 'getPresentation' | 'setLibraryFilter' | 'tuneChannel';

const GUIDE_ERROR_OPERATIONS: Readonly<Record<string, readonly GuideOperation[]>> = Object.freeze({
  GUIDE_UNAUTHORIZED: ['getPresentation', 'setLibraryFilter', 'tuneChannel'],
  GUIDE_VALIDATION_FAILED: ['getPresentation', 'setLibraryFilter', 'tuneChannel'],
  GUIDE_PRESENTATION_STALE: ['getPresentation'],
  GUIDE_PRESENTATION_CANCELLED: ['getPresentation'],
  GUIDE_AUTH_FAILED: ['getPresentation'],
  GUIDE_CHANNEL_NOT_FOUND: ['getPresentation'],
  GUIDE_TRANSPORT_ERROR: ['getPresentation'],
  GUIDE_PRESENTATION_FAILED: ['getPresentation'],
  GUIDE_FILTER_SCOPE_STALE: ['setLibraryFilter'],
  GUIDE_FILTER_REVISION_CONFLICT: ['setLibraryFilter'],
  GUIDE_FILTER_STORAGE_UNAVAILABLE: ['setLibraryFilter'],
  GUIDE_FILTER_UNSUPPORTED_VERSION: ['setLibraryFilter'],
  GUIDE_FILTER_REVISION_EXHAUSTED: ['setLibraryFilter'],
  GUIDE_TUNE_FAILED: ['tuneChannel'],
});

export function createGuideBridge(
  invoke: GuideBridgeInvoke,
  channels: GuideBridgeChannels,
  createRequestId: (prefix: string) => string,
): LineupDesktopPreloadApi['guide'] {
  const activePresentationRequestIds = new Set<string>();
  return {
    getPresentation: async (input) => {
      const requestId = createRequestId('guide-presentation');
      if (
        !isPlainRecord(input) ||
        !hasOnlyOptionalKeys(input, ['startTimeMs', 'durationMs'], ['channelOffset', 'channelLimit']) ||
        typeof input.startTimeMs !== 'number' ||
        !Number.isFinite(input.startTimeMs) ||
        input.startTimeMs < 0 ||
        typeof input.durationMs !== 'number' ||
        !Number.isFinite(input.durationMs) ||
        input.durationMs <= 0 ||
        input.durationMs > MAX_GUIDE_PRESENTATION_DURATION_MS
        || (input.channelOffset !== undefined && (!Number.isSafeInteger(input.channelOffset) || input.channelOffset < 0))
        || (input.channelLimit !== undefined && (!Number.isSafeInteger(input.channelLimit) || input.channelLimit < 1 || input.channelLimit > 24))
      ) {
        return guideValidationFailure(requestId, 'getPresentation', 'Invalid presentation time range options.');
      }
      activePresentationRequestIds.add(requestId);
      try {
        const result = await invoke(channels.getPresentation, {
          requestId,
          payload: {
            startTimeMs: input.startTimeMs,
            durationMs: input.durationMs,
            ...(input.channelOffset === undefined ? {} : { channelOffset: input.channelOffset }),
            ...(input.channelLimit === undefined ? {} : { channelLimit: input.channelLimit }),
          },
        });
        return isGuideResult<GuidePresentationSource>(result, requestId, 'getPresentation', isGuidePresentationSource)
          ? result
          : guideValidationFailure(requestId, 'getPresentation', 'Invalid guide result envelope received.');
      } catch {
        return guideValidationFailure(requestId, 'getPresentation', 'Internal IPC invoke failed.');
      } finally {
        activePresentationRequestIds.delete(requestId);
      }
    },
    cancelPresentation: async () => {
      const requestIds = [...activePresentationRequestIds];
      await Promise.all(requestIds.map(async (requestId) => {
        try {
          await invoke(channels.cancelPresentation, { requestId, payload: {} });
        } catch {
          // Cancellation is best-effort from the renderer's perspective.
        }
      }));
    },
    setLibraryFilter: async (input) => {
      const requestId = createRequestId('guide-library-filter');
      if (!isPlainRecord(input) || !hasOnlyKeys(input, ['expectedScopeToken', 'expectedRevision', 'libraryId']) ||
        !isSafeString(input.expectedScopeToken) || !Number.isSafeInteger(input.expectedRevision) || input.expectedRevision < 0 ||
        !(input.libraryId === null || isSafeString(input.libraryId))) {
        return guideValidationFailure(requestId, 'setLibraryFilter', 'Invalid library filter request.');
      }
      try {
        const result = await invoke(channels.setLibraryFilter, { requestId, payload: input });
        if (!isGuideResult<GuideLibraryFilterState>(result, requestId, 'setLibraryFilter', isGuideLibraryFilterState)) {
          return guideValidationFailure(requestId, 'setLibraryFilter', 'Invalid guide result envelope received.');
        }
        return result.ok && (
          result.value.scopeToken !== input.expectedScopeToken ||
          result.value.revision !== input.expectedRevision + 1 ||
          result.value.selectedLibraryId !== input.libraryId
        )
          ? guideValidationFailure(requestId, 'setLibraryFilter', 'Invalid guide result envelope received.')
          : result;
      } catch {
        return guideValidationFailure(requestId, 'setLibraryFilter', 'Internal IPC invoke failed.');
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
      return isGuideResult<never>(result, requestId, 'tuneChannel', isEmptyObject)
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
  operation: GuideOperation,
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
      isGuideRuntimeError(value.error, operation)
    );
  }
  return false;
}

function isGuidePresentationSource(value: unknown): value is GuidePresentationSource {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['channels', 'nowWatching', 'channelWindow', 'libraryFilter', 'minimumStartTimeMs']) &&
    typeof value.minimumStartTimeMs === 'number' &&
    Number.isSafeInteger(value.minimumStartTimeMs) &&
    value.minimumStartTimeMs >= 0 &&
    Array.isArray(value.channels) &&
    value.channels.length <= MAX_GUIDE_CHANNELS &&
    value.channels.every(isEpgChannelViewModel) &&
    value.channels.reduce((total, channel) => total + channel.programs.length, 0) <= MAX_GUIDE_PROGRAMS &&
    (value.nowWatching === null || isEpgCurrentProgramViewModel(value.nowWatching)) &&
    isPlainRecord(value.channelWindow) && hasOnlyKeys(value.channelWindow, ['offset', 'total']) &&
    typeof value.channelWindow.offset === 'number' && Number.isSafeInteger(value.channelWindow.offset) && value.channelWindow.offset >= 0 &&
    typeof value.channelWindow.total === 'number' && Number.isSafeInteger(value.channelWindow.total) && value.channelWindow.total >= 0 &&
    value.channelWindow.offset <= value.channelWindow.total &&
    value.channelWindow.offset + value.channels.length <= value.channelWindow.total &&
    isGuideLibraryFilterState(value.libraryFilter)
  );
}

function isGuideLibraryFilterState(value: unknown): value is GuideLibraryFilterState {
  if (!isPlainRecord(value) || !hasOnlyKeys(value, ['scopeToken', 'revision', 'libraries', 'selectedLibraryId', 'persistenceStatus']) ||
    !isSafeString(value.scopeToken) || typeof value.revision !== 'number' || !Number.isSafeInteger(value.revision) || value.revision < 0 ||
    !Array.isArray(value.libraries) ||
    !(value.selectedLibraryId === null || isSafeString(value.selectedLibraryId)) ||
    !(value.persistenceStatus === 'ready' || value.persistenceStatus === 'missing' || value.persistenceStatus === 'corrupt' || value.persistenceStatus === 'unsupported-version')) {
    return false;
  }
  const libraryIds = new Set<string>();
  for (const library of value.libraries) {
    if (!isPlainRecord(library) || !hasOnlyKeys(library, ['id', 'name', 'contentKind']) || !isSafeString(library.id) ||
      !isBoundedSafeDisplayString(library.name, 160) ||
      !(library.contentKind === 'show' || library.contentKind === 'movie' || library.contentKind === 'mixed') ||
      libraryIds.has(library.id)) return false;
    libraryIds.add(library.id);
  }
  return value.selectedLibraryId === null || libraryIds.has(value.selectedLibraryId);
}

function isEpgChannelViewModel(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'number', 'name', 'programs']) &&
    isSafeString(value.id) &&
    isSafeString(value.number) &&
    isSafeDisplayString(value.name) &&
    Array.isArray(value.programs) &&
    value.programs.length <= MAX_GUIDE_PROGRAMS_PER_CHANNEL &&
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
    isGuideArtworkSet(value.artwork)
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

function isGuideRuntimeError(value: unknown, operation: GuideOperation): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'retryable', 'recoverable', 'operation']) &&
    typeof value.code === 'string' && GUIDE_ERROR_OPERATIONS[value.code]?.includes(operation) === true &&
    isSafeDisplayString(value.message) &&
    typeof value.retryable === 'boolean' &&
    typeof value.recoverable === 'boolean' &&
    value.operation === operation
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

function hasOnlyOptionalKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  return requiredKeys.every((key) => Object.hasOwn(value, key)) &&
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
    (value.kind === 'poster' || value.kind === 'background' || value.kind === 'logo') &&
    isFiniteNonNegativeNumber(value.expiresAtMs) &&
    Number.isSafeInteger(value.expiresAtMs) &&
    isBoundedSafeDisplayString(value.altText, 160) &&
    (value.status === 'available' || value.status === 'placeholder');
}

function isGuideArtworkSet(value: unknown): value is GuideArtworkSet {
  return isPlainRecord(value) &&
    hasOnlyKeys(value, ['poster', 'background']) &&
    (value.poster === null || (isArtworkRef(value.poster) && value.poster.kind === 'poster')) &&
    (value.background === null || (isArtworkRef(value.background) && value.background.kind === 'background'));
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}
