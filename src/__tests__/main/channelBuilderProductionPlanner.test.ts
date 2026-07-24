import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { createDefaultChannelSetupConfig } from '../../domain/channelBuilder/config.js';
import {
  buildChannelSetupPlan,
  createChannelSetupPlanner,
} from '../../domain/channelBuilder/planner.js';
import {
  channelBuilderIdentityOperations,
  type ChannelBuilderIdentityOperations,
} from '../../domain/channelBuilder/planIdentity.js';
import type {
  ChannelBuilderFacetSnapshot,
  ChannelBuilderPlannerInput,
  NormalizedChannelSetupConfig,
} from '../../domain/channelBuilder/types.js';
import {
  buildProductionChannelSetupPlan,
  channelBuilderProductionIdentityOperations,
} from '../../main/channel/channelBuilderProductionPlanner.js';

const pure = channelBuilderIdentityOperations;
const native = channelBuilderProductionIdentityOperations;

function operationParity(
  run: (operations: ChannelBuilderIdentityOperations) => unknown,
): void {
  let pureValue: unknown;
  let nativeValue: unknown;
  let pureError: unknown;
  let nativeError: unknown;
  try {
    pureValue = run(pure);
  } catch (error) {
    pureError = error;
  }
  try {
    nativeValue = run(native);
  } catch (error) {
    nativeError = error;
  }
  if (pureError !== undefined || nativeError !== undefined) {
    assert.ok(pureError instanceof Error);
    assert.ok(nativeError instanceof Error);
    assert.equal(nativeError.name, pureError.name);
    assert.equal(nativeError.message, pureError.message);
    return;
  }
  assert.deepEqual(nativeValue, pureValue);
}

