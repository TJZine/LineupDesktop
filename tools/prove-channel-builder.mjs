import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import electronPath from 'electron';

export const CHANNEL_BUILDER_PROOF_ROOT = 'docs/runs/channel-builder-onboarding-parity';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function parseArgs(argv) {
  if (argv.length !== 2 || argv[0] !== '--out' || argv[1].trim().length === 0) {
    throw new Error(`Usage: node tools/prove-channel-builder.mjs --out ${CHANNEL_BUILDER_PROOF_ROOT}/<run-name>`);
  }
  return { outputDirectory: argv[1] };
}

export function resolveOutputDirectory(value, root = repoRoot) {
  const proofRoot = path.resolve(root, CHANNEL_BUILDER_PROOF_ROOT);
  const resolved = path.resolve(root, value);
  const relative = path.relative(proofRoot, resolved);
  if (relative.length === 0 || relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error('Channel builder proof output must be a named run below the ignored proof root.');
  }
  return resolved;
}

export async function runProof(options) {
  const outputDirectory = resolveOutputDirectory(options.outputDirectory);
  const userDataDirectory = await mkdtemp(path.join(os.tmpdir(), 'lineup-channel-builder-proof-'));
  try {
    await mkdir(outputDirectory, { recursive: true });
    for (const phase of ['first-run', 'relaunch']) {
      await launchPhase({ outputDirectory, userDataDirectory, phase });
    }
    console.log('Channel builder Electron proof passed.');
  } finally {
    await rm(userDataDirectory, { recursive: true, force: true });
  }
}

async function launchPhase({ outputDirectory, userDataDirectory, phase }) {
  const mainEntry = path.join(repoRoot, 'dist', 'main', 'index.js');
  const child = spawn(electronPath, [mainEntry, `--user-data-dir=${userDataDirectory}`], {
    cwd: repoRoot,
    env: {
      ...process.env,
      LINEUP_DESKTOP_SMOKE: '1',
      LINEUP_CHANNEL_SETUP_PROOF: '1',
      LINEUP_CHANNEL_SETUP_PROOF_PHASE: phase,
      LINEUP_CHANNEL_SETUP_PROOF_OUTPUT: outputDirectory,
      NODE_ENV: 'production',
    },
    stdio: 'inherit',
  });
  const code = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      child.kill();
      reject(new Error(`Channel builder proof ${phase} phase timed out.`));
    }, 300_000);
    child.once('error', (error) => { clearTimeout(timeout); reject(error); });
    child.once('close', (exitCode, signal) => { clearTimeout(timeout); resolve(signal === null ? exitCode : 1); });
  });
  if (code !== 0) throw new Error(`Channel builder proof ${phase} phase failed.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    await runProof(parseArgs(process.argv.slice(2)));
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Channel builder proof failed.');
    process.exitCode = 1;
  }
}
