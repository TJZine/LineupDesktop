import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers';
import type { platform as processPlatform } from 'node:process';
import { NativePlayerPresentationOwner } from '../../../main/player/nativePlayerPresentationOwner.js';
import type { NativePlayerPresentationUpdate, NativePlayerHostPort } from '../../../main/player/nativePlayerHostPort.js';

test('presentation owner negotiates an epoch before touching native state', async () => {
  const updates: NativePlayerPresentationUpdate[] = [];
  const host = { updatePresentation: async (update: NativePlayerPresentationUpdate) => { updates.push(update); return { ok: true as const, status: 'applied' as const }; } } as NativePlayerHostPort;
  const owner = createOwner(host);
  assert.deepEqual(await owner.update(request(null, 1)), { ok: true, status: 'deferred', documentEpoch: 1, revision: 1 });
  assert.equal(updates.length, 0);
  assert.equal((await owner.update(request(1, 2))).status, 'applied');
  assert.equal(updates.length, 1);
  assert.equal(updates[0]?.parentHwnd, '42');
});

test('presentation owner keeps one active and only the latest trailing update', async () => {
  const resolvers: Array<(value: { ok: true; status: 'applied' | 'hidden' }) => void> = [];
  const host = { updatePresentation: (_update: NativePlayerPresentationUpdate) => new Promise<{ ok: true; status: 'applied' | 'hidden' }>((resolve) => resolvers.push(resolve)) } as NativePlayerHostPort;
  const owner = createOwner(host);
  await owner.update(request(null, 1));
  const active = owner.update(request(1, 2));
  const replaced = owner.update(request(1, 3));
  const latest = owner.update(request(1, 4));
  assert.equal((await replaced).status, 'main-stale');
  assert.equal(resolvers.length, 1);
  resolvers[0]?.({ ok: true, status: 'applied' });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(resolvers.length, 2); // active revalidation closes native first
  resolvers[1]?.({ ok: true, status: 'hidden' });
  assert.equal((await active).status, 'helper-stale');
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(resolvers.length, 3);
  resolvers[2]?.({ ok: true, status: 'applied' });
  assert.equal((await latest).status, 'applied');
});

test('presentation owner copies trailing geometry before later caller mutation', async () => {
  const updates: NativePlayerPresentationUpdate[] = [];
  const resolvers: Array<(value: { ok: true; status: 'applied' | 'hidden' }) => void> = [];
  const host = {
    updatePresentation: (update: NativePlayerPresentationUpdate) => {
      updates.push(update);
      return new Promise<{ ok: true; status: 'applied' | 'hidden' }>((resolve) => resolvers.push(resolve));
    },
  } as NativePlayerHostPort;
  const owner = createOwner(host);
  await owner.update(request(null, 1));
  const active = owner.update(request(1, 2));
  const rect = { x: 0.5, y: 0.5, width: 0.25, height: 0.25 };
  const trailing = owner.update({
    documentEpoch: 1,
    revision: 3,
    requestId: 'media-1',
    mode: 'guide-classic-pip',
    rect,
  });
  rect.x = -1;
  rect.width = 2;

  resolvers[0]?.({ ok: true, status: 'applied' });
  await new Promise((resolve) => setImmediate(resolve));
  resolvers[1]?.({ ok: true, status: 'hidden' });
  assert.equal((await active).status, 'helper-stale');
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(updates[2]?.bounds, { x: 0.5, y: 0.5, width: 0.25, height: 0.25 });
  resolvers[2]?.({ ok: true, status: 'applied' });
  assert.equal((await trailing).status, 'applied');
});

test('presentation owner keeps non-Windows opaque and unsupported', async () => {
  const owner = createOwner(null, 'darwin');
  await owner.update(request(null, 1));
  assert.equal((await owner.update(request(1, 2))).status, 'unsupported');
});