function identityVectors(): readonly ((
  operations: ChannelBuilderIdentityOperations,
) => unknown)[] {
  const profile = pure.createProfileBinding('profile-1');
  const server = pure.createServerBinding('server-1');
  const librarySet = pure.createLibrarySetBinding([
    { libraryId: '2', libraryUuid: 'uuid-2' },
    { libraryId: '1', libraryUuid: 'uuid-1' },
  ]);
  const libraryFacet = pure.createFacetIdentity('library', {
    profileBinding: profile,
    serverBinding: server,
    family: 'library',
    libraryId: '1',
    libraryUuid: 'uuid-1',
    libraryType: 'movie',
  });
  const librarySource = pure.createSourceIdentity({
    type: 'library',
    libraryId: '1',
    libraryType: 'movie',
    includeWatched: true,
    libraryFilter: Object.assign(Object.create(null), {
      genre: 'Drama',
      constructor: 'safe',
    }),
  });
  const candidateInput = {
    origin: {
      profileBinding: profile,
      serverBinding: server,
      librarySetBinding: librarySet,
    },
    sourceReference: {
      kind: 'facet' as const,
      facetId: libraryFacet,
      sourceIdentity: librarySource,
    },
    contentFilterIdentity: null,
    sortOrder: null,
    lineupReplicaIndex: 3,
    isPlaybackModeVariant: true,
    playbackMode: 'block' as const,
    blockSize: 3,
  };
  const candidateIdentity = pure.createCandidateIdentity(candidateInput);
  const facetCommon = { profileBinding: profile, serverBinding: server };
  const playlist = {
    type: 'playlist' as const,
    playlistKey: 'playlist-rating',
    playlistName: 'Ignored',
  };
  const collection = {
    type: 'collection' as const,
    collectionKey: 'collection-rating',
    collectionName: 'Ignored',
  };
  return [
    (operations) => operations.canonicalJsonV1(null),
    (operations) =>
      operations.canonicalJsonV1({
        z: -0,
        a: 'e\u0301',
        n: Number.MAX_VALUE,
        keys: { '2': 'two', '10': 'ten' },
      }),
    (operations) => operations.sha256HexV1(''),
    (operations) => operations.sha256HexV1('abc'),
    (operations) => operations.sha256HexV1('😀'),
    (operations) => operations.sha256HexV1('\ud800'),
    (operations) => operations.sha256HexV1('\udc00'),
    (operations) => operations.createPersistedStringV1(''),
    (operations) => operations.createPersistedStringV1('\u0000\u001f\u007f\u0080'),
    (operations) => operations.createPersistedStringV1('😀'),
    (operations) => operations.createPersistedStringV1('\ud800'),
    (operations) => operations.createPersistedStringV1('\udc00'),
    (operations) => operations.createPersistedStringV1('e\u0301\ud800'),
    (operations) => operations.createProfileBinding('profile-1'),
    (operations) => operations.createServerBinding('server-1'),
    (operations) =>
      operations.createLibrarySetBinding([
        { libraryId: '2', libraryUuid: 'uuid-2' },
        { libraryId: '1', libraryUuid: 'uuid-1' },
      ]),
    (operations) =>
      operations.createFacetIdentity('library', {
        ...facetCommon,
        family: 'library',
        libraryId: '1',
        libraryUuid: 'uuid-1',
        libraryType: 'movie',
      }),
    (operations) =>
      operations.createFacetIdentity('playlist', {
        ...facetCommon,
        family: 'playlist',
        libraryId: null,
        libraryUuid: null,
        ratingKey: 'playlist-rating',
        key: '/playlist/key',
      }),
    (operations) =>
      operations.createFacetIdentity('collection', {
        ...facetCommon,
        family: 'collection',
        libraryId: '1',
        libraryUuid: 'uuid-1',
        ratingKey: 'collection-rating',
        key: '/collection/key',
      }),
    (operations) =>
      operations.createFacetIdentity('recently-added', {
        ...facetCommon,
        family: 'recently-added',
        libraryId: '1',
        libraryUuid: 'uuid-1',
        libraryType: 'movie',
      }),
    ...((
      ['genre', 'director', 'year', 'studio', 'actor'] as const
    ).map(
      (family) => (operations: ChannelBuilderIdentityOperations) =>
        operations.createFacetIdentity(family, {
          ...facetCommon,
          family,
          libraryId: '1',
          libraryUuid: 'uuid-1',
          key: 'tag-key',
          tagValue: 'Tag Value',
          fastKey: 'fast-key',
        }),
    )),
    (operations) => operations.createSourceIdentity(librarySourceInput()),
    (operations) => operations.createSourceIdentity(collection),
    (operations) =>
      operations.createSourceIdentity({
        type: 'show',
        showKey: 'show-rating',
        showName: 'Ignored',
        seasonFilter: [3, 1, 3],
      }),
    (operations) => operations.createSourceIdentity(playlist),
    (operations) =>
      operations.createSourceIdentity({
        type: 'manual',
        items: [
          { ratingKey: '1', title: 'One', durationMs: 1 },
          { ratingKey: '2', title: 'Two', durationMs: 2 },
        ],
      }),
    (operations) =>
      operations.createSourceIdentity({
        type: 'mixed',
        mixMode: 'interleave',
        sources: [playlist, collection],
      }),
    (operations) =>
      operations.createMixedSourceIdentity('sequential', [
        `source:${'1'.repeat(64)}`,
        `source:${'2'.repeat(64)}`,
      ]),
    ...(['genre', 'director', 'studio', 'actor'] as const).map(
      (family) => (operations: ChannelBuilderIdentityOperations) =>
        operations.createTagSemanticGroupIdentity({
          profileBinding: profile,
          serverBinding: server,
          family,
          tagValue: 'DRAMA',
        }),
    ),
    (operations) =>
      operations.createContentFilterIdentity({
        profileBinding: profile,
        serverBinding: server,
        filters: [
          { field: 'year', operator: 'eq', value: 1994 },
          { field: 'genre', operator: 'contains', value: 'Drama' },
        ],
      }),
    (operations) =>
      operations.createContentFilterIdentity({
        profileBinding: profile,
        serverBinding: server,
        filters: null,
      }),
    (operations) => operations.createCandidateIdentityPreimage(candidateInput),
    (operations) => operations.createCandidateIdentity(candidateInput),
    (operations) => operations.createCandidateIdentityTuple(candidateInput),
    (operations) =>
      operations.findByteEqualCandidateTupleIndex(
        [operations.createCandidateIdentityTuple(candidateInput)],
        operations.createCandidateIdentityTuple(candidateInput),
      ),
    (operations) =>
      operations.findByteEqualCandidateTupleIndex(
        [{ identity: candidateIdentity, bytes: '{"source":"first"}' }],
        { identity: candidateIdentity, bytes: '{"source":"second"}' },
      ),
    (operations) =>
      operations.createCandidateId({
        seed: 'seed-1',
        strategy: 'genres',
        candidateIdentity,
        occurrence: 0,
      }),
    (operations) =>
      operations.createPlanIdentity(
        { clock: { nowMs: 1 }, seed: 'seed' } as never,
        { status: 'ready' } as never,
      ),
    (operations) =>
      operations.createDeterministicShuffleSeed('seed-1', 'value-1'),
  ];
}

