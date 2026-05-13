import fs from 'node:fs/promises';
import fsSync from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { scanFileContent, scanSupportBundleDirectory } from './verify-redaction.mjs';

export const REQUIRED_RD17_SMOKE_FILES = [
  'manifest.json',
  'summary.json',
  'redaction-report.json',
  'support-bundle/manifest.json',
  'support-bundle/diagnostics.ndjson',
  'support-bundle/crash-recovery.json',
  'support-bundle/player-snapshot.json',
  'support-bundle/environment.json',
  'support-bundle/redaction-report.json',
];

const SCRIPT_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIRECTORY, '..');
const DIST_ROOT = path.join(REPO_ROOT, 'dist');
export const RD17_SMOKE_EVIDENCE_ROOT = 'docs/runs/rd-17-diagnostics-crash-recovery-support-bundle';
export const RD17_SMOKE_EVIDENCE_ROOT_ABSOLUTE = path.resolve(REPO_ROOT, RD17_SMOKE_EVIDENCE_ROOT);
const SUPPORT_BUNDLE_PARENT_NAME = 'support-bundle-parent';
const SUPPORT_BUNDLE_ID = 'windows-smoke';
const CREATED_AT_MS = 1_801_000_000_000;

const LOAD_COMMAND = {
  command: 'load',
  requestId: 'rd17-load-1',
  payload: {
    media: {
      id: 'rd17-media-1',
      title: 'RD-17 smoke media',
      durationMs: 1000,
      container: 'mkv',
    },
    policy: {
      autoplay: true,
      startPositionMs: 0,
      preferredAudioTrackId: null,
      preferredSubtitleTrackId: null,
    },
    capabilityProfileId: 'rd17-smoke',
  },
};

const REPLACEMENT_LOAD_COMMAND = {
  ...LOAD_COMMAND,
  requestId: 'rd17-load-2',
};

export function isWindowsProofPlatform(platform = process.platform) {
  return platform === 'win32';
}

export function parseSmokeArgs(argv = process.argv.slice(2)) {
  const outIndex = argv.indexOf('--out');
  if (outIndex < 0 || outIndex === argv.length - 1 || argv[outIndex + 1]?.startsWith('--')) {
    throw new Error('Usage: node tools/rd17-diagnostics-smoke.mjs --out <evidence-directory>');
  }
  return {
    outDirectory: argv[outIndex + 1],
  };
}

async function main() {
  let args;
  try {
    args = parseSmokeArgs();
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'Invalid RD-17 smoke arguments.');
    process.exitCode = 1;
    return;
  }

  let outRoot;
  try {
    outRoot = resolveEvidenceDirectory(args.outDirectory);
  } catch (error) {
    console.error(formatSmokeFailure(error));
    process.exitCode = 1;
    return;
  }

  if (!isWindowsProofPlatform()) {
    console.error('RD-17 diagnostics smoke requires Windows; proof not claimed.');
    process.exitCode = 1;
    return;
  }

  try {
    await runWindowsSmoke(outRoot);
    console.log('RD-17 diagnostics smoke passed.');
  } catch (error) {
    console.error(formatSmokeFailure(error));
    process.exitCode = 1;
  }
}

