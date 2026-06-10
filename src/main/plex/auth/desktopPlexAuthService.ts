import type { PlexAuthProfileSummary, PlexHomeUserSummary } from '../../../contracts/plex.js';
import { sleepWithPlexAbort, throwIfPlexRequestAborted } from '../abort.js';
import { PlexAuthError, createPlexAuthHttpError } from './plexAuthError.js';
import {
  parseHomeUsersPayload,
  parsePinResponse,
  parseSwitchResponsePayload,
  parseUserResponse,
  type PlexResponsePayload,
} from './plexAuthPayloadParsers.js';
import {
  HOME_ENDPOINT_VERSIONS,
  hasProvidedPlexHomePin,
  requestFirstSupportedPlexHomeEndpoint,
  type DesktopPlexHomeEndpointVersion,
} from './plexHomeEndpointPolicy.js';
import type { DesktopPlexCredentialStore } from './desktopPlexCredentialStore.js';
import type { PlexAuthConfig, PlexAuthToken, PlexPinRequest } from './types.js';
import { toPlexAuthProfileSummary } from './types.js';

export type DesktopPlexAuthTransportAction =
  | 'request-pin'
  | 'check-pin-status'
  | 'cancel-pin'
  | 'validate-token'
  | 'get-home-users'
  | 'switch-home-user';

export interface DesktopPlexAuthTransportRequest {
  action: DesktopPlexAuthTransportAction;
  config: PlexAuthConfig;
  pinId?: number;
  token?: string;
  userId?: string;
  pin?: string | null;
  homeEndpointVersion?: DesktopPlexHomeEndpointVersion;
  signal?: AbortSignal | null;
}

export interface DesktopPlexAuthTransportResponse {
  status: number;
  payload: PlexResponsePayload | unknown;
}

export interface DesktopPlexAuthTransport {
  request(input: DesktopPlexAuthTransportRequest): Promise<DesktopPlexAuthTransportResponse>;
}

export interface DesktopPlexAuthServiceOptions {
  config: PlexAuthConfig;
  transport: DesktopPlexAuthTransport;
  credentialStore?: Pick<DesktopPlexCredentialStore, 'saveAccountCredential'>;
  nowMs?: () => number;
  pollIntervalMs?: number;
  pinTimeoutMs?: number;
  sleep?: (durationMs: number, signal?: AbortSignal | null) => Promise<void>;
}

export interface DesktopPlexPinSummary {
  id: number;
  code: string;
  expiresAtMs: number;
  clientIdentifier: string;
  claimed: boolean;
}

export interface DesktopPlexPinStatusResult {
  pin: DesktopPlexPinSummary;
  profile: PlexAuthProfileSummary | null;
}

export interface DesktopPlexTokenValidationResult {
  valid: boolean;
  profile: PlexAuthProfileSummary | null;
}

export interface DesktopPlexSwitchHomeUserResult {
  activeProfile: PlexAuthProfileSummary;
}

const DEFAULT_PIN_POLL_INTERVAL_MS = 1_000;
const DEFAULT_PIN_TIMEOUT_MS = 300_000;

/**
 * Plex auth keeps transport and credential persistence injected, validates
 * tokens before profile exposure, and commits in-memory account state only
 * after credential storage succeeds and the request remains active.
 */
export class DesktopPlexAuthService {
  private readonly config: PlexAuthConfig;
  private readonly transport: DesktopPlexAuthTransport;
  private readonly credentialStore?: Pick<DesktopPlexCredentialStore, 'saveAccountCredential'>;
  private readonly nowMs: () => number;
  private readonly pollIntervalMs: number;
  private readonly pinTimeoutMs: number;
  private readonly sleep: (durationMs: number, signal?: AbortSignal | null) => Promise<void>;
  private pendingPin: PlexPinRequest | null = null;
  private accountToken: PlexAuthToken | null = null;
  private activeToken: PlexAuthToken | null = null;
  private activeUserId: string | null = null;

  constructor(options: DesktopPlexAuthServiceOptions) {
    this.config = options.config;
    this.transport = options.transport;
    this.credentialStore = options.credentialStore;
    this.nowMs = options.nowMs ?? Date.now;
    this.pollIntervalMs = options.pollIntervalMs ?? DEFAULT_PIN_POLL_INTERVAL_MS;
    this.pinTimeoutMs = options.pinTimeoutMs ?? DEFAULT_PIN_TIMEOUT_MS;
    this.sleep = options.sleep ?? sleepWithAbort;
  }

