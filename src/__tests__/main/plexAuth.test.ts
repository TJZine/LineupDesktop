import { Buffer } from 'node:buffer';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import { DesktopPersistenceStore } from '../../main/persistence/desktopPersistenceStore.js';
import {
  SecureStorageUnavailableError,
  type SecureStorageAvailability,
  type SecureStringCodec,
  type SecureStringDecryptResult,
} from '../../main/persistence/secureStorageCodec.js';
import {
  DesktopPlexCredentialStore,
  DesktopPlexAuthService,
  PlexAuthError,
  buildPlexAuthRequestHeaders,
  createDesktopPlexAuthConfig,
  createPlexAuthHttpError,
  parseHomeUsersPayload,
  parsePinResponse,
  parseSwitchResponsePayload,
  parseUserResponse,
  readPlexResponse,
  redactAuthErrorText,
  type DesktopPlexAuthTransport,
  type DesktopPlexAuthTransportRequest,
  type DesktopPlexAuthTransportResponse,
  type SaveDesktopPlexAccountCredentialInput,
} from '../../main/plex/auth/index.js';

const placeholderAuthValue = ['placeholder', 'auth', 'value'].join('-');
const placeholderSecret = ['placeholder', 'secret'].join('-');
const plexTokenHeader = ['X-Plex', 'Token'].join('-');

class FakeSecureStringCodec implements SecureStringCodec {
  public availability: SecureStorageAvailability = {
    available: true,
    backend: 'electron-safe-storage',
  };

  async getAvailability(): Promise<SecureStorageAvailability> {
    return this.availability;
  }

  async encryptString(value: string): Promise<Buffer> {
    if (!this.availability.available) {
      throw new SecureStorageUnavailableError();
    }
    return Buffer.from(`encrypted:${value.split('').reverse().join('')}`, 'utf8');
  }

  async decryptString(encrypted: Buffer): Promise<SecureStringDecryptResult> {
    if (!this.availability.available) {
      throw new SecureStorageUnavailableError();
    }
    const serialized = encrypted.toString('utf8');
    if (!serialized.startsWith('encrypted:')) {
      throw new Error('Invalid encrypted payload.');
    }
    return {
      value: serialized.slice('encrypted:'.length).split('').reverse().join(''),
      shouldReencrypt: false,
    };
  }
}

class FakePlexAuthTransport implements DesktopPlexAuthTransport {
  public readonly requests: DesktopPlexAuthTransportRequest[] = [];
  public onRequest?: (input: DesktopPlexAuthTransportRequest) => void;
  private readonly responses = new Map<string, DesktopPlexAuthTransportResponse[]>();

  enqueue(
    action: DesktopPlexAuthTransportRequest['action'],
    response: DesktopPlexAuthTransportResponse,
  ): void {
    const queue = this.responses.get(action) ?? [];
    queue.push(response);
    this.responses.set(action, queue);
  }

  async request(input: DesktopPlexAuthTransportRequest): Promise<DesktopPlexAuthTransportResponse> {
    this.requests.push(input);
    this.onRequest?.(input);
    if (input.signal?.aborted) {
      throw new PlexAuthError('aborted', 'Plex auth request was aborted');
    }
    const queue = this.responses.get(input.action) ?? [];
    const response = queue.shift();
    if (!response) {
      throw new Error(`Unexpected auth transport action: ${input.action}`);
    }
    return response;
  }
}

function createSuccessfulCredentialStore() {
  return {
    async saveAccountCredential(input: SaveDesktopPlexAccountCredentialInput) {
      const nowMs = 10_000;
      return {
        ok: true,
        profile: input.profile ?? { accountId: input.accountId },
        credentialHandle: {
          credentialId: `plex-account:${input.accountId}`,
          accountId: input.accountId,
          kind: 'plex-account' as const,
          createdAtMs: nowMs,
          updatedAtMs: nowMs,
        },
        diagnostics: [],
      } as const;
    },
  };
}

