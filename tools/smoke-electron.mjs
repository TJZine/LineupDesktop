import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import electronPath from 'electron';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mainEntry = path.join(repoRoot, 'dist', 'main', 'index.js');

const child = spawn(electronPath, [mainEntry], {
  cwd: repoRoot,
  env: {
    ...process.env,
    LINEUP_DESKTOP_SMOKE: '1',
    NODE_ENV: 'production',
  },
  stdio: 'inherit',
});

child.on('exit', (code, signal) => {
  if (signal) {
    console.error(`Electron smoke exited via ${signal}.`);
    process.exit(1);
  }
  process.exit(code ?? 1);
});
