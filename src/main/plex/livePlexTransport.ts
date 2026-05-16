import { clearTimeout, setTimeout } from 'node:timers';

import {
  buildPlexAuthRequestHeaders,
  type DesktopPlexAuthTransport,
  type DesktopPlexAuthTransportRequest,
  type DesktopPlexAuthTransportResponse,
  type PlexResponsePayload,
  readPlexResponse,
} from './auth/index.js';
import type {
  DesktopPlexConnectionProbeTransportResult,
  DesktopPlexDiscoveryTransport,
} from './discovery/index.js';
import {
  discoverPlexResourcesWithRequestPolicy,
  type DiscoveryTextResponse,
} from './discovery/livePlexDiscoveryRequestPolicy.js';
import type { PlexConnection, PlexServer } from './discovery/types.js';
import { LivePlexTransportError } from './livePlexTransportError.js';

export { LivePlexTransportError } from './livePlexTransportError.js';
export type { LivePlexTransportErrorCode } from './livePlexTransportError.js';

export interface LivePlexTransportOptions {
  fetch?: typeof globalThis.fetch;
  timeoutMs?: number;
  nowMs?: () => number;
  discoveryWaitMs?: (delayMs: number) => Promise<void>;
}

export interface LivePlexLibraryRequest {
  connection: PlexConnection;
  token: string;
  signal?: AbortSignal | null;
}

export interface LivePlexListLibraryItemsRequest extends LivePlexLibraryRequest {
  sectionId: string;
  offset: number;
  limit: number;
  sort?: string;
  filter?: Readonly<Record<string, string | number>>;
  includeCollections?: boolean;
}

export interface LivePlexSearchLibraryRequest extends LivePlexLibraryRequest {
  query: string;
  sectionId?: string | null;
  limit: number;
  types?: readonly string[];
}

export interface LivePlexGetMetadataRequest extends LivePlexLibraryRequest {
  ratingKey: string;
}

export interface LivePlexLibraryTransport {
  listLibrarySections(input: LivePlexLibraryRequest): Promise<PlexResponsePayload>;
  listLibraryItems(input: LivePlexListLibraryItemsRequest): Promise<PlexResponsePayload>;
  searchLibrary(input: LivePlexSearchLibraryRequest): Promise<PlexResponsePayload>;
  getMetadata(input: LivePlexGetMetadataRequest): Promise<PlexResponsePayload>;
}

const DEFAULT_TIMEOUT_MS = 20_000;
const PLEX_TV_ORIGIN = 'https://plex.tv';
const PLEX_TOKEN_HEADER_NAME = ['X-Plex', 'Token'].join('-');

