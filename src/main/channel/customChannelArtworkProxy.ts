import { randomBytes } from 'node:crypto';

import type { ArtworkRef } from '../../contracts/artwork.js';

export interface CustomChannelArtworkSource {
  ratingKey: string;
  sourceKey: string;
  kind: ArtworkRef['kind'];
  altText: string;
  createdAtMs: number;
}

export interface CustomChannelArtworkFetchResult {
  contentType: 'image/jpeg' | 'image/png' | 'image/webp';
  bytes: Uint8Array;
  cacheControl: string;
}

export type CustomChannelArtworkFetcher = (
  source: CustomChannelArtworkSource,
  signal: AbortSignal,
) => Promise<{ contentType: string; bytes: Uint8Array }>;

export type CustomChannelArtworkAuthorizer = () => boolean;

export type CustomChannelArtworkReadResult =
  | { ok: true; value: CustomChannelArtworkFetchResult }
  | { ok: false; reason: 'not-found' | 'expired' | 'unauthorized' | 'timeout' | 'invalid-content' | 'too-large' | 'failed' };

export class CustomChannelArtworkProxy {
  private readonly ttlMs: number;
  private readonly maxBytes: number;
  private readonly timeoutMs: number;
  private readonly now: () => number;
  private readonly fetcher: CustomChannelArtworkFetcher;
  private readonly isAuthorized: CustomChannelArtworkAuthorizer;
  private readonly sources = new Map<string, CustomChannelArtworkSource>();
  private readonly cache = new Map<string, CustomChannelArtworkFetchResult>();

  public constructor(options: {
    now: () => number;
    fetcher: CustomChannelArtworkFetcher;
    isAuthorized?: CustomChannelArtworkAuthorizer;
    ttlMs?: number;
    maxBytes?: number;
    timeoutMs?: number;
  }) {
    this.now = options.now;
    this.fetcher = options.fetcher;
    this.isAuthorized = options.isAuthorized ?? (() => true);
    this.ttlMs = options.ttlMs ?? 15 * 60_000;
    this.maxBytes = options.maxBytes ?? 1_500_000;
    this.timeoutMs = options.timeoutMs ?? 5_000;
  }

  public register(source: Omit<CustomChannelArtworkSource, 'createdAtMs'>): ArtworkRef {
    const id = `artwork-${randomBytes(18).toString('base64url')}`;
    const createdAtMs = this.now();
    this.sources.set(id, { ...source, createdAtMs });
    return {
      id,
      kind: source.kind,
      expiresAtMs: createdAtMs + this.ttlMs,
      altText: source.altText,
      status: 'available',
    };
  }

  public placeholder(kind: ArtworkRef['kind'], altText: string): ArtworkRef {
    return {
      id: `artwork-${randomBytes(18).toString('base64url')}`,
      kind,
      expiresAtMs: this.now() + this.ttlMs,
      altText,
      status: 'placeholder',
    };
  }

  public async read(id: string): Promise<CustomChannelArtworkReadResult> {
    if (!this.isAuthorized()) return { ok: false, reason: 'unauthorized' };
    const source = this.sources.get(id);
    if (source === undefined) return { ok: false, reason: 'not-found' };
    if (source.createdAtMs + this.ttlMs <= this.now()) {
      this.sources.delete(id);
      this.cache.delete(id);
      return { ok: false, reason: 'expired' };
    }
    const cached = this.cache.get(id);
    if (cached !== undefined) return { ok: true, value: cached };

    const controller = new AbortController();
    try {
      const fetched = await Promise.race([
        this.fetcher({ ...source }, controller.signal),
        timeoutAfter(this.timeoutMs, controller),
      ]);
      const contentType = normalizeContentType(fetched.contentType);
      if (contentType === null) return { ok: false, reason: 'invalid-content' };
      if (fetched.bytes.byteLength > this.maxBytes) return { ok: false, reason: 'too-large' };
      const value: CustomChannelArtworkFetchResult = {
        contentType,
        bytes: new Uint8Array(fetched.bytes),
        cacheControl: `private, max-age=${String(Math.floor(this.ttlMs / 1000))}`,
      };
      this.cache.set(id, value);
      return { ok: true, value };
    } catch (error) {
      return controller.signal.aborted || error instanceof DOMException && error.name === 'AbortError'
        ? { ok: false, reason: 'timeout' }
        : { ok: false, reason: 'failed' };
    } finally {
      controller.abort();
    }
  }

  public clear(): void {
    this.sources.clear();
    this.cache.clear();
  }
}

function normalizeContentType(value: string): CustomChannelArtworkFetchResult['contentType'] | null {
  const normalized = value.split(';', 1)[0]?.trim().toLowerCase();
  return normalized === 'image/jpeg' || normalized === 'image/png' || normalized === 'image/webp'
    ? normalized
    : null;
}

function timeoutAfter(timeoutMs: number, controller: AbortController): Promise<never> {
  return new Promise((_, reject) => {
    globalThis.setTimeout(() => {
      controller.abort();
      reject(new DOMException('Artwork request timed out.', 'AbortError'));
    }, timeoutMs);
  });
}
