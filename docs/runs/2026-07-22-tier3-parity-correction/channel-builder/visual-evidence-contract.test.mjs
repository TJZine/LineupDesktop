import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir, rm, symlink, unlink, utimes, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { deflateSync } from 'node:zlib';
import {
  DESKTOP_ROOT,
  EvidenceContractError,
  UPSTREAM_ROOT,
  collectSourceRecord,
  resolveUpstreamRoot,
  runGit,
  sourceSnapshot,
  validateEvidencePair,
  validateUpstreamManifest,
  validateVisualManifest,
  verifyCaptureFile,
  verifyEvidenceFiles,
  verifySourceRecord,
  verifySourceSnapshot,
  validateUpstreamRoot,
} from './verify.mjs';
import { CAPTURE_RELATIVE_PATH, ROW_IDS, ROWS, UPSTREAM_COMMIT } from './states.mjs';
import {
  inspectFreshPng,
  parseCaptureWaitMs,
  validateExistingEvidenceAncestry,
} from './capture-upstream.mjs';
import { publishPair } from './capture.mjs';

const SESSION = 'cb-evidence-0123456789abcdef0123456789abcdef';
const CAPTURED_AT = '2026-07-25T12:34:56.789Z';
const DESKTOP_COMMIT = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const SHA = 'a'.repeat(64);
const BLOB = 'c'.repeat(40);

const clone = (value) => JSON.parse(JSON.stringify(value));
const source = (sourcePath) => ({ path: sourcePath, gitBlob: BLOB, sha256: SHA });
const capture = (captureId) => ({ captureId, sha256: SHA });

async function createSymlinkOrSkip(t, target, linkPath, type) {
  try {
    await symlink(target, linkPath, type);
    return true;
  } catch (error) {
    if (error?.code === 'EPERM' || error?.code === 'EACCES' || error?.code === 'ENOTSUP') {
      t.skip('Symlink creation is unavailable on this platform.');
      return false;
    }
    throw error;
  }
}

test('upstream root resolution uses the task-specific environment override or Desktop sibling', () => {
  const desktopRoot = path.resolve(path.join('workspace', 'LineupDesktop'));
  assert.equal(
    resolveUpstreamRoot({ environment: {}, desktopRoot }),
    path.join(path.dirname(desktopRoot), 'Lineup'),
  );
  const override = path.resolve(path.join('workspace', 'upstream-checkout'));
  assert.equal(
    resolveUpstreamRoot({
      environment: { LINEUP_WS1_UPSTREAM_ROOT: override },
      desktopRoot,
    }),
    override,
  );
  assert.throws(
    () => resolveUpstreamRoot({ environment: { LINEUP_WS1_UPSTREAM_ROOT: '' }, desktopRoot }),
    /configuration is invalid/u,
  );
  assert.throws(
    () => resolveUpstreamRoot({ environment: { LINEUP_WS1_UPSTREAM_ROOT: 'relative-upstream' }, desktopRoot }),
    /configuration is invalid/u,
  );
});

test('upstream root validation is fail-closed and redaction-safe', async (t) => {
  const temporaryRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-upstream-root-'));
  const missingRoot = path.join(temporaryRoot, 'missing');
  const fileRoot = path.join(temporaryRoot, 'file');
  const nonGitRoot = path.join(temporaryRoot, 'non-git');
  const wrongCommitRoot = path.join(temporaryRoot, 'wrong-commit');
  await writeFile(fileRoot, 'not a directory');
  await mkdir(nonGitRoot);
  await mkdir(wrongCommitRoot);
  execFileSync('git', ['init', '-q'], { cwd: wrongCommitRoot });
  execFileSync('git', ['config', 'user.email', 'test@example.invalid'], { cwd: wrongCommitRoot });
  execFileSync('git', ['config', 'user.name', 'Evidence Test'], { cwd: wrongCommitRoot });
  await writeFile(path.join(wrongCommitRoot, 'fixture.txt'), 'fixture\n');
  execFileSync('git', ['add', 'fixture.txt'], { cwd: wrongCommitRoot });
  execFileSync('git', ['commit', '-q', '-m', 'fixture'], { cwd: wrongCommitRoot });
  try {
    await assert.rejects(validateUpstreamRoot({ upstreamRoot: missingRoot }), /checkout is unavailable/u);
    await assert.rejects(validateUpstreamRoot({ upstreamRoot: fileRoot }), /checkout is unavailable/u);
    await assert.rejects(validateUpstreamRoot({ upstreamRoot: nonGitRoot }), /Git validation failed/u);
    await assert.rejects(validateUpstreamRoot({ upstreamRoot: wrongCommitRoot }), /HEAD differs/u);
    await assert.rejects(
      validateUpstreamRoot({ upstreamRoot: path.join(UPSTREAM_ROOT, 'src') }),
      /top-level is invalid/u,
    );
    await assert.doesNotReject(validateUpstreamRoot({ upstreamRoot: UPSTREAM_ROOT }));

    await t.test('symlink root is rejected when the platform permits symlink creation', async (symlinkTest) => {
      const linkRoot = path.join(temporaryRoot, 'link');
      if (!await createSymlinkOrSkip(symlinkTest, UPSTREAM_ROOT, linkRoot, 'dir')) return;
      await assert.rejects(validateUpstreamRoot({ upstreamRoot: linkRoot }), /checkout is unavailable/u);
    });

    assert.throws(
      () => runGit(missingRoot, ['rev-parse', 'HEAD']),
      (error) => error.message === 'Git command failed.' && !error.message.includes(temporaryRoot),
    );
  } finally {
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

function pngCrc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) === 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, 'ascii');
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  typeBytes.copy(chunk, 4);
  data.copy(chunk, 8);
  chunk.writeUInt32BE(pngCrc32(Buffer.concat([typeBytes, data])), 8 + data.length);
  return chunk;
}

