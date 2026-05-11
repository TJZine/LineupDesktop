import type { PlexAuthConfig } from './types.js';

export const DESKTOP_PLEX_AUTH_METADATA = {
  product: 'Lineup Desktop',
  version: '0.0.0',
  platform: 'Desktop',
  device: 'Desktop',
  deviceName: 'Lineup Desktop',
} as const;

export interface PlexIdentityHeaderOptions {
  platformVersion?: string | null;
  deviceName?: string | null;
  model?: string | null;
}

export function createDesktopPlexAuthConfig(options: {
  clientIdentifier: string;
  platformVersion?: string;
  deviceName?: string;
}): PlexAuthConfig {
  return {
    ...DESKTOP_PLEX_AUTH_METADATA,
    clientIdentifier: options.clientIdentifier,
    platformVersion: options.platformVersion ?? 'desktop',
    deviceName: options.deviceName ?? DESKTOP_PLEX_AUTH_METADATA.deviceName,
  };
}

export function createPlexIdentityHeaders(
  metadata: PlexAuthConfig,
  options: PlexIdentityHeaderOptions = {},
): Record<string, string> {
  const headers: Record<string, string> = {
    'X-Plex-Client-Identifier': metadata.clientIdentifier,
    'X-Plex-Product': metadata.product,
    'X-Plex-Version': metadata.version,
    'X-Plex-Platform': metadata.platform,
    'X-Plex-Platform-Version': options.platformVersion ?? metadata.platformVersion,
    'X-Plex-Device': metadata.device,
    'X-Plex-Device-Name': options.deviceName ?? metadata.deviceName,
  };

  if (options.model) {
    headers['X-Plex-Model'] = options.model;
  }

  return headers;
}

export function buildPlexAuthRequestHeaders(
  config: PlexAuthConfig,
  options: { token?: string; platformVersion?: string; deviceName?: string } = {},
): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    ...createPlexIdentityHeaders(config, options),
  };

  if (options.token) {
    headers['X-Plex-Token'] = options.token;
  }

  return headers;
}
