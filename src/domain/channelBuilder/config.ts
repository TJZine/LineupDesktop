import {
  CHANNEL_BUILDER_MAX_LIBRARIES,
  CHANNEL_BUILDER_MIXED_SCOPE_STRATEGIES,
  CHANNEL_BUILDER_STRATEGY_KEYS,
} from './constants.js';
import type {
  ChannelBuilderStrategyConfig,
  ChannelBuilderStrategyKey,
  ChannelSetupConfig,
  ChannelSetupConfigContext,
  NormalizedChannelSetupConfig,
} from './types.js';

const identifierPattern = /^[A-Za-z0-9._-]{1,120}$/u;
const mixedScope = new Set<ChannelBuilderStrategyKey>(
  CHANNEL_BUILDER_MIXED_SCOPE_STRATEGIES,
);

const strategyConfig = {
  collections: { enabled: true, priority: 2, scope: 'per-library' },
  playlists: { enabled: true, priority: 1, scope: 'per-library' },
  genres: { enabled: true, priority: 4, scope: 'per-library' },
  directors: { enabled: true, priority: 8, scope: 'per-library' },
  decades: { enabled: true, priority: 7, scope: 'per-library' },
  recentlyAdded: { enabled: true, priority: 3, scope: 'per-library' },
  studios: { enabled: true, priority: 5, scope: 'per-library' },
  actors: { enabled: true, priority: 6, scope: 'per-library' },
} as const satisfies Readonly<Record<ChannelBuilderStrategyKey, ChannelBuilderStrategyConfig>>;

export const CHANNEL_SETUP_BEHAVIOR_DEFAULTS = Object.freeze({
  maxChannels: 200,
  minItemsPerChannel: 5,
  buildMode: 'replace',
  actorStudioCombineMode: 'separate',
  strategyConfig: Object.freeze(
    Object.fromEntries(
      CHANNEL_BUILDER_STRATEGY_KEYS.map((key) => [key, Object.freeze({ ...strategyConfig[key] })]),
    ) as Record<ChannelBuilderStrategyKey, ChannelBuilderStrategyConfig>,
  ),
  channelExpansion: Object.freeze({
    addAlternateLineups: false,
    alternateLineupCopies: 1,
    variantType: 'none',
    variantBlockSize: 3,
  }),
  seriesOrdering: Object.freeze({
    basePlaybackMode: 'shuffle',
    baseBlockSize: 3,
  }),
} as const);

type ConfigResult =
  | Readonly<{ ok: true; config: NormalizedChannelSetupConfig }>
  | Readonly<{ ok: false }>;

function hasExactKeys(
  value: unknown,
  expected: readonly string[],
): value is Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return false;
  const keys = Object.keys(value);
  return keys.length === expected.length && expected.every((key) => keys.includes(key));
}

function validIdentifier(value: unknown): value is string {
  return typeof value === 'string' && value === value.trim() && identifierPattern.test(value);
}

function validInteger(value: unknown, minimum: number, maximum: number): value is number {
  return (
    typeof value === 'number' &&
    Number.isInteger(value) &&
    Number.isSafeInteger(value) &&
    value >= minimum &&
    value <= maximum
  );
}

function cloneConfig(config: ChannelSetupConfig): NormalizedChannelSetupConfig {
  return {
    serverId: config.serverId,
    selectedLibraryIds: [...config.selectedLibraryIds],
    maxChannels: config.maxChannels,
    minItemsPerChannel: config.minItemsPerChannel,
    buildMode: config.buildMode,
    actorStudioCombineMode: config.actorStudioCombineMode,
    strategyConfig: Object.fromEntries(
      CHANNEL_BUILDER_STRATEGY_KEYS.map((key) => [key, { ...config.strategyConfig[key] }]),
    ) as Record<ChannelBuilderStrategyKey, ChannelBuilderStrategyConfig>,
    channelExpansion: { ...config.channelExpansion },
    seriesOrdering: { ...config.seriesOrdering },
  };
}

function validateContext(value: unknown): value is ChannelSetupConfigContext {
  if (!hasExactKeys(value, ['serverId', 'selectedLibraryIds'])) return false;
  if (!validIdentifier(value.serverId) || !Array.isArray(value.selectedLibraryIds)) return false;
  if (
    value.selectedLibraryIds.length < 1 ||
    value.selectedLibraryIds.length > CHANNEL_BUILDER_MAX_LIBRARIES ||
    !value.selectedLibraryIds.every(validIdentifier)
  ) {
    return false;
  }
  return new Set(value.selectedLibraryIds).size === value.selectedLibraryIds.length;
}