function librarySourceInput() {
  const libraryFilter = Object.assign(Object.create(null), {
    genre: 'Drama',
    ['e\u0301']: 'decomposed',
    é: 'composed',
    constructor: 'safe',
    prototype: 'safe',
  }) as Record<string, string>;
  Object.defineProperty(libraryFilter, '__proto__', {
    value: 'safe',
    enumerable: true,
  });
  return {
    type: 'library' as const,
    libraryId: '1',
    libraryType: 'movie' as const,
    includeWatched: true,
    libraryFilter,
  };
}

function hostileVectors(): readonly ((
  operations: ChannelBuilderIdentityOperations,
) => unknown)[] {
  const profile = pure.createProfileBinding('profile-1');
  const server = pure.createServerBinding('server-1');
  const librarySet = pure.createLibrarySetBinding([
    { libraryId: '1', libraryUuid: 'uuid-1' },
  ]);
  const sparse = new Array<number>(2);
  sparse[1] = 1;
  const cyclic: Record<string, unknown> = {};
  cyclic.self = cyclic;
  const rawLeaf = {
    type: 'playlist' as const,
    playlistKey: 'leaf',
    playlistName: 'Leaf',
  };
  let tooDeepSource: unknown = rawLeaf;
  for (let index = 0; index < 8; index += 1) {
    tooDeepSource = {
      type: 'mixed',
      mixMode: 'sequential',
      sources: [tooDeepSource],
    };
  }
  const manualItems = Array.from({ length: 501 }, (_, index) => ({
    ratingKey: `item-${index}`,
    title: `Item ${index}`,
    durationMs: 1,
  }));
  const safeLeaf = {
    kind: 'facet' as const,
    facetId: null,
    sourceIdentity: `source:${'1'.repeat(64)}` as const,
  };
  let tooDeepSafeSource: unknown = safeLeaf;
  for (let index = 0; index < 8; index += 1) {
    tooDeepSafeSource = {
      kind: 'mixed',
      sourceIdentity: `source:${'2'.repeat(64)}`,
      mixMode: 'sequential',
      sources: [tooDeepSafeSource],
    };
  }
  const safeManual = {
    kind: 'manual' as const,
    sourceIdentity: `source:${'3'.repeat(64)}` as const,
    items: Array.from({ length: 500 }, () => safeLeaf),
  };
  const candidateWithSource = (sourceReference: unknown) => ({
    origin: {
      profileBinding: profile,
      serverBinding: server,
      librarySetBinding: librarySet,
    },
    sourceReference,
    contentFilterIdentity: null,
    sortOrder: null,
    lineupReplicaIndex: null,
    isPlaybackModeVariant: null,
    playbackMode: 'shuffle',
    blockSize: null,
  });
  return [
    (operations) => operations.canonicalJsonV1(Number.NaN),
    (operations) => operations.canonicalJsonV1(Number.POSITIVE_INFINITY),
    (operations) => operations.canonicalJsonV1(Number.NEGATIVE_INFINITY),
    (operations) => operations.canonicalJsonV1(undefined),
    (operations) => operations.canonicalJsonV1(Symbol('unsupported')),
    (operations) => operations.canonicalJsonV1(1n),
    (operations) => operations.canonicalJsonV1(() => undefined),
    (operations) => operations.canonicalJsonV1(sparse),
    (operations) => operations.canonicalJsonV1(cyclic),
    (operations) => operations.canonicalJsonV1(new Date(0)),
    (operations) => operations.canonicalJsonV1({ é: 1, ['e\u0301']: 2 }),
    (operations) => operations.createProfileBinding(' \u0000 '),
    (operations) => operations.createServerBinding(''),
    (operations) => operations.createLibrarySetBinding([]),
    (operations) =>
      operations.createLibrarySetBinding([
        { libraryId: '1', libraryUuid: 'uuid-1' },
        { libraryId: '1', libraryUuid: 'uuid-2' },
      ]),
    (operations) =>
      operations.createFacetIdentity('library', {
        profileBinding: profile,
        serverBinding: server,
        family: 'library',
        libraryId: '1',
        libraryUuid: 'uuid-1',
        libraryType: 'movie',
        extra: true,
      } as never),
    (operations) =>
      operations.createFacetIdentity('playlist', {
        profileBinding: profile,
        serverBinding: server,
        family: 'playlist',
        libraryId: 'not-null',
        libraryUuid: null,
        ratingKey: 'playlist-rating',
        key: '/playlist/key',
      } as never),
    (operations) => operations.createSourceIdentity(tooDeepSource as never),
    (operations) =>
      operations.createSourceIdentity({
        type: 'manual',
        items: manualItems,
      }),
    (operations) =>
      operations.createSourceIdentity({
        ...librarySourceInput(),
        libraryFilter: { genre: Number.NaN },
      }),
    (operations) =>
      operations.createSourceIdentity({
        ...librarySourceInput(),
        libraryFilter: { tokenizedUrl: 'forbidden' },
      }),
    (operations) =>
      operations.createSourceIdentity({
        type: 'playlist',
        playlistKey: 'playlist-1',
        playlistName: 'Playlist',
        unknown: true,
      } as never),
    (operations) =>
      operations.createSourceIdentity({
        type: 'mixed',
        mixMode: 'sequential',
        sources: [],
      }),
    (operations) => operations.createMixedSourceIdentity('sequential', []),
    (operations) =>
      operations.createTagSemanticGroupIdentity({
        profileBinding: profile,
        serverBinding: server,
        family: 'year' as never,
        tagValue: '1994',
      }),
    (operations) =>
      operations.createTagSemanticGroupIdentity({
        profileBinding: profile,
        serverBinding: server,
        family: 'genre',
        tagValue: 'private-raw-value',
        unknown: true,
      } as never),
    (operations) =>
      operations.createContentFilterIdentity({
        profileBinding: profile,
        serverBinding: server,
        filters: [{ field: 'unknown' as never, operator: 'eq', value: 1 }],
      }),
    (operations) =>
      operations.createContentFilterIdentity({
        profileBinding: profile,
        serverBinding: server,
        filters: [{ field: 'director', operator: 'eq', value: Number.NaN }],
      }),
    (operations) =>
      operations.createCandidateIdentity({
        origin: {
          profileBinding: profile,
          serverBinding: server,
          librarySetBinding: `library-set-binding:${'1'.repeat(64)}`,
        },
        sourceReference: {
          kind: 'facet',
          facetId: null,
          sourceIdentity: `source:${'1'.repeat(64)}`,
        },
        contentFilterIdentity: null,
        sortOrder: null,
        lineupReplicaIndex: 4,
        isPlaybackModeVariant: null,
        playbackMode: 'shuffle',
        blockSize: null,
      } as never),
    (operations) =>
      operations.createCandidateIdentity({
        ...candidateWithSource(safeLeaf),
        unknown: true,
      } as never),
    (operations) =>
      operations.createCandidateIdentity(
        candidateWithSource(tooDeepSafeSource) as never,
      ),
    (operations) =>
      operations.createCandidateIdentity(
        candidateWithSource({
          kind: 'mixed',
          sourceIdentity: `source:${'4'.repeat(64)}`,
          mixMode: 'sequential',
          sources: [safeManual, safeManual],
        }) as never,
      ),
    (operations) =>
      operations.createCandidateId({
        seed: 'seed',
        strategy: 'genres',
        candidateIdentity: `candidate-identity:${'1'.repeat(64)}`,
        occurrence: -1,
      }),
    (operations) =>
      operations.createPlanIdentity(
        { unsupported: undefined } as never,
        { status: 'ready' } as never,
      ),
    (operations) =>
      operations.createDeterministicShuffleSeed('\u0000', 'value'),
  ];
}