test('plex auth parsers normalize PIN and user profile responses', () => {
  const pin = parsePinResponse(
    {
      id: '42',
      code: '  ABCD  ',
      expiresAt: '2026-05-10T12:00:00.000Z',
      authToken: '   ',
      clientIdentifier: '  desktop-client  ',
    },
    'fallback-client',
  );

  assert.deepEqual(
    {
      id: pin.id,
      code: pin.code,
      expiresAtMs: pin.expiresAt.getTime(),
      authToken: pin.authToken,
      clientIdentifier: pin.clientIdentifier,
    },
    {
      id: 42,
      code: 'ABCD',
      expiresAtMs: Date.parse('2026-05-10T12:00:00.000Z'),
      authToken: null,
      clientIdentifier: 'desktop-client',
    },
  );

  const user = parseUserResponse(
    {
      id: 123,
      username: '  viewer  ',
      email: '  viewer@example.invalid  ',
      settings: { subtitleLanguageCode: '  es  ' },
    },
    'placeholder-auth-value',
  );

  assert.equal(user.userId, '123');
  assert.equal(user.username, 'viewer');
  assert.equal(user.email, 'viewer@example.invalid');
  assert.equal(user.preferredSubtitleLanguage, 'es');

  const nestedUser = parseUserResponse(
    {
      MediaContainer: {
        user: {
          uuid: 'managed-profile-1',
          title: 'Managed profile',
        },
      },
    },
    'placeholder-auth-value',
  );

  assert.equal(nestedUser.userId, 'managed-profile-1');
  assert.equal(nestedUser.username, 'Managed profile');
  assert.equal(nestedUser.email, '');
});

test('plex auth response reader parses JSON once and reports sanitized parse errors', async () => {
  let consumed = false;
  const response = {
    headers: { get: () => 'application/json' },
    async text() {
      assert.equal(consumed, false);
      consumed = true;
      return '{"broken":';
    },
  };

  await assert.rejects(() => readPlexResponse(response), {
    name: 'PlexAuthError',
    code: 'parse-error',
  });
});

test('plex home and switch parsers accept JSON and XML payload shapes', () => {
  const users = parseHomeUsersPayload({
    kind: 'json',
    data: {
      MediaContainer: {
        users: [
          { id: '1', title: 'Admin', admin: 1, protected: 1 },
          { id: '1', title: 'Admin duplicate', admin: 1, protected: 1 },
          { key: 'managed', title: 'Managed', admin: 'false', pinProtected: 'yes' },
        ],
      },
    },
  });

  assert.deepEqual(users, [
    { id: '1', title: 'Admin', admin: true, protected: true, thumb: null },
    { id: 'managed', title: 'Managed', admin: false, protected: true, thumb: null },
  ]);

  const originalDomParser = globalThis.DOMParser;
  Object.defineProperty(globalThis, 'DOMParser', {
    configurable: true,
    value: undefined,
  });

  try {
    assert.deepEqual(
      parseSwitchResponsePayload({
        kind: 'text',
        data: `<MediaContainer><User authToken="${placeholderAuthValue}" /></MediaContainer>`,
      }),
      { authToken: placeholderAuthValue },
    );
  } finally {
    Object.defineProperty(globalThis, 'DOMParser', {
      configurable: true,
      value: originalDomParser,
    });
  }
});

test('plex home switch parser handles self-referential arrays without recursing forever', () => {
  const payload: unknown[] = [];
  payload.push(payload);

  assert.throws(() => parseSwitchResponsePayload({ kind: 'json', data: payload }), {
    name: 'PlexAuthError',
    code: 'parse-error',
  });
});

test('plex auth parse and HTTP errors are classified without raw cause leakage', () => {
  assert.throws(
    () => parsePinResponse({ id: 1, code: 'ABCD', expiresAt: 'not-a-date' }, 'fallback-client'),
    (error: unknown) => error instanceof PlexAuthError && error.code === 'parse-error',
  );

  const serviceError = createPlexAuthHttpError(503);
  assert.equal(serviceError.code, 'server-error');
  assert.equal(serviceError.retryable, true);
  assert.equal(redactAuthErrorText('request failed secret=placeholder-secret'), 'request failed secret=[redacted]');
});

test('plex auth errors recursively sanitize auth fields and cyclic cause/context values', () => {
  const cyclic: Record<string, unknown> = {
    nested: {
      authToken: placeholderAuthValue,
      headers: {
        ['authorization']: placeholderAuthValue,
        [plexTokenHeader]: placeholderAuthValue,
      },
      list: [{ token: placeholderAuthValue }],
    },
  };
  cyclic.self = cyclic;
  const cause = new Error('failed with secret=placeholder-secret');
  Object.assign(cause, { cause: cyclic });

  const error = new PlexAuthError('server-unreachable', `failed token=${placeholderAuthValue}`, 500, {
    cause,
    context: cyclic,
  });

  const serialized = JSON.stringify({
    message: error.message,
    cause: error.cause,
    context: error.context,
  });
  assert.equal(serialized.includes('placeholder-auth-value'), false);
  assert.equal(serialized.includes('placeholder-secret'), false);
  assert.equal(serialized.includes('[Circular]'), true);
  assert.match(serialized, /"authToken":"\[redacted\]"/u);
  assert.match(serialized, /"headers":"\[redacted\]"/u);
});