function pngBytes(width, height, options = {}) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const scanlines = Buffer.alloc((width * 4 + 1) * height);
  const idat = options.idat ?? deflateSync(scanlines);
  return Buffer.concat([
    Buffer.from('89504e470d0a1a0a', 'hex'),
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', idat),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

function validUpstream() {
  return {
    schemaVersion: 1,
    evidenceSessionId: SESSION,
    capturedAtUtc: CAPTURED_AT,
    upstreamCommit: UPSTREAM_COMMIT,
    rows: Object.fromEntries(ROW_IDS.map((rowId) => {
      const expected = ROWS[rowId];
      return [rowId, {
        sources: expected.upstreamSources.map(source),
        states: expected.upstreamStates.map((state) => ({
          stateId: state.stateId,
          captureId: state.captureId,
          sha256: SHA,
        })),
      }];
    })),
  };
}

function nullAclResult() {
  return { persistenceParent: null, channelFile: null, smokeRoot: null, smokeSentinel: null };
}

function booleanAclResult(value) {
  return { persistenceParent: value, channelFile: value, smokeRoot: value, smokeSentinel: value };
}

function validVisual() {
  return {
    schemaVersion: 1,
    evidenceSessionId: SESSION,
    capturedAtUtc: CAPTURED_AT,
    upstreamCommit: UPSTREAM_COMMIT,
    desktopCommit: DESKTOP_COMMIT,
    windowsAclProof: {
      scope: 'not-run',
      status: 'pending',
      packageIdentity: null,
      observedAtUtc: null,
      currentUserControl: nullAclResult(),
      broadWriteAbsent: nullAclResult(),
      inheritsFromValidatedParent: nullAclResult(),
    },
    rows: Object.fromEntries(ROW_IDS.map((rowId) => {
      const expected = ROWS[rowId];
      return [rowId, {
        desktopSources: expected.desktopSources.map(source),
        upstreamCaptureIds: expected.upstreamStates.map((state) => state.captureId),
        desktopScenarioId: expected.desktopScenarioId,
        desktopCaptures: expected.desktopCaptures.map(capture),
        status: 'blocked',
        blocker: { code: 'render-unavailable', message: 'Evidence row is blocked.' },
        decision: null,
        dimensions: { ...expected.dimensions },
      }];
    })),
  };
}

function rejects(action, expression) {
  assert.throws(action, (error) => error instanceof EvidenceContractError && expression.test(error.message));
}

test('accepts the exact individual and paired blocked schemas', () => {
  const upstream = validUpstream();
  const visual = validVisual();
  assert.equal(validateUpstreamManifest(upstream), upstream);
  assert.equal(validateVisualManifest(visual), visual);
  assert.deepEqual(validateEvidencePair(upstream, visual, DESKTOP_COMMIT), {
    upstreamManifest: upstream,
    visualManifest: visual,
  });
});

test('rejects unknown, missing, or reordered keys at every named schema level', async (t) => {
  const cases = [
    ['upstream top-level unknown', () => { const value = validUpstream(); value.extra = true; return () => validateUpstreamManifest(value); }],
    ['upstream row unknown', () => { const value = validUpstream(); value.rows['UI-17'].extra = true; return () => validateUpstreamManifest(value); }],
    ['upstream source unknown', () => { const value = validUpstream(); value.rows['UI-17'].sources[0].extra = true; return () => validateUpstreamManifest(value); }],
    ['upstream state unknown', () => { const value = validUpstream(); value.rows['UI-17'].states[0].extra = true; return () => validateUpstreamManifest(value); }],
    ['visual top-level unknown', () => { const value = validVisual(); value.extra = true; return () => validateVisualManifest(value); }],
    ['visual row unknown', () => { const value = validVisual(); value.rows['UI-17'].extra = true; return () => validateVisualManifest(value); }],
    ['desktop source unknown', () => { const value = validVisual(); value.rows['UI-17'].desktopSources[0].extra = true; return () => validateVisualManifest(value); }],
    ['desktop capture unknown', () => { const value = validVisual(); value.rows['UI-17'].desktopCaptures[0].extra = true; return () => validateVisualManifest(value); }],
    ['blocker unknown', () => { const value = validVisual(); value.rows['UI-17'].blocker.extra = true; return () => validateVisualManifest(value); }],
    ['dimensions unknown', () => { const value = validVisual(); value.rows['UI-17'].dimensions.extra = true; return () => validateVisualManifest(value); }],
    ['ACL proof unknown', () => { const value = validVisual(); value.windowsAclProof.extra = true; return () => validateVisualManifest(value); }],
    ['ACL result unknown', () => { const value = validVisual(); value.windowsAclProof.currentUserControl.extra = null; return () => validateVisualManifest(value); }],
    ['reordered top-level keys', () => {
      const value = validUpstream();
      const reordered = { evidenceSessionId: value.evidenceSessionId, schemaVersion: 1, capturedAtUtc: value.capturedAtUtc, upstreamCommit: value.upstreamCommit, rows: value.rows };
      return () => validateUpstreamManifest(reordered);
    }],
    ['missing row key', () => { const value = validVisual(); delete value.rows['UI-24']; return () => validateVisualManifest(value); }],
    ['reordered row keys', () => {
      const value = validVisual();
      value.rows = Object.fromEntries([...Object.entries(value.rows)].reverse());
      return () => validateVisualManifest(value);
    }],
  ];
  for (const [name, build] of cases) await t.test(name, () => rejects(build(), /keys|rows/u));
});

test('rejects every invalid identifier, timestamp, commit, hash, and path class', async (t) => {
  const cases = [
    ['session prefix', (upstream) => { upstream.evidenceSessionId = `wrong-${'0'.repeat(32)}`; }],
    ['session length', (upstream) => { upstream.evidenceSessionId = `cb-evidence-${'0'.repeat(31)}`; }],
    ['timestamp lacks milliseconds', (upstream) => { upstream.capturedAtUtc = '2026-07-25T12:34:56Z'; }],
    ['timestamp is impossible', (upstream) => { upstream.capturedAtUtc = '2026-02-30T12:34:56.789Z'; }],
    ['commit uppercase', (upstream) => { upstream.upstreamCommit = UPSTREAM_COMMIT.toUpperCase(); }],
    ['blob short', (upstream) => { upstream.rows['UI-17'].sources[0].gitBlob = 'a'.repeat(39); }],
    ['SHA uppercase', (upstream) => { upstream.rows['UI-17'].states[0].sha256 = 'A'.repeat(64); }],
    ['state unsafe', (upstream) => { upstream.rows['UI-17'].states[0].stateId = '../state'; }],
    ['absolute path', (upstream) => { upstream.rows['UI-17'].sources[0].path = ['', 'tmp', 'source'].join('/'); }],
    ['backslash path', (upstream) => { upstream.rows['UI-17'].sources[0].path = 'src\\source'; }],
    ['parent segment', (upstream) => { upstream.rows['UI-17'].sources[0].path = 'src/../source'; }],
    ['empty segment', (upstream) => { upstream.rows['UI-17'].sources[0].path = 'src//source'; }],
  ];
  for (const [name, mutate] of cases) {
    await t.test(name, () => {
      const value = validUpstream();
      mutate(value);
      rejects(() => validateUpstreamManifest(value), /invalid|path|unsafe|timestamp|audited/u);
    });
  }
});

test('rejects omitted, extra, reordered, and duplicate frozen arrays and closures', async (t) => {
  const cases = [
    ['omitted upstream source', () => { const value = validUpstream(); value.rows['UI-17'].sources.pop(); return () => validateUpstreamManifest(value); }],
    ['extra upstream source', () => { const value = validUpstream(); value.rows['UI-17'].sources.push(clone(value.rows['UI-17'].sources[0])); return () => validateUpstreamManifest(value); }],
    ['reordered upstream states', () => { const value = validUpstream(); value.rows['UI-17'].states.reverse(); return () => validateUpstreamManifest(value); }],
    ['omitted reviewed Desktop closure member', () => { const value = validVisual(); value.rows['UI-18'].desktopSources.pop(); return () => validateVisualManifest(value); }],
    ['reordered reviewed Desktop closure', () => { const value = validVisual(); value.rows['UI-19'].desktopSources.reverse(); return () => validateVisualManifest(value); }],
    ['missing upstream reference', () => { const value = validVisual(); value.rows['UI-21'].upstreamCaptureIds.pop(); return () => validateVisualManifest(value); }],
    ['extra upstream reference', () => { const value = validVisual(); value.rows['UI-21'].upstreamCaptureIds.push('extra'); return () => validateVisualManifest(value); }],
    ['duplicate upstream reference', () => { const value = validVisual(); value.rows['UI-21'].upstreamCaptureIds[1] = value.rows['UI-21'].upstreamCaptureIds[0]; return () => validateVisualManifest(value); }],
    ['reordered Desktop captures', () => { const value = validVisual(); value.rows['UI-22'].desktopCaptures.reverse(); return () => validateVisualManifest(value); }],
  ];
  for (const [name, build] of cases) await t.test(name, () => rejects(build(), /frozen|approved|closure|source|capture|state|order/u));
});

test('enforces status, blocker, and decision cross-products', async (t) => {
  const cases = [
    ['match', null, null, true],
    ['adaptation', null, { kind: 'electron-adaptation', rationaleCode: 'input-model' }, true],
    ['divergence', null, { kind: 'approved-divergence', rationaleCode: 'desktop-product-decision' }, true],
    ['blocked', { code: 'comparison-incomplete', message: 'Evidence row is blocked.' }, null, true],
    ['match', { code: 'render-unavailable', message: 'Evidence row is blocked.' }, null, false],
    ['blocked', null, null, false],
    ['blocked', { code: 'other', message: 'Evidence row is blocked.' }, null, false],
    ['blocked', { code: 'render-unavailable', message: 'details leaked' }, null, false],
    ['adaptation', null, { kind: 'electron-adaptation', rationaleCode: 'other' }, false],
    ['divergence', null, { kind: 'approved-divergence', rationaleCode: 'other' }, false],
  ];
  for (const [status, blocker, decision, accepted] of cases) {
    await t.test(`${status}-${accepted ? 'accepted' : 'rejected'}-${JSON.stringify(decision)}`, () => {
      const value = validVisual();
      Object.assign(value.rows['UI-17'], { status, blocker, decision });
      if (accepted) assert.doesNotThrow(() => validateVisualManifest(value));
      else rejects(() => validateVisualManifest(value), /blocker|decision|approved/u);
    });
  }
});

test('enforces exact scenario dimensions and positive finite values', () => {
  const wrong = validVisual();
  wrong.rows['UI-22'].dimensions.cssViewportWidth = 901;
  rejects(() => validateVisualManifest(wrong), /differs from the scenario/u);
  const nonFinite = validVisual();
  nonFinite.rows['UI-23'].dimensions.devicePixelRatio = Infinity;
  rejects(() => validateVisualManifest(nonFinite), /finite and positive/u);
  const wrongScenario = validVisual();
  wrongScenario.rows['UI-17'].desktopScenarioId = 'CB-UI-02-BASELINE-REVIEW';
  rejects(() => validateVisualManifest(wrongScenario), /frozen scenario/u);
});

test('enforces the complete ACL scope/status/null/12-boolean truth table', async (t) => {
  await t.test('not-run exact shape', () => assert.doesNotThrow(() => validateVisualManifest(validVisual())));
  await t.test('not-run rejects any boolean', () => {
    const value = validVisual(); value.windowsAclProof.currentUserControl.channelFile = true;
    rejects(() => validateVisualManifest(value), /not-run/u);
  });
  await t.test('unpackaged pending and blocked are valid but passed is forbidden', () => {
    for (const status of ['pending', 'blocked']) {
      const value = validVisual();
      value.windowsAclProof = {
        scope: 'unpackaged-preliminary', status, packageIdentity: 'unpacked-1',
        observedAtUtc: CAPTURED_AT,
        currentUserControl: booleanAclResult(true),
        broadWriteAbsent: booleanAclResult(true),
        inheritsFromValidatedParent: booleanAclResult(true),
      };
      assert.doesNotThrow(() => validateVisualManifest(value));
    }
    const value = validVisual();
    value.windowsAclProof = {
      scope: 'unpackaged-preliminary', status: 'passed', packageIdentity: 'unpacked-1',
      observedAtUtc: CAPTURED_AT,
      currentUserControl: booleanAclResult(true),
      broadWriteAbsent: booleanAclResult(true),
      inheritsFromValidatedParent: booleanAclResult(true),
    };
    rejects(() => validateVisualManifest(value), /cannot pass/u);
  });
  await t.test('packaged passes iff all 12 are true', () => {
    const passing = validVisual();
    passing.windowsAclProof = {
      scope: 'packaged', status: 'passed', packageIdentity: 'package-1',
      observedAtUtc: CAPTURED_AT,
      currentUserControl: booleanAclResult(true),
      broadWriteAbsent: booleanAclResult(true),
      inheritsFromValidatedParent: booleanAclResult(true),
    };
    assert.doesNotThrow(() => validateVisualManifest(passing));
    passing.windowsAclProof.currentUserControl.channelFile = false;
    rejects(() => validateVisualManifest(passing), /if and only if/u);
    passing.windowsAclProof.status = 'blocked';
    assert.doesNotThrow(() => validateVisualManifest(passing));
  });
  await t.test('non-not-run scopes reject any null result', () => {
    const value = validVisual();
    value.windowsAclProof = {
      scope: 'packaged', status: 'blocked', packageIdentity: 'package-1',
      observedAtUtc: CAPTURED_AT,
      currentUserControl: booleanAclResult(true),
      broadWriteAbsent: booleanAclResult(true),
      inheritsFromValidatedParent: booleanAclResult(true),
    };
    value.windowsAclProof.broadWriteAbsent.smokeRoot = null;
    rejects(() => validateVisualManifest(value), /12 boolean/u);
  });
});

test('rejects unsafe raw ACL, identity, URL, token, and authorization material', async (t) => {
  for (const unsafe of ['https://private.invalid', 'X-Plex-Token', 'Authorization: secret', 'S-1-5-21-123', 'Get-Acl', 'icacls']) {
    await t.test(unsafe, () => {
      const value = validVisual();
      value.windowsAclProof = {
        scope: 'unpackaged-preliminary',
        status: 'pending',
        packageIdentity: unsafe,
        observedAtUtc: CAPTURED_AT,
        currentUserControl: booleanAclResult(true),
        broadWriteAbsent: booleanAclResult(true),
        inheritsFromValidatedParent: booleanAclResult(true),
      };
      rejects(() => validateVisualManifest(value), /invalid|forbidden/u);
    });
  }
});

test('rejects all whole-session and cross-row substitutions before conclusions', async (t) => {
  const cases = [
    ['different session', (upstream, visual) => { visual.evidenceSessionId = `cb-evidence-${'f'.repeat(32)}`; }],
    ['different upstream commit', (_upstream, visual) => { visual.upstreamCommit = 'd'.repeat(40); }],
    ['cross-row capture substitution', (_upstream, visual) => { visual.rows['UI-17'].upstreamCaptureIds = [...visual.rows['UI-18'].upstreamCaptureIds]; }],
    ['paired capture reorder', (_upstream, visual) => { visual.rows['UI-17'].upstreamCaptureIds.reverse(); }],
    ['Desktop HEAD mismatch', () => {}],
  ];
  for (const [name, mutate] of cases) {
    await t.test(name, () => {
      const upstream = validUpstream();
      const visual = validVisual();
      mutate(upstream, visual);
      const expectedHead = name === 'Desktop HEAD mismatch' ? 'e'.repeat(40) : DESKTOP_COMMIT;
      rejects(() => validateEvidencePair(upstream, visual, expectedHead), /session|upstream|capture|frozen|audited|HEAD/u);
    });
  }
});

test('real Git source proof rejects unstaged, staged, untracked/replaced, hash, and mutation failures', async (t) => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'cb-evidence-git-'));
  const relativePath = 'src/source.ts';
  try {
    await mkdir(path.join(root, 'src'));
    execFileSync('git', ['init', '-q'], { cwd: root });
    execFileSync('git', ['config', 'core.autocrlf', 'false'], { cwd: root });
    execFileSync('git', ['config', 'user.email', 'evidence@example.invalid'], { cwd: root });
    execFileSync('git', ['config', 'user.name', 'Evidence Test'], { cwd: root });
    await writeFile(path.join(root, relativePath), 'export const value = 1;\n');
    execFileSync('git', ['add', relativePath], { cwd: root });
    execFileSync('git', ['commit', '-qm', 'fixture'], { cwd: root });
    const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
    const record = await collectSourceRecord(root, commit, relativePath);
    assert.equal((await verifySourceRecord(root, commit, record)).path, relativePath);
    const snapshot = await sourceSnapshot(root, [record]);

    await t.test('wrong blob record reaches recorded identity comparison', async () => {
      await assert.rejects(verifySourceRecord(root, commit, { ...record, gitBlob: 'a'.repeat(40) }), /recorded blob and SHA/u);
    });
    await t.test('wrong SHA record reaches recorded identity comparison', async () => {
      await assert.rejects(verifySourceRecord(root, commit, { ...record, sha256: SHA }), /recorded blob and SHA/u);
    });
    await t.test('unstaged dirt', async () => {
      try {
        await writeFile(path.join(root, relativePath), 'export const value = 2;\n');
        await assert.rejects(collectSourceRecord(root, commit, relativePath), /bytes differ|changes/u);
      } finally {
        execFileSync('git', ['restore', '--worktree', '--source=HEAD', '--', relativePath], { cwd: root });
      }
    });
    await t.test('staged dirt', async () => {
      try {
        await writeFile(path.join(root, relativePath), 'export const value = 3;\n');
        execFileSync('git', ['add', relativePath], { cwd: root });
        execFileSync('git', ['restore', '--worktree', '--source=HEAD', '--', relativePath], { cwd: root });
        await assert.rejects(collectSourceRecord(root, commit, relativePath), /staged or unstaged changes/u);
      } finally {
        execFileSync('git', ['restore', '--staged', '--worktree', '--source=HEAD', '--', relativePath], { cwd: root });
      }
    });
    await t.test('scoped untracked replacement reaches substitute rejection', async () => {
      try {
        execFileSync('git', ['rm', '--cached', '-q', relativePath], { cwd: root });
        await assert.rejects(collectSourceRecord(root, commit, relativePath), /untracked substitute/u);
      } finally {
        execFileSync('git', ['reset', '-q', 'HEAD', '--', relativePath], { cwd: root });
      }
    });
    await t.test('replaced or missing source', async () => {
      try {
        await unlink(path.join(root, relativePath));
        await assert.rejects(collectSourceRecord(root, commit, relativePath), /ENOENT/u);
      } finally {
        execFileSync('git', ['restore', '--worktree', '--source=HEAD', '--', relativePath], { cwd: root });
      }
    });
    await t.test('between-preflight-and-capture mutation', async () => {
      try {
        await writeFile(path.join(root, relativePath), 'export const value = 4;\n');
        await assert.rejects(verifySourceSnapshot(root, snapshot), /changed after preflight/u);
      } finally {
        execFileSync('git', ['restore', '--worktree', '--source=HEAD', '--', relativePath], { cwd: root });
      }
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('capture proof rejects missing, symlinked, malformed, wrong-dimension, and hash-mismatched PNGs', async (t) => {
  const evidenceRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-evidence-missing-'));
  const relativeCapture = 'captures/upstream/capture.png';
  const absoluteCapture = path.join(evidenceRoot, relativeCapture);
  const dimensions = ROWS['UI-23'].dimensions;
  try {
    await assert.rejects(verifyCaptureFile(evidenceRoot, 'captures/upstream/missing.png', SHA, dimensions), /missing or unsafe/u);
    await mkdir(path.join(evidenceRoot, 'captures', 'upstream'), { recursive: true });
    await t.test('plain non-PNG', async () => {
      await writeFile(absoluteCapture, 'not a PNG');
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, SHA, dimensions), /structurally complete PNG/u);
    });
    await t.test('signature-only 24-byte buffer', async () => {
      const signatureOnly = Buffer.alloc(24);
      Buffer.from('89504e470d0a1a0a', 'hex').copy(signatureOnly);
      await writeFile(absoluteCapture, signatureOnly);
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, SHA, dimensions), /structurally complete PNG/u);
    });
    await t.test('CRC-valid but undecodable IDAT', async () => {
      await writeFile(absoluteCapture, pngBytes(1280, 720, { idat: Buffer.from('undecodable') }));
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, SHA, dimensions), /IDAT stream is not decodable/u);
    });
    await t.test('corrupt chunk CRC', async () => {
      const corrupt = pngBytes(1280, 720);
      corrupt[29] ^= 0xff;
      await writeFile(absoluteCapture, corrupt);
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, SHA, dimensions), /CRC mismatch/u);
    });
    await t.test('wrong bitmap dimensions', async () => {
      const wrongDimensions = pngBytes(1, 1);
      await writeFile(absoluteCapture, wrongDimensions);
      const wrongHash = createHash('sha256').update(wrongDimensions).digest('hex');
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, wrongHash, dimensions), /bitmap dimensions/u);
    });
    const png = pngBytes(1280, 720);
    const actualHash = createHash('sha256').update(png).digest('hex');
    await t.test('symlink capture', async (symlinkTest) => {
      const target = path.join(evidenceRoot, 'target.png');
      await writeFile(target, png);
      await unlink(absoluteCapture);
      if (!await createSymlinkOrSkip(symlinkTest, target, absoluteCapture, 'file')) return;
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, actualHash, dimensions), /missing or unsafe/u);
      await unlink(absoluteCapture);
    });
    await t.test('paired SHA mismatch after successful decode and dimensions', async () => {
      await writeFile(absoluteCapture, png);
      await assert.rejects(verifyCaptureFile(evidenceRoot, relativeCapture, SHA, dimensions), /SHA-256 mismatch/u);
      await assert.doesNotReject(verifyCaptureFile(evidenceRoot, relativeCapture, actualHash, dimensions));
    });
  } finally {
    await rm(evidenceRoot, { recursive: true, force: true });
  }
});

