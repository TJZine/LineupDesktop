import type {
  PlexServerHealthStatus,
  PlexServerSelectionFailureReason,
} from '../../../contracts/plex.js';

export interface PlexConnection {
  uri: string;
  protocol: 'http' | 'https';
  address: string;
  port: number;
  local: boolean;
  relay: boolean;
  latencyMs: number | null;
}

export interface PlexServer {
  id: string;
  name: string;
  sourceTitle: string;
  ownerId: string;
  owned: boolean;
  connections: PlexConnection[];
  capabilities: string[];
  preferredConnection: PlexConnection | null;
}

export interface PlexApiConnection {
  uri: string;
  protocol: string;
  address: string;
  port: number;
  local: boolean;
  relay: boolean;
}

export interface PlexApiResource {
  clientIdentifier: string;
  name: string;
  sourceTitle: string;
  ownerId: string;
  owned: boolean;
  provides: string;
  connections: PlexApiConnection[];
}

export interface MixedContentConfig {
  preferHttps: boolean;
  tryHttpsUpgrade: boolean;
  allowLocalHttp: boolean;
}

export type PlexConnectionProbeOutcome = 'reachable' | 'auth-required' | 'access-denied' | 'unreachable';

export interface PlexConnectionProbeResult {
  connection: PlexConnection;
  outcome: PlexConnectionProbeOutcome;
}

export interface PlexFastestConnectionProbeResult {
  selectedProbe: PlexConnectionProbeResult | null;
  authRequired: boolean;
  authState: Extract<PlexConnectionProbeOutcome, 'auth-required' | 'access-denied'> | null;
}

export interface PlexServerHealthRecord {
  status: PlexServerHealthStatus;
  connectionKind: 'local' | 'remote' | 'relay' | 'unknown';
  latencyMs?: number;
  testedAtMs: number;
}

export type PlexServerSelectionSource = 'manual' | 'discovery' | 'restored';

export interface PlexServerSelectionFailure {
  reason: PlexServerSelectionFailureReason;
  server?: PlexServer;
}
