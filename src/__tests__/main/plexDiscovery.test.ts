import { Buffer } from 'node:buffer';
import { setTimeout as sleep } from 'node:timers/promises';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import type { PlexSelectedServerSummary } from '../../contracts/persistence.js';
import { DesktopPersistenceStore } from '../../main/persistence/desktopPersistenceStore.js';
import {
  SecureStorageUnavailableError,
  type SecureStorageAvailability,
  type SecureStringCodec,
  type SecureStringDecryptResult,
} from '../../main/persistence/secureStorageCodec.js';
import {
  DesktopPlexSelectedServerStore,
  DesktopPlexServerDiscovery,
  PlexDiscoveryError,
  createPlexApiResource,
  type DesktopPlexConnectionProbeTransportResult,
  type DesktopPlexDiscoveryTransport,
  type PlexConnection,
  type PlexServerSelectionSource,
  type PlexServer,
} from '../../main/plex/discovery/index.js';
import { LivePlexTransport, LivePlexTransportError } from '../../main/plex/livePlexTransport.js';

const placeholderAuthValue = 'placeholder-auth-value';

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
    return Buffer.from(`encrypted:${value}`, 'utf8');
  }

  async decryptString(encrypted: Buffer): Promise<SecureStringDecryptResult> {
    if (!this.availability.available) {
      throw new SecureStorageUnavailableError();
    }
    return {
      value: encrypted.toString('utf8').replace(/^encrypted:/u, ''),
      shouldReencrypt: false,
    };
  }
}

class FakeDiscoveryTransport implements DesktopPlexDiscoveryTransport {
  public resources: unknown = [];
  public readonly probeRequests: Array<{
    server: PlexServer;
    connection: PlexConnection;
    token?: string;
  }> = [];
  private readonly probeResponses = new Map<string, DesktopPlexConnectionProbeTransportResult>();
  private deferredResources:
    | {
        promise: Promise<unknown>;
        resolve: (value: unknown) => void;
      }
    | null = null;

  enqueueProbe(
    connectionAddress: string,
    result: DesktopPlexConnectionProbeTransportResult,
  ): void {
    this.probeResponses.set(connectionAddress, result);
  }

  deferResources(): { resolve: (value: unknown) => void } {
    let resolve!: (value: unknown) => void;
    const promise = new Promise<unknown>((resolver) => {
      resolve = resolver;
    });
    this.deferredResources = { promise, resolve };
    return { resolve };
  }

  async discoverResources(): Promise<unknown> {
    if (this.deferredResources) {
      const pending = this.deferredResources;
      this.deferredResources = null;
      return pending.promise;
    }
    return this.resources;
  }

  async probeConnection(input: {
    server: PlexServer;
    connection: PlexConnection;
    token?: string;
  }): Promise<DesktopPlexConnectionProbeTransportResult> {
    this.probeRequests.push(input);
    return this.probeResponses.get(input.connection.address) ?? { outcome: 'unreachable' };
  }
}

class DeferredSelectedServerStore {
  public saved: Array<{ serverId: string; source: PlexServerSelectionSource; profileId?: string }> = [];
  private resolveSave: (() => void) | null = null;

  async readSelectedServerSummary() {
    return null;
  }

  async saveSelectedServerSummary(
    server: PlexServer,
    source: PlexServerSelectionSource,
    options?: { profileId?: string },
  ): Promise<PlexSelectedServerSummary> {
    this.saved.push({ serverId: server.id, source, profileId: options?.profileId });
    await new Promise<void>((resolve) => {
      this.resolveSave = resolve;
    });
    return {
      serverId: server.id,
      name: server.name,
      source,
      lastSelectedAtMs: 10_000,
    };
  }

  resolve(): void {
    this.resolveSave?.();
  }
}

type FakeFetchResponse = {
  status: number;
  body: string;
  headers?: Record<string, string>;
};

