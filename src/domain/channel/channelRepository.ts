import { isValidContentSource } from './channelContentSourceValidator.js';
import {
  cloneChannelForOwnership,
  cloneContentFilters,
  cloneContentSource,
} from './channelDomainClone.js';
import type { ChannelPersistenceStore } from './channelPersistenceStore.js';
import { CHANNEL_DOMAIN_FORBIDDEN_KEYS } from './channelSafety.js';
import {
  isValidBuildStrategy,
  isValidContentFilterArray,
  isValidPlaybackMode,
  isValidSortOrder,
} from './channelValueValidators.js';
import { MAX_CHANNEL_NUMBER, MIN_CHANNEL_NUMBER } from './constants.js';
import type { ChannelClock, ChannelLogger } from './interfaces.js';
import type {
  ChannelConfig,
  ChannelContentSource,
  ContentFilter,
  ManualContentItem,
  StoredChannelData,
} from './types.js';

export type LoadedChannelState = {
  data: StoredChannelData;
  didMutate: boolean;
} | null;

export interface ChannelRepositoryConfig {
  store: ChannelPersistenceStore;
  clock: ChannelClock;
  logger?: Pick<ChannelLogger, 'warn'>;
}

/**
 * Loads stored channel data through normalization/repair, marking didMutate
 * when persisted shape, seeds, order, or current-channel pointers are corrected.
 */
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
    const storedSavedAt = stored.savedAt;
    const hasValidSavedAt = typeof storedSavedAt === 'number' && Number.isFinite(storedSavedAt);
    const savedAt = hasValidSavedAt ? storedSavedAt : this.clock.now();
    const dataCurrentChannelId =
      typeof stored.currentChannelId === 'string' ? stored.currentChannelId.trim() : null;

    const channelCandidates: ChannelConfig[] = [];
    let didMutate = !hasValidSavedAt;
    for (const raw of stored.channels) {
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
        didMutate = true;
        continue;
      }

      const normalized = normalizePersistedChannelCandidate(raw, this.logger);
      if (!normalized) {
        didMutate = true;
        continue;
      }

      const channel = normalized.channel;
      if (normalized.didMutate) {
        didMutate = true;
      }
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
  }

  public async saveCurrentChannelId(channelId: string | null): Promise<void> {
    await this.store.writeCurrentChannelId(channelId);
  }
}

const PERSISTED_CHANNEL_KEYS = new Set<string>([
  'id',
  'number',
  'name',
  'description',
  'isAutoGenerated',
  'icon',
  'color',
  'buildStrategy',
  'sourceLibraryId',
  'sourceLibraryName',
  'lineupReplicaIndex',
  'isPlaybackModeVariant',
  'contentSource',
  'playbackMode',
  'shuffleSeed',
  'blockSize',
  'phaseSeed',
  'startTimeAnchor',
  'contentFilters',
  'sortOrder',
  'skipIntros',
  'skipCredits',
  'maxEpisodeRunTimeMs',
  'minEpisodeRunTimeMs',
  'createdAt',
  'updatedAt',
  'lastContentRefresh',
  'itemCount',
  'totalDurationMs',
]);

type PersistedChannelNormalizationResult = {
  channel: ChannelConfig;
  didMutate: boolean;
};

function normalizePersistedChannelCandidate(
  raw: unknown,
  logger?: Pick<ChannelLogger, 'warn'>,
): PersistedChannelNormalizationResult | null {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    return null;
  }

  const record = raw as Record<string, unknown>;
  let didMutate = hasUnknownKeys(record, PERSISTED_CHANNEL_KEYS);

  const id = readTrimmedNonEmptyString(record.id);
  const name = readNonEmptyString(record.name);
  const playbackMode = isValidPlaybackMode(record.playbackMode) ? record.playbackMode : null;
  const startTimeAnchor = readFiniteNumber(record.startTimeAnchor);
  const createdAt = readFiniteNumber(record.createdAt);
  const updatedAt = readFiniteNumber(record.updatedAt);
  const lastContentRefresh = readFiniteNumber(record.lastContentRefresh);
  const itemCount = readNonNegativeFiniteNumber(record.itemCount);
  const totalDurationMs = readNonNegativeFiniteNumber(record.totalDurationMs);
  const skipIntros = typeof record.skipIntros === 'boolean' ? record.skipIntros : null;
  const skipCredits = typeof record.skipCredits === 'boolean' ? record.skipCredits : null;
  const contentSource = readContentSource(record.contentSource);

  if (
    id === null ||
    name === null ||
    playbackMode === null ||
    startTimeAnchor === null ||
    createdAt === null ||
    updatedAt === null ||
    lastContentRefresh === null ||
    itemCount === null ||
    totalDurationMs === null ||
    skipIntros === null ||
    skipCredits === null ||
    contentSource === null
  ) {
    logger?.warn('Dropping malformed persisted channel during normalized load');
    return null;
  }

  if (typeof record.id === 'string' && record.id !== id) {
    didMutate = true;
  }
  if (hasUnknownContentSourceKeys(record.contentSource)) {
    didMutate = true;
  }

  const number =
    typeof record.number === 'number' && Number.isFinite(record.number)
      ? record.number
      : Number.NaN;
  if (!Number.isInteger(number)) {
    didMutate = true;
  }

  const channel: ChannelConfig = {
    id,
    number,
    name,
    contentSource,
    playbackMode,
    startTimeAnchor,
    skipIntros,
    skipCredits,
    createdAt,
    updatedAt,
    lastContentRefresh,
    itemCount,
    totalDurationMs,
  };

  didMutate = applyPersistedOptionalFields(channel, record, didMutate);
  return { channel: cloneChannelForOwnership(channel), didMutate };
}