test('evidence ancestry rejects a symlink component between repository root and HERE', async (t) => {
  const repositoryRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-evidence-root-'));
  const externalRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-evidence-external-'));
  const expectedRelative = path.join('docs', 'runs', 'date', 'channel-builder');
  try {
    await mkdir(path.join(repositoryRoot, 'docs', 'runs'), { recursive: true });
    await mkdir(path.join(externalRoot, 'channel-builder'));
    if (!await createSymlinkOrSkip(t, externalRoot, path.join(repositoryRoot, 'docs', 'runs', 'date'), 'dir')) return;
    await assert.rejects(
      validateExistingEvidenceAncestry(
        repositoryRoot,
        path.join(repositoryRoot, expectedRelative),
        expectedRelative,
      ),
      /symlink|non-directory/u,
    );
  } finally {
    await rm(repositoryRoot, { recursive: true, force: true });
    await rm(externalRoot, { recursive: true, force: true });
  }
});

test('bounded capture session accepts only PNGs generated after collector start', async () => {
  assert.equal(parseCaptureWaitMs(['--wait-ms=1000']), 1000);
  assert.throws(() => parseCaptureWaitMs([]), /required/u);
  assert.throws(() => parseCaptureWaitMs(['--wait-ms=0']), /1 through 3600000/u);
  assert.throws(() => parseCaptureWaitMs(['--wait-ms=3600001']), /1 through 3600000/u);

  const evidenceRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-capture-session-'));
  const relativePath = 'captures/upstream/session.png';
  const absolutePath = path.join(evidenceRoot, relativePath);
  const dimensions = ROWS['UI-23'].dimensions;
  const png = pngBytes(1280, 720);
  try {
    await mkdir(path.dirname(absolutePath), { recursive: true });
    const startedAtMs = Date.now();
    const generated = new Promise((resolve, reject) => {
      setTimeout(() => writeFile(absolutePath, png).then(resolve, reject), 25);
    });
    await assert.doesNotReject(inspectFreshPng(evidenceRoot, relativePath, dimensions, startedAtMs, 1000));
    await generated;

    const priorSessionTime = new Date(startedAtMs - 10_000);
    await utimes(absolutePath, priorSessionTime, priorSessionTime);
    await assert.rejects(
      inspectFreshPng(evidenceRoot, relativePath, dimensions, Date.now(), 1),
      /predates this evidence session/u,
    );

    const laterRelativePath = 'captures/upstream/later-session.png';
    const laterAbsolutePath = path.join(evidenceRoot, laterRelativePath);
    const expiredSessionStart = Date.now() - 100;
    const generatedAfterExpiry = new Promise((resolve, reject) => {
      setTimeout(() => writeFile(laterAbsolutePath, png).then(resolve, reject), 25);
    });
    await assert.rejects(
      inspectFreshPng(evidenceRoot, laterRelativePath, dimensions, expiredSessionStart, 50),
      /unavailable or unsafe/u,
    );
    await generatedAfterExpiry;
  } finally {
    await rm(evidenceRoot, { recursive: true, force: true });
  }
});

