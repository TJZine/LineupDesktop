import { randomBytes } from 'node:crypto';
import { lstat, rename, unlink, writeFile } from 'node:fs/promises';
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
  runGit,
  sourceSnapshot,
  validateEvidencePair,
  verifySourceSnapshot,
} from './verify.mjs';
import {
  collectFreshUpstreamCaptures,
  collectUpstreamPreflight,
  ensureCaptureDirectories,
  inspectFreshPng,
  parseCaptureWaitMs,
  verifyUpstreamPostflight,
} from './capture-upstream.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

async function collectDesktopPreflight(desktopCommit) {
  const rows = {};
  const uniqueSources = new Map();
  for (const rowId of ROW_IDS) {
    const desktopSources = [];
    for (const relativePath of ROWS[rowId].desktopSources) {
      const record = await collectSourceRecord(DESKTOP_ROOT, desktopCommit, relativePath);
      desktopSources.push(record);
      uniqueSources.set(record.path, record);
    }
    rows[rowId] = { desktopSources };
  }
  return {
    rows,
    snapshot: await sourceSnapshot(DESKTOP_ROOT, [...uniqueSources.values()]),
  };
}

async function collectFreshDesktopCaptures(startedAtMs, waitMs) {
  const capturesByRow = {};
  for (const rowId of ROW_IDS) {
    const desktopCaptures = [];
    for (const captureId of ROWS[rowId].desktopCaptures) {
      const relativePath = CAPTURE_RELATIVE_PATH.desktop(captureId);
      desktopCaptures.push({
        captureId,
        sha256: await inspectFreshPng(HERE, relativePath, ROWS[rowId].dimensions, startedAtMs, waitMs),
      });
    }
    capturesByRow[rowId] = desktopCaptures;
  }
  return capturesByRow;
}

async function verifyDesktopPostflight(preflight, desktopCommit) {
  if (runGit(DESKTOP_ROOT, ['rev-parse', 'HEAD']).trim() !== desktopCommit) throw new Error('Desktop HEAD changed after capture preflight.');
  await verifySourceSnapshot(DESKTOP_ROOT, preflight.snapshot);
  for (const rowId of ROW_IDS) {
    for (const source of preflight.rows[rowId].desktopSources) {
      const current = await collectSourceRecord(DESKTOP_ROOT, desktopCommit, source.path);
      if (current.gitBlob !== source.gitBlob || current.sha256 !== source.sha256) {
        throw new Error(`${source.path} changed after Desktop preflight.`);
      }
    }
  }
}

function notRunAclProof() {
  const empty = () => ({ persistenceParent: null, channelFile: null, smokeRoot: null, smokeSentinel: null });
  return {
    scope: 'not-run',
    status: 'pending',
    packageIdentity: null,
    observedAtUtc: null,
    currentUserControl: empty(),
    broadWriteAbsent: empty(),
    inheritsFromValidatedParent: empty(),
  };
}

export async function publishPair(upstreamManifest, visualManifest, evidenceRoot = HERE) {
  const destinations = [
    path.join(evidenceRoot, 'upstream-reference-manifest.json'),
    path.join(evidenceRoot, 'visual-comparison.json'),
  ];
  for (const destination of destinations) {
    if (await lstat(destination).catch(() => null)) throw new Error('A manifest already exists; refusing to overwrite an evidence session.');
  }
  const suffix = `${process.pid}-${randomBytes(16).toString('hex')}`;
  const temporary = [
    path.join(evidenceRoot, `.cb-manifest-upstream-${suffix}.tmp`),
    path.join(evidenceRoot, `.cb-manifest-visual-${suffix}.tmp`),
  ];
  let firstPublished = false;
  try {
    await writeFile(temporary[0], `${JSON.stringify(upstreamManifest, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
    await writeFile(temporary[1], `${JSON.stringify(visualManifest, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
    await rename(temporary[0], destinations[0]);
    firstPublished = true;
    await rename(temporary[1], destinations[1]);
  } catch {
    if (firstPublished) await unlink(destinations[0]).catch(() => undefined);
    throw new Error('Manifest pair publication failed.');
  } finally {
    await unlink(temporary[0]).catch(() => undefined);
    await unlink(temporary[1]).catch(() => undefined);
  }
}

async function main() {
  const startedAtMs = Date.now();
  const waitMs = parseCaptureWaitMs(process.argv.slice(2));
  await ensureCaptureDirectories();
  const desktopCommit = runGit(DESKTOP_ROOT, ['rev-parse', 'HEAD']).trim();
  const upstreamPreflight = await collectUpstreamPreflight();
  const desktopPreflight = await collectDesktopPreflight(desktopCommit);
  const upstreamStates = await collectFreshUpstreamCaptures(startedAtMs, waitMs);
  const desktopCaptures = await collectFreshDesktopCaptures(startedAtMs, waitMs);
  await verifyUpstreamPostflight(upstreamPreflight);
  await verifyDesktopPostflight(desktopPreflight, desktopCommit);

  const evidenceSessionId = `cb-evidence-${randomBytes(16).toString('hex')}`;
  const capturedAtUtc = new Date().toISOString();
  const upstreamManifest = {
    schemaVersion: 1,
    evidenceSessionId,
    capturedAtUtc,
    upstreamCommit: UPSTREAM_COMMIT,
    rows: Object.fromEntries(ROW_IDS.map((rowId) => [rowId, {
      sources: upstreamPreflight.rows[rowId].sources,
      states: upstreamStates[rowId],
    }])),
  };
  const visualManifest = {
    schemaVersion: 1,
    evidenceSessionId,
    capturedAtUtc,
    upstreamCommit: UPSTREAM_COMMIT,
    desktopCommit,
    windowsAclProof: notRunAclProof(),
    rows: Object.fromEntries(ROW_IDS.map((rowId) => [rowId, {
      desktopSources: desktopPreflight.rows[rowId].desktopSources,
      upstreamCaptureIds: ROWS[rowId].upstreamStates.map((state) => state.captureId),
      desktopScenarioId: ROWS[rowId].desktopScenarioId,
      desktopCaptures: desktopCaptures[rowId],
      status: 'blocked',
      blocker: { code: 'comparison-incomplete', message: 'Evidence row is blocked.' },
      decision: null,
      dimensions: { ...ROWS[rowId].dimensions },
    }])),
  };
  validateEvidencePair(upstreamManifest, visualManifest, desktopCommit);
  await publishPair(upstreamManifest, visualManifest);
  process.stdout.write(`Published paired comparison-incomplete manifests for ${evidenceSessionId}.\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`Desktop capture blocked: ${error.message ?? String(error)}\n`);
    process.exitCode = 1;
  });
}
