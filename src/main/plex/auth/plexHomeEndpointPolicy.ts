import { PlexAuthError } from './plexAuthError.js';
import type { DesktopPlexAuthTransportResponse } from './desktopPlexAuthService.js';

export type DesktopPlexHomeEndpointVersion = 'v2' | 'v1';

export const HOME_ENDPOINT_VERSIONS: readonly DesktopPlexHomeEndpointVersion[] = ['v2', 'v1'];

export interface PlexHomeEndpointTransportInput {
  action: 'get-home-users' | 'switch-home-user';
  token: string;
  userId?: string;
  pin?: string | null;
  homeEndpointVersion: DesktopPlexHomeEndpointVersion;
  signal: AbortSignal | null;
}

export type PlexHomeEndpointResponse = DesktopPlexAuthTransportResponse & {
  homeEndpointVersion: DesktopPlexHomeEndpointVersion;
};

export async function requestFirstSupportedPlexHomeEndpoint(input: {
  action: 'get-home-users' | 'switch-home-user';
  token: string;
  userId?: string;
  pin?: string | null;
  signal: AbortSignal | null;
  startAtEndpointVersion?: DesktopPlexHomeEndpointVersion;
  request: (request: PlexHomeEndpointTransportInput) => Promise<DesktopPlexAuthTransportResponse>;
}): Promise<PlexHomeEndpointResponse | null> {
  const startIndex =
    input.startAtEndpointVersion === undefined
      ? 0
      : Math.max(0, HOME_ENDPOINT_VERSIONS.indexOf(input.startAtEndpointVersion));
  let lastRetryableResponse: PlexHomeEndpointResponse | null = null;
  let lastRetryableError: PlexAuthError | null = null;

  for (const homeEndpointVersion of HOME_ENDPOINT_VERSIONS.slice(startIndex)) {
    throwIfAborted(input.signal);
    try {
      const response = await input.request({
        action: input.action,
        token: input.token,
        userId: input.userId,
        pin: input.pin ?? null,
        homeEndpointVersion,
        signal: input.signal,
      });
      throwIfAborted(input.signal);
      if (isUnsupportedHomeEndpointStatus(response.status)) {
        continue;
      }
      if (shouldTryNextHomeEndpoint(response.status)) {
        lastRetryableResponse = { ...response, homeEndpointVersion };
        lastRetryableError = null;
        continue;
      }
      return { ...response, homeEndpointVersion };
    } catch (error) {
      throwIfAborted(input.signal);
      if (error instanceof PlexAuthError && isRetryableHomeEndpointError(error)) {
        lastRetryableError = error;
        continue;
      }
      throw error;
    }
  }

  if (lastRetryableError) {
    throw lastRetryableError;
  }
  return lastRetryableResponse;
}

export function hasProvidedPlexHomePin(pin: string | null | undefined): boolean {
  return typeof pin === 'string' && pin.trim().length > 0;
}

function isUnsupportedHomeEndpointStatus(status: number): boolean {
  return status === 404 || status === 405;
}

function shouldTryNextHomeEndpoint(status: number): boolean {
  return (status < 200 || status >= 300) && status !== 401 && status !== 403;
}

function isRetryableHomeEndpointError(error: PlexAuthError): boolean {
  return (
    error.code === 'server-unreachable' ||
    error.code === 'server-error' ||
    error.code === 'rate-limited'
  );
}

function throwIfAborted(signal: AbortSignal | null): void {
  if (signal?.aborted) {
    throw new PlexAuthError('aborted', 'Plex auth request was aborted');
  }
}
