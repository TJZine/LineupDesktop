import { ChannelError } from './channelError.js';
import { isValidContentSource } from './channelContentSourceValidator.js';
import {
  cloneChannelForOwnership,
  cloneContentFilters,
  cloneContentSource,
} from './channelDomainClone.js';
import {
  CHANNEL_ERROR_MESSAGES,
  MAX_CHANNELS,
  MAX_CHANNEL_NUMBER,
  MIN_CHANNEL_NUMBER,
} from './constants.js';
import {
  isValidBuildStrategy,
  isValidContentFilterArray,
  isValidPlaybackMode,
  isValidSortOrder,
} from './channelValueValidators.js';
import type {
  BuildStrategy,
  ChannelConfig,
  ChannelContentSource,
  ChannelCreateInput,
  ChannelUpdateInput,
  ContentFilter,
  PlaybackMode,
  SortOrder,
} from './types.js';

type ChannelAuthoringServiceConfig = {
  generateId: () => string;
  now: () => number;
};

type ChannelAuthoringLogger = {
  warn: (message: string, detail?: unknown) => void;
};

export function omitUndefinedChannelUpdates(updates: ChannelUpdateInput): ChannelUpdateInput {
  const filtered: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(updates)) {
    if (value !== undefined) {
      filtered[key] = value;
    }
  }
  return filtered as ChannelUpdateInput;
}

export type ReplacementChannelState = {
  channels: Map<string, ChannelConfig>;
  channelOrder: string[];
};

export class ChannelAuthoringService {
  private readonly generateId: () => string;
  private readonly now: () => number;

  public constructor(config: ChannelAuthoringServiceConfig) {
    this.generateId = config.generateId;
    this.now = config.now;
  }

  public createChannel(
    input: ChannelCreateInput,
    existingChannels: Iterable<ChannelConfig>,
  ): ChannelConfig {
    if (!input.contentSource) {
      throw new ChannelError(
        'CHANNEL_CONTENT_SOURCE_REQUIRED',
        CHANNEL_ERROR_MESSAGES.CHANNEL_CONTENT_SOURCE_REQUIRED,
      );
    }
    const contentSource = this.validateContentSource(input.contentSource);
    const channels = Array.from(existingChannels);
    if (channels.length >= MAX_CHANNELS) {
      throw new ChannelError('MAX_CHANNELS_REACHED', CHANNEL_ERROR_MESSAGES.MAX_CHANNELS_REACHED);
    }

    const now = this.now();
    const playbackMode = this.validatePlaybackMode(input.playbackMode, 'playbackMode') ?? 'sequential';
    const startTimeAnchor = this.validateStartTimeAnchor(input.startTimeAnchor, now);
    const validatedInput = this.validateOptionalFields(input, playbackMode, 'create');
    const channelNumber =
      validatedInput.number !== undefined
        ? this.validateRequestedNumber(validatedInput.number, channels)
        : this.getNextAvailableNumber(channels);
    const channel: ChannelConfig = {
      id: this.generateId(),
      number: channelNumber,
      name: typeof validatedInput.name === 'string' && validatedInput.name.length > 0
        ? validatedInput.name
        : `Channel ${channelNumber}`,
      contentSource: cloneContentSource(contentSource),
      playbackMode,
      startTimeAnchor,
      skipIntros: validatedInput.skipIntros === true,
      skipCredits: validatedInput.skipCredits === true,
      createdAt: now,
      updatedAt: now,
      lastContentRefresh: 0,
      itemCount: 0,
      totalDurationMs: 0,
    };

    this.applyOptionalFields(channel, validatedInput);
    this.applySeedDefaults(channel);
    return channel;
  }