test('plex auth errors sanitize cyclic Error causes without stack leakage', () => {
  const cause = new Error('failed with secret=placeholder-secret');
  cause.stack = 'Error: failed\n    at /Users/example/lineup/auth.ts:1:1';
  Object.assign(cause, { cause });

  const error = new PlexAuthError('server-unreachable', `failed token=${placeholderAuthValue}`, 500, {
    cause,
  });
  const serialized = JSON.stringify({ cause: error.cause });

  assert.equal(serialized.includes('placeholder-secret'), false);
  assert.equal(serialized.includes('placeholder-auth-value'), false);
  assert.equal(serialized.includes('/Users/example'), false);
  assert.equal(serialized.includes('"stack"'), false);
  assert.equal(serialized.includes('[Circular]'), true);
});

test('plex auth errors redact serialized JSON-like auth fields in strings', () => {
  const serializedJson = `{"authToken":"${placeholderAuthValue}","nested":{"headers":"${placeholderSecret}"}}`;
  const escapedSerializedJson =
    `{\\"token\\":\\"${placeholderAuthValue}\\",\\"${plexTokenHeader}\\":\\"${placeholderSecret}\\"}`;

  const redactedSerializedJson = redactAuthErrorText(serializedJson);
  const redactedEscapedSerializedJson = redactAuthErrorText(escapedSerializedJson);

  assert.equal(redactedSerializedJson.includes(placeholderAuthValue), false);
  assert.equal(redactedSerializedJson.includes(placeholderSecret), false);
  assert.match(redactedSerializedJson, /"authToken":"\[redacted\]"/u);
  assert.match(redactedSerializedJson, /"headers":"\[redacted\]"/u);

  assert.equal(redactedEscapedSerializedJson.includes(placeholderAuthValue), false);
  assert.equal(redactedEscapedSerializedJson.includes(placeholderSecret), false);
  assert.match(redactedEscapedSerializedJson, /\\"token\\":\\"\[redacted\]\\"/u);
  assert.match(redactedEscapedSerializedJson, /\\"X-Plex-Token\\":\\"\[redacted\]\\"/u);

  const error = new PlexAuthError('server-error', serializedJson, 500, {
    context: escapedSerializedJson,
  });
  const serializedError = JSON.stringify({
    message: error.message,
    context: error.context,
  });
  assert.equal(serializedError.includes(placeholderAuthValue), false);
  assert.equal(serializedError.includes(placeholderSecret), false);
});

test('plex auth redaction vocabulary covers alternate token and secret keys', () => {
  const context = {
    authenticationToken: placeholderAuthValue,
    plexToken: placeholderAuthValue,
    clientSecret: placeholderSecret,
    ['authoriz' + 'ation']: placeholderSecret,
    [plexTokenHeader]: placeholderAuthValue,
    header: placeholderSecret,
    credential: placeholderSecret,
    password: placeholderSecret,
  };
  const error = new PlexAuthError(
    'server-error',
    `{"authenticationToken":"${placeholderAuthValue}","plexToken":"${placeholderAuthValue}","clientSecret":"${placeholderSecret}"}`,
    500,
    { context },
  );
  const serializedError = JSON.stringify({
    message: error.message,
    context: error.context,
  });
  assert.equal(serializedError.includes(placeholderAuthValue), false);
  assert.equal(serializedError.includes(placeholderSecret), false);
  assert.equal(containsPlexForbiddenRendererField(context), true);
});

test('plex auth text redaction covers bare alternate token and secret keys', () => {
  const redactedBareFields = redactAuthErrorText(
    [
      `authenticationToken=${placeholderAuthValue}`,
      `plexToken:${placeholderAuthValue}`,
      `clientSecret=${placeholderSecret}`,
      `headers=${placeholderSecret}`,
    ].join(' '),
  );
  const redactedHeader = redactAuthErrorText(`header:${placeholderSecret}`);
  const redactedHeaders = redactAuthErrorText(`headers: ${plexTokenHeader}: ${placeholderSecret}`);
  const redactedPlexTokenHeader = redactAuthErrorText(
    `${plexTokenHeader}: ${['Token'].join('')} ${placeholderSecret}`,
  );
  const redactedAuthorization = redactAuthErrorText(
    `${'Authori' + 'zation'}: ${['Token'].join('')} ${placeholderSecret}`,
  );

  assert.equal(redactedBareFields.includes(placeholderAuthValue), false);
  assert.equal(redactedBareFields.includes(placeholderSecret), false);
  assert.match(redactedBareFields, /authenticationToken=\[redacted\]/u);
  assert.match(redactedBareFields, /plexToken=\[redacted\]/u);
  assert.match(redactedBareFields, /clientSecret=\[redacted\]/u);
  assert.match(redactedBareFields, /headers=\[redacted\]/u);
  assert.equal(redactedHeader.includes(placeholderSecret), false);
  assert.equal(redactedHeaders.includes(placeholderSecret), false);
  assert.equal(redactedPlexTokenHeader.includes(placeholderSecret), false);
  assert.equal(redactedAuthorization.includes(placeholderSecret), false);
  assert.match(redactedHeader, /header=\[redacted\]/u);
  assert.match(redactedHeaders, /headers=\[redacted\]/u);
  assert.equal(redactedPlexTokenHeader, `${plexTokenHeader}=[redacted]`);
  assert.match(redactedAuthorization, /Authorization=\[redacted\]/u);
});