function createDiscoveryFetch(responses: FakeFetchResponse[]): {
  fetch: typeof globalThis.fetch;
  calls: Array<{ url: string; headers: Record<string, string> }>;
} {
  const calls: Array<{ url: string; headers: Record<string, string> }> = [];
  const fetch = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({
      url: String(url),
      headers: normalizeRequestHeaders(init?.headers),
    });
    const next = responses.shift();
    if (!next) {
      throw new Error('unexpected discovery fetch');
    }
    return {
      status: next.status,
      headers: {
        get(name: string): string | null {
          const lowerName = name.toLowerCase();
          const entry = Object.entries(next.headers ?? {}).find(([key]) => key.toLowerCase() === lowerName);
          return entry?.[1] ?? null;
        },
      },
      async text(): Promise<string> {
        return next.body;
      },
    } as Response;
  }) as typeof globalThis.fetch;
  return { fetch, calls };
}

function normalizeRequestHeaders(headers: HeadersInit | undefined): Record<string, string> {
  if (!headers) {
    return {};
  }
  if (headers instanceof Headers) {
    const normalized: Record<string, string> = {};
    headers.forEach((value, key) => {
      normalized[key] = value;
    });
    return normalized;
  }
  if (Array.isArray(headers)) {
    return Object.fromEntries(headers);
  }
  return { ...headers };
}

function jsonDiscoveryResponse(resources: unknown[]): FakeFetchResponse {
  return {
    status: 200,
    body: JSON.stringify(resources),
    headers: { 'Content-Type': 'application/json' },
  };
}

test('plex discovery errors summarize unserializable context without stack leakage', () => {
  const context: Record<string, unknown> = { token: 'placeholder-auth-value' };
  context.self = context;
  const cause = new Error('discovery failed secret=placeholder-secret');
  cause.stack = 'Error: failed\n    at /Users/example/lineup/discovery.ts:1:1';

  const error = new PlexDiscoveryError('server-error', 'failed token=placeholder-auth-value', 500, {
    cause,
    context,
  });
  const serialized = JSON.stringify({
    message: error.message,
    cause: error.cause,
    context: error.context,
  });

  assert.equal(serialized.includes('placeholder-auth-value'), false);
  assert.equal(serialized.includes('placeholder-secret'), false);
  assert.equal(serialized.includes('/Users/example'), false);
  assert.equal(serialized.includes('"stack"'), false);
  assert.equal(serialized.includes('unserializable object'), true);
});

test('live plex discovery falls back through trusted token-query variants', async () => {
  const { fetch, calls } = createDiscoveryFetch([
    { status: 500, body: 'temporary failure', headers: { 'Content-Type': 'text/plain' } },
    jsonDiscoveryResponse([
      {
        clientIdentifier: 'server-variant',
        name: 'Variant Server',
        sourceTitle: 'Variant Server',
        ownerId: 'owner',
        owned: true,
        provides: 'server',
        connections: [],
      },
    ]),
  ]);
  const transport = new LivePlexTransport({
    fetch,
    discoveryWaitMs: async () => {},
  });

  const resources = await transport.discoverResources({ token: placeholderAuthValue });

  assert.equal(calls.length, 2);
  assert.equal(calls[0]?.url.includes('X-Plex-Token'), false);
  assert.equal(calls[0]?.url.includes('includeIPv6'), false);
  assert.equal(calls[0]?.headers['X-Plex-Token'], placeholderAuthValue);
  assert.equal(calls[1]?.url.startsWith('https://plex.tv/api/v2/resources'), true);
  assert.equal(calls[1]?.url.includes('X-Plex-Token=placeholder-auth-value'), true);
  assert.equal(calls[1]?.url.includes('includeIPv6'), false);
  assert.deepEqual(resources, [
    {
      clientIdentifier: 'server-variant',
      name: 'Variant Server',
      sourceTitle: 'Variant Server',
      ownerId: 'owner',
      owned: true,
      provides: 'server',
      connections: [],
    },
  ]);
});