function applyPersistedOptionalFields(
  channel: ChannelConfig,
  record: Record<string, unknown>,
  initialDidMutate: boolean,
): boolean {
  let didMutate = initialDidMutate;

  didMutate = assignOptionalString(channel, record, 'description', didMutate);
  didMutate = assignOptionalString(channel, record, 'icon', didMutate);
  didMutate = assignOptionalString(channel, record, 'color', didMutate);
  didMutate = assignOptionalString(channel, record, 'sourceLibraryId', didMutate);
  didMutate = assignOptionalString(channel, record, 'sourceLibraryName', didMutate);
  didMutate = assignOptionalBoolean(channel, record, 'isAutoGenerated', didMutate);
  didMutate = assignOptionalBoolean(channel, record, 'isPlaybackModeVariant', didMutate);
  didMutate = assignOptionalFiniteNumber(channel, record, 'shuffleSeed', didMutate);
  didMutate = assignOptionalFiniteNumber(channel, record, 'phaseSeed', didMutate);
  didMutate = assignOptionalPositiveInteger(channel, record, 'maxEpisodeRunTimeMs', didMutate);
  didMutate = assignOptionalPositiveInteger(channel, record, 'minEpisodeRunTimeMs', didMutate);
  if (
    channel.minEpisodeRunTimeMs !== undefined &&
    channel.maxEpisodeRunTimeMs !== undefined &&
    channel.minEpisodeRunTimeMs > channel.maxEpisodeRunTimeMs
  ) {
    delete channel.minEpisodeRunTimeMs;
    delete channel.maxEpisodeRunTimeMs;
    didMutate = true;
  }

  if (record.buildStrategy !== undefined) {
    if (isValidBuildStrategy(record.buildStrategy)) {
      channel.buildStrategy = record.buildStrategy;
    } else {
      didMutate = true;
    }
  }

  if (record.lineupReplicaIndex !== undefined) {
    const index = readNonNegativeFiniteNumber(record.lineupReplicaIndex);
    if (index === null) {
      didMutate = true;
    } else {
      const normalized = Math.floor(index);
      channel.lineupReplicaIndex = normalized;
      didMutate ||= normalized !== record.lineupReplicaIndex;
    }
  }

  if (record.blockSize !== undefined) {
    const blockSize = readFiniteNumber(record.blockSize);
    if (channel.playbackMode === 'block' && blockSize !== null) {
      const normalized = Math.max(1, Math.floor(blockSize));
      channel.blockSize = normalized;
      didMutate ||= normalized !== record.blockSize;
    } else {
      didMutate = true;
    }
  }

  if (record.contentFilters !== undefined) {
    if (isValidContentFilterArray(record.contentFilters)) {
      channel.contentFilters = cloneContentFilters(record.contentFilters);
      if (hasUnknownContentFilterKeys(record.contentFilters)) {
        didMutate = true;
      }
    } else {
      didMutate = true;
    }
  }

  if (record.sortOrder !== undefined) {
    if (isValidSortOrder(record.sortOrder)) {
      channel.sortOrder = record.sortOrder;
    } else {
      didMutate = true;
    }
  }

  return didMutate;
}

function readContentSource(value: unknown): ChannelContentSource | null {
  const clean = readPersistedContentSource(value);
  if (clean === null || !isValidContentSource(clean)) {
    return null;
  }
  return cloneContentSource(clean);
}