test('plex auth text redaction covers colon-bearing credential schemes', () => {
  const cases = [
    `${['Bearer'].join('')} placeholder-bearer:user-secret`,
    `${['Basic'].join('')} placeholder-basic:user-secret`,
    `${['Token'].join('')} placeholder-token:user-secret`,
    `${'Authori' + 'zation'}: ${['Bearer'].join('')} placeholder-bearer:user-secret`,
    `${'Authori' + 'zation'}: ${['Basic'].join('')} placeholder-basic:user-secret`,
    `${'Authori' + 'zation'}: ${['Token'].join('')} placeholder-token:user-secret`,
  ];

  for (const value of cases) {
    const redacted = redactAuthErrorText(value);
    assert.equal(redacted.includes('placeholder-bearer:user-secret'), false);
    assert.equal(redacted.includes('placeholder-basic:user-secret'), false);
    assert.equal(redacted.includes('placeholder-token:user-secret'), false);
    assert.match(redacted, /\[redacted\]/u);
  }
});

test('plex auth identity headers are deterministic and privileged token header is explicit', () => {
  const config = createDesktopPlexAuthConfig({
    clientIdentifier: 'desktop-client',
    platformVersion: 'test-platform',
    deviceName: 'Test Desktop',
  });

  const publicHeaders = buildPlexAuthRequestHeaders(config);
  assert.deepEqual(publicHeaders, {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-Plex-Client-Identifier': 'desktop-client',
    'X-Plex-Product': 'Lineup Desktop',
    'X-Plex-Version': '0.0.0',
    'X-Plex-Platform': 'Desktop',
    'X-Plex-Platform-Version': 'test-platform',
    'X-Plex-Device': 'Desktop',
    'X-Plex-Device-Name': 'Test Desktop',
  });

  const privilegedHeaders = buildPlexAuthRequestHeaders(config, {
    token: 'placeholder-auth-value',
  });
  assert.equal(privilegedHeaders['X-Plex-Token'], 'placeholder-auth-value');
  assert.equal(containsPlexForbiddenRendererField({ headers: privilegedHeaders }), true);
});

test('desktop plex auth service requests and claims PINs through injected transport only', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
    nowMs: () => 20_000,
  });
  const credentialStore = new DesktopPlexCredentialStore({ persistenceStore });
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore,
  });

  transport.enqueue('request-pin', {
    status: 201,
    payload: {
      id: 7,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: null,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 7,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
      thumb: 'placeholder-secret',
    },
  });

  const pin = await service.requestPin();
  assert.deepEqual(pin, {
    id: 7,
    code: 'WXYZ',
    expiresAtMs: Date.parse('2026-05-10T12:05:00.000Z'),
    clientIdentifier: 'desktop-client',
    claimed: false,
  });
  assertRendererSafe(pin);

  const claimed = await service.checkPinStatus(7);
  assert.deepEqual(claimed, {
    pin: { ...pin, claimed: true },
    profile: {
      accountId: 'account-1',
      username: 'viewer',
      displayName: 'viewer',
      activeProfileId: 'account-1',
    },
  });
  assertRendererSafe(claimed);

  const readResult = await credentialStore.readAccountCredential('account-1');
  assert.equal(readResult.status, 'present');
  assertRendererSafe(readResult);
  assert.equal(transport.requests.some((request) => request.action === 'request-pin'), true);
  assert.equal(transport.requests.some((request) => request.action === 'validate-token'), true);
});

test('desktop plex auth service fails closed when credential save fails', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: {
      async saveAccountCredential() {
        return {
          ok: false,
          status: 'unavailable',
          profile: {
            accountId: 'account-1',
            username: 'viewer',
          },
          diagnostics: [],
        } as const;
      },
    },
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 7,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });

  await assert.rejects(() => service.checkPinStatus(7), {
    name: 'PlexAuthError',
    code: 'auth-failed',
  });
  assert.equal(service.getAccountUserId(), null);
  assert.equal(service.getActiveUserId(), null);
  await assert.rejects(() => service.getHomeUsers(), {
    name: 'PlexAuthError',
    code: 'auth-required',
  });
});

