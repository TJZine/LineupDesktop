import type {
  PlexServerSelectionSummary,
  PlexServerSummary,
} from '../../../contracts/plex.js';
import { throwIfPlexRequestAborted } from '../abort.js';
import type { DesktopPlexSelectedServerStore } from './desktopPlexSelectedServerStore.js';
import {
  createHealthRecord,
  findFastestConnectionProbe,
  parsePlexResources,
  toRendererSafeServerSummary,
} from './discoveryDomain.js';
import { PlexDiscoveryError } from './plexDiscoveryError.js';
import type { LivePlexTransportErrorCode } from '../livePlexTransportError.js';
import type {
  MixedContentConfig,
  PlexApiResource,
  PlexConnection,
  PlexConnectionProbeOutcome,
  PlexConnectionProbeResult,
  PlexFastestConnectionProbeResult,
  PlexServer,
  PlexServerHealthRecord,
  PlexServerSelectionSource,
} from './types.js';

export interface DesktopPlexDiscoveryTransport {
  discoverResources(input: { token?: string; signal?: AbortSignal | null }): Promise<unknown>;
  probeConnection(input: {
    server: PlexServer;
    connection: PlexConnection;
    token?: string;
    signal?: AbortSignal | null;
  }): Promise<DesktopPlexConnectionProbeTransportResult>;
}

export interface DesktopPlexConnectionProbeTransportResult {
  outcome: PlexConnectionProbeOutcome;
  latencyMs?: number | null;
}

export interface DesktopPlexServerDiscoveryOptions {
  transport: DesktopPlexDiscoveryTransport;
  selectedServerStore?: Pick<
    DesktopPlexSelectedServerStore,
    'readSelectedServerSummary' | 'saveSelectedServerSummary'
  >;
  mixedContentConfig?: Partial<MixedContentConfig>;
  nowMs?: () => number;
}

/**
 * Discovery owns main-memory connection custody, invalidates stale async
 * results with a context version, and persists only selected-server summaries.
 */
export class DesktopPlexServerDiscovery {
  private readonly transport: DesktopPlexDiscoveryTransport;
  private readonly selectedServerStore?: DesktopPlexServerDiscoveryOptions['selectedServerStore'];
  private readonly mixedContentConfig?: Partial<MixedContentConfig>;
  private readonly nowMs: () => number;
  private discoveryContextVersion = 0;
  private servers: PlexServer[] = [];
  private selectedServer: PlexServer | null = null;
  private selectedConnection: PlexConnection | null = null;
  private serverHealth = new Map<string, PlexServerHealthRecord>();

  constructor(options: DesktopPlexServerDiscoveryOptions) {
    this.transport = options.transport;
    this.selectedServerStore = options.selectedServerStore;
    this.mixedContentConfig = options.mixedContentConfig;
    this.nowMs = options.nowMs ?? Date.now;
  }

  async refreshServers(options: { token?: string; signal?: AbortSignal | null } = {}): Promise<PlexServerSummary[]> {
    throwIfAborted(options.signal);
    const contextVersion = this.discoveryContextVersion;
    const resources = await this.discoverResources(options.signal ?? null, options.token);
    throwIfAborted(options.signal);
    const servers = parsePlexResources(resources);

    if (contextVersion !== this.discoveryContextVersion) {
      return this.getServerSummaries();
    }

    this.servers = servers;
    if (this.selectedServer && !servers.some((server) => server.id === this.selectedServer?.id)) {
      this.selectedServer = null;
      this.selectedConnection = null;
    }

    return this.getServerSummaries();
  }

  getServerSummaries(): PlexServerSummary[] {
    const selectedServerId = this.selectedServer?.id ?? null;
    return this.servers.map((server) =>
      toRendererSafeServerSummary(server, selectedServerId, this.serverHealth.get(server.id)),
    );
  }

  getSelectedServerSummary(): PlexServerSummary | null {
    if (!this.selectedServer) {
      return null;
    }
    return toRendererSafeServerSummary(
      this.selectedServer,
      this.selectedServer.id,
      this.serverHealth.get(this.selectedServer.id),
    );
  }

  getSelectedConnectionForMain(): PlexConnection | null {
    return this.selectedConnection ? { ...this.selectedConnection } : null;
  }

  resetDiscoveryContext(): void {
    this.discoveryContextVersion += 1;
    this.servers = [];
    this.selectedServer = null;
    this.selectedConnection = null;
    this.serverHealth.clear();
  }

