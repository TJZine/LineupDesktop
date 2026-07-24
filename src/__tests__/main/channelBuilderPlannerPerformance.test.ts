import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  createDefaultChannelSetupConfig,
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
  createSourceIdentity,
  type ChannelBuilderFacetSnapshot,
} from '../../domain/channelBuilder/index.js';
import { buildProductionChannelSetupPlan } from '../../main/channel/channelBuilderProductionPlanner.js';

function performanceFixture(): Parameters<typeof buildProductionChannelSetupPlan>[0] {
  const configResult = createDefaultChannelSetupConfig({
    serverId: 'server-1',
    selectedLibraryIds: ['library-1'],
  });
  assert.equal(configResult.ok, true);
  if (!configResult.ok) throw new Error('fixture config failed');
  const libraryFacetId = `library:${'1'.repeat(64)}` as const;
  const librarySourceIdentity = createSourceIdentity({
    type: 'library',
    libraryId: 'library-1',
    libraryType: 'movie',
    includeWatched: true,
  });
  const facetSnapshot: ChannelBuilderFacetSnapshot = {
    context: {
      contextEpoch: 1,
      profileBinding: createProfileBinding('profile-1'),
      serverBinding: createServerBinding('server-1'),
      librarySetBinding: createLibrarySetBinding([
        { libraryId: 'library-1', libraryUuid: 'uuid-1' },
      ]),
    },
    libraries: [
      {
        facetId: libraryFacetId,
        sourceIdentity: librarySourceIdentity,
        title: 'Movies',
        mediaType: 'movie',
        contentCount: 50_000,
      },
    ],
    playlists: Array.from({ length: 50_000 }, (_, index) => {
      const digest = index.toString(16).padStart(64, '0');
      return {
        facetId: `playlist:${digest}` as const,
        sourceIdentity: `source:${digest}` as const,
        title: `Playlist ${index.toString().padStart(5, '0')}`,
        itemCount: 5,
        durationMs: 1,
      };
    }),
    collections: [],
    tags: [],
    recentlyAdded: [],
    aggregate: {
      status: 'ready',
      warningCodes: [],
      omittedMalformedCount: 0,
      omittedCappedCount: 0,
    },
  };
  return {
    normalizedConfig: {
      ...configResult.config,
      maxChannels: 500,
      strategyConfig: Object.fromEntries(
        Object.entries(configResult.config.strategyConfig).map(([key, value]) => [
          key,
          { ...value, enabled: key === 'playlists' },
        ]),
      ) as typeof configResult.config.strategyConfig,
    },
    facetSnapshot,
    existingLineup: [],
    clock: { nowMs: 1 },
    seed: 'performance-seed',
  };
}

test(
  'plans the deterministic 50,000-candidate fixture within the Windows reference cap',
  { skip: globalThis.process.env.npm_lifecycle_event !== 'verify:channel-builder-performance' },
  (t) => {
    const input = performanceFixture();
    const warm = buildProductionChannelSetupPlan(input);
    assert.equal(
      warm.planIdentity,
      'plan-identity:23d450b5bc28c3afc9189d5fbaa0987d2009f0b8f7458b02e6f211ea59f4bd5b',
    );
    assert.equal(warm.candidateDrafts.length, 50_000);
    const startedAt = globalThis.performance.now();
    const measured = buildProductionChannelSetupPlan(input);
    const elapsedMs = globalThis.performance.now() - startedAt;
    assert.equal(measured.planIdentity, warm.planIdentity);
    assert.equal(measured.candidateDrafts.length, 50_000);
    t.diagnostic(
      `channel-builder planner invocation ${elapsedMs.toFixed(2)} ms on ${globalThis.process.platform}`,
    );
    if (globalThis.process.platform === 'win32') {
      assert.ok(
        elapsedMs <= 2_000,
        `expected <= 2000 ms on Windows, observed ${elapsedMs.toFixed(2)} ms`,
      );
    }
  },
);