test('live plex discovery parses XML resources before desktop discovery projection', async () => {
  const { fetch } = createDiscoveryFetch([
    {
      status: 200,
      headers: { 'Content-Type': 'application/xml' },
      body: `
        <MediaContainer>
          <Device
            clientIdentifier="server-xml"
            name='XML Server &#65;'
            sourceTitle='XML &amp; Source'
            ownerId="owner-xml"
            owned="1"
            provides="server">
            <Connection
              uri='https://xml.example:32400/library'
              protocol='https'
              address='xml'
              port='32400'
              local='1'
              relay='0' />
          </Device>
        </MediaContainer>
      `,
    },
  ]);
  const liveTransport = new LivePlexTransport({ fetch });
  const discovery = new DesktopPlexServerDiscovery({ transport: liveTransport });

  const summaries = await discovery.refreshServers({ token: placeholderAuthValue });

  assert.deepEqual(summaries, [
    {
      serverId: 'server-xml',
      name: 'XML Server A',
      owned: true,
      sourceTitle: 'XML & Source',
      connectionCount: 1,
      hasLocalConnection: true,
      hasRemoteConnection: false,
      hasRelayConnection: false,
      selected: false,
    },
  ]);
  assertRendererSafe(summaries);
});

test('live plex discovery classifies malformed non-XML responses as parse errors', async () => {
  const { fetch } = createDiscoveryFetch([
    {
      status: 200,
      body: 'not-a-json-or-xml-payload',
      headers: { 'Content-Type': 'text/plain' },
    },
  ]);
  const transport = new LivePlexTransport({ fetch });

  await assert.rejects(
    () => transport.discoverResources({ token: placeholderAuthValue }),
    (error) =>
      error instanceof LivePlexTransportError &&
      error.code === 'parse-error' &&
      error.httpStatus === 200,
  );
});

test('live plex discovery classifies malformed XML responses as parse errors', async () => {
  const { fetch } = createDiscoveryFetch([
    {
      status: 200,
      body: '<MediaContainer><Device name="broken"></MediaContainer>',
      headers: { 'Content-Type': 'application/xml' },
    },
  ]);
  const transport = new LivePlexTransport({ fetch });

  await assert.rejects(
    () => transport.discoverResources({ token: placeholderAuthValue }),
    (error) =>
      error instanceof LivePlexTransportError &&
      error.code === 'parse-error' &&
      error.httpStatus === 200,
  );
});

test('live plex discovery rejects malformed XML connection nesting', async () => {
  const { fetch } = createDiscoveryFetch([
    {
      status: 200,
      body: '<MediaContainer><Device name="broken"><Connection uri="https://broken.example"></Device></MediaContainer>',
      headers: { 'Content-Type': 'application/xml' },
    },
  ]);
  const transport = new LivePlexTransport({ fetch });

  await assert.rejects(
    () => transport.discoverResources({ token: placeholderAuthValue }),
    (error) =>
      error instanceof LivePlexTransportError &&
      error.code === 'parse-error' &&
      error.httpStatus === 200,
  );
});

test('live plex discovery rejects malformed XML entities', async () => {
  for (const nameAttribute of [
    'A & B',
    'A &bogus; B',
    'bad &#x110000; codepoint',
    'bad &#0; codepoint',
    'bad &#1; codepoint',
    'bad &#8; codepoint',
    'bad &#31; codepoint',
    'bad &#xFFFE; codepoint',
    'bad &#xFFFF; codepoint',
  ]) {
    const { fetch } = createDiscoveryFetch([
      {
        status: 200,
        body: `<MediaContainer><Device clientIdentifier="bad-entity" name="${nameAttribute}" /></MediaContainer>`,
        headers: { 'Content-Type': 'application/xml' },
      },
    ]);
    const transport = new LivePlexTransport({ fetch });

    await assert.rejects(
      () => transport.discoverResources({ token: placeholderAuthValue }),
      (error) =>
        error instanceof LivePlexTransportError &&
        error.code === 'parse-error' &&
        error.httpStatus === 200,
    );
  }
});

