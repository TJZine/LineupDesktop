import { PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS } from './persistence.js';
import { PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS } from './player.js';

/**
 * Plex renderer summaries must omit credentials, raw connection details,
 * headers, filesystem paths, raw payloads, and image-key material.
 */
export const PLEX_FORBIDDEN_RENDERER_FIELD_KEYS = [
  ...PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS,
  ...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  'serverUri',
  'rawServerUri',
  'connectionUri',
  'rawConnectionUri',
  'address',
  'port',
  'uri',
  'url',
  'headers',
  'rawHeaders',
  'authToken',
  'accessToken',
  'access_token',
  'authenticationToken',
  'token',
  'accountToken',
  'activeToken',
  'plexToken',
  'clientSecret',
  'authorization',
  'X-Plex-Token',
  'header',
  'secret',
  'credential',
  'password',
  'rawPayload',
  'rawPlexPayload',
  'mediaFile',
  'mediaPart',
  'file',
  'path',
  'thumb',
  'art',
  'banner',
  'clearLogo',
] as const;

export type PlexForbiddenRendererFieldKey = (typeof PLEX_FORBIDDEN_RENDERER_FIELD_KEYS)[number];

const PLEX_FORBIDDEN_RENDERER_FIELD_KEY_SET = new Set(
  PLEX_FORBIDDEN_RENDERER_FIELD_KEYS.map((key) => key.toLowerCase()),
);

export interface PlexLibrarySectionSummary {
  id: string;
  title: string;
  type: 'movie' | 'show' | 'artist' | 'photo';
  contentCount: number | null;
  episodeCount?: number;
  lastScannedAtMs: number;
}

export interface PlexMediaItemSummary {
  ratingKey: string;
  type: 'movie' | 'show' | 'episode' | 'track' | 'clip';
  title: string;
  sortTitle: string;
  summary: string;
  year: number;
  durationMs: number;
  addedAtMs: number;
  updatedAtMs: number;
  rating?: number;
  audienceRating?: number;
  contentRating?: string;
  genres?: readonly string[];
  directors?: readonly string[];
  actors?: readonly string[];
  studios?: readonly string[];
  grandparentTitle?: string;
  parentTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  viewOffset?: number;
  viewCount?: number;
  lastViewedAtMs?: number;
}

export interface PlexCollectionSummary {
  ratingKey: string;
  title: string;
  childCount: number;
}

export interface PlexPlaylistSummary {
  ratingKey: string;
  title: string;
  duration: number;
  leafCount: number;
}

export interface PlexTagDirectorySummary {
  key: string;
  title: string;
  count: number | null;
}

export interface PlexAuthProfileSummary {
  accountId: string;
  username?: string;
  displayName?: string;
  activeProfileId?: string;
  preferredSubtitleLanguage?: string;
}

export interface PlexHomeUserSummary {
  id: string;
  title: string;
  admin: boolean;
  protected: boolean;
  restricted?: boolean;
}

export type PlexServerHealthStatus = 'ok' | 'unreachable' | 'auth-required' | 'access-denied';

export type PlexServerConnectionKind = 'local' | 'remote' | 'relay' | 'unknown';

export interface PlexServerHealthSummary {
  status: PlexServerHealthStatus;
  connectionKind: PlexServerConnectionKind;
  latencyMs?: number;
  testedAtMs: number;
}

export interface PlexServerSummary {
  serverId: string;
  name: string;
  owned: boolean;
  sourceTitle?: string;
  connectionCount: number;
  hasLocalConnection: boolean;
  hasRemoteConnection: boolean;
  hasRelayConnection: boolean;
  selected: boolean;
  health?: PlexServerHealthSummary;
}

export type PlexServerSelectionFailureReason =
  | 'server-not-found'
  | 'unreachable'
  | 'auth-required'
  | 'access-denied'
  | 'no-persisted-server';

export type PlexServerSelectionSummary =
  | {
      kind: 'selected';
      server: PlexServerSummary;
      persisted: boolean;
    }
  | {
      kind: 'selection-failed';
      reason: PlexServerSelectionFailureReason;
      server?: PlexServerSummary;
      persisted: false;
    };

export const PLEX_RUNTIME_OPERATIONS = [
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
] as const;

export type PlexRuntimeOperation = (typeof PLEX_RUNTIME_OPERATIONS)[number];

export const PLEX_RUNTIME_ERROR_CODES = [
  'PLEX_UNAUTHORIZED',
  'PLEX_VALIDATION_FAILED',
  'PLEX_CANCELLED',
  'PLEX_STALE_RESULT',
  'PLEX_AUTH_REQUIRED',
  'PLEX_AUTH_INVALID',
  'PLEX_PIN_EXPIRED',
  'PLEX_PIN_TIMEOUT',
  'PLEX_RATE_LIMITED',
  'PLEX_SERVER_UNREACHABLE',
  'PLEX_ACCESS_DENIED',
  'PLEX_RESOURCE_NOT_FOUND',
  'PLEX_STORAGE_UNAVAILABLE',
  'PLEX_STORAGE_CORRUPT',
  'PLEX_PARSE_FAILED',
  'PLEX_LIBRARY_FAILED',
  'PLEX_UNKNOWN',
] as const;

