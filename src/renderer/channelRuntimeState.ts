import type {
  ChannelSetupCommitMode,
  ChannelSetupIpcResult,
  ChannelSetupRuntimeError,
  ChannelSetupSummary,
} from '../contracts/channel.js';

export interface ChannelRuntimeRendererState {
  summary: ChannelSetupSummary | null;
  statusText: string;
  errorText: string | null;
  pending: boolean;
  commitMode: ChannelSetupCommitMode;
  confirmReplace: boolean;
}

export function createChannelRuntimeRendererState(): ChannelRuntimeRendererState {
  return {
    summary: null,
    statusText: 'Channel setup status not loaded',
    errorText: null,
    pending: false,
    commitMode: 'append',
    confirmReplace: false,
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

export function markChannelCommitPending(
  state: ChannelRuntimeRendererState,
  mode: ChannelSetupCommitMode,
): ChannelRuntimeRendererState {
  return {
    ...state,
    pending: true,
    commitMode: mode,
    statusText: mode === 'replace' ? 'Replacing channels' : 'Saving channels',
    errorText: null,
  };
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
    confirmReplace: false,
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
      confirmReplace: result.error.code === 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
    };
  }
  return {
    summary: result.value,
    pending: false,
    statusText: formatChannelSetupStatus(result.value),
    errorText: null,
    commitMode: state.commitMode,
    confirmReplace: false,
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
  if (error.code === 'CHANNEL_VALIDATION_FAILED' && error.message.trim().length > 0) {
    return sanitizeRendererMessage(error.message);
  }
  switch (error.code) {
    case 'CHANNEL_UNAUTHORIZED':
      return 'Channel setup status is not authorized.';
    case 'CHANNEL_VALIDATION_FAILED':
      return 'Channel setup status could not be validated.';
    case 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED':
      return 'Replacing saved channels requires confirmation.';
    case 'CHANNEL_PLEX_REQUIRED':
      return 'Choose a Plex profile, server, and library first.';
    case 'CHANNEL_STORAGE_CORRUPT':
      return 'Persisted channels could not be recovered.';
    case 'CHANNEL_STORAGE_UNAVAILABLE':
      return 'Persisted channel storage is unavailable.';
    case 'CHANNEL_UNKNOWN':
      return 'Channel setup status could not be loaded.';
  }
  return assertNever(error.code);
}

function sanitizeRendererMessage(message: string): string {
  const safe = Array.from(message)
    .filter((char) => {
      const codePoint = char.codePointAt(0);
      return codePoint !== undefined && codePoint >= 0x20 && codePoint < 0x7f;
    })
    .join('')
    .replace(/\s+/gu, ' ')
    .trim();
  if (safe.length === 0 || containsPrivateRendererTerm(safe)) {
    return 'Channel setup could not continue.';
  }
  return safe.slice(0, 220);
}

function containsPrivateRendererTerm(message: string): boolean {
  return /\b(?:token|credential|secret|header|serverUri|connectionUri|endpointUrl|baseUrl|tokenizedUrl|appPath|userDataPath|filesystemPath|persistenceFilePath|rawPayload|rawPlexPayload|nativeHandle)\b/iu.test(message) ||
    /\bhttps?:\/\/\S+/iu.test(message) ||
    /\b[A-Za-z]:\\\S+/u.test(message) ||
    /\/Users\/\S+/u.test(message) ||
    /(?:^|\s)\/home\/\S+/u.test(message) ||
    /\\\\[^\\\s]+\\[^\\\s]+(?:\\\S*)?/u.test(message);
}

function assertNever(value: never): never {
  throw new Error(`Unhandled channel setup runtime error code: ${String(value)}`);
}
