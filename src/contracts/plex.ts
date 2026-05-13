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
  'uri',
  'url',
  'headers',
  'rawHeaders',
  'authToken',
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
