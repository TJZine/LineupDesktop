import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  clearInterval as clearNodeInterval,
  setImmediate as setNodeImmediate,
  setInterval as setNodeInterval,
} from 'node:timers';

import {
  buildSmokeSpawnOptions,
  createSmokeBootstrap,
  runElectronSmoke,
} from '../smoke-electron.mjs';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

test('smoke composition keeps synchronous and asynchronous player delivery in distinct sinks', async () => {
  const [mainSource, playerIpcSource] = await Promise.all([
    fs.readFile(path.join(repoRoot, 'src/main/index.ts'), 'utf8'),
    fs.readFile(path.join(repoRoot, 'src/main/player/playerIpc.ts'), 'utf8'),
  ]);

  for (const symbol of [
    'sendSynchronousPlayerEvent: sendPlayerEvent',
    'onAsynchronousAdapterEvents: eventRouter.route',
    'onEvents: options.onAsynchronousAdapterEvents',
    'options.sendSynchronousPlayerEvent(event)',
    'cleanupFailedApplicationStartup(',
  ]) {
    assert.ok(
      `${mainSource}\n${playerIpcSource}`.includes(symbol),
      `missing required playback wiring symbol: ${symbol}`,
    );
  }
  assertSymbolsInOrder(
    sliceBetween(mainSource, 'onNativeHostLifecycleFailure:', 'wirePlexPlaybackCleanup({'),
    [
      'acquireCleanupHold()',
      'flushCurrentRuntime()',
      'invalidate()',
      'handleHelperCrash()',
      'releaseCleanupHold()',
    ],
    'native-host crash cleanup',
  );
  assertSymbolsInOrder(
    sliceBetween(mainSource, 'getPlaybackRuntime:', 'bootstrapPlaybackRuntime({'),
    ['acquireCleanupHold()', 'invalidate()', 'runtime.cleanup(', 'releaseCleanupHold()'],
    'Plex playback cleanup',
  );
  assertSymbolsInOrder(
    playerIpcSource,
    [
      'new DesktopPlayerAdapter(',
      'host.onLifecycleFailure?.(options.onNativeHostLifecycleFailure)',
    ],
    'player lifecycle subscription',
  );
  assertSymbolsInOrder(
    sliceBetween(playerIpcSource, 'const unsubscribe = unsubscribeMainLifecycle;', 'return {'),
    ['unsubscribe?.()', 'runtime.adapter?.cleanup()'],
    'player teardown',
  );
  const quitFlow = sliceBetween(mainSource, "app.on('before-quit'", 'function attachContainmentHandlers');
  assertSymbolsInOrder(
    quitFlow,
    [
      'teardownDiagnosticsIpc?.()',
      'playerIpcQuitTeardownComplete || teardown === null',
    ],
    'unconditional diagnostics teardown',
  );
  assertSymbolsInOrder(
    quitFlow,
    ['teardown.teardown()', 'localPlaybackEventRouter?.dispose()', 'localPlaybackRuntime?.teardown()'],
    'deferred quit cleanup',
  );
  assertSymbolsInOrder(
    mainSource,
    [
      'new PlaybackProgramTransitionOwner({',
      'registerPlayerRecoveryIpc({',
      'initializeActiveChannel()',
    ],
    'playback recovery composition',
  );
  assert.doesNotMatch(mainSource, /onChannelTuned\s*:/u);
  assert.doesNotMatch(mainSource, /activeChannelScheduler\.on\(\s*['"]programStart['"]/u);
  assert.doesNotMatch(mainSource, /startCurrentPlayback\(\s*['"]startup['"]\s*\)/u);
  assert.doesNotMatch(playerIpcSource, /sendPlayerEvent/u);
});

function sliceBetween(source, startSymbol, endSymbol) {
  const start = source.indexOf(startSymbol);
  const end = source.indexOf(endSymbol, start + startSymbol.length);
  assert.notEqual(start, -1, `missing source boundary: ${startSymbol}`);
  assert.notEqual(end, -1, `missing source boundary: ${endSymbol}`);
  return source.slice(start, end);
}

function assertSymbolsInOrder(source, symbols, label) {
  let cursor = -1;
  for (const symbol of symbols) {
    const next = source.indexOf(symbol, cursor + 1);
    assert.notEqual(next, -1, `${label} is missing ${symbol}`);
    assert.ok(next > cursor, `${label} has ${symbol} out of order`);
    cursor = next;
  }
}

test('smoke launcher creates a canonical nonce-bound sentinel and exact arguments', async () => {
  const bootstrap = await createSmokeBootstrap(process.platform);
  try {
    assert.match(bootstrap.nonce, /^[a-f0-9]{64}$/u);
    assert.ok(bootstrap.canonicalRoot.includes(bootstrap.nonce));
    assert.equal(
      bootstrap.protectionPolicy,
      process.platform === 'win32'
        ? 'windows-inherited-userdata-acl'
        : 'posix-0600',
    );
    if (process.platform !== 'win32') {
      assert.equal((await fs.lstat(bootstrap.sentinelPath)).mode & 0o777, 0o600);
    }
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
  const child = new FakeSmokeChild({ killResult: false, withRefedHandle: true });
  const failures = [];
  let smokeRoot;

  try {
    const result = await runElectronSmoke({
      spawnChild: (_executable, args) => {
        smokeRoot = smokeRootFromArgs(args);
        return child;
      },
      deadlineMs: 30,
      reapDeadlineMs: 5,
      reportFailure: (message) => failures.push(message),
    });

    assert.equal(result, 1);
    assert.deepEqual(child.killSignals, ['SIGKILL']);
    assert.equal(child.unrefCount, 1);
    assert.equal(child.handle?.hasRef(), false);
    assert.equal(child.listenerCount('error'), 0);
    assert.equal(child.listenerCount('exit'), 0);
    assert.deepEqual(failures, ['Electron smoke exceeded its deadline.']);
    assert.equal(await pathExists(smokeRoot), false);
  } finally {
    child.dispose();
  }
});

test('smoke launcher safely reports bootstrap failure and removes its provisional root', { timeout: 1_000 }, async () => {
  const failures = [];
  const bootstrapRoot = await fs.mkdtemp(
    path.join(os.tmpdir(), 'lineup-smoke-bootstrap-failure-'),
  );

  const result = await runElectronSmoke({
    createBootstrap: (_platform, { onRootCreated }) => {
      onRootCreated(bootstrapRoot);
      throw new Error('untrusted bootstrap detail');
    },
    deadlineMs: 100,
    reportFailure: (message) => failures.push(message),
  });

  assert.equal(result, 1);
  assert.deepEqual(failures, ['Electron smoke setup failed.']);
  assert.equal(await pathExists(bootstrapRoot), false);
});

test('smoke launcher bounds a hung bootstrap and removes its provisional root', { timeout: 1_000 }, async () => {
  const failures = [];
  const bootstrapRoot = await fs.mkdtemp(
    path.join(os.tmpdir(), 'lineup-smoke-bootstrap-hang-'),
  );

  const result = await runElectronSmoke({
    createBootstrap: (_platform, { onRootCreated }) => {
      onRootCreated(bootstrapRoot);
      return new Promise(() => {});
    },
    deadlineMs: 5,
    reapDeadlineMs: 5,
    reportFailure: (message) => failures.push(message),
  });

  assert.equal(result, 1);
  assert.deepEqual(failures, ['Electron smoke exceeded its deadline.']);
  assert.equal(await pathExists(bootstrapRoot), false);
});

class FakeSmokeChild extends EventEmitter {
  killSignals = [];
  unrefCount = 0;

  constructor({ killResult = true, withRefedHandle = false } = {}) {
    super();
    this.killResult = killResult;
    this.handle = withRefedHandle ? setNodeInterval(() => {}, 60_000) : undefined;
  }

  kill(signal) {
    this.killSignals.push(signal);
    return this.killResult;
  }

  unref() {
    this.unrefCount += 1;
    this.handle?.unref();
    return this;
  }

  dispose() {
    if (this.handle !== undefined) clearNodeInterval(this.handle);
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
