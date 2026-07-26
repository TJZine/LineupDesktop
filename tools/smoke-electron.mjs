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
const smokeSpawnFailureMessage = 'Electron smoke failed to start.';
const smokeSignalFailureMessage = 'Electron smoke exited via a signal.';
const smokeTimeoutFailureMessage = 'Electron smoke exceeded its deadline.';
const smokeCleanupFailureMessage = 'Electron smoke cleanup failed.';

export async function createSmokeBootstrap(platform = process.platform) {
  const temporaryDirectory = await fs.realpath(os.tmpdir());
  const nonce = randomBytes(32).toString('hex');
  const root = await fs.mkdtemp(
    path.join(temporaryDirectory, `lineup-desktop-smoke-${nonce}-`),
  );
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
  spawnChild = spawn,
  deadlineMs = smokeDeadlineMs,
  reapDeadlineMs = childReapDeadlineMs,
  reportFailure = (message) => console.error(message),
} = {}) {
  const bootstrap = await createSmokeBootstrap();
  const { args, options } = buildSmokeSpawnOptions(bootstrap);
  let cleaned = false;
  const cleanup = async () => {
    if (cleaned) return;
    cleaned = true;
    await fs.rm(bootstrap.canonicalRoot, { recursive: true, force: true });
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
      child.kill(signal);
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
    let reapTimer;
    const deadlineTimer = setNodeTimeout(() => {
      deadlineExpired = true;
      reapTimer = setNodeTimeout(() => {
        void settle(1, smokeTimeoutFailureMessage);
      }, reapDeadlineMs);
      try {
        child.kill('SIGKILL');
      } catch {
        void settle(1, smokeTimeoutFailureMessage);
      }
    }, deadlineMs);
    const settle = async (code, failureMessage) => {
      if (settled) return;
      settled = true;
      clearNodeTimeout(deadlineTimer);
      if (reapTimer !== undefined) clearNodeTimeout(reapTimer);
      removeHandlers();
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
    child.once('error', () => {
      void settle(1, smokeSpawnFailureMessage);
    });
    child.once('exit', (code, signal) => {
      if (deadlineExpired) {
        void settle(1, smokeTimeoutFailureMessage);
        return;
      }
      if (signal) {
        void settle(1, smokeSignalFailureMessage);
        return;
      }
      void settle(code ?? 1);
    });
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await runElectronSmoke();
}
