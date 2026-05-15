import type {
  PlexIpcResult,
  PlexRuntimeError,
  PlexRuntimeErrorCode,
  PlexRuntimeOperation,
  PlexRuntimeSnapshot,
  PlexServerSelectionSummary,
  PlexServerSummary,
} from '../../contracts/plex.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { PlexAuthError } from './auth/index.js';
import { PlexDiscoveryError } from './discovery/index.js';
import { PlexLibraryError } from './library/plexLibraryError.js';
import type { PlexMediaContainer } from './library/types.js';
import { LivePlexTransportError } from './livePlexTransport.js';

export function createInitialSnapshot(nowMs: number): PlexRuntimeSnapshot {
  return {
    auth: {
      state: 'signed-out',
      pin: null,
      profile: null,
      homeUsers: [],
      credentialStatus: 'missing',
    },
    servers: {
      status: 'idle',
      selected: null,
      items: [],
      lastSelection: null,
    },
    library: {
      status: 'idle',
      sections: [],
      selectedSectionId: null,
      items: [],
      search: null,
      metadata: null,
    },
    lastError: null,
    updatedAtMs: nowMs,
  };
}

export function success<T>(requestId: string, value: T): PlexIpcResult<T> {
  return { ok: true, value, requestId };
}

export function failureResult<T>(
  requestId: string,
  error: PlexRuntimeError,
  options: { cancelled?: boolean; stale?: boolean } = {},
): PlexIpcResult<T> {
  return {
    ok: false,
    requestId,
    error,
    ...(options.cancelled ? { cancelled: true as const } : {}),
    ...(options.stale ? { stale: true as const } : {}),
  };
}

export function cloneRuntimeSnapshot(snapshot: PlexRuntimeSnapshot): PlexRuntimeSnapshot {
  return {
    ...snapshot,
    auth: {
      ...snapshot.auth,
      homeUsers: [...snapshot.auth.homeUsers],
    },
    servers: {
      ...snapshot.servers,
      items: [...snapshot.servers.items],
    },
    library: {
      ...snapshot.library,
      sections: [...snapshot.library.sections],
      items: [...snapshot.library.items],
      search:
        snapshot.library.search === null
          ? null
          : {
              query: snapshot.library.search.query,
              items: [...snapshot.library.search.items],
            },
    },
  };
}

export function applyFailureSnapshot(
  snapshot: PlexRuntimeSnapshot,
  error: PlexRuntimeError,
  nowMs: number,
): PlexRuntimeSnapshot {
  return {
    ...snapshot,
    servers:
      error.operation === 'refreshServers' ||
      error.operation === 'restoreSelectedServer' ||
      error.operation === 'selectServer'
        ? { ...snapshot.servers, status: 'failed' }
        : snapshot.servers,
    library:
      error.operation === 'listLibrarySections' ||
      error.operation === 'listLibraryItems' ||
      error.operation === 'searchLibrary' ||
      error.operation === 'getMetadata'
        ? { ...snapshot.library, status: 'failed' }
        : snapshot.library,
    lastError: error,
    updatedAtMs: nowMs,
  };
}

export function applyServerSelectionSnapshot(input: {
  snapshot: PlexRuntimeSnapshot;
  selection: PlexServerSelectionSummary;
  selected: PlexServerSummary | null;
  items: readonly PlexServerSummary[];
  nowMs: number;
}): PlexRuntimeSnapshot {
  const previousServerId = input.snapshot.servers.selected?.serverId ?? null;
  const nextServerId = input.selection.kind === 'selected'
    ? input.selection.server.serverId
    : null;
  const preserveLibrary =
    input.selection.kind === 'selected' &&
    previousServerId !== null &&
    previousServerId === nextServerId;

  return {
    ...input.snapshot,
    servers: {
      status: input.selection.kind === 'selected' ? 'ready' : 'failed',
      selected: input.selected,
      items: input.items,
      lastSelection: input.selection,
    },
    library:
      preserveLibrary
        ? input.snapshot.library
        : createIdleLibrarySnapshot(),
    lastError: null,
    updatedAtMs: input.nowMs,
  };
}

function createIdleLibrarySnapshot(): PlexRuntimeSnapshot['library'] {
  return {
    status: 'idle',
    sections: [],
    selectedSectionId: null,
    items: [],
    search: null,
    metadata: null,
  };
}

export function recordRuntimeDiagnostic(input: {
  eventStore?: DiagnosticEventStore;
  snapshot: PlexRuntimeSnapshot;
  operation: PlexRuntimeOperation;
  status: 'started' | 'succeeded' | 'failed' | 'cancelled';
  code?: string;
}): void {
  input.eventStore?.record({
    surface: 'main',
    category: 'ipc',
    severity: input.status === 'failed' ? 'error' : input.status === 'cancelled' ? 'warning' : 'info',
    status: input.status,
    operation: `plex.${input.operation}`,
    message: `Plex ${input.operation} ${input.status}.`,
    result: input.status === 'succeeded' ? 'success' : input.status === 'cancelled' ? 'cancelled' : undefined,
    context: {
      operation: input.operation,
      ...(input.code !== undefined ? { code: input.code } : {}),
      serverCount: input.snapshot.servers.items.length,
      sectionCount: input.snapshot.library.sections.length,
      itemCount: input.snapshot.library.items.length,
    },
  });
}

