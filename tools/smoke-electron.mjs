import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import electronPath from 'electron';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mainEntry = path.join(repoRoot, 'dist', 'main', 'index.js');
const userDataDir = await mkdtemp(path.join(os.tmpdir(), 'lineup-desktop-smoke-'));

const child = spawn(electronPath, [mainEntry, `--user-data-dir=${userDataDir}`], {
  cwd: repoRoot,
  env: {
    ...process.env,
    LINEUP_DESKTOP_SMOKE: '1',
    NODE_ENV: 'production',
  },
  stdio: 'inherit',
});

child.on('close', async (code, signal) => {
  try {
    await rm(userDataDir, { recursive: true, force: true });
  } catch {
    console.error('Electron smoke could not remove its isolated user-data directory.');
    process.exitCode = 1;
    return;
  }
  if (signal) console.error(`Electron smoke exited via ${signal}.`);
  process.exitCode = signal ? 1 : code ?? 1;
});
