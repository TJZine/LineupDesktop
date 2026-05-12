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
  public readonly probeRequests: Array<{ server: PlexServer; connection: PlexConnection }> = [];
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
  }): Promise<DesktopPlexConnectionProbeTransportResult> {
    this.probeRequests.push(input);
    return this.probeResponses.get(input.connection.address) ?? { outcome: 'unreachable' };
  }
}

class DeferredSelectedServerStore {
  public saved: Array<{ serverId: string; source: PlexServerSelectionSource }> = [];
  private resolveSave: (() => void) | null = null;

  async readSelectedServerSummary() {
    return null;
  }

  async saveSelectedServerSummary(
    server: PlexServer,
    source: PlexServerSelectionSource,
  ): Promise<PlexSelectedServerSummary> {
    this.saved.push({ serverId: server.id, source });
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
  const selected = await discovery.selectServer('server-1', { source: 'manual' });
  const persisted = await persistenceStore.getRendererSafeSnapshot();
  const persistedFile = await fs.readFile(path.join(temporaryDirectory, 'persistence.json'), 'utf8');

  assert.equal(selected.kind, 'selected');
  assertRendererSafe(selected);
  assert.deepEqual(persisted.selectedServer, {
    serverId: 'server-1',
    name: 'Living Room',
    source: 'manual',
    lastSelectedAtMs: 50_000,
  });
  assert.equal(persistedFile.includes('://'), false);
  assert.equal(persistedFile.includes('connection'), false);
  assert.equal(discovery.getSelectedConnectionForMain()?.address, 'local');
});

test('desktop plex discovery restores by persisted server id with fresh probing', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
    nowMs: () => 10_000,
  });
  await persistenceStore.setSelectedPlexServer({
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

  const restored = await discovery.restoreSelectedServer();
  const persisted = await persistenceStore.getRendererSafeSnapshot();

  assert.equal(restored.kind, 'selected');
  assert.equal(restored.kind === 'selected' ? restored.server.name : '', 'Fresh Name');
  assert.deepEqual(persisted.selectedServer, {
    serverId: 'server-1',
    name: 'Fresh Name',
    source: 'restored',
    lastSelectedAtMs: 20_000,
  });
  assertRendererSafe(restored);
});

test('desktop plex discovery keeps stale persisted server id on restore miss or auth failure', async () => {
  const temporaryDirectory = await createTemporaryDirectory();
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: path.join(temporaryDirectory, 'persistence.json'),
    secureStringCodec: new FakeSecureStringCodec(),
  });
  await persistenceStore.setSelectedPlexServer({
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

  const missing = await discovery.restoreSelectedServer();
  assert.deepEqual(missing, {
    kind: 'selection-failed',
    reason: 'server-not-found',
    persisted: false,
  });
  assert.equal((await persistenceStore.getRendererSafeSnapshot()).selectedServer?.serverId, 'missing-server');

  await persistenceStore.setSelectedPlexServer({
    serverId: 'server-1',
    name: 'Present',
    source: 'manual',
    lastSelectedAtMs: 2,
  });
  const authRequired = await discovery.restoreSelectedServer();
  assert.equal(authRequired.kind, 'selection-failed');
  assert.equal(authRequired.kind === 'selection-failed' ? authRequired.reason : '', 'auth-required');
  assert.equal((await persistenceStore.getRendererSafeSnapshot()).selectedServer?.serverId, 'server-1');
  assertRendererSafe(authRequired);
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
  await discovery.selectServer('server-1');
  assert.equal(discovery.getSelectedConnectionForMain()?.address, 'server');

  await persistenceStore.setSelectedPlexServer({
    serverId: 'server-1',
    name: 'Present',
    source: 'manual',
    lastSelectedAtMs: 1,
  });
  transport.enqueueProbe('server', { outcome: 'unreachable' });

  const restored = await discovery.restoreSelectedServer();

  assert.equal(restored.kind, 'selection-failed');
  assert.equal(discovery.getSelectedConnectionForMain(), null);
  assert.equal(discovery.getSelectedServerSummary(), null);
  assert.equal((await persistenceStore.getRendererSafeSnapshot()).selectedServer?.serverId, 'server-1');
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
  await assert.rejects(() => discovery.selectServer('server-1'), {
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

  const selection = discovery.selectServer('server-1');
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

  const selection = discovery.selectServer('server-1');
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
  assert.deepEqual(selectedServerStore.saved, [{ serverId: 'server-1', source: 'discovery' }]);
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