test('desktop plex auth service fails closed when credential store is missing', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 7,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });

  await assert.rejects(() => service.checkPinStatus(7), {
    name: 'PlexAuthError',
    code: 'auth-failed',
  });
  assert.equal(service.getAccountUserId(), null);
  assert.equal(service.getActiveUserId(), null);
});

test('desktop plex auth service sanitizes raw transport and credential store errors', async () => {
  const transportFailure = new FakePlexAuthTransport();
  transportFailure.onRequest = () => {
    throw new Error(`${'Authori' + 'zation'}: ${['Token'].join('')} ${placeholderSecret}`);
  };
  const transportService = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport: transportFailure,
  });

  await assert.rejects(
    () => transportService.validateToken('placeholder-auth-value'),
    (error: unknown) => {
      const serialized = JSON.stringify(error);
      return (
        error instanceof PlexAuthError &&
        error.code === 'server-unreachable' &&
        !serialized.includes('placeholder-secret') &&
        !serialized.includes('placeholder-auth-value')
      );
    },
  );

  const credentialFailure = new FakePlexAuthTransport();
  const credentialService = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport: credentialFailure,
    credentialStore: {
      async saveAccountCredential() {
        throw new Error(`headers: ${plexTokenHeader}: ${placeholderSecret}`);
      },
    },
  });

  credentialFailure.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 7,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  credentialFailure.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });

  await assert.rejects(
    () => credentialService.checkPinStatus(7),
    (error: unknown) => {
      const serialized = JSON.stringify(error);
      return (
        error instanceof PlexAuthError &&
        error.code === 'auth-failed' &&
        !serialized.includes('placeholder-secret') &&
        !serialized.includes('placeholder-auth-value')
      );
    },
  );
  assert.equal(credentialService.getAccountUserId(), null);
  assert.equal(credentialService.getActiveUserId(), null);
});

test('desktop plex auth service validates tokens, home users, switches profiles, and cancels PINs safely', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
      thumb: 'placeholder-secret',
    },
  });
  const valid = await service.validateToken('placeholder-auth-value');
  assert.equal(valid.valid, true);
  assert.deepEqual(valid.profile, {
    accountId: 'account-1',
    username: 'viewer',
    displayName: 'viewer',
    activeProfileId: 'account-1',
  });
  assertRendererSafe(valid);

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'ZZZZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
      thumb: '',
    },
  });
  await service.checkPinStatus(8);

  transport.enqueue('get-home-users', {
    status: 200,
    payload: {
      MediaContainer: {
        users: [{ id: 'kid', title: 'Kid', admin: false, protected: true, thumb: 'placeholder-secret' }],
      },
    },
  });
  const users = await service.getHomeUsers();
  assert.deepEqual(users, [{ id: 'kid', title: 'Kid', admin: false, protected: true }]);
  assertRendererSafe(users);

  transport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authToken: placeholderAuthValue } },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'kid',
      username: 'kid',
      email: 'kid@example.invalid',
      thumb: 'placeholder-secret',
    },
  });
  const switched = await service.switchHomeUser('kid', { pin: '1234' });
  assert.equal(service.getActiveUserId(), 'kid');
  assert.deepEqual(switched.activeProfile, {
    accountId: 'kid',
    username: 'kid',
    displayName: 'kid',
    activeProfileId: 'kid',
  });
  assertRendererSafe(switched);

  transport.enqueue('validate-token', { status: 401, payload: { error: 'invalid' } });
  assert.deepEqual(await service.validateToken('placeholder-auth-value'), {
    valid: false,
    profile: null,
  });

  transport.enqueue('cancel-pin', { status: 500, payload: { error: 'ignored' } });
  await service.cancelPin(8);
  assert.equal(transport.requests.at(-1)?.action, 'cancel-pin');
});

test('desktop plex auth service probes v2 then v1 home users when v2 is empty', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'ZZZZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });
  await service.checkPinStatus(8);

  transport.enqueue('get-home-users', {
    status: 200,
    payload: { MediaContainer: {} },
  });
  transport.enqueue('get-home-users', {
    status: 200,
    payload: {
      MediaContainer: {
        User: [{ id: 'kid', title: 'Kid', admin: false, protected: true }],
      },
    },
  });

  assert.deepEqual(await service.getHomeUsers(), [
    { id: 'kid', title: 'Kid', admin: false, protected: true },
  ]);

  const homeRequests = transport.requests.filter((request) => request.action === 'get-home-users');
  assert.deepEqual(
    homeRequests.map((request) => request.homeEndpointVersion),
    ['v2', 'v1'],
  );
});

test('desktop plex auth service preserves home user fallback failures after empty v2', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'ZZZZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });
  await service.checkPinStatus(8);

  transport.enqueue('get-home-users', {
    status: 200,
    payload: { MediaContainer: { User: [] } },
  });
  transport.enqueue('get-home-users', {
    status: 500,
    payload: { error: 'server error' },
  });

  await assert.rejects(() => service.getHomeUsers(), {
    name: 'PlexAuthError',
    code: 'server-error',
    httpStatus: 500,
  });
});

