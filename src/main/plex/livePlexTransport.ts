import { clearTimeout, setTimeout } from 'node:timers';

import {
  buildPlexAuthRequestHeaders,
  type DesktopPlexAuthTransport,
  type DesktopPlexAuthTransportRequest,
  type DesktopPlexAuthTransportResponse,
  type PlexAuthConfig,
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
  authConfig?: PlexAuthConfig;
  fetch?: typeof globalThis.fetch;
  timeoutMs?: number;
  guideArtworkTimeoutMs?: number;
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

export interface LivePlexGetCollectionItemsRequest extends LivePlexLibraryRequest {
  collectionKey: string;
}

export interface LivePlexGetShowEpisodesRequest extends LivePlexLibraryRequest {
  showKey: string;
}

export interface LivePlexGetPlaylistItemsRequest extends LivePlexLibraryRequest {
  playlistKey: string;
}

export interface LivePlexListCollectionsPageRequest extends LivePlexLibraryRequest {
  sectionId: string;
  offset: number;
  limit: 100;
}

export interface LivePlexListServerPlaylistsPageRequest extends LivePlexLibraryRequest {
  offset: number;
  limit: 100;
}

export interface LivePlexListTagDirectoryPageRequest extends LivePlexLibraryRequest {
  sectionId: string;
  family: 'genre' | 'director' | 'year' | 'studio' | 'actor';
  mediaType: 1 | 2 | 4;
  offset: number;
  limit: 100;
}

export interface LivePlexLibraryTransport {
  listLibrarySections(input: LivePlexLibraryRequest): Promise<PlexResponsePayload>;
  listLibraryItems(input: LivePlexListLibraryItemsRequest): Promise<PlexResponsePayload>;
  searchLibrary(input: LivePlexSearchLibraryRequest): Promise<PlexResponsePayload>;
  getMetadata(input: LivePlexGetMetadataRequest): Promise<PlexResponsePayload>;
  getCollectionItems(input: LivePlexGetCollectionItemsRequest): Promise<PlexResponsePayload>;
  getShowEpisodes(input: LivePlexGetShowEpisodesRequest): Promise<PlexResponsePayload>;
  getPlaylistItems(input: LivePlexGetPlaylistItemsRequest): Promise<PlexResponsePayload>;
  stopTranscodeSession(input: {
    connection: PlexConnection;
    token: string;
    sessionId: string;
    signal?: AbortSignal | null;
  }): Promise<void>;
}

export interface LivePlexChannelBuilderFacetTransport {
  listCollectionsPage(input: LivePlexListCollectionsPageRequest): Promise<PlexResponsePayload>;
  listServerPlaylistsPage(input: LivePlexListServerPlaylistsPageRequest): Promise<PlexResponsePayload>;
  listTagDirectoryPage(input: LivePlexListTagDirectoryPageRequest): Promise<PlexResponsePayload>;
}

export type GuideArtworkMimeType = 'image/jpeg' | 'image/png' | 'image/webp';

export interface LivePlexGuideArtworkRequest extends LivePlexLibraryRequest {
  locator: string;
}

export interface LivePlexGuideArtworkResponse {
  bytes: Uint8Array;
  mimeType: GuideArtworkMimeType;
}

export interface LivePlexGuideArtworkTransport {
  fetchGuideArtwork(input: LivePlexGuideArtworkRequest): Promise<LivePlexGuideArtworkResponse>;
}

const DEFAULT_TIMEOUT_MS = 20_000;
const GUIDE_ARTWORK_TIMEOUT_MS = 5_000;
const GUIDE_ARTWORK_MAX_BYTES = 1_500_000;
const PLEX_TV_ORIGIN = 'https://plex.tv';
export const PLEX_TOKEN_HEADER_NAME = ['X-Plex', 'Token'].join('-');
const GUIDE_ARTWORK_LOCATOR_PATTERN =
  /^\/library\/metadata\/[0-9]{1,20}\/thumb(?:\/[0-9]{1,20})?$/u;

export class LivePlexTransport
  implements
    DesktopPlexAuthTransport,
    DesktopPlexDiscoveryTransport,
    LivePlexLibraryTransport,
    LivePlexChannelBuilderFacetTransport,
    LivePlexGuideArtworkTransport
{
  private readonly authConfig: PlexAuthConfig | undefined;
  private readonly fetchImpl: typeof globalThis.fetch;
  private readonly timeoutMs: number;
  private readonly guideArtworkTimeoutMs: number;
  private readonly nowMs: () => number;
  private readonly discoveryWaitMs: (delayMs: number) => Promise<void>;

  constructor(options: LivePlexTransportOptions = {}) {
    this.authConfig = options.authConfig;
    this.fetchImpl = options.fetch ?? globalThis.fetch;
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.guideArtworkTimeoutMs = options.guideArtworkTimeoutMs ?? GUIDE_ARTWORK_TIMEOUT_MS;
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
      headers: this.buildPlexRequestHeaders(input.token),
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
        headers: this.buildPlexRequestHeaders(input.token),
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

  async listCollectionsPage(
    input: LivePlexListCollectionsPageRequest,
  ): Promise<PlexResponsePayload> {
    const url = new URL(
      `/library/sections/${encodeURIComponent(input.sectionId)}/all`,
      normalizeBaseUri(input.connection.uri),
    );
    url.searchParams.set('type', '18');
    url.searchParams.set('includeGuids', '1');
    url.searchParams.set('includeMeta', '1');
    setContainerWindow(url, input.offset, input.limit);
    return this.fetchPmsUrlPayload(url, input.token, input.signal ?? null);
  }

  async listServerPlaylistsPage(
    input: LivePlexListServerPlaylistsPageRequest,
  ): Promise<PlexResponsePayload> {
    const url = new URL('/playlists', normalizeBaseUri(input.connection.uri));
    setContainerWindow(url, input.offset, input.limit);
    return this.fetchPmsUrlPayload(url, input.token, input.signal ?? null);
  }

  async listTagDirectoryPage(
    input: LivePlexListTagDirectoryPageRequest,
  ): Promise<PlexResponsePayload> {
    const url = new URL(
      `/library/sections/${encodeURIComponent(input.sectionId)}/${input.family}`,
      normalizeBaseUri(input.connection.uri),
    );
    url.searchParams.set('type', String(input.mediaType));
    setContainerWindow(url, input.offset, input.limit);
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

  async getCollectionItems(input: LivePlexGetCollectionItemsRequest): Promise<PlexResponsePayload> {
    return this.fetchPmsPayload(
      input.connection,
      `/library/collections/${encodeURIComponent(input.collectionKey)}/items`,
      input.token,
      input.signal ?? null,
    );
  }

  async getShowEpisodes(input: LivePlexGetShowEpisodesRequest): Promise<PlexResponsePayload> {
    return this.fetchPmsPayload(
      input.connection,
      `/library/metadata/${encodeURIComponent(input.showKey)}/allLeaves`,
      input.token,
      input.signal ?? null,
    );
  }

  async getPlaylistItems(input: LivePlexGetPlaylistItemsRequest): Promise<PlexResponsePayload> {
    return this.fetchPmsPayload(
      input.connection,
      `/library/playlists/${encodeURIComponent(input.playlistKey)}/items`,
      input.token,
      input.signal ?? null,
    );
  }

  async stopTranscodeSession(input: {
    connection: PlexConnection;
    token: string;
    sessionId: string;
    signal?: AbortSignal | null;
  }): Promise<void> {
    const url = new URL('/video/:/transcode/universal/stop', normalizeBaseUri(input.connection.uri));
    url.searchParams.set('session', input.sessionId);
    await this.fetchPmsUrlPayload(url, input.token, input.signal ?? null).catch(() => {
      // Ignore stop failures per plan
    });
  }

  async fetchGuideArtwork(
    input: LivePlexGuideArtworkRequest,
  ): Promise<LivePlexGuideArtworkResponse> {
    const locator = normalizeGuideArtworkLocator(input.locator);
    const url = buildContainedGuideArtworkUrl(input.connection.uri, locator);
    const timeoutController = new AbortController();
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      timeoutController.abort();
    }, this.guideArtworkTimeoutMs);
    const onAbort = () => timeoutController.abort(input.signal?.reason);
    if (input.signal?.aborted) onAbort();
    else input.signal?.addEventListener('abort', onAbort, { once: true });
    try {
      const response = await this.fetchImpl(url, {
        method: 'GET',
        redirect: 'error',
        headers: this.buildPlexRequestHeaders(input.token),
        signal: timeoutController.signal,
      });
      try {
        throwForHttpStatus(response.status);
      } catch (error) {
        await cancelGuideArtworkResponseBody(response);
        throw error;
      }
      let mimeType: GuideArtworkMimeType;
      try {
        mimeType = normalizeGuideArtworkMimeType(response.headers.get('content-type'));
      } catch (error) {
        await cancelGuideArtworkResponseBody(response);
        throw error;
      }
      const contentLength = readContentLength(response.headers.get('content-length'));
      if (contentLength !== null && contentLength > GUIDE_ARTWORK_MAX_BYTES) {
        await cancelGuideArtworkResponseBody(response);
        throw guideArtworkError('parse-error');
      }
      return {
        bytes: await readBoundedGuideArtworkBytes(response, GUIDE_ARTWORK_MAX_BYTES),
        mimeType,
      };
    } catch (error) {
      if (input.signal?.aborted) {
        throw new LivePlexTransportError('aborted', 'Plex artwork request was aborted', undefined, {
          cause: error,
        });
      }
      if (timedOut) {
        throw new LivePlexTransportError('timeout', 'Plex artwork request timed out', undefined, {
          retryable: true,
          cause: error,
        });
      }
      if (error instanceof LivePlexTransportError) throw error;
      throw new LivePlexTransportError(
        'server-unreachable',
        'Plex artwork request failed',
        undefined,
        { retryable: true, cause: error },
      );
    } finally {
      clearTimeout(timeout);
      input.signal?.removeEventListener('abort', onAbort);
    }
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
        headers: this.buildPlexRequestHeaders(token),
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

  private buildPlexRequestHeaders(token?: string): Record<string, string> {
    if (this.authConfig !== undefined) {
      return buildPlexAuthRequestHeaders(this.authConfig, {
        ...(token !== undefined ? { token } : {}),
      });
    }
    return {
      Accept: 'application/json',
      ...(token !== undefined ? { [PLEX_TOKEN_HEADER_NAME]: token } : {}),
    };
  }
}

function setContainerWindow(url: URL, offset: number, limit: number): void {
  url.searchParams.set('X-Plex-Container-Start', String(offset));
  url.searchParams.set('X-Plex-Container-Size', String(limit));
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

export function normalizeBaseUri(uri: string): string {
  return uri.endsWith('/') ? uri : `${uri}/`;
}

export function normalizeGuideArtworkLocator(locator: string): string {
  const characterCodes = Array.from(locator, (character) => character.charCodeAt(0));
  if (
    locator.length < 1 ||
    locator.length > 512 ||
    locator !== locator.trim() ||
    characterCodes.some((code) => code > 0x7f) ||
    characterCodes.some((code) => code <= 0x20 || code === 0x7f) ||
    [...'\\%?#'].some((character) => locator.includes(character)) ||
    !GUIDE_ARTWORK_LOCATOR_PATTERN.test(locator)
  ) {
    throw guideArtworkError('validation');
  }
  const segments = locator.split('/');
  if (segments.some((segment, index) => index > 0 && (segment === '' || segment === '.' || segment === '..'))) {
    throw guideArtworkError('validation');
  }
  return locator;
}

function buildContainedGuideArtworkUrl(connectionUri: string, locator: string): URL {
  try {
    const base = new URL(normalizeBaseUri(connectionUri));
    const url = new URL(locator, base);
    if (
      url.protocol !== base.protocol ||
      url.hostname !== base.hostname ||
      effectivePort(url) !== effectivePort(base) ||
      url.username !== '' ||
      url.password !== '' ||
      url.search !== '' ||
      url.hash !== '' ||
      url.pathname !== locator
    ) {
      throw guideArtworkError('validation');
    }
    return url;
  } catch (error) {
    if (error instanceof LivePlexTransportError) throw error;
    throw guideArtworkError('validation');
  }
}

function effectivePort(url: URL): string {
  if (url.port !== '') return url.port;
  if (url.protocol === 'http:') return '80';
  if (url.protocol === 'https:') return '443';
  return '';
}

function normalizeGuideArtworkMimeType(value: string | null): GuideArtworkMimeType {
  const normalized = value?.split(';', 1)[0]?.trim().toLowerCase();
  if (normalized === 'image/jpeg' || normalized === 'image/png' || normalized === 'image/webp') {
    return normalized;
  }
  throw guideArtworkError('parse-error');
}

function readContentLength(value: string | null): number | null {
  if (value === null || !/^[0-9]+$/u.test(value)) return null;
  const result = Number(value);
  return Number.isSafeInteger(result) ? result : null;
}

async function readBoundedGuideArtworkBytes(
  response: Response,
  maximumBytes: number,
): Promise<Uint8Array> {
  if (response.body === null) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      total += result.value.byteLength;
      if (total > maximumBytes) {
        await reader.cancel();
        throw guideArtworkError('parse-error');
      }
      chunks.push(result.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function cancelGuideArtworkResponseBody(response: Response): Promise<void> {
  if (response.body === null) return;
  try {
    await response.body.cancel();
  } catch {
    // Best-effort network resource release must not replace the fixed transport failure.
  }
}

function guideArtworkError(code: 'validation' | 'parse-error'): LivePlexTransportError {
  return new LivePlexTransportError(
    code === 'validation' ? 'parse-error' : code,
    code === 'validation'
      ? 'Plex artwork locator is invalid'
      : 'Plex artwork response is invalid',
  );
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
