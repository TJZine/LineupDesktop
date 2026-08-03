import assert from 'node:assert/strict';
import test from 'node:test';
import { setImmediate as waitForImmediate } from 'node:timers/promises';

import { GuideArtworkOwner } from '../../main/channel/guideArtworkOwner.js';
import type { GuideArtworkReadySession } from '../../main/plex/guideArtworkSessionGenerationOwner.js';
import { deferred } from '../helpers/deferred.js';

function session(generationId = 2): GuideArtworkReadySession {
  return Object.freeze({
    generationId,
    status: 'ready',
    profileBinding: 'profile-binding',
    serverBinding: 'server-binding',
    connection: Object.freeze({
      uri: 'https://plex.invalid:32400', protocol: 'https' as const,
      address: 'plex.invalid', port: 32400, local: true, relay: false, latencyMs: 1,
    }),
    token: ['captured', 'credential'].join('-'),
    lineupRevision: 4,
  });
}

function fixture(input: {
  fetchGuideArtwork?: (request: { signal?: AbortSignal | null }) => Promise<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>;
  current?: () => boolean;
} = {}) {
  const listeners = new Set<() => void>();
  let refCounter = 0;
  const ready = session();
  const owner = new GuideArtworkOwner(
    {
      subscribe(listener: () => void) { listeners.add(listener); return () => listeners.delete(listener); },
      captureCurrent: () => ready,
      isCurrent: () => input.current?.() ?? true,
    } as never,
    {
      fetchGuideArtwork: input.fetchGuideArtwork ?? (async () => ({
        bytes: new Uint8Array([1]), mimeType: 'image/jpeg' as const,
      })),
    },
    () => 1_000,
    () => `artwork-${String(++refCounter).padStart(24, 'a')}`,
  );
  return { owner, emit: () => { for (const listener of [...listeners]) listener(); } };
}

