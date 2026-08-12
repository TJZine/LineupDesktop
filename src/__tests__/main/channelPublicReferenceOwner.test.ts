import assert from 'node:assert/strict';
import test from 'node:test';

import type { ChannelAggregate } from '../../domain/channel/channelPersistenceStore.js';
import type { ChannelConfig } from '../../domain/channel/types.js';
import { ChannelPublicReferenceOwner } from '../../main/channel/channelPublicReferenceOwner.js';

test('allocates full-generation aliases independent of projection call order', () => {
  const aggregate = createAggregate([
    channel('safe-id', 1, false, 'safe-library'),
    channel('token-secret', 2, true, 'Bearer-secret'),
    channel('unsafe id', 3, false, 'safe-library'),
  ]);
  const statusFirst = new ChannelPublicReferenceOwner();
  const generationA = statusFirst.createGeneration(aggregate);
  const statusA = statusFirst.projectStatus(generationA, aggregate, 10);
  const guideA = statusFirst.projectPresentation(generationA, {
    channels: [{ id: 'safe-id', number: '1', name: 'Safe', programs: [] }],
    nowWatching: null,
  });
  const guideFirst = new ChannelPublicReferenceOwner();
  const generationB = guideFirst.createGeneration(aggregate);
  const guideB = guideFirst.projectPresentation(generationB, {
    channels: [{ id: 'safe-id', number: '1', name: 'Safe', programs: [] }],
    nowWatching: null,
  });
  const statusB = guideFirst.projectStatus(generationB, aggregate, 10);

  assert.deepEqual(statusA, statusB);
  assert.deepEqual(guideA, guideB);
  assert.equal(statusA.channels[0]?.id, 'safe-id');
  assert.match(statusA.channels[1]?.id ?? '', /^legacy-channel-/u);
  assert.match(statusA.channels[1]?.sourceLibraryId ?? '', /^legacy-library-/u);
  assert.equal(statusA.channels[2]?.sourceLibraryId, 'safe-library');
});

test('projects program references and resolves only current generation channel references', () => {
  const owner = new ChannelPublicReferenceOwner();
  const aggregate = createAggregate([channel('unsafe id', 1, false, null)]);
  const generation = owner.createGeneration(aggregate);
  const status = owner.projectStatus(generation, aggregate, 10);
  const publicChannelId = status.channels[0]!.id;
  const presentation = owner.projectPresentation(generation, {
    channels: [{
      id: 'unsafe id',
      number: '1',
      name: '\u0000',
      programs: [{
        id: 'raw-private-program',
        title: '',
        subtitle: '',
        description: '',
        showTitle: '',
        episodeLabel: '',
        rating: '',
        quality: [],
        genres: [],
        startsAtMs: 1,
        endsAtMs: 2,
        artwork: { poster: null, background: null },
      }],
    }],
    nowWatching: null,
  });

  assert.equal(owner.resolveChannel(generation, publicChannelId), 'unsafe id');
  assert.equal(owner.resolveChannel(generation, 'missing'), null);
  assert.equal(presentation.channels[0]?.name, 'Untitled channel');
  assert.match(presentation.channels[0]?.programs[0]?.id ?? '', /^guide-program-[a-f0-9]{64}-0$/u);
  assert.equal(presentation.channels[0]?.programs[0]?.title, 'Untitled program');
});

test('owns and sanitizes artwork alt text without retaining hostile scheduled content', () => {
  const owner = new ChannelPublicReferenceOwner();
  const aggregate = createAggregate([channel('channel-1', 1, false, null)]);
  const generation = owner.createGeneration(aggregate);
  const sourcePoster = Object.freeze({
    id: 'artwork-ABCDEFGHIJKLMNOP',
    kind: 'poster' as const,
    expiresAtMs: 10_000,
    altText: 'Bearer secret https://private.invalid/<poster>\u0000'.repeat(8),
    status: 'available' as const,
  });
  const sourceArtwork = Object.freeze({
    poster: sourcePoster,
    background: Object.freeze({ ...sourcePoster, id: 'artwork-QRSTUVWXYZabcdef', kind: 'background' as const }),
  });
  const projected = owner.projectPresentation(generation, {
    channels: [{
      id: 'channel-1', number: '1', name: 'One', programs: [{
        id: 'raw-program',
        title: 'Bearer secret https://private.invalid/<title>\u0000'.repeat(8),
        subtitle: '', description: '', showTitle: '', episodeLabel: '', rating: '',
        quality: [], genres: [], startsAtMs: 1, endsAtMs: 2, artwork: sourceArtwork,
      }],
    }],
    nowWatching: null,
  });
  const program = projected.channels[0]!.programs[0]!;

  assert.equal(program.title, '[redacted]');
  assert.equal(program.artwork.poster?.altText, '[redacted]');
  assert.equal(program.artwork.background?.altText, '[redacted]');
  assert.notEqual(program.artwork.poster, sourceArtwork.poster);
  assert.notEqual(program.artwork.background, sourceArtwork.background);
  assert.equal(Object.isFrozen(program.artwork), true);
  assert.deepEqual(sourceArtwork.poster, {
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 10_000,
    altText: 'Bearer secret https://private.invalid/<poster>\u0000'.repeat(8), status: 'available',
  });
});

test('rejects duplicate raw channel ids and hidden Guide references', () => {
  const owner = new ChannelPublicReferenceOwner();
  assert.throws(() => owner.createGeneration(createAggregate([
    channel('duplicate', 1, false, null),
    channel('duplicate', 2, false, null),
  ])));
  const aggregate = createAggregate([channel('hidden', 1, true, null)]);
  const generation = owner.createGeneration(aggregate);
  assert.throws(() => owner.projectPresentation(generation, {
    channels: [{ id: 'hidden', number: '1', name: 'Hidden', programs: [] }],
    nowWatching: null,
  }));
});

function createAggregate(channels: readonly ChannelConfig[]): ChannelAggregate {
  return {
    storedChannelData: {
      channels: [...channels],
      channelOrder: channels.map((entry) => entry.id),
      currentChannelId: channels.find((entry) => entry.hidden !== true)?.id ?? null,
      savedAt: 1,
    },
    currentChannelId: channels.find((entry) => entry.hidden !== true)?.id ?? null,
    lineupRevision: 2,
    channelBuilderState: null,
  };
}

function channel(
  id: string,
  number: number,
  hidden: boolean,
  sourceLibraryId: string | null,
): ChannelConfig {
  return {
    id,
    number,
    name: `Channel ${number}`,
    hidden,
    sourceLibraryId: sourceLibraryId ?? undefined,
    sourceLibraryName: sourceLibraryId === null ? undefined : 'Library',
    contentSource: {
      type: 'manual',
      items: [{ ratingKey: `item-${number}`, title: 'Item', durationMs: 1_000 }],
    },
    playbackMode: 'sequential',
    startTimeAnchor: 1,
    skipIntros: false,
    skipCredits: false,
    createdAt: 1,
    updatedAt: 1,
    lastContentRefresh: 1,
    itemCount: 1,
    totalDurationMs: 1_000,
  };
}