const MAX_PERSISTED_CONTENT_SOURCE_DEPTH = 25;

function readPersistedContentSource(value: unknown, depth = 0): ChannelContentSource | null {
  if (depth > MAX_PERSISTED_CONTENT_SOURCE_DEPTH) {
    return null;
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  if (hasForbiddenKeys(record)) {
    return null;
  }

  switch (record.type) {
    case 'library':
      return readPersistedLibrarySource(record);
    case 'collection':
      return readPersistedCollectionSource(record);
    case 'show':
      return readPersistedShowSource(record);
    case 'playlist':
      return readPersistedPlaylistSource(record);
    case 'manual':
      return readPersistedManualSource(record);
    case 'mixed':
      return readPersistedMixedSource(record, depth);
    default:
      return null;
  }
}

function readPersistedLibrarySource(record: Record<string, unknown>): ChannelContentSource | null {
  const libraryFilter = readPersistedLibraryFilter(record.libraryFilter);
  if (record.libraryFilter !== undefined && libraryFilter === null) {
    return null;
  }
  return {
    type: 'library',
    libraryId: record.libraryId,
    libraryType: record.libraryType,
    includeWatched: record.includeWatched,
    ...(libraryFilter !== undefined ? { libraryFilter } : {}),
  } as ChannelContentSource;
}

function readPersistedCollectionSource(record: Record<string, unknown>): ChannelContentSource {
  return {
    type: 'collection',
    collectionKey: record.collectionKey,
    collectionName: record.collectionName,
  } as ChannelContentSource;
}

function readPersistedShowSource(record: Record<string, unknown>): ChannelContentSource {
  return {
    type: 'show',
    showKey: record.showKey,
    showName: record.showName,
    ...(record.seasonFilter !== undefined ? { seasonFilter: record.seasonFilter } : {}),
  } as ChannelContentSource;
}

function readPersistedPlaylistSource(record: Record<string, unknown>): ChannelContentSource {
  return {
    type: 'playlist',
    playlistKey: record.playlistKey,
    playlistName: record.playlistName,
  } as ChannelContentSource;
}

function readPersistedManualSource(record: Record<string, unknown>): ChannelContentSource | null {
  if (!Array.isArray(record.items)) {
    return null;
  }
  const items: ManualContentItem[] = [];
  for (const item of record.items) {
    const cleanItem = readPersistedManualItem(item);
    if (cleanItem === null) {
      return null;
    }
    items.push(cleanItem);
  }
  return { type: 'manual', items };
}

function readPersistedManualItem(value: unknown): ManualContentItem | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  if (hasForbiddenKeys(record)) {
    return null;
  }
  return {
    ratingKey: record.ratingKey,
    title: record.title,
    durationMs: record.durationMs,
  } as ManualContentItem;
}

function readPersistedMixedSource(
  record: Record<string, unknown>,
  depth: number,
): ChannelContentSource | null {
  if (!Array.isArray(record.sources)) {
    return null;
  }
  const sources: ChannelContentSource[] = [];
  for (const source of record.sources) {
    const cleanSource = readPersistedContentSource(source, depth + 1);
    if (cleanSource === null) {
      return null;
    }
    sources.push(cleanSource);
  }
  return {
    type: 'mixed',
    sources,
    mixMode: record.mixMode,
  } as ChannelContentSource;
}

