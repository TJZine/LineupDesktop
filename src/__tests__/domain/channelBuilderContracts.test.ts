import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  CHANNEL_BUILDER_FACET_WARNING_CODES,
  CHANNEL_BUILDER_STRATEGY_KEYS,
  CHANNEL_SETUP_BEHAVIOR_DEFAULTS,
  containsChannelBuilderCredentialMarker,
  convertFacetWarnings,
  createDefaultChannelSetupConfig,
  isValidChannelBuilderFacetSnapshotAggregate,
  normalizeChannelSetupConfig,
  projectChannelBuilderSafeDisplayString,
} from '../../domain/channelBuilder/index.js';

describe('channel builder contracts', () => {
  it('owns the complete deeply immutable behavior defaults', () => {
    assert.deepEqual(CHANNEL_BUILDER_STRATEGY_KEYS, [
      'collections',
      'playlists',
      'genres',
      'directors',
      'decades',
      'recentlyAdded',
      'studios',
      'actors',
    ]);
    assert.deepEqual(CHANNEL_SETUP_BEHAVIOR_DEFAULTS, {
      maxChannels: 200,
      minItemsPerChannel: 5,
      buildMode: 'replace',
      actorStudioCombineMode: 'separate',
      strategyConfig: {
        collections: { enabled: true, priority: 2, scope: 'per-library' },
        playlists: { enabled: true, priority: 1, scope: 'per-library' },
        genres: { enabled: true, priority: 4, scope: 'per-library' },
        directors: { enabled: true, priority: 8, scope: 'per-library' },
        decades: { enabled: true, priority: 7, scope: 'per-library' },
        recentlyAdded: { enabled: true, priority: 3, scope: 'per-library' },
        studios: { enabled: true, priority: 5, scope: 'per-library' },
        actors: { enabled: true, priority: 6, scope: 'per-library' },
      },
      channelExpansion: {
        addAlternateLineups: false,
        alternateLineupCopies: 1,
        variantType: 'none',
        variantBlockSize: 3,
      },
      seriesOrdering: { basePlaybackMode: 'shuffle', baseBlockSize: 3 },
    });
    assert.equal(Object.isFrozen(CHANNEL_SETUP_BEHAVIOR_DEFAULTS), true);
    assert.equal(Object.isFrozen(CHANNEL_SETUP_BEHAVIOR_DEFAULTS.strategyConfig), true);
  });

  it('creates and normalizes only complete exact context-bound configs', () => {
    const context = { serverId: 'server-1', selectedLibraryIds: ['library-1'] };
    const created = createDefaultChannelSetupConfig(context);
    assert.equal(created.ok, true);
    if (!created.ok) return;
    assert.deepEqual(Object.keys(created.config).sort(), [
      'actorStudioCombineMode',
      'buildMode',
      'channelExpansion',
      'maxChannels',
      'minItemsPerChannel',
      'selectedLibraryIds',
      'seriesOrdering',
      'serverId',
      'strategyConfig',
    ]);
    assert.deepEqual(normalizeChannelSetupConfig(created.config, context), created);
    assert.deepEqual(
      normalizeChannelSetupConfig({ ...created.config, unknown: true }, context),
      { ok: false },
    );
    assert.deepEqual(
      normalizeChannelSetupConfig(
        { ...created.config, selectedLibraryIds: ['other-library'] },
        context,
      ),
      { ok: false },
    );
    assert.equal(
      normalizeChannelSetupConfig(
        {
          ...created.config,
          channelExpansion: {
            ...created.config.channelExpansion,
            addAlternateLineups: true,
            alternateLineupCopies: 3,
          },
        },
        context,
      ).ok,
      true,
    );
    assert.deepEqual(
      normalizeChannelSetupConfig(
        {
          ...created.config,
          channelExpansion: {
            ...created.config.channelExpansion,
            alternateLineupCopies: 4,
          },
        },
        context,
      ),
      { ok: false },
    );
    assert.deepEqual(
      createDefaultChannelSetupConfig({
        serverId: 'server-1',
        selectedLibraryIds: Array.from({ length: 25 }, (_, index) => `library-${index}`),
      }),
      { ok: false },
    );
  });

  it('redacts complete credential-bearing strings and safely projects display text', () => {
    for (const raw of [
      'Authorization: Bearer secret',
      'Bearer secret',
      'token=secret',
      'HEADER value',
      'headers: value',
      'Mixed Headers value',
      'token-secret',
      'Bearer-secret',
      'authorization-secret',
    ]) {
      assert.equal(containsChannelBuilderCredentialMarker(raw), true, raw);
      assert.equal(
        projectChannelBuilderSafeDisplayString(raw, {
          fallback: 'Untitled channel',
          maxUtf16Units: 160,
        }),
        '[redacted]',
        raw,
      );
    }
    assert.equal(containsChannelBuilderCredentialMarker('mytoken'), false);
    assert.equal(
      projectChannelBuilderSafeDisplayString('Visit https://example.com now', {
        fallback: 'Untitled channel',
        maxUtf16Units: 160,
      }),
      'Visit [link] now',
    );
    assert.equal(
      projectChannelBuilderSafeDisplayString('\u0000 <Title> 😀', {
        fallback: 'Untitled channel',
        maxUtf16Units: 7,
      }),
      '‹Title›',
    );
    assert.equal(
      projectChannelBuilderSafeDisplayString('A😀B', {
        fallback: 'Untitled channel',
        maxUtf16Units: 2,
      }),
      'A',
    );
    assert.equal(
      projectChannelBuilderSafeDisplayString('\u0000 \t', {
        fallback: 'Untitled channel',
        maxUtf16Units: 160,
      }),
      'Untitled channel',
    );
  });

  it('validates the exact lexical facet-warning/count state and conversion', () => {
    assert.deepEqual(CHANNEL_BUILDER_FACET_WARNING_CODES, [
      'FACET_CAP_REACHED',
      'FACET_DISCOVERY_TIMEOUT',
      'FACET_EMPTY',
      'FACET_MALFORMED_ENTRIES_OMITTED',
      'FACET_PARTIAL_FAILURE',
      'FACET_UNAVAILABLE',
      'TV_PEOPLE_METADATA_INCOMPLETE',
    ]);
    const aggregate = {
      status: 'slow' as const,
      warningCodes: [
        'FACET_CAP_REACHED',
        'FACET_MALFORMED_ENTRIES_OMITTED',
      ] as const,
      omittedMalformedCount: 2,
      omittedCappedCount: null,
    };
    assert.equal(isValidChannelBuilderFacetSnapshotAggregate(aggregate), true);
    assert.deepEqual(convertFacetWarnings(aggregate), [
      {
        code: 'FACET_CAP_REACHED',
        phase: 'discovery',
        strategy: null,
        affectedCount: null,
      },
      {
        code: 'FACET_MALFORMED_ENTRIES_OMITTED',
        phase: 'discovery',
        strategy: null,
        affectedCount: 2,
      },
    ]);
    assert.equal(
      isValidChannelBuilderFacetSnapshotAggregate({
        ...aggregate,
        warningCodes: ['FACET_EMPTY', 'FACET_EMPTY'],
        omittedMalformedCount: 0,
        omittedCappedCount: 0,
      }),
      false,
    );
    assert.equal(
      isValidChannelBuilderFacetSnapshotAggregate({
        ...aggregate,
        warningCodes: ['FACET_MALFORMED_ENTRIES_OMITTED'],
        omittedMalformedCount: 0,
        omittedCappedCount: 0,
      }),
      false,
    );
  });
});