test('internal hidden barriers preserve first-null epoch negotiation across navigation', async () => {
  const updates: NativePlayerPresentationUpdate[] = [];
  const host = {
    updatePresentation: async (update: NativePlayerPresentationUpdate) => {
      updates.push(update);
      return { ok: true as const, status: update.mode === 'hidden' ? 'hidden' as const : 'applied' as const };
    },
  } as NativePlayerHostPort;
  const owner = createOwner(host);
  assert.equal((await owner.hide()).status, 'hidden');
  assert.deepEqual(await owner.update(request(null, 1)), { ok: true, status: 'deferred', documentEpoch: 1, revision: 1 });
  assert.equal((await owner.update(request(1, 2))).status, 'applied');
  assert.equal((await owner.hide()).status, 'hidden');
  assert.equal(owner.invalidateDocument(), true);
  assert.equal((await owner.hide()).status, 'hidden');
  assert.deepEqual(await owner.update(request(null, 1)), { ok: true, status: 'deferred', documentEpoch: 2, revision: 1 });
  assert.equal((await owner.update(request(2, 2))).status, 'applied');
  assert.deepEqual(updates.map(({ documentEpoch, revision, mode }) => ({ documentEpoch, revision, mode })), [
    { documentEpoch: 1, revision: 1, mode: 'hidden' },
    { documentEpoch: 1, revision: 2, mode: 'player-full' },
    { documentEpoch: 1, revision: 2, mode: 'hidden' },
    { documentEpoch: 2, revision: 1, mode: 'hidden' },
    { documentEpoch: 2, revision: 2, mode: 'player-full' },
  ]);
});

test('presentation owner keeps 10,000 updates at one active and one latest trailing operation', async () => {
  const updates: NativePlayerPresentationUpdate[] = [];
  const resolvers: Array<(value: { ok: true; status: 'applied' | 'hidden' }) => void> = [];
  const host = {
    updatePresentation: (update: NativePlayerPresentationUpdate) => {
      updates.push(update);
      return new Promise<{ ok: true; status: 'applied' | 'hidden' }>((resolve) => resolvers.push(resolve));
    },
  } as NativePlayerHostPort;
  const owner = createOwner(host);
  await owner.update(request(null, 1));
  const active = owner.update(request(1, 2));
  let staleSettlements = 0;
  const trailing: Array<Promise<unknown>> = [];
  let latest: ReturnType<NativePlayerPresentationOwner['update']> | null = null;
  for (let revision = 3; revision <= 10_001; revision += 1) {
    const pending = owner.update(request(1, revision));
    latest = pending;
    if (revision < 10_001) trailing.push(pending.then((result) => { if (result.status === 'main-stale') staleSettlements += 1; }));
  }
  await Promise.all(trailing);
  assert.equal(staleSettlements, 9_998);
  assert.equal(updates.length, 1);
  resolvers[0]?.({ ok: true, status: 'applied' });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(updates.length, 2);
  assert.equal(updates[1]?.mode, 'hidden');
  resolvers[1]?.({ ok: true, status: 'hidden' });
  assert.equal((await active).status, 'helper-stale');
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(updates.length, 3);
  assert.equal(updates[2]?.revision, 10_001);
  resolvers[2]?.({ ok: true, status: 'applied' });
  assert.notEqual(latest, null);
  if (latest === null) throw new Error('Expected the latest presentation update.');
  assert.equal((await latest).status, 'applied');
});

test('presentation owner fails closed when document epoch cannot advance', async () => {
  const host = {
    updatePresentation: async (update: NativePlayerPresentationUpdate) => ({ ok: true as const, status: update.mode === 'hidden' ? 'hidden' as const : 'applied' as const }),
  } as NativePlayerHostPort;
  const owner = createOwner(host, 'win32', Number.MAX_SAFE_INTEGER);
  assert.equal((await owner.hide()).status, 'hidden');
  assert.equal(owner.invalidateDocument(), false);
  assert.equal((await owner.update(request(null, 1))).status, 'rejected');
});

test('presentation owner distinguishes pre-send rejection from shared-host failure', async () => {
  const preSend = createOwner({
    updatePresentation: async () => ({
      ok: false as const, classification: 'pre-send-rejected' as const,
      error: { code: 'X', message: 'safe', category: 'helper-failure' as const, recoverable: true, retryable: false },
    }),
  });
  await preSend.update(request(null, 1));
  assert.equal((await preSend.update(request(1, 2))).status, 'rejected');
  const shared = createOwner({
    updatePresentation: async () => ({
      ok: false as const, classification: 'shared-host-failure' as const,
      error: { code: 'X', message: 'safe', category: 'helper-failure' as const, recoverable: true, retryable: true },
    }),
  });
  await shared.update(request(null, 1));
  assert.equal((await shared.update(request(1, 2))).status, 'lifecycle-failure');
});

