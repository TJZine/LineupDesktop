import type {
  ChannelSetupIpcResult,
  ChannelSetupRuntimeError,
  ChannelSetupSummary,
} from '../contracts/channel.js';

export interface ChannelRuntimeRendererState {
  summary: ChannelSetupSummary | null;
  statusText: string;
  errorText: string | null;
  pending: boolean;
}

export function createChannelRuntimeRendererState(): ChannelRuntimeRendererState {
  return {
    summary: null,
    statusText: 'Channel setup status not loaded',
    errorText: null,
    pending: false,
  };
}

export function markChannelRuntimePending(
  state: ChannelRuntimeRendererState,
): ChannelRuntimeRendererState {
  return {
    ...state,
    pending: true,
    statusText: 'Loading persisted channel status',
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
    summary: result.value,
    pending: false,
    statusText: formatChannelSetupStatus(result.value),
    errorText: null,
  };
}

export function formatChannelSetupStatus(summary: ChannelSetupSummary | null): string {
  if (summary === null) {
    return 'Channel setup status not loaded';
  }
  if (summary.status === 'configured') {
    return summary.recovery.repaired ? 'Recovered with repairs' : 'Recovered';
  }
  if (summary.status === 'not-configured') {
    return 'No persisted channels';
  }
  if (summary.status === 'recovering') {
    return 'Recovering channels';
  }
  return 'Recovery failed';
}

export function sanitizeChannelRuntimeError(error: ChannelSetupRuntimeError): string {
  switch (error.code) {
    case 'CHANNEL_UNAUTHORIZED':
      return 'Channel setup status is not authorized.';
    case 'CHANNEL_VALIDATION_FAILED':
      return 'Channel setup status could not be validated.';
    case 'CHANNEL_STORAGE_CORRUPT':
      return 'Persisted channels could not be recovered.';
    case 'CHANNEL_STORAGE_UNAVAILABLE':
      return 'Persisted channel storage is unavailable.';
    case 'CHANNEL_UNKNOWN':
      return 'Channel setup status could not be loaded.';
  }
}
