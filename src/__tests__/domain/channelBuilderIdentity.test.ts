import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  canonicalJsonV1,
  createCandidateId,
  createCandidateIdentity,
  createContentFilterIdentity,
  findByteEqualCandidateTupleIndex,
  createFacetIdentity,
  createLibrarySetBinding,
  createPersistedStringV1,
  createPlanIdentity,
  createProfileBinding,
  createServerBinding,
  createSourceIdentity,
  createTagSemanticGroupIdentity,
  sha256HexV1,
} from '../../domain/channelBuilder/index.js';

describe('Channel Builder Identity V1', () => {
  it('matches independent SHA-256 literals and canonical byte rules', () => {
    assert.equal(
      sha256HexV1(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    assert.equal(
      sha256HexV1('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    assert.equal(
      sha256HexV1('😀'),
      'f0443a342c5ef54783a111b51ba56c938e474c32324d90c3a60c9c8e3a37e2d9',
    );
    assert.equal(
      sha256HexV1('\ud800'),
      '83d544ccc223c057d2bf80d3f2a32982c32c3c0db8e2674820da5064783fb097',
    );
    assert.equal(
      sha256HexV1('\udc00'),
      '83d544ccc223c057d2bf80d3f2a32982c32c3c0db8e2674820da5064783fb097',
    );
    assert.equal(canonicalJsonV1({ z: -0, a: 'e\u0301', n: 1e21 }), '{"a":"é","n":1e+21,"z":0}');
    const numericLikeKeys = { '2': 'two', '10': 'ten' };
    const numericLikeBytes = '{"10":"ten","2":"two"}';
    assert.equal(canonicalJsonV1(numericLikeKeys), numericLikeBytes);
    assert.equal(
      sha256HexV1(numericLikeBytes),
      'b71e124675fc80e7314688bffdb68e83515851fb51474125db9a0c4c8aca3808',
    );
    assert.equal(canonicalJsonV1({ value: Number.MAX_VALUE }), '{"value":1.7976931348623157e+308}');
    assert.throws(() => canonicalJsonV1(Number.NaN));
    assert.throws(() => canonicalJsonV1(Number.POSITIVE_INFINITY));
    assert.throws(() => canonicalJsonV1(Number.NEGATIVE_INFINITY));
    const sparse = new Array<number>(2);
    sparse[1] = 1;
    assert.throws(() => canonicalJsonV1(sparse));
    assert.throws(() => canonicalJsonV1({ é: 1, ['e\u0301']: 2 }));
    assert.throws(() => canonicalJsonV1(new Date(0)));
  });

  it('pins every facet family and complete plan identity bytes', () => {
    const profileBinding = createProfileBinding('profile-1');
    const serverBinding = createServerBinding('server-1');
    const common = { profileBinding, serverBinding };
    assert.deepEqual(
      {
        library: createFacetIdentity('library', {
          ...common,
          family: 'library',
          libraryId: '1',
          libraryUuid: 'uuid-1',
          libraryType: 'movie',
        }),
        playlist: createFacetIdentity('playlist', {
          ...common,
          family: 'playlist',
          libraryId: null,
          libraryUuid: null,
          ratingKey: 'playlist-rating',
          key: '/playlist/key',
        }),
        collection: createFacetIdentity('collection', {
          ...common,
          family: 'collection',
          libraryId: '1',
          libraryUuid: 'uuid-1',
          ratingKey: 'collection-rating',
          key: '/collection/key',
        }),
        recentlyAdded: createFacetIdentity('recently-added', {
          ...common,
          family: 'recently-added',
          libraryId: '1',
          libraryUuid: 'uuid-1',
          libraryType: 'movie',
        }),
        ...Object.fromEntries(
          (['genre', 'director', 'year', 'studio', 'actor'] as const).map(
            (family) => [
              family,
              createFacetIdentity(family, {
                ...common,
                family,
                libraryId: '1',
                libraryUuid: 'uuid-1',
                key: 'tag-key',
                tagValue: 'Tag Value',
                fastKey: 'fast-key',
              }),
            ],
          ),
        ),
      },
      {
        library:
          'library:6cd067ae91ecf53077bd910910e02296df0fcfd9dd4e3249b87e2a594f0be897',
        playlist:
          'playlist:64b87d8aa9ed7d7e27cc0fcec28484b9d1548d59d0a4222b65db668f36eae2b1',
        collection:
          'collection:999d16a5c1d1708221b9c1b406e1f98d665cad97e1e3c2814ad9184ff7fa52f9',
        recentlyAdded:
          'recently-added:9e247dcabb327900865429c2a75b012a98d7f5c7242d705246fb76dd0512beeb',
        genre:
          'genre:5e653cb1d14772b1b31742aace6b8575e5c913b8d13ec7814b45146a83fa63a4',
        director:
          'director:c8a9ca5a3d324dc7e55a4b0cd509d3df008ea4981abe7539f8dc8a4c8eae35fe',
        year:
          'year:92af9027e12d653f955c5c4a15bd730b5fba9d5c7f139b9fbf509693c637cbb7',
        studio:
          'studio:0d0298791b881f6a331330e4d3967d862f89b9f8c3eb7b1051df9fa28e144c5b',
        actor:
          'actor:56e00838a5d3be143e79e4205afb47ef540bb9530d941788efb71c1b9101197b',
      },
    );
    const planBytes =
      '{"input":{"clock":{"nowMs":1},"seed":"seed"},"output":{"status":"ready"}}';
    assert.equal(
      canonicalJsonV1({
        input: { clock: { nowMs: 1 }, seed: 'seed' },
        output: { status: 'ready' },
      }),
      planBytes,
    );
    assert.equal(
      createPlanIdentity(
        { clock: { nowMs: 1 }, seed: 'seed' } as never,
        { status: 'ready' } as never,
      ),
      'plan-identity:d1802a0a448a4bc89ad9698587c0d6e257438615a696357750d5cb19c92b7c21',
    );
  });

  it('pins every source variant, order, and resolver-key semantics', () => {
    const playlist = {
      type: 'playlist' as const,
      playlistKey: 'playlist-rating',
      playlistName: 'Ignored A',
    };
    const collection = {
      type: 'collection' as const,
      collectionKey: 'collection-rating',
      collectionName: 'Ignored B',
    };
    const vectors = {
      library: createSourceIdentity({
        type: 'library',
        libraryId: '1',
        libraryType: 'movie',
        includeWatched: true,
        libraryFilter: { genre: 'Drama' },
      }),
      collection: createSourceIdentity(collection),
      show: createSourceIdentity({
        type: 'show',
        showKey: 'show-rating',
        showName: 'Ignored',
        seasonFilter: [3, 1, 3],
      }),
      playlist: createSourceIdentity(playlist),
      manual: createSourceIdentity({
        type: 'manual',
        items: [
          { ratingKey: '1', title: 'One', durationMs: 1 },
          { ratingKey: '2', title: 'Two', durationMs: 2 },
        ],
      }),
      manualReversed: createSourceIdentity({
        type: 'manual',
        items: [
          { ratingKey: '2', title: 'Two', durationMs: 2 },
          { ratingKey: '1', title: 'One', durationMs: 1 },
        ],
      }),
      mixedSequential: createSourceIdentity({
        type: 'mixed',
        mixMode: 'sequential',
        sources: [playlist, collection],
      }),
      mixedSequentialReversed: createSourceIdentity({
        type: 'mixed',
        mixMode: 'sequential',
        sources: [collection, playlist],
      }),
      mixedInterleave: createSourceIdentity({
        type: 'mixed',
        mixMode: 'interleave',
        sources: [playlist, collection],
      }),
      mixedInterleaveReversed: createSourceIdentity({
        type: 'mixed',
        mixMode: 'interleave',
        sources: [collection, playlist],
      }),
    };
    assert.deepEqual(vectors, {
      library:
        'source:aaa337d0a488a2562359929d182167f62635bfd86318e1b50996aed8d194e554',
      collection:
        'source:a1a3f4cbc1ce2e9f49a5ecc19224385ee768f6bb15676b110c9c5d09200b7a2a',
      show: 'source:4c161ff3eabbf08eec14bfcb2cdc7daa043fb0fe5b4382e0f4479f1c7f448037',
      playlist:
        'source:ea2a13471bbb7973109dd7bf56fb1a25e84190929819aa912b2ea70e94217738',
      manual:
        'source:7b3cd724fced5686904e66eeaa1c3a2e1837400a9945756ed3e8e379f4172769',
      manualReversed:
        'source:482902edf7c51c1c96f5d8ce9931df2e6b028fa84d9617583ef4a52ff6fb46eb',
      mixedSequential:
        'source:e5410fbc921e48b11ec3edf6f08dfe204962e002e0ad87354707f55fe5462b2f',
      mixedSequentialReversed:
        'source:97732ef18551fa7ac214edb273e532e28e3b15eeacbd107a1d9f6d52ba8cee4e',
      mixedInterleave:
        'source:58cb079950e002834cd254140da59b21dfbc05f44612da4b8419113d7b66ef64',
      mixedInterleaveReversed:
        'source:bfd558598c81b1686d722b12c9b4fb47f3554a2c7f67c0a1f2d93bee9bc2bc5e',
    });
    assert.equal(
      createSourceIdentity({ ...playlist, playlistName: 'Other presentation' }),
      vectors.playlist,
    );
    assert.notEqual(
      createSourceIdentity({
        ...playlist,
        playlistKey: '/playlist/key',
      }),
      vectors.playlist,
    );
    assert.equal(
      createSourceIdentity({ ...collection, collectionName: 'Other presentation' }),
      vectors.collection,
    );
    assert.notEqual(
      createSourceIdentity({
        ...collection,
        collectionKey: '/collection/key',
      }),
      vectors.collection,
    );
  });

  it('enforces depth-eight and 500-leaf source-tree boundaries', () => {
    const rawLeaf = {
      type: 'playlist' as const,
      playlistKey: 'leaf',
      playlistName: 'Leaf',
    };
    const nestRaw = (wrappers: number): never => {
      let source: unknown = rawLeaf;
      for (let index = 0; index < wrappers; index += 1) {
        source = {
          type: 'mixed',
          mixMode: 'sequential',
          sources: [source],
        };
      }
      return source as never;
    };
    assert.match(createSourceIdentity(nestRaw(7)), /^source:[a-f0-9]{64}$/u);
    assert.throws(() => createSourceIdentity(nestRaw(8)));
    const manualItems = Array.from({ length: 500 }, (_, index) => ({
      ratingKey: `item-${index}`,
      title: `Item ${index}`,
      durationMs: 1,
    }));
    assert.match(
      createSourceIdentity({
        type: 'mixed',
        mixMode: 'sequential',
        sources: [{ type: 'manual', items: manualItems }],
      }),
      /^source:[a-f0-9]{64}$/u,
    );
    assert.throws(() =>
      createSourceIdentity({
        type: 'mixed',
        mixMode: 'sequential',
        sources: [
          { type: 'manual', items: manualItems },
          { type: 'manual', items: manualItems },
        ],
      }),
    );

    const origin = {
      profileBinding: createProfileBinding('profile-1'),
      serverBinding: createServerBinding('server-1'),
      librarySetBinding: createLibrarySetBinding([
        { libraryId: '1', libraryUuid: 'uuid-1' },
      ]),
    };
    const safeLeaf = {
      kind: 'facet' as const,
      facetId: null,
      sourceIdentity: `source:${'1'.repeat(64)}` as const,
    };
    const nestSafe = (wrappers: number): never => {
      let source: unknown = safeLeaf;
      for (let index = 0; index < wrappers; index += 1) {
        source = {
          kind: 'mixed',
          sourceIdentity: `source:${'2'.repeat(64)}`,
          mixMode: 'sequential',
          sources: [source],
        };
      }
      return source as never;
    };
    const candidateInput = (sourceReference: never) => ({
      origin,
      sourceReference,
      contentFilterIdentity: null,
      sortOrder: null,
      lineupReplicaIndex: null,
      isPlaybackModeVariant: null,
      playbackMode: 'shuffle' as const,
      blockSize: null,
    });
    assert.match(
      createCandidateIdentity(candidateInput(nestSafe(7))),
      /^candidate-identity:[a-f0-9]{64}$/u,
    );
    assert.throws(() =>
      createCandidateIdentity(candidateInput(nestSafe(8))),
    );
    const safeManual = {
      kind: 'manual',
      sourceIdentity: `source:${'3'.repeat(64)}`,
      items: Array.from({ length: 500 }, () => safeLeaf),
    };
    assert.match(
      createCandidateIdentity(candidateInput(safeManual as never)),
      /^candidate-identity:[a-f0-9]{64}$/u,
    );
    assert.throws(() =>
      createCandidateIdentity(
        candidateInput({
          kind: 'mixed',
          sourceIdentity: `source:${'4'.repeat(64)}`,
          mixMode: 'sequential',
          sources: [safeManual, safeManual],
        } as never),
      ),
    );
  });

  it('pins literal binding, facet, source, candidate, and candidate-id vectors', () => {
    const profileBinding = createProfileBinding('profile-1');
    const serverBinding = createServerBinding('server-1');
    const librarySetBinding = createLibrarySetBinding([
      { libraryId: '2', libraryUuid: 'uuid-2' },
      { libraryId: '1', libraryUuid: 'uuid-1' },
    ]);
    assert.equal(
      profileBinding,
      'profile-binding:466e3fa8db893ebcfb89a00de7873be4aaa4eb6eb2e58ab4ac81052f95f58151',
    );
    assert.equal(
      serverBinding,
      'server-binding:debd4e86a5fe234afcad97564ef4ca7de5328aebc22c1117752cf02a62a1ae10',
    );
    assert.equal(
      librarySetBinding,
      'library-set-binding:9777830a319572913d2e9196229386c0a33c927fe3e887bc9336022f17d7f52c',
    );
    const facetId = createFacetIdentity('library', {
      profileBinding,
      serverBinding,
      family: 'library',
      libraryId: '1',
      libraryUuid: 'uuid-1',
      libraryType: 'movie',
    });
    const sourceIdentity = createSourceIdentity({
      type: 'library',
      libraryId: '1',
      libraryType: 'movie',
      includeWatched: true,
      libraryFilter: { genre: 'Drama' },
    });
    assert.equal(
      facetId,
      'library:6cd067ae91ecf53077bd910910e02296df0fcfd9dd4e3249b87e2a594f0be897',
    );
    assert.equal(
      sourceIdentity,
      'source:aaa337d0a488a2562359929d182167f62635bfd86318e1b50996aed8d194e554',
    );
    const candidateIdentity = createCandidateIdentity({
      origin: { profileBinding, serverBinding, librarySetBinding },
      sourceReference: { kind: 'facet', facetId, sourceIdentity },
      contentFilterIdentity: null,
      sortOrder: null,
      lineupReplicaIndex: null,
      isPlaybackModeVariant: null,
      playbackMode: 'shuffle',
      blockSize: null,
    });
    assert.equal(
      candidateIdentity,
      'candidate-identity:ebcb958e4f6304cdc59d5382c21fc1c7a9038979f22a2d7cfc0056d51b41b64b',
    );
    assert.equal(
      createCandidateId({
        seed: 'seed-1',
        strategy: 'genres',
        candidateIdentity,
        occurrence: 0,
      }),
      'candidate:1572a197db7d67b97888244a4ac105e1d68b51f82145029f7e7c61f2f5f2ce1f',
    );
    assert.throws(() =>
      createCandidateIdentity({
        origin: { profileBinding, serverBinding, librarySetBinding },
        sourceReference: { kind: 'facet', facetId, sourceIdentity },
        contentFilterIdentity: null,
        sortOrder: null,
        lineupReplicaIndex: 4 as never,
        isPlaybackModeVariant: null,
        playbackMode: 'shuffle',
        blockSize: null,
      }),
    );
    assert.equal(
      createCandidateIdentity({
        origin: { profileBinding, serverBinding, librarySetBinding },
        sourceReference: {
          kind: 'facet',
          facetId: `genre:${'f'.repeat(64)}`,
          sourceIdentity,
        },
        contentFilterIdentity: null,
        sortOrder: null,
        lineupReplicaIndex: null,
        isPlaybackModeVariant: null,
        playbackMode: 'shuffle',
        blockSize: null,
      }),
      candidateIdentity,
    );
    const contentFilterIdentity = createContentFilterIdentity({
      profileBinding,
      serverBinding,
      filters: [{ field: 'year', operator: 'eq', value: 1994 }],
    });
    assert.notEqual(contentFilterIdentity, null);
    assert.notEqual(
      createCandidateIdentity({
        origin: { profileBinding, serverBinding, librarySetBinding },
        sourceReference: { kind: 'facet', facetId, sourceIdentity },
        contentFilterIdentity,
        sortOrder: null,
        lineupReplicaIndex: null,
        isPlaybackModeVariant: null,
        playbackMode: 'shuffle',
        blockSize: null,
      }),
      candidateIdentity,
    );
    assert.throws(() =>
      createCandidateIdentity({
        origin: { profileBinding, serverBinding, librarySetBinding },
        sourceReference: { kind: 'facet', facetId, sourceIdentity },
        contentFilterIdentity: null,
        sortOrder: null,
        lineupReplicaIndex: null,
        isPlaybackModeVariant: null,
        playbackMode: 'shuffle',
        blockSize: null,
        unknown: true,
      } as never),
    );
  });

  it('pins opaque tag-group and content-filter identity domains', () => {
    const profileBinding = createProfileBinding('profile-1');
    const serverBinding = createServerBinding('server-1');
    const group = createTagSemanticGroupIdentity({
      profileBinding,
      serverBinding,
      family: 'genre',
      tagValue: 'Drama',
    });
    const groupBytes =
      `{"family":"genre","groupValue":"drama","profileBinding":` +
      `"${profileBinding}","serverBinding":"${serverBinding}"}`;
    assert.equal(
      sha256HexV1(`lineup-builder/tag-group/v1:${groupBytes}`),
      group.slice('tag-group:'.length),
    );
    assert.equal(
      group,
      'tag-group:610a9d97c0c6f7836b84d234847a207a895e5738202c1edc1f7175b4220eba42',
    );
    assert.equal(
      createTagSemanticGroupIdentity({
        profileBinding,
        serverBinding,
        family: 'genre',
        tagValue: 'DRAMA',
      }),
      group,
    );
    assert.notEqual(
      createTagSemanticGroupIdentity({
        profileBinding,
        serverBinding,
        family: 'actor',
        tagValue: 'Drama',
      }),
      group,
    );

    const filterIdentity = createContentFilterIdentity({
      profileBinding,
      serverBinding,
      filters: [{ field: 'director', operator: 'eq', value: 'Director' }],
    });
    const filterBytes =
      `{"filters":[{"field":"director","operator":"eq","value":"Director"}],` +
      `"profileBinding":"${profileBinding}","serverBinding":"${serverBinding}"}`;
    assert.equal(
      sha256HexV1(`lineup-builder/content-filters/v1:${filterBytes}`),
      filterIdentity?.slice('content-filters:'.length),
    );
    assert.equal(
      filterIdentity,
      'content-filters:ea48e481a702e2b3ffce07615d34af3fe980125fd139ffbdde1af63b941f8c6d',
    );
    assert.equal(
      createContentFilterIdentity({
        profileBinding,
        serverBinding,
        filters: [],
      }),
      null,
    );
    assert.notEqual(
      createContentFilterIdentity({
        profileBinding,
        serverBinding,
        filters: [{ field: 'director', operator: 'eq', value: 'Other' }],
      }),
      filterIdentity,
    );
    assert.equal(JSON.stringify({ group, filterIdentity }).includes('Director'), false);
    assert.throws(
      () =>
        createTagSemanticGroupIdentity({
          profileBinding,
          serverBinding,
          family: 'genre',
          tagValue: 'private-raw-value',
          unknown: true,
        } as never),
      (error: unknown) =>
        error instanceof TypeError &&
        error.message === 'Invalid tag semantic group identity input.' &&
        !error.message.includes('private-raw-value'),
    );
    assert.throws(
      () =>
        createContentFilterIdentity({
          profileBinding,
          serverBinding,
          filters: [
            {
              field: 'director',
              operator: 'eq',
              value: Number.NaN,
            },
          ],
        }),
      (error: unknown) =>
        error instanceof TypeError &&
        error.message === 'Invalid content filter identity input.',
    );
  });

  it('preserves raw persisted strings and ordered manual/mixed identities', () => {
    const raw = `e\u0301\u0000😀\ud800${'x'.repeat(520)}`;
    const persisted = createPersistedStringV1(raw);
    assert.equal(persisted.nfc.startsWith('é\u0000😀\ud800'), true);
    assert.equal(persisted.utf16.length, raw.length);
    assert.equal(
      String.fromCharCode(...persisted.utf16.slice(0, 6)),
      raw.slice(0, 6),
    );
    const first = createSourceIdentity({
      type: 'manual',
      items: [
        { ratingKey: '1', title: 'One', durationMs: 1 },
        { ratingKey: '2', title: 'Two', durationMs: 2 },
      ],
    });
    const reversed = createSourceIdentity({
      type: 'manual',
      items: [
        { ratingKey: '2', title: 'Two', durationMs: 2 },
        { ratingKey: '1', title: 'One', durationMs: 1 },
      ],
    });
    assert.notEqual(first, reversed);
  });

  it('keeps arbitrary and NFC-colliding library-filter keys distinct', () => {
    const first = createSourceIdentity({
      type: 'library',
      libraryId: '1',
      libraryType: 'movie',
      includeWatched: true,
      libraryFilter: {
        arbitrary: 1.25,
        é: Number.MAX_VALUE,
        ['e\u0301']: 'distinct',
      },
    });
    const second = createSourceIdentity({
      type: 'library',
      libraryId: '1',
      libraryType: 'movie',
      includeWatched: true,
      libraryFilter: {
        arbitrary: 1.25,
        ['e\u0301']: Number.MAX_VALUE,
        é: 'distinct',
      },
    });
    assert.notEqual(first, second);
    assert.throws(() =>
      createSourceIdentity({
        type: 'library',
        libraryId: '1',
        libraryType: 'movie',
        includeWatched: true,
        libraryFilter: { tokenizedUrl: 'forbidden' },
      }),
    );
    assert.throws(() =>
      createSourceIdentity({
        type: 'playlist',
        playlistKey: 'playlist-1',
        playlistName: 'Playlist',
        unknown: true,
      } as never),
    );
  });

  it('requires canonical tuple bytes even when candidate digests collide', () => {
    const collisionIdentity = `candidate-identity:${'a'.repeat(64)}` as const;
    assert.equal(
      findByteEqualCandidateTupleIndex(
        [{ identity: collisionIdentity, bytes: '{"source":"first"}' }],
        { identity: collisionIdentity, bytes: '{"source":"second"}' },
      ),
      -1,
    );
    assert.equal(
      findByteEqualCandidateTupleIndex(
        [
          { identity: collisionIdentity, bytes: '{"source":"first"}' },
          { identity: collisionIdentity, bytes: '{"source":"second"}' },
        ],
        { identity: collisionIdentity, bytes: '{"source":"second"}' },
      ),
      1,
    );
  });
});
