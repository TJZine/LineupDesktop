import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

import {
  buildSmokeSpawnOptions,
  createSmokeBootstrap,
} from '../smoke-electron.mjs';

test('smoke launcher creates a canonical nonce-bound sentinel and exact arguments', async () => {
  const bootstrap = await createSmokeBootstrap('linux');
  try {
    assert.match(bootstrap.nonce, /^[a-f0-9]{64}$/u);
    assert.ok(bootstrap.canonicalRoot.includes(bootstrap.nonce));
    assert.equal((await fs.lstat(bootstrap.sentinelPath)).mode & 0o777, 0o600);
    assert.deepEqual(
      JSON.parse(await fs.readFile(bootstrap.sentinelPath, 'utf8')),
      { mode: 'lineup-desktop-smoke-v1', nonce: bootstrap.nonce },
    );
    const spawn = buildSmokeSpawnOptions(bootstrap);
    assert.ok(spawn.args.includes(`--user-data-dir=${bootstrap.canonicalRoot}`));
    assert.ok(spawn.args.includes(`--lineup-smoke-root=${bootstrap.canonicalRoot}`));
    assert.equal(spawn.options.env.LINEUP_DESKTOP_SMOKE_NONCE, bootstrap.nonce);
    assert.equal(spawn.options.env.NODE_ENV, 'production');
  } finally {
    await fs.rm(bootstrap.canonicalRoot, { recursive: true, force: true });
  }
});

test('Windows capability branch records ACL policy without numeric mode enforcement', async () => {
  const bootstrap = await createSmokeBootstrap('win32');
  try {
    assert.equal(bootstrap.protectionPolicy, 'windows-inherited-userdata-acl');
  } finally {
    await fs.rm(bootstrap.canonicalRoot, { recursive: true, force: true });
  }
});
