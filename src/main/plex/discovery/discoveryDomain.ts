import type {
  PlexServerHealthSummary,
  PlexServerSummary,
} from '../../../contracts/plex.js';
import { DEFAULT_MIXED_CONTENT_CONFIG } from './constants.js';
import { PlexDiscoveryError } from './plexDiscoveryError.js';
import type {
  MixedContentConfig,
  PlexApiConnection,
  PlexApiResource,
  PlexConnection,
  PlexConnectionProbeResult,
  PlexFastestConnectionProbeResult,
  PlexServer,
  PlexServerHealthRecord,
} from './types.js';

export function parsePlexResources(resources: unknown): PlexServer[] {
  if (!Array.isArray(resources)) {
    throw new PlexDiscoveryError('parse-error', 'Plex discovery resources must be an array');
  }

  const servers: PlexServer[] = [];
  for (const resource of resources) {
    if (!isPlexApiResourceLike(resource)) {
      continue;
    }
    if (!resource.provides.split(',').map((capability) => capability.trim()).includes('server')) {
      continue;
    }

    const connections = resource.connections
      .map(parsePlexConnection)
      .filter((connection): connection is PlexConnection => connection !== null);

    servers.push({
      id: resource.clientIdentifier.trim(),
      name: resource.name.trim(),
      sourceTitle: typeof resource.sourceTitle === 'string' ? resource.sourceTitle.trim() : '',
      ownerId: typeof resource.ownerId === 'string' ? resource.ownerId.trim() : '',
      owned: normalizeBoolean(resource.owned),
      connections,
      capabilities: resource.provides
        .split(',')
        .map((capability) => capability.trim())
        .filter(Boolean),
      preferredConnection: null,
    });
  }

  return servers.filter((server) => server.id.length > 0 && server.name.length > 0);
}

export async function findFastestConnectionProbe(options: {
  server: PlexServer;
  mixedContentConfig?: Partial<MixedContentConfig>;
  probeConnection: (connection: PlexConnection) => Promise<PlexConnectionProbeResult>;
}): Promise<PlexFastestConnectionProbeResult> {
  const mixedContentConfig = {
    ...DEFAULT_MIXED_CONTENT_CONFIG,
    ...options.mixedContentConfig,
  };
  const summary: PlexFastestConnectionProbeResult = {
    selectedProbe: null,
    authRequired: false,
    authState: null,
  };

  for (const tier of buildProbeTiers(options.server, mixedContentConfig)) {
    if (tier.length === 0) {
      continue;
    }

    const tierProbes = await Promise.all(tier.map((connection) => options.probeConnection(connection)));
    const selectedProbe = pickFastestReachableProbe(tierProbes);

    for (const probe of tierProbes) {
      if (probe.outcome === 'access-denied') {
        summary.authState = 'access-denied';
      } else if (probe.outcome === 'auth-required') {
        summary.authRequired = true;
        summary.authState ??= 'auth-required';
      }
    }

    if (selectedProbe) {
      return { ...summary, selectedProbe };
    }
  }

  return summary;
}

export function toRendererSafeServerSummary(
  server: PlexServer,
  selectedServerId: string | null,
  health?: PlexServerHealthRecord,
): PlexServerSummary {
  return {
    serverId: server.id,
    name: server.name,
    owned: server.owned,
    ...(server.sourceTitle.length > 0 ? { sourceTitle: server.sourceTitle } : {}),
    connectionCount: server.connections.length,
    hasLocalConnection: server.connections.some((connection) => connection.local && !connection.relay),
    hasRemoteConnection: server.connections.some((connection) => !connection.local && !connection.relay),
    hasRelayConnection: server.connections.some((connection) => connection.relay),
    selected: selectedServerId === server.id,
    ...(health ? { health: toRendererSafeHealthSummary(health) } : {}),
  };
}

export function createHealthRecord(options: {
  status: PlexServerHealthRecord['status'];
  connection?: PlexConnection | null;
  latencyMs?: number | null;
  testedAtMs: number;
}): PlexServerHealthRecord {
  return {
    status: options.status,
    connectionKind: getConnectionKind(options.connection ?? null),
    ...(typeof options.latencyMs === 'number' && Number.isFinite(options.latencyMs)
      ? { latencyMs: Math.max(0, Math.round(options.latencyMs)) }
      : {}),
    testedAtMs: Math.max(0, Math.floor(options.testedAtMs)),
  };
}

