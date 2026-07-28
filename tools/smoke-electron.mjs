import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  clearTimeout as clearNodeTimeout,
  setTimeout as setNodeTimeout,
} from 'node:timers';
import { fileURLToPath } from 'node:url';
import electronPath from 'electron';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mainEntry = path.join(repoRoot, 'dist', 'main', 'index.js');
const sentinelName = '.lineup-desktop-smoke-sentinel';
const smokeDeadlineMs = 60_000;
const childReapDeadlineMs = 5_000;
const smokeBootstrapFailureMessage = 'Electron smoke setup failed.';
const smokeSpawnFailureMessage = 'Electron smoke failed to start.';
const smokeSignalFailureMessage = 'Electron smoke exited via a signal.';
const smokeTimeoutFailureMessage = 'Electron smoke exceeded its deadline.';
const smokeCleanupFailureMessage = 'Electron smoke cleanup failed.';

export async function createSmokeBootstrap(
  platform = process.platform,
  { onRootCreated = () => {} } = {},
) {
  const temporaryDirectory = await fs.realpath(os.tmpdir());
  const nonce = randomBytes(32).toString('hex');
  let root;
  try {
    root = await fs.mkdtemp(
      path.join(temporaryDirectory, `lineup-desktop-smoke-${nonce}-`),
    );
    onRootCreated(root);
    const canonicalRoot = await fs.realpath(root);
    const relative = path.relative(temporaryDirectory, canonicalRoot);
    if (
      relative.length === 0 ||
      relative.startsWith('..') ||
      path.isAbsolute(relative) ||
      !path.basename(canonicalRoot).includes(nonce)
    ) {
      throw new Error('Electron smoke temporary root validation failed.');
    }
    const sentinelPath = path.join(canonicalRoot, sentinelName);
    await fs.writeFile(
      sentinelPath,
      JSON.stringify({ mode: 'lineup-desktop-smoke-v1', nonce }),
      { flag: 'wx', mode: 0o600 },
    );
    if (platform !== 'win32') {
      await fs.chmod(sentinelPath, 0o600);
      const stat = await fs.lstat(sentinelPath);
      if ((stat.mode & 0o777) !== 0o600) {
        throw new Error('Electron smoke sentinel mode validation failed.');
      }
    }
    return Object.freeze({
      canonicalRoot,
      nonce,
      sentinelPath,
      protectionPolicy:
        platform === 'win32'
          ? 'windows-inherited-userdata-acl'
          : 'posix-0600',
    });
  } catch (error) {
    if (root !== undefined) {
      await fs.rm(root, { recursive: true, force: true });
    }
    throw error;
  }
}

export function buildSmokeSpawnOptions(bootstrap) {
  return {
    args: [
      mainEntry,
      `--user-data-dir=${bootstrap.canonicalRoot}`,
      `--lineup-smoke-root=${bootstrap.canonicalRoot}`,
    ],
    options: {
      cwd: repoRoot,
      env: {
        ...process.env,
        LINEUP_DESKTOP_SMOKE: '1',
        LINEUP_DESKTOP_SMOKE_NONCE: bootstrap.nonce,
        NODE_ENV: 'production',
      },
      stdio: 'inherit',
    },
  };
}

