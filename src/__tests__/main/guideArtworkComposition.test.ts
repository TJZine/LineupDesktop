import assert from 'node:assert/strict';
import test from 'node:test';
import { setImmediate as waitForImmediate } from 'node:timers/promises';

import { ChannelLineupMutationCoordinator } from '../../main/channel/channelLineupMutationCoordinator.js';
import { GuideArtworkOwner } from '../../main/channel/guideArtworkOwner.js';
import { GuideArtworkSessionGenerationOwner } from '../../main/plex/guideArtworkSessionGenerationOwner.js';
import { deferred } from '../helpers/deferred.js';
import { createRequire } from 'node:module';
import { Buffer } from 'node:buffer';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPlexApiResource, type PlexConnection } from '../../main/plex/discovery/index.js';
import type { ChannelAggregate, ChannelAggregateMutationRequest, ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import type { CreatePlexCompositionOptions, PlexComposition } from '../../main/plex/plexComposition.js';
import type { ChannelComposition, CreateChannelCompositionOptions } from '../../main/channel/channelComposition.js';
import { LivePlexTransport } from '../../main/plex/livePlexTransport.js';

function sessionFixture() {
  const auth = {
    getActiveUserId: () => 'profile-1',
    getActiveTokenForMain: () => 'token-1',
  };
  const discovery = {
    getSelectedServerSummary: () => ({ serverId: 'server-1' }),
    getSelectedConnectionForMain: () => ({
      uri: 'https://plex.invalid:32400', protocol: 'https', address: 'plex.invalid',
      port: 32400, local: true, relay: false, latencyMs: 1,
    }),
  };
  return new GuideArtworkSessionGenerationOwner(auth as never, discovery as never);
}

test('builder and custom mutation leases cover persistence and overlap until both settle', async () => {
  const sessionOwner = sessionFixture();
  const builder = deferred<unknown>();
  const custom = deferred<unknown>();
  const store = {
    mutateChannelAggregate: (input: { kind: string }) =>
      input.kind === 'builder-lineup' ? builder.promise : custom.promise,
  };
  const coordinator = new ChannelLineupMutationCoordinator(store as never, sessionOwner);
  const builderResult = coordinator.mutateBuilderLineup({
    expectedLineupRevision: 1, mutate: (current) => current, onCommitBarrier: () => 'cancel',
  });
  const customResult = coordinator.mutateCustomLineup({ mutate: (current) => current });
  assert.equal(sessionOwner.captureCurrent(1), null);
  builder.resolve({ status: 'canceled' });
  await builderResult;
  assert.equal(sessionOwner.captureCurrent(1), null);
  custom.resolve({ status: 'committed', aggregate: {} });
  await customResult;
  assert.ok(sessionOwner.captureCurrent(1));
});

test('mutation failure releases its transition lease', async () => {
  const sessionOwner = sessionFixture();
  const store = { mutateChannelAggregate: async () => { throw new Error('write failed'); } };
  const coordinator = new ChannelLineupMutationCoordinator(store as never, sessionOwner);
  await assert.rejects(coordinator.mutateCustomLineup({ mutate: (current) => current }), /write failed/u);
  assert.ok(sessionOwner.captureCurrent(1));
});

test('session transition and owner disposal abort late artwork completion', async () => {
  const sessionOwner = sessionFixture();
  const fetch = deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>();
  let signal: AbortSignal | undefined;
  const artworkOwner = new GuideArtworkOwner(sessionOwner, {
    fetchGuideArtwork: async (request) => {
      signal = request.signal ?? undefined;
      return fetch.promise;
    },
  });
  const ref = artworkOwner.createRef({ role: 'poster', locator: '/library/metadata/1/thumb', altText: 'Poster', lineupRevision: 1 });
  assert.ok(ref);
  const pending = artworkOwner.get(ref.id);
  await waitForImmediate();
  const lease = sessionOwner.beginTransition('teardown');
  assert.equal(signal?.aborted, true);
  fetch.resolve({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' });
  assert.equal(await pending, null);
  artworkOwner.dispose();
  lease.settle();
  assert.equal(await artworkOwner.get(ref.id), null);
});

test('production Plex and channel compositions deliver protocol artwork and cancel late work in teardown order', async () => {
  const appData = await mkdtemp(join(tmpdir(), 'lineup-guide-artwork-composition-'));
  const restoreElectron = replaceElectron({
    safeStorage: {
      isEncryptionAvailable: () => true,
      isAsyncEncryptionAvailable: async () => true,
      encryptStringAsync: async (value: string) => Buffer.from(value, 'utf8'),
      decryptStringAsync: async (value: Buffer) => ({
        result: value.toString('utf8'), shouldReEncrypt: false,
      }),
      getSelectedStorageBackend: () => 'test',
    },
    net: { fetch: globalThis.fetch },
    protocol: { handle: () => undefined, registerSchemesAsPrivileged: () => undefined },
  });
  try {
    const require = createRequire(import.meta.url);
    const { createPlexComposition } = require('../../main/plex/plexComposition.ts') as {
      createPlexComposition(options: CreatePlexCompositionOptions): Promise<PlexComposition>;
    };
    const { bindGuideArtworkOwnerToWebContents, createChannelComposition } = require('../../main/channel/channelComposition.ts') as {
      bindGuideArtworkOwnerToWebContents(
        webContents: { once(event: 'destroyed', listener: () => void): unknown },
        owner: Pick<GuideArtworkOwner, 'dispose'>,
      ): void;
      createChannelComposition(options: CreateChannelCompositionOptions): ChannelComposition;
    };
    const { serveLineupProtocolRequest } = require('../../main/protocol.ts') as {
      serveLineupProtocolRequest(
        request: { url: string; method: string }, rendererRoot: string,
        owner: ChannelComposition['guideArtworkOwner'],
      ): Promise<Response>;
    };
    const transport = new LivePlexTransport();
    const plex = await createPlexComposition({
      app: { getPath: () => appData, getVersion: () => '0.0.0-test' } as never,
      createTransport: () => transport,
    });
    const token = 'account-token-value';
    transport.request = async (input) => {
      if (input.action === 'request-pin') return {
        status: 201, payload: { kind: 'json', data: { id: 7, code: 'ABCD', expiresAt: '2099-01-01T00:00:00.000Z' } },
      };
      if (input.action === 'check-pin-status') return {
        status: 200, payload: { kind: 'json', data: { id: 7, code: 'ABCD', expiresAt: '2099-01-01T00:00:00.000Z', authToken: token } },
      };
      if (input.action === 'validate-token') return {
        status: 200, payload: { kind: 'json', data: { id: 'account-1', username: 'viewer', email: 'viewer@example.invalid' } },
      };
      return { status: 200, payload: { kind: 'json', data: [] } };
    };
    const connection: PlexConnection = {
      uri: 'https://server.invalid:32400', protocol: 'https', address: 'server.invalid',
      port: 32400, local: true, relay: false, latencyMs: 5,
    };
    transport.discoverResources = async () => [createPlexApiResource({
      clientIdentifier: 'server-1', name: 'Server', connections: [connection],
    })];
    transport.probeConnection = async () => ({ outcome: 'reachable', latencyMs: 5 });
    assert.equal((await plex.runtime.requestPin('pin')).ok, true);
    const polled = await plex.runtime.pollPin('poll', 7);
    assert.equal(polled.ok, true, JSON.stringify(polled));
    assert.equal((await plex.runtime.refreshServers('refresh')).ok, true);
    assert.equal((await plex.runtime.selectServer('select', 'server-1')).ok, true);

    const fetches: Array<ReturnType<typeof deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>>> = [];
    const signals: AbortSignal[] = [];
    transport.fetchGuideArtwork = async (request) => {
      signals.push(request.signal ?? new AbortController().signal);
      const gate = deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>();
      fetches.push(gate);
      return gate.promise;
    };
    const channel = createChannelComposition({
      persistence: { kind: 'memory', storage: memoryStorage() },
      plexRuntime: plex.runtime,
      guideArtworkSessionGenerationOwner: plex.guideArtworkSessionGenerationOwner,
      guideArtworkTransport: plex.guideArtworkTransport,
    });
    const first = channel.guideArtworkOwner.createRef({ role: 'poster',
      locator: '/library/metadata/1/thumb', altText: 'Poster', lineupRevision: 0,
    });
    assert.ok(first);
    const firstResponse = serveLineupProtocolRequest(
      { url: `lineup://shell/artwork/${first.id}`, method: 'GET' }, appData, channel.guideArtworkOwner,
    );
    await waitForImmediate();
    fetches[0]!.resolve({ bytes: new Uint8Array([1, 2, 3]), mimeType: 'image/jpeg' });
    assert.equal((await firstResponse).status, 200);

    const late = channel.guideArtworkOwner.createRef({ role: 'poster',
      locator: '/library/metadata/2/thumb', altText: 'Late', lineupRevision: 0,
    });
    assert.ok(late);
    const lateResponse = serveLineupProtocolRequest(
      { url: `lineup://shell/artwork/${late.id}`, method: 'GET' }, appData, channel.guideArtworkOwner,
    );
    await waitForImmediate();
    let destroyed: (() => void) | null = null;
    bindGuideArtworkOwnerToWebContents({
      once: (_event: 'destroyed', listener: () => void) => { destroyed = listener; return {} as never; },
    } as never, channel.guideArtworkOwner);
    assert.ok(destroyed);
    (destroyed as () => void)();
    assert.equal(signals[1]?.aborted, true);
    await channel.teardown();
    fetches[1]!.resolve({ bytes: new Uint8Array([9]), mimeType: 'image/jpeg' });
    assert.equal((await lateResponse).status, 404);

    const trace: string[] = [];
    plex.guideArtworkSessionGenerationOwner.subscribe((snapshot) => {
      if (snapshot.status === 'disposed') trace.push('session-disposed');
    });
    transport.request = async (input) => {
      if (input.action !== 'get-home-users') return { status: 200, payload: { kind: 'json', data: [] } };
      return new Promise((_resolve, reject) => {
        const abort = () => { trace.push('transport-aborted'); reject(new Error('aborted')); };
        input.signal?.addEventListener('abort', abort, { once: true });
        if (input.signal?.aborted) abort();
      });
    };
    const pendingUsers = plex.runtime.getHomeUsers('teardown-users');
    await waitForImmediate();
    await plex.teardown();
    await pendingUsers;
    assert.deepEqual(trace, ['session-disposed', 'transport-aborted']);
  } finally {
    restoreElectron();
    await rm(appData, { recursive: true, force: true });
  }
});

function memoryStorage(): ChannelPersistenceStoragePort {
  let aggregate: ChannelAggregate = {
    storedChannelData: null, currentChannelId: null, lineupRevision: 0, channelBuilderState: null,
  };
  return {
    readStoredChannelData: async () => null,
    writeStoredChannelData: async () => undefined,
    clearStoredChannelData: async () => undefined,
    readCurrentChannelId: async () => aggregate.currentChannelId,
    writeCurrentChannelId: async () => undefined,
    readChannelAggregate: async () => aggregate,
    mutateChannelAggregate: async (request: ChannelAggregateMutationRequest) => {
      if (request.onCommitBarrier() === 'cancel') return { status: 'canceled' };
      aggregate = request.mutate(aggregate);
      return { status: 'committed', aggregate };
    },
  };
}

function replaceElectron(exports: object): () => void {
  const require = createRequire(import.meta.url);
  const modulePath = require.resolve('electron');
  require('electron');
  const entry = require.cache[modulePath];
  assert.ok(entry);
  const previous = entry.exports;
  entry.exports = exports;
  return () => { entry.exports = previous; };
}
