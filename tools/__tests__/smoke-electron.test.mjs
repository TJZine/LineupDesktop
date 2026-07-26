import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs/promises';
import test from 'node:test';
import { setImmediate as setNodeImmediate } from 'node:timers';

import {
  buildSmokeSpawnOptions,
  createSmokeBootstrap,
  runElectronSmoke,
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

test('smoke launcher preserves a successful child exit and cleans its temporary root', { timeout: 1_000 }, async () => {
  const child = new FakeSmokeChild();
  let smokeRoot;

  const resultPromise = runElectronSmoke({
    spawnChild: (_executable, args) => {
      smokeRoot = smokeRootFromArgs(args);
      setNodeImmediate(() => child.emit('exit', 0, null));
      return child;
    },
    deadlineMs: 100,
    reapDeadlineMs: 20,
  });

  assert.equal(await resultPromise, 0);
  assert.equal(await pathExists(smokeRoot), false);
  assert.deepEqual(child.killSignals, []);
});

test('smoke launcher force-kills a non-exiting child, reports a fixed failure, and cleans up', { timeout: 1_000 }, async () => {
  const child = new FakeSmokeChild();
  const failures = [];
  let smokeRoot;

  const result = await runElectronSmoke({
    spawnChild: (_executable, args) => {
      smokeRoot = smokeRootFromArgs(args);
      return child;
    },
    deadlineMs: 1,
    reapDeadlineMs: 5,
    reportFailure: (message) => failures.push(message),
  });

  assert.equal(result, 1);
  assert.deepEqual(child.killSignals, ['SIGKILL']);
  assert.deepEqual(failures, ['Electron smoke exceeded its deadline.']);
  assert.equal(await pathExists(smokeRoot), false);
});

class FakeSmokeChild extends EventEmitter {
  killSignals = [];

  kill(signal) {
    this.killSignals.push(signal);
    return true;
  }
}

function smokeRootFromArgs(args) {
  const argument = args.find((value) => value.startsWith('--lineup-smoke-root='));
  assert.ok(argument);
  return argument.slice('--lineup-smoke-root='.length);
}

async function pathExists(candidate) {
  try {
    await fs.access(candidate);
    return true;
  } catch {
    return false;
  }
}