  async selectServer(
    serverId: string,
    options: {
      source?: PlexServerSelectionSource;
      token?: string;
      profileId?: string | null;
      signal?: AbortSignal | null;
    } = {},
  ): Promise<PlexServerSelectionSummary> {
    const contextVersion = this.discoveryContextVersion;
    const server = this.servers.find((candidate) => candidate.id === serverId);
    if (!server) {
      return { kind: 'selection-failed', reason: 'server-not-found', persisted: false };
    }

    const probeSummary = await this.findFastestConnection(server, options.signal ?? null, options.token);
    throwIfAborted(options.signal);
    if (contextVersion !== this.discoveryContextVersion) {
      return { kind: 'selection-failed', reason: 'server-not-found', persisted: false };
    }

    if (!probeSummary.selectedProbe) {
      const reason = mapProbeSummaryToFailureReason(probeSummary);
      this.selectedServer = null;
      this.selectedConnection = null;
      this.serverHealth.set(
        server.id,
        createHealthRecord({
          status: reason === 'access-denied'
            ? 'access-denied'
            : reason === 'auth-required'
              ? 'auth-required'
              : 'unreachable',
          testedAtMs: this.nowMs(),
        }),
      );
      return {
        kind: 'selection-failed',
        reason,
        server: toRendererSafeServerSummary(server, null, this.serverHealth.get(server.id)),
        persisted: false,
      };
    }

    const selectedConnection = probeSummary.selectedProbe.connection;
    const selectedServer = {
      ...server,
      preferredConnection: selectedConnection,
      connections: server.connections.map((connection) => ({ ...connection })),
    };

    if (!this.selectedServerStore) {
      throw new PlexDiscoveryError('server-error', 'Plex selected-server store is not available');
    }
    const profileId = normalizeActiveProfileId(options.profileId);
    if (profileId === null) {
      return {
        kind: 'selection-failed',
        reason: 'auth-required',
        server: toRendererSafeServerSummary(server, null, this.serverHealth.get(server.id)),
        persisted: false,
      };
    }
    throwIfAborted(options.signal);
    await this.selectedServerStore.saveSelectedServerSummary(
      selectedServer,
      options.source ?? 'discovery',
      { profileId, signal: options.signal ?? null },
    );
    throwIfAborted(options.signal);
    if (contextVersion !== this.discoveryContextVersion) {
      return { kind: 'selection-failed', reason: 'server-not-found', persisted: false };
    }

    this.selectedServer = selectedServer;
    this.selectedConnection = { ...selectedConnection };
    this.serverHealth.set(
      server.id,
      createHealthRecord({
        status: 'ok',
        connection: selectedConnection,
        latencyMs: selectedConnection.latencyMs,
        testedAtMs: this.nowMs(),
      }),
    );

    return {
      kind: 'selected',
      server: toRendererSafeServerSummary(
        selectedServer,
        selectedServer.id,
        this.serverHealth.get(selectedServer.id),
      ),
      persisted: true,
    };
  }

  async restoreSelectedServer(options: {
    token?: string;
    profileId?: string | null;
    signal?: AbortSignal | null;
  } = {}): Promise<PlexServerSelectionSummary> {
    if (!this.selectedServerStore) {
      throw new PlexDiscoveryError('server-error', 'Plex selected-server store is not available');
    }

    throwIfAborted(options.signal);
    const profileId = normalizeActiveProfileId(options.profileId);
    if (profileId === null) {
      return { kind: 'selection-failed', reason: 'no-persisted-server', persisted: false };
    }
    const persisted = await this.selectedServerStore.readSelectedServerSummary(profileId);
    throwIfAborted(options.signal);
    if (!persisted) {
      return { kind: 'selection-failed', reason: 'no-persisted-server', persisted: false };
    }

    await this.refreshServers(options);
    return this.selectServer(persisted.serverId, {
      source: 'restored',
      token: options.token,
      profileId,
      signal: options.signal ?? null,
    });
  }

  private async discoverResources(signal: AbortSignal | null, token?: string): Promise<unknown> {
    try {
      return await this.transport.discoverResources({
        ...(token !== undefined ? { token } : {}),
        signal,
      });
    } catch (error) {
      if (error instanceof PlexDiscoveryError) {
        throw error;
      }
      if (signal?.aborted || isTransportAbortError(error)) {
        throw new PlexDiscoveryError('aborted', 'Plex discovery request was aborted', undefined, {
          cause: error,
        });
      }
      if (isLivePlexTransportLikeError(error)) {
        throw mapLiveTransportLikeErrorToDiscoveryError(error);
      }
      throw new PlexDiscoveryError('server-unreachable', 'Plex discovery transport failed', undefined, {
        cause: error,
        retryable: true,
      });
    }
  }

