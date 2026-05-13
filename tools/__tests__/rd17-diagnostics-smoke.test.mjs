import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  REQUIRED_RD17_SMOKE_FILES,
  RD17_SMOKE_EVIDENCE_ROOT,
  RD17_SMOKE_EVIDENCE_ROOT_ABSOLUTE,
  formatSmokeFailure,
  isWindowsProofPlatform,
  parseSmokeArgs,
  resolveEvidenceDirectory,
} from '../rd17-diagnostics-smoke.mjs';

test('rd17 diagnostics smoke exposes the required evidence file manifest', () => {
  assert.deepEqual(REQUIRED_RD17_SMOKE_FILES, [
    'manifest.json',
    'summary.json',
    'redaction-report.json',
    'support-bundle/manifest.json',
    'support-bundle/diagnostics.ndjson',
    'support-bundle/crash-recovery.json',
    'support-bundle/player-snapshot.json',
    'support-bundle/environment.json',
    'support-bundle/redaction-report.json',
  ]);
});

test('rd17 diagnostics smoke keeps Windows proof platform explicit', () => {
  assert.equal(isWindowsProofPlatform('win32'), true);
  assert.equal(isWindowsProofPlatform('darwin'), false);
  assert.equal(isWindowsProofPlatform('linux'), false);
});

test('rd17 diagnostics smoke requires an explicit output directory argument', () => {
  assert.deepEqual(parseSmokeArgs(['--out', `${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`]), {
    outDirectory: `${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`,
  });
  assert.throws(
    () => parseSmokeArgs([]),
    /--out <evidence-directory>/u,
  );
  assert.throws(
    () => parseSmokeArgs(['--out']),
    /--out <evidence-directory>/u,
  );
});

test('rd17 diagnostics smoke constrains output to the ignored RD-17 evidence root', () => {
  const inside = resolveEvidenceDirectory(`${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`);

  assert.equal(path.relative(RD17_SMOKE_EVIDENCE_ROOT_ABSOLUTE, inside), 'windows-smoke');
  assert.throws(
    () => resolveEvidenceDirectory('docs/runs/rd-16-subtitle-audio-hdr-hardening/windows-smoke'),
    /RD-17 evidence root/u,
  );
  assert.throws(
    () => resolveEvidenceDirectory('../outside-rd17-proof'),
    /RD-17 evidence root/u,
  );
});

test('rd17 diagnostics smoke rejects symlink components inside the evidence root', (t) => {
  const repoRoot = makeTempRepo(t);
  const symlinkRoot = path.join(RD17_SMOKE_EVIDENCE_ROOT, 'symlink-escape-test');
  const targetRoot = path.join(RD17_SMOKE_EVIDENCE_ROOT, 'symlink-target-test');
  const symlinkRootAbsolute = path.join(repoRoot, symlinkRoot);
  const targetRootAbsolute = path.join(repoRoot, targetRoot);
  fs.mkdirSync(targetRootAbsolute, { recursive: true });
  fs.symlinkSync(targetRootAbsolute, symlinkRootAbsolute, 'dir');

  assert.throws(
    () => resolveEvidenceDirectory(`${symlinkRoot}/windows-smoke`, { repoRoot }),
    /RD-17 evidence root/u,
  );
});

test('rd17 diagnostics smoke rejects a symlink evidence root', (t) => {
  const repoRoot = makeTempRepo(t);
  const evidenceRoot = path.join(repoRoot, RD17_SMOKE_EVIDENCE_ROOT);
  const targetRoot = path.join(repoRoot, `${RD17_SMOKE_EVIDENCE_ROOT}-target-test`);
  fs.mkdirSync(path.dirname(evidenceRoot), { recursive: true });
  fs.mkdirSync(targetRoot, { recursive: true });
  fs.symlinkSync(targetRoot, evidenceRoot, 'dir');

  assert.throws(
    () => resolveEvidenceDirectory(`${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`, { repoRoot }),
    /RD-17 evidence root/u,
  );
});

test('rd17 diagnostics smoke rejects a symlink evidence ancestor', (t) => {
  const repoRoot = makeTempRepo(t);
  const runsRoot = path.dirname(RD17_SMOKE_EVIDENCE_ROOT);
  const docsRoot = path.join(repoRoot, path.dirname(runsRoot));
  const targetRoot = path.join(repoRoot, `${runsRoot}-target-test`);
  fs.mkdirSync(docsRoot, { recursive: true });
  fs.mkdirSync(targetRoot, { recursive: true });
  fs.symlinkSync(targetRoot, path.join(repoRoot, runsRoot), 'dir');

  assert.throws(
    () => resolveEvidenceDirectory(`${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`, { repoRoot }),
    /RD-17 evidence root/u,
  );
});

test('rd17 diagnostics smoke failure output stays path-free', () => {
  const rawPathError = new Error(
    [
      'ENOENT: no such file or directory, open ',
      ['', 'Users', 'example', 'Library', 'Application Support', 'Lineup', 'proof.json'].join('/'),
    ].join(''),
  );

  assert.equal(formatSmokeFailure(rawPathError), 'RD-17 diagnostics smoke failed.');
  assert.equal(
    formatSmokeFailure(new Error('RD-17 smoke output must be under the RD-17 evidence root.')),
    'RD-17 smoke output must be under the RD-17 evidence root.',
  );
});

function makeTempRepo(t) {
  const repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lineup-rd17-smoke-'));
  t.after(() => {
    fs.rmSync(repoRoot, { recursive: true, force: true });
  });
  return repoRoot;
}
