import { isValidContentSource } from './channelContentSourceValidator.js';
import { cloneChannelForOwnership } from './channelDomainClone.js';
import type { ChannelPersistenceStore } from './channelPersistenceStore.js';
import { MAX_CHANNEL_NUMBER, MIN_CHANNEL_NUMBER } from './constants.js';
import type { ChannelClock, ChannelLogger } from './interfaces.js';
import type { ChannelConfig, StoredChannelData } from './types.js';

export type LoadedChannelState = {
  data: StoredChannelData;
  didMutate: boolean;
} | null;

export interface ChannelRepositoryConfig {
  store: ChannelPersistenceStore;
  clock: ChannelClock;
  logger?: Pick<ChannelLogger, 'warn'>;
}

export class ChannelRepository {
  private readonly store: ChannelPersistenceStore;
  private readonly clock: ChannelClock;
  private readonly logger?: Pick<ChannelLogger, 'warn'>;

  public constructor(config: ChannelRepositoryConfig) {
    this.store = config.store;
    this.clock = config.clock;
    this.logger = config.logger;
  }

  public async loadNormalized(): Promise<LoadedChannelState> {
    const stored = await this.store.readStoredChannelData();
    if (stored === null) {
      return null;
    }
    if (!Array.isArray(stored.channels) || !Array.isArray(stored.channelOrder)) {
      return null;
    }

    const savedCurrentChannelId = await this.store.readCurrentChannelId();
    const savedAt =
      typeof stored.savedAt === 'number' && Number.isFinite(stored.savedAt)
        ? stored.savedAt
        : this.clock.now();
    const dataCurrentChannelId =
      typeof stored.currentChannelId === 'string' ? stored.currentChannelId.trim() : null;

    const channelCandidates: ChannelConfig[] = [];
    let didMutate = false;
    for (const raw of stored.channels) {
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        didMutate = true;
        continue;
      }

      const candidate = raw as Partial<ChannelConfig>;
      if (typeof candidate.id !== 'string' || candidate.id.trim().length === 0) {
        didMutate = true;
        continue;
      }
      if (!isValidContentSource(candidate.contentSource)) {
        didMutate = true;
        continue;
      }
      const channel = cloneChannelForOwnership(candidate as ChannelConfig);
      channel.id = channel.id.trim();
      if (typeof channel.shuffleSeed !== 'number' || !Number.isFinite(channel.shuffleSeed)) {
        channel.shuffleSeed = fnv1a32Uint(`${channel.id}:shuffle`);
        didMutate = true;
      }
      if (typeof channel.phaseSeed !== 'number' || !Number.isFinite(channel.phaseSeed)) {
        channel.phaseSeed = fnv1a32Uint(`${channel.id}:phase`);
        didMutate = true;
      }
      channelCandidates.push(channel);
    }

    const uniqueChannels = dropDuplicateChannels(channelCandidates, this.logger);
    if (uniqueChannels.length !== channelCandidates.length) {
      didMutate = true;
    }

    const normalizedNumbers = normalizeChannelNumbers(uniqueChannels, this.logger);
    if (normalizedNumbers.didMutate) {
      didMutate = true;
    }

    const normalizedChannels = normalizedNumbers.channels;
    const channelIds = new Set(normalizedChannels.map((channel) => channel.id));
    const normalizedOrder = normalizeChannelOrder(stored.channelOrder, channelIds);
    if (normalizedOrder.didMutate) {
      didMutate = true;
    }

    let channelOrder = normalizedOrder.channelOrder;
    if (channelOrder.length === 0 && normalizedChannels.length > 0) {
      channelOrder = [...normalizedChannels]
        .sort((left, right) => left.number - right.number || left.id.localeCompare(right.id))
        .map((channel) => channel.id);
      didMutate = true;
    }

    let currentChannelId = dataCurrentChannelId;
    if (savedCurrentChannelId !== null && channelIds.has(savedCurrentChannelId)) {
      currentChannelId = savedCurrentChannelId;
      if (currentChannelId !== dataCurrentChannelId) {
        didMutate = true;
      }
    } else if (currentChannelId !== null && !channelIds.has(currentChannelId)) {
      currentChannelId = channelOrder[0] ?? null;
      didMutate = true;
    } else if (currentChannelId === null && channelOrder.length > 0) {
      currentChannelId = channelOrder[0] ?? null;
      didMutate = true;
    }
    if (savedCurrentChannelId !== null && !channelIds.has(savedCurrentChannelId)) {
      didMutate = true;
    }

    return {
      data: {
        channels: normalizedChannels,
        channelOrder,
        currentChannelId,
        savedAt,
      },
      didMutate,
    };
  }

  public async saveStoredChannelData(data: StoredChannelData): Promise<void> {
    await this.store.writeStoredChannelData(data);
    await this.store.writeCurrentChannelId(data.currentChannelId);
  }

  public async saveCurrentChannelId(channelId: string | null): Promise<void> {
    await this.store.writeCurrentChannelId(channelId);
  }
}

function normalizeChannelOrder(
  rawOrder: readonly unknown[],
  channelIds: ReadonlySet<string>,
): { channelOrder: string[]; didMutate: boolean } {
  const seen = new Set<string>();
  const channelOrder: string[] = [];
  let didMutate = false;
  for (const value of rawOrder) {
    if (typeof value !== 'string' || !channelIds.has(value) || seen.has(value)) {
      didMutate = true;
      continue;
    }
    seen.add(value);
    channelOrder.push(value);
  }
  for (const id of channelIds) {
    if (!seen.has(id)) {
      didMutate = true;
      channelOrder.push(id);
    }
  }
  return { channelOrder, didMutate };
}

function dropDuplicateChannels(
  channels: readonly ChannelConfig[],
  logger?: Pick<ChannelLogger, 'warn'>,
): ChannelConfig[] {
  const seen = new Set<string>();
  const normalized: ChannelConfig[] = [];
  for (const channel of channels) {
    if (seen.has(channel.id)) {
      logger?.warn('Dropping duplicate persisted channel during normalized load');
      continue;
    }
    seen.add(channel.id);
    normalized.push(channel);
  }
  return normalized;
}

function normalizeChannelNumbers(
  channels: readonly ChannelConfig[],
  logger?: Pick<ChannelLogger, 'warn'>,
): { channels: ChannelConfig[]; didMutate: boolean } {
  const usedNumbers = new Set<number>();
  let didMutate = false;
  const normalized: ChannelConfig[] = [];

  const takeNextAvailableNumber = (): number | null => {
    for (let n = MIN_CHANNEL_NUMBER; n <= MAX_CHANNEL_NUMBER; n++) {
      if (!usedNumbers.has(n)) {
        usedNumbers.add(n);
        return n;
      }
    }
    return null;
  };

  for (const channel of channels) {
    const number = channel.number;
    const hasValidUnusedNumber =
      Number.isInteger(number) &&
      number >= MIN_CHANNEL_NUMBER &&
      number <= MAX_CHANNEL_NUMBER &&
      !usedNumbers.has(number);
    if (hasValidUnusedNumber) {
      usedNumbers.add(number);
      normalized.push(channel);
      continue;
    }

    const fallbackNumber = takeNextAvailableNumber();
    if (fallbackNumber === null) {
      didMutate = true;
      logger?.warn('Dropping persisted channel during normalized load due to number exhaustion');
      continue;
    }
    normalized.push({ ...channel, number: fallbackNumber });
    didMutate = true;
  }

  return { channels: normalized, didMutate };
}

function fnv1a32Uint(input: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index++) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}