function readPersistedLibraryFilter(value: unknown): Record<string, string | number> | undefined | null {
  if (value === undefined) {
    return undefined;
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  if (hasForbiddenKeys(record)) {
    return null;
  }
  const filter: Record<string, string | number> = {};
  for (const [key, entry] of Object.entries(record)) {
    if (typeof entry === 'string') {
      filter[key] = entry;
    } else if (typeof entry === 'number' && Number.isFinite(entry)) {
      filter[key] = entry;
    } else {
      return null;
    }
  }
  return filter;
}

function hasForbiddenKeys(record: Record<string, unknown>): boolean {
  return Object.keys(record).some((key) => (CHANNEL_DOMAIN_FORBIDDEN_KEYS as readonly string[]).includes(key));
}

function readTrimmedNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readNonEmptyString(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function readFiniteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function readNonNegativeFiniteNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : null;
}

function hasUnknownKeys(record: Record<string, unknown>, knownKeys: ReadonlySet<string>): boolean {
  return Object.keys(record).some((key) => !knownKeys.has(key));
}

function assignOptionalString<K extends OptionalStringChannelKey>(
  channel: ChannelConfig,
  record: Record<string, unknown>,
  key: K,
  didMutate: boolean,
): boolean {
  const value = record[key];
  if (value === undefined) {
    return didMutate;
  }
  if (typeof value !== 'string') {
    return true;
  }
  channel[key] = value;
  return didMutate;
}

function assignOptionalBoolean<K extends OptionalBooleanChannelKey>(
  channel: ChannelConfig,
  record: Record<string, unknown>,
  key: K,
  didMutate: boolean,
): boolean {
  const value = record[key];
  if (value === undefined) {
    return didMutate;
  }
  if (typeof value !== 'boolean') {
    return true;
  }
  channel[key] = value;
  return didMutate;
}

function assignOptionalFiniteNumber<K extends OptionalNumberChannelKey>(
  channel: ChannelConfig,
  record: Record<string, unknown>,
  key: K,
  didMutate: boolean,
): boolean {
  const value = record[key];
  if (value === undefined) {
    return didMutate;
  }
  const number = readFiniteNumber(value);
  if (number === null) {
    return true;
  }
  channel[key] = number;
  return didMutate;
}

function assignOptionalPositiveInteger<K extends OptionalNumberChannelKey>(
  channel: ChannelConfig,
  record: Record<string, unknown>,
  key: K,
  didMutate: boolean,
): boolean {
  const value = record[key];
  if (value === undefined) {
    return didMutate;
  }
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    !Number.isInteger(value) ||
    value <= 0
  ) {
    return true;
  }
  channel[key] = value;
  return didMutate;
}

type OptionalStringChannelKey =
  | 'description'
  | 'icon'
  | 'color'
  | 'sourceLibraryId'
  | 'sourceLibraryName';

type OptionalBooleanChannelKey = 'isAutoGenerated' | 'isPlaybackModeVariant';
type OptionalNumberChannelKey =
  | 'shuffleSeed'
  | 'phaseSeed'
  | 'maxEpisodeRunTimeMs'
  | 'minEpisodeRunTimeMs';

function hasUnknownContentSourceKeys(source: unknown): boolean {
  if (!source || typeof source !== 'object' || Array.isArray(source)) {
    return false;
  }

  const record = source as Record<string, unknown>;
  switch (record.type) {
    case 'library':
      return hasUnknownKeys(record, LIBRARY_SOURCE_KEYS);
    case 'collection':
      return hasUnknownKeys(record, COLLECTION_SOURCE_KEYS);
    case 'show':
      return hasUnknownKeys(record, SHOW_SOURCE_KEYS);
    case 'playlist':
      return hasUnknownKeys(record, PLAYLIST_SOURCE_KEYS);
    case 'manual':
      return (
        hasUnknownKeys(record, MANUAL_SOURCE_KEYS) ||
        (Array.isArray(record.items) && record.items.some(hasUnknownManualItemKeys))
      );
    case 'mixed':
      return (
        hasUnknownKeys(record, MIXED_SOURCE_KEYS) ||
        (Array.isArray(record.sources) && record.sources.some(hasUnknownContentSourceKeys))
      );
    default:
      return false;
  }
}

const LIBRARY_SOURCE_KEYS = new Set<string>([
  'type',
  'libraryId',
  'libraryType',
  'includeWatched',
  'libraryFilter',
]);
const COLLECTION_SOURCE_KEYS = new Set<string>(['type', 'collectionKey', 'collectionName']);
const SHOW_SOURCE_KEYS = new Set<string>(['type', 'showKey', 'showName', 'seasonFilter']);
const PLAYLIST_SOURCE_KEYS = new Set<string>(['type', 'playlistKey', 'playlistName']);
const MANUAL_SOURCE_KEYS = new Set<string>(['type', 'items']);
const MIXED_SOURCE_KEYS = new Set<string>(['type', 'sources', 'mixMode']);
const MANUAL_ITEM_KEYS = new Set<string>(['ratingKey', 'title', 'durationMs']);
const CONTENT_FILTER_KEYS = new Set<string>(['field', 'operator', 'value']);

function hasUnknownManualItemKeys(value: unknown): boolean {
  return !!value && typeof value === 'object' && !Array.isArray(value) &&
    hasUnknownKeys(value as Record<string, unknown>, MANUAL_ITEM_KEYS);
}

function hasUnknownContentFilterKeys(filters: ContentFilter[]): boolean {
  return filters.some((filter) => hasUnknownKeys(filter as unknown as Record<string, unknown>, CONTENT_FILTER_KEYS));
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