export function createDefaultChannelSetupConfig(context: ChannelSetupConfigContext): ConfigResult {
  if (!validateContext(context)) return { ok: false };
  return {
    ok: true,
    config: cloneConfig({
      serverId: context.serverId,
      selectedLibraryIds: context.selectedLibraryIds,
      ...CHANNEL_SETUP_BEHAVIOR_DEFAULTS,
    }),
  };
}

export function normalizeChannelSetupConfig(
  input: unknown,
  expectedContext: ChannelSetupConfigContext,
): ConfigResult {
  if (!validateContext(expectedContext)) return { ok: false };
  if (
    !hasExactKeys(input, [
      'serverId',
      'selectedLibraryIds',
      'maxChannels',
      'minItemsPerChannel',
      'buildMode',
      'actorStudioCombineMode',
      'strategyConfig',
      'channelExpansion',
      'seriesOrdering',
    ])
  ) {
    return { ok: false };
  }
  if (
    input.serverId !== expectedContext.serverId ||
    !Array.isArray(input.selectedLibraryIds) ||
    input.selectedLibraryIds.length !== expectedContext.selectedLibraryIds.length ||
    input.selectedLibraryIds.some((value, index) => value !== expectedContext.selectedLibraryIds[index])
  ) {
    return { ok: false };
  }
  if (
    !validInteger(input.maxChannels, 1, 500) ||
    !validInteger(input.minItemsPerChannel, 1, 500) ||
    (input.buildMode !== 'append' &&
      input.buildMode !== 'replace' &&
      input.buildMode !== 'merge') ||
    (input.actorStudioCombineMode !== 'separate' &&
      input.actorStudioCombineMode !== 'combined')
  ) {
    return { ok: false };
  }
  if (!hasExactKeys(input.strategyConfig, CHANNEL_BUILDER_STRATEGY_KEYS)) return { ok: false };
  const normalizedStrategies = {} as Record<
    ChannelBuilderStrategyKey,
    ChannelBuilderStrategyConfig
  >;
  for (const key of CHANNEL_BUILDER_STRATEGY_KEYS) {
    const candidate = input.strategyConfig[key];
    if (
      !hasExactKeys(candidate, ['enabled', 'priority', 'scope']) ||
      typeof candidate.enabled !== 'boolean' ||
      !validInteger(candidate.priority, 1, 100) ||
      (candidate.scope !== 'per-library' && candidate.scope !== 'cross-library') ||
      (candidate.scope === 'cross-library' && !mixedScope.has(key))
    ) {
      return { ok: false };
    }
    normalizedStrategies[key] = {
      enabled: candidate.enabled,
      priority: candidate.priority,
      scope: candidate.scope,
    };
  }
  if (
    !hasExactKeys(input.channelExpansion, [
      'addAlternateLineups',
      'alternateLineupCopies',
      'variantType',
      'variantBlockSize',
    ]) ||
    typeof input.channelExpansion.addAlternateLineups !== 'boolean' ||
    !validInteger(input.channelExpansion.alternateLineupCopies, 1, 3) ||
    !['none', 'sequential', 'block'].includes(
      String(input.channelExpansion.variantType),
    ) ||
    !validInteger(input.channelExpansion.variantBlockSize, 2, 5)
  ) {
    return { ok: false };
  }
  if (
    !hasExactKeys(input.seriesOrdering, ['basePlaybackMode', 'baseBlockSize']) ||
    !['shuffle', 'sequential', 'block'].includes(
      String(input.seriesOrdering.basePlaybackMode),
    ) ||
    !validInteger(input.seriesOrdering.baseBlockSize, 2, 5)
  ) {
    return { ok: false };
  }
  return {
    ok: true,
    config: cloneConfig({
      serverId: expectedContext.serverId,
      selectedLibraryIds: expectedContext.selectedLibraryIds,
      maxChannels: input.maxChannels,
      minItemsPerChannel: input.minItemsPerChannel,
      buildMode: input.buildMode,
      actorStudioCombineMode: input.actorStudioCombineMode,
      strategyConfig: normalizedStrategies,
      channelExpansion: {
        addAlternateLineups: input.channelExpansion.addAlternateLineups,
        alternateLineupCopies: input.channelExpansion.alternateLineupCopies,
        variantType: input.channelExpansion.variantType as 'none' | 'sequential' | 'block',
        variantBlockSize: input.channelExpansion.variantBlockSize,
      },
      seriesOrdering: {
        basePlaybackMode: input.seriesOrdering.basePlaybackMode as
          | 'shuffle'
          | 'sequential'
          | 'block',
        baseBlockSize: input.seriesOrdering.baseBlockSize,
      },
    }),
  };
}
