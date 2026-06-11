import type {
  PlayerError,
  PlayerErrorCategory,
  PlayerRendererSafeDiagnostic,
  PlayerRequestId,
} from '../../contracts/player.js';
import type { NativePlayerHostFailure } from './nativePlayerHostPort.js';
import {
  assertNever,
  hasForbiddenPrivilegedField,
  isNonEmptyString,
  isPlayerErrorCategory,
  isRecord,
  sanitizeCounts,
  type UnknownRecord,
  validateMediaDiagnostic,
  validateTrackIds,
} from './playerAdapterValidation.js';

export interface ValidationFailure {
  error: PlayerError;
}

export function validationFailure(
  requestId: PlayerRequestId | undefined,
  reason: string,
): ValidationFailure {
  return {
    error: createPlayerError({
      code: 'PLAYER_VALIDATION_FAILED',
      category: 'validation-failure',
      message: 'The player request was rejected because it was not valid.',
      requestId,
      diagnostic: {
        component: 'desktop-player-adapter',
        operation: 'validation',
        status: 'rejected',
        reason,
      },
    }),
  };
}

export function duplicateRequestError(requestId: PlayerRequestId): PlayerError {
  return createPlayerError({
    code: 'PLAYER_DUPLICATE_REQUEST_ID',
    category: 'validation-failure',
    message: 'The player request was rejected because it reused an active request ID.',
    requestId,
    diagnostic: {
      component: 'desktop-player-adapter',
      operation: 'validation',
      status: 'rejected',
      reason: 'duplicate request id',
    },
  });
}

export function hostFailureToError(requestId: PlayerRequestId, failure: NativePlayerHostFailure): PlayerError {
  const hostFailure: UnknownRecord =
    isRecord(failure) && !hasForbiddenPrivilegedField(failure) ? failure : {};
  const category = isPlayerErrorCategory(hostFailure.category) ? hostFailure.category : 'unknown';
  return createPlayerError({
    code: hostFailureCode(category),
    category,
    message: hostFailureMessage(category),
    recoverable: typeof hostFailure.recoverable === 'boolean' ? hostFailure.recoverable : false,
    retryable: typeof hostFailure.retryable === 'boolean' ? hostFailure.retryable : false,
    requestId,
    diagnostic: {
      component: 'desktop-player-adapter',
      operation: 'host.command',
      status: 'failed',
      reason: 'host reported command failure',
    },
  });
}

export function hostLifecycleFailureToError(
  requestId: PlayerRequestId | null,
  failure: NativePlayerHostFailure,
): PlayerError {
  const hostFailure: UnknownRecord =
    isRecord(failure) && !hasForbiddenPrivilegedField(failure) ? failure : {};
  const category = isPlayerErrorCategory(hostFailure.category) ? hostFailure.category : 'helper-failure';
  return createPlayerError({
    code: hostFailureCode(category),
    category,
    message: hostLifecycleFailureMessage(category),
    recoverable: typeof hostFailure.recoverable === 'boolean' ? hostFailure.recoverable : true,
    retryable: typeof hostFailure.retryable === 'boolean' ? hostFailure.retryable : true,
    requestId: requestId ?? undefined,
    diagnostic: {
      component: 'desktop-player-adapter',
      operation: 'helper.lifecycle',
      status: 'failed',
      reason: 'helper lifecycle failure',
    },
  });
}

export function normalizeHostErrorPayload(
  value: unknown,
  requestId: PlayerRequestId | null,
): { error: ValidationFailure['error'] } | PlayerError {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return validationFailure(requestId ?? undefined, 'host error payload was invalid');
  }
  const category = isPlayerErrorCategory(value.category) ? value.category : 'unknown';
  return createPlayerError({
    code: hostFailureCode(category),
    category,
    message: hostFailureMessage(category),
    recoverable: typeof value.recoverable === 'boolean' ? value.recoverable : false,
    retryable: typeof value.retryable === 'boolean' ? value.retryable : false,
    requestId: requestId ?? undefined,
    diagnostic: {
      component: 'desktop-player-adapter',
      operation: 'host.error',
      status: 'failed',
      reason: 'host reported playback failure',
    },
  });
}

