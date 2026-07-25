import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { createChannelBuilderSmokeFixture } from '../../main/channel/channelBuilderSmokeFixture.js';
import {
  LINEUP_SMOKE_SENTINEL_NAME,
  SmokeBootstrapOwner,
} from '../../main/smokeBootstrapOwner.js';

test('validated smoke fixture is deterministic, non-empty, and memory-backed', async () => {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-smoke-fixture-parent-'));
  const nonce = 'b'.repeat(64);
  const root = fs.mkdtempSync(path.join(temporaryRoot, `lineup-${nonce}-`));
  const appData = fs.mkdtempSync(path.join(temporaryRoot, 'app-data-'));
  fs.writeFileSync(
    path.join(root, LINEUP_SMOKE_SENTINEL_NAME),
    JSON.stringify({ mode: 'lineup-desktop-smoke-v1', nonce }),
    { flag: 'wx', mode: 0o600 },
  );
  try {
    const grant = new SmokeBootstrapOwner({
      app: {
        getPath: (name) => name === 'userData' ? root : appData,
        getName: () => 'Lineup Desktop',
      },
      argv: [`--user-data-dir=${root}`, `--lineup-smoke-root=${root}`],
      environment: {
        LINEUP_DESKTOP_SMOKE: '1',
        LINEUP_DESKTOP_SMOKE_NONCE: nonce,
      },
      platform: 'linux',
      temporaryDirectory: temporaryRoot,
    }).validate();
    assert.equal(grant.status, 'smoke');
    if (grant.status !== 'smoke') return;
    const fixture = createChannelBuilderSmokeFixture(grant.capability);
    const context = fixture.contextSource.getBuilderContextForMain();
    assert.equal(context?.ok, true);
    const items = await fixture.contextSource.withChannelBuilderFacetSession(
      {
        expectedContext: {
          contextEpoch: 0,
          profileBinding: 'unused' as never,
          serverBinding: 'unused' as never,
          librarySetBinding: 'unused' as never,
        },
        selectedLibraryIds: ['smoke-library'],
        deadlineAtMs: 10,
        signal: new AbortController().signal,
      },
      async (session) => session.listLibraryItemsPage({
        sectionId: 'smoke-library',
        query: { kind: 'recently-added', mediaType: 1 },
        offset: 0,
        limit: 100,
        signal: new AbortController().signal,
      }),
    );
    assert.equal(items.entries.length, 6);
    assert.deepEqual(await fixture.storage.readChannelAggregate(), {
      storedChannelData: null,
      currentChannelId: null,
      lineupRevision: 0,
      channelBuilderState: null,
    });
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});

test('smoke fixture rejects an unvalidated value', () => {
  assert.throws(() => createChannelBuilderSmokeFixture({} as never));
});