  async requestPin(options: { signal?: AbortSignal | null } = {}): Promise<DesktopPlexPinSummary> {
    throwIfAborted(options.signal);
    const response = await this.requestTransport({
      action: 'request-pin',
      config: this.config,
      signal: options.signal ?? null,
    });
    throwIfAborted(options.signal);
    assertOkResponse(response);
    const pin = parsePinResponse(toPayloadData(response.payload), this.config.clientIdentifier);
    throwIfAborted(options.signal);
    this.pendingPin = pin;
    return toPinSummary(pin);
  }

  async checkPinStatus(
    pinId: number,
    options: { signal?: AbortSignal | null } = {},
  ): Promise<DesktopPlexPinStatusResult> {
    throwIfAborted(options.signal);
    const response = await this.requestTransport({
      action: 'check-pin-status',
      config: this.config,
      pinId,
      signal: options.signal ?? null,
    });
    throwIfAborted(options.signal);
    assertOkResponse(response);
    const pin = parsePinResponse(toPayloadData(response.payload), this.config.clientIdentifier);
    throwIfAborted(options.signal);
    this.pendingPin = pin;

    if (pin.authToken === null) {
      return { pin: toPinSummary(pin), profile: null };
    }

    throwIfAborted(options.signal);
    const token = await this.fetchUserProfile(pin.authToken, options.signal ?? null);
    throwIfAborted(options.signal);
    await this.setAccountToken(token, options.signal ?? null);
    return { pin: toPinSummary(pin), profile: toPlexAuthProfileSummary(token) };
  }

  async pollForPin(
    pinId: number,
    options: { signal?: AbortSignal | null } = {},
  ): Promise<DesktopPlexPinStatusResult> {
    const startMs = this.nowMs();
    let lastRetryableError: PlexAuthError | null = null;

    throwIfAborted(options.signal);
    while (this.nowMs() - startMs < this.pinTimeoutMs) {
      try {
        const result = await this.checkPinStatus(pinId, options);
        if (result.pin.claimed) {
          return result;
        }
        lastRetryableError = null;
      } catch (error) {
        if (!(error instanceof PlexAuthError) || !error.retryable) {
          throw error;
        }
        lastRetryableError = error;
      }

      await this.sleep(this.pollIntervalMs, options.signal ?? null);
    }

    if (lastRetryableError) {
      throw lastRetryableError;
    }
    throw new PlexAuthError('pin-timeout', 'PIN polling timeout exceeded');
  }

  async cancelPin(pinId: number, options: { signal?: AbortSignal | null } = {}): Promise<void> {
    try {
      await this.requestTransport({
        action: 'cancel-pin',
        config: this.config,
        pinId,
        signal: options.signal ?? null,
      });
    } catch {
      // Preserve upstream behavior: cancellation is best-effort.
    }

    throwIfAborted(options.signal);
    if (this.pendingPin?.id === pinId) {
      this.pendingPin = null;
    }
  }

  async validateToken(
    token: string,
    options: { signal?: AbortSignal | null } = {},
  ): Promise<DesktopPlexTokenValidationResult> {
    try {
      const authToken = await this.fetchUserProfile(token, options.signal ?? null);
      return { valid: true, profile: toPlexAuthProfileSummary(authToken) };
    } catch (error) {
      if (
        error instanceof PlexAuthError &&
        (error.code === 'auth-required' || error.code === 'auth-invalid')
      ) {
        return { valid: false, profile: null };
      }
      throw error;
    }
  }

  async restoreAccountToken(
    token: string,
    options: { signal?: AbortSignal | null } = {},
  ): Promise<PlexAuthProfileSummary> {
    const authToken = await this.fetchUserProfile(token, options.signal ?? null);
    throwIfAborted(options.signal);
    this.accountToken = authToken;
    this.activeToken = authToken;
    this.activeUserId = authToken.userId;
    return toPlexAuthProfileSummary(authToken);
  }

