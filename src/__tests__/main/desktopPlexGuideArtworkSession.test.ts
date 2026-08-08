import assert from 'node:assert/strict';
import test from 'node:test';

import { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import { GuideArtworkSessionGenerationOwner } from '../../main/plex/guideArtworkSessionGenerationOwner.js';
import { GuideArtworkOwner } from '../../main/channel/guideArtworkOwner.js';
import { setImmediate as waitForImmediate } from 'node:timers/promises';
import type { PlexConnection } from '../../main/plex/discovery/types.js';
function rejectingDeferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: Error) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

function runtimeFixture(overrides: Record<string, unknown> = {}) {
  const connection = {
    uri: 'https://plex.invalid:32400', protocol: 'https' as const, address: 'plex.invalid',
    port: 32400, local: true, relay: false, latencyMs: 1,
  };
  const auth = {
    getActiveUserId: () => 'profile-1',
    getActiveTokenForMain: () => 'token-1',
    getAccountTokenForMain: () => 'account-token-1',
    ...overrides,
  };
  const discovery = {
    getSelectedServerSummary: () => ({ serverId: 'server-1' }),
    getSelectedConnectionForMain: () => connection,
    getServerSummaries: () => [],
    resetDiscoveryContext: () => undefined,
    ...overrides,
  };
  const sessionOwner = new GuideArtworkSessionGenerationOwner(auth as never, discovery as never);
  const runtime = new DesktopPlexRuntime({
    authService: auth as never,
    credentialStore: {
      readDefaultAccountCredentialSecret:
        (overrides.readDefaultAccountCredentialSecret as (() => Promise<unknown>) | undefined) ??
        (async () => ({ status: 'missing' })),
    } as never,
    serverDiscovery: discovery as never,
    libraryTransport: {} as never,
    guideArtworkSessionGenerationOwner: sessionOwner,
    nowMs: () => 1_000,
  });
  return { runtime, sessionOwner, auth, discovery, connection };
}

test('each conservative Plex entrypoint stays unavailable through successful settlement', async () => {
  const successCases = [
    {
      name: 'pollPin', method: 'pollForPin', value: {
        pin: { id: 1, code: 'ABCD', expiresAtMs: 2_000, claimed: false }, profile: null,
      }, invoke: (runtime: DesktopPlexRuntime) => runtime.pollPin('poll-success', 1),
    },
    { name: 'getHomeUsers', method: 'getHomeUsers', value: [], invoke: (runtime: DesktopPlexRuntime) => runtime.getHomeUsers('users-success') },
    {
      name: 'switchHomeUser', method: 'switchHomeUser',
      value: { activeProfile: { accountId: 'account-1', activeProfileId: 'profile-2' } },
      invoke: (runtime: DesktopPlexRuntime) => runtime.switchHomeUser('switch-success', { userId: 'profile-2' }),
    },
    {
      name: 'restoreSelectedServer', method: 'restoreSelectedServer',
      value: { kind: 'selection-failed', reason: 'no-persisted-server', persisted: false },
      invoke: (runtime: DesktopPlexRuntime) => runtime.restoreSelectedServer('restore-success'),
    },
    { name: 'refreshServers', method: 'refreshServers', value: [], invoke: (runtime: DesktopPlexRuntime) => runtime.refreshServers('refresh-success') },
    {
      name: 'selectServer', method: 'selectServer',
      value: { kind: 'selection-failed', reason: 'server-not-found', persisted: false },
      invoke: (runtime: DesktopPlexRuntime) => runtime.selectServer('select-success', 'server-2'),
    },
  ] as const;
  for (const entry of successCases) {
    const gate = rejectingDeferred<unknown>();
    const { runtime, sessionOwner } = runtimeFixture({ [entry.method]: () => gate.promise });
    const before = sessionOwner.captureCurrent(1);
    assert.ok(before);
    const pending = entry.invoke(runtime);
    assert.equal(sessionOwner.captureCurrent(1), null, `${entry.name} pending`);
    gate.resolve(entry.value);
    assert.equal((await pending).ok, true, `${entry.name} result`);
    const after = sessionOwner.captureCurrent(1);
    assert.ok(after, `${entry.name} settled`);
    assert.notEqual(after.generationId, before.generationId, `${entry.name} same-valued invalidation`);
  }
});