function plannerConfig(): NormalizedChannelSetupConfig {
  const result = createDefaultChannelSetupConfig({
    serverId: 'server-1',
    selectedLibraryIds: ['library-1'],
  });
  assert.equal(result.ok, true);
  if (!result.ok) throw new Error('fixture config failed');
  return {
    ...result.config,
    maxChannels: 12,
    strategyConfig: Object.fromEntries(
      Object.entries(result.config.strategyConfig).map(([key, value]) => [
        key,
        { ...value, enabled: key === 'playlists' },
      ]),
    ) as NormalizedChannelSetupConfig['strategyConfig'],
  };
}

function plannerSnapshot(
  status: 'ready' | 'slow' | 'blocked',
  title = 'Playlist \u0000 token=hostile',
): ChannelBuilderFacetSnapshot {
  return {
    context: {
      contextEpoch: 1,
      profileBinding: pure.createProfileBinding('profile-1'),
      serverBinding: pure.createServerBinding('server-1'),
      librarySetBinding: pure.createLibrarySetBinding([
        { libraryId: 'library-1', libraryUuid: 'uuid-1' },
      ]),
    },
    libraries: [
      {
        facetId: `library:${'1'.repeat(64)}`,
        sourceIdentity: pure.createSourceIdentity({
          type: 'library',
          libraryId: 'library-1',
          libraryType: 'movie',
          includeWatched: true,
        }),
        title: 'Movies',
        mediaType: 'movie',
        contentCount: 100,
      },
    ],
    playlists: [
      {
        facetId: `playlist:${'2'.repeat(64)}`,
        sourceIdentity: pure.createSourceIdentity({
          type: 'playlist',
          playlistKey: 'playlist-1',
          playlistName: 'Ignored',
        }),
        title,
        itemCount: 20,
        durationMs: 1,
      },
    ],
    collections: [],
    tags: [],
    recentlyAdded: [],
    aggregate: {
      status,
      warningCodes: status === 'slow' ? ['FACET_DISCOVERY_TIMEOUT'] : [],
      omittedMalformedCount: 0,
      omittedCappedCount: 0,
    },
  };
}