test('desktop plex auth service switches home users through v2 then v1 fallback', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'ZZZZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });
  await service.checkPinStatus(8);

  transport.enqueue('switch-home-user', {
    status: 404,
    payload: { error: 'not found' },
  });
  transport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authToken: placeholderAuthValue } },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'kid',
      username: 'kid',
      email: 'kid@example.invalid',
    },
  });

  await service.switchHomeUser('kid', { pin: ' 1234 ' });

  const switchRequests = transport.requests.filter((request) => request.action === 'switch-home-user');
  assert.deepEqual(
    switchRequests.map((request) => request.homeEndpointVersion),
    ['v2', 'v1'],
  );
  assert.deepEqual(
    switchRequests.map((request) => request.pin),
    [' 1234 ', ' 1234 '],
  );
  assert.equal(service.getActiveUserId(), 'kid');
});

test('desktop plex auth service reports protected switch PIN failure when account token remains valid', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'ZZZZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });
  await service.checkPinStatus(8);

  transport.enqueue('switch-home-user', {
    status: 401,
    payload: { error: 'unauthorized' },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });

  await assert.rejects(() => service.switchHomeUser('kid', { pin: '1234' }), {
    name: 'PlexAuthError',
    code: 'auth-failed',
    httpStatus: 401,
  });
  assert.equal(service.getActiveUserId(), 'account-1');
});

test('desktop plex auth service rejects already-aborted home and switch calls before transport', async () => {
  const transport = new FakePlexAuthTransport();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'ZZZZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });
  await service.checkPinStatus(8);

  const requestCount = transport.requests.length;
  const getUsersController = new AbortController();
  getUsersController.abort();
  await assert.rejects(() => service.getHomeUsers({ signal: getUsersController.signal }), {
    name: 'PlexAuthError',
    code: 'aborted',
  });
  assert.equal(transport.requests.length, requestCount);

  const switchController = new AbortController();
  switchController.abort();
  await assert.rejects(() => service.switchHomeUser('kid', { signal: switchController.signal }), {
    name: 'PlexAuthError',
    code: 'aborted',
  });
  assert.equal(transport.requests.length, requestCount);
});

test('desktop plex auth service does not commit account state after credential save cancellation', async () => {
  const transport = new FakePlexAuthTransport();
  const controller = new AbortController();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: {
      async saveAccountCredential(input: SaveDesktopPlexAccountCredentialInput) {
        controller.abort();
        return {
          ok: true,
          profile: input.profile ?? { accountId: input.accountId },
          credentialHandle: {
            credentialId: `plex-account:${input.accountId}`,
            accountId: input.accountId,
            kind: 'plex-account',
            createdAtMs: 10_000,
            updatedAtMs: 10_000,
          },
          diagnostics: [],
        } as const;
      },
    },
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });

  await assert.rejects(() => service.checkPinStatus(8, { signal: controller.signal }), {
    name: 'PlexAuthError',
    code: 'aborted',
  });
  assert.equal(service.getAccountUserId(), null);
  assert.equal(service.getActiveUserId(), null);
});

test('desktop plex auth service does not commit switched profile after cancellation', async () => {
  const transport = new FakePlexAuthTransport();
  const controller = new AbortController();
  let validateCount = 0;
  transport.onRequest = (request) => {
    if (request.action === 'validate-token') {
      validateCount += 1;
      if (validateCount === 2) {
        controller.abort();
      }
    }
  };
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    credentialStore: createSuccessfulCredentialStore(),
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 8,
      code: 'WXYZ',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: placeholderAuthValue,
      clientIdentifier: 'desktop-client',
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'account-1',
      username: 'viewer',
      email: 'viewer@example.invalid',
    },
  });
  await service.checkPinStatus(8);
  assert.equal(service.getActiveUserId(), 'account-1');

  transport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authenticationToken: placeholderAuthValue } },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: {
      id: 'kid',
      username: 'kid',
      email: 'kid@example.invalid',
    },
  });

  await assert.rejects(() => service.switchHomeUser('kid', { signal: controller.signal }), {
    name: 'PlexAuthError',
    code: 'aborted',
  });
  assert.equal(service.getActiveUserId(), 'account-1');
});