  async getHomeUsers(options: { signal?: AbortSignal | null } = {}): Promise<PlexHomeUserSummary[]> {
    if (!this.accountToken) {
      throw new PlexAuthError('auth-required', 'Plex account token not available');
    }
    throwIfAborted(options.signal);

    const response = await this.requestFirstSupportedHomeEndpoint({
      action: 'get-home-users',
      token: this.accountToken.token,
      signal: options.signal ?? null,
    });
    if (!response) {
      return [];
    }
    throwIfAborted(options.signal);
    assertOkResponse(response);
    const users = parseHomeUsersPayload(toPlexResponsePayload(response.payload));
    if (users.length > 0) {
      return users.map(toHomeUserSummary);
    }

    for (const endpointVersion of HOME_ENDPOINT_VERSIONS.slice(
      HOME_ENDPOINT_VERSIONS.indexOf(response.homeEndpointVersion) + 1,
    )) {
      const fallbackResponse = await this.requestFirstSupportedHomeEndpoint({
        action: 'get-home-users',
        token: this.accountToken.token,
        signal: options.signal ?? null,
        startAtEndpointVersion: endpointVersion,
      });
      if (!fallbackResponse) {
        return [];
      }
      throwIfAborted(options.signal);
      assertOkResponse(fallbackResponse);
      const fallbackUsers = parseHomeUsersPayload(toPlexResponsePayload(fallbackResponse.payload));
      if (fallbackUsers.length > 0) {
        return fallbackUsers.map(toHomeUserSummary);
      }
    }

    return [];
  }

  async switchHomeUser(
    userId: string,
    options: { pin?: string | null; signal?: AbortSignal | null } = {},
  ): Promise<DesktopPlexSwitchHomeUserResult> {
    if (!this.accountToken) {
      throw new PlexAuthError('auth-required', 'Plex account token not available');
    }
    throwIfAborted(options.signal);

    const response = await this.requestFirstSupportedHomeEndpoint({
      action: 'switch-home-user',
      token: this.accountToken.token,
      userId,
      pin: options.pin ?? null,
      signal: options.signal ?? null,
    });
    if (!response) {
      throw new PlexAuthError('resource-not-found', 'Plex Home switching is not supported');
    }
    throwIfAborted(options.signal);
    if ((response.status === 401 || response.status === 403) && hasProvidedPlexHomePin(options.pin)) {
      const validation = await this.validateToken(this.accountToken.token, { signal: options.signal ?? null });
      throwIfAborted(options.signal);
      if (validation.valid) {
        throw new PlexAuthError('auth-failed', 'Incorrect Plex Home PIN', response.status);
      }
    }
    assertOkResponse(response);
    const { authToken } = parseSwitchResponsePayload(toPlexResponsePayload(response.payload));
    const activeToken = await this.fetchUserProfile(authToken, options.signal ?? null);
    throwIfAborted(options.signal);
    this.activeToken = activeToken;
    this.activeUserId = activeToken.userId;

    return { activeProfile: toPlexAuthProfileSummary(activeToken) };
  }

  getActiveUserId(): string | null {
    return this.activeUserId;
  }

  getAccountUserId(): string | null {
    return this.accountToken?.userId ?? null;
  }

  getActiveTokenForMain(): string | null {
    return this.activeToken?.token ?? null;
  }

  getAccountTokenForMain(): string | null {
    return this.accountToken?.token ?? null;
  }

  private async fetchUserProfile(token: string, signal: AbortSignal | null): Promise<PlexAuthToken> {
    throwIfAborted(signal);
    const response = await this.requestTransport({
      action: 'validate-token',
      config: this.config,
      token,
      signal,
    });
    throwIfAborted(signal);
    assertOkResponse(response);
    return parseUserResponse(toPayloadData(response.payload), token);
  }

  private async setAccountToken(token: PlexAuthToken, signal: AbortSignal | null): Promise<void> {
    if (!this.credentialStore) {
      throw new PlexAuthError('auth-failed', 'Plex account credential store is not available');
    }

    throwIfAborted(signal);
    let saveResult: Awaited<ReturnType<DesktopPlexCredentialStore['saveAccountCredential']>>;
    try {
      saveResult = await this.credentialStore.saveAccountCredential(
        {
          accountId: token.userId,
          secretValue: token.token,
          profile: toPlexAuthProfileSummary(token),
        },
        { signal },
      );
    } catch (error) {
      throwIfAborted(signal);
      throw sanitizeAuthSeamError(error, 'auth-failed', 'Plex account credential could not be saved');
    }
    if (saveResult && !saveResult.ok) {
      throw new PlexAuthError('auth-failed', 'Plex account credential could not be saved');
    }
    throwIfAborted(signal);
    this.accountToken = token;
    this.activeToken = token;
    this.activeUserId = token.userId;
  }

