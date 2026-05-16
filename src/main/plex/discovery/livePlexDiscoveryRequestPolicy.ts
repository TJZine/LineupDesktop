import type { PlexApiConnection, PlexApiResource } from './types.js';
import { parseXmlDiscoveryResourceArray } from './livePlexDiscoveryXmlParser.js';
import { LivePlexTransportError } from '../livePlexTransportError.js';

export type DiscoveryHeadersLike = {
  get(name: string): string | null;
};

export interface DiscoveryTextResponse {
  status: number;
  headers: DiscoveryHeadersLike | undefined;
  text: string;
}

export interface DiscoveryFetchVariant {
  url: URL;
  headers: Record<string, string>;
}

export interface LivePlexDiscoveryRequestPolicyOptions {
  token?: string;
  signal: AbortSignal | null;
  fetchText(input: {
    url: URL;
    init: RequestInit;
    signal: AbortSignal | null;
  }): Promise<DiscoveryTextResponse>;
  waitMs(delayMs: number): Promise<void>;
}

const DISCOVERY_MAX_ATTEMPTS = 2;
const DISCOVERY_RATE_LIMIT_DEFAULT_DELAY_MS = 2_000;
const DISCOVERY_RATE_LIMIT_MAX_DELAY_MS = 30_000;
const DISCOVERY_RETRY_BACKOFF_MS = 500;
const MIN_PORT = 1;
const MAX_PORT = 65_535;
const PLEX_TV_ORIGIN = 'https://plex.tv';
const PLEX_CLIENTS_ORIGIN = 'https://clients.plex.tv';
const PLEX_TOKEN_HEADER_NAME = ['X-Plex', 'Token'].join('-');
const NUMERIC_RETRY_AFTER_PATTERN = /^[+-]?(?:\d+\.?\d*|\.\d+)$/u;

export async function discoverPlexResourcesWithRequestPolicy(
  options: LivePlexDiscoveryRequestPolicyOptions,
): Promise<PlexApiResource[]> {
  const variants = buildDiscoveryFetchVariants(options.token);
  let lastRetryableError: LivePlexTransportError | null = null;
  let lastServerError: LivePlexTransportError | null = null;

  for (let attempt = 0; attempt < DISCOVERY_MAX_ATTEMPTS; attempt += 1) {
    let retryScheduled = false;

    for (const variant of variants) {
      let response: DiscoveryTextResponse;
      try {
        response = await options.fetchText({
          url: variant.url,
          init: {
            method: 'GET',
            headers: variant.headers,
          },
          signal: options.signal,
        });
      } catch (error) {
        if (error instanceof LivePlexTransportError && isDiscoveryRetryableTransportError(error)) {
          lastRetryableError = error;
          continue;
        }
        throw error;
      }

      if (response.status === 429 && attempt < DISCOVERY_MAX_ATTEMPTS - 1) {
        await options.waitMs(getDiscoveryRateLimitDelayMs(response.headers));
        retryScheduled = true;
        break;
      }

      if (response.status >= 500 && response.status <= 599) {
        lastServerError = new LivePlexTransportError('server-error', 'Plex service request failed', response.status, {
          retryable: true,
        });
        continue;
      }

      throwForDiscoveryHttpStatus(response.status);
      return parseDiscoveryResourcesResponse(
        response.text,
        getResponseContentType(response.headers),
        response.status,
      );
    }

    if (retryScheduled) {
      continue;
    }
    if ((lastServerError ?? lastRetryableError) && attempt < DISCOVERY_MAX_ATTEMPTS - 1) {
      await options.waitMs(DISCOVERY_RETRY_BACKOFF_MS);
    }
  }

  if (lastServerError) {
    throw lastServerError;
  }
  if (lastRetryableError) {
    throw lastRetryableError;
  }
  throw new LivePlexTransportError('server-unreachable', 'Plex service is unreachable', undefined, {
    retryable: true,
  });
}

function buildDiscoveryFetchVariants(token?: string): DiscoveryFetchVariant[] {
  const headers = {
    Accept: 'application/json',
    ...(token !== undefined ? { [PLEX_TOKEN_HEADER_NAME]: token } : {}),
  };
  const baseUrl = buildDiscoveryResourcesUrl(PLEX_TV_ORIGIN);
  const variants: DiscoveryFetchVariant[] = [{ url: baseUrl, headers }];

  if (token === undefined || token.length === 0) {
    return variants;
  }

  variants.push(
    { url: withTrustedTokenQuery(baseUrl, token), headers },
    { url: withTrustedTokenQuery(buildDiscoveryResourcesUrl(PLEX_CLIENTS_ORIGIN), token), headers },
  );
  return variants;
}

function buildDiscoveryResourcesUrl(origin: string): URL {
  const url = new URL('/api/v2/resources', origin);
  url.searchParams.set('includeHttps', '1');
  url.searchParams.set('includeRelay', '1');
  return url;
}

function withTrustedTokenQuery(url: URL, token: string): URL {
  const trustedUrl = new URL(url.toString());
  if (trustedUrl.origin === PLEX_TV_ORIGIN || trustedUrl.origin === PLEX_CLIENTS_ORIGIN) {
    trustedUrl.searchParams.set(PLEX_TOKEN_HEADER_NAME, token);
  }
  return trustedUrl;
}

