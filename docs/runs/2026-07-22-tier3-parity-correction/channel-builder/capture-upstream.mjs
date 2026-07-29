import { createHash } from 'node:crypto';
import { lstat, mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CAPTURE_RELATIVE_PATH,
  ROW_IDS,
  ROWS,
  UPSTREAM_COMMIT,
} from './states.mjs';
import {
  collectSourceRecord,
  DESKTOP_ROOT,
  sourceSnapshot,
  UPSTREAM_ROOT,
  validatePngBuffer,
  validateUpstreamRoot,
  verifySourceSnapshot,
} from './verify.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

function hash(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export async function ensureCaptureDirectories() {
  const expectedRelative = path.join('docs', 'runs', '2026-07-22-tier3-parity-correction', 'channel-builder');
  await validateExistingEvidenceAncestry(DESKTOP_ROOT, HERE, expectedRelative);
  const capturesRoot = path.join(HERE, 'captures');
  const upstreamRoot = path.join(capturesRoot, 'upstream');
  const desktopRoot = path.join(capturesRoot, 'desktop');
  for (const candidate of [capturesRoot, upstreamRoot, desktopRoot]) {
    const existing = await lstat(candidate).catch(() => null);
    if (existing === null) {
      await mkdir(candidate);
    } else if (!existing.isDirectory() || existing.isSymbolicLink()) {
      throw new Error('Approved evidence path contains a symlink or non-directory component.');
    }
  }
}

export async function validateExistingEvidenceAncestry(repositoryRoot, evidenceRoot, expectedRelative) {
  const relative = path.relative(repositoryRoot, evidenceRoot);
  if (
    path.resolve(repositoryRoot, expectedRelative) !== path.resolve(evidenceRoot)
    || relative !== expectedRelative
    || path.isAbsolute(relative)
    || relative.startsWith(`..${path.sep}`)
  ) {
    throw new Error('Evidence root is outside the exact approved repository location.');
  }
  let ancestor = repositoryRoot;
  for (const segment of ['', ...relative.split(path.sep)]) {
    if (segment !== '') ancestor = path.join(ancestor, segment);
    const info = await lstat(ancestor).catch(() => null);
    if (info === null || !info.isDirectory() || info.isSymbolicLink()) {
      throw new Error('Approved evidence ancestry contains a missing, symlink, or non-directory component.');
    }
  }
}

export async function collectUpstreamPreflight() {
  const upstreamRoot = await validateUpstreamRoot({ upstreamRoot: UPSTREAM_ROOT });
  const rows = {};
  const uniqueSources = new Map();
  for (const rowId of ROW_IDS) {
    const sources = [];
    for (const relativePath of ROWS[rowId].upstreamSources) {
      const record = await collectSourceRecord(upstreamRoot, UPSTREAM_COMMIT, relativePath);
      sources.push(record);
      uniqueSources.set(record.path, record);
    }
    rows[rowId] = { sources };
  }
  return {
    rows,
    snapshot: await sourceSnapshot(upstreamRoot, [...uniqueSources.values()]),
  };
}

export async function collectFreshUpstreamCaptures(startedAtMs, waitMs = 0) {
  const statesByRow = {};
  for (const rowId of ROW_IDS) {
    const states = [];
    for (const expected of ROWS[rowId].upstreamStates) {
      const relativePath = CAPTURE_RELATIVE_PATH.upstream(expected.captureId);
      states.push({
        stateId: expected.stateId,
        captureId: expected.captureId,
        sha256: await inspectFreshPng(HERE, relativePath, ROWS[rowId].dimensions, startedAtMs, waitMs),
      });
    }
    statesByRow[rowId] = states;
  }
  return statesByRow;
}

export async function verifyUpstreamPostflight(preflight) {
  const upstreamRoot = await validateUpstreamRoot({ upstreamRoot: UPSTREAM_ROOT });
  await verifySourceSnapshot(upstreamRoot, preflight.snapshot);
  for (const rowId of ROW_IDS) {
    for (const source of preflight.rows[rowId].sources) {
      const current = await collectSourceRecord(upstreamRoot, UPSTREAM_COMMIT, source.path);
      if (current.gitBlob !== source.gitBlob || current.sha256 !== source.sha256) {
        throw new Error(`${source.path} changed after upstream preflight.`);
      }
    }
  }
}

export async function inspectFreshPng(evidenceRoot, relativePath, dimensions, startedAtMs, waitMs) {
  const absolute = path.join(evidenceRoot, relativePath);
  const deadline = startedAtMs + waitMs;
  let info = await lstat(absolute).catch(() => null);
  while ((info === null || info.mtimeMs < startedAtMs) && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    info = await lstat(absolute).catch(() => null);
  }
  if (info === null || !info.isFile() || info.isSymbolicLink()) throw new Error(`${relativePath} is unavailable or unsafe; no manifest was written.`);
  if (info.mtimeMs < startedAtMs) throw new Error(`${relativePath} predates this evidence session.`);
  const bytes = await readFile(absolute);
  validatePngBuffer(bytes, dimensions);
  return hash(bytes);
}

async function main() {
  const startedAtMs = Date.now();
  const waitMs = parseCaptureWaitMs(process.argv.slice(2));
  await ensureCaptureDirectories();
  const preflight = await collectUpstreamPreflight();
  await collectFreshUpstreamCaptures(startedAtMs, waitMs);
  await verifyUpstreamPostflight(preflight);
  process.stdout.write('Fresh upstream captures passed this diagnostic session; use capture.mjs with an explicit bounded wait for a publishable paired session.\n');
}

export function parseCaptureWaitMs(argumentsList) {
  const option = argumentsList.find((argument) => argument.startsWith('--wait-ms='));
  if (option === undefined) throw new Error('--wait-ms is required to open a bounded capture session.');
  const value = Number(option.slice('--wait-ms='.length));
  if (!Number.isInteger(value) || value < 1 || value > 3_600_000) throw new Error('--wait-ms must be an integer from 1 through 3600000.');
  return value;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`Upstream capture blocked: ${error.message ?? String(error)}\n`);
    process.exitCode = 1;
  });
}