export function hostFailureCode(category: PlayerErrorCategory): string {
  switch (category) {
    case 'source':
      return 'PLAYER_HOST_SOURCE_FAILURE';
    case 'authentication':
      return 'PLAYER_HOST_AUTHENTICATION_FAILURE';
    case 'authorization':
      return 'PLAYER_HOST_AUTHORIZATION_FAILURE';
    case 'network':
      return 'PLAYER_HOST_NETWORK_FAILURE';
    case 'unsupported-media':
      return 'PLAYER_HOST_UNSUPPORTED_MEDIA';
    case 'unsupported-capability':
      return 'PLAYER_HOST_UNSUPPORTED_CAPABILITY';
    case 'timeout':
      return 'PLAYER_HOST_TIMEOUT';
    case 'aborted':
      return 'PLAYER_HOST_ABORTED';
    case 'engine-failure':
      return 'PLAYER_HOST_ENGINE_FAILURE';
    case 'helper-failure':
      return 'PLAYER_HOST_HELPER_FAILURE';
    case 'render-failure':
      return 'PLAYER_HOST_RENDER_FAILURE';
    case 'track-failure':
      return 'PLAYER_HOST_TRACK_FAILURE';
    case 'cleanup-failure':
      return 'PLAYER_HOST_CLEANUP_FAILURE';
    case 'stale-request':
      return 'PLAYER_HOST_STALE_REQUEST';
    case 'validation-failure':
      return 'PLAYER_HOST_VALIDATION_FAILURE';
    case 'unknown':
      return 'PLAYER_HOST_FAILURE';
    default:
      return assertNever(category);
  }
}

export function hostFailureMessage(category: PlayerErrorCategory): string {
  switch (category) {
    case 'source':
      return 'The player helper could not load the selected media.';
    case 'authentication':
    case 'authorization':
      return 'The player helper was not allowed to load the selected media.';
    case 'network':
      return 'The player helper could not reach the media source.';
    case 'unsupported-media':
      return 'The selected media is not supported by the player helper.';
    case 'unsupported-capability':
      return 'The requested player capability is not supported.';
    case 'timeout':
      return 'The player helper timed out.';
    case 'aborted':
      return 'The player helper operation was aborted.';
    case 'engine-failure':
      return 'The player engine failed.';
    case 'helper-failure':
      return 'The player helper failed.';
    case 'render-failure':
      return 'The player renderer surface failed.';
    case 'track-failure':
      return 'The player helper could not apply the requested track change.';
    case 'cleanup-failure':
      return 'The player helper could not clean up safely.';
    case 'stale-request':
      return 'The player helper reported a stale playback request.';
    case 'validation-failure':
      return 'The player helper returned an invalid playback payload.';
    case 'unknown':
      return 'The player helper reported a playback failure.';
    default:
      return assertNever(category);
  }
}

function hostLifecycleFailureMessage(category: PlayerErrorCategory): string {
  if (category === 'helper-failure') {
    return 'The player helper stopped unexpectedly.';
  }
  return hostFailureMessage(category);
}

export function sanitizePlayerError(value: unknown, fallbackCode: string): PlayerError {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return createPlayerError({
      code: fallbackCode,
      category: 'validation-failure',
      message: 'The player helper returned an invalid error payload.',
      diagnostic: {
        component: 'desktop-player-adapter',
        operation: 'host.error',
        status: 'rejected',
        reason: 'invalid host error payload',
      },
    });
  }
  return createPlayerError({
    code: isNonEmptyString(value.code) ? value.code : fallbackCode,
    category: isPlayerErrorCategory(value.category) ? value.category : 'unknown',
    message: isNonEmptyString(value.message) ? value.message : 'The player helper reported an error.',
    recoverable: typeof value.recoverable === 'boolean' ? value.recoverable : false,
    retryable: typeof value.retryable === 'boolean' ? value.retryable : false,
    requestId: isNonEmptyString(value.requestId) ? value.requestId : undefined,
    diagnostic: sanitizeDiagnostic(value.diagnostic),
  });
}

export function createPlayerError(input: {
  code: string;
  category: PlayerErrorCategory;
  message: string;
  recoverable?: boolean;
  retryable?: boolean;
  requestId?: PlayerRequestId;
  diagnostic?: PlayerRendererSafeDiagnostic;
}): PlayerError {
  return {
    code: input.code,
    category: input.category,
    message: input.message,
    recoverable: input.recoverable ?? false,
    retryable: input.retryable ?? false,
    requestId: input.requestId,
    diagnostic: sanitizeDiagnostic(input.diagnostic),
  };
}

export function sanitizeDiagnostic(value: unknown): PlayerRendererSafeDiagnostic | undefined {
  if (!isRecord(value) || hasForbiddenPrivilegedField(value)) {
    return undefined;
  }
  const counts = isRecord(value.counts) ? sanitizeCounts(value.counts) : undefined;
  const media = validateMediaDiagnostic(value.media);
  const trackIds = validateTrackIds(value.trackIds);
  return {
    component: isNonEmptyString(value.component) ? value.component : 'desktop-player-adapter',
    operation: isNonEmptyString(value.operation) ? value.operation : 'unknown',
    status: typeof value.status === 'string' ? value.status : undefined,
    reason: typeof value.reason === 'string' ? value.reason : undefined,
    counts,
    capabilityProfileId: isNonEmptyString(value.capabilityProfileId)
      ? value.capabilityProfileId
      : undefined,
    trackIds,
    media,
    timestampMs: typeof value.timestampMs === 'number' && Number.isFinite(value.timestampMs) && value.timestampMs >= 0
      ? value.timestampMs
      : undefined,
  };
}