  public buildReplacementState(
    channels: ChannelConfig[],
    logger: ChannelAuthoringLogger,
  ): ReplacementChannelState {
    const nextChannels = new Map<string, ChannelConfig>();
    const nextChannelOrder: string[] = [];
    const availableNumbers: number[] = [];
    for (let n = MIN_CHANNEL_NUMBER; n <= MAX_CHANNEL_NUMBER; n++) {
      availableNumbers.push(n);
    }
    const usedNumbers = new Set<number>();
    const takeNextAvailable = (): number | null => {
      const next = availableNumbers.shift();
      if (next === undefined) {
        return null;
      }
      usedNumbers.add(next);
      return next;
    };

    for (const channel of channels) {
      if (!this.shouldAcceptReplacementChannel(channel, nextChannels, nextChannelOrder, logger)) {
        continue;
      }
      const normalizedChannel = cloneChannelForOwnership(channel);
      const isValidNumber =
        typeof normalizedChannel.number === 'number' &&
        Number.isInteger(normalizedChannel.number) &&
        normalizedChannel.number >= MIN_CHANNEL_NUMBER &&
        normalizedChannel.number <= MAX_CHANNEL_NUMBER &&
        !usedNumbers.has(normalizedChannel.number);
      if (isValidNumber) {
        const index = availableNumbers.indexOf(normalizedChannel.number);
        if (index >= 0) {
          availableNumbers.splice(index, 1);
        }
        usedNumbers.add(normalizedChannel.number);
      } else {
        const fallback = takeNextAvailable();
        if (fallback === null) {
          logger.warn(`Skipping channel ${channel.name} (${channel.id}) due to number exhaustion`);
          continue;
        }
        normalizedChannel.number = fallback;
      }
      this.applySeedDefaults(normalizedChannel);
      nextChannels.set(normalizedChannel.id, normalizedChannel);
      nextChannelOrder.push(normalizedChannel.id);
    }

    return { channels: nextChannels, channelOrder: nextChannelOrder };
  }

  public updateChannel(
    channel: ChannelConfig,
    updates: ChannelUpdateInput,
    existingChannels: Iterable<ChannelConfig>,
  ): ChannelConfig {
    const filteredUpdates = omitUndefinedChannelUpdates(updates);
    const hasContentSourceUpdate = Object.prototype.hasOwnProperty.call(filteredUpdates, 'contentSource');
    const contentSourceUpdate = hasContentSourceUpdate
      ? this.validateContentSource(filteredUpdates.contentSource)
      : undefined;
    const playbackMode = this.validatePlaybackMode(filteredUpdates.playbackMode, 'playbackMode') ?? channel.playbackMode;
    const validatedUpdates = this.validateOptionalFields(filteredUpdates, playbackMode, 'update', channel);
    if (validatedUpdates.number !== undefined && validatedUpdates.number !== channel.number) {
      this.validateRequestedNumber(validatedUpdates.number, existingChannels);
    }
    const clonedUpdates: ChannelUpdateInput = {
      ...validatedUpdates,
      ...(hasContentSourceUpdate && contentSourceUpdate
        ? { contentSource: cloneContentSource(contentSourceUpdate) }
        : {}),
    };

    const updated: ChannelConfig = {
      ...channel,
      ...clonedUpdates,
      id: channel.id,
      createdAt: channel.createdAt,
      updatedAt: this.now(),
      lastContentRefresh: channel.lastContentRefresh,
      itemCount: channel.itemCount,
      totalDurationMs: channel.totalDurationMs,
    };

    this.applyOptionalFields(updated, clonedUpdates);
    this.applySeedDefaults(updated);
    return updated;
  }

  public getNextAvailableNumber(channels: Iterable<ChannelConfig>): number {
    const usedNumbers = new Set<number>();
    for (const channel of channels) {
      usedNumbers.add(channel.number);
    }
    for (let n = MIN_CHANNEL_NUMBER; n <= MAX_CHANNEL_NUMBER; n++) {
      if (!usedNumbers.has(n)) {
        return n;
      }
    }
    throw new ChannelError('MAX_CHANNELS_REACHED', CHANNEL_ERROR_MESSAGES.MAX_CHANNELS_REACHED);
  }

  public isChannelNumberInUse(number: number, channels: Iterable<ChannelConfig>): boolean {
    for (const channel of channels) {
      if (channel.number === number) {
        return true;
      }
    }
    return false;
  }

