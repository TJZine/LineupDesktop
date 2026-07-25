import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DesktopPlexContextNotifications,
  type DesktopPlexBuilderContextEvent,
} from '../../main/plex/desktopPlexContextNotifications.js';

test('Plex builder context publishes one initial event and value-changing revisions', () => {
  const owner = new DesktopPlexContextNotifications();
  const events: DesktopPlexBuilderContextEvent[] = [];
  const unsubscribe = owner.subscribe((event) => events.push(event));
  assert.deepEqual(events, [{ kind: 'initial', revision: 0, result: null }]);

  owner.publish({ ok: false, error: { code: 'profile-unavailable' } });
  owner.publish({ ok: false, error: { code: 'profile-unavailable' } });
  owner.publish({
    ok: true,
    snapshot: {
      activeProfileId: 'profile',
      selectedServerId: 'server',
      libraryPairs: [
        { libraryId: '2', libraryUuid: 'uuid-2' },
        { libraryId: '1', libraryUuid: 'uuid-1' },
      ],
    },
  });
  assert.deepEqual(events, [
    { kind: 'initial', revision: 0, result: null },
    {
      kind: 'changed',
      revision: 1,
      result: { ok: false, error: { code: 'profile-unavailable' } },
    },
    {
      kind: 'changed',
      revision: 2,
      result: {
        ok: true,
        snapshot: {
          activeProfileId: 'profile',
          selectedServerId: 'server',
          libraryPairs: [
            { libraryId: '1', libraryUuid: 'uuid-1' },
            { libraryId: '2', libraryUuid: 'uuid-2' },
          ],
        },
      },
    },
  ]);
  unsubscribe();
  unsubscribe();
  owner.publish({ ok: false, error: { code: 'server-unavailable' } });
  assert.equal(events.length, 3);
});

test('Plex builder context isolates listeners and returns ownership-safe clones', () => {
  const owner = new DesktopPlexContextNotifications();
  let observed = 0;
  owner.subscribe(() => {
    throw new Error('listener detail');
  });
  owner.subscribe(() => {
    observed += 1;
  });
  owner.publish({
    ok: true,
    snapshot: {
      activeProfileId: 'profile',
      selectedServerId: 'server',
      libraryPairs: [{ libraryId: '1', libraryUuid: 'uuid-1' }],
    },
  });
  assert.equal(observed, 2);
  const first = owner.get();
  const second = owner.get();
  assert.notEqual(first, second);
  assert.notEqual(
    first?.ok ? first.snapshot.libraryPairs : null,
    second?.ok ? second.snapshot.libraryPairs : null,
  );
});

test('Plex builder context rejects ambiguous or malformed private catalogs', () => {
  const owner = new DesktopPlexContextNotifications();
  assert.throws(() =>
    owner.publish({
      ok: true,
      snapshot: {
        activeProfileId: 'profile',
        selectedServerId: 'server',
        libraryPairs: [
          { libraryId: '1', libraryUuid: 'uuid-1' },
          { libraryId: '1', libraryUuid: 'uuid-2' },
        ],
      },
    }));
  assert.equal(owner.get(), null);
});