test('live plex discovery classifies unreadable response bodies as parse errors', async () => {
  const fetch = (async () =>
    ({
      status: 200,
      headers: new Headers({ 'Content-Type': 'application/json' }),
      async text(): Promise<string> {
        throw new Error('body stream unavailable token=placeholder-auth-value');
      },
    }) as Response) as typeof globalThis.fetch;
  const transport = new LivePlexTransport({ fetch });

  await assert.rejects(
    () => transport.discoverResources({ token: placeholderAuthValue }),
    (error) =>
      error instanceof LivePlexTransportError &&
      error.code === 'parse-error' &&
      error.httpStatus === 200 &&
      !JSON.stringify(error).includes(placeholderAuthValue) &&
      !JSON.stringify(error.cause).includes(placeholderAuthValue),
  );
});

test('desktop plex discovery preserves live transport parse failures', async () => {
  const fetch = (async () =>
    ({
      status: 200,
      headers: new Headers({ 'Content-Type': 'application/json' }),
      async text(): Promise<string> {
        throw new Error('body stream unavailable token=placeholder-auth-value');
      },
    }) as Response) as typeof globalThis.fetch;
  const liveTransport = new LivePlexTransport({ fetch });
  const discovery = new DesktopPlexServerDiscovery({ transport: liveTransport });

  await assert.rejects(
    () => discovery.refreshServers({ token: placeholderAuthValue }),
    (error) =>
      error instanceof PlexDiscoveryError &&
      error.code === 'parse-error' &&
      error.retryable === false &&
      error.httpStatus === 200 &&
      !JSON.stringify(error).includes(placeholderAuthValue) &&
      !JSON.stringify(error.cause).includes(placeholderAuthValue),
  );
});

test('live plex discovery honors bounded 429 retry-after retry path', async () => {
  const { fetch, calls } = createDiscoveryFetch([
    {
      status: 429,
      body: 'rate limited',
      headers: { 'Retry-After': '0.25', 'Content-Type': 'text/plain' },
    },
    jsonDiscoveryResponse([]),
  ]);
  const waits: number[] = [];
  const transport = new LivePlexTransport({
    fetch,
    discoveryWaitMs: async (delayMs) => {
      waits.push(delayMs);
    },
  });

  const resources = await transport.discoverResources({ token: placeholderAuthValue });

  assert.deepEqual(resources, []);
  assert.deepEqual(waits, [250]);
  assert.equal(calls.length, 2);
});

test('live plex discovery keeps tokenized request failures out of error output', async () => {
  const calls: string[] = [];
  const fetch = (async (url: string | URL | Request) => {
    calls.push(String(url));
    throw new Error(`failed ${String(url)} token=${placeholderAuthValue}`);
  }) as typeof globalThis.fetch;
  const transport = new LivePlexTransport({
    fetch,
    discoveryWaitMs: async () => {},
  });

  await assert.rejects(
    () => transport.discoverResources({ token: placeholderAuthValue }),
    (error) => {
      assert.equal(error instanceof LivePlexTransportError, true);
      const serialized = JSON.stringify(error);
      assert.equal(serialized.includes(placeholderAuthValue), false);
      assert.equal(serialized.includes('X-Plex-Token=placeholder-auth-value'), false);
      return true;
    },
  );
  assert.equal(calls.some((url) => url.startsWith('https://clients.plex.tv/api/v2/resources')), true);
});