  private async requestTransport(
    input: DesktopPlexAuthTransportRequest,
  ): Promise<DesktopPlexAuthTransportResponse> {
    try {
      return await this.transport.request(input);
    } catch (error) {
      throw sanitizeAuthSeamError(error, 'server-unreachable', 'Plex auth transport failed', true);
    }
  }

  private async requestFirstSupportedHomeEndpoint(input: {
    action: 'get-home-users' | 'switch-home-user';
    token: string;
    userId?: string;
    pin?: string | null;
    signal: AbortSignal | null;
    startAtEndpointVersion?: DesktopPlexHomeEndpointVersion;
  }): Promise<(DesktopPlexAuthTransportResponse & { homeEndpointVersion: DesktopPlexHomeEndpointVersion }) | null> {
    return requestFirstSupportedPlexHomeEndpoint({
      ...input,
      request: (request) =>
        this.requestTransport({
          action: input.action,
          config: this.config,
          token: request.token,
          userId: request.userId,
          pin: request.pin ?? null,
          homeEndpointVersion: request.homeEndpointVersion,
          signal: request.signal,
        }),
    });
  }
}

function assertOkResponse(response: DesktopPlexAuthTransportResponse): void {
  if (response.status < 200 || response.status >= 300) {
    throw createPlexAuthHttpError(response.status);
  }
}

function toHomeUserSummary(user: ReturnType<typeof parseHomeUsersPayload>[number]): PlexHomeUserSummary {
  return {
    id: user.id,
    title: user.title,
    admin: user.admin,
    protected: user.protected,
    ...(user.restricted === undefined ? {} : { restricted: user.restricted }),
  };
}

function sanitizeAuthSeamError(
  error: unknown,
  code: 'auth-failed' | 'server-unreachable',
  message: string,
  retryable = false,
): PlexAuthError {
  if (error instanceof PlexAuthError) {
    return error;
  }
  if (isLivePlexTransportAbortError(error)) {
    return new PlexAuthError('aborted', 'Plex auth request was aborted', undefined, { cause: error });
  }
  return new PlexAuthError(code, message, undefined, { cause: error, retryable });
}

function isLivePlexTransportAbortError(error: unknown): boolean {
  return (
    error instanceof Error &&
    error.name === 'LivePlexTransportError' &&
    'code' in error &&
    error.code === 'aborted'
  );
}

function toPayloadData(payload: PlexResponsePayload | unknown): unknown {
  if (!isPlexResponsePayload(payload)) {
    return payload;
  }
  return payload.kind === 'empty' ? undefined : payload.data;
}

function toPlexResponsePayload(payload: PlexResponsePayload | unknown): PlexResponsePayload {
  return isPlexResponsePayload(payload) ? payload : { kind: 'json', data: payload };
}

function isPlexResponsePayload(payload: PlexResponsePayload | unknown): payload is PlexResponsePayload {
  return (
    !!payload &&
    typeof payload === 'object' &&
    'kind' in payload &&
    ((payload as { kind?: unknown }).kind === 'json' ||
      (payload as { kind?: unknown }).kind === 'text' ||
      (payload as { kind?: unknown }).kind === 'empty')
  );
}

function toPinSummary(pin: PlexPinRequest): DesktopPlexPinSummary {
  return {
    id: pin.id,
    code: pin.code,
    expiresAtMs: pin.expiresAt.getTime(),
    clientIdentifier: pin.clientIdentifier,
    claimed: pin.authToken !== null,
  };
}

function throwIfAborted(signal?: AbortSignal | null): void {
  throwIfPlexRequestAborted(signal, createAbortedError);
}

function sleepWithAbort(durationMs: number, signal?: AbortSignal | null): Promise<void> {
  return sleepWithPlexAbort(durationMs, signal, createAbortedError);
}

function createAbortedError(): PlexAuthError {
  return new PlexAuthError('aborted', 'Plex auth request was aborted');
}
