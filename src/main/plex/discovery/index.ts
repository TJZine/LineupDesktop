export { DEFAULT_MIXED_CONTENT_CONFIG, PLEX_DISCOVERY_CONSTANTS } from './constants.js';
export {
  createHealthRecord,
  findFastestConnectionProbe,
  parsePlexResources,
  toRendererSafeServerSummary,
} from './discoveryDomain.js';
export {
  DesktopPlexSelectedServerStore,
  type DesktopPlexSelectedServerStoreOptions,
} from './desktopPlexSelectedServerStore.js';
export {
  DesktopPlexServerDiscovery,
  createPlexApiResource,
  type DesktopPlexConnectionProbeTransportResult,
  type DesktopPlexDiscoveryTransport,
  type DesktopPlexServerDiscoveryOptions,
} from './desktopPlexServerDiscovery.js';
export { PlexDiscoveryError, type PlexDiscoveryErrorCode } from './plexDiscoveryError.js';
export type {
  MixedContentConfig,
  PlexApiConnection,
  PlexApiResource,
  PlexConnection,
  PlexConnectionProbeOutcome,
  PlexConnectionProbeResult,
  PlexFastestConnectionProbeResult,
  PlexServer,
  PlexServerHealthRecord,
  PlexServerSelectionFailure,
  PlexServerSelectionSource,
} from './types.js';