test('presentation owner maps corrective-hide settlement exactly before reporting staleness', async (t) => {
  const vectors = [
    { name: 'hidden', hidden: { ok: true as const, status: 'hidden' as const }, expected: 'helper-stale' },
    { name: 'nonhidden-applied', hidden: { ok: true as const, status: 'applied' as const }, expected: 'lifecycle-failure' },
    { name: 'nonhidden-stale', hidden: { ok: true as const, status: 'stale' as const }, expected: 'helper-stale' },
    {
      name: 'pre-send', expected: 'rejected',
      hidden: { ok: false as const, classification: 'pre-send-rejected' as const, error: nativeFailure('helper-failure') },
    },
    {
      name: 'timeout', expected: 'timeout',
      hidden: { ok: false as const, classification: 'shared-host-failure' as const, error: nativeFailure('timeout') },
    },
    {
      name: 'lifecycle', expected: 'lifecycle-failure',
      hidden: { ok: false as const, classification: 'shared-host-failure' as const, error: nativeFailure('helper-failure') },
    },
  ] as const;
  for (const vector of vectors) {
    await t.test(vector.name, async () => {
      const updates: NativePlayerPresentationUpdate[] = [];
      const firstResolvers: Array<(value: { ok: true; status: 'applied' }) => void> = [];
      const host = {
        updatePresentation: (update: NativePlayerPresentationUpdate) => {
          updates.push(update);
          if (updates.length === 1) {
            return new Promise<{ ok: true; status: 'applied' }>((resolve) => firstResolvers.push(resolve));
          }
          if (update.mode === 'hidden') return Promise.resolve(vector.hidden);
          return Promise.resolve({ ok: true as const, status: 'applied' as const });
        },
      };
      const owner = createOwner(host);
      await owner.update(request(null, 1));
      const active = owner.update(request(1, 2));
      const latest = owner.update(request(1, 3));
      firstResolvers[0]?.({ ok: true, status: 'applied' });
      assert.equal((await active).status, vector.expected);
      assert.equal((await latest).status, 'applied');
      assert.equal(updates[1]?.mode, 'hidden');
    });
  }
});

test('presentation owner treats an applied ACK for hidden as an unhealthy post-send failure', async () => {
  const owner = createOwner({
    updatePresentation: async () => ({ ok: true as const, status: 'applied' as const }),
  });
  const result = await owner.update({
    documentEpoch: null, revision: 1, requestId: null, mode: 'hidden', rect: null,
  });
  assert.equal(result.status, 'lifecycle-failure');
});

test('presentation owner shares concurrent disposal and rejects updates and invalidation while hiding', async () => {
  const updates: NativePlayerPresentationUpdate[] = [];
  const resolvers: Array<(value: { ok: true; status: 'hidden' }) => void> = [];
  const owner = createOwner({
    updatePresentation: (update: NativePlayerPresentationUpdate) => {
      updates.push(update);
      return new Promise<{ ok: true; status: 'hidden' }>((resolve) => resolvers.push(resolve));
    },
  });

  const disposal = owner.dispose();
  assert.equal(owner.dispose(), disposal);
  assert.equal(updates.length, 1);
  assert.equal(updates[0]?.mode, 'hidden');
  assert.equal((await owner.update(request(null, 1))).status, 'rejected');
  assert.equal(owner.invalidateDocument(), false);

  resolvers[0]?.({ ok: true, status: 'hidden' });
  await disposal;
  assert.equal((await owner.hide()).status, 'lifecycle-failure');
  assert.equal(updates.length, 1);
});

function createOwner(
  host: Pick<NativePlayerHostPort, 'updatePresentation'> | null,
  platform: typeof processPlatform = 'win32',
  initialDocumentEpoch?: number,
) {
  return new NativePlayerPresentationOwner({
    platform, host,
    getSnapshot: () => ({
      requestId: 'media-1', status: 'playing', media: null, capabilityProfileId: null,
      seekSupport: 'unknown', positionMs: 0, durationMs: null, bufferedRanges: [], playing: true,
      volume: 1, muted: false, playbackRate: 1, selectedAudioTrackId: null,
      selectedSubtitleTrackId: null, selectedVideoTrackId: null, tracks: [],
      quality: { mode: 'unknown', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unknown' }, lastError: null,
    }),
    getParentIdentity: () => ({ hwnd: '42', pid: 9 }),
    initialDocumentEpoch,
  });
}
function request(documentEpoch: number | null, revision: number) {
  return { documentEpoch, revision, requestId: 'media-1', mode: 'player-full', rect: { x: 0, y: 0, width: 1, height: 1 } };
}

function nativeFailure(category: 'helper-failure' | 'timeout') {
  return {
    code: 'PLAYER_HELPER_TEST_FAILURE',
    message: 'safe',
    category,
    recoverable: true,
    retryable: true,
  } as const;
}