test('desktop plex auth service polling honors abort cancellation', async () => {
  const transport = new FakePlexAuthTransport();
  const controller = new AbortController();
  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    nowMs: () => 0,
    pollIntervalMs: 10,
    sleep: async () => {
      controller.abort();
      throw new PlexAuthError('aborted', 'Plex auth request was aborted');
    },
  });

  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      id: 9,
      code: 'WAIT',
      expiresAt: '2026-05-10T12:05:00.000Z',
      authToken: null,
      clientIdentifier: 'desktop-client',
    },
  });

  await assert.rejects(() => service.pollForPin(9, { signal: controller.signal }), {
    name: 'PlexAuthError',
    code: 'aborted',
  });
});

test('desktop plex auth service polling removes abort listeners after successful sleeps', async () => {
  const transport = new FakePlexAuthTransport();
  const controller = new AbortController();
  const signal = controller.signal;
  const originalAddEventListener = signal.addEventListener.bind(signal);
  const originalRemoveEventListener = signal.removeEventListener.bind(signal);
  let addedAbortListeners = 0;
  let removedAbortListeners = 0;
  let nowMs = 0;

  signal.addEventListener = ((...args: Parameters<AbortSignal['addEventListener']>) => {
    if (args[0] === 'abort') {
      addedAbortListeners += 1;
    }
    return originalAddEventListener(...args);
  }) as AbortSignal['addEventListener'];
  signal.removeEventListener = ((...args: Parameters<AbortSignal['removeEventListener']>) => {
    if (args[0] === 'abort') {
      removedAbortListeners += 1;
    }
    return originalRemoveEventListener(...args);
  }) as AbortSignal['removeEventListener'];

  transport.onRequest = (request) => {
    if (request.action === 'check-pin-status') {
      nowMs += 2;
    }
  };

  const service = new DesktopPlexAuthService({
    config: createDesktopPlexAuthConfig({ clientIdentifier: 'desktop-client' }),
    transport,
    nowMs: () => nowMs,
    pollIntervalMs: 1,
    pinTimeoutMs: 5,
  });

  for (let index = 0; index < 3; index += 1) {
    transport.enqueue('check-pin-status', {
      status: 200,
      payload: {
        id: 9,
        code: 'WAIT',
        expiresAt: '2026-05-10T12:05:00.000Z',
        authToken: null,
        clientIdentifier: 'desktop-client',
      },
    });
  }

  await assert.rejects(() => service.pollForPin(9, { signal }), {
    name: 'PlexAuthError',
    code: 'pin-timeout',
  });
  assert.equal(addedAbortListeners, 3);
  assert.equal(removedAbortListeners, 3);
});

test('desktop plex credential store returns renderer-safe save and read summaries', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
    nowMs: () => 10_000,
  });
  const credentialStore = new DesktopPlexCredentialStore({ persistenceStore });

  const saveResult = await credentialStore.saveAccountCredential({
    accountId: 'account-1',
    secretValue: 'placeholder-secret',
    profile: {
      accountId: 'account-1',
      username: 'viewer',
      displayName: 'Viewer',
      activeProfileId: 'profile-1',
    },
  });
  assert.equal(saveResult.ok, true);
  assertRendererSafe(saveResult);

  const readResult = await credentialStore.readAccountCredential('account-1');
  assert.equal(readResult.status, 'present');
  assertRendererSafe(readResult);
  assert.equal(JSON.stringify(readResult).includes('placeholder-secret'), false);
  if (readResult.status === 'present') {
    assert.equal(readResult.credentialHandle.createdAtMs, 10_000);
    assert.deepEqual(readResult.profile, {
      accountId: 'account-1',
      username: 'viewer',
      displayName: 'Viewer',
    });
  }

  const persisted = await fs.readFile(path.join(temporaryDirectory, 'persistence.json'), 'utf8');
  assert.equal(persisted.includes('placeholder-secret'), false);
});

test('desktop plex credential store reports snapshot handle mismatches before using stub handle', async () => {
  const credentialStore = new DesktopPlexCredentialStore({
    persistenceStore: {
      async readPlexCredentialSecret() {
        return {
          status: 'present',
          accountId: 'account-1',
          credentialId: 'plex-account:account-1',
          secretValue: 'placeholder-secret',
          shouldReencrypt: false,
          diagnostics: [],
        } as const;
      },
      async getRendererSafeSnapshot() {
        return {
          storage: { credentials: 'available', appData: 'available' },
          accounts: [],
          credentialHandles: [],
          selectedServer: null,
          diagnostics: [],
        } as const;
      },
      async savePlexCredential() {
        return { ok: false, status: 'corrupt', diagnostics: [] } as const;
      },
    },
  });

  const readResult = await credentialStore.readAccountCredential('account-1');

  assert.equal(readResult.status, 'present');
  assertRendererSafe(readResult);
  if (readResult.status === 'present') {
    assert.equal(readResult.credentialHandle.createdAtMs, 0);
    assert.equal(readResult.credentialHandle.updatedAtMs, 0);
    assert.equal(readResult.diagnostics.some((diagnostic) => diagnostic.reason?.includes('stub handle')), true);
  }
});

