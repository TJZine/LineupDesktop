import test from 'node:test';
import assert from 'node:assert/strict';

import { ChannelBuilderContextEpochOwner } from '../../main/channel/channelBuilderContextEpochOwner.js';
import type {
  ChannelBuilderFacetAccessInput,
  ChannelBuilderFacetSession,
} from '../../main/plex/desktopPlexChannelBuilderFacetSource.js';
import {
  DesktopPlexContextNotifications,
  type DesktopPlexBuilderContextListener,
} from '../../main/plex/desktopPlexContextNotifications.js';

test('context epoch owner captures selected pairs and invalidates retained plans independently', () => {
  const source = new FakeContextSource();
  const owner = new ChannelBuilderContextEpochOwner(source);
  source.publishReady([
    { libraryId: '1', libraryUuid: 'uuid-1' },
    { libraryId: '2', libraryUuid: 'uuid-2' },
  ]);
  const first = owner.capture(['1']);
  const second = owner.capture(['2']);
  assert.equal(first.context.contextEpoch, 1);
  assert.deepEqual(first.selectedLibraryPairs, [
    { libraryId: '1', libraryUuid: 'uuid-1' },
  ]);

  let firstInvalidations = 0;
  let secondInvalidations = 0;
  owner.retain({
    planId: 'plan-1',
    ...first,
    invalidate: () => {
      firstInvalidations += 1;
    },
  });
  owner.retain({
    planId: 'plan-2',
    ...second,
    invalidate: () => {
      secondInvalidations += 1;
    },
  });

  source.publishReady([
    { libraryId: '1', libraryUuid: 'uuid-1' },
    { libraryId: '2', libraryUuid: 'uuid-2' },
    { libraryId: '3', libraryUuid: 'uuid-3' },
  ]);
  assert.equal(firstInvalidations, 0);
  assert.equal(secondInvalidations, 0);
  owner.assertCurrent(first.context, first.selectedLibraryPairs);

  source.publishReady([
    { libraryId: '1', libraryUuid: 'uuid-1-changed' },
    { libraryId: '2', libraryUuid: 'uuid-2' },
    { libraryId: '3', libraryUuid: 'uuid-3' },
  ]);
  assert.equal(firstInvalidations, 1);
  assert.equal(secondInvalidations, 0);

  source.notifications.publish({
    ok: true,
    snapshot: {
      activeProfileId: 'profile-2',
      selectedServerId: 'server',
      libraryPairs: [
        { libraryId: '1', libraryUuid: 'uuid-1-changed' },
        { libraryId: '2', libraryUuid: 'uuid-2' },
      ],
    },
  });
  assert.equal(secondInvalidations, 1);
  owner.shutdown();
  owner.shutdown();
});

test('context epoch owner rejects missing pairs and stale discovery epochs safely', async () => {
  const source = new FakeContextSource();
  const owner = new ChannelBuilderContextEpochOwner(source);
  source.publishReady([{ libraryId: '1', libraryUuid: 'uuid-1' }]);
  const selected = owner.capture(['1']);
  assert.throws(() => owner.capture(['missing']), hasContextChangedCode);

  source.publishReady([
    { libraryId: '1', libraryUuid: 'uuid-1' },
    { libraryId: '2', libraryUuid: 'uuid-2' },
  ]);
  await assert.rejects(
    owner.withSession(
      {
        expectedContext: selected.context,
        selectedLibraryIds: ['1'],
        deadlineAtMs: Date.now() + 1_000,
        signal: new AbortController().signal,
      },
      async () => 'unused',
    ),
    hasContextChangedCode,
  );
  assert.equal(source.sessionCalls, 0);
  owner.shutdown();
});

class FakeContextSource {
  readonly notifications = new DesktopPlexContextNotifications();
  sessionCalls = 0;

  getBuilderContextForMain() {
    return this.notifications.get();
  }

  subscribeBuilderContextForMain(listener: DesktopPlexBuilderContextListener) {
    return this.notifications.subscribe(listener);
  }

  async withChannelBuilderFacetSession<T>(
    _input: ChannelBuilderFacetAccessInput,
    _run: (session: ChannelBuilderFacetSession) => Promise<T>,
  ): Promise<T> {
    this.sessionCalls += 1;
    throw new Error('Unexpected session acquisition.');
  }

  publishReady(
    libraryPairs: readonly Readonly<{ libraryId: string; libraryUuid: string }>[],
  ): void {
    this.notifications.publish({
      ok: true,
      snapshot: {
        activeProfileId: 'profile',
        selectedServerId: 'server',
        libraryPairs,
      },
    });
  }
}

function hasContextChangedCode(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === 'CHANNEL_CONTEXT_CHANGED'
  );
}
