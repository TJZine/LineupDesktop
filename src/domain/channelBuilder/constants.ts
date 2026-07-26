import type {
  ChannelBuilderFacetWarningCode,
  ChannelBuilderStrategyKey,
} from './types.js';

export const CHANNEL_BUILDER_STRATEGY_KEYS = Object.freeze([
  'collections',
  'playlists',
  'genres',
  'directors',
  'decades',
  'recentlyAdded',
  'studios',
  'actors',
] as const satisfies readonly ChannelBuilderStrategyKey[]);

export const CHANNEL_BUILDER_FACET_WARNING_CODES = Object.freeze([
  'FACET_CAP_REACHED',
  'FACET_DISCOVERY_TIMEOUT',
  'FACET_EMPTY',
  'FACET_MALFORMED_ENTRIES_OMITTED',
  'FACET_PARTIAL_FAILURE',
  'FACET_UNAVAILABLE',
  'TV_PEOPLE_METADATA_INCOMPLETE',
] as const satisfies readonly ChannelBuilderFacetWarningCode[]);

export const CHANNEL_BUILDER_MIXED_SCOPE_STRATEGIES = Object.freeze([
  'genres',
  'directors',
  'studios',
  'actors',
] as const satisfies readonly ChannelBuilderStrategyKey[]);

export const CHANNEL_BUILDER_MAX_CHANNELS = 500;
export const CHANNEL_BUILDER_MAX_MIN_ITEMS_PER_CHANNEL = 500;
export const CHANNEL_BUILDER_MAX_CANDIDATES = 50_000;
export const CHANNEL_BUILDER_MAX_LIBRARIES = 24;
export const CHANNEL_BUILDER_MAX_WARNINGS = 50;
export const CHANNEL_BUILDER_MAX_EXISTING_LINEUP = 500;
export const CHANNEL_BUILDER_MAX_SOURCE_DEPTH = 8;
export const CHANNEL_BUILDER_MAX_SOURCE_LEAVES = 500;

export const CHANNEL_DOMAIN_FORBIDDEN_KEYS = Object.freeze([
  'rawMediaUrl',
  'tokenizedUrl',
  'authHeaders',
  'rawAuthHeaders',
  'persistentToken',
  'credentialMaterial',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
  'localStorage',
  'storageKey',
  'currentChannelKey',
  'serverUri',
  'connectionUri',
] as const);
