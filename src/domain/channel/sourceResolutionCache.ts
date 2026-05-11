import { cloneResolvedItem, cloneResolvedItems } from './channelDomainClone.js';
import { SOURCE_CACHE_MAX_ENTRIES, SOURCE_CACHE_TTL_MS } from './constants.js';
import type { ChannelClock } from './interfaces.js';
import type { ChannelContentSource, ResolvedContentItem } from './types.js';

type SourceCacheEntry = {
  items: ResolvedContentItem[];
  cachedAt: number;
  epoch: number;
  generation: number;
};

type SourceInFlightEntry = {
  promise: Promise<ResolvedContentItem[]>;
  epoch: number;
  generation: number;
};

type ResolveSourceUncached = (
  source: ChannelContentSource,
) => Promise<ResolvedContentItem[]>;

export class SourceResolutionCache {
  private cacheEpoch = 0;
  private readonly sourceCacheGenerationByKey = new Map<string, number>();
  private readonly sourceCache = new Map<string, SourceCacheEntry>();
  private readonly sourceInFlight = new Map<string, SourceInFlightEntry>();
  private readonly parentKeysByChildKey = new Map<string, Set<string>>();
  private readonly childKeysByParentKey = new Map<string, Set<string>>();
  private readonly clock: ChannelClock;

  public constructor(clock: ChannelClock) {
    this.clock = clock;
  }

  public clear(): void {
    this.cacheEpoch += 1;
    this.sourceCache.clear();
    this.sourceCacheGenerationByKey.clear();
    this.parentKeysByChildKey.clear();
    this.childKeysByParentKey.clear();
    this.sourceInFlight.clear();
  }

  public invalidate(source: ChannelContentSource): void {
    const invalidatedKeys = new Set<string>();
    this.invalidateSource(source, invalidatedKeys);
  }

  public async resolve(
    source: ChannelContentSource,
    resolveUncached: ResolveSourceUncached,
  ): Promise<ResolvedContentItem[]> {
    const cacheKey = this.buildKey(source);
    const epoch = this.cacheEpoch;
    const generation = this.getSourceCacheGeneration(cacheKey);
    const cached = this.getCachedSourceItems(cacheKey);
    if (cached) {
      return cached;
    }

    const inFlight = this.sourceInFlight.get(cacheKey);
    if (inFlight && inFlight.epoch === epoch && inFlight.generation === generation) {
      const items = await inFlight.promise;
      this.assertCurrentScope(cacheKey, {
        epoch: inFlight.epoch,
        generation: inFlight.generation,
      });
      return cloneResolvedItems(items);
    }
    if (inFlight) {
      this.sourceInFlight.delete(cacheKey);
    }

    const resolvePromise = resolveUncached(source)
      .then((items) => {
        this.setCachedSourceItems(cacheKey, source, items, { epoch, generation });
        return items;
      })
      .finally(() => {
        const current = this.sourceInFlight.get(cacheKey);
        if (current?.promise === resolvePromise) {
          this.sourceInFlight.delete(cacheKey);
        }
      });

    this.sourceInFlight.set(cacheKey, { promise: resolvePromise, epoch, generation });
    const items = await resolvePromise;
    this.assertCurrentScope(cacheKey, { epoch, generation });
    return cloneResolvedItems(items);
  }

  public buildKey(source: ChannelContentSource): string {
    return this.stableSerialize(source);
  }

  public cloneItems(items: ReadonlyArray<ResolvedContentItem>): ResolvedContentItem[] {
    return cloneResolvedItems(items);
  }

  public cloneItem(item: ResolvedContentItem, scheduledIndex = item.scheduledIndex): ResolvedContentItem {
    return cloneResolvedItem(item, scheduledIndex);
  }

  private getSourceCacheGeneration(key: string): number {
    return this.sourceCacheGenerationByKey.get(key) ?? 0;
  }

  private bumpSourceCacheGeneration(key: string): number {
    const next = (this.sourceCacheGenerationByKey.get(key) ?? 0) + 1;
    this.sourceCacheGenerationByKey.set(key, next);
    return next;
  }

  private invalidateSourceKey(key: string, invalidatedKeys: Set<string>): void {
    if (invalidatedKeys.has(key)) {
      return;
    }
    invalidatedKeys.add(key);

    const parentKeys = [...(this.parentKeysByChildKey.get(key) ?? [])];
    this.bumpSourceCacheGeneration(key);
    this.sourceCache.delete(key);
    this.unregisterParentDependencies(key);
    this.sourceInFlight.delete(key);

    for (const parentKey of parentKeys) {
      this.invalidateSourceKey(parentKey, invalidatedKeys);
    }
  }

  private invalidateSource(source: ChannelContentSource, invalidatedKeys: Set<string>): void {
    this.invalidateSourceKey(this.buildKey(source), invalidatedKeys);

    if (source.type !== 'mixed') {
      return;
    }
    for (const subSource of source.sources) {
      this.invalidateSource(subSource, invalidatedKeys);
    }
  }