test('all conservative Plex operations hold artwork unavailable through failure settlement', async () => {
  const operations = [
    ['pollPin', (runtime: DesktopPlexRuntime) => runtime.pollPin('poll', 1)],
    ['getHomeUsers', (runtime: DesktopPlexRuntime) => runtime.getHomeUsers('users')],
    ['switchHomeUser', (runtime: DesktopPlexRuntime) => runtime.switchHomeUser('switch', { userId: 'profile-2' })],
    ['restoreSelectedServer', (runtime: DesktopPlexRuntime) => runtime.restoreSelectedServer('restore')],
    ['refreshServers', (runtime: DesktopPlexRuntime) => runtime.refreshServers('refresh')],
    ['selectServer', (runtime: DesktopPlexRuntime) => runtime.selectServer('select', 'server-2')],
  ] as const;
  for (const [method, invoke] of operations) {
    const gate = rejectingDeferred<never>();
    const { runtime, sessionOwner } = runtimeFixture({
      pollForPin: () => gate.promise,
      getHomeUsers: () => gate.promise,
      switchHomeUser: () => gate.promise,
      restoreSelectedServer: () => gate.promise,
      refreshServers: () => gate.promise,
      selectServer: () => gate.promise,
    });
    const pending = invoke(runtime);
    assert.equal(sessionOwner.captureCurrent(1), null, `${method} pending`);
    gate.reject(new Error(`${method} failed`));
    assert.equal((await pending).ok, false, `${method} failure result`);
    assert.ok(sessionOwner.captureCurrent(1), `${method} settled`);
  }
});

test('overlapping same-operation cancellation cannot reopen artwork before the survivor succeeds', async () => {
  const calls: Array<ReturnType<typeof rejectingDeferred<readonly never[]>>> = [];
  const { runtime, sessionOwner } = runtimeFixture({
    getHomeUsers: ({ signal }: { signal: AbortSignal }) => {
      const gate = rejectingDeferred<readonly never[]>();
      calls.push(gate);
      signal.addEventListener('abort', () => gate.reject(new Error('aborted')), { once: true });
      if (signal.aborted) gate.reject(new Error('aborted'));
      return gate.promise;
    },
  });
  const first = runtime.getHomeUsers('first');
  const second = runtime.getHomeUsers('second');
  assert.equal(sessionOwner.captureCurrent(1), null);
  assert.equal((await first).ok, false);
  assert.equal(sessionOwner.captureCurrent(1), null);
  calls[1]!.resolve([]);
  assert.equal((await second).ok, true);
  assert.ok(sessionOwner.captureCurrent(1));
});

test('nested account restoration keeps capture blocked until inner and outer operations settle', async () => {
  const credential = rejectingDeferred<{ status: 'present'; secretValue: string }>();
  const restore = rejectingDeferred<{ accountId: string; activeProfileId: string }>();
  const users = rejectingDeferred<readonly never[]>();
  const { runtime, sessionOwner } = runtimeFixture({
    getAccountTokenForMain: () => null,
    readDefaultAccountCredentialSecret: () => credential.promise,
    restoreAccountToken: () => restore.promise,
    getHomeUsers: () => users.promise,
  });
  const pending = runtime.getHomeUsers('nested-restore');
  assert.equal(sessionOwner.captureCurrent(1), null);
  credential.resolve({ status: 'present', secretValue: 'restored-token' });
  await waitForImmediate();
  assert.equal(sessionOwner.captureCurrent(1), null, 'inner restore pending');
  restore.resolve({ accountId: 'account-1', activeProfileId: 'profile-1' });
  await waitForImmediate();
  assert.equal(sessionOwner.captureCurrent(1), null, 'inner settled but outer pending');
  users.resolve([]);
  assert.equal((await pending).ok, true);
  assert.ok(sessionOwner.captureCurrent(1));
});