export class LivePlexTransport
  implements DesktopPlexAuthTransport, DesktopPlexDiscoveryTransport, LivePlexLibraryTransport
{
  private readonly fetchImpl: typeof globalThis.fetch;
  private readonly timeoutMs: number;
  private readonly nowMs: () => number;
  private readonly discoveryWaitMs: (delayMs: number) => Promise<void>;

  constructor(options: LivePlexTransportOptions = {}) {
    this.fetchImpl = options.fetch ?? globalThis.fetch;
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.nowMs = options.nowMs ?? Date.now;
    this.discoveryWaitMs = options.discoveryWaitMs ?? defaultWaitMs;
  }

  async request(input: DesktopPlexAuthTransportRequest): Promise<DesktopPlexAuthTransportResponse> {
    const { url, init } = this.buildAuthRequest(input);
    const response = await this.fetchNormalized(url, init, input.signal ?? null);
    return {
      status: response.status,
      payload: response.payload,
    };
  }

  async discoverResources(input: { token?: string; signal?: AbortSignal | null }): Promise<unknown> {
    return discoverPlexResourcesWithRequestPolicy({
      ...(input.token !== undefined ? { token: input.token } : {}),
      signal: input.signal ?? null,
      fetchText: ({ url, init, signal }) => this.fetchTextNormalized(url, init, signal),
      waitMs: this.discoveryWaitMs,
    });
  }

  async probeConnection(input: {
    server: PlexServer;
    connection: PlexConnection;
    token?: string;
    signal?: AbortSignal | null;
  }): Promise<DesktopPlexConnectionProbeTransportResult> {
    const startedAtMs = this.nowMs();
    const response = await this.fetchNormalized(
      new URL('/identity', normalizeBaseUri(input.connection.uri)),
      {
        method: 'GET',
        headers: {
          Accept: 'application/json',
          ...(input.token !== undefined ? { [PLEX_TOKEN_HEADER_NAME]: input.token } : {}),
        },
      },
      input.signal ?? null,
    );
    if (response.status === 401) {
      return { outcome: 'auth-required' };
    }
    if (response.status === 403) {
      return { outcome: 'access-denied' };
    }
    if (response.status < 200 || response.status >= 300) {
      return { outcome: 'unreachable' };
    }
    return { outcome: 'reachable', latencyMs: this.nowMs() - startedAtMs };
  }

  async listLibrarySections(input: LivePlexLibraryRequest): Promise<PlexResponsePayload> {
    return this.fetchPmsPayload(input.connection, '/library/sections', input.token, input.signal ?? null);
  }

  async listLibraryItems(input: LivePlexListLibraryItemsRequest): Promise<PlexResponsePayload> {
    const url = new URL(
      `/library/sections/${encodeURIComponent(input.sectionId)}/all`,
      normalizeBaseUri(input.connection.uri),
    );
    url.searchParams.set('X-Plex-Container-Start', String(input.offset));
    url.searchParams.set('X-Plex-Container-Size', String(input.limit));
    if (input.sort !== undefined) {
      url.searchParams.set('sort', input.sort);
    }
    if (input.filter !== undefined) {
      for (const [key, value] of Object.entries(input.filter)) {
        url.searchParams.set(key, String(value));
      }
    }
    if (input.includeCollections === true) {
      url.searchParams.set('includeCollections', '1');
    }
    return this.fetchPmsUrlPayload(url, input.token, input.signal ?? null);
  }

  async searchLibrary(input: LivePlexSearchLibraryRequest): Promise<PlexResponsePayload> {
    const url = new URL('/hubs/search', normalizeBaseUri(input.connection.uri));
    url.searchParams.set('query', input.query);
    url.searchParams.set('limit', String(input.limit));
    if (input.sectionId !== undefined && input.sectionId !== null) {
      url.searchParams.set('sectionId', input.sectionId);
    }
    if (input.types !== undefined && input.types.length > 0) {
      url.searchParams.set('types', input.types.join(','));
    }
    return this.fetchPmsUrlPayload(url, input.token, input.signal ?? null);
  }

  async getMetadata(input: LivePlexGetMetadataRequest): Promise<PlexResponsePayload> {
    return this.fetchPmsPayload(
      input.connection,
      `/library/metadata/${encodeURIComponent(input.ratingKey)}`,
      input.token,
      input.signal ?? null,
    );
  }

  private buildAuthRequest(input: DesktopPlexAuthTransportRequest): {
    url: URL;
    init: RequestInit;
  } {
    const headers = buildPlexAuthRequestHeaders(input.config, {
      ...(input.token !== undefined ? { token: input.token } : {}),
    });
    switch (input.action) {
      case 'request-pin': {
        const url = new URL('/api/v2/pins', PLEX_TV_ORIGIN);
        return { url, init: { method: 'POST', headers } };
      }
      case 'check-pin-status':
        return {
          url: new URL(`/api/v2/pins/${encodeURIComponent(String(input.pinId ?? ''))}`, PLEX_TV_ORIGIN),
          init: { method: 'GET', headers },
        };
      case 'cancel-pin':
        return {
          url: new URL(`/api/v2/pins/${encodeURIComponent(String(input.pinId ?? ''))}`, PLEX_TV_ORIGIN),
          init: { method: 'DELETE', headers },
        };
      case 'validate-token':
        return {
          url: new URL('/users/account.json', PLEX_TV_ORIGIN),
          init: { method: 'GET', headers },
        };
      case 'get-home-users':
        return {
          url: new URL(homeUsersPath(input.homeEndpointVersion), PLEX_TV_ORIGIN),
          init: { method: 'GET', headers },
        };
      case 'switch-home-user': {
        const url = new URL(
          `${homeUsersPath(input.homeEndpointVersion)}/${encodeURIComponent(input.userId ?? '')}/switch`,
          PLEX_TV_ORIGIN,
        );
        const pin = input.pin?.trim();
        if (pin) {
          url.searchParams.set('pin', pin);
        }
        return { url, init: { method: 'POST', headers } };
      }
    }
  }

  private async fetchPmsPayload(
    connection: PlexConnection,
    pathname: string,
    token: string,
    signal: AbortSignal | null,
  ): Promise<PlexResponsePayload> {
    return this.fetchPmsUrlPayload(new URL(pathname, normalizeBaseUri(connection.uri)), token, signal);
  }

  private async fetchPmsUrlPayload(
    url: URL,
    token: string,
    signal: AbortSignal | null,
  ): Promise<PlexResponsePayload> {
    const response = await this.fetchNormalized(
      url,
      {
        method: 'GET',
        headers: {
          Accept: 'application/json',
          [PLEX_TOKEN_HEADER_NAME]: token,
        },
      },
      signal,
    );
    throwForHttpStatus(response.status);
    return response.payload;
  }

  private async fetchNormalized(
    url: URL,
    init: RequestInit,
    signal: AbortSignal | null,
  ): Promise<{ status: number; payload: PlexResponsePayload }> {
    const timeoutController = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      timeoutController.abort();
    }, this.timeoutMs);
    const onAbort = () => timeoutController.abort();
    if (signal?.aborted) {
      timeoutController.abort();
    } else {
      signal?.addEventListener('abort', onAbort, { once: true });
    }

    try {
      const response = await this.fetchImpl(url, {
        ...init,
        signal: timeoutController.signal,
      });
      const payload = await readPlexResponse(response);
      return { status: response.status, payload };
    } catch (error) {
      if (signal?.aborted) {
        throw new LivePlexTransportError('aborted', 'Plex request was aborted', undefined, {
          cause: error,
        });
      }
      if (timedOut) {
        throw new LivePlexTransportError('timeout', 'Plex request timed out', undefined, {
          retryable: true,
          cause: error,
        });
      }
      if (error instanceof LivePlexTransportError) {
        throw error;
      }
      if (isPlexParseError(error)) {
        throw new LivePlexTransportError('parse-error', 'Plex response could not be parsed', undefined, {
          cause: error,
        });
      }
      throw new LivePlexTransportError('server-unreachable', 'Plex service is unreachable', undefined, {
        retryable: true,
        cause: error,
      });
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
    }
  }

  private async fetchTextNormalized(
    url: URL,
    init: RequestInit,
    signal: AbortSignal | null,
  ): Promise<DiscoveryTextResponse> {
    const timeoutController = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      timeoutController.abort();
    }, this.timeoutMs);
    const onAbort = () => timeoutController.abort();
    if (signal?.aborted) {
      timeoutController.abort();
    } else {
      signal?.addEventListener('abort', onAbort, { once: true });
    }

    try {
      const response = await this.fetchImpl(url, {
        ...init,
        signal: timeoutController.signal,
      });
      let text: string;
      try {
        text = await response.text();
      } catch (error) {
        if (signal?.aborted) {
          throw new LivePlexTransportError('aborted', 'Plex request was aborted', undefined, {
            cause: error,
          });
        }
        if (timedOut) {
          throw new LivePlexTransportError('timeout', 'Plex request timed out', undefined, {
            retryable: true,
            cause: error,
          });
        }
        throw new LivePlexTransportError('parse-error', 'Plex response could not be parsed', response.status, {
          cause: error,
        });
      }
      return { status: response.status, headers: response.headers, text };
    } catch (error) {
      if (signal?.aborted) {
        throw new LivePlexTransportError('aborted', 'Plex request was aborted', undefined, {
          cause: error,
        });
      }
      if (timedOut) {
        throw new LivePlexTransportError('timeout', 'Plex request timed out', undefined, {
          retryable: true,
          cause: error,
        });
      }
      if (error instanceof LivePlexTransportError) {
        throw error;
      }
      throw new LivePlexTransportError('server-unreachable', 'Plex service is unreachable', undefined, {
        retryable: true,
        cause: error,
      });
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
    }
  }
}

function throwForHttpStatus(status: number): void {
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

async function defaultWaitMs(delayMs: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, delayMs));
}

function normalizeBaseUri(uri: string): string {
  return uri.endsWith('/') ? uri : `${uri}/`;
}

function homeUsersPath(endpointVersion: 'v2' | 'v1' | undefined): string {
  return endpointVersion === 'v1' ? '/api/home/users' : '/api/v2/home/users';
}

function isPlexParseError(error: unknown): boolean {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof error.code === 'string' &&
    error.code === 'parse-error'
  );
}