test('artwork refs bind the current session, clamp alt text, and expire', async () => {
  let now = 1_000;
  let refCounter = 0;
  const ready = session();
  const owner = new GuideArtworkOwner(
    { subscribe: () => () => undefined, captureCurrent: () => ready, isCurrent: () => true } as never,
    { fetchGuideArtwork: async () => ({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' }) },
    () => now,
    () => `artwork-${String(++refCounter).padStart(24, 'a')}`,
  );
  const ref = owner.createRef({
    locator: '/library/metadata/1/thumb', altText: 'A'.repeat(200), lineupRevision: 4,
  });
  assert.ok(ref);
  assert.equal(ref.kind, 'poster');
  assert.equal(ref.altText.length, 160);
  assert.ok(await owner.get(ref.id));
  now = ref.expiresAtMs;
  assert.equal(await owner.get(ref.id), null);
});

test('authorization caps at 6000 live refs and cache eviction revokes delivery', async () => {
  const { owner } = fixture();
  const refs = Array.from({ length: 6_001 }, (_, index) => owner.createRef({
    locator: `/library/metadata/${String(index + 1)}/thumb`,
    altText: 'Poster',
    lineupRevision: 4,
  }));
  assert.equal(refs.slice(0, 6_000).every(Boolean), true);
  assert.equal(refs[6_000], null);
  owner.dispose();

  const cacheFixture = fixture();
  const cacheRefs = Array.from({ length: 33 }, (_, index) => cacheFixture.owner.createRef({
    locator: `/library/metadata/${String(index + 1)}/thumb`, altText: 'Poster', lineupRevision: 4,
  }));
  for (const ref of cacheRefs) {
    assert.ok(ref);
    assert.ok(await cacheFixture.owner.get(ref.id));
  }
  assert.equal(await cacheFixture.owner.get(cacheRefs[0]!.id), null);
});

test('createRef reclaims expired authorizations at capacity and rejects their late fetches', async () => {
  let now = 1_000;
  let refCounter = 0;
  const fetch = deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>();
  const ready = session();
  const owner = new GuideArtworkOwner(
    { subscribe: () => () => undefined, captureCurrent: () => ready, isCurrent: () => true } as never,
    { fetchGuideArtwork: async () => fetch.promise },
    () => now,
    () => `artwork-${String(++refCounter).padStart(24, 'a')}`,
  );
  const refs = Array.from({ length: 6_000 }, (_, index) => owner.createRef({
    locator: `/library/metadata/${String(index + 1)}/thumb`, altText: 'Poster', lineupRevision: 4,
  }));
  assert.equal(owner.createRef({ locator: '/library/metadata/full/thumb', altText: 'Full', lineupRevision: 4 }), null);
  const late = owner.get(refs[0]!.id);
  await waitForImmediate();
  now = refs[0]!.expiresAtMs;
  const replacement = owner.createRef({ locator: '/library/metadata/6001/thumb', altText: 'New', lineupRevision: 4 });
  assert.ok(replacement);
  fetch.resolve({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' });
  assert.equal(await late, null);
  assert.equal(await owner.get(refs[0]!.id), null);
});

test('queue allows four fetches, coalesces by ref, and releases a slot', async () => {
  const pending: Array<ReturnType<typeof deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>>> = [];
  let active = 0;
  let maximumActive = 0;
  const { owner } = fixture({
    fetchGuideArtwork: async () => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      const request = deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>();
      pending.push(request);
      return request.promise.finally(() => { active -= 1; });
    },
  });
  const refs = Array.from({ length: 5 }, (_, index) => owner.createRef({
    locator: `/library/metadata/${String(index + 1)}/thumb`, altText: 'Poster', lineupRevision: 4,
  })) as Array<NonNullable<ReturnType<typeof owner.createRef>>>;
  const firstA = owner.get(refs[0]!.id);
  const firstB = owner.get(refs[0]!.id);
  const results = [firstA, ...refs.slice(1).map((ref) => owner.get(ref.id))];
  assert.equal(firstA, firstB);
  await waitForImmediate();
  assert.equal(pending.length, 4);
  pending[0]!.resolve({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' });
  await waitForImmediate();
  assert.equal(pending.length, 5);
  for (const request of pending.slice(1)) {
    request.resolve({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' });
  }
  await Promise.all(results);
  assert.equal(maximumActive, 4);
});

test('generation notification revokes refs and aborts queued and in-flight work', async () => {
  const signals: AbortSignal[] = [];
  const { owner, emit } = fixture({
    fetchGuideArtwork: async ({ signal }) => new Promise((_resolve, reject) => {
      if (signal) {
        signals.push(signal);
        signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
      }
    }),
  });
  const ref = owner.createRef({ locator: '/library/metadata/1/thumb', altText: 'Poster', lineupRevision: 4 });
  assert.ok(ref);
  const pending = owner.get(ref.id);
  await waitForImmediate();
  emit();
  assert.equal(await pending, null);
  assert.equal(signals[0]?.aborted, true);
  assert.equal(await owner.get(ref.id), null);
});

test('currentness is checked before queue, before fetch, and after fetch', async () => {
  let current = true;
  let fetches = 0;
  const fetch = deferred<{ bytes: Uint8Array; mimeType: 'image/jpeg' }>();
  const { owner } = fixture({
    current: () => current,
    fetchGuideArtwork: async () => {
      fetches += 1;
      return fetch.promise;
    },
  });
  const ref = owner.createRef({ locator: '/library/metadata/1/thumb', altText: 'Poster', lineupRevision: 4 });
  assert.ok(ref);
  const pending = owner.get(ref.id);
  await waitForImmediate();
  assert.equal(fetches, 1);
  current = false;
  fetch.resolve({ bytes: new Uint8Array([1]), mimeType: 'image/jpeg' });
  assert.equal(await pending, null);
  assert.equal(await owner.get(ref.id), null);
});
