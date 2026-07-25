import type {
  ChannelSetupIpcResult,
  ChannelSetupOperation,
  ChannelSetupRuntimeError,
  ChannelSetupSummary,
} from '../contracts/channel.js';

export interface ChannelRuntimeRendererState {
  summary: ChannelSetupSummary | null;
  operation: ChannelSetupOperation | null;
  statusText: string;
  errorText: string | null;
  pending: boolean;
}

export interface ChannelBuildCancellationProjection {
  visible: boolean;
  enabled: boolean;
  label: 'Cancel build' | 'Canceling…';
}

export function createChannelRuntimeRendererState(): ChannelRuntimeRendererState {
  return {
    summary: null,
    operation: null,
    statusText: 'Channel setup status not loaded',
    errorText: null,
    pending: false,
  };
}

export function markChannelRuntimePending(
  state: ChannelRuntimeRendererState,
  statusText = 'Loading persisted channel status',
): ChannelRuntimeRendererState {
  return { ...state, pending: true, statusText, errorText: null };
}

export function markChannelRuntimeBlocked(
  state: ChannelRuntimeRendererState,
  message: string,
): ChannelRuntimeRendererState {
  return {
    ...state,
    pending: false,
    statusText: 'Channel setup needs a library',
    errorText: sanitizeRendererMessage(message),
  };
}

export function clearChannelRuntimeActionState(
  state: ChannelRuntimeRendererState,
  options: { preservePending: boolean } = { preservePending: false },
): ChannelRuntimeRendererState {
  return {
    ...state,
    pending: options.preservePending,
    statusText: options.preservePending ? state.statusText : formatChannelSetupStatus(state.summary),
    errorText: null,
  };
}

export function applyChannelStatusResult(
  state: ChannelRuntimeRendererState,
  result: ChannelSetupIpcResult<ChannelSetupSummary>,
): ChannelRuntimeRendererState {
  if (!result.ok) {
    return {
      ...state,
      pending: false,
      statusText: 'Channel status unavailable',
      errorText: sanitizeChannelRuntimeError(result.error),
    };
  }
  return {
    ...state,
    summary: result.value,
    pending: false,
    statusText: formatChannelSetupStatus(result.value),
    errorText: null,
  };
}

export function applyChannelOperation(
  state: ChannelRuntimeRendererState,
  operation: ChannelSetupOperation,
): ChannelRuntimeRendererState {
  const terminal =
    operation.state === 'review-ready' ||
    operation.state === 'succeeded' ||
    operation.state === 'failed' ||
    operation.state === 'canceled';
  return {
    ...state,
    operation,
    pending: !terminal,
    statusText: formatOperationStatus(operation),
    errorText: operation.state === 'failed'
      ? sanitizeChannelRuntimeError(operation.error)
      : null,
  };
}

export function projectChannelBuildCancellation(
  state: ChannelRuntimeRendererState,
): ChannelBuildCancellationProjection {
  const operation = state.operation;
  const isCanceling =
    operation?.state === 'canceling' || state.statusText === 'Canceling…';
  const isHandoffPending =
    state.pending &&
    (operation === null || operation.state === 'review-ready');
  const isPreCommitOperation =
    operation !== null &&
    operation.state !== 'review-ready' &&
    operation.state !== 'succeeded' &&
    operation.state !== 'failed' &&
    operation.state !== 'canceled' &&
    operation.phase !== 'persist' &&
    operation.phase !== 'refresh-guide';
  const enabled = !isCanceling && (isHandoffPending || isPreCommitOperation);
  return {
    visible: enabled || isCanceling,
    enabled,
    label: isCanceling ? 'Canceling…' : 'Cancel build',
  };
}

export function formatChannelSetupStatus(summary: ChannelSetupSummary | null): string {
  if (summary === null) return 'Channel setup status not loaded';
  if (summary.status === 'configured') {
    return summary.recovery.repaired ? 'Recovered with repairs' : 'Recovered';
  }
  if (summary.status === 'not-configured') return 'No persisted channels';
  if (summary.status === 'recovering') return 'Recovering channels';
  return 'Recovery failed';
}

export function sanitizeChannelRuntimeError(error: ChannelSetupRuntimeError): string {
  switch (error.code) {
    case 'CHANNEL_UNAUTHORIZED': return 'Channel setup status is not authorized.';
    case 'CHANNEL_VALIDATION_FAILED': return 'Channel setup request could not be validated.';
    case 'CHANNEL_BUSY': return 'Another channel setup operation is active.';
    case 'CHANNEL_PLEX_REQUIRED': return 'Choose a Plex profile, server, and library first.';
    case 'CHANNEL_CONTEXT_CHANGED': return 'Channel context changed. Review again.';
    case 'CHANNEL_LINEUP_CONFLICT': return 'Channels changed after review. Review again.';
    case 'CHANNEL_PLAN_NOT_FOUND':
    case 'CHANNEL_PLAN_EXPIRED':
    case 'CHANNEL_PLAN_ALREADY_USED': return 'Channel setup review is unavailable. Review again.';
    case 'CHANNEL_OPERATION_NOT_FOUND':
    case 'CHANNEL_OPERATION_EXPIRED': return 'Channel setup operation is unavailable.';
    case 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED': return 'Replacing saved channels requires confirmation.';
    case 'CHANNEL_REPLACEMENT_EMPTY': return 'No replacement channels remained available.';
    case 'CHANNEL_STORAGE_CORRUPT': return 'Persisted channels could not be recovered.';
    case 'CHANNEL_STORAGE_UNAVAILABLE': return 'Persisted channel storage is unavailable.';
    case 'CHANNEL_UNKNOWN': return 'Channel setup could not complete the request.';
  }
}

function formatOperationStatus(operation: ChannelSetupOperation): string {
  if (operation.state === 'review-ready') return 'Channel review ready';
  if (operation.state === 'succeeded') return 'Channels saved';
  if (operation.state === 'canceled') return 'Channel setup canceled';
  if (operation.state === 'failed') return 'Channel setup failed';
  if (operation.state === 'canceling') return 'Canceling…';
  if (operation.phase === 'discover-facets') return 'Discovering channel options';
  if (operation.phase === 'plan') return 'Planning channels';
  if (operation.phase === 'materialize') return 'Preparing channels';
  if (operation.phase === 'persist' || operation.phase === 'refresh-guide') {
    return 'Saving channels—cancel is no longer available.';
  }
  return 'Refreshing Guide';
}

function sanitizeRendererMessage(message: string): string {
  // eslint-disable-next-line no-control-regex
  const safe = message.replace(/[\u0000-\u001f\u007f-\u009f]/gu, ' ').replace(/\s+/gu, ' ').trim();
  return safe.length > 0 ? safe.slice(0, 160) : 'Channel setup could not continue.';
}