async function runWindowsSmoke(outRoot) {
  runBuild();

  await fs.rm(outRoot, { recursive: true, force: true });
  await fs.mkdir(outRoot, { recursive: true, mode: 0o700 });

  const [
    { DiagnosticEventStore },
    { SupportBundleExporter },
    { NativePlayerHostProcess },
  ] = await Promise.all([
    importDistModule('main/diagnostics/diagnosticEventStore.js'),
    importDistModule('main/diagnostics/supportBundleExporter.js'),
    importDistModule('main/player/nativePlayerHostProcess.js'),
  ]);

  const diagnostics = new DiagnosticEventStore({
    clock: createClock(CREATED_AT_MS),
    idGenerator: createIdGenerator('rd17-smoke-record'),
  });
  const spawnedChildren = [];
  const host = new NativePlayerHostProcess({
    spawnHostProcess: () => {
      const child = spawnHelperProcess(spawnedChildren.length === 0 ? createCrashHelperScript() : createSuccessHelperScript());
      spawnedChildren.push(child);
      return child;
    },
    requestTimeoutMs: 5000,
    cleanupGraceMs: 250,
    diagnosticEventStore: diagnostics,
  });

  diagnostics.record({
    surface: 'main',
    category: 'lifecycle',
    severity: 'info',
    status: 'observed',
    operation: 'smoke.start',
    message: 'RD-17 diagnostics smoke started.',
  });

  const failedResult = await host.execute(LOAD_COMMAND);
  await waitForChildClose(spawnedChildren[0]);
  const replacementResult = await host.execute(REPLACEMENT_LOAD_COMMAND);
  await host.cleanup(REPLACEMENT_LOAD_COMMAND.requestId);
  await waitForChildClose(spawnedChildren[1]);

  const crashRecovery = diagnostics.getCrashRecoverySummary();
  assertSmoke(failedResult.ok === false, 'Expected first helper command to fail safely.');
  assertSmoke(failedResult.ok ? false : failedResult.error.code === 'PLAYER_HELPER_EXITED', 'Expected safe helper exit error.');
  assertSmoke(replacementResult.ok === true, 'Expected replacement helper command to succeed.');
  assertSmoke(spawnedChildren.length === 2, 'Expected replacement helper spawn.');
  assertSmoke(crashRecovery.helperCrashCount >= 1, 'Expected helper crash diagnostic.');
  assertSmoke(crashRecovery.helperRestartCount >= 1, 'Expected helper restart diagnostic.');
  assertSmoke(spawnedChildren.every(hasObservedChildExit), 'Expected helper cleanup or exit observation.');

  const supportParent = path.join(outRoot, SUPPORT_BUNDLE_PARENT_NAME);
  await fs.mkdir(supportParent, { recursive: false, mode: 0o700 });
  const exporter = new SupportBundleExporter({
    eventStore: diagnostics,
    parentDirectoryProvider: () => supportParent,
    redactionScanner: (bundleDirectory, options) => scanSupportBundleDirectory(bundleDirectory, options),
    clock: () => CREATED_AT_MS,
    bundleIdGenerator: () => SUPPORT_BUNDLE_ID,
    appVersion: '0.0.0',
    platformFamily: 'win32',
    shellMode: 'smoke',
    crashRecoveryProvider: () => diagnostics.getCrashRecoverySummary(),
    playerSnapshotProvider: () => createSafePlayerSnapshot(),
    environmentProvider: () => createSafeEnvironmentSummary(),
  });

  const exportResult = await exporter.exportSupportBundle();
  assertSmoke(exportResult.status === 'succeeded', 'Expected support bundle export success.');
  assertSmoke(exportResult.bundleId === SUPPORT_BUNDLE_ID, 'Expected safe support bundle id.');
  assertSmoke(exportResult.bundleDirectoryName === `lineup-desktop-support-${SUPPORT_BUNDLE_ID}`, 'Expected safe support bundle directory name.');
  assertSmoke(exportResult.redactionReport.status === 'passed', 'Expected completed bundle scan to pass.');
  assertSmoke(JSON.stringify(exportResult).includes(supportParent) === false, 'Renderer-visible result exposed parent custody.');

  const generatedBundleDirectory = path.join(supportParent, exportResult.bundleDirectoryName);
  const evidenceBundleDirectory = path.join(outRoot, 'support-bundle');
  await fs.rename(generatedBundleDirectory, evidenceBundleDirectory);
  await fs.rm(supportParent, { recursive: true, force: true });
  await assertRequiredSupportBundleFiles(evidenceBundleDirectory);

  const supportBundleReport = scanSupportBundleDirectory(evidenceBundleDirectory, {
    timestampMs: CREATED_AT_MS,
    truncatedRecordCount: exportResult.redactionReport.truncatedRecordCount,
    omittedFileCount: exportResult.redactionReport.omittedFileCount,
  });
  assertSmoke(supportBundleReport.status === 'passed', 'Expected support bundle evidence scan to pass.');

  const summary = {
    schemaVersion: 1,
    status: 'passed',
    platform: 'win32',
    helperCrashDetected: crashRecovery.helperCrashCount >= 1,
    mainProcessAlive: true,
    failedRequestSafeErrorState: failedResult.ok === false && failedResult.error.code === 'PLAYER_HELPER_EXITED',
    helperCleanupReapObserved: spawnedChildren.every(hasObservedChildExit),
    replacementHelperUsed: spawnedChildren.length === 2 && replacementResult.ok === true,
    supportBundleTargetMainCreatedUnderInjectedParent: true,
    rendererVisibleResultContainsOnlyBundleIdentity: rendererVisibleResultContainsOnlyBundleIdentity(exportResult),
    completedBundleScanStatus: supportBundleReport.status,
    forbiddenMaterialPresent: false,
  };

  assertSmoke(summary.rendererVisibleResultContainsOnlyBundleIdentity, 'Renderer-visible support bundle result was not safe.');

  const manifest = {
    schemaVersion: 1,
    status: 'passed',
    proof: 'rd17-diagnostics-crash-recovery-support-bundle',
    platform: 'win32',
    requiredFiles: REQUIRED_RD17_SMOKE_FILES,
  };

  assertSmoke(scanFileContent(jsonContent(manifest)).length === 0, 'Top-level manifest redaction scan failed.');
  assertSmoke(scanFileContent(jsonContent(summary)).length === 0, 'Top-level summary redaction scan failed.');

  await writeJson(path.join(outRoot, 'manifest.json'), manifest);
  await writeJson(path.join(outRoot, 'summary.json'), summary);
  const topLevelReport = scanSupportBundleDirectory(outRoot, {
    timestampMs: CREATED_AT_MS,
    truncatedRecordCount: supportBundleReport.truncatedRecordCount,
    omittedFileCount: supportBundleReport.omittedFileCount,
  });
  assertSmoke(topLevelReport.status === 'passed', 'Top-level evidence redaction scan failed.');
  await writeJson(path.join(outRoot, 'redaction-report.json'), topLevelReport);
  await assertRequiredEvidenceFiles(outRoot);
}