test('desktop plex credential store normalizes mismatched profile account ids to storage account id', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const credentialStore = new DesktopPlexCredentialStore({
    persistenceStore: new DesktopPersistenceStore({
      persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
      secureStringCodec: new FakeSecureStringCodec(),
    }),
  });

  const saveResult = await credentialStore.saveAccountCredential({
    accountId: 'storage-account',
    secretValue: 'placeholder-secret',
    profile: {
      accountId: 'profile-account',
      username: 'viewer',
      displayName: 'Viewer',
    },
  });
  assert.equal(saveResult.ok, true);
  assertRendererSafe(saveResult);
  if (saveResult.ok) {
    assert.equal(saveResult.profile.accountId, 'storage-account');
    assert.equal(saveResult.credentialHandle.accountId, 'storage-account');
  }

  const readResult = await credentialStore.readAccountCredential('storage-account');
  assert.equal(readResult.status, 'present');
  assertRendererSafe(readResult);
  if (readResult.status === 'present') {
    assert.equal(readResult.accountId, 'storage-account');
    assert.equal(readResult.profile.accountId, 'storage-account');
    assert.equal(readResult.credentialHandle.accountId, 'storage-account');
  }
});

test('desktop plex credential store maps missing, corrupt, and unavailable states safely', async () => {
  const missingStore = new DesktopPlexCredentialStore({
    persistenceStore: new DesktopPersistenceStore({
      persistenceFilePath: path.join(await createTemporaryDirectory(), 'missing.json'),
      secureStringCodec: new FakeSecureStringCodec(),
    }),
  });
  const missing = await missingStore.readAccountCredential('missing-account');
  assert.equal(missing.status, 'missing');
  assertRendererSafe(missing);

  const corruptDirectory = await createTemporaryDirectory();
  const corruptPath = path.join(corruptDirectory, 'persistence.json');
  await fs.writeFile(corruptPath, '{"schemaVersion":1,"credentials":"invalid"}\n');
  const corruptStore = new DesktopPlexCredentialStore({
    persistenceStore: new DesktopPersistenceStore({
      persistenceFilePath: corruptPath,
      secureStringCodec: new FakeSecureStringCodec(),
    }),
  });
  const corrupt = await corruptStore.readAccountCredential('account-1');
  assert.equal(corrupt.status, 'corrupt');
  assertRendererSafe(corrupt);

  const codec = new FakeSecureStringCodec();
  const unavailableDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(unavailableDirectory, 'persistence.json'),
    secureStringCodec: codec,
  });
  await persistenceStore.savePlexCredential({
    accountId: 'account-1',
    secretValue: 'placeholder-secret',
  });
  codec.availability = {
    available: false,
    backend: 'electron-safe-storage',
    reason: 'encryption-unavailable',
  };
  const unavailableStore = new DesktopPlexCredentialStore({ persistenceStore });
  const unavailable = await unavailableStore.readAccountCredential('account-1');
  assert.equal(unavailable.status, 'unavailable');
  assertRendererSafe(unavailable);
});

test('plex forbidden renderer vocabulary catches recursive auth and raw payload fields', () => {
  assert.equal(
    containsPlexForbiddenRendererField({
      profile: { accountId: 'account-1', displayName: 'Viewer' },
      nested: { authToken: placeholderAuthValue },
    }),
    true,
  );
  assert.equal(
    containsPlexForbiddenRendererField({
      profile: { accountId: 'account-1', displayName: 'Viewer' },
      nested: { rawPlexPayload: { id: 1 } },
    }),
    true,
  );
  assert.equal(
    containsPlexForbiddenRendererField({
      profile: { accountId: 'account-1', displayName: 'Viewer' },
      nested: {
        ['Authori' + 'zation']: 'placeholder-auth-value',
        ['x-plex-token']: 'placeholder-auth-value',
        Headers: { secret: 'placeholder-secret' },
      },
    }),
    true,
  );
  assert.equal(
    containsPlexForbiddenRendererField({
      profile: { accountId: 'account-1', displayName: 'Viewer' },
      credentialHandle: {
        credentialId: 'plex-account:account-1',
        accountId: 'account-1',
        kind: 'plex-account',
        createdAtMs: 1,
        updatedAtMs: 1,
      },
    }),
    false,
  );
});

function assertRendererSafe(value: unknown): void {
  assert.equal(containsPlexForbiddenRendererField(value), false);
  const serialized = JSON.stringify(value);
  assert.equal(serialized.includes('placeholder-secret'), false);
  assert.equal(serialized.includes('placeholder-auth-value'), false);
}

async function createTemporaryDirectory(): Promise<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), 'lineup-rd10-auth-'));
}
