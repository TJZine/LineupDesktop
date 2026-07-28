import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  LINEUP_SMOKE_SENTINEL_NAME,
  SmokeBootstrapOwner,
  isSmokeBootstrapCapability,
} from '../../main/smokeBootstrapOwner.js';

test('no smoke marker selects normal startup', () => {
  const owner = new SmokeBootstrapOwner({
    app: {
      getPath: (name) => name === 'userData' ? '/unused/user-data' : '/unused/app-data',
      getName: () => 'Lineup Desktop',
    },
    argv: [],
    environment: {},
    platform: 'linux',
  });
  assert.deepEqual(owner.validate(), { status: 'normal', capability: null });
});

test('valid canonical nonce-bound temporary root grants smoke capability', () => {
  const fixture = createFixture();
  try {
    const result = fixture.validate();
    assert.equal(result.status, 'smoke');
    assert.equal(result.status === 'smoke' && isSmokeBootstrapCapability(result.capability), true);
    if (result.status === 'smoke') {
      assert.equal(
        result.capability.protectionPolicy,
        globalThis.process.platform === 'win32'
          ? 'windows-inherited-userdata-acl'
          : 'posix-0600',
      );
    }
  } finally {
    fixture.cleanup();
  }
});

test('smoke validation fails closed for environment-only and nonce mismatch', () => {
  const fixture = createFixture();
  try {
    assert.equal(fixture.validate({ argv: [] }).status, 'failed');
    assert.equal(fixture.validate({ nonce: '0'.repeat(64) }).status, 'failed');
  } finally {
    fixture.cleanup();
  }
});

test('smoke validation fails closed for insecure POSIX sentinel modes', {
  skip: globalThis.process.platform === 'win32',
}, () => {
  const fixture = createFixture();
  try {
    fs.chmodSync(fixture.sentinelPath, 0o644);
    assert.equal(fixture.validate().status, 'failed');
  } finally {
    fixture.cleanup();
  }
});

test('smoke validation fails closed for symlink roots', {
  skip: globalThis.process.platform === 'win32',
}, () => {
  const fixture = createFixture();
  try {
    const link = path.join(fixture.temporaryRoot, `lineup-${fixture.nonce}-link`);
    fs.symlinkSync(fixture.root, link, 'dir');
    assert.equal(fixture.validate({ root: link }).status, 'failed');
  } finally {
    fixture.cleanup();
  }
});

function createFixture() {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-smoke-test-parent-'));
  const nonce = 'a'.repeat(64);
  const root = fs.mkdtempSync(path.join(temporaryRoot, `lineup-${nonce}-`));
  const sentinelPath = path.join(root, LINEUP_SMOKE_SENTINEL_NAME);
  fs.writeFileSync(
    sentinelPath,
    JSON.stringify({ mode: 'lineup-desktop-smoke-v1', nonce }),
    { flag: 'wx', mode: 0o600 },
  );
  const appData = fs.mkdtempSync(path.join(temporaryRoot, 'app-data-'));
  const validate = (
    overrides: Readonly<{ argv?: readonly string[]; nonce?: string; root?: string }> = {},
  ) => {
    const selectedRoot = overrides.root ?? root;
    return new SmokeBootstrapOwner({
      app: {
        getPath: (name) => name === 'userData' ? selectedRoot : appData,
        getName: () => 'Lineup Desktop',
      },
      argv: overrides.argv ?? [
        `--user-data-dir=${selectedRoot}`,
        `--lineup-smoke-root=${selectedRoot}`,
      ],
      environment: {
        LINEUP_DESKTOP_SMOKE: '1',
        LINEUP_DESKTOP_SMOKE_NONCE: overrides.nonce ?? nonce,
      },
      platform: globalThis.process.platform,
      temporaryDirectory: temporaryRoot,
    }).validate();
  };
  return {
    temporaryRoot,
    nonce,
    root,
    sentinelPath,
    validate,
    cleanup: () => fs.rmSync(temporaryRoot, { recursive: true, force: true }),
  };
}