function runBuild() {
  const result = spawnSync('npm', ['run', 'build:electron'], {
    cwd: REPO_ROOT,
    shell: process.platform === 'win32',
    stdio: 'pipe',
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    throw new Error('Electron build failed before RD-17 diagnostics smoke.');
  }
}

export function resolveEvidenceDirectory(outDirectory) {
  if (typeof outDirectory !== 'string' || outDirectory.trim().length === 0) {
    throw new Error('RD-17 smoke output must be under the RD-17 evidence root.');
  }
  const resolved = path.resolve(REPO_ROOT, outDirectory);
  const relative = path.relative(RD17_SMOKE_EVIDENCE_ROOT_ABSOLUTE, resolved);
  if (
    relative.length === 0 ||
    relative.startsWith('..') ||
    path.isAbsolute(relative)
  ) {
    throw new Error('RD-17 smoke output must be under the RD-17 evidence root.');
  }
  if (containsSymlinkComponent(resolved)) {
    throw new Error('RD-17 smoke output must be under the RD-17 evidence root.');
  }
  return resolved;
}

function containsSymlinkComponent(targetPath) {
  let current = REPO_ROOT;
  const relative = path.relative(REPO_ROOT, targetPath);
  for (const segment of relative.split(path.sep)) {
    if (segment.length === 0) {
      continue;
    }
    current = path.join(current, segment);
    try {
      if (fsSync.lstatSync(current).isSymbolicLink()) {
        return true;
      }
    } catch (error) {
      if (error?.code === 'ENOENT') {
        return false;
      }
      throw error;
    }
  }
  return false;
}

export function formatSmokeFailure(error) {
  const message = error instanceof Error ? error.message : String(error);
  if (message === 'RD-17 smoke output must be under the RD-17 evidence root.') {
    return message;
  }
  if (message === 'Electron build failed before RD-17 diagnostics smoke.') {
    return message;
  }
  if (message.startsWith('Expected ') || message.startsWith('Renderer-visible ')) {
    return message;
  }
  return 'RD-17 diagnostics smoke failed.';
}

function importDistModule(relativePath) {
  return import(pathToFileURL(path.join(DIST_ROOT, relativePath)).href);
}

function spawnHelperProcess(script) {
  return spawn(process.execPath, ['-e', script], {
    stdio: 'pipe',
    windowsHide: true,
  });
}

function createCrashHelperScript() {
  return String.raw`
process.stdin.resume();
process.stdin.once('data', () => process.exit(42));
`;
}

function createSuccessHelperScript() {
  return String.raw`
let buffer = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buffer += chunk;
  let newlineIndex = buffer.indexOf('\n');
  while (newlineIndex >= 0) {
    const line = buffer.slice(0, newlineIndex).trim();
    buffer = buffer.slice(newlineIndex + 1);
    if (line.length > 0) {
      const message = JSON.parse(line);
      if (message.type === 'command') {
        process.stdout.write(JSON.stringify({
          type: 'result',
          requestId: message.requestId,
          ok: true,
          events: [
            {
              type: 'media.loaded',
              requestId: message.requestId,
              media: message.payload.media,
              durationMs: message.payload.media.durationMs ?? null,
              tracks: [],
            },
            {
              type: 'playback.state',
              requestId: message.requestId,
              status: 'playing',
              playing: true,
            },
          ],
        }) + '\n');
      }
      if (message.type === 'cleanup') {
        setTimeout(() => process.exit(0), 5);
      }
    }
    newlineIndex = buffer.indexOf('\n');
  }
});
`;
}

function createSafePlayerSnapshot() {
  return {
    requestId: null,
    status: 'idle',
    media: null,
    capabilityProfileId: null,
    positionMs: 0,
    durationMs: null,
    bufferedRanges: [],
    playing: false,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    lastError: null,
  };
}

function createSafeEnvironmentSummary() {
  return {
    schemaVersion: 1,
    platformFamily: 'win32',
    runtime: 'electron-main-smoke',
    proofMode: 'rd17-diagnostics-smoke',
  };
}

async function assertRequiredSupportBundleFiles(bundleDirectory) {
  for (const relativePath of REQUIRED_RD17_SMOKE_FILES.filter((fileName) => fileName.startsWith('support-bundle/'))) {
    const supportRelativePath = relativePath.slice('support-bundle/'.length);
    await assertFileExists(path.join(bundleDirectory, supportRelativePath));
  }
}

async function assertRequiredEvidenceFiles(outRoot) {
  for (const relativePath of REQUIRED_RD17_SMOKE_FILES) {
    await assertFileExists(path.join(outRoot, relativePath));
  }
}

async function assertFileExists(filePath) {
  const stat = await fs.stat(filePath);
  assertSmoke(stat.isFile(), 'Expected RD-17 smoke evidence file.');
}

function rendererVisibleResultContainsOnlyBundleIdentity(result) {
  const allowedKeys = new Set([
    'status',
    'bundleId',
    'bundleDirectoryName',
    'createdAtMs',
    'fileCount',
    'byteCount',
    'includedFiles',
    'redactionReport',
  ]);
  return Object.keys(result).every((key) => allowedKeys.has(key));
}

function createClock(startMs) {
  let current = startMs;
  return () => {
    current += 1;
    return current;
  };
}

function createIdGenerator(prefix) {
  let counter = 0;
  return () => {
    counter += 1;
    return `${prefix}-${String(counter)}`;
  };
}

async function waitForChildClose(child) {
  if (hasObservedChildExit(child)) {
    return;
  }
  await new Promise((resolve) => {
    child.once('close', resolve);
  });
}

function hasObservedChildExit(child) {
  return child.exitCode !== null || child.signalCode !== null;
}

function writeJson(filePath, value) {
  return fs.writeFile(filePath, jsonContent(value), { encoding: 'utf8', mode: 0o600 });
}

function jsonContent(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function assertSmoke(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
