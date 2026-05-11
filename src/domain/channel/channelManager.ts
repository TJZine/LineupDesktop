import { ChannelAuthoringService, omitUndefinedChannelUpdates } from './channelAuthoringService.js';
import { isValidContentSource } from './channelContentSourceValidator.js';
import { cloneChannelForOwnership } from './channelDomainClone.js';
import { ChannelError, getChannelErrorCode } from './channelError.js';
import { ChannelImportExportService } from './channelImportExportService.js';
import { ChannelResolutionCache } from './channelResolutionCache.js';
import { ChannelRetryScheduler } from './channelRetryScheduler.js';
import { ContentResolver } from './contentResolver.js';
import { CHANNEL_ERROR_MESSAGES } from './constants.js';
import type {
  ChannelCreateOptions,
  ChannelLogger,
  ChannelManagerConfig,
  ChannelResolveOptions,
  DomainDisposable,
  IChannelManager,
} from './interfaces.js';
import type {
  ChannelConfig,
  ChannelContentSource,
  ChannelCreateInput,
  ChannelManagerEventMap,
  ChannelManagerState,
  ChannelUpdateInput,
  ImportResult,
  ResolvedChannelContent,
  ResolvedContentItem,
  StoredChannelData,
} from './types.js';

const NETWORK_ERROR_CODES = new Set([
  'NETWORK_TIMEOUT',
  'NETWORK_OFFLINE',
  'SERVER_UNREACHABLE',
  'NETWORK_UNAVAILABLE',
]);

const RESOLUTION_AFFECTING_UPDATE_FIELDS: readonly (keyof ChannelUpdateInput)[] = [
  'contentSource',
  'contentFilters',
  'sortOrder',
  'playbackMode',
  'blockSize',
  'minEpisodeRunTimeMs',
  'maxEpisodeRunTimeMs',
  'shuffleSeed',
];

const NOOP_LOGGER: ChannelLogger = {
  warn: () => undefined,
  error: () => undefined,
};

class ChannelEventOwner {
  private readonly handlers: {
    [K in keyof ChannelManagerEventMap]: Array<(payload: ChannelManagerEventMap[K]) => void>;
  } = {
    channelCreated: [],
    channelUpdated: [],
    channelDeleted: [],
    channelSwitch: [],
    contentResolved: [],
    persistenceWarning: [],
  };

  public on<K extends keyof ChannelManagerEventMap>(
    event: K,
    handler: (payload: ChannelManagerEventMap[K]) => void,
  ): DomainDisposable {
    this.handlers[event].push(handler);
    return {
      dispose: () => this.off(event, handler),
    };
  }

  public emit<K extends keyof ChannelManagerEventMap>(event: K, payload: ChannelManagerEventMap[K]): void {
    for (const handler of [...this.handlers[event]]) {
      handler(payload);
    }
  }

  public clear(): void {
    this.handlers.channelCreated.length = 0;
    this.handlers.channelUpdated.length = 0;
    this.handlers.channelDeleted.length = 0;
    this.handlers.channelSwitch.length = 0;
    this.handlers.contentResolved.length = 0;
    this.handlers.persistenceWarning.length = 0;
  }

  private off<K extends keyof ChannelManagerEventMap>(
    event: K,
    handler: (payload: ChannelManagerEventMap[K]) => void,
  ): void {
    const handlers = this.handlers[event];
    const index = handlers.indexOf(handler);
    if (index >= 0) handlers.splice(index, 1);
  }
}

export class ChannelManager implements IChannelManager {
  private readonly emitter = new ChannelEventOwner();
  private readonly contentResolver: ContentResolver;
  private readonly authoring: ChannelAuthoringService;
  private readonly importExport: ChannelImportExportService;
  private readonly resolutionCache: ChannelResolutionCache;
  private readonly retryScheduler: ChannelRetryScheduler;
  private readonly logger: ChannelLogger;
  private readonly persistence;

