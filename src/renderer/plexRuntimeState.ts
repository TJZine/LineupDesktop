import type {
  PlexIpcResult,
  PlexMediaItemSummary,
  PlexRuntimeError,
  PlexRuntimeOperation,
  PlexRuntimeSnapshot,
} from '../contracts/plex.js';

export type PlexRendererOperation =
  | PlexRuntimeOperation
  | 'pollPinLoop'
  | 'cleanup';

export interface PlexRuntimeRendererState {
  snapshot: PlexRuntimeSnapshot | null;
  selectedSectionId: string | null;
  selectedServerId: string | null;
  selectedItemRatingKey: string | null;
  searchQuery: string;
  homeUserPin: string;
  statusText: string;
  errorText: string | null;
  pending: Readonly<Record<PlexRendererOperation, boolean>>;
  lastMetadata: PlexMediaItemSummary | null;
}

const PLEX_RENDERER_OPERATIONS = [
  'getSnapshot',
  'requestPin',
  'pollPin',
  'cancelPin',
  'getHomeUsers',
  'switchHomeUser',
  'restoreSelectedServer',
  'refreshServers',
  'selectServer',
  'listLibrarySections',
  'listLibraryItems',
  'searchLibrary',
  'getMetadata',
  'pollPinLoop',
  'cleanup',
] as const satisfies readonly PlexRendererOperation[];

export function createPlexRuntimeRendererState(): PlexRuntimeRendererState {
  return {
    snapshot: null,
    selectedSectionId: null,
    selectedServerId: null,
    selectedItemRatingKey: null,
    searchQuery: '',
    homeUserPin: '',
    statusText: 'Not loaded',
    errorText: null,
    pending: createPendingMap(),
    lastMetadata: null,
  };
}

export function markPlexRendererOperationPending(
  state: PlexRuntimeRendererState,
  operation: PlexRendererOperation,
  pending: boolean,
): PlexRuntimeRendererState {
  return {
    ...state,
    pending: {
      ...state.pending,
      [operation]: pending,
    },
    statusText: pending ? formatPendingStatus(operation) : state.statusText,
  };
}

export function clearPlexRendererPending(
  state: PlexRuntimeRendererState,
  statusText = state.statusText,
): PlexRuntimeRendererState {
  return {
    ...state,
    pending: createPendingMap(),
    statusText,
  };
}

export function clearPlexRendererForCleanup(
  state: PlexRuntimeRendererState,
  statusText = 'Cleaned up',
): PlexRuntimeRendererState {
  const snapshot = state.snapshot === null
    ? null
    : {
      ...state.snapshot,
      auth: {
        ...state.snapshot.auth,
        state: state.snapshot.auth.state === 'pin-pending' ? 'signed-out' : state.snapshot.auth.state,
        pin: null,
        homeUsers: [],
      },
      library: {
        ...state.snapshot.library,
        sections: [],
        selectedSectionId: null,
        items: [],
        search: null,
        metadata: null,
      },
    } satisfies PlexRuntimeSnapshot;
  return {
    ...clearPlexRendererPending(state, statusText),
    snapshot,
    homeUserPin: '',
    selectedSectionId: null,
    selectedServerId: null,
    selectedItemRatingKey: null,
    searchQuery: '',
    lastMetadata: null,
  };
}

export function applyPlexSnapshot(
  state: PlexRuntimeRendererState,
  snapshot: PlexRuntimeSnapshot,
  statusText = 'Ready',
): PlexRuntimeRendererState {
  return {
    ...state,
    snapshot,
    selectedSectionId: snapshot.library.selectedSectionId,
    selectedServerId: snapshot.servers.selected?.serverId ?? null,
    selectedItemRatingKey: snapshot.library.metadata?.ratingKey ?? null,
    errorText: snapshot.lastError === null ? null : sanitizePlexRuntimeError(snapshot.lastError),
    statusText,
    lastMetadata: snapshot.library.metadata,
  };
}

export function applyPlexIpcFailure<TValue>(
  state: PlexRuntimeRendererState,
  result: Extract<PlexIpcResult<TValue>, { ok: false }>,
): PlexRuntimeRendererState {
  const statusText = result.cancelled
    ? 'Cancelled'
    : result.stale ? 'Stale result ignored' : 'Failed';
  return {
    ...state,
    statusText,
    errorText: sanitizePlexRuntimeError(result.error),
  };
}

export function updatePlexRendererInputs(
  state: PlexRuntimeRendererState,
  input: Partial<Pick<PlexRuntimeRendererState, 'searchQuery' | 'homeUserPin' | 'selectedSectionId'>>,
): PlexRuntimeRendererState {
  return {
    ...state,
    searchQuery: input.searchQuery ?? state.searchQuery,
    homeUserPin: input.homeUserPin ?? state.homeUserPin,
    selectedSectionId: input.selectedSectionId ?? state.selectedSectionId,
  };
}

export function selectPlexRendererItem(
  state: PlexRuntimeRendererState,
  ratingKey: string,
): PlexRuntimeRendererState {
  return {
    ...state,
    selectedItemRatingKey: ratingKey,
  };
}

export function clearPlexRendererMetadata(
  state: PlexRuntimeRendererState,
  statusText = 'Metadata closed',
): PlexRuntimeRendererState {
  return {
    ...state,
    selectedItemRatingKey: null,
    lastMetadata: null,
    statusText,
    snapshot: state.snapshot === null
      ? null
      : {
        ...state.snapshot,
        library: {
          ...state.snapshot.library,
          metadata: null,
        },
      },
  };
}