test('plex discovery parser normalizes resources and renderer-safe summaries', async () => {
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Living Room',
      sourceTitle: 'Living Room',
      connections: [
        createConnection({ address: 'local', uri: `${'https'}://local.example:32400/library` }),
        createConnection({ address: 'credentialed', uri: `${'https'}://user:pass@example.invalid:32400` }),
        createConnection({ address: 'file', uri: 'file:///tmp/not-allowed' }),
      ],
    }),
    createPlexApiResource({
      clientIdentifier: 'client-1',
      name: 'Ignored Client',
      provides: 'client',
      connections: [createConnection({ address: 'client' })],
    }),
    {
      clientIdentifier: 'partial-server',
      name: 'Partial',
      provides: 'server',
      connections: [createConnection({ address: 'partial' })],
    },
  ];
  const discovery = new DesktopPlexServerDiscovery({ transport });

  const summaries = await discovery.refreshServers();

  assert.deepEqual(summaries, [
    {
      serverId: 'server-1',
      name: 'Living Room',
      owned: true,
      sourceTitle: 'Living Room',
      connectionCount: 1,
      hasLocalConnection: true,
      hasRemoteConnection: false,
      hasRelayConnection: false,
      selected: false,
    },
    {
      serverId: 'partial-server',
      name: 'Partial',
      owned: false,
      connectionCount: 1,
      hasLocalConnection: true,
      hasRemoteConnection: false,
      hasRelayConnection: false,
      selected: false,
    },
  ]);
  assertRendererSafe(summaries);
});

test('desktop plex discovery selects a server and persists only RD-09 summary state', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
    nowMs: () => 50_000,
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Living Room',
      connections: [
        createConnection({ address: 'remote', local: false, uri: `${'https'}://remote.example:32400` }),
        createConnection({ address: 'local', uri: `${'https'}://local.example:32400` }),
      ],
    }),
  ];
  transport.enqueueProbe('local', { outcome: 'reachable', latencyMs: 20 });
  transport.enqueueProbe('remote', { outcome: 'reachable', latencyMs: 80 });
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore, nowMs: () => 50_000 }),
    nowMs: () => 60_000,
  });

  await discovery.refreshServers();
  const selected = await discovery.selectServer('server-1', {
    source: 'manual',
    token: placeholderAuthValue,
    profileId: 'profile-a',
  });
  const persisted = await persistenceStore.getRendererSafeSnapshot();
  const scopedPersisted = await persistenceStore.getSelectedPlexServer('profile-a');
  const persistedFile = await fs.readFile(path.join(temporaryDirectory, 'persistence.json'), 'utf8');

  assert.equal(selected.kind, 'selected');
  assertRendererSafe(selected);
  assert.deepEqual(scopedPersisted, {
    serverId: 'server-1',
    name: 'Living Room',
    source: 'manual',
    lastSelectedAtMs: 50_000,
  });
  assert.equal(persisted.selectedServer, null);
  assert.equal(persistedFile.includes('://'), false);
  assert.equal(persistedFile.includes('connection'), false);
  assert.equal(discovery.getSelectedConnectionForMain()?.address, 'local');
  assert.equal(transport.probeRequests.every((request) => request.token === placeholderAuthValue), true);
});

test('desktop plex discovery restores by persisted server id with fresh probing', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
    nowMs: () => 10_000,
  });
  await persistenceStore.setSelectedPlexServer('profile-a', {
    serverId: 'server-1',
    name: 'Stale Name',
    source: 'manual',
    lastSelectedAtMs: 1,
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Fresh Name',
      connections: [createConnection({ address: 'fresh', uri: `${'https'}://fresh.example:32400` })],
    }),
  ];
  transport.enqueueProbe('fresh', { outcome: 'reachable', latencyMs: 12 });
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore, nowMs: () => 20_000 }),
    nowMs: () => 30_000,
  });

  const restored = await discovery.restoreSelectedServer({ profileId: 'profile-a' });
  const persisted = await persistenceStore.getSelectedPlexServer('profile-a');

  assert.equal(restored.kind, 'selected');
  assert.equal(restored.kind === 'selected' ? restored.server.name : '', 'Fresh Name');
  assert.deepEqual(persisted, {
    serverId: 'server-1',
    name: 'Fresh Name',
    source: 'restored',
    lastSelectedAtMs: 20_000,
  });
  assertRendererSafe(restored);
});

