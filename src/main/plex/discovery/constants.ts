import type { MixedContentConfig } from './types.js';

export const PLEX_DISCOVERY_CONSTANTS = {
  identityEndpoint: '/identity',
  serverCacheDurationMs: 300_000,
  connectionTestTimeoutMs: 10_000,
} as const;

export const DEFAULT_MIXED_CONTENT_CONFIG: MixedContentConfig = {
  preferHttps: true,
  tryHttpsUpgrade: true,
  allowLocalHttp: true,
};