export function stripPinSecretFields(input: {
  id: number;
  code: string;
  expiresAtMs: number;
  claimed: boolean;
}) {
  return {
    id: input.id,
    code: input.code,
    expiresAtMs: input.expiresAtMs,
    claimed: input.claimed,
  };
}

export function validatePositiveInteger(
  value: number,
  operation: PlexRuntimeOperation,
): PlexRuntimeError | null {
  if (!Number.isFinite(value) || value <= 0 || Math.floor(value) !== value) {
    return validationError(operation);
  }
  return null;
}

export function isOptionalShortString(value: string | null | undefined): boolean {
  return value === undefined || value === null || (typeof value === 'string' && value.length <= 128);
}

export function payloadAsContainer<T>(payload: unknown): PlexMediaContainer<T> {
  if (
    typeof payload === 'object' &&
    payload !== null &&
    'kind' in payload &&
    (payload as { kind?: unknown }).kind === 'json'
  ) {
    return (payload as unknown as { data: unknown }).data as PlexMediaContainer<T>;
  }
  throw new PlexLibraryError('parse-error', 'Plex library response was not JSON');
}

export function normalizeOperationKey(operationKey: string): PlexRuntimeOperation {
  const [operation] = operationKey.split(':');
  return operation as PlexRuntimeOperation;
}

export function mapCredentialStatus(status: string): PlexRuntimeSnapshot['auth']['credentialStatus'] {
  if (status === 'unavailable' || status === 'corrupt') {
    return status;
  }
  if (status === 'present') {
    return 'present';
  }
  return 'missing';
}

export function mapRuntimeError(error: unknown, operation: PlexRuntimeOperation): PlexRuntimeError {
  if (isAbortError(error)) {
    return runtimeError('PLEX_CANCELLED', operation, {
      message: 'Plex request was cancelled.',
      recoverable: true,
    });
  }
  if (error instanceof PlexAuthError) {
    return mapAuthError(error, operation);
  }
  if (error instanceof PlexDiscoveryError) {
    return mapDiscoveryError(error, operation);
  }
  if (error instanceof PlexLibraryError) {
    return mapLibraryError(error, operation);
  }
  if (error instanceof LivePlexTransportError) {
    return mapTransportError(error, operation);
  }
  return runtimeError('PLEX_UNKNOWN', operation, {
    message: 'Plex operation failed.',
    retryable: false,
    recoverable: true,
  });
}

export function storageError(status: string): PlexRuntimeError {
  return runtimeError(
    status === 'corrupt' ? 'PLEX_STORAGE_CORRUPT' : 'PLEX_STORAGE_UNAVAILABLE',
    'getSnapshot',
    {
      message: 'Plex credential storage is unavailable.',
      recoverable: true,
    },
  );
}

export function validationError(operation: PlexRuntimeOperation): PlexRuntimeError {
  return runtimeError('PLEX_VALIDATION_FAILED', operation, {
    message: 'Plex request payload is invalid.',
    recoverable: false,
  });
}

export function authRequiredError(operation: PlexRuntimeOperation): PlexRuntimeError {
  return runtimeError('PLEX_AUTH_REQUIRED', operation, {
    message: 'Plex authentication is required.',
    recoverable: true,
  });
}

export function staleError(operation: PlexRuntimeOperation): PlexRuntimeError {
  return runtimeError('PLEX_STALE_RESULT', operation, {
    message: 'Plex request result is stale.',
    recoverable: true,
  });
}

export class StaleRuntimeMutationError extends Error {
  constructor() {
    super('Plex runtime mutation is stale');
    this.name = 'StaleRuntimeMutationError';
  }
}

function mapAuthError(error: PlexAuthError, operation: PlexRuntimeOperation): PlexRuntimeError {
  const codeMap: Record<PlexAuthError['code'], PlexRuntimeErrorCode> = {
    'auth-required': 'PLEX_AUTH_REQUIRED',
    'auth-invalid': 'PLEX_AUTH_INVALID',
    'auth-failed': 'PLEX_AUTH_INVALID',
    'pin-expired': 'PLEX_PIN_EXPIRED',
    'pin-timeout': 'PLEX_PIN_TIMEOUT',
    'rate-limited': 'PLEX_RATE_LIMITED',
    'resource-not-found': 'PLEX_RESOURCE_NOT_FOUND',
    'server-unreachable': 'PLEX_SERVER_UNREACHABLE',
    'server-error': 'PLEX_UNKNOWN',
    aborted: 'PLEX_CANCELLED',
    'parse-error': 'PLEX_PARSE_FAILED',
  };
  const code = codeMap[error.code];
  return runtimeError(code, operation, {
    message: messageForCode(code),
    httpStatus: error.httpStatus,
    retryable: error.retryable,
    recoverable: true,
  });
}