test('desktop plex discovery scopes selected-server save and restore by active profile id', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-a',
      name: 'Profile A Server',
      connections: [createConnection({ address: 'a', uri: `${'https'}://a.example:32400` })],
    }),
    createPlexApiResource({
      clientIdentifier: 'server-b',
      name: 'Profile B Server',
      connections: [createConnection({ address: 'b', uri: `${'https'}://b.example:32400` })],
    }),
  ];
  transport.enqueueProbe('a', { outcome: 'reachable', latencyMs: 30 });
  transport.enqueueProbe('b', { outcome: 'reachable', latencyMs: 20 });
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore, nowMs: () => 70_000 }),
  });

  await discovery.refreshServers();
  const selectedA = await discovery.selectServer('server-a', { profileId: 'profile-a' });
  const selectedB = await discovery.selectServer('server-b', { profileId: 'profile-b' });
  const persistedFile = await fs.readFile(path.join(temporaryDirectory, 'persistence.json'), 'utf8');

  assert.equal(selectedA.kind, 'selected');
  assert.equal(selectedB.kind, 'selected');
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'server-a');
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-b'))?.serverId, 'server-b');
  assert.equal(persistedFile.includes('://'), false);
  assert.equal(persistedFile.includes('connection'), false);

  const restoreTransport = new FakeDiscoveryTransport();
  restoreTransport.resources = transport.resources;
  restoreTransport.enqueueProbe('b', { outcome: 'reachable', latencyMs: 10 });
  const restoreDiscovery = new DesktopPlexServerDiscovery({
    transport: restoreTransport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore, nowMs: () => 80_000 }),
  });

  const restoredB = await restoreDiscovery.restoreSelectedServer({ profileId: 'profile-b' });

  assert.equal(restoredB.kind, 'selected');
  assert.equal(restoredB.kind === 'selected' ? restoredB.server.serverId : '', 'server-b');
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'server-a');
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-b'))?.source, 'restored');
  assertRendererSafe(restoredB);
});

test('desktop plex discovery returns no persisted server for a profile without scoped selection', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  await persistenceStore.setSelectedPlexServer('profile-a', {
    serverId: 'server-a',
    name: 'Profile A Server',
    source: 'manual',
    lastSelectedAtMs: 1,
  });
  const discovery = new DesktopPlexServerDiscovery({
    transport: new FakeDiscoveryTransport(),
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore }),
  });

  const restored = await discovery.restoreSelectedServer({ profileId: 'profile-b' });

  assert.deepEqual(restored, {
    kind: 'selection-failed',
    reason: 'no-persisted-server',
    persisted: false,
  });
  assert.equal(discovery.getSelectedConnectionForMain(), null);
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'server-a');
  assert.equal(await persistenceStore.getSelectedPlexServer('profile-b'), null);
});

test('desktop plex discovery keeps stale persisted server id on restore miss or auth failure', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  await persistenceStore.setSelectedPlexServer('profile-a', {
    serverId: 'missing-server',
    name: 'Missing',
    source: 'manual',
    lastSelectedAtMs: 1,
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Present',
      connections: [createConnection({ address: 'auth-needed' })],
    }),
  ];
  transport.enqueueProbe('auth-needed', { outcome: 'auth-required' });
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore }),
  });

  const missing = await discovery.restoreSelectedServer({ profileId: 'profile-a' });
  assert.deepEqual(missing, {
    kind: 'selection-failed',
    reason: 'server-not-found',
    persisted: false,
  });
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'missing-server');

  await persistenceStore.setSelectedPlexServer('profile-a', {
    serverId: 'server-1',
    name: 'Present',
    source: 'manual',
    lastSelectedAtMs: 2,
  });
  const authRequired = await discovery.restoreSelectedServer({ profileId: 'profile-a' });
  assert.equal(authRequired.kind, 'selection-failed');
  assert.equal(authRequired.kind === 'selection-failed' ? authRequired.reason : '', 'auth-required');
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'server-1');
  assertRendererSafe(authRequired);
});