  private async findFastestConnection(
    server: PlexServer,
    signal: AbortSignal | null,
    token?: string,
  ): Promise<PlexFastestConnectionProbeResult> {
    return findFastestConnectionProbe({
      server,
      mixedContentConfig: this.mixedContentConfig,
      probeConnection: (connection) => this.probeConnection(server, connection, signal, token),
    });
  }

  private async probeConnection(
    server: PlexServer,
    connection: PlexConnection,
    signal: AbortSignal | null,
    token?: string,
  ): Promise<PlexConnectionProbeResult> {
    throwIfAborted(signal);
    try {
      const result = await this.transport.probeConnection({
        server,
        connection,
        ...(token !== undefined ? { token } : {}),
        signal,
      });
      throwIfAborted(signal);
      return {
        connection: {
          ...connection,
          latencyMs: typeof result.latencyMs === 'number' && Number.isFinite(result.latencyMs)
            ? Math.max(0, Math.round(result.latencyMs))
            : connection.latencyMs,
        },
        outcome: result.outcome,
      };
    } catch {
      throwIfAborted(signal);
      return { connection, outcome: 'unreachable' };
    }
  }
}

export function createPlexApiResource(input: Partial<PlexApiResource> = {}): PlexApiResource {
  return {
    clientIdentifier: input.clientIdentifier ?? 'server-1',
    name: input.name ?? 'Server 1',
    sourceTitle: input.sourceTitle ?? input.name ?? 'Server 1',
    ownerId: input.ownerId ?? 'owner-1',
    owned: input.owned ?? true,
    provides: input.provides ?? 'server',
    connections: input.connections ?? [],
  };
}

function mapProbeSummaryToFailureReason(
  summary: PlexFastestConnectionProbeResult,
): 'unreachable' | 'auth-required' | 'access-denied' {
  if (summary.authState === 'access-denied') {
    return 'access-denied';
  }
  if (summary.authState === 'auth-required' || summary.authRequired) {
    return 'auth-required';
  }
  return 'unreachable';
}

function throwIfAborted(signal?: AbortSignal | null): void {
  throwIfPlexRequestAborted(
    signal,
    () => new PlexDiscoveryError('aborted', 'Plex discovery request was aborted'),
  );
}

function normalizeActiveProfileId(profileId?: string | null): string | null {
  const normalized = profileId?.trim() ?? '';
  return normalized.length > 0 ? normalized : null;
}

function isTransportAbortError(error: unknown): boolean {
  return error instanceof Error && 'code' in error && error.code === 'aborted';
}

function isLivePlexTransportLikeError(error: unknown): error is {
  code: LivePlexTransportErrorCode;
  httpStatus?: number;
  retryable: boolean;
} {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof error.code === 'string' &&
    isDiscoveryTransportErrorCode(error.code) &&
    'retryable' in error &&
    typeof error.retryable === 'boolean'
  );
}

function isDiscoveryTransportErrorCode(code: string): code is LivePlexTransportErrorCode {
  return (
    code === 'auth-required' ||
    code === 'auth-invalid' ||
    code === 'resource-not-found' ||
    code === 'rate-limited' ||
    code === 'server-unreachable' ||
    code === 'parse-error' ||
    code === 'aborted' ||
    code === 'timeout' ||
    code === 'server-error'
  );
}

function mapLiveTransportLikeErrorToDiscoveryError(error: {
  code: LivePlexTransportErrorCode;
  httpStatus?: number;
  retryable: boolean;
}): PlexDiscoveryError {
  const code = error.code === 'timeout' ? 'server-unreachable' : error.code;
  return new PlexDiscoveryError(
    code,
    messageForTransportDiscoveryErrorCode(code),
    error.httpStatus,
    {
      cause: error,
      retryable: error.retryable,
    },
  );
}

function messageForTransportDiscoveryErrorCode(code: Exclude<LivePlexTransportErrorCode, 'timeout'>): string {
  switch (code) {
    case 'auth-required':
      return 'Plex authentication is required';
    case 'auth-invalid':
      return 'Plex authentication was rejected';
    case 'resource-not-found':
      return 'Plex discovery resource was not found';
    case 'rate-limited':
      return 'Plex discovery request was rate limited';
    case 'server-unreachable':
      return 'Plex discovery transport failed';
    case 'parse-error':
      return 'Plex discovery response could not be parsed';
    case 'aborted':
      return 'Plex discovery request was aborted';
    case 'server-error':
      return 'Plex discovery service request failed';
  }
}