  private registerParentDependencies(parentKey: string, childKeys: string[]): void {
    this.unregisterParentDependencies(parentKey);
    if (childKeys.length === 0) return;

    const uniqueChildKeys = new Set(childKeys);
    this.childKeysByParentKey.set(parentKey, uniqueChildKeys);
    for (const childKey of uniqueChildKeys) {
      const parentKeys = this.parentKeysByChildKey.get(childKey) ?? new Set<string>();
      parentKeys.add(parentKey);
      this.parentKeysByChildKey.set(childKey, parentKeys);
    }
  }

  private unregisterParentDependencies(parentKey: string): void {
    const childKeys = this.childKeysByParentKey.get(parentKey);
    if (!childKeys) return;

    for (const childKey of childKeys) {
      const parentKeys = this.parentKeysByChildKey.get(childKey);
      if (!parentKeys) continue;
      parentKeys.delete(parentKey);
      if (parentKeys.size === 0) {
        this.parentKeysByChildKey.delete(childKey);
      }
    }
    this.childKeysByParentKey.delete(parentKey);
  }

  private stableSerialize(value: unknown, seen = new WeakSet<object>()): string {
    if (value === undefined) return JSON.stringify(null);
    if (value === null) return JSON.stringify(value);

    const valueType = typeof value;
    if (valueType === 'string' || valueType === 'boolean') return JSON.stringify(value);
    if (valueType === 'number') {
      if (!Number.isFinite(value)) {
        throw new Error('Unsupported content source cache key value: non-finite number');
      }
      return JSON.stringify(value);
    }
    if (valueType === 'function' || valueType === 'bigint' || valueType === 'symbol') {
      throw new Error(`Unsupported content source cache key value type: ${valueType}`);
    }

    const objectValue = value as object;
    if (seen.has(objectValue)) {
      throw new Error('Cannot build content source cache key for circular source data');
    }

    seen.add(objectValue);
    try {
      if (Array.isArray(value)) {
        return `[${value.map((entry) => this.stableSerialize(entry, seen)).join(',')}]`;
      }
      const entries = Object.entries(value as Record<string, unknown>)
        .filter(([, entry]) => entry !== undefined)
        .sort(([left], [right]) => left.localeCompare(right));
      return `{${entries
        .map(([key, entry]) => `${JSON.stringify(key)}:${this.stableSerialize(entry, seen)}`)
        .join(',')}}`;
    } finally {
      seen.delete(objectValue);
    }
  }

  private buildDescendantSourceKeys(source: ChannelContentSource): string[] {
    if (source.type !== 'mixed') {
      return [];
    }

    const childKeys: string[] = [];
    const pending = [...source.sources];
    for (let index = 0; index < pending.length; index += 1) {
      const child = pending[index];
      if (!child) continue;
      childKeys.push(this.buildKey(child));
      if (child.type === 'mixed') {
        pending.push(...child.sources);
      }
    }
    return childKeys;
  }

  private getCachedSourceItems(key: string): ResolvedContentItem[] | null {
    const cached = this.sourceCache.get(key);
    if (!cached) return null;

    if (cached.epoch !== this.cacheEpoch || cached.generation !== this.getSourceCacheGeneration(key)) {
      this.sourceCache.delete(key);
      this.unregisterParentDependencies(key);
      return null;
    }
    if (this.clock.now() - cached.cachedAt > SOURCE_CACHE_TTL_MS) {
      this.sourceCache.delete(key);
      this.unregisterParentDependencies(key);
      return null;
    }

    this.sourceCache.delete(key);
    this.sourceCache.set(key, cached);
    return cloneResolvedItems(cached.items);
  }

  private setCachedSourceItems(
    key: string,
    source: ChannelContentSource,
    items: ResolvedContentItem[],
    scope: { epoch: number; generation: number },
  ): void {
    if (scope.epoch !== this.cacheEpoch) return;
    if (scope.generation !== this.getSourceCacheGeneration(key)) return;

    this.sourceCache.delete(key);
    this.unregisterParentDependencies(key);
    this.sourceCache.set(key, {
      items: cloneResolvedItems(items),
      cachedAt: this.clock.now(),
      epoch: scope.epoch,
      generation: scope.generation,
    });
    if (source.type === 'mixed') {
      this.registerParentDependencies(key, this.buildDescendantSourceKeys(source));
    }

    while (this.sourceCache.size > SOURCE_CACHE_MAX_ENTRIES) {
      const oldest = this.sourceCache.keys().next().value;
      if (oldest === undefined) break;
      this.sourceCache.delete(oldest);
      this.unregisterParentDependencies(oldest);
    }
  }

  private assertCurrentScope(key: string, scope: { epoch: number; generation: number }): void {
    if (scope.epoch !== this.cacheEpoch || scope.generation !== this.getSourceCacheGeneration(key)) {
      throw new Error('Source resolution invalidated');
    }
  }
}