  private state: ChannelManagerState = {
    channels: new Map(),
    currentChannelId: null,
    channelOrder: [],
  };

  public constructor(private readonly config: ChannelManagerConfig) {
    this.logger = config.logger ?? NOOP_LOGGER;
    this.persistence = config.persistence ?? null;
    this.contentResolver = new ContentResolver(config.plexLibrary, config.clock, this.logger);
    this.authoring = new ChannelAuthoringService({
      generateId: config.generateId,
      now: () => config.clock.now(),
    });
    this.resolutionCache = new ChannelResolutionCache(config.clock);
    this.retryScheduler = new ChannelRetryScheduler({
      getChannel: (channelId): ChannelConfig | null => this.state.channels.get(channelId) ?? null,
      resolve: (channel, isCurrent): Promise<ResolvedChannelContent> =>
        this.resolveContentInternal(channel, { shouldApply: isCurrent }),
      logger: this.logger,
      timers: config.timers,
      clock: config.clock,
    });
    this.importExport = new ChannelImportExportService({
      getAllChannels: (): ChannelConfig[] => this.getAllChannels(),
      isChannelNumberInUse: (number): boolean => this.isChannelNumberInUse(number),
      getNextAvailableNumber: (): number => this.getNextAvailableNumber(),
      createChannel: (input): Promise<ChannelConfig> => this.createChannel(input),
    });
  }

  public async replaceAllChannels(
    channels: ChannelConfig[],
    options?: { currentChannelId?: string | null },
  ): Promise<void> {
    const replacement = this.authoring.buildReplacementState(channels, this.logger);
    const nextChannels = replacement.channels;
    const nextChannelOrder = replacement.channelOrder;
    const requestedCurrent = options?.currentChannelId ?? null;
    const fallbackCurrent = nextChannelOrder[0] ?? null;
    const nextCurrentChannelId =
      requestedCurrent && nextChannels.has(requestedCurrent) ? requestedCurrent : fallbackCurrent;

    await this.persistStoredChannelData({
      channels: Array.from(nextChannels.values()),
      channelOrder: nextChannelOrder,
      currentChannelId: nextCurrentChannelId,
      savedAt: this.config.clock.now(),
    });

    this.retryScheduler.cancelAll();
    this.contentResolver.clearCaches();
    this.state.channels = nextChannels;
    this.resolutionCache.clear();
    this.state.channelOrder = nextChannelOrder;
    this.state.currentChannelId = nextCurrentChannelId;
  }

  public async createChannel(
    config: ChannelCreateInput,
    options?: ChannelCreateOptions,
  ): Promise<ChannelConfig> {
    const channel = this.authoring.createChannel(config, this.state.channels.values());
    let resolvedContent: ResolvedChannelContent | null = null;
    let shouldEmitContentResolved = false;

    try {
      if (options?.initialContent) {
        const initialItems = this.resolutionCache.cloneItems(options.initialContent);
        resolvedContent = this.createResolvedContent(channel, initialItems);
        this.applyResolvedContentMetadata(channel, resolvedContent);
      } else {
        resolvedContent = await this.resolveContentForAuthoring(channel, options);
        this.applyResolvedContentMetadata(channel, resolvedContent);
        shouldEmitContentResolved = !resolvedContent.fromCache;
      }
    } catch (error) {
      if (!isGracefulAuthoringResolutionError(error)) {
        throw error;
      }
      this.logger.warn(`Failed initial content resolution for channel ${channel.id}`, summarizeError(error));
    }

    this.state.channels.set(channel.id, channel);
    this.state.channelOrder.push(channel.id);

    if (resolvedContent) {
      this.resolutionCache.set(resolvedContent);
      if (shouldEmitContentResolved) {
        this.emitter.emit('contentResolved', resolvedContent);
      }
    }

    await this.queueSave();
    this.emitter.emit('channelCreated', channel);
    return cloneChannelForOwnership(channel);
  }