  public applySeedDefaults(channel: ChannelConfig): void {
    if (typeof channel.shuffleSeed !== 'number' || !Number.isFinite(channel.shuffleSeed)) {
      channel.shuffleSeed = fnv1a32Uint(`${channel.id}:shuffle`);
    }
    if (typeof channel.phaseSeed !== 'number' || !Number.isFinite(channel.phaseSeed)) {
      channel.phaseSeed = fnv1a32Uint(`${channel.id}:phase`);
    }
  }

  private applyOptionalFields(channel: ChannelConfig, input: Partial<ChannelCreateInput>): void {
    if (input.description !== undefined) channel.description = input.description;
    if (input.isAutoGenerated !== undefined) channel.isAutoGenerated = input.isAutoGenerated;
    if (input.icon !== undefined) channel.icon = input.icon;
    if (input.color !== undefined) channel.color = input.color;
    if (input.buildStrategy !== undefined) channel.buildStrategy = input.buildStrategy;
    if (input.sourceLibraryId !== undefined) channel.sourceLibraryId = input.sourceLibraryId;
    if (input.sourceLibraryName !== undefined) channel.sourceLibraryName = input.sourceLibraryName;
    if (typeof input.lineupReplicaIndex === 'number' && Number.isFinite(input.lineupReplicaIndex)) {
      channel.lineupReplicaIndex = Math.max(0, Math.floor(input.lineupReplicaIndex));
    }
    if (typeof input.isPlaybackModeVariant === 'boolean') {
      channel.isPlaybackModeVariant = input.isPlaybackModeVariant;
    }
    if (typeof input.shuffleSeed === 'number' && Number.isFinite(input.shuffleSeed)) {
      channel.shuffleSeed = input.shuffleSeed;
    }
    if (typeof input.phaseSeed === 'number' && Number.isFinite(input.phaseSeed)) {
      channel.phaseSeed = input.phaseSeed;
    }
    if (
      channel.playbackMode === 'block' &&
      typeof input.blockSize === 'number' &&
      Number.isFinite(input.blockSize)
    ) {
      channel.blockSize = Math.max(1, Math.floor(input.blockSize));
    } else if (channel.playbackMode !== 'block') {
      delete channel.blockSize;
    }
    if (input.contentFilters !== undefined) {
      channel.contentFilters = cloneContentFilters(input.contentFilters);
    }
    if (input.sortOrder !== undefined) channel.sortOrder = input.sortOrder;
    if (input.maxEpisodeRunTimeMs !== undefined) channel.maxEpisodeRunTimeMs = input.maxEpisodeRunTimeMs;
    if (input.minEpisodeRunTimeMs !== undefined) channel.minEpisodeRunTimeMs = input.minEpisodeRunTimeMs;
  }

