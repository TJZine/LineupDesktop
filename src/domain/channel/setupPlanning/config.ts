import {
  CHANNEL_SETUP_STRATEGY_KEYS,
  type ChannelSetupConfig,
  type ChannelSetupConfigDraft,
  type ChannelSetupStrategyConfig,
  type ChannelSetupStrategyKey,
} from '../../../contracts/channel.js';
import { DEFAULT_CHANNEL_SETUP_MAX, MAX_CHANNELS } from '../constants.js';

export type {
  ChannelSetupConfig,
  ChannelSetupConfigDraft,
  ChannelSetupStrategyKey,
} from '../../../contracts/channel.js';

export const DEFAULT_MIN_ITEMS_PER_CHANNEL = 5;

export const DEFAULT_CHANNEL_SETUP_STRATEGY_PRIORITIES: Readonly<Record<ChannelSetupStrategyKey, number>> = {
  playlists: 1,
  collections: 2,
  recentlyAdded: 3,
  genres: 4,
  studios: 5,
  actors: 6,
  decades: 7,
  directors: 8,
};

export const MIXED_SCOPE_CHANNEL_SETUP_STRATEGIES: ReadonlySet<ChannelSetupStrategyKey> = new Set([
  'genres',
  'directors',
  'studios',
  'actors',
]);

export function normalizeChannelSetupConfig(draft: ChannelSetupConfigDraft): ChannelSetupConfig {
  const selectedLibraryIds = Array.from(new Set(
    (Array.isArray(draft.selectedLibraryIds) ? draft.selectedLibraryIds : [])
      .filter((id): id is string => typeof id === 'string')
      .map((id) => id.trim())
      .filter((id) => id.length > 0),
  ));
  const strategyConfig = CHANNEL_SETUP_STRATEGY_KEYS.reduce<Record<ChannelSetupStrategyKey, ChannelSetupStrategyConfig>>(
    (normalized, strategy) => {
      const candidate = draft.strategyConfig?.[strategy];
      normalized[strategy] = {
        enabled: typeof candidate?.enabled === 'boolean' ? candidate.enabled : true,
        priority: finiteInteger(candidate?.priority, DEFAULT_CHANNEL_SETUP_STRATEGY_PRIORITIES[strategy], 1),
        scope: MIXED_SCOPE_CHANNEL_SETUP_STRATEGIES.has(strategy) && candidate?.scope === 'cross-library'
          ? 'cross-library'
          : 'per-library',
      };
      return normalized;
    },
    {} as Record<ChannelSetupStrategyKey, ChannelSetupStrategyConfig>,
  );

  const variantType = draft.channelExpansion?.variantType;
  const basePlaybackMode = draft.seriesOrdering?.basePlaybackMode;
  return {
    selectedLibraryIds,
    maxChannels: finiteInteger(draft.maxChannels, DEFAULT_CHANNEL_SETUP_MAX, 1, MAX_CHANNELS),
    minItemsPerChannel: finiteInteger(draft.minItemsPerChannel, DEFAULT_MIN_ITEMS_PER_CHANNEL, 1),
    buildMode: draft.buildMode === 'append' || draft.buildMode === 'merge' ? draft.buildMode : 'replace',
    actorStudioCombineMode: draft.actorStudioCombineMode === 'combined' ? 'combined' : 'separate',
    strategyConfig,
    channelExpansion: {
      addAlternateLineups: draft.channelExpansion?.addAlternateLineups === true,
      alternateLineupCopies: finiteInteger(draft.channelExpansion?.alternateLineupCopies, 1, 1, 3),
      variantType: variantType === 'sequential' || variantType === 'block' ? variantType : 'none',
      variantBlockSize: finiteInteger(draft.channelExpansion?.variantBlockSize, 3, 2, 5),
    },
    seriesOrdering: {
      basePlaybackMode: basePlaybackMode === 'sequential' || basePlaybackMode === 'block'
        ? basePlaybackMode
        : 'shuffle',
      baseBlockSize: finiteInteger(draft.seriesOrdering?.baseBlockSize, 3, 2, 5),
    },
  };
}

function finiteInteger(value: unknown, fallback: number, minimum: number, maximum = Number.MAX_SAFE_INTEGER): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.floor(value)));
}