test('captured sessions own exact frozen connection fields and artwork fetch never reacquires runtime state', async () => {
  const counts = { profile: 0, token: 0, summary: 0, connection: 0 };
  const exactConnection = {
    uri: 'https://plex.invalid:32400/base', protocol: 'https' as const,
    address: '2001:db8::1', port: 32400, local: false, relay: true, latencyMs: 27,
  };
  const fetched: Array<{ connection: PlexConnection; token: string }> = [];
  const { sessionOwner } = runtimeFixture({
    getActiveUserId: () => { counts.profile += 1; return 'profile-1'; },
    getActiveTokenForMain: () => { counts.token += 1; return 'token-1'; },
    getSelectedServerSummary: () => { counts.summary += 1; return { serverId: 'server-1' }; },
    getSelectedConnectionForMain: () => { counts.connection += 1; return exactConnection; },
  });
  const artworkOwner = new GuideArtworkOwner(sessionOwner, {
    fetchGuideArtwork: async (request) => {
      fetched.push({ connection: request.connection, token: request.token });
      return { bytes: new Uint8Array([1]), mimeType: 'image/jpeg' };
    },
  }, () => 1_000, () => 'artwork-ABCDEFGHIJKLMNOP');
  const ref = artworkOwner.createRef({ locator: '/library/metadata/1/thumb', altText: 'Poster', lineupRevision: 9 });
  assert.ok(ref);
  const afterCapture = { ...counts };
  assert.ok(await artworkOwner.get(ref.id));
  assert.deepEqual(counts, afterCapture);
  assert.deepEqual(fetched, [{ connection: exactConnection, token: 'token-1' }]);
  assert.notEqual(fetched[0]!.connection, exactConnection);
  assert.equal(Object.isFrozen(fetched[0]!.connection), true);
  artworkOwner.dispose();
});

test('runtime transitions close artwork authorization before enqueue, before queued fetch, and after fetch', async () => {
  const home = rejectingDeferred<readonly never[]>();
  const secondHome = rejectingDeferred<readonly never[]>();
  let homeCall = 0;
  const fetches: Array<ReturnType<typeof rejectingDeferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>>> = [];
  let refId = 0;
  const { runtime, sessionOwner } = runtimeFixture({
    getHomeUsers: () => (homeCall++ === 0 ? home.promise : secondHome.promise),
  });
  const artworkOwner = new GuideArtworkOwner(sessionOwner, {
    fetchGuideArtwork: async () => {
      const gate = rejectingDeferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>();
      fetches.push(gate);
      return gate.promise;
    },
  }, () => 1_000, () => `artwork-${String(++refId).padStart(24, 'a')}`);

  const beforeEnqueue = artworkOwner.createRef({ locator: '/library/metadata/1/thumb', altText: 'One', lineupRevision: 1 });
  assert.ok(beforeEnqueue);
  const transition = runtime.getHomeUsers('three-gates');
  assert.equal(await artworkOwner.get(beforeEnqueue.id), null);
  assert.equal(fetches.length, 0);
  home.resolve([]);
  await transition;

  const refs = Array.from({ length: 5 }, (_, index) => artworkOwner.createRef({
    locator: `/library/metadata/${String(index + 2)}/thumb`, altText: 'Poster', lineupRevision: 1,
  })) as Array<NonNullable<ReturnType<typeof artworkOwner.createRef>>>;
  const pending = refs.map((ref) => artworkOwner.get(ref.id));
  await waitForImmediate();
  assert.equal(fetches.length, 4);
  const queuedTransition = runtime.getHomeUsers('three-gates-queued');
  assert.equal(await pending[4], null, 'queued authorization revoked before transport');
  for (const gate of fetches) gate.resolve({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' });
  assert.deepEqual(await Promise.all(pending.slice(0, 4)), [null, null, null, null]);
  secondHome.resolve([]);
  await queuedTransition;
  artworkOwner.dispose();
});

test('shutdown publishes permanent disposal before aborting runtime operations', async () => {
  const trace: string[] = [];
  const { runtime, sessionOwner } = runtimeFixture({
    getHomeUsers: ({ signal }: { signal: AbortSignal }) => new Promise((_resolve, reject) => {
      const abort = () => { trace.push('operation-aborted'); reject(new Error('aborted')); };
      signal.addEventListener('abort', abort, { once: true });
      if (signal.aborted) abort();
    }),
  });
  sessionOwner.subscribe((snapshot) => { if (snapshot.status === 'disposed') trace.push('session-disposed'); });
  const pending = runtime.getHomeUsers('pending');
  await runtime.shutdown();
  await pending;
  assert.deepEqual(trace, ['session-disposed', 'operation-aborted']);
  assert.equal(sessionOwner.captureCurrent(1), null);
});
