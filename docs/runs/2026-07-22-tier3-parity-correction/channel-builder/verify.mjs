import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { lstat, readFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { inflateSync } from 'node:zlib';
import {
  BLOCKER_CODES,
  CAPTURE_RELATIVE_PATH,
  ROW_IDS,
  ROWS,
  UPSTREAM_COMMIT,
} from './states.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const DESKTOP_ROOT = path.resolve(HERE, '../../../..');
const UPSTREAM_ROOT_ENV = 'LINEUP_WS1_UPSTREAM_ROOT';

export function resolveUpstreamRoot({
  environment = process.env,
  desktopRoot = DESKTOP_ROOT,
} = {}) {
  const isSet = Object.prototype.hasOwnProperty.call(environment, UPSTREAM_ROOT_ENV);
  const candidate = isSet
    ? environment[UPSTREAM_ROOT_ENV]
    : path.join(path.dirname(desktopRoot), 'Lineup');
  if (typeof candidate !== 'string' || candidate.length === 0 || !path.isAbsolute(candidate)) {
    fail('Upstream checkout configuration is invalid.');
  }
  return path.resolve(candidate);
}

export const UPSTREAM_ROOT = resolveUpstreamRoot();

const HEX_40 = /^[a-f0-9]{40}$/u;
const HEX_64 = /^[a-f0-9]{64}$/u;
const SAFE_ID = /^[A-Za-z0-9._-]{1,120}$/u;
const SESSION_ID = /^cb-evidence-[a-f0-9]{32}$/u;
const UTC_MILLISECONDS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u;
const STATUS_VALUES = new Set(['match', 'adaptation', 'divergence', 'blocked']);
const ACL_TARGETS = ['persistenceParent', 'channelFile', 'smokeRoot', 'smokeSentinel'];

export class EvidenceContractError extends Error {
  constructor(message) {
    super(message);
    this.name = 'EvidenceContractError';
  }
}

function fail(message) {
  throw new EvidenceContractError(message);
}

function object(value, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object`);
}

function exactKeys(value, expected, label) {
  object(value, label);
  const actual = Object.keys(value);
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    fail(`${label} keys must be exactly ${expected.join(', ')} in order`);
  }
}

function exactArray(actual, expected, label) {
  if (!Array.isArray(actual)) fail(`${label} must be an array`);
  if (actual.length !== expected.length || actual.some((value, index) => value !== expected[index])) {
    fail(`${label} must exactly match the frozen order`);
  }
  if (new Set(actual).size !== actual.length) fail(`${label} contains duplicates`);
}

function pattern(value, expression, label) {
  if (typeof value !== 'string' || !expression.test(value)) fail(`${label} has an invalid value`);
}

function timestamp(value, label) {
  pattern(value, UTC_MILLISECONDS, label);
  if (new Date(value).toISOString() !== value) fail(`${label} is not an exact UTC timestamp`);
}

function repositoryPath(value, label) {
  if (typeof value !== 'string' || value.length === 0 || value.startsWith('/') || value.includes('\\')) {
    fail(`${label} must be a repository-relative POSIX path`);
  }
  const segments = value.split('/');
  if (segments.some((segment) => segment === '' || segment === '.' || segment === '..')) {
    fail(`${label} contains an unsafe segment`);
  }
}

function positiveFinite(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) fail(`${label} must be finite and positive`);
}

function validateSource(value, expectedPath, label) {
  exactKeys(value, ['path', 'gitBlob', 'sha256'], label);
  repositoryPath(value.path, `${label}.path`);
  if (value.path !== expectedPath) fail(`${label}.path differs from the approved source closure`);
  pattern(value.gitBlob, HEX_40, `${label}.gitBlob`);
  pattern(value.sha256, HEX_64, `${label}.sha256`);
}

function validateCapture(value, expectedCaptureId, label, idKey = 'captureId') {
  exactKeys(value, [idKey, 'sha256'], label);
  pattern(value[idKey], SAFE_ID, `${label}.${idKey}`);
  if (value[idKey] !== expectedCaptureId) fail(`${label}.${idKey} differs from the frozen capture order`);
  pattern(value.sha256, HEX_64, `${label}.sha256`);
}

function validateRowsObject(rows, label) {
  exactKeys(rows, ROW_IDS, label);
}

export function validateUpstreamManifest(manifest) {
  exactKeys(manifest, ['schemaVersion', 'evidenceSessionId', 'capturedAtUtc', 'upstreamCommit', 'rows'], 'upstream manifest');
  if (manifest.schemaVersion !== 1) fail('upstream manifest schemaVersion must be 1');
  pattern(manifest.evidenceSessionId, SESSION_ID, 'upstream manifest evidenceSessionId');
  timestamp(manifest.capturedAtUtc, 'upstream manifest capturedAtUtc');
  pattern(manifest.upstreamCommit, HEX_40, 'upstream manifest upstreamCommit');
  if (manifest.upstreamCommit !== UPSTREAM_COMMIT) fail('upstream manifest does not use the audited full pin');
  validateRowsObject(manifest.rows, 'upstream manifest rows');
  for (const rowId of ROW_IDS) {
    const expected = ROWS[rowId];
    const rowValue = manifest.rows[rowId];
    exactKeys(rowValue, ['sources', 'states'], `upstream ${rowId}`);
    if (!Array.isArray(rowValue.sources) || rowValue.sources.length !== expected.upstreamSources.length) {
      fail(`upstream ${rowId}.sources differs from the frozen source list`);
    }
    rowValue.sources.forEach((source, index) => validateSource(source, expected.upstreamSources[index], `upstream ${rowId}.sources[${index}]`));
    if (!Array.isArray(rowValue.states) || rowValue.states.length !== expected.upstreamStates.length) {
      fail(`upstream ${rowId}.states differs from the frozen state list`);
    }
    rowValue.states.forEach((state, index) => {
      const expectedState = expected.upstreamStates[index];
      exactKeys(state, ['stateId', 'captureId', 'sha256'], `upstream ${rowId}.states[${index}]`);
      pattern(state.stateId, SAFE_ID, `upstream ${rowId}.states[${index}].stateId`);
      pattern(state.captureId, SAFE_ID, `upstream ${rowId}.states[${index}].captureId`);
      pattern(state.sha256, HEX_64, `upstream ${rowId}.states[${index}].sha256`);
      if (state.stateId !== expectedState.stateId || state.captureId !== expectedState.captureId) {
        fail(`upstream ${rowId}.states differs from the frozen state/capture order`);
      }
    });
    uniqueRecords(rowValue.sources, (entry) => entry.path, `upstream ${rowId}.sources`);
    uniqueRecords(rowValue.states, (entry) => `${entry.stateId}\0${entry.captureId}`, `upstream ${rowId}.states`);
  }
  rejectUnsafeMaterial(manifest, 'upstream manifest');
  return manifest;
}

function validateAclResult(value, label) {
  exactKeys(value, ACL_TARGETS, label);
  return ACL_TARGETS.map((target) => {
    const result = value[target];
    if (result !== null && typeof result !== 'boolean') fail(`${label}.${target} must be boolean or null`);
    return result;
  });
}

function validateWindowsAclProof(value) {
  exactKeys(value, [
    'scope',
    'status',
    'packageIdentity',
    'observedAtUtc',
    'currentUserControl',
    'broadWriteAbsent',
    'inheritsFromValidatedParent',
  ], 'windowsAclProof');
  if (!['not-run', 'unpackaged-preliminary', 'packaged'].includes(value.scope)) fail('windowsAclProof.scope is invalid');
  if (!['pending', 'passed', 'blocked'].includes(value.status)) fail('windowsAclProof.status is invalid');
  const results = [
    ...validateAclResult(value.currentUserControl, 'windowsAclProof.currentUserControl'),
    ...validateAclResult(value.broadWriteAbsent, 'windowsAclProof.broadWriteAbsent'),
    ...validateAclResult(value.inheritsFromValidatedParent, 'windowsAclProof.inheritsFromValidatedParent'),
  ];
  if (value.scope === 'not-run') {
    if (value.status !== 'pending' || value.packageIdentity !== null || value.observedAtUtc !== null || results.some((result) => result !== null)) {
      fail('not-run ACL proof must be pending with null identity, observation, and results');
    }
    return;
  }
  pattern(value.packageIdentity, SAFE_ID, 'windowsAclProof.packageIdentity');
  timestamp(value.observedAtUtc, 'windowsAclProof.observedAtUtc');
  if (results.some((result) => typeof result !== 'boolean')) fail(`${value.scope} ACL proof requires all 12 boolean results`);
  const allTrue = results.every(Boolean);
  if (value.scope === 'unpackaged-preliminary') {
    if (!['pending', 'blocked'].includes(value.status)) fail('unpackaged ACL proof cannot pass');
  } else if ((value.status === 'passed') !== allTrue || !['passed', 'blocked'].includes(value.status)) {
    fail('packaged ACL status must pass if and only if all 12 results pass');
  }
}

function validateDecision(status, blocker, decision, label) {
  if (!STATUS_VALUES.has(status)) fail(`${label}.status is invalid`);
  if (status === 'blocked') {
    exactKeys(blocker, ['code', 'message'], `${label}.blocker`);
    if (!BLOCKER_CODES.includes(blocker.code) || blocker.message !== 'Evidence row is blocked.') fail(`${label}.blocker is invalid`);
    if (decision !== null) fail(`${label}.decision must be null while blocked`);
    return;
  }
  if (blocker !== null) fail(`${label}.blocker must be null unless blocked`);
  if (status === 'match') {
    if (decision !== null) fail(`${label}.decision must be null for match`);
  } else if (status === 'adaptation') {
    exactKeys(decision, ['kind', 'rationaleCode'], `${label}.decision`);
    if (decision.kind !== 'electron-adaptation' || !['input-model', 'platform-layout', 'accessibility', 'native-shell'].includes(decision.rationaleCode)) {
      fail(`${label}.decision is not an approved Electron adaptation`);
    }
  } else {
    exactKeys(decision, ['kind', 'rationaleCode'], `${label}.decision`);
    if (decision.kind !== 'approved-divergence' || decision.rationaleCode !== 'desktop-product-decision') {
      fail(`${label}.decision is not an approved divergence`);
    }
  }
}

export function validateVisualManifest(manifest) {
  exactKeys(manifest, [
    'schemaVersion',
    'evidenceSessionId',
    'capturedAtUtc',
    'upstreamCommit',
    'desktopCommit',
    'windowsAclProof',
    'rows',
  ], 'visual manifest');
  if (manifest.schemaVersion !== 1) fail('visual manifest schemaVersion must be 1');
  pattern(manifest.evidenceSessionId, SESSION_ID, 'visual manifest evidenceSessionId');
  timestamp(manifest.capturedAtUtc, 'visual manifest capturedAtUtc');
  pattern(manifest.upstreamCommit, HEX_40, 'visual manifest upstreamCommit');
  pattern(manifest.desktopCommit, HEX_40, 'visual manifest desktopCommit');
  if (manifest.upstreamCommit !== UPSTREAM_COMMIT) fail('visual manifest does not use the audited full upstream pin');
  validateWindowsAclProof(manifest.windowsAclProof);
  validateRowsObject(manifest.rows, 'visual manifest rows');
  for (const rowId of ROW_IDS) {
    const expected = ROWS[rowId];
    const rowValue = manifest.rows[rowId];
    const label = `visual ${rowId}`;
    exactKeys(rowValue, [
      'desktopSources',
      'upstreamCaptureIds',
      'desktopScenarioId',
      'desktopCaptures',
      'status',
      'blocker',
      'decision',
      'dimensions',
    ], label);
    if (!Array.isArray(rowValue.desktopSources) || rowValue.desktopSources.length !== expected.desktopSources.length) {
      fail(`${label}.desktopSources differs from the approved closure`);
    }
    rowValue.desktopSources.forEach((source, index) => validateSource(source, expected.desktopSources[index], `${label}.desktopSources[${index}]`));
    exactArray(rowValue.upstreamCaptureIds, expected.upstreamStates.map((state) => state.captureId), `${label}.upstreamCaptureIds`);
    pattern(rowValue.desktopScenarioId, SAFE_ID, `${label}.desktopScenarioId`);
    if (rowValue.desktopScenarioId !== expected.desktopScenarioId) fail(`${label}.desktopScenarioId differs from the frozen scenario`);
    if (!Array.isArray(rowValue.desktopCaptures) || rowValue.desktopCaptures.length !== expected.desktopCaptures.length) {
      fail(`${label}.desktopCaptures differs from the frozen capture list`);
    }
    rowValue.desktopCaptures.forEach((capture, index) => validateCapture(capture, expected.desktopCaptures[index], `${label}.desktopCaptures[${index}]`));
    uniqueRecords(rowValue.desktopSources, (entry) => entry.path, `${label}.desktopSources`);
    uniqueRecords(rowValue.desktopCaptures, (entry) => entry.captureId, `${label}.desktopCaptures`);
    validateDecision(rowValue.status, rowValue.blocker, rowValue.decision, label);
    exactKeys(rowValue.dimensions, [
      'contentDipWidth',
      'contentDipHeight',
      'cssViewportWidth',
      'cssViewportHeight',
      'windowsScalePercent',
      'devicePixelRatio',
      'zoomPercent',
    ], `${label}.dimensions`);
    for (const [key, expectedValue] of Object.entries(expected.dimensions)) {
      positiveFinite(rowValue.dimensions[key], `${label}.dimensions.${key}`);
      if (rowValue.dimensions[key] !== expectedValue) fail(`${label}.dimensions.${key} differs from the scenario`);
    }
  }
  rejectUnsafeMaterial(manifest, 'visual manifest');
  return manifest;
}

export function validateEvidencePair(upstreamManifest, visualManifest, expectedDesktopCommit = visualManifest.desktopCommit) {
  validateUpstreamManifest(upstreamManifest);
  validateVisualManifest(visualManifest);
  if (upstreamManifest.evidenceSessionId !== visualManifest.evidenceSessionId) fail('paired manifests use different evidence sessions');
  if (upstreamManifest.upstreamCommit !== visualManifest.upstreamCommit) fail('paired manifests use different upstream commits');
  if (visualManifest.desktopCommit !== expectedDesktopCommit) fail('visual manifest desktopCommit differs from captured HEAD');
  for (const rowId of ROW_IDS) {
    const upstreamStates = upstreamManifest.rows[rowId].states;
    const visualReferences = visualManifest.rows[rowId].upstreamCaptureIds;
    const expectedReferences = upstreamStates.map((state) => state.captureId);
    exactArray(visualReferences, expectedReferences, `paired ${rowId} upstream capture references`);
  }
  return { upstreamManifest, visualManifest };
}

function uniqueRecords(values, identity, label) {
  const identities = values.map(identity);
  if (new Set(identities).size !== identities.length) fail(`${label} contains duplicates`);
}

function rejectUnsafeMaterial(value, label) {
  const serialized = JSON.stringify(value);
  if (/(?:https?:\/\/|X-Plex-Token|Authorization\s*:|S-\d-\d+(?:-\d+)+|Get-Acl|icacls|\bBUILTIN\\|\bUsers\\)/iu.test(serialized)) {
    fail(`${label} contains forbidden raw or identifying material`);
  }
}

export function runGit(root, args, options = {}) {
  try {
    return execFileSync('git', args, {
      cwd: root,
      encoding: options.encoding ?? 'utf8',
      stdio: options.stdio ?? ['ignore', 'pipe', 'pipe'],
    });
  } catch {
    fail('Git command failed.');
  }
}

export async function validateUpstreamRoot({
  upstreamRoot = resolveUpstreamRoot(),
} = {}) {
  if (typeof upstreamRoot !== 'string' || upstreamRoot.length === 0 || !path.isAbsolute(upstreamRoot)) {
    fail('Upstream checkout configuration is invalid.');
  }
  const resolvedRoot = path.resolve(upstreamRoot);
  const info = await lstat(resolvedRoot).catch(() => null);
  if (info === null || !info.isDirectory() || info.isSymbolicLink()) {
    fail('Upstream checkout is unavailable.');
  }
  const canonicalRoot = await realpath(resolvedRoot).catch(() => fail('Upstream checkout is unavailable.'));
  let topLevel;
  let head;
  try {
    topLevel = runGit(canonicalRoot, ['rev-parse', '--show-toplevel']).trim();
    head = runGit(canonicalRoot, ['rev-parse', 'HEAD']).trim();
  } catch {
    fail('Upstream checkout Git validation failed.');
  }
  if (path.resolve(topLevel) !== canonicalRoot) fail('Upstream checkout Git top-level is invalid.');
  if (head !== UPSTREAM_COMMIT) fail('Upstream checkout HEAD differs from the audited full pin.');
  return canonicalRoot;
}

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

export async function collectSourceRecord(root, commit, relativePath) {
  repositoryPath(relativePath, 'source path');
  const untracked = runGit(root, ['ls-files', '--others', '--exclude-standard', '--', relativePath]).trim();
  if (untracked !== '') fail(`${relativePath} has an untracked substitute`);
  let tracked;
  try {
    tracked = runGit(root, ['ls-files', '--error-unmatch', '--', relativePath]).trim();
  } catch {
    fail(`${relativePath} is not tracked at the expected path`);
  }
  if (tracked !== relativePath) fail(`${relativePath} is not tracked at the expected path`);
  runGit(root, ['cat-file', '-e', `${commit}:${relativePath}`]);
  const gitBlob = runGit(root, ['rev-parse', `${commit}:${relativePath}`]).trim();
  pattern(gitBlob, HEX_40, `${relativePath} Git blob`);
  const pinnedBytes = runGit(root, ['show', `${commit}:${relativePath}`], { encoding: 'buffer' });
  const worktreeBytes = await readFile(path.join(root, relativePath));
  const pinnedSha256 = sha256(pinnedBytes);
  if (sha256(worktreeBytes) !== pinnedSha256) fail(`${relativePath} worktree bytes differ from ${commit}`);
  try {
    runGit(root, ['diff', '--quiet', '--', relativePath], { stdio: 'ignore' });
    runGit(root, ['diff', '--cached', '--quiet', commit, '--', relativePath], { stdio: 'ignore' });
  } catch {
    fail(`${relativePath} has staged or unstaged changes`);
  }
  return { path: relativePath, gitBlob, sha256: pinnedSha256 };
}

export async function verifySourceRecord(root, commit, record) {
  const actual = await collectSourceRecord(root, commit, record.path);
  if (actual.gitBlob !== record.gitBlob || actual.sha256 !== record.sha256) {
    fail(`${record.path} does not match its recorded blob and SHA-256`);
  }
  return actual;
}

export async function sourceSnapshot(root, records) {
  const snapshot = {};
  for (const record of records) snapshot[record.path] = sha256(await readFile(path.join(root, record.path)));
  return snapshot;
}

export async function verifySourceSnapshot(root, snapshot) {
  for (const [relativePath, expectedSha256] of Object.entries(snapshot)) {
    if (sha256(await readFile(path.join(root, relativePath))) !== expectedSha256) fail(`${relativePath} changed after preflight`);
  }
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) === 1 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export function validatePngBuffer(bytes, dimensions) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 45 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
    fail('capture is not a structurally complete PNG');
  }
  let offset = 8;
  let chunkIndex = 0;
  let ihdr = null;
  let sawIdat = false;
  let idatEnded = false;
  let sawIend = false;
  const idatParts = [];
  while (offset < bytes.length) {
    if (bytes.length - offset < 12) fail('PNG has a truncated chunk header');
    const length = bytes.readUInt32BE(offset);
    const chunkEnd = offset + 12 + length;
    if (!Number.isSafeInteger(chunkEnd) || chunkEnd > bytes.length) fail('PNG chunk exceeds file bounds');
    const typeBytes = bytes.subarray(offset + 4, offset + 8);
    const type = typeBytes.toString('ascii');
    if (!/^[A-Za-z]{4}$/u.test(type)) fail('PNG chunk type is invalid');
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    const recordedCrc = bytes.readUInt32BE(offset + 8 + length);
    if (crc32(Buffer.concat([typeBytes, data])) !== recordedCrc) fail(`PNG ${type} chunk CRC mismatch`);
    if (chunkIndex === 0 && type !== 'IHDR') fail('PNG IHDR must be the first chunk');
    if (sawIend) fail('PNG contains data after IEND');
    if (type === 'IHDR') {
      if (ihdr !== null || chunkIndex !== 0 || length !== 13) fail('PNG must contain one 13-byte first IHDR');
      const width = data.readUInt32BE(0);
      const height = data.readUInt32BE(4);
      const bitDepth = data[8];
      const colorType = data[9];
      const compression = data[10];
      const filter = data[11];
      const interlace = data[12];
      if (width <= 0 || height <= 0) fail('PNG dimensions must be positive');
      if (dimensions !== undefined) {
        const expectedWidth = dimensions.cssViewportWidth * dimensions.devicePixelRatio;
        const expectedHeight = dimensions.cssViewportHeight * dimensions.devicePixelRatio;
        if (!Number.isInteger(expectedWidth) || !Number.isInteger(expectedHeight) || expectedWidth <= 0 || expectedHeight <= 0) {
          fail('scenario bitmap dimensions must be positive integers');
        }
        if (width !== expectedWidth || height !== expectedHeight) {
          fail('capture bitmap dimensions differ from the frozen scenario');
        }
      }
      const supportedDepths = {
        0: [1, 2, 4, 8, 16],
        2: [8, 16],
        4: [8, 16],
        6: [8, 16],
      };
      if (!supportedDepths[colorType]?.includes(bitDepth)) fail('PNG color type and bit depth are unsupported');
      if (compression !== 0 || filter !== 0 || interlace !== 0) fail('PNG compression, filter, or interlace method is unsupported');
      ihdr = { width, height, bitDepth, colorType };
    } else if (type === 'IDAT') {
      if (ihdr === null || idatEnded) fail('PNG IDAT chunks must be consecutive after IHDR');
      sawIdat = true;
      idatParts.push(data);
    } else {
      if (sawIdat) idatEnded = true;
      if (type === 'IEND') {
        if (length !== 0) fail('PNG IEND must be empty');
        sawIend = true;
      } else if (type === 'PLTE') {
        if (sawIdat || length === 0 || length > 768 || length % 3 !== 0) fail('PNG PLTE chunk is invalid');
      } else if (type[0] === type[0].toUpperCase() && type !== 'PLTE') {
        fail(`PNG contains unsupported critical chunk ${type}`);
      }
    }
    offset = chunkEnd;
    chunkIndex += 1;
  }
  if (ihdr === null || !sawIdat || !sawIend || offset !== bytes.length) fail('PNG is missing required terminal chunks');
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[ihdr.colorType];
  const rowBytes = Math.ceil((ihdr.width * channels * ihdr.bitDepth) / 8);
  const stride = rowBytes + 1;
  const expectedInflatedLength = stride * ihdr.height;
  if (!Number.isSafeInteger(stride) || !Number.isSafeInteger(expectedInflatedLength) || expectedInflatedLength > 268_435_456) {
    fail('PNG inflated scanline length is invalid');
  }
  let inflated;
  try {
    inflated = inflateSync(Buffer.concat(idatParts), { maxOutputLength: expectedInflatedLength + 1 });
  } catch {
    fail('PNG IDAT stream is not decodable');
  }
  if (inflated.length !== expectedInflatedLength) {
    fail('PNG inflated scanline length is invalid');
  }
  for (let row = 0; row < ihdr.height; row += 1) {
    if (inflated[row * stride] > 4) fail('PNG scanline filter is invalid');
  }
  return { width: ihdr.width, height: ihdr.height };
}

export async function verifyCaptureFile(root, relativePath, expectedSha256, dimensions) {
  repositoryPath(relativePath, 'capture path');
  const absolute = path.join(root, relativePath);
  const info = await lstat(absolute).catch(() => null);
  if (info === null || !info.isFile() || info.isSymbolicLink()) fail(`${relativePath} capture is missing or unsafe`);
  const bytes = await readFile(absolute);
  validatePngBuffer(bytes, dimensions);
  if (sha256(bytes) !== expectedSha256) fail(`${relativePath} capture SHA-256 mismatch`);
}

export async function verifyEvidenceFiles({
  upstreamManifest,
  visualManifest,
  upstreamRoot = UPSTREAM_ROOT,
  desktopRoot = DESKTOP_ROOT,
  evidenceRoot = HERE,
  expectedDesktopCommit,
}) {
  const desktopHead = runGit(desktopRoot, ['rev-parse', 'HEAD']).trim();
  const expectedHead = expectedDesktopCommit ?? desktopHead;
  validateEvidencePair(upstreamManifest, visualManifest, expectedHead);
  const validatedUpstreamRoot = await validateUpstreamRoot({ upstreamRoot });
  for (const rowId of ROW_IDS) {
    for (const source of upstreamManifest.rows[rowId].sources) await verifySourceRecord(validatedUpstreamRoot, UPSTREAM_COMMIT, source);
    for (const source of visualManifest.rows[rowId].desktopSources) await verifySourceRecord(desktopRoot, expectedHead, source);
    for (const state of upstreamManifest.rows[rowId].states) {
      await verifyCaptureFile(evidenceRoot, CAPTURE_RELATIVE_PATH.upstream(state.captureId), state.sha256, ROWS[rowId].dimensions);
    }
    for (const capture of visualManifest.rows[rowId].desktopCaptures) {
      await verifyCaptureFile(evidenceRoot, CAPTURE_RELATIVE_PATH.desktop(capture.captureId), capture.sha256, ROWS[rowId].dimensions);
    }
  }
  return { evidenceSessionId: visualManifest.evidenceSessionId, desktopCommit: expectedHead };
}

export async function readManifests(evidenceRoot = HERE) {
  const upstreamPath = path.join(evidenceRoot, 'upstream-reference-manifest.json');
  const visualPath = path.join(evidenceRoot, 'visual-comparison.json');
  const [upstreamBytes, visualBytes] = await Promise.all([
    readFile(upstreamPath, 'utf8').catch(() => fail('upstream-reference-manifest.json is unavailable')),
    readFile(visualPath, 'utf8').catch(() => fail('visual-comparison.json is unavailable')),
  ]);
  const upstreamManifest = JSON.parse(upstreamBytes);
  const visualManifest = JSON.parse(visualBytes);
  return { upstreamManifest, visualManifest };
}

async function main() {
  const contractOnly = process.argv.includes('--contract-only');
  const { upstreamManifest, visualManifest } = await readManifests();
  if (contractOnly) {
    validateEvidencePair(upstreamManifest, visualManifest);
    process.stdout.write(`Contract-valid blocked or captured evidence session ${visualManifest.evidenceSessionId}\n`);
    return;
  }
  const result = await verifyEvidenceFiles({ upstreamManifest, visualManifest });
  process.stdout.write(`Verified complete evidence session ${result.evidenceSessionId} at Desktop ${result.desktopCommit}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.name ?? 'Error'}: ${error.message ?? String(error)}\n`);
    process.exitCode = 1;
  });
}