  public async updateChannel(id: string, updates: ChannelUpdateInput): Promise<ChannelConfig> {
    const channel = this.state.channels.get(id);
    if (!channel) throw createChannelNotFoundError();

    const filteredUpdates = omitUndefinedChannelUpdates(updates);
    const peerChannels = Array.from(this.state.channels.values()).filter((candidate) => candidate.id !== id);
    const updated = this.authoring.updateChannel(channel, filteredUpdates, peerChannels);
    let resolvedContent: ResolvedChannelContent | null = null;

    if (affectsResolvedContent(filteredUpdates)) {
      try {
        resolvedContent = await this.resolveContentForAuthoring(updated);
        if (this.state.channels.get(id) !== channel) {
          return cloneChannelForOwnership(updated);
        }
        this.applyResolvedContentMetadata(updated, resolvedContent);
      } catch (error) {
        if (!isGracefulAuthoringResolutionError(error)) throw error;
        this.logger.warn(`Failed content resolution during update for ${id}`, summarizeError(error));
      }
    }

    if (this.state.channels.get(id) !== channel) {
      return cloneChannelForOwnership(updated);
    }

    this.state.channels.set(id, updated);
    if (resolvedContent) {
      this.resolutionCache.set(resolvedContent);
      if (!resolvedContent.fromCache) this.emitter.emit('contentResolved', resolvedContent);
    }

    await this.queueSave();
    this.emitter.emit('channelUpdated', updated);
    return cloneChannelForOwnership(updated);
  }

  public async deleteChannel(id: string): Promise<void> {
    if (!this.state.channels.has(id)) throw createChannelNotFoundError();

    this.state.channels.delete(id);
    this.resolutionCache.delete(id);
    this.state.channelOrder = this.state.channelOrder.filter((cid) => cid !== id);
    if (this.state.currentChannelId === id) {
      this.state.currentChannelId = this.state.channelOrder[0] ?? null;
    }
    await this.queueSave();
    this.emitter.emit('channelDeleted', id);
  }

  public getChannel(id: string): ChannelConfig | null {
    const channel = this.state.channels.get(id);
    return channel ? cloneChannelForOwnership(channel) : null;
  }

  public getAllChannels(): ChannelConfig[] {
    return this.state.channelOrder
      .map((id) => this.state.channels.get(id))
      .filter((channel): channel is ChannelConfig => channel !== undefined)
      .map(cloneChannelForOwnership);
  }

  public getChannelByNumber(number: number): ChannelConfig | null {
    for (const channel of this.state.channels.values()) {
      if (channel.number === number) return cloneChannelForOwnership(channel);
    }
    return null;
  }