  private validateOptionalFields(
    input: Partial<ChannelCreateInput>,
    finalPlaybackMode: PlaybackMode,
    mode: 'create' | 'update',
    existingChannel?: ChannelConfig,
  ): Partial<ChannelCreateInput> {
    const validated: Partial<ChannelCreateInput> = {};

    if (input.number !== undefined) {
      validated.number = this.requireNumberInput(input.number);
    }
    if (input.name !== undefined) {
      validated.name = this.requireNonBlankString(input.name, 'name');
    }
    if (input.description !== undefined) {
      validated.description = this.requireString(input.description, 'description');
    }
    if (input.icon !== undefined) {
      validated.icon = this.requireString(input.icon, 'icon');
    }
    if (input.color !== undefined) {
      validated.color = this.requireString(input.color, 'color');
    }
    if (input.sourceLibraryId !== undefined) {
      validated.sourceLibraryId = this.requireString(input.sourceLibraryId, 'sourceLibraryId');
    }
    if (input.sourceLibraryName !== undefined) {
      validated.sourceLibraryName = this.requireString(input.sourceLibraryName, 'sourceLibraryName');
    }
    if (input.isAutoGenerated !== undefined) {
      validated.isAutoGenerated = this.requireBoolean(input.isAutoGenerated, 'isAutoGenerated');
    }
    if (input.isPlaybackModeVariant !== undefined) {
      validated.isPlaybackModeVariant = this.requireBoolean(
        input.isPlaybackModeVariant,
        'isPlaybackModeVariant',
      );
    }
    if (input.skipIntros !== undefined) {
      validated.skipIntros = this.requireBoolean(input.skipIntros, 'skipIntros');
    }
    if (input.skipCredits !== undefined) {
      validated.skipCredits = this.requireBoolean(input.skipCredits, 'skipCredits');
    }

    if (input.playbackMode !== undefined) {
      validated.playbackMode = this.requirePlaybackMode(input.playbackMode, 'playbackMode');
    }
    if (input.startTimeAnchor !== undefined) {
      validated.startTimeAnchor = this.requireNonNegativeFiniteNumber(input.startTimeAnchor, 'startTimeAnchor');
    }
    if (input.buildStrategy !== undefined) {
      validated.buildStrategy = this.requireBuildStrategy(input.buildStrategy, 'buildStrategy');
    }
    if (input.contentFilters !== undefined) {
      validated.contentFilters = this.requireContentFilters(input.contentFilters, 'contentFilters');
    }
    if (input.sortOrder !== undefined) {
      validated.sortOrder = this.requireSortOrder(input.sortOrder, 'sortOrder');
    }
    if (input.lineupReplicaIndex !== undefined) {
      validated.lineupReplicaIndex = this.requireNonNegativeFiniteNumber(
        input.lineupReplicaIndex,
        'lineupReplicaIndex',
      );
    }
    if (input.shuffleSeed !== undefined) {
      validated.shuffleSeed = this.requireFiniteNumber(input.shuffleSeed, 'shuffleSeed');
    }
    if (input.phaseSeed !== undefined) {
      validated.phaseSeed = this.requireFiniteNumber(input.phaseSeed, 'phaseSeed');
    }
    if (input.blockSize !== undefined) {
      if (finalPlaybackMode !== 'block') {
        this.throwStorageValidation('blockSize may only be provided when playbackMode is block');
      }
      validated.blockSize = this.requireFiniteNumber(input.blockSize, 'blockSize');
    }
    if (input.maxEpisodeRunTimeMs !== undefined) {
      validated.maxEpisodeRunTimeMs = this.requirePositiveInteger(
        input.maxEpisodeRunTimeMs,
        'maxEpisodeRunTimeMs',
      );
    }
    if (input.minEpisodeRunTimeMs !== undefined) {
      validated.minEpisodeRunTimeMs = this.requirePositiveInteger(
        input.minEpisodeRunTimeMs,
        'minEpisodeRunTimeMs',
      );
    }

    const finalMin = validated.minEpisodeRunTimeMs ?? existingChannel?.minEpisodeRunTimeMs;
    const finalMax = validated.maxEpisodeRunTimeMs ?? existingChannel?.maxEpisodeRunTimeMs;
    if (finalMin !== undefined && finalMax !== undefined && finalMin > finalMax) {
      this.throwStorageValidation('minEpisodeRunTimeMs must be less than or equal to maxEpisodeRunTimeMs');
    }

    return validated;
  }

  private validatePlaybackMode(value: unknown, fieldName: string): PlaybackMode | undefined {
    if (value === undefined) {
      return undefined;
    }
    return this.requirePlaybackMode(value, fieldName);
  }

  private validateStartTimeAnchor(value: unknown, fallback: number): number {
    if (value === undefined) {
      return fallback;
    }
    return this.requireNonNegativeFiniteNumber(value, 'startTimeAnchor');
  }

  private requirePlaybackMode(value: unknown, fieldName: string): PlaybackMode {
    if (!isValidPlaybackMode(value)) {
      this.throwStorageValidation(`${fieldName} must be a valid playback mode`);
    }
    return value;
  }

  private requireNumberInput(value: unknown): number {
    if (typeof value !== 'number') {
      this.throwStorageValidation('number must be a number');
    }
    return value;
  }

  private requireString(value: unknown, fieldName: string): string {
    if (typeof value !== 'string') {
      this.throwStorageValidation(`${fieldName} must be a string`);
    }
    return value;
  }

