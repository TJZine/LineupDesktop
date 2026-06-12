import type {
  PlayerError,
  PlayerEvent,
  PlayerMediaSummary,
  PlayerRendererSafeDiagnostic,
  PlayerRequestId,
} from '../../contracts/player.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { PlexPlaybackRuntimeCleanupReason } from './plexPlaybackRuntime.js';

const RUNTIME_COMPONENT = 'plex-playback-runtime';

export function createRuntimeWarning(
  requestId: PlayerRequestId | null,
  code: string,
  message: string,
  diagnostic: Omit<PlayerRendererSafeDiagnostic, 'component'>,
): PlayerEvent {
  const warning: PlayerError = {
    code,
    category: 'stale-request',
    message,
    recoverable: true,
    retryable: false,
    requestId: requestId ?? undefined,
    diagnostic: { component: RUNTIME_COMPONENT, ...diagnostic },
  };
  return {
    event: 'warning',
    requestId: warning.requestId ?? null,
    warning,
  };
}

export function createRuntimeSourceError(
  requestId: PlayerRequestId | undefined,
  code: string,
  message: string,
  diagnostic: Omit<PlayerRendererSafeDiagnostic, 'component'>,
): PlayerEvent {
  return {
    event: 'error',
    requestId: requestId ?? null,
    error: {
      code,
      category: 'source',
      message,
      recoverable: true,
      retryable: true,
      requestId,
      diagnostic: { component: RUNTIME_COMPONENT, ...diagnostic },
    },
  };
}

export function createRuntimeBoundaryError(
  requestId: PlayerRequestId | undefined,
  reason: string,
): PlayerEvent {
  return {
    event: 'error',
    requestId: requestId ?? null,
    error: {
      code: 'PLAYER_RUNTIME_VALIDATION_FAILED',
      category: 'validation-failure',
      message: 'The playback runtime rejected an unsafe playback payload.',
      recoverable: false,
      retryable: false,
      requestId,
      diagnostic: {
        component: RUNTIME_COMPONENT,
        operation: 'validation',
        status: 'rejected',
        reason,
      },
    },
  };
}

export function createRuntimeLoadFailedError(
  requestId: PlayerRequestId,
  media: PlayerMediaSummary,
): PlayerEvent {
  return createRuntimeSourceError(
    requestId,
    'PLAYER_PLAYBACK_LOAD_FAILED',
    'The player could not load the scheduled media.',
    {
      operation: 'player.load',
      status: 'failed',
      reason: 'player load failed',
      media: projectDiagnosticMedia(media),
    },
  );
}

export function createRuntimeSchedulerSelectionError(): PlayerEvent {
  return createRuntimeSourceError(
    undefined,
    'PLAYER_PLAYBACK_SELECTION_UNAVAILABLE',
    'The playback runtime could not resolve the scheduled playback.',
    {
      operation: 'schedule.resolve',
      status: 'failed',
      reason: 'scheduler selection failed',
    },
  );
}

export function createRuntimeCleanupFailure(
  requestId: PlayerRequestId,
  reason: PlexPlaybackRuntimeCleanupReason,
  failureReason: string,
): PlayerEvent {
  return {
    event: 'error',
    requestId,
    error: {
      code: 'PLAYER_PLAYBACK_CLEANUP_FAILED',
      category: 'cleanup-failure',
      message: 'Playback cleanup did not complete safely.',
      recoverable: true,
      retryable: true,
      requestId,
      diagnostic: {
        component: RUNTIME_COMPONENT,
        operation: 'cleanup',
        status: 'failed',
        reason: failureReason,
        counts: { [reason]: 1 },
      },
    },
  };
}

export function createRuntimeUnscopedCleanupFailure(failureReason: string): PlayerEvent {
  return {
    event: 'error',
    requestId: null,
    error: {
      code: 'PLAYER_PLAYBACK_CLEANUP_FAILED',
      category: 'cleanup-failure',
      message: 'Playback cleanup did not complete safely.',
      recoverable: true,
      retryable: true,
      diagnostic: {
        component: RUNTIME_COMPONENT,
        operation: 'cleanup',
        status: 'failed',
        reason: failureReason,
      },
    },
  };
}

export function recordRuntimeCleanupDiagnostic(
  diagnosticEventStore: DiagnosticEventStore | undefined,
  requestId: PlayerRequestId,
  reason: PlexPlaybackRuntimeCleanupReason,
  code: string,
): void {
  diagnosticEventStore?.record({
    surface: RUNTIME_COMPONENT,
    category: 'cleanup',
    severity: 'error',
    status: 'failed',
    operation: 'cleanup',
    message: 'Playback runtime cleanup failed.',
    requestId,
    result: 'failure',
    context: { code, reason },
  });
}

export function recordRuntimeHelperCrashDiagnostic(
  diagnosticEventStore: DiagnosticEventStore | undefined,
  requestId: PlayerRequestId | undefined,
): void {
  diagnosticEventStore?.record({
    surface: RUNTIME_COMPONENT,
    category: 'helper-crash',
    severity: 'error',
    status: 'observed',
    operation: 'helper-crash.cleanup',
    message: 'Playback runtime received a helper crash cleanup request.',
    requestId,
    result: 'ignored',
    context: { code: 'PLAYER_HELPER_CRASHED' },
  });
}

function projectDiagnosticMedia(media: PlayerMediaSummary): Pick<PlayerMediaSummary, 'id' | 'title'> {
  return { id: media.id, title: media.title };
}
