import { randomBytes } from 'node:crypto';

import type { ArtworkRef } from '../../contracts/artwork.js';
import { ARTWORK_REF_ID_PATTERN } from '../../contracts/artwork.js';
import type {
  GuideArtworkReadySession,
  GuideArtworkSessionGenerationOwner,
} from '../plex/guideArtworkSessionGenerationOwner.js';
import {
  normalizeGuideArtworkLocator,
  type GuideArtworkMimeType,
  type LivePlexGuideArtworkTransport,
} from '../plex/livePlexTransport.js';

const ARTWORK_REF_TTL_MS = 15 * 60 * 1_000;
const MAX_LIVE_REFS = 6_000;
const MAX_CACHE_ENTRIES = 32;
const MAX_CACHE_BYTES = 24 * 1024 * 1024;
const MAX_CONCURRENT_FETCHES = 4;

type GuideArtworkRole = 'poster' | 'background';

type Authorization = {
  readonly refId: string;
  readonly identity: string;
  readonly locator: string;
  expiresAtMs: number;
  readonly session: GuideArtworkReadySession;
};

export type GuideArtworkDelivery = Readonly<{
  bytes: Uint8Array;
  mimeType: GuideArtworkMimeType;
}>;

type CacheEntry = GuideArtworkDelivery & Readonly<{ size: number }>;

type QueueEntry = {
  authorization: Authorization;
  controller: AbortController;
  resolve(value: GuideArtworkDelivery | null): void;
};

export class GuideArtworkOwner {
  private readonly authorizations = new Map<string, Authorization>();
  private readonly authorizationIdsByIdentity = new Map<string, string>();
  private readonly cache = new Map<string, CacheEntry>();
  private readonly pending = new Map<string, Promise<GuideArtworkDelivery | null>>();
  private readonly queue: QueueEntry[] = [];
  private readonly activeControllers = new Set<AbortController>();
  private readonly unsubscribe: () => void;
  private cacheBytes = 0;
  private activeFetches = 0;
  private disposed = false;

  public constructor(
    private readonly sessionOwner: GuideArtworkSessionGenerationOwner,
    private readonly transport: LivePlexGuideArtworkTransport,
    private readonly nowMs: () => number = Date.now,
    private readonly createRefId: () => string = () =>
      `artwork-${randomBytes(18).toString('base64url')}`,
  ) {
    this.unsubscribe = sessionOwner.subscribe(() => this.invalidateAll());
  }

  public createRef(input: Readonly<{
    role: GuideArtworkRole;
    locator: string;
    altText: string;
    lineupRevision: number;
  }>): ArtworkRef | null {
    if (this.disposed) return null;
    let locator: string;
    try {
      locator = normalizeGuideArtworkLocator(input.locator);
    } catch {
      return null;
    }
    if (!locatorMatchesRole(locator, input.role)) return null;
    const session = this.sessionOwner.captureCurrent(input.lineupRevision);
    if (session === null) return null;
    const identity = authorizationIdentity(session, input.role, locator);
    const existingRefId = this.authorizationIdsByIdentity.get(identity);
    if (existingRefId !== undefined) {
      const existing = this.readCurrentAuthorization(existingRefId);
      if (existing !== null) {
        existing.expiresAtMs = this.nowMs() + ARTWORK_REF_TTL_MS;
        return projectRef(existing, input.role, input.altText);
      }
    }
    if (this.authorizations.size >= MAX_LIVE_REFS) {
      this.reclaimExpiredAuthorizations();
      if (this.authorizations.size >= MAX_LIVE_REFS) return null;
    }
    let refId: string | null = null;
    for (let attempt = 0; attempt < 100; attempt += 1) {
      const candidate = this.createRefId();
      if (ARTWORK_REF_ID_PATTERN.test(candidate) && !this.authorizations.has(candidate)) {
        refId = candidate;
        break;
      }
    }
    if (refId === null) return null;
    const expiresAtMs = this.nowMs() + ARTWORK_REF_TTL_MS;
    const authorization: Authorization = Object.seal({
      refId,
      identity,
      locator,
      expiresAtMs,
      session,
    });
    this.authorizations.set(refId, authorization);
    this.authorizationIdsByIdentity.set(identity, refId);
    return projectRef(authorization, input.role, input.altText);
  }

  public get(refId: string): Promise<GuideArtworkDelivery | null> {
    const authorization = this.readCurrentAuthorization(refId);
    if (authorization === null) return Promise.resolve(null);
    if (!this.sessionOwner.isCurrent(authorization.session.generationId)) {
      this.revoke(refId);
      return Promise.resolve(null);
    }
    const existing = this.pending.get(refId);
    if (existing !== undefined) return existing;
    const controller = new AbortController();
    const promise = new Promise<GuideArtworkDelivery | null>((resolve) => {
      this.queue.push({ authorization, controller, resolve });
      this.pumpQueue();
    }).finally(() => {
      this.pending.delete(refId);
    });
    this.pending.set(refId, promise);
    return promise;
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unsubscribe();
    this.invalidateAll();
  }

