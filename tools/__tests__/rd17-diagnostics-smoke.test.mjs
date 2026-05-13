import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
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
  const symlinkRoot = path.join(RD17_SMOKE_EVIDENCE_ROOT, 'symlink-escape-test');
  const targetRoot = path.join(RD17_SMOKE_EVIDENCE_ROOT, 'symlink-target-test');
  fs.rmSync(symlinkRoot, { recursive: true, force: true });
  fs.rmSync(targetRoot, { recursive: true, force: true });
  fs.mkdirSync(targetRoot, { recursive: true });
  fs.symlinkSync(path.resolve(targetRoot), symlinkRoot, 'dir');
  t.after(() => {
    fs.rmSync(symlinkRoot, { recursive: true, force: true });
    fs.rmSync(targetRoot, { recursive: true, force: true });
  });

  assert.throws(
    () => resolveEvidenceDirectory(`${symlinkRoot}/windows-smoke`),
    /RD-17 evidence root/u,
  );
});

test('rd17 diagnostics smoke rejects a symlink evidence root', (t) => {
  const evidenceRoot = RD17_SMOKE_EVIDENCE_ROOT;
  const backupRoot = `${RD17_SMOKE_EVIDENCE_ROOT}-backup-test`;
  const targetRoot = `${RD17_SMOKE_EVIDENCE_ROOT}-target-test`;
  let evidenceMovedToBackup = false;

  t.after(() => {
    fs.rmSync(evidenceRoot, { recursive: true, force: true });
    fs.rmSync(targetRoot, { recursive: true, force: true });
    if (evidenceMovedToBackup && fs.existsSync(backupRoot)) {
      fs.renameSync(backupRoot, evidenceRoot);
    } else {
      fs.rmSync(backupRoot, { recursive: true, force: true });
    }
  });

  fs.rmSync(backupRoot, { recursive: true, force: true });
  fs.rmSync(targetRoot, { recursive: true, force: true });
  if (fs.existsSync(evidenceRoot)) {
    fs.renameSync(evidenceRoot, backupRoot);
    evidenceMovedToBackup = true;
  }
  fs.mkdirSync(targetRoot, { recursive: true });
  fs.symlinkSync(path.resolve(targetRoot), evidenceRoot, 'dir');

  assert.throws(
    () => resolveEvidenceDirectory(`${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`),
    /RD-17 evidence root/u,
  );
});

test('rd17 diagnostics smoke rejects a symlink evidence ancestor', (t) => {
  const runsRoot = path.dirname(RD17_SMOKE_EVIDENCE_ROOT);
  const docsRoot = path.dirname(runsRoot);
  const backupRoot = `${runsRoot}-backup-test`;
  const targetRoot = `${runsRoot}-target-test`;
  let runsMovedToBackup = false;

  t.after(() => {
    fs.rmSync(runsRoot, { recursive: true, force: true });
    fs.rmSync(targetRoot, { recursive: true, force: true });
    if (runsMovedToBackup && fs.existsSync(backupRoot)) {
      fs.renameSync(backupRoot, runsRoot);
    } else {
      fs.rmSync(backupRoot, { recursive: true, force: true });
    }
  });

  fs.mkdirSync(docsRoot, { recursive: true });
  fs.rmSync(backupRoot, { recursive: true, force: true });
  fs.rmSync(targetRoot, { recursive: true, force: true });
  if (fs.existsSync(runsRoot)) {
    fs.renameSync(runsRoot, backupRoot);
    runsMovedToBackup = true;
  }
  fs.mkdirSync(targetRoot, { recursive: true });
  fs.symlinkSync(path.resolve(targetRoot), runsRoot, 'dir');

  assert.throws(
    () => resolveEvidenceDirectory(`${RD17_SMOKE_EVIDENCE_ROOT}/windows-smoke`),
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