  private requireNonBlankString(value: unknown, fieldName: string): string {
    const stringValue = this.requireString(value, fieldName);
    if (stringValue.trim().length === 0) {
      this.throwStorageValidation(`${fieldName} must be non-blank`);
    }
    return stringValue;
  }

  private requireBoolean(value: unknown, fieldName: string): boolean {
    if (typeof value !== 'boolean') {
      this.throwStorageValidation(`${fieldName} must be a boolean`);
    }
    return value;
  }

  private requireBuildStrategy(value: unknown, fieldName: string): BuildStrategy {
    if (!isValidBuildStrategy(value)) {
      this.throwStorageValidation(`${fieldName} must be a valid build strategy`);
    }
    return value;
  }

  private requireContentFilters(value: unknown, fieldName: string): ContentFilter[] {
    if (!isValidContentFilterArray(value)) {
      this.throwStorageValidation(`${fieldName} must be an array of valid content filters`);
    }
    return cloneContentFilters(value);
  }

  private requireSortOrder(value: unknown, fieldName: string): SortOrder {
    if (!isValidSortOrder(value)) {
      this.throwStorageValidation(`${fieldName} must be a valid sort order`);
    }
    return value;
  }

  private requireFiniteNumber(value: unknown, fieldName: string): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      this.throwStorageValidation(`${fieldName} must be a finite number`);
    }
    return value;
  }

  private requireNonNegativeFiniteNumber(value: unknown, fieldName: string): number {
    const numberValue = this.requireFiniteNumber(value, fieldName);
    if (numberValue < 0) {
      this.throwStorageValidation(`${fieldName} must be greater than or equal to 0`);
    }
    return numberValue;
  }

  private requirePositiveInteger(value: unknown, fieldName: string): number {
    if (
      typeof value !== 'number' ||
      !Number.isFinite(value) ||
      !Number.isInteger(value) ||
      value <= 0
    ) {
      this.throwStorageValidation(`${fieldName} must be a positive integer`);
    }
    return value;
  }

  private throwStorageValidation(message: string): never {
    throw new ChannelError('STORAGE_VALIDATION_FAILED', message);
  }

  private validateContentSource(source: unknown): ChannelContentSource {
    if (!isValidContentSource(source)) {
      throw new ChannelError(
        'CHANNEL_CONTENT_SOURCE_INVALID',
        CHANNEL_ERROR_MESSAGES.CHANNEL_CONTENT_SOURCE_INVALID,
      );
    }
    return source;
  }

  private validateRequestedNumber(number: number, existingChannels: Iterable<ChannelConfig>): number {
    if (!Number.isInteger(number) || number < MIN_CHANNEL_NUMBER || number > MAX_CHANNEL_NUMBER) {
      throw new ChannelError('INVALID_CHANNEL_NUMBER', CHANNEL_ERROR_MESSAGES.INVALID_CHANNEL_NUMBER);
    }
    if (this.isChannelNumberInUse(number, existingChannels)) {
      throw new ChannelError('DUPLICATE_CHANNEL_NUMBER', CHANNEL_ERROR_MESSAGES.DUPLICATE_CHANNEL_NUMBER);
    }
    return number;
  }

  private shouldAcceptReplacementChannel(
    channel: ChannelConfig,
    nextChannels: Map<string, ChannelConfig>,
    nextChannelOrder: string[],
    logger: ChannelAuthoringLogger,
  ): boolean {
    if (!isValidContentSource(channel.contentSource)) {
      logger.warn(`Skipping invalid channel ${channel.name} (${channel.id}) during replaceAllChannels`);
      return false;
    }
    if (nextChannels.has(channel.id)) {
      logger.warn(`Skipping duplicate channel ${channel.name} (${channel.id}) during replaceAllChannels`);
      return false;
    }
    if (nextChannelOrder.length >= MAX_CHANNELS) {
      logger.warn(`Skipping channel ${channel.name} (${channel.id}) due to MAX_CHANNELS limit`);
      return false;
    }
    return true;
  }
}

function fnv1a32Uint(input: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index++) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}