test('desktop plex discovery does not overwrite another profile when scoped restore misses', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  await persistenceStore.setSelectedPlexServer('profile-a', {
    serverId: 'server-a',
    name: 'Profile A Server',
    source: 'manual',
    lastSelectedAtMs: 1,
  });
  await persistenceStore.setSelectedPlexServer('profile-b', {
    serverId: 'missing-server',
    name: 'Missing',
    source: 'manual',
    lastSelectedAtMs: 2,
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-a',
      name: 'Profile A Server',
      connections: [createConnection({ address: 'a' })],
    }),
  ];
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore }),
  });

  const restored = await discovery.restoreSelectedServer({ profileId: 'profile-b' });

  assert.deepEqual(restored, {
    kind: 'selection-failed',
    reason: 'server-not-found',
    persisted: false,
  });
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'server-a');
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-b'))?.serverId, 'missing-server');
});

test('desktop plex discovery skips persisted selected-server reads when restore is already aborted', async () => {
  let readCount = 0;
  const selectedServerStore = {
    async readSelectedServerSummary(): Promise<PlexSelectedServerSummary | null> {
      readCount += 1;
      return null;
    },
    async saveSelectedServerSummary(
      server: PlexServer,
      source: PlexServerSelectionSource,
    ): Promise<PlexSelectedServerSummary> {
      return {
        serverId: server.id,
        name: server.name,
        source,
        lastSelectedAtMs: 1,
      };
    },
  };
  const discovery = new DesktopPlexServerDiscovery({
    transport: new FakeDiscoveryTransport(),
    selectedServerStore,
  });
  const abortController = new AbortController();
  abortController.abort();

  await assert.rejects(
    () => discovery.restoreSelectedServer({ signal: abortController.signal }),
    (error) => error instanceof PlexDiscoveryError && error.code === 'aborted',
  );
  assert.equal(readCount, 0);
});

test('desktop plex discovery clears selected connection when a fresh same-server restore probe fails', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Present',
      connections: [createConnection({ address: 'server' })],
    }),
  ];
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore }),
  });

  transport.enqueueProbe('server', { outcome: 'reachable', latencyMs: 10 });
  await discovery.refreshServers();
  await discovery.selectServer('server-1', { profileId: 'profile-a' });
  assert.equal(discovery.getSelectedConnectionForMain()?.address, 'server');

  await persistenceStore.setSelectedPlexServer('profile-a', {
    serverId: 'server-1',
    name: 'Present',
    source: 'manual',
    lastSelectedAtMs: 1,
  });
  transport.enqueueProbe('server', { outcome: 'unreachable' });

  const restored = await discovery.restoreSelectedServer({ profileId: 'profile-a' });

  assert.equal(restored.kind, 'selection-failed');
  assert.equal(discovery.getSelectedConnectionForMain(), null);
  assert.equal(discovery.getSelectedServerSummary(), null);
  assert.equal((await persistenceStore.getSelectedPlexServer('profile-a'))?.serverId, 'server-1');
});

test('desktop plex discovery does not commit runtime state when RD-09 selected-server save fails', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceFilePath = path.join(temporaryDirectory, 'persistence.json');
  await fs.writeFile(persistenceFilePath, '{"schemaVersion":1,"credentials":"invalid"}\n');
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath,
    secureStringCodec: new FakeSecureStringCodec(),
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Present',
      connections: [createConnection({ address: 'server' })],
    }),
  ];
  transport.enqueueProbe('server', { outcome: 'reachable', latencyMs: 10 });
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore }),
  });

  await discovery.refreshServers();
  await assert.rejects(() => discovery.selectServer('server-1', { profileId: 'profile-a' }), {
    name: 'PlexDiscoveryError',
    code: 'server-error',
  });

  const snapshot = await persistenceStore.getRendererSafeSnapshot();
  assert.equal(snapshot.selectedServer, null);
  assert.equal(snapshot.storage.appData, 'corrupt');
  assert.equal(discovery.getSelectedConnectionForMain(), null);
  assert.equal(discovery.getSelectedServerSummary(), null);
});