export async function runElectronSmoke({
  createBootstrap = createSmokeBootstrap,
  spawnChild = spawn,
  deadlineMs = smokeDeadlineMs,
  reapDeadlineMs = childReapDeadlineMs,
  reportFailure = (message) => console.error(message),
} = {}) {
  const deadlineAt = Date.now() + deadlineMs;
  let bootstrapRoot;
  let cleanupStartedForRoot;
  let bootstrapAbandoned = false;
  const cleanupRoot = async (root = bootstrapRoot) => {
    if (root === undefined || cleanupStartedForRoot === root) return;
    cleanupStartedForRoot = root;
    await fs.rm(root, { recursive: true, force: true });
  };
  const registerBootstrapRoot = (root) => {
    bootstrapRoot = root;
    if (bootstrapAbandoned) void cleanupRoot(root).catch(() => {});
  };
  const bootstrapPromise = Promise.resolve().then(() => createBootstrap(
    process.platform,
    { onRootCreated: registerBootstrapRoot },
  ));
  let bootstrapDeadlineTimer;
  const bootstrapOutcome = await Promise.race([
    bootstrapPromise.then(
      (bootstrap) => ({ kind: 'ready', bootstrap }),
      () => ({ kind: 'failed' }),
    ),
    new Promise((resolve) => {
      bootstrapDeadlineTimer = setNodeTimeout(
        () => resolve({ kind: 'timeout' }),
        Math.max(0, deadlineAt - Date.now()),
      );
    }),
  ]);
  if (bootstrapDeadlineTimer !== undefined) {
    clearNodeTimeout(bootstrapDeadlineTimer);
  }
  if (bootstrapOutcome.kind !== 'ready') {
    bootstrapAbandoned = true;
    void bootstrapPromise.finally(() => cleanupRoot()).catch(() => {});
    try {
      await cleanupRoot();
    } catch {
      reportFailure(smokeCleanupFailureMessage);
      return 1;
    }
    reportFailure(
      bootstrapOutcome.kind === 'timeout'
        ? smokeTimeoutFailureMessage
        : smokeBootstrapFailureMessage,
    );
    return 1;
  }
  const bootstrap = bootstrapOutcome.bootstrap;
  bootstrapRoot = bootstrap.canonicalRoot;
  const { args, options } = buildSmokeSpawnOptions(bootstrap);
  const cleanup = async () => {
    await cleanupRoot(bootstrap.canonicalRoot);
  };
  let child;
  try {
    child = spawnChild(electronPath, args, options);
  } catch {
    try {
      await cleanup();
    } catch {
      reportFailure(smokeCleanupFailureMessage);
      return 1;
    }
    reportFailure(smokeSpawnFailureMessage);
    return 1;
  }
  const signals = ['SIGINT', 'SIGTERM'];
  const handlers = new Map();
  for (const signal of signals) {
    const handler = () => {
      try {
        child.kill(signal);
      } catch {
        // The bounded lifecycle below still owns settlement and cleanup.
      }
    };
    handlers.set(signal, handler);
    process.once(signal, handler);
  }
  const removeHandlers = () => {
    for (const [signal, handler] of handlers) process.off(signal, handler);
  };
  return new Promise((resolve) => {
    let settled = false;
    let deadlineExpired = false;
    let childExited = false;
    let reapTimer;
    const deadlineTimer = setNodeTimeout(() => {
      deadlineExpired = true;
      reapTimer = setNodeTimeout(() => {
        void settle(1, smokeTimeoutFailureMessage);
      }, reapDeadlineMs);
      try {
        child.kill('SIGKILL');
      } catch {
        // The bounded reap timer still releases child ownership.
      }
    }, Math.max(0, deadlineAt - Date.now()));
    const onError = () => {
      void settle(1, smokeSpawnFailureMessage);
    };
    const onExit = (code, signal) => {
      childExited = true;
      if (deadlineExpired) {
        void settle(1, smokeTimeoutFailureMessage);
        return;
      }
      if (signal) {
        void settle(1, smokeSignalFailureMessage);
        return;
      }
      void settle(code ?? 1);
    };
    const settle = async (code, failureMessage) => {
      if (settled) return;
      settled = true;
      clearNodeTimeout(deadlineTimer);
      if (reapTimer !== undefined) clearNodeTimeout(reapTimer);
      removeHandlers();
      child.off('error', onError);
      child.off('exit', onExit);
      if (deadlineExpired && !childExited) {
        try {
          child.unref();
        } catch {
          // Settlement must remain deterministic for incomplete child doubles.
        }
      }
      let result = code;
      let message = failureMessage;
      try {
        await cleanup();
      } catch {
        result = 1;
        message = smokeCleanupFailureMessage;
      }
      if (message) reportFailure(message);
      resolve(result);
    };
    child.once('error', onError);
    child.once('exit', onExit);
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await runElectronSmoke();
}