export type PlexRuntimeErrorCode = (typeof PLEX_RUNTIME_ERROR_CODES)[number];

export interface PlexRuntimeError {
  code: PlexRuntimeErrorCode;
  message: string;
  retryable: boolean;
  recoverable: boolean;
  operation: PlexRuntimeOperation;
  httpStatus?: number;
}

export type PlexIpcResult<TValue> =
  | { ok: true; value: TValue; requestId: string }
  | {
      ok: false;
      error: PlexRuntimeError;
      requestId: string;
      cancelled?: true;
      stale?: true;
    };

export interface PlexIpcRequest<TPayload> {
  requestId: string;
  payload: TPayload;
}

export type PlexEmptyRequest = PlexIpcRequest<Record<string, never>>;
export type PlexPollPinRequest = PlexIpcRequest<{ pinId: number }>;
export type PlexCancelPinRequest = PlexIpcRequest<{ pinId: number }>;
export type PlexSwitchHomeUserRequest = PlexIpcRequest<{
  userId: string;
  pin?: string | null;
}>;
export type PlexSelectServerRequest = PlexIpcRequest<{ serverId: string }>;
export type PlexListLibraryItemsRequest = PlexIpcRequest<{
  sectionId: string;
  offset?: number;
  limit?: number;
  sort?: string;
}>;
export type PlexSearchLibraryRequest = PlexIpcRequest<{
  query: string;
  sectionId?: string;
  limit?: number;
}>;
export type PlexGetMetadataRequest = PlexIpcRequest<{ ratingKey: string }>;

export interface PlexPinSummary {
  id: number;
  code: string;
  expiresAtMs: number;
  claimed: boolean;
}

export interface PlexRuntimeSnapshot {
  auth: {
    state: 'signed-out' | 'pin-pending' | 'signed-in';
    pin: PlexPinSummary | null;
    profile: PlexAuthProfileSummary | null;
    homeUsers: readonly PlexHomeUserSummary[];
    credentialStatus: 'missing' | 'present' | 'unavailable' | 'corrupt';
  };
  servers: {
    status: 'idle' | 'loading' | 'ready' | 'failed';
    selected: PlexServerSummary | null;
    items: readonly PlexServerSummary[];
    lastSelection: PlexServerSelectionSummary | null;
  };
  library: {
    status: 'idle' | 'loading' | 'ready' | 'failed';
    sections: readonly PlexLibrarySectionSummary[];
    selectedSectionId: string | null;
    items: readonly PlexMediaItemSummary[];
    search: { query: string; items: readonly PlexMediaItemSummary[] } | null;
    metadata: PlexMediaItemSummary | null;
  };
  lastError: PlexRuntimeError | null;
  updatedAtMs: number;
}

export interface PlexRequestPinValue {
  pin: PlexPinSummary;
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexPollPinValue {
  pin: PlexPinSummary;
  profile: PlexAuthProfileSummary | null;
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexCancelPinValue {
  pinId: number;
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexGetHomeUsersValue {
  users: readonly PlexHomeUserSummary[];
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexSwitchHomeUserValue {
  profile: PlexAuthProfileSummary;
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexRestoreSelectedServerValue {
  selection: PlexServerSelectionSummary;
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexRefreshServersValue {
  servers: readonly PlexServerSummary[];
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexSelectServerValue {
  selection: PlexServerSelectionSummary;
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexListLibrarySectionsValue {
  sections: readonly PlexLibrarySectionSummary[];
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexListLibraryItemsValue {
  sectionId: string;
  offset: number;
  limit: number;
  items: readonly PlexMediaItemSummary[];
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexSearchLibraryValue {
  query: string;
  sectionId: string | null;
  items: readonly PlexMediaItemSummary[];
  snapshot: PlexRuntimeSnapshot;
}

export interface PlexGetMetadataValue {
  item: PlexMediaItemSummary;
  snapshot: PlexRuntimeSnapshot;
}

/**
 * Rejects known forbidden field names case-insensitively; it is not a general
 * proof that arbitrary values are secret-free.
 */
export function containsPlexForbiddenRendererField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => containsPlexForbiddenRendererField(item));
  }

  if (value === null || typeof value !== 'object') {
    return false;
  }

  for (const [key, child] of Object.entries(value)) {
    if (PLEX_FORBIDDEN_RENDERER_FIELD_KEY_SET.has(key.toLowerCase())) {
      return true;
    }
    if (containsPlexForbiddenRendererField(child)) {
      return true;
    }
  }

  return false;
}
