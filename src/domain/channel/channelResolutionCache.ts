import { cloneResolvedContent, cloneResolvedItems } from './channelDomainClone.js';
import { CACHE_TTL_MS } from './constants.js';
import type { ChannelClock } from './interfaces.js';
import type { ResolvedChannelContent, ResolvedContentItem } from './types.js';

export class ChannelResolutionCache {
  private readonly resolvedContent = new Map<string, ResolvedChannelContent>();
  private readonly clock: ChannelClock;

  public constructor(clock: ChannelClock) {
    this.clock = clock;
  }

  public get(channelId: string): ResolvedChannelContent | null {
    const content = this.resolvedContent.get(channelId);
    return content ? cloneResolvedContent(content) : null;
  }

  public set(content: ResolvedChannelContent): void {
    this.resolvedContent.set(content.channelId, cloneResolvedContent(content));
  }

  public delete(channelId: string): void {
    this.resolvedContent.delete(channelId);
  }

  public clear(): void {
    this.resolvedContent.clear();
  }

  public isFresh(channelId: string): boolean {
    const cached = this.getRaw(channelId);
    return cached !== null && !this.isStale(cached);
  }

  public isStale(content: ResolvedChannelContent): boolean {
    return content.isStale === true || this.clock.now() - content.resolvedAt > CACHE_TTL_MS;
  }

  public cloneItems(items: ReadonlyArray<ResolvedContentItem>): ResolvedContentItem[] {
    return cloneResolvedItems(items);
  }

  public cloneContent(
    content: ResolvedChannelContent,
    overrides?: Partial<Pick<ResolvedChannelContent, 'fromCache' | 'isStale' | 'cacheReason'>>,
  ): ResolvedChannelContent {
    return cloneResolvedContent(content, overrides);
  }

  private getRaw(channelId: string): ResolvedChannelContent | null {
    return this.resolvedContent.get(channelId) ?? null;
  }
}