test('desktop plex discovery ignores stale in-flight discovery context', async () => {
  const transport = new FakeDiscoveryTransport();
  const pending = transport.deferResources();
  const discovery = new DesktopPlexServerDiscovery({ transport });

  const refresh = discovery.refreshServers();
  discovery.resetDiscoveryContext();
  pending.resolve([
    createPlexApiResource({
      clientIdentifier: 'stale-server',
      name: 'Stale',
      connections: [createConnection({ address: 'stale' })],
    }),
  ]);

  assert.deepEqual(await refresh, []);
  assert.deepEqual(discovery.getServerSummaries(), []);
});

test('desktop plex discovery ignores stale in-flight selection after context reset', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  const transport = new FakeDiscoveryTransport();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Present',
      connections: [createConnection({ address: 'server' })],
    }),
  ];
  let resolveProbe!: (value: DesktopPlexConnectionProbeTransportResult) => void;
  transport.probeConnection = async (input) => {
    transport.probeRequests.push(input);
    return new Promise<DesktopPlexConnectionProbeTransportResult>((resolve) => {
      resolveProbe = resolve;
    });
  };
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore: new DesktopPlexSelectedServerStore({ persistenceStore }),
  });
  await discovery.refreshServers();

  const selection = discovery.selectServer('server-1', { profileId: 'profile-a' });
  discovery.resetDiscoveryContext();
  resolveProbe({ outcome: 'reachable', latencyMs: 10 });

  assert.deepEqual(await selection, {
    kind: 'selection-failed',
    reason: 'server-not-found',
    persisted: false,
  });
  assert.equal(discovery.getSelectedConnectionForMain(), null);
  assert.equal((await persistenceStore.getRendererSafeSnapshot()).selectedServer, null);
});

test('desktop plex discovery does not report success or commit memory when context resets during save', async () => {
  const transport = new FakeDiscoveryTransport();
  const selectedServerStore = new DeferredSelectedServerStore();
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Present',
      connections: [createConnection({ address: 'server' })],
    }),
  ];
  transport.enqueueProbe('server', { outcome: 'reachable', latencyMs: 10 });
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore,
  });
  await discovery.refreshServers();

  const selection = discovery.selectServer('server-1', { profileId: 'profile-a' });
  await waitFor(() => selectedServerStore.saved.length === 1);
  discovery.resetDiscoveryContext();
  selectedServerStore.resolve();

  assert.deepEqual(await selection, {
    kind: 'selection-failed',
    reason: 'server-not-found',
    persisted: false,
  });
  assert.equal(discovery.getSelectedConnectionForMain(), null);
  assert.equal(discovery.getSelectedServerSummary(), null);
  assert.deepEqual(selectedServerStore.saved, [{ serverId: 'server-1', source: 'discovery', profileId: 'profile-a' }]);
});

function createConnection(input: {
  uri?: string;
  address: string;
  port?: number;
  local?: boolean;
  relay?: boolean;
}): {
  uri: string;
  protocol: string;
  address: string;
  port: number;
  local: boolean;
  relay: boolean;
} {
  return {
    uri: input.uri ?? `${'https'}://${input.address}.example:32400`,
    protocol: 'https',
    address: input.address,
    port: input.port ?? 32_400,
    local: input.local ?? true,
    relay: input.relay ?? false,
  };
}

function assertRendererSafe(value: unknown): void {
  assert.equal(containsPlexForbiddenRendererField(value), false);
  const serialized = JSON.stringify(value);
  assert.equal(serialized.includes('placeholder-secret'), false);
  assert.equal(serialized.includes('placeholder-auth-value'), false);
  assert.equal(serialized.includes('://'), false);
  assert.equal(serialized.includes('"uri"'), false);
}

async function createTemporaryDirectory(): Promise<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), 'lineup-rd10-discovery-'));
}

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) {
      return;
    }
    await sleep(0);
  }
  throw new Error('Timed out waiting for test condition.');
}
