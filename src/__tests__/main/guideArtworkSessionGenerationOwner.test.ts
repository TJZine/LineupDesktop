import assert from 'node:assert/strict';
import test from 'node:test';

import { GuideArtworkSessionGenerationOwner } from '../../main/plex/guideArtworkSessionGenerationOwner.js';

function fixture(initialGenerationId = 1) {
  const auth = {
    profileId: 'profile-1',
    token: 'credential-value-1',
    getActiveUserId() { return this.profileId; },
    getActiveTokenForMain() { return this.token; },
  };
  const discovery = {
    serverId: 'server-1',
    connection: {
      uri: 'https://plex.invalid:32400',
      protocol: 'https' as const,
      address: 'plex.invalid',
      port: 32400,
      local: true,
      relay: false,
      latencyMs: 12,
    },
    getSelectedServerSummary() { return { serverId: this.serverId }; },
    getSelectedConnectionForMain() { return this.connection; },
  };
  return {
    auth,
    discovery,
    owner: new GuideArtworkSessionGenerationOwner(auth as never, discovery as never, initialGenerationId),
  };
}

test('artwork session generations are immutable, monotonic, and non-deduplicating', () => {
  const { owner } = fixture();
  const observed: Array<{ id: number; status: string }> = [];
  owner.subscribe((snapshot) => observed.push({ id: snapshot.generationId, status: snapshot.status }));

  owner.invalidateTransition('first');
  owner.invalidateTransition('same-valued-transition');
  const ready = owner.captureCurrent(7);
  assert.ok(ready);
  assert.equal(owner.captureCurrent(7), ready);
  owner.invalidateTransition('same-ready-values');
  const replaced = owner.captureCurrent(7);

  assert.deepEqual(observed.map((entry) => entry.status), [
    'unavailable', 'unavailable', 'ready', 'unavailable', 'ready',
  ]);
  assert.deepEqual(observed.map((entry) => entry.id), [2, 3, 4, 5, 6]);
  assert.notEqual(replaced, ready);
  assert.equal(Object.isFrozen(replaced?.connection), true);
});

test('same profile token or connection field replacement invalidates before fresh capture', () => {
  const { owner, auth, discovery } = fixture();
  const first = owner.captureCurrent(3);
  assert.ok(first);

  auth.token = 'credential-value-2';
  const tokenReplacement = owner.captureCurrent(3);
  assert.equal(tokenReplacement?.generationId, (first?.generationId ?? 0) + 2);
  discovery.connection = { ...discovery.connection, latencyMs: 13 };
  const connectionReplacement = owner.captureCurrent(3);
  assert.equal(connectionReplacement?.generationId, (tokenReplacement?.generationId ?? 0) + 2);
  assert.equal(first?.token, 'credential-value-1');
  assert.equal(first?.connection.latencyMs, 12);
});

test('failed transitions stay unavailable and disposal is permanent and idempotent', () => {
  const { owner, auth } = fixture();
  assert.ok(owner.captureCurrent(1));
  owner.invalidateTransition('transition-start');
  auth.token = '';
  assert.equal(owner.captureCurrent(1), null);
  assert.equal(owner.getSnapshot().status, 'unavailable');

  const notifications: string[] = [];
  owner.subscribe((snapshot) => notifications.push(snapshot.status));
  owner.dispose();
  owner.dispose();
  assert.deepEqual(notifications, ['disposed']);
  assert.equal(owner.captureCurrent(1), null);
  owner.invalidateTransition('late');
  assert.equal(owner.getSnapshot().status, 'disposed');
});

test('generation overflow permanently disposes instead of wrapping', () => {
  const { owner } = fixture(Number.MAX_SAFE_INTEGER - 1);
  owner.invalidateTransition('last-generation');
  assert.equal(owner.getSnapshot().generationId, Number.MAX_SAFE_INTEGER);
  owner.invalidateTransition('overflow');
  assert.equal(owner.getSnapshot().status, 'disposed');
  assert.equal(owner.getSnapshot().generationId, Number.MAX_SAFE_INTEGER);
  assert.equal(owner.captureCurrent(1), null);
});

test('transition leases keep capture unavailable until every overlapping transition settles', () => {
  const { owner } = fixture();
  const statuses: string[] = [];
  owner.subscribe((snapshot) => statuses.push(snapshot.status));

  const first = owner.beginTransition('first');
  const second = owner.beginTransition('second');
  assert.equal(owner.captureCurrent(1), null);
  first.settle();
  first.settle();
  assert.equal(owner.captureCurrent(1), null);
  second.settle();
  assert.ok(owner.captureCurrent(1));
  assert.deepEqual(statuses.slice(0, 2), ['unavailable', 'unavailable']);
});

test('transition settlement after disposal is inert', () => {
  const { owner } = fixture();
  const lease = owner.beginTransition('pending');
  owner.dispose();
  lease.settle();
  lease.settle();
  assert.equal(owner.getSnapshot().status, 'disposed');
  assert.equal(owner.captureCurrent(1), null);
});