function toRendererSafeHealthSummary(health: PlexServerHealthRecord): PlexServerHealthSummary {
  return {
    status: health.status,
    connectionKind: health.connectionKind,
    ...(health.latencyMs === undefined ? {} : { latencyMs: health.latencyMs }),
    testedAtMs: health.testedAtMs,
  };
}

function parsePlexConnection(connection: PlexApiConnection): PlexConnection | null {
  const normalizedUri = normalizeConnectionUri(connection.uri);
  if (!normalizedUri) {
    return null;
  }
  const parsed = new URL(normalizedUri);
  return {
    uri: normalizedUri,
    protocol: parsed.protocol === 'https:' ? 'https' : 'http',
    address: String(connection.address ?? '').trim(),
    port: normalizePort(connection.port),
    local: normalizeBoolean(connection.local),
    relay: normalizeBoolean(connection.relay),
    latencyMs: null,
  };
}

function normalizeConnectionUri(uri: string): string | null {
  try {
    const parsed = new URL(uri);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null;
    }
    if (parsed.username || parsed.password || !parsed.hostname) {
      return null;
    }
    return parsed.origin;
  } catch {
    return null;
  }
}

function buildProbeTiers(server: PlexServer, mixedContentConfig: MixedContentConfig): PlexConnection[][] {
  const httpsConnections = server.connections.filter((connection) => connection.protocol === 'https');
  const localDirectHttps = httpsConnections.filter((connection) => connection.local && !connection.relay);
  const remoteDirectHttps = httpsConnections.filter((connection) => !connection.local && !connection.relay);
  const relayHttps = httpsConnections.filter((connection) => connection.relay);
  const localDirectHttp = server.connections.filter(
    (connection) => connection.protocol === 'http' && connection.local && !connection.relay,
  );
  const tiers: PlexConnection[][] = [];

  if (!mixedContentConfig.preferHttps && mixedContentConfig.allowLocalHttp) {
    tiers.push(localDirectHttp);
  }

  tiers.push(localDirectHttps);

  if (mixedContentConfig.preferHttps) {
    tiers.push(remoteDirectHttps, relayHttps);
  }

  if (mixedContentConfig.tryHttpsUpgrade) {
    tiers.push(localDirectHttp.map(upgradeConnectionToHttps));
  }

  if (!mixedContentConfig.preferHttps) {
    tiers.push(remoteDirectHttps, relayHttps);
  }

  if (mixedContentConfig.allowLocalHttp && mixedContentConfig.preferHttps) {
    tiers.push(localDirectHttp);
  }

  return tiers;
}

function pickFastestReachableProbe(
  probes: readonly PlexConnectionProbeResult[],
): PlexConnectionProbeResult | null {
  let fastest: PlexConnectionProbeResult | null = null;
  let fastestLatency = Number.POSITIVE_INFINITY;
  for (const probe of probes) {
    if (probe.outcome !== 'reachable') {
      continue;
    }
    const latency = typeof probe.connection.latencyMs === 'number'
      ? probe.connection.latencyMs
      : Number.POSITIVE_INFINITY;
    if (fastest === null || latency < fastestLatency) {
      fastest = probe;
      fastestLatency = latency;
    }
  }
  return fastest;
}

function upgradeConnectionToHttps(connection: PlexConnection): PlexConnection {
  return {
    ...connection,
    uri: connection.uri.replace(/^http:/u, 'https:'),
    protocol: 'https',
    latencyMs: null,
  };
}

function getConnectionKind(connection: PlexConnection | null): PlexServerHealthRecord['connectionKind'] {
  if (!connection) {
    return 'unknown';
  }
  if (connection.relay) {
    return 'relay';
  }
  return connection.local ? 'local' : 'remote';
}

function isPlexApiResourceLike(value: unknown): value is PlexApiResource {
  if (value === null || typeof value !== 'object') {
    return false;
  }
  const candidate = value as Partial<PlexApiResource>;
  return (
    typeof candidate.clientIdentifier === 'string' &&
    typeof candidate.name === 'string' &&
    typeof candidate.provides === 'string' &&
    Array.isArray(candidate.connections)
  );
}

function normalizeBoolean(value: unknown): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true' || normalized === 'yes';
  }
  return false;
}

function normalizePort(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(String(value ?? '').trim());
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 65_535 ? parsed : 0;
}