function mapDiscoveryError(error: PlexDiscoveryError, operation: PlexRuntimeOperation): PlexRuntimeError {
  const codeMap: Record<PlexDiscoveryError['code'], PlexRuntimeErrorCode> = {
    'auth-required': 'PLEX_AUTH_REQUIRED',
    'auth-invalid': 'PLEX_AUTH_INVALID',
    'server-unreachable': 'PLEX_SERVER_UNREACHABLE',
    'server-error': 'PLEX_UNKNOWN',
    aborted: 'PLEX_CANCELLED',
    'parse-error': 'PLEX_PARSE_FAILED',
  };
  const code = codeMap[error.code];
  return runtimeError(code, operation, {
    message: messageForCode(code),
    httpStatus: error.httpStatus,
    retryable: error.retryable,
    recoverable: true,
  });
}

function mapLibraryError(error: PlexLibraryError, operation: PlexRuntimeOperation): PlexRuntimeError {
  const codeMap: Record<string, PlexRuntimeErrorCode> = {
    'parse-error': 'PLEX_PARSE_FAILED',
    'network-error': 'PLEX_SERVER_UNREACHABLE',
    'authentication-expired': 'PLEX_AUTH_INVALID',
    'server-error': 'PLEX_LIBRARY_FAILED',
    'rate-limited': 'PLEX_RATE_LIMITED',
    aborted: 'PLEX_CANCELLED',
  };
  return runtimeError(codeMap[error.code] ?? 'PLEX_LIBRARY_FAILED', operation, {
    message: messageForCode(codeMap[error.code] ?? 'PLEX_LIBRARY_FAILED'),
    httpStatus: error.httpStatus,
    retryable: error.code === 'network-error' || error.code === 'rate-limited',
    recoverable: true,
  });
}

function mapTransportError(error: LivePlexTransportError, operation: PlexRuntimeOperation): PlexRuntimeError {
  const codeMap: Record<LivePlexTransportError['code'], PlexRuntimeErrorCode> = {
    'auth-required': 'PLEX_AUTH_REQUIRED',
    'auth-invalid': 'PLEX_AUTH_INVALID',
    'resource-not-found': 'PLEX_RESOURCE_NOT_FOUND',
    'rate-limited': 'PLEX_RATE_LIMITED',
    'server-unreachable': 'PLEX_SERVER_UNREACHABLE',
    'parse-error': 'PLEX_PARSE_FAILED',
    aborted: 'PLEX_CANCELLED',
    timeout: 'PLEX_SERVER_UNREACHABLE',
    'server-error': 'PLEX_LIBRARY_FAILED',
  };
  return runtimeError(codeMap[error.code], operation, {
    message: messageForCode(codeMap[error.code]),
    httpStatus: error.httpStatus,
    retryable: error.retryable,
    recoverable: true,
  });
}

function runtimeError(
  code: PlexRuntimeErrorCode,
  operation: PlexRuntimeOperation,
  options: {
    message: string;
    retryable?: boolean;
    recoverable: boolean;
    httpStatus?: number;
  },
): PlexRuntimeError {
  return {
    code,
    message: options.message,
    retryable: options.retryable ?? false,
    recoverable: options.recoverable,
    operation,
    ...(options.httpStatus !== undefined ? { httpStatus: options.httpStatus } : {}),
  };
}

function messageForCode(code: PlexRuntimeErrorCode): string {
  switch (code) {
    case 'PLEX_AUTH_REQUIRED':
      return 'Plex authentication is required.';
    case 'PLEX_AUTH_INVALID':
      return 'Plex authentication was rejected.';
    case 'PLEX_PIN_EXPIRED':
      return 'Plex link code expired. Request a new code and try again.';
    case 'PLEX_PIN_TIMEOUT':
      return 'Plex link code timed out. Request a new code and try again.';
    case 'PLEX_RATE_LIMITED':
      return 'Plex request was rate limited.';
    case 'PLEX_RESOURCE_NOT_FOUND':
      return 'Plex resource was not found.';
    case 'PLEX_SERVER_UNREACHABLE':
      return 'Plex server is unreachable.';
    case 'PLEX_PARSE_FAILED':
      return 'Plex response could not be parsed.';
    case 'PLEX_LIBRARY_FAILED':
      return 'Plex library request failed.';
    case 'PLEX_CANCELLED':
      return 'Plex request was cancelled.';
    default:
      return 'Plex operation failed.';
  }
}

function isAbortError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.name === 'AbortError' ||
      ('code' in error && error.code === 'ABORT_ERR') ||
      ('code' in error && error.code === 'aborted'))
  );
}