export function clearPlexRendererSearch(
  state: PlexRuntimeRendererState,
  statusText = 'Search cleared',
): PlexRuntimeRendererState {
  return {
    ...clearPlexRendererMetadata(state, statusText),
    searchQuery: '',
    snapshot: state.snapshot === null
      ? null
      : {
        ...state.snapshot,
        library: {
          ...state.snapshot.library,
          search: null,
          metadata: null,
        },
      },
  };
}

export function clearPlexRendererItems(
  state: PlexRuntimeRendererState,
  statusText = 'Items cleared',
): PlexRuntimeRendererState {
  return {
    ...clearPlexRendererSearch(state, statusText),
    snapshot: state.snapshot === null
      ? null
      : {
        ...state.snapshot,
        library: {
          ...state.snapshot.library,
          items: [],
          search: null,
          metadata: null,
        },
      },
  };
}

export function clearPlexRendererSection(
  state: PlexRuntimeRendererState,
  statusText = 'Library selection cleared',
): PlexRuntimeRendererState {
  return {
    ...clearPlexRendererItems(state, statusText),
    selectedSectionId: null,
    snapshot: state.snapshot === null
      ? null
      : {
        ...state.snapshot,
        library: {
          ...state.snapshot.library,
          selectedSectionId: null,
          items: [],
          search: null,
          metadata: null,
        },
      },
  };
}

export function clearPlexRendererServer(
  state: PlexRuntimeRendererState,
  statusText = 'Server selection cleared for this setup view',
): PlexRuntimeRendererState {
  return {
    ...clearPlexRendererSection(state, statusText),
    selectedServerId: null,
  };
}

export function clearPlexRendererPinSubflow(
  state: PlexRuntimeRendererState,
  statusText = 'Sign-in flow cleared',
): PlexRuntimeRendererState {
  const snapshot = state.snapshot === null
    ? null
    : {
      ...state.snapshot,
      auth: {
        ...state.snapshot.auth,
        pin: null,
        homeUsers: [],
        state: state.snapshot.auth.state === 'pin-pending' ? 'signed-out' : state.snapshot.auth.state,
      },
    } satisfies PlexRuntimeSnapshot;
  return {
    ...state,
    snapshot,
    homeUserPin: '',
    statusText,
  };
}

export function sanitizePlexRuntimeError(error: PlexRuntimeError): string {
  if (error.code === 'PLEX_PARSE_FAILED') {
    return parseFailureText(error.operation);
  }

  switch (error.code) {
    case 'PLEX_VALIDATION_FAILED':
      return 'Check the selected value and try again.';
    case 'PLEX_AUTH_REQUIRED':
    case 'PLEX_AUTH_INVALID':
    case 'PLEX_UNAUTHORIZED':
      return 'Plex sign-in is required.';
    case 'PLEX_PIN_EXPIRED':
    case 'PLEX_PIN_TIMEOUT':
      return 'The Plex PIN expired.';
    case 'PLEX_CANCELLED':
      return 'The Plex operation was cancelled.';
    case 'PLEX_STALE_RESULT':
      return 'An older Plex result was ignored.';
    case 'PLEX_RATE_LIMITED':
      return 'Plex is rate limiting requests.';
    case 'PLEX_SERVER_UNREACHABLE':
      return 'The selected Plex server is unreachable.';
    case 'PLEX_ACCESS_DENIED':
      return 'Access was denied.';
    case 'PLEX_RESOURCE_NOT_FOUND':
      return 'The requested Plex item was not found.';
    case 'PLEX_STORAGE_UNAVAILABLE':
    case 'PLEX_STORAGE_CORRUPT':
      return 'Plex credential storage is unavailable.';
    case 'PLEX_LIBRARY_FAILED':
      return 'Plex library data could not be loaded.';
    case 'PLEX_UNKNOWN':
      return 'The Plex operation failed.';
  }
}

function parseFailureText(operation: PlexRuntimeOperation): string {
  switch (operation) {
    case 'requestPin':
    case 'pollPin':
    case 'getHomeUsers':
    case 'switchHomeUser':
      return 'Plex sign-in response could not be loaded.';
    case 'restoreSelectedServer':
    case 'refreshServers':
    case 'selectServer':
      return 'Plex server data could not be loaded.';
    case 'listLibrarySections':
    case 'listLibraryItems':
    case 'searchLibrary':
    case 'getMetadata':
      return 'Plex library data could not be loaded.';
    case 'getSnapshot':
    case 'cancelPin':
      return 'Plex response could not be loaded.';
  }
}

function createPendingMap(): Readonly<Record<PlexRendererOperation, boolean>> {
  const entries = PLEX_RENDERER_OPERATIONS.map((operation) => [operation, false] as const);
  return Object.fromEntries(entries) as Readonly<Record<PlexRendererOperation, boolean>>;
}

function formatPendingStatus(operation: PlexRendererOperation): string {
  switch (operation) {
    case 'getSnapshot':
      return 'Loading snapshot';
    case 'requestPin':
      return 'Requesting PIN';
    case 'pollPin':
    case 'pollPinLoop':
      return 'Checking PIN';
    case 'cancelPin':
    case 'cleanup':
      return 'Cancelling';
    case 'getHomeUsers':
      return 'Loading profiles';
    case 'switchHomeUser':
      return 'Switching profile';
    case 'restoreSelectedServer':
      return 'Restoring server';
    case 'refreshServers':
      return 'Refreshing servers';
    case 'selectServer':
      return 'Selecting server';
    case 'listLibrarySections':
      return 'Loading libraries';
    case 'listLibraryItems':
      return 'Loading items';
    case 'searchLibrary':
      return 'Searching library';
    case 'getMetadata':
      return 'Loading metadata';
  }
}