test('manifest pair publishes atomically through same-directory transient files and cleans them', async () => {
  const evidenceRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-manifest-publication-'));
  try {
    const upstream = validUpstream();
    const visual = validVisual();
    await publishPair(upstream, visual, evidenceRoot);
    assert.deepEqual(
      JSON.parse(await readFile(path.join(evidenceRoot, 'upstream-reference-manifest.json'), 'utf8')),
      upstream,
    );
    assert.deepEqual(
      JSON.parse(await readFile(path.join(evidenceRoot, 'visual-comparison.json'), 'utf8')),
      visual,
    );
    assert.deepEqual(
      (await readdir(evidenceRoot)).filter((name) => name.startsWith('.cb-manifest-')),
      [],
    );
    await assert.rejects(publishPair(upstream, visual, evidenceRoot), /already exists/u);
    assert.deepEqual(
      (await readdir(evidenceRoot)).filter((name) => name.startsWith('.cb-manifest-')),
      [],
    );
  } finally {
    await rm(evidenceRoot, { recursive: true, force: true });
  }
});

test('verifyEvidenceFiles reaches the complete real-repository source and capture proof path', { timeout: 120_000 }, async () => {
  const evidenceRoot = await mkdtemp(path.join(os.tmpdir(), 'cb-evidence-complete-'));
  const desktopCommit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: DESKTOP_ROOT, encoding: 'utf8' }).trim();
  const upstreamRecords = new Map();
  const desktopRecords = new Map();
  const upstreamRows = {};
  const visualRows = {};
  try {
    const record = async (cache, root, commit, relativePath) => {
      if (!cache.has(relativePath)) cache.set(relativePath, await collectSourceRecord(root, commit, relativePath));
      return cache.get(relativePath);
    };
    for (const rowId of ROW_IDS) {
      const expected = ROWS[rowId];
      const upstreamStates = [];
      const desktopCaptures = [];
      const width = expected.dimensions.cssViewportWidth * expected.dimensions.devicePixelRatio;
      const height = expected.dimensions.cssViewportHeight * expected.dimensions.devicePixelRatio;
      assert.equal(Number.isInteger(width) && Number.isInteger(height), true);
      const bytes = pngBytes(width, height);
      const captureSha = createHash('sha256').update(bytes).digest('hex');
      for (const state of expected.upstreamStates) {
        const relativePath = CAPTURE_RELATIVE_PATH.upstream(state.captureId);
        await mkdir(path.dirname(path.join(evidenceRoot, relativePath)), { recursive: true });
        await writeFile(path.join(evidenceRoot, relativePath), bytes);
        upstreamStates.push({ stateId: state.stateId, captureId: state.captureId, sha256: captureSha });
      }
      for (const captureId of expected.desktopCaptures) {
        const relativePath = CAPTURE_RELATIVE_PATH.desktop(captureId);
        await mkdir(path.dirname(path.join(evidenceRoot, relativePath)), { recursive: true });
        await writeFile(path.join(evidenceRoot, relativePath), bytes);
        desktopCaptures.push({ captureId, sha256: captureSha });
      }
      upstreamRows[rowId] = {
        sources: await Promise.all(expected.upstreamSources.map((relativePath) => record(upstreamRecords, UPSTREAM_ROOT, UPSTREAM_COMMIT, relativePath))),
        states: upstreamStates,
      };
      visualRows[rowId] = {
        desktopSources: await Promise.all(expected.desktopSources.map((relativePath) => record(desktopRecords, DESKTOP_ROOT, desktopCommit, relativePath))),
        upstreamCaptureIds: expected.upstreamStates.map((state) => state.captureId),
        desktopScenarioId: expected.desktopScenarioId,
        desktopCaptures,
        status: 'blocked',
        blocker: { code: 'comparison-incomplete', message: 'Evidence row is blocked.' },
        decision: null,
        dimensions: { ...expected.dimensions },
      };
    }
    const upstreamManifest = {
      schemaVersion: 1,
      evidenceSessionId: SESSION,
      capturedAtUtc: CAPTURED_AT,
      upstreamCommit: UPSTREAM_COMMIT,
      rows: upstreamRows,
    };
    const visualManifest = {
      schemaVersion: 1,
      evidenceSessionId: SESSION,
      capturedAtUtc: CAPTURED_AT,
      upstreamCommit: UPSTREAM_COMMIT,
      desktopCommit,
      windowsAclProof: validVisual().windowsAclProof,
      rows: visualRows,
    };
    await assert.doesNotReject(verifyEvidenceFiles({
      upstreamManifest,
      visualManifest,
      upstreamRoot: UPSTREAM_ROOT,
      desktopRoot: DESKTOP_ROOT,
      evidenceRoot,
      expectedDesktopCommit: desktopCommit,
    }));
    const wrongRow = upstreamManifest.rows['UI-17'];
    const wrongCapture = wrongRow.states[0];
    const wrongRelativePath = CAPTURE_RELATIVE_PATH.upstream(wrongCapture.captureId);
    const wrongBytes = pngBytes(1, 1);
    wrongCapture.sha256 = createHash('sha256').update(wrongBytes).digest('hex');
    await writeFile(path.join(evidenceRoot, wrongRelativePath), wrongBytes);
    await assert.rejects(verifyEvidenceFiles({
      upstreamManifest,
      visualManifest,
      upstreamRoot: UPSTREAM_ROOT,
      desktopRoot: DESKTOP_ROOT,
      evidenceRoot,
      expectedDesktopCommit: desktopCommit,
    }), /bitmap dimensions/u);
  } finally {
    await rm(evidenceRoot, { recursive: true, force: true });
  }
});