  private pumpQueue(): void {
    while (!this.disposed && this.activeFetches < MAX_CONCURRENT_FETCHES) {
      const entry = this.queue.shift();
      if (entry === undefined) return;
      if (!this.isAuthorizationCurrent(entry.authorization)) {
        entry.resolve(null);
        continue;
      }
      this.activeFetches += 1;
      this.activeControllers.add(entry.controller);
      void this.performFetch(entry)
        .then(entry.resolve, () => entry.resolve(null))
        .finally(() => {
          this.activeFetches -= 1;
          this.activeControllers.delete(entry.controller);
          this.pumpQueue();
        });
    }
  }

  private async performFetch(entry: QueueEntry): Promise<GuideArtworkDelivery | null> {
    const { authorization } = entry;
    if (!this.isAuthorizationCurrent(authorization)) return null;
    const cached = this.cache.get(authorization.refId);
    if (cached !== undefined) {
      if (!this.isAuthorizationCurrent(authorization)) return null;
      this.touchCache(authorization.refId, cached);
      return { bytes: cached.bytes, mimeType: cached.mimeType };
    }
    const response = await this.transport.fetchGuideArtwork({
      locator: authorization.locator,
      connection: authorization.session.connection,
      token: authorization.session.token,
      signal: entry.controller.signal,
    });
    if (!this.isAuthorizationCurrent(authorization)) return null;
    const stored = Object.freeze({
      bytes: response.bytes,
      mimeType: response.mimeType,
      size: response.bytes.byteLength,
    });
    this.insertCache(authorization.refId, stored);
    if (!this.isAuthorizationCurrent(authorization)) {
      this.revoke(authorization.refId);
      return null;
    }
    return { bytes: stored.bytes, mimeType: stored.mimeType };
  }

  private readCurrentAuthorization(refId: string): Authorization | null {
    if (this.disposed || !ARTWORK_REF_ID_PATTERN.test(refId)) return null;
    const authorization = this.authorizations.get(refId);
    if (authorization === undefined) return null;
    if (authorization.expiresAtMs <= this.nowMs()) {
      this.revoke(refId);
      return null;
    }
    return authorization;
  }

  private isAuthorizationCurrent(authorization: Authorization): boolean {
    return !this.disposed &&
      this.authorizations.get(authorization.refId) === authorization &&
      authorization.expiresAtMs > this.nowMs() &&
      this.sessionOwner.isCurrent(authorization.session.generationId);
  }

  private insertCache(refId: string, entry: CacheEntry): void {
    const previous = this.cache.get(refId);
    if (previous !== undefined) this.cacheBytes -= previous.size;
    this.cache.delete(refId);
    this.cache.set(refId, entry);
    this.cacheBytes += entry.size;
    while (this.cache.size > MAX_CACHE_ENTRIES || this.cacheBytes > MAX_CACHE_BYTES) {
      const oldestRefId = this.cache.keys().next().value as string | undefined;
      if (oldestRefId === undefined) break;
      this.revoke(oldestRefId);
    }
  }

  private touchCache(refId: string, entry: CacheEntry): void {
    this.cache.delete(refId);
    this.cache.set(refId, entry);
  }

  private revoke(refId: string): void {
    const authorization = this.authorizations.get(refId);
    this.authorizations.delete(refId);
    if (authorization !== undefined && this.authorizationIdsByIdentity.get(authorization.identity) === refId) {
      this.authorizationIdsByIdentity.delete(authorization.identity);
    }
    const cached = this.cache.get(refId);
    if (cached !== undefined) {
      this.cache.delete(refId);
      this.cacheBytes -= cached.size;
    }
  }

  private reclaimExpiredAuthorizations(): void {
    const nowMs = this.nowMs();
    for (const [refId, authorization] of this.authorizations) {
      if (authorization.expiresAtMs <= nowMs) this.revoke(refId);
    }
  }

  private invalidateAll(): void {
    this.authorizations.clear();
    this.authorizationIdsByIdentity.clear();
    this.cache.clear();
    this.cacheBytes = 0;
    for (const entry of this.queue.splice(0)) {
      entry.controller.abort();
      entry.resolve(null);
    }
    for (const controller of this.activeControllers) controller.abort();
  }
}

function locatorMatchesRole(locator: string, role: GuideArtworkRole): boolean {
  const family = locator.split('/')[4];
  return (role === 'poster' && family === 'thumb') ||
    (role === 'background' && family === 'art');
}

function authorizationIdentity(
  session: GuideArtworkReadySession,
  role: GuideArtworkRole,
  locator: string,
): string {
  return `${String(session.generationId)}\u0000${String(session.lineupRevision)}\u0000${role}\u0000${locator}`;
}

function projectRef(
  authorization: Authorization,
  role: GuideArtworkRole,
  altText: string,
): ArtworkRef {
  return Object.freeze({
    id: authorization.refId,
    kind: role,
    expiresAtMs: authorization.expiresAtMs,
    altText: clampDisplay(altText, 160),
    status: 'available',
  });
}

function clampDisplay(value: string, maximum: number): string {
  return value.replace(/[<>]/gu, '').slice(0, maximum);
}