  public async resolveChannelContent(
    channelId: string,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedChannelContent> {
    const channel = this.state.channels.get(channelId);
    if (!channel) throw createChannelNotFoundError();

    const cached = this.resolutionCache.get(channelId);
    if (cached && !this.resolutionCache.isStale(cached)) {
      return this.resolutionCache.cloneContent(cached, {
        fromCache: true,
        isStale: false,
        cacheReason: 'fresh',
      });
    }

    return this.resolveContentInternal(channel, options);
  }

  public async refreshChannelContent(
    channelId: string,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedChannelContent> {
    const channel = this.state.channels.get(channelId);
    if (!channel) throw createChannelNotFoundError();

    this.resolutionCache.delete(channelId);
    this.contentResolver.invalidateSource(channel.contentSource);
    return this.resolveContentInternal(channel, options);
  }

  public async resolveChannelItemsForSchedule(
    channelId: string,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    const channel = this.state.channels.get(channelId);
    if (!channel) throw createChannelNotFoundError();

    const cached = this.resolutionCache.get(channelId);
    if (cached && !this.resolutionCache.isStale(cached)) {
      return this.resolutionCache.cloneItems(cached.items);
    }

    const items = await this.resolveFilteredItems(channel, options);
    return this.resolutionCache.cloneItems(items);
  }

  public async reorderChannels(orderedIds: string[]): Promise<void> {
    this.assertExactChannelOrder(orderedIds);
    this.state.channelOrder = [...orderedIds];
    await this.queueSave();
  }

  public setCurrentChannel(channelId: string): void {
    const channel = this.state.channels.get(channelId);
    if (!channel) throw createChannelNotFoundError();

    this.state.currentChannelId = channelId;
    const index = this.state.channelOrder.indexOf(channelId);
    this.emitter.emit('channelSwitch', { channel: cloneChannelForOwnership(channel), index });
    void this.queueSave().catch((error) => {
      this.logger.error('Failed to persist current channel', summarizeError(error));
    });
  }

  public getCurrentChannel(): ChannelConfig | null {
    if (!this.state.currentChannelId) return null;
    const channel = this.state.channels.get(this.state.currentChannelId);
    return channel ? cloneChannelForOwnership(channel) : null;
  }

  public getNextChannel(): ChannelConfig | null {
    if (!this.state.currentChannelId || this.state.channelOrder.length === 0) return null;
    const currentIndex = this.state.channelOrder.indexOf(this.state.currentChannelId);
    const nextIndex = (currentIndex + 1) % this.state.channelOrder.length;
    const nextId = this.state.channelOrder[nextIndex];
    const channel = nextId ? this.state.channels.get(nextId) : null;
    return channel ? cloneChannelForOwnership(channel) : null;
  }

  public getPreviousChannel(): ChannelConfig | null {
    if (!this.state.currentChannelId || this.state.channelOrder.length === 0) return null;
    const currentIndex = this.state.channelOrder.indexOf(this.state.currentChannelId);
    const prevIndex = (currentIndex - 1 + this.state.channelOrder.length) % this.state.channelOrder.length;
    const prevId = this.state.channelOrder[prevIndex];
    const channel = prevId ? this.state.channels.get(prevId) : null;
    return channel ? cloneChannelForOwnership(channel) : null;
  }

  public exportChannels(): string {
    return this.importExport.exportChannels();
  }

  public importChannels(data: string): Promise<ImportResult> {
    return this.importExport.importChannels(data);
  }

  public async flushSaves(): Promise<void> {
    const data = this.getStoredChannelData();
    if (this.persistence?.flush) {
      await this.persistence.flush(data);
      return;
    }
    await this.persistStoredChannelData(data);
  }

  public dispose(): void {
    this.retryScheduler.cancelAll();
    this.persistence?.dispose?.();
    this.contentResolver.clearCaches();
    this.emitter.clear();
  }

  public saveChannels(): Promise<void> {
    return this.persistStoredChannelData(this.getStoredChannelData());
  }

  public async loadChannels(): Promise<void> {
    try {
      const data = await this.persistence?.load();
      if (!data) return;
      const replacement = this.authoring.buildReplacementState(
        orderChannelsForStoredOrder(data.channels, data.channelOrder),
        this.logger,
      );
      const currentChannelId =
        data.currentChannelId && replacement.channels.has(data.currentChannelId)
          ? data.currentChannelId
          : replacement.channelOrder[0] ?? null;
      this.retryScheduler.cancelAll();
      this.contentResolver.clearCaches();
      this.resolutionCache.clear();
      this.state.channels = replacement.channels;
      this.state.channelOrder = replacement.channelOrder;
      this.state.currentChannelId = currentChannelId;
    } catch (error) {
      this.logger.error('Failed to load channels from storage', summarizeError(error));
    }
  }

  public on<K extends keyof ChannelManagerEventMap>(
    event: K,
    handler: (payload: ChannelManagerEventMap[K]) => void,
  ): DomainDisposable {
    return this.emitter.on(event, handler);
  }

  private async queueSave(): Promise<void> {
    const data = this.getStoredChannelData();
    if (this.persistence?.queueSave) {
      this.persistence.queueSave(data);
      return;
    }
    await this.persistStoredChannelData(data);
  }

  private getStoredChannelData(): StoredChannelData {
    return {
      channels: this.getAllChannels(),
      channelOrder: [...this.state.channelOrder],
      currentChannelId: this.state.currentChannelId,
      savedAt: this.config.clock.now(),
    };
  }

  private async persistStoredChannelData(data: StoredChannelData): Promise<void> {
    if (this.persistence) {
      await this.persistence.save(data);
    }
  }

  private assertExactChannelOrder(orderedIds: string[]): void {
    if (orderedIds.length !== this.state.channels.size) {
      throw new ChannelError('STORAGE_VALIDATION_FAILED', 'Channel reorder must include every channel exactly once');
    }

    const seen = new Set<string>();
    for (const id of orderedIds) {
      if (seen.has(id)) {
        throw new ChannelError('STORAGE_VALIDATION_FAILED', 'Channel reorder cannot include duplicate channel ids');
      }
      seen.add(id);
      if (!this.state.channels.has(id)) {
        throw new ChannelError('STORAGE_VALIDATION_FAILED', 'Channel reorder cannot include unknown channel ids');
      }
    }
  }

  private async resolveFilteredItems(
    channel: ChannelConfig,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]> {
    const rawItems = await this.contentResolver.resolveSource(channel.contentSource, options);
    if (rawItems.length === 0) {
      throw new ChannelError(
        'CONTENT_UNAVAILABLE',
        'Content source returned no items - source may have been deleted',
        true,
      );
    }

    let items = rawItems;
    if (channel.contentFilters && channel.contentFilters.length > 0) {
      items = this.contentResolver.applyFilters(items, channel.contentFilters);
    }
    if (channel.sortOrder) {
      items = this.contentResolver.applySort(items, channel.sortOrder);
    }

    items = items.filter((item) => item.durationMs > 0);
    if (channel.minEpisodeRunTimeMs || channel.maxEpisodeRunTimeMs) {
      items = items.filter((item) => {
        if (channel.minEpisodeRunTimeMs && item.durationMs < channel.minEpisodeRunTimeMs) return false;
        if (channel.maxEpisodeRunTimeMs && item.durationMs > channel.maxEpisodeRunTimeMs) return false;
        return true;
      });
    }

    if (items.length === 0) {
      throw new ChannelError('SCHEDULER_EMPTY_CHANNEL', CHANNEL_ERROR_MESSAGES.EMPTY_CONTENT);
    }

    return items;
  }

  private createResolvedContent(
    channel: ChannelConfig,
    items: ResolvedContentItem[],
  ): ResolvedChannelContent {
    const orderedItems = this.contentResolver.applyPlaybackMode(
      items,
      channel.playbackMode,
      typeof channel.shuffleSeed === 'number' && Number.isFinite(channel.shuffleSeed)
        ? channel.shuffleSeed
        : fnv1a32Uint(`${channel.id}:shuffle`),
      channel.blockSize,
    );
    const totalDurationMs = items.reduce((sum, item) => sum + item.durationMs, 0);
    return {
      channelId: channel.id,
      resolvedAt: this.config.clock.now(),
      items,
      totalDurationMs,
      orderedItems,
      fromCache: false,
      isStale: false,
      cacheReason: 'fresh',
    };
  }

  private applyResolvedContentMetadata(channel: ChannelConfig, content: ResolvedChannelContent): void {
    if (content.fromCache) return;
    channel.lastContentRefresh = content.resolvedAt;
    channel.itemCount = content.items.length;
    channel.totalDurationMs = content.totalDurationMs;
  }

  private createAccessDeniedResolutionError(channel: ChannelConfig, error: unknown): ChannelError {
    this.logger.warn('Access denied resolving channel content', {
      channelId: channel.id,
      contentSource: getContentSourceLogIdentity(channel.contentSource),
      status: getHttpStatus(error),
      error: summarizeError(error),
    });
    return new ChannelError(
      'ACCESS_DENIED',
      "Profile does not have access to this channel's content library",
    );
  }

  private async resolveContentForAuthoring(
    channel: ChannelConfig,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedChannelContent> {
    const cached = this.resolutionCache.get(channel.id);
    try {
      const items = await this.resolveFilteredItems(channel, options);
      this.retryScheduler.cancel(channel.id);
      return this.createResolvedContent(channel, items);
    } catch (error) {
      if (error instanceof ChannelError && error.code === 'SCHEDULER_EMPTY_CHANNEL') throw error;
      if (isNetworkError(error) && cached) {
        this.retryScheduler.queue(channel.id);
        return this.resolutionCache.cloneContent(cached, {
          fromCache: true,
          isStale: true,
          cacheReason: 'network_error',
        });
      }
      if (isGracefulAuthoringResolutionError(error) && cached) {
        return this.resolutionCache.cloneContent(cached, {
          fromCache: true,
          isStale: true,
          cacheReason: 'content_unavailable',
        });
      }
      if (isAccessDeniedError(error)) throw this.createAccessDeniedResolutionError(channel, error);
      throw error;
    }
  }

  private async resolveContentInternal(
    channel: ChannelConfig,
    options?: ChannelResolveOptions & { shouldApply?: () => boolean },
  ): Promise<ResolvedChannelContent> {
    const cached = this.resolutionCache.get(channel.id);
    try {
      const items = await this.resolveFilteredItems(channel, options);
      const result = this.createResolvedContent(channel, items);
      if (!this.canApplyResolvedContent(channel, options?.shouldApply)) return result;

      this.retryScheduler.cancel(channel.id);
      this.resolutionCache.set(result);
      this.emitter.emit('contentResolved', result);
      this.applyResolvedContentMetadata(channel, result);
      this.state.channels.set(channel.id, channel);
      await this.queueSave();
      return this.resolutionCache.cloneContent(result);
    } catch (error) {
      if (options?.shouldApply && !options.shouldApply()) throw error;
      if (error instanceof ChannelError && error.code === 'SCHEDULER_EMPTY_CHANNEL') throw error;
      if (isNetworkError(error) && cached) {
        const isStale = this.resolutionCache.isStale(cached);
        this.retryScheduler.queue(channel.id);
        return this.resolutionCache.cloneContent(cached, {
          fromCache: true,
          isStale,
          cacheReason: 'network_error',
        });
      }
      if (isGracefulAuthoringResolutionError(error) && cached) {
        return this.resolutionCache.cloneContent(cached, {
          fromCache: true,
          isStale: true,
          cacheReason: 'content_unavailable',
        });
      }
      if (isAccessDeniedError(error)) {
        this.resolutionCache.delete(channel.id);
        this.contentResolver.invalidateSource(channel.contentSource);
        this.retryScheduler.cancel(channel.id);
        throw this.createAccessDeniedResolutionError(channel, error);
      }
      throw error;
    }
  }

  private canApplyResolvedContent(channel: ChannelConfig, shouldApply?: () => boolean): boolean {
    return this.state.channels.get(channel.id) === channel && (shouldApply === undefined || shouldApply());
  }

  private isChannelNumberInUse(number: number): boolean {
    return this.authoring.isChannelNumberInUse(number, this.state.channels.values());
  }

  private getNextAvailableNumber(): number {
    return this.authoring.getNextAvailableNumber(this.state.channels.values());
  }
}

function affectsResolvedContent(updates: ChannelUpdateInput): boolean {
  return RESOLUTION_AFFECTING_UPDATE_FIELDS.some((field) =>
    Object.prototype.hasOwnProperty.call(updates, field),
  );
}

function orderChannelsForStoredOrder(
  channels: readonly ChannelConfig[],
  channelOrder: readonly string[],
): ChannelConfig[] {
  const channelsById = new Map(channels.map((channel) => [channel.id, channel]));
  const ordered: ChannelConfig[] = [];
  const seen = new Set<string>();

  for (const id of channelOrder) {
    const channel = channelsById.get(id);
    if (!channel || seen.has(id)) {
      continue;
    }
    seen.add(id);
    ordered.push(channel);
  }

  for (const channel of channels) {
    if (!seen.has(channel.id)) {
      ordered.push(channel);
    }
  }

  return ordered;
}

function createChannelNotFoundError(): ChannelError {
  return new ChannelError('CHANNEL_NOT_FOUND', CHANNEL_ERROR_MESSAGES.CHANNEL_NOT_FOUND);
}

function isNetworkError(error: unknown): boolean {
  const code = getChannelErrorCode(error);
  if (code && NETWORK_ERROR_CODES.has(code)) return true;
  return error instanceof Error && (
    error.message.toLowerCase().includes('network') ||
    error.message.toLowerCase().includes('timeout') ||
    error.message.toLowerCase().includes('econnrefused') ||
    error.message.toLowerCase().includes('failed to fetch')
  );
}

function isContentUnavailableError(error: unknown): boolean {
  return getChannelErrorCode(error) === 'CONTENT_UNAVAILABLE';
}

function isAccessDeniedError(error: unknown): boolean {
  return getChannelErrorCode(error) === 'ACCESS_DENIED' || getHttpStatus(error) === 403;
}

function isResourceNotFoundError(error: unknown): boolean {
  const code = getChannelErrorCode(error);
  if (code === 'RESOURCE_NOT_FOUND') return true;
  const status = getHttpStatus(error);
  if (status === 404) return true;
  return error instanceof Error && /\b404\b/.test(error.message);
}

function isGracefulAuthoringResolutionError(error: unknown): boolean {
  return isContentUnavailableError(error) || isResourceNotFoundError(error);
}

function getContentSourceLogIdentity(source: ChannelContentSource): { type: ChannelContentSource['type']; id?: string } {
  switch (source.type) {
    case 'library':
      return { type: source.type, id: source.libraryId };
    case 'collection':
      return { type: source.type, id: source.collectionKey };
    case 'show':
      return { type: source.type, id: source.showKey };
    case 'playlist':
      return { type: source.type, id: source.playlistKey };
    case 'mixed':
    case 'manual':
      return { type: source.type };
  }
}

function getHttpStatus(error: unknown): number | undefined {
  if (!error || typeof error !== 'object') return undefined;
  const maybe = error as { httpStatus?: unknown; status?: unknown };
  if (typeof maybe.httpStatus === 'number') return maybe.httpStatus;
  if (typeof maybe.status === 'number') return maybe.status;
  return undefined;
}

function summarizeError(error: unknown): unknown {
  if (error instanceof Error) {
    return { name: error.name, message: error.message };
  }
  return error;
}

function fnv1a32Uint(input: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index++) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

export function isValidChannelConfig(value: unknown): value is ChannelConfig {
  if (!value || typeof value !== 'object') return false;
  const channel = value as Partial<ChannelConfig>;
  return (
    typeof channel.id === 'string' &&
    typeof channel.number === 'number' &&
    Number.isInteger(channel.number) &&
    typeof channel.name === 'string' &&
    typeof channel.startTimeAnchor === 'number' &&
    typeof channel.createdAt === 'number' &&
    typeof channel.updatedAt === 'number' &&
    typeof channel.lastContentRefresh === 'number' &&
    typeof channel.itemCount === 'number' &&
    typeof channel.totalDurationMs === 'number' &&
    typeof channel.skipIntros === 'boolean' &&
    typeof channel.skipCredits === 'boolean' &&
    typeof channel.playbackMode === 'string' &&
    isValidContentSource(channel.contentSource)
  );
}