function plannerInput(
  buildMode: 'append' | 'merge' | 'replace',
  status: 'ready' | 'slow' | 'blocked',
): ChannelBuilderPlannerInput {
  return {
    normalizedConfig: { ...plannerConfig(), buildMode },
    facetSnapshot: plannerSnapshot(status),
    existingLineup: [],
    clock: { nowMs: 123 },
    seed: 'seed-1',
  };
}

describe('production Channel Builder planner', () => {
  it('matches every frozen identity operation across golden and hostile classes', () => {
    for (const vector of [...identityVectors(), ...hostileVectors()]) {
      operationParity(vector);
    }
  });

  it('keeps pure defaults and the native bound planner deeply byte-identical', () => {
    const nativeBoundPlanner = createChannelSetupPlanner(native);
    for (const mode of ['append', 'merge', 'replace'] as const) {
      for (const status of ['ready', 'slow', 'blocked'] as const) {
        const input = plannerInput(mode, status);
        const expected = buildChannelSetupPlan(input);
        assert.deepEqual(nativeBoundPlanner(input), expected);
        assert.deepEqual(buildProductionChannelSetupPlan(input), expected);
        assert.deepEqual(buildChannelSetupPlan(input), expected);
      }
    }

    const baseExpandedInput = plannerInput('append', 'ready');
    const expandedInput: ChannelBuilderPlannerInput = {
      ...baseExpandedInput,
      normalizedConfig: {
        ...baseExpandedInput.normalizedConfig,
        channelExpansion: {
          ...baseExpandedInput.normalizedConfig.channelExpansion,
          addAlternateLineups: true,
          alternateLineupCopies: 3,
        },
      },
    };
    const expanded = buildChannelSetupPlan(expandedInput);
    assert.deepEqual(
      expanded.candidateDrafts.map((candidate) => candidate.lineupReplicaIndex),
      [0, 1, 2, 3],
    );
    assert.deepEqual(buildProductionChannelSetupPlan(expandedInput), expanded);

    const first = expanded.candidateDrafts[0]!;
    const matchInput: ChannelBuilderPlannerInput = {
      ...plannerInput('merge', 'ready'),
      existingLineup: [
        {
          id: 'existing-1',
          number: 1,
          name: 'Existing \ud800',
          sourceDisposition: 'matchable',
          sourceReference: first.sourceReference,
          playbackMode: first.playbackMode,
          contentFilterIdentity: first.contentFilterPlan.contentFilterIdentity,
          builderProvenance: {
            schemaVersion: 1,
            identityVersion: 1,
            ...first.origin,
            sourceIdentity: first.sourceReference.sourceIdentity,
            candidateIdentity: first.candidateIdentity,
          },
        },
      ],
    };
    assert.deepEqual(
      buildProductionChannelSetupPlan(matchInput),
      buildChannelSetupPlan(matchInput),
    );

    const hostileDisplayInput: ChannelBuilderPlannerInput = {
      ...plannerInput('replace', 'ready'),
      facetSnapshot: plannerSnapshot('ready', 'Authorization: Bearer secret'),
    };
    const hostile = buildChannelSetupPlan(hostileDisplayInput);
    assert.equal(hostile.candidateDrafts[0]?.displayName, '[redacted]');
    assert.deepEqual(buildProductionChannelSetupPlan(hostileDisplayInput), hostile);
    assert.deepEqual(
      buildProductionChannelSetupPlan(hostileDisplayInput),
      buildProductionChannelSetupPlan(hostileDisplayInput),
    );
  });

  it('uses the bound identity capability for inline-decade construction and validation', () => {
    const baseInput = plannerInput('replace', 'ready');
    const library = baseInput.facetSnapshot.libraries[0]!;
    const decadeInput: ChannelBuilderPlannerInput = {
      ...baseInput,
      normalizedConfig: {
        ...baseInput.normalizedConfig,
        strategyConfig: Object.fromEntries(
          Object.entries(baseInput.normalizedConfig.strategyConfig).map(
            ([key, value]) => [
              key,
              { ...value, enabled: key === 'decades' },
            ],
          ),
        ) as NormalizedChannelSetupConfig['strategyConfig'],
      },
      facetSnapshot: {
        ...baseInput.facetSnapshot,
        playlists: [],
        tags: [
          {
            facetId: `year:${'3'.repeat(64)}`,
            sourceIdentity: `source:${'3'.repeat(64)}`,
            libraryFacetId: library.facetId,
            family: 'year',
            displayTitle: '1994',
            itemCount: 20,
            episodeCount: null,
            distinctSeriesCount: null,
            semanticGroupIdentity: null,
            contentFilterIdentity: null,
            yearValue: 1994,
          },
        ],
      },
    };
    let contentFilterIdentityCalls = 0;
    const countingOperations: ChannelBuilderIdentityOperations = {
      ...native,
      createContentFilterIdentity(input) {
        contentFilterIdentityCalls += 1;
        return native.createContentFilterIdentity(input);
      },
    };
    const expected = buildChannelSetupPlan(decadeInput);
    const actual = createChannelSetupPlanner(countingOperations)(decadeInput);
    assert.deepEqual(actual, expected);
    assert.equal(actual.candidateDrafts[0]?.strategy, 'decades');
    assert.equal(actual.candidateDrafts[0]?.contentFilterPlan.kind, 'inline');
    assert.equal(contentFilterIdentityCalls, 2);
  });

  it('rejects same-digest existing matches when canonical tuple bytes differ', () => {
    const base = buildChannelSetupPlan(plannerInput('replace', 'ready'));
    const candidate = base.candidateDrafts[0]!;
    const collisionIdentity = `candidate-identity:${'a'.repeat(64)}` as const;
    const collisionInput: ChannelBuilderPlannerInput = {
      ...plannerInput('merge', 'ready'),
      existingLineup: [
        {
          id: 'existing-collision',
          number: 1,
          name: 'Existing collision',
          sourceDisposition: 'matchable',
          sourceReference: candidate.sourceReference,
          playbackMode: candidate.playbackMode,
          contentFilterIdentity:
            candidate.contentFilterPlan.contentFilterIdentity,
          builderProvenance: {
            schemaVersion: 1,
            identityVersion: 1,
            ...candidate.origin,
            sourceIdentity: candidate.sourceReference.sourceIdentity,
            candidateIdentity: collisionIdentity,
          },
        },
      ],
    };
    const collisionOperations = (
      operations: ChannelBuilderIdentityOperations,
    ): ChannelBuilderIdentityOperations => {
      let tupleCall = 0;
      return {
        ...operations,
        createCandidateIdentityTuple(input) {
          const tuple = operations.createCandidateIdentityTuple(input);
          const bytes = `${tuple.bytes}:${tupleCall}`;
          tupleCall += 1;
          return { identity: collisionIdentity, bytes };
        },
      };
    };
    const pureCollision = createChannelSetupPlanner(collisionOperations(pure))(
      collisionInput,
    );
    const nativeCollision = createChannelSetupPlanner(
      collisionOperations(native),
    )(collisionInput);
    assert.deepEqual(nativeCollision, pureCollision);
    assert.equal(
      pureCollision.candidateLedger[0]?.classification,
      'new-apply',
    );
    assert.equal(
      pureCollision.existingLedger[0]?.disposition,
      'unmatched-retained',
    );
  });
});