function parseDiscoveryResourcesResponse(text: string, contentType: string, status: number): PlexApiResource[] {
  if (text.trim().length === 0) {
    return [];
  }

  const jsonResources = parseJsonDiscoveryResourceArray(text, status);
  if (jsonResources) {
    return jsonResources;
  }

  if (!isXmlResourceResponse(text, contentType)) {
    throw new LivePlexTransportError('parse-error', 'Plex discovery response could not be parsed', status);
  }

  return parseXmlDiscoveryResourceArray(text, status);
}

function parseJsonDiscoveryResourceArray(text: string, status: number): PlexApiResource[] | null {
  try {
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed)) {
      return parsed.map((resource) => normalizeJsonResource(resource, status));
    }
  } catch (error) {
    if (error instanceof LivePlexTransportError) {
      throw error;
    }
  }
  return null;
}

function normalizeJsonResource(resource: unknown, status: number): PlexApiResource {
  if (!isRecord(resource)) {
    throwInvalidDiscoveryResource(status);
  }
  return {
    clientIdentifier: readString(resource.clientIdentifier),
    name: readString(resource.name),
    sourceTitle: readString(resource.sourceTitle),
    ownerId: readString(resource.ownerId),
    owned: readBoolean(resource.owned),
    provides: readString(resource.provides),
    connections: readJsonConnections(resource.connections, status),
  };
}

function readJsonConnections(connections: unknown, status: number): PlexApiConnection[] {
  if (connections === undefined || connections === null) {
    return [];
  }
  if (!Array.isArray(connections)) {
    throwInvalidDiscoveryResource(status);
  }
  return connections.map((connection) => normalizeJsonConnection(connection, status));
}

function normalizeJsonConnection(connection: unknown, status: number): PlexApiConnection {
  if (!isRecord(connection)) {
    throw new LivePlexTransportError('parse-error', 'Invalid Plex discovery connection payload', status);
  }
  return {
    uri: readString(connection.uri),
    protocol: readString(connection.protocol),
    address: readString(connection.address),
    port: normalizePort(connection.port),
    local: readBoolean(connection.local),
    relay: readBoolean(connection.relay),
  };
}

function isXmlResourceResponse(text: string, contentType: string): boolean {
  return contentType.toLowerCase().includes('xml') || text.trim().startsWith('<');
}

function throwInvalidDiscoveryResource(status: number): never {
  throw new LivePlexTransportError('parse-error', 'Invalid Plex discovery resource payload', status);
}

function throwForDiscoveryHttpStatus(status: number): void {
  if (status >= 200 && status < 300) {
    return;
  }
  if (status === 401) {
    throw new LivePlexTransportError('auth-required', 'Plex authentication is required', 401);
  }
  if (status === 403) {
    throw new LivePlexTransportError('auth-invalid', 'Plex authentication was rejected', 403);
  }
  if (status === 404) {
    throw new LivePlexTransportError('resource-not-found', 'Plex resource was not found', 404);
  }
  if (status === 429) {
    throw new LivePlexTransportError('rate-limited', 'Plex request was rate limited', 429, {
      retryable: true,
    });
  }
  if (status >= 500) {
    throw new LivePlexTransportError('server-error', 'Plex service request failed', status, {
      retryable: true,
    });
  }
  throw new LivePlexTransportError('server-error', 'Plex service request failed', status);
}

function getResponseContentType(headers: DiscoveryHeadersLike | undefined): string {
  return headers?.get('Content-Type') ?? headers?.get('content-type') ?? '';
}

function getDiscoveryRateLimitDelayMs(headers: DiscoveryHeadersLike | undefined): number {
  const retryAfter = headers?.get('Retry-After') ?? headers?.get('retry-after') ?? '';
  if (retryAfter.length === 0) {
    return DISCOVERY_RATE_LIMIT_DEFAULT_DELAY_MS;
  }

  const delayMs = parseRetryAfterDelayMs(retryAfter);
  if (!Number.isFinite(delayMs) || delayMs <= 0) {
    return DISCOVERY_RATE_LIMIT_DEFAULT_DELAY_MS;
  }
  return Math.min(delayMs, DISCOVERY_RATE_LIMIT_MAX_DELAY_MS);
}

function parseRetryAfterDelayMs(retryAfter: string): number {
  const trimmed = retryAfter.trim();
  if (NUMERIC_RETRY_AFTER_PATTERN.test(trimmed)) {
    return Number.parseFloat(trimmed) * 1000;
  }
  const parsedDateMs = Date.parse(trimmed);
  if (!Number.isFinite(parsedDateMs)) {
    return NaN;
  }
  return Math.max(0, parsedDateMs - Date.now());
}

function isDiscoveryRetryableTransportError(error: LivePlexTransportError): boolean {
  return error.code === 'server-unreachable' || error.code === 'timeout';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function readString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function readBoolean(value: unknown): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true';
  }
  return false;
}

function normalizePort(value: unknown): number {
  const parsed =
    typeof value === 'number' ? value : typeof value === 'string' && value.trim().length > 0 ? Number(value.trim()) : 0;
  return Number.isInteger(parsed) && parsed >= MIN_PORT && parsed <= MAX_PORT ? parsed : 0;
}
