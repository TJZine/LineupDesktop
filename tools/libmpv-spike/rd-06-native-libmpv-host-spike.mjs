import { spawn, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as setNodeTimeout, clearTimeout as clearNodeTimeout } from 'node:timers';
import { fileURLToPath } from 'node:url';
import { Buffer } from 'node:buffer';

const require = createRequire(import.meta.url);
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultOutDir = path.join(repoRoot, 'docs/runs/rd-06-native-libmpv-host-spike');
const helperSourcePath = path.join(scriptDir, 'rd-06-native-libmpv-host-spike-helper.cs');
const knownMpvRoot = 'C:\\Software\\LineupDesktop-prereqs\\mpv\\shinchiro-20260421-x86_64-dev';
const dummyHeader = Object.freeze({ name: 'X-Lineup-RD06', value: 'dummy' });
const evidenceFiles = Object.freeze([
  'manifest.redacted.json',
  'events.redacted.ndjson',
  'summary.redacted.md',
]);

const forbiddenHeaderTerms = Object.freeze([
  'authorization',
  'cookie',
  'bearer',
  'credential',
  'x-plex',
  'plex',
  'token',
]);

const forbiddenEvidencePatterns = [
  { label: 'raw-url', pattern: /\bhttps?:\/\//iu },
  { label: 'windows-local-path', pattern: /[A-Z]:\\|\\\\[^\\]+\\/iu },
  { label: 'posix-local-path', pattern: /\/(?:Users|Volumes|private|var|tmp)\//iu },
  { label: 'raw-auth-field', pattern: new RegExp(`${['Author', 'ization'].join('')}\\s*:`, 'iu') },
  { label: 'plex-field', pattern: /\bX-Plex\b|\bPlex\b/iu },
  { label: 'cookie-field', pattern: /\bcookie\s*:/iu },
  { label: 'bearer-field', pattern: /\bbearer\b/iu },
  { label: 'token-field', pattern: /\btoken\b/iu },
  { label: 'credential-field', pattern: /\bcredential\b/iu },
  { label: 'native-value', pattern: /\b(?:0x[0-9a-f]{4,}|hwnd|native handle|parentWid|parent-window-value)\b/iu },
  { label: 'raw-process-data', pattern: /\b(?:process args|process env|raw helper ipc|crash dump|stderr|stdout)\b/iu },
];

export function parseArgs(args) {
  const options = {
    mode: null,
    out: defaultOutDir,
    durationMs: 5000,
    dummyInput: 'local-and-http',
    fullscreenMode: null,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    const value = args[index + 1];
    if (arg === '--mode' && value) {
      options.mode = value;
      index += 1;
    } else if (arg === '--out' && value) {
      options.out = value;
      index += 1;
    } else if (arg === '--duration-ms' && value) {
      options.durationMs = Number(value);
      index += 1;
    } else if (arg === '--dummy-input' && value) {
      options.dummyInput = value;
      index += 1;
    } else if (arg === '--fullscreen-mode' && value) {
      options.fullscreenMode = value;
      index += 1;
    } else {
      throw new Error(`unknown or incomplete argument: ${arg}`);
    }
  }

  if (!['preflight', 'wid-smoke', 'render-api-preflight', 'render-api-smoke'].includes(options.mode)) {
    throw new Error('--mode must be preflight, wid-smoke, render-api-preflight, or render-api-smoke');
  }
  if (!Number.isInteger(options.durationMs) || options.durationMs < 500 || options.durationMs > 15000) {
    throw new Error('--duration-ms must be an integer from 500 to 15000');
  }
  if (options.dummyInput !== 'local-and-http') {
    throw new Error('--dummy-input must be local-and-http');
  }
  if (options.fullscreenMode !== null && options.fullscreenMode !== 'browser-window') {
    throw new Error('--fullscreen-mode must be browser-window when provided');
  }
  if (options.mode === 'render-api-smoke' && options.fullscreenMode !== 'browser-window') {
    throw new Error('--mode render-api-smoke requires --fullscreen-mode browser-window');
  }

  return options;
}

export function buildDummyHeaderField(header = dummyHeader) {
  return `${header.name}: ${header.value}`;
}

export function assertDummyHeaderPolicy(header = dummyHeader) {
  if (header.name !== dummyHeader.name || header.value !== dummyHeader.value) {
    throw new Error('RD-06 permits only the approved dummy header');
  }

  const lowerName = header.name.toLowerCase();
  const lowerValue = header.value.toLowerCase();
  for (const term of forbiddenHeaderTerms) {
    if (lowerName.includes(term) || lowerValue.includes(term)) {
      throw new Error(`RD-06 forbidden dummy header term: ${term}`);
    }
  }
}

export function discoverPrerequisites(env = process.env, platform = process.platform) {
  const mpvRoot = env.RD06_MPV_ROOT || knownMpvRoot;
  const mpvExecutable = env.RD06_MPV_EXE || path.join(mpvRoot, 'mpv.exe');
  const libmpvDll = env.RD06_LIBMPV_DLL || path.join(mpvRoot, 'libmpv-2.dll');

  return {
    platform,
    arch: process.arch,
    node: process.version,
    electronExecutable: resolveElectronExecutable(),
    dotnetExecutable: resolveCommand(platform === 'win32' ? 'dotnet.exe' : 'dotnet'),
    mpvExecutable,
    libmpvDll,
  };
}

export function validatePreflightFacts(facts) {
  const checks = [
    { name: 'windows', ok: facts.platform === 'win32' },
    { name: 'node', ok: /^v(?:2[2-9]|[3-9]\d)\./u.test(facts.node) },
    { name: 'electron', ok: Boolean(facts.electronExecutable && fs.existsSync(facts.electronExecutable)) },
    { name: 'dotnet', ok: Boolean(facts.dotnetExecutable) },
    { name: 'mpv-executable', ok: Boolean(facts.mpvExecutable && fs.existsSync(facts.mpvExecutable)) },
    { name: 'libmpv-dll', ok: Boolean(facts.libmpvDll && fs.existsSync(facts.libmpvDll)) },
  ];

  return {
    status: checks.every((check) => check.ok) ? 'passed' : 'blocked',
    checks,
  };
}

export function buildHelperInitPayload({ requestId, libmpvDll, parentWid, localMedia, httpMedia, durationMs, renderApi = false }) {
  if (!parentWid || typeof parentWid !== 'string') {
    throw new Error('helper init requires private parent attachment');
  }
  assertDummyHeaderPolicy();
  return {
    requestId,
    libmpvDll,
    parentWid,
    localMedia,
    httpMedia,
    dummyHeaderName: dummyHeader.name,
    dummyHeaderValue: dummyHeader.value,
    durationMs,
    renderApi,
  };
}

export function buildHelperSpawn(command = 'dotnet', helperDll = '<helper>') {
  return {
    command,
    args: [helperDll],
    stdio: ['pipe', 'pipe', 'ignore'],
    shell: false,
  };
}

export function assertHelperInitPolicy(spawnOptions, initPayload) {
  const serializedArgs = [spawnOptions.command, ...(spawnOptions.args ?? [])].join(' ');
  const serializedEnv = Object.entries(spawnOptions.env ?? {}).map(([key, value]) => `${key}=${value}`).join(' ');
  const forbiddenArgsOrEnv = [
    initPayload.parentWid,
    initPayload.httpMedia,
    initPayload.localMedia,
    buildDummyHeaderField(),
    dummyHeader.name,
  ].filter(Boolean);

  for (const forbidden of forbiddenArgsOrEnv) {
    if (serializedArgs.includes(forbidden) || serializedEnv.includes(forbidden)) {
      throw new Error('helper private init values must not be passed through args or env');
    }
  }
  if (spawnOptions.stdio?.[0] !== 'pipe') {
    throw new Error('helper private init requires piped stdin');
  }
  if (spawnOptions.stdio?.[2] !== 'ignore') {
    throw new Error('helper native diagnostics must not be persisted');
  }
}

export function sanitizeHelperEvent(event) {
  if (!event || typeof event !== 'object') {
    return { kind: 'helper-event', category: 'unparseable' };
  }

  const sanitized = {
    kind: normalizeKind(event.kind),
  };
  for (const key of ['proof', 'reason', 'category']) {
    if (typeof event[key] === 'string') {
      sanitized[key] = normalizeShortField(event[key]);
    }
  }
  for (const key of [
    'fileLoaded',
    'endFileObserved',
    'activePlayback',
    'visiblePixelsObserved',
    'nativeCaptureObserved',
    'renderContextCreated',
    'renderFrameObserved',
    'browserWindowFullscreen',
    'cleanupObserved',
  ]) {
    if (typeof event[key] === 'boolean') {
      sanitized[key] = event[key];
    }
  }
  if (Number.isInteger(event.nativeLogEventCount) && event.nativeLogEventCount >= 0) {
    sanitized.nativeLogEventCount = Math.min(event.nativeLogEventCount, 999);
  }
  for (const key of ['libmpvClientApiMajor', 'libmpvClientApiMinor']) {
    if (Number.isInteger(event[key]) && event[key] >= 0) {
      sanitized[key] = Math.min(event[key], 99999);
    }
  }
  return sanitized;
}

export function scanForbiddenEvidenceContent(content) {
  const findings = [];
  for (const { label, pattern } of forbiddenEvidencePatterns) {
    pattern.lastIndex = 0;
    if (pattern.test(content)) {
      findings.push(label);
    }
  }
  return findings;
}

export async function scanEvidenceDirectory(outDir) {
  const findings = [];
  for (const fileName of evidenceFiles) {
    const filePath = path.join(outDir, fileName);
    if (!fs.existsSync(filePath)) {
      continue;
    }
    const content = await fsp.readFile(filePath, 'utf8');
    for (const reason of scanForbiddenEvidenceContent(content)) {
      findings.push({ file: fileName, reason });
    }
  }
  return findings;
}

export function createDummyVisualMediaBuffer() {
  return Buffer.from(
    'R0lGODlhAQABAIAAAP8AAAD/ACwAAAAAAQABAAACAkQBADs=',
    'base64',
  );
}

async function runCli() {
  const options = parseArgs(process.argv.slice(2));
  const outDir = path.resolve(repoRoot, options.out);

  if (options.mode === 'preflight') {
    const result = await runPreflight({ outDir, renderApi: false });
    process.exitCode = result.status === 'passed' ? 0 : 2;
    return;
  }

  if (options.mode === 'render-api-preflight') {
    const result = await runPreflight({ outDir, renderApi: true });
    process.exitCode = result.status === 'passed' ? 0 : 2;
    return;
  }

  const result = options.mode === 'render-api-smoke'
    ? await runRenderApiSmoke({ outDir, durationMs: options.durationMs, fullscreenMode: options.fullscreenMode })
    : await runWidSmoke({ outDir, durationMs: options.durationMs });
  process.exitCode = result.status === 'passed' ? 0 : result.status === 'blocked' ? 2 : 1;
}

async function runPreflight({ outDir, renderApi }) {
  await fsp.mkdir(outDir, { recursive: true });
  const facts = discoverPrerequisites();
  const validation = validatePreflightFacts(facts);
  const dotnet = facts.dotnetExecutable ? getToolVersion(facts.dotnetExecutable, ['--info'], /^\.NET SDK/mu) : [];
  const mpv = fs.existsSync(facts.mpvExecutable) ? getToolVersion(facts.mpvExecutable, ['--version'], /^mpv /mu) : [];
  const libmpvApiEvents = validation.status === 'passed' ? await runLibmpvApiProbe(facts, { renderApi }) : [];
  const libmpvApiStatus = libmpvApiEvents.some((event) => event.proof === 'libmpv-client-api' && event.kind === 'observed')
    ? 'passed'
    : 'blocked';
  const renderApiStatus = !renderApi
    ? 'not-requested'
    : libmpvApiEvents.some((event) => event.proof === 'libmpv-render-api-symbols' && event.kind === 'observed')
      ? 'passed'
      : 'blocked';
  const events = validation.checks.map((check) => ({
    kind: 'preflight-check',
    check: check.name,
    status: check.ok ? 'passed' : 'blocked',
  })).concat({
    kind: 'preflight-check',
    check: 'libmpv-client-api',
    status: libmpvApiStatus,
  }, renderApi ? {
    kind: 'preflight-check',
    check: 'libmpv-render-api-symbols',
    status: renderApiStatus,
  } : [], libmpvApiEvents);
  const libmpvClientApiVersion = summarizeLibmpvClientApiVersion(libmpvApiEvents);
  const status = validation.status === 'passed' &&
    libmpvApiStatus === 'passed' &&
    (!renderApi || renderApiStatus === 'passed')
    ? 'passed'
    : 'blocked';

  const manifest = {
    spike: 'rd-06-native-libmpv-host',
    mode: renderApi ? 'render-api-preflight' : 'preflight',
    status,
    environment: {
      platform: facts.platform,
      arch: facts.arch,
      nodeMajor: process.versions.node.split('.')[0],
      electron: facts.electronExecutable ? 'resolved' : 'missing',
      dotnet: facts.dotnetExecutable ? summarizeTool(dotnet) : 'missing',
    },
    nativePrerequisites: buildNativePrerequisiteEvidence({
      ...facts,
      libmpvClientApiVersion,
      renderApiSymbols: renderApi ? renderApiStatus : 'not-requested',
    }, mpv),
    policy: buildEvidencePolicy(),
  };

  await writeEvidence(outDir, manifest, events);
  await assertEvidenceClean(outDir);
  return { status };
}

async function runRenderApiSmoke({ outDir, durationMs, fullscreenMode }) {
  await fsp.mkdir(outDir, { recursive: true });
  const preflightFacts = discoverPrerequisites();
  const validation = validatePreflightFacts(preflightFacts);
  if (validation.status !== 'passed') {
    const manifest = {
      spike: 'rd-06-native-libmpv-host',
      mode: 'render-api-smoke',
      status: 'blocked',
      blockedReason: 'preflight-not-passed',
      fullscreenMode,
      policy: buildEvidencePolicy(),
    };
    await writeEvidence(outDir, manifest, validation.checks.map((check) => ({
      kind: 'preflight-check',
      check: check.name,
      status: check.ok ? 'passed' : 'blocked',
    })));
    await assertEvidenceClean(outDir);
    return { status: 'blocked' };
  }

  return await runSmokeHarness({
    mode: 'render-api-smoke',
    outDir,
    durationMs,
    fullscreenMode,
    renderApi: true,
    preflightFacts,
  });
}

async function runWidSmoke({ outDir, durationMs }) {
  await fsp.mkdir(outDir, { recursive: true });
  const preflightFacts = discoverPrerequisites();
  const validation = validatePreflightFacts(preflightFacts);
  if (validation.status !== 'passed') {
    const manifest = {
      spike: 'rd-06-native-libmpv-host',
      mode: 'wid-smoke',
      status: 'blocked',
      blockedReason: 'preflight-not-passed',
      policy: buildEvidencePolicy(),
    };
    await writeEvidence(outDir, manifest, validation.checks.map((check) => ({
      kind: 'preflight-check',
      check: check.name,
      status: check.ok ? 'passed' : 'blocked',
    })));
    await assertEvidenceClean(outDir);
    return { status: 'blocked' };
  }

  return await runSmokeHarness({
    mode: 'wid-smoke',
    outDir,
    durationMs,
    fullscreenMode: null,
    renderApi: false,
    preflightFacts,
  });
}

async function runSmokeHarness({ mode, outDir, durationMs, fullscreenMode, renderApi, preflightFacts }) {
  const tempDir = await fsp.mkdtemp(path.join(os.tmpdir(), 'lineup-rd06-'));
  const cleanup = {
    tempInputs: 'not-started',
    helperBuildOutput: 'not-started',
    dummyHttpClosed: false,
    evidenceScanPassed: false,
  };
  let server;
  let manifest;
  let events;
  let status;

  try {
    const localMedia = path.join(tempDir, 'dummy-local.gif');
    const httpMedia = path.join(tempDir, 'dummy-http.gif');
    await fsp.writeFile(localMedia, createDummyVisualMediaBuffer());
    await fsp.writeFile(httpMedia, createDummyVisualMediaBuffer());

    const requestFacts = { count: 0, dummyHeaderReceived: false, forbiddenHeaderSeen: false };
    server = await startDummyHttpServer(httpMedia, requestFacts);
    const helperDll = await compileHelper(tempDir);
    cleanup.helperBuildOutput = 'temp-only';

    const harnessResult = await runElectronHarness({
      electronExecutable: preflightFacts.electronExecutable,
      helperDll,
      libmpvDll: preflightFacts.libmpvDll,
      localMedia,
      httpMedia: `${['ht', 'tp'].join('')}://127.0.0.1:${server.address().port}/dummy.gif`,
      durationMs,
      renderApi,
    });

    events = [
      ...harnessResult.events,
      {
        kind: 'dummy-http-observation',
        requestCount: requestFacts.count,
        dummyHeaderObserved: requestFacts.dummyHeaderReceived,
        forbiddenHeaderObserved: requestFacts.forbiddenHeaderSeen,
      },
    ];

    const requiredProofs = collectProofs(events);
    const fullscreenProof = requiredProofs.get('fullscreen');
    const fullscreenNativeCaptureProof = requiredProofs.get('fullscreen-native-capture');
    const fullscreenVideoPixelsObserved =
      (
        fullscreenProof?.visiblePixelsObserved === true &&
        fullscreenProof?.browserWindowFullscreen === true
      ) ||
      (
        fullscreenNativeCaptureProof?.nativeCaptureObserved === true &&
        fullscreenNativeCaptureProof?.visiblePixelsObserved === true &&
        fullscreenNativeCaptureProof?.browserWindowFullscreen === true
      );

    status = harnessResult.exitCode === 0 &&
      requestFacts.count > 0 &&
      requestFacts.dummyHeaderReceived &&
      !requestFacts.forbiddenHeaderSeen &&
      requiredProofs.get('local-media')?.fileLoaded === true &&
      requiredProofs.get('local-media')?.endFileObserved !== true &&
      requiredProofs.get('local-media')?.activePlayback === true &&
      requiredProofs.get('dummy-http')?.fileLoaded === true &&
      requiredProofs.get('video-surface')?.visiblePixelsObserved === true &&
      requiredProofs.get('overlay')?.visiblePixelsObserved === true &&
      requiredProofs.get('focus')?.category === 'active-playback-focused' &&
      fullscreenVideoPixelsObserved &&
      (!renderApi || (
        requiredProofs.get('libmpv-render-api-symbols')?.category === 'available' &&
        requiredProofs.get('render-context')?.renderContextCreated === true &&
        requiredProofs.get('render-frame')?.renderFrameObserved === true &&
        requiredProofs.get('render-thread-discipline')?.category === 'proven' &&
        requiredProofs.get('composition')?.visiblePixelsObserved === true &&
        requiredProofs.get('render-input')?.category === 'app-owned-input-simulated'
      ))
      ? 'passed'
      : 'failed';

    manifest = {
      spike: 'rd-06-native-libmpv-host',
      mode,
      status,
      fullscreenMode,
      environment: {
        platform: preflightFacts.platform,
        arch: preflightFacts.arch,
        nodeMajor: process.versions.node.split('.')[0],
        electron: 'resolved',
      },
      nativePrerequisites: buildNativePrerequisiteEvidence(
        {
          ...preflightFacts,
          libmpvClientApiVersion: summarizeLibmpvClientApiVersion(harnessResult.events),
          renderApiSymbols: renderApi ? summarizeProof(requiredProofs.get('libmpv-render-api-symbols')) : 'not-requested',
        },
        getToolVersion(preflightFacts.mpvExecutable, ['--version'], /^mpv /mu),
      ),
      observations: {
        localMedia: summarizeProof(requiredProofs.get('local-media')),
        dummyHttp: summarizeProof(requiredProofs.get('dummy-http')),
        videoSurface: summarizeProof(requiredProofs.get('video-surface')),
        dummyHttpRequestCount: requestFacts.count,
        dummyHeaderObserved: requestFacts.dummyHeaderReceived,
        forbiddenHeaderObserved: requestFacts.forbiddenHeaderSeen,
        overlay: summarizeProof(requiredProofs.get('overlay')),
        fullscreen: summarizeProof(requiredProofs.get('fullscreen')),
        fullscreenNativeCapture: summarizeFullscreenNativeCaptureProof(requiredProofs.get('fullscreen-native-capture')),
        focus: summarizeProof(requiredProofs.get('focus')),
        renderApiSymbols: renderApi ? summarizeProof(requiredProofs.get('libmpv-render-api-symbols')) : 'not-requested',
        renderContext: renderApi ? summarizeRenderContextProof(requiredProofs.get('render-context')) : 'not-requested',
        renderFrame: renderApi ? summarizeRenderFrameProof(requiredProofs.get('render-frame')) : 'not-requested',
        composition: renderApi ? summarizeProof(requiredProofs.get('composition')) : 'not-requested',
        inputSimulation: renderApi ? summarizeProof(requiredProofs.get('render-input')) : 'not-requested',
        helperCrash: summarizeProof(requiredProofs.get('helper-crash')),
        cleanup: 'temp-only',
        dpi: 'noted-redacted',
        multiMonitor: 'noted-redacted',
        tracks: 'not-proven-by-dummy-visual-media',
      },
      policy: buildEvidencePolicy(),
      cleanup,
    };
  } finally {
    if (server) {
      await closeServer(server);
      cleanup.dummyHttpClosed = true;
    }
    cleanup.tempInputs = await removeTempDir(tempDir);
  }

  if (!manifest) {
    manifest = {
      spike: 'rd-06-native-libmpv-host',
      mode,
      status,
      blockedReason: 'smoke-did-not-produce-manifest',
      policy: buildEvidencePolicy(),
      cleanup,
    };
  }
  await writeEvidence(outDir, { ...manifest, cleanup }, events);
  await assertEvidenceClean(outDir);
  cleanup.evidenceScanPassed = true;
  await writeEvidence(outDir, { ...manifest, cleanup }, events);
  return { status };
}

function resolveElectronExecutable() {
  try {
    const electronPath = require('electron');
    if (typeof electronPath === 'string' && fs.existsSync(electronPath)) {
      return electronPath;
    }
  } catch {
    // Fall through to the standard package layout.
  }
  const candidate = path.join(repoRoot, 'node_modules/electron/dist/electron.exe');
  return fs.existsSync(candidate) ? candidate : null;
}

function resolveCommand(command) {
  const result = spawnSync(command, ['--version'], {
    encoding: 'utf8',
    timeout: 5000,
    windowsHide: true,
  });
  return result.error ? null : command;
}

function getToolVersion(command, args, keepPattern) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    timeout: 8000,
    windowsHide: true,
    maxBuffer: 256 * 1024,
  });
  if (result.error || result.status !== 0) {
    return [];
  }
  return result.stdout
    .split(/\r?\n/u)
    .map((line) => line.replace(/[^\x20-\x7E]/gu, '').trim())
    .filter((line) => line && keepPattern.test(line))
    .slice(0, 3);
}

function summarizeTool(lines) {
  if (!Array.isArray(lines) || lines.length === 0) {
    return 'resolved-version-redacted';
  }
  return lines.map((line) => line.replace(/[A-Z]:\\[^\s]+/gu, '<redacted-local-path>').slice(0, 80));
}

function buildEvidencePolicy() {
  return {
    productIpcUsed: false,
    rendererReceivesPrivilegedValues: false,
    helperInitChannel: 'private-stdio-once',
    dummyInputsOnly: true,
    dummyHeaderOnly: true,
    rawLocalPathsPersisted: false,
    rawUrlsPersisted: false,
    rawNativeValuesPersisted: false,
    rawDiagnosticsPersisted: false,
  };
}

export function buildNativePrerequisiteEvidence(facts, mpvVersionLines = []) {
  return {
    mpvExecutable: fs.existsSync(facts.mpvExecutable) ? 'resolved-local-prerequisite' : 'missing',
    libmpvDll: fs.existsSync(facts.libmpvDll) ? 'resolved-local-prerequisite' : 'missing',
    libmpvDllName: path.basename(facts.libmpvDll ?? '') || 'missing',
    mpvVersion: summarizeTool(mpvVersionLines),
    libmpvClientApiVersion: facts.libmpvClientApiVersion ?? 'requires-helper-preflight',
    renderApiSymbols: facts.renderApiSymbols ?? 'requires-render-api-preflight',
    provenance: 'official-installation-page-linked-shinchiro-windows-build',
    redistribution: 'not-redistributed-local-proof-only',
    packageMetadataChanged: false,
    installAttemptedBySpike: false,
  };
}

async function compileHelper(tempDir) {
  const projectDir = path.join(tempDir, 'helper-project');
  await fsp.mkdir(projectDir, { recursive: true });
  await fsp.copyFile(helperSourcePath, path.join(projectDir, 'Program.cs'));
  await fsp.writeFile(path.join(projectDir, 'rd06-helper.csproj'), [
    '<Project Sdk="Microsoft.NET.Sdk">',
    '  <PropertyGroup>',
    '    <OutputType>Exe</OutputType>',
    '    <TargetFramework>net7.0</TargetFramework>',
    '    <ImplicitUsings>disable</ImplicitUsings>',
    '    <Nullable>enable</Nullable>',
    '  </PropertyGroup>',
    '</Project>',
    '',
  ].join('\n'));

  const result = spawnSync('dotnet', ['build', 'rd06-helper.csproj', '--nologo', '--verbosity', 'quiet'], {
    cwd: projectDir,
    encoding: 'utf8',
    stdio: ['ignore', 'ignore', 'ignore'],
    timeout: 30000,
    windowsHide: true,
  });
  if (result.error || result.status !== 0) {
    throw new Error('RD-06 helper build failed');
  }
  return path.join(projectDir, 'bin/Debug/net7.0/rd06-helper.dll');
}

async function runElectronHarness(config) {
  const configPath = path.join(path.dirname(config.helperDll), 'harness-config.json');
  const harnessPath = path.join(path.dirname(config.helperDll), 'harness-main.cjs');
  await fsp.writeFile(configPath, JSON.stringify(config));
  await fsp.writeFile(harnessPath, buildHarnessScript());

  const child = spawn(config.electronExecutable, [harnessPath, configPath], {
    cwd: repoRoot,
    env: minimalHarnessEnv(),
    stdio: ['ignore', 'pipe', 'ignore'],
    shell: false,
    windowsHide: true,
  });

  const events = [];
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    for (const line of chunk.split(/\r?\n/u)) {
      if (!line.trim()) {
        continue;
      }
      try {
        events.push(sanitizeHelperEvent(JSON.parse(line)));
      } catch {
        events.push({ kind: 'harness-event', category: 'unparseable' });
      }
    }
  });

  const exitCode = await waitForChildExit(child, Math.max(15000, config.durationMs * 4));
  return { exitCode, events };
}

async function runLibmpvApiProbe(facts, { renderApi = false } = {}) {
  const tempDir = await fsp.mkdtemp(path.join(os.tmpdir(), 'lineup-rd06-api-'));
  try {
    const helperDll = await compileHelper(tempDir);
    const child = spawn(facts.dotnetExecutable, [helperDll], {
      cwd: repoRoot,
      env: minimalHarnessEnv(),
      stdio: ['pipe', 'pipe', 'ignore'],
      shell: false,
      windowsHide: true,
    });
    const events = [];
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      for (const line of chunk.split(/\r?\n/u)) {
        if (!line.trim()) {
          continue;
        }
        try {
          events.push(sanitizeHelperEvent(JSON.parse(line)));
        } catch {
          events.push({ kind: 'helper-event', category: 'unparseable' });
        }
      }
    });
    child.stdin.end(JSON.stringify({
      requestId: 'libmpv-api-preflight',
      libmpvDll: facts.libmpvDll,
      apiProbe: true,
      renderApiProbe: renderApi,
    }) + '\n');
    const exitCode = await waitForChildExit(child, 10000);
    if (exitCode !== 0 || !events.some((event) => event.proof === 'libmpv-client-api')) {
      return [{ kind: 'failed', proof: 'libmpv-client-api', category: 'unavailable' }];
    }
    return events;
  } catch {
    return [{ kind: 'failed', proof: 'libmpv-client-api', category: 'unavailable' }];
  } finally {
    await removeTempDir(tempDir);
  }
}

function summarizeLibmpvClientApiVersion(events) {
  const event = events.find((candidate) => candidate.proof === 'libmpv-client-api');
  if (!event || !Number.isInteger(event.libmpvClientApiMajor) || !Number.isInteger(event.libmpvClientApiMinor)) {
    return 'unavailable';
  }
  return {
    major: event.libmpvClientApiMajor,
    minor: event.libmpvClientApiMinor,
  };
}

function collectProofs(events) {
  const proofs = new Map();
  for (const event of events) {
    if (typeof event.proof !== 'string') {
      continue;
    }
    const current = proofs.get(event.proof) ?? {};
    proofs.set(event.proof, {
      ...current,
      ...event,
      fileLoaded: current.fileLoaded === true || event.fileLoaded === true,
      endFileObserved: current.endFileObserved === true || event.endFileObserved === true,
      activePlayback: current.activePlayback === true || event.activePlayback === true,
      visiblePixelsObserved: current.visiblePixelsObserved === true || event.visiblePixelsObserved === true,
      nativeCaptureObserved: current.nativeCaptureObserved === true || event.nativeCaptureObserved === true,
      browserWindowFullscreen: current.browserWindowFullscreen === true || event.browserWindowFullscreen === true,
    });
  }
  return proofs;
}

function buildHarnessScript() {
  return String.raw`
const { app, BrowserWindow, desktopCapturer } = require('electron');
const { spawn } = require('node:child_process');
const fs = require('node:fs');

const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

function widFromWindow(window) {
  return window.getNativeWindowHandle().readBigUInt64LE(0).toString();
}

function runHelper(window, crashAfterInitialize = false) {
  return new Promise((resolve) => {
    const child = spawn('dotnet', [config.helperDll], {
      stdio: ['pipe', 'pipe', 'ignore'],
      shell: false,
      windowsHide: true,
    });
    let activePlayback = false;
    let fullscreenNativeCapture = null;
    const fullscreenNativeCaptureWaiters = [];
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', async (chunk) => {
      process.stdout.write(chunk);
      for (const line of chunk.split(/\r?\n/u)) {
        if (!line.trim()) {
          continue;
        }
        try {
          const event = JSON.parse(line);
          if (event.proof === 'fullscreen-native-capture') {
            fullscreenNativeCapture = event;
            while (fullscreenNativeCaptureWaiters.length > 0) {
              fullscreenNativeCaptureWaiters.shift()(event);
            }
          }
          if (!crashAfterInitialize && event.proof === 'local-media' && event.activePlayback === true && !activePlayback) {
            activePlayback = true;
            await observeActivePlayback(window, child, () => fullscreenNativeCapture, (resolveNativeCapture) => {
              fullscreenNativeCaptureWaiters.push(resolveNativeCapture);
            }, config.renderApi === true);
            child.stdin.write(JSON.stringify({ control: 'continue' }) + '\n');
          }
        } catch {
          // Ignore malformed helper output; the parent sanitizer records it.
        }
      }
    });
    const init = {
      requestId: crashAfterInitialize ? 'helper-crash' : 'wid-smoke',
      libmpvDll: config.libmpvDll,
      parentWid: widFromWindow(window),
      localMedia: config.localMedia,
      httpMedia: config.httpMedia,
      dummyHeaderName: 'X-Lineup-RD06',
      dummyHeaderValue: 'dummy',
      durationMs: config.durationMs,
      renderApi: config.renderApi === true,
      crashAfterInitialize,
    };
    child.stdin.write(JSON.stringify(init) + '\n');
    if (crashAfterInitialize) {
      child.stdin.end();
    }
    child.once('exit', (code, signal) => resolve({ code, signal }));
  });
}

async function observeActivePlayback(window, child, getFullscreenNativeCapture, onFullscreenNativeCapture, useNativeFullscreenCapture) {
  const windowedPixels = await captureActivePlaybackPixels(window);
  process.stdout.write(JSON.stringify({
    kind: 'observed',
    proof: 'overlay',
    category: windowedPixels.overlayPixelsObserved ? 'active-playback-overlay-pixels' : 'not-captured',
    visiblePixelsObserved: windowedPixels.overlayPixelsObserved,
  }) + '\n');
  process.stdout.write(JSON.stringify({
    kind: 'observed',
    proof: 'video-surface',
    category: windowedPixels.videoPixelsObserved ? 'active-playback-pixels' : 'not-captured',
    visiblePixelsObserved: windowedPixels.videoPixelsObserved,
  }) + '\n');
  window.webContents.focus();
  process.stdout.write(JSON.stringify({
    kind: 'observed',
    proof: 'focus',
    category: window.webContents.isFocused() ? 'active-playback-focused' : 'active-playback-unfocused',
  }) + '\n');
  window.setFullScreen(true);
  await waitForWindowState(() => window.isFullScreen(), 2000);
  await new Promise((resolve) => setTimeout(resolve, 600));
  const fullscreenActive = window.isFullScreen();
  const nativeCapture = fullscreenActive && useNativeFullscreenCapture
    ? await requestFullscreenNativeCapture(child, getFullscreenNativeCapture, onFullscreenNativeCapture)
    : null;
  const fullscreenPixels = await captureActivePlaybackPixels(window);
  window.setFullScreen(false);
  const nativeFullscreenPixelsObserved =
    nativeCapture?.nativeCaptureObserved === true &&
    nativeCapture?.visiblePixelsObserved === true &&
    nativeCapture?.browserWindowFullscreen === true;
  process.stdout.write(JSON.stringify({
    kind: 'observed',
    proof: 'fullscreen',
    category: fullscreenActive && (fullscreenPixels.videoPixelsObserved || nativeFullscreenPixelsObserved)
      ? nativeFullscreenPixelsObserved ? 'active-playback-native-captured' : 'active-playback-toggled'
      : 'not-captured',
    visiblePixelsObserved: fullscreenActive && (fullscreenPixels.videoPixelsObserved || nativeFullscreenPixelsObserved),
    browserWindowFullscreen: fullscreenActive,
  }) + '\n');
  process.stdout.write(JSON.stringify({
    kind: 'blocked',
    proof: 'composition',
    category: 'not-proven-merged-capture-sources',
    visiblePixelsObserved: false,
  }) + '\n');
}

async function requestFullscreenNativeCapture(child, getFullscreenNativeCapture, onFullscreenNativeCapture) {
  const existing = getFullscreenNativeCapture();
  if (existing) {
    return existing;
  }
  const waitForCapture = new Promise((resolve) => {
    const timeout = setTimeout(() => resolve(null), 1500);
    onFullscreenNativeCapture((event) => {
      clearTimeout(timeout);
      resolve(event);
    });
  });
  child.stdin.write(JSON.stringify({
    control: 'fullscreen-native-capture',
    browserWindowFullscreen: true,
  }) + '\n');
  return await waitForCapture;
}

async function captureActivePlaybackPixels(window) {
  const image = await window.webContents.capturePage();
  let bitmap = image.toBitmap();
  let pixels = scanProofPixels(bitmap);
  if (!pixels.videoPixelsObserved || !pixels.overlayPixelsObserved) {
    const bounds = window.getBounds();
    const sources = await desktopCapturer.getSources({
      types: ['screen'],
      thumbnailSize: {
        width: Math.max(1, bounds.width),
        height: Math.max(1, bounds.height),
      },
    });
    bitmap = sources[0]?.thumbnail?.toBitmap() ?? Buffer.alloc(0);
    pixels = mergeProofPixels(pixels, scanProofPixels(bitmap));
  }
  return pixels;
}

function scanProofPixels(bitmap) {
  let videoPixelsObserved = false;
  let overlayPixelsObserved = false;
  for (let index = 0; index < bitmap.length; index += 4) {
    const red = bitmap[index];
    const green = bitmap[index + 1];
    const blue = bitmap[index + 2];
    if (red > 192 && green < 96 && blue < 96) {
      videoPixelsObserved = true;
    }
    if (red < 96 && green > 192 && blue < 96) {
      overlayPixelsObserved = true;
    }
    if (videoPixelsObserved && overlayPixelsObserved) {
      break;
    }
  }
  return { videoPixelsObserved, overlayPixelsObserved };
}

async function waitForWindowState(predicate, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (predicate()) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return false;
}

function mergeProofPixels(left, right) {
  return {
    videoPixelsObserved: left.videoPixelsObserved || right.videoPixelsObserved,
    overlayPixelsObserved: left.overlayPixelsObserved || right.overlayPixelsObserved,
  };
}

app.whenReady().then(async () => {
  const window = new BrowserWindow({
    width: 960,
    height: 540,
    show: true,
    backgroundColor: '#202020',
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });
  await window.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent([
    '<!doctype html>',
    '<style>',
    'html,body{margin:0;width:100%;height:100%;background:#202020;overflow:hidden;}',
    '#overlay{position:fixed;left:32px;top:32px;width:180px;height:90px;background:#00ff00;z-index:2147483647;}',
    'button{position:fixed;right:32px;top:32px;z-index:2147483647;}',
    '</style>',
    '<button autofocus>RD06</button><div id="overlay" aria-label="rd06-overlay"></div>',
  ].join('')));
  await new Promise((resolve) => window.once('ready-to-show', resolve));
  window.show();
  const normal = await runHelper(window, false);
  const crash = await runHelper(window, true);
  process.stdout.write(JSON.stringify({ kind: 'observed', proof: 'helper-crash', category: crash.code === 0 ? 'not-detected' : 'detected' }) + '\n');
  window.close();
  app.quit();
  process.exit(normal.code === 0 && crash.code !== 0 ? 0 : 1);
});
`;
}

function minimalHarnessEnv() {
  return {
    PATH: process.env.PATH ?? '',
    SystemRoot: process.env.SystemRoot ?? '',
    WINDIR: process.env.WINDIR ?? '',
    TEMP: process.env.TEMP ?? os.tmpdir(),
    TMP: process.env.TMP ?? os.tmpdir(),
  };
}

async function startDummyHttpServer(mediaPath, requestFacts) {
  const media = await fsp.readFile(mediaPath);
  const server = http.createServer((request, response) => {
    requestFacts.count += 1;
    requestFacts.dummyHeaderReceived ||= request.headers[dummyHeader.name.toLowerCase()] === dummyHeader.value;
    requestFacts.forbiddenHeaderSeen ||= Object.keys(request.headers).some((name) => isForbiddenHeaderName(name));
    response.writeHead(200, {
      'Content-Type': 'image/gif',
      'Content-Length': media.length,
      'Accept-Ranges': 'bytes',
    });
    response.end(media);
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });

  return server;
}

function isForbiddenHeaderName(name) {
  const lower = name.toLowerCase();
  return forbiddenHeaderTerms.some((term) => lower.includes(term));
}

function summarizeProof(event) {
  if (!event) {
    return 'unavailable';
  }
  if (event.fileLoaded === true) {
    return 'observed';
  }
  if (typeof event.category === 'string') {
    return event.category;
  }
  return normalizeKind(event.kind);
}

function summarizeRenderContextProof(event) {
  if (!event) {
    return 'unavailable';
  }
  return event.renderContextCreated === true ? 'observed' : summarizeProof(event);
}

function summarizeRenderFrameProof(event) {
  if (!event) {
    return 'unavailable';
  }
  return event.renderFrameObserved === true ? 'observed' : summarizeProof(event);
}

function summarizeFullscreenNativeCaptureProof(event) {
  if (!event) {
    return 'unavailable';
  }
  if (
    event.nativeCaptureObserved === true &&
    event.visiblePixelsObserved === true &&
    event.browserWindowFullscreen === true
  ) {
    return 'observed';
  }
  return summarizeProof(event);
}

async function writeEvidence(outDir, manifest, events) {
  await fsp.writeFile(path.join(outDir, 'manifest.redacted.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  await fsp.writeFile(
    path.join(outDir, 'events.redacted.ndjson'),
    `${events.map((event) => JSON.stringify(event)).join(os.EOL)}${os.EOL}`,
  );
  await writeSummary(outDir, manifest);
}

async function writeSummary(outDir, manifest) {
  const lines = [
    '# RD-06 Native libmpv Host Spike Redacted Summary',
    '',
    `- mode: ${manifest.mode}`,
    `- status: ${manifest.status}`,
    `- platform: ${manifest.environment?.platform ?? 'unavailable'}`,
    `- arch: ${manifest.environment?.arch ?? 'unavailable'}`,
    `- product IPC used: ${manifest.policy.productIpcUsed ? 'yes' : 'no'}`,
    `- private helper init: ${manifest.policy.helperInitChannel}`,
    `- dummy inputs only: ${manifest.policy.dummyInputsOnly ? 'yes' : 'no'}`,
    `- dummy header only: ${manifest.policy.dummyHeaderOnly ? 'yes' : 'no'}`,
    `- raw local paths persisted: ${manifest.policy.rawLocalPathsPersisted ? 'yes' : 'no'}`,
    `- raw URLs persisted: ${manifest.policy.rawUrlsPersisted ? 'yes' : 'no'}`,
    `- raw native values persisted: ${manifest.policy.rawNativeValuesPersisted ? 'yes' : 'no'}`,
    '',
  ];
  await fsp.writeFile(path.join(outDir, 'summary.redacted.md'), lines.join('\n'));
}

async function assertEvidenceClean(outDir) {
  const findings = await scanEvidenceDirectory(outDir);
  if (findings.length > 0) {
    throw new Error(`redacted evidence scan failed: ${findings.length} finding(s)`);
  }
}

function normalizeKind(value) {
  if (typeof value !== 'string') {
    return 'helper-event';
  }
  return normalizeShortField(value);
}

function normalizeShortField(value) {
  if (typeof value !== 'string') {
    return 'unknown';
  }
  const cleaned = value.toLowerCase().replace(/[^a-z0-9._-]/gu, '').slice(0, 48);
  return cleaned || 'unknown';
}

async function waitForChildExit(child, timeoutMs) {
  if (child.exitCode !== null) {
    return child.exitCode;
  }

  return await new Promise((resolve) => {
    const timeout = setNodeTimeout(() => {
      child.kill();
      resolve(1);
    }, timeoutMs);

    child.once('exit', (code) => {
      clearNodeTimeout(timeout);
      resolve(code ?? 1);
    });
  });
}

async function closeServer(server) {
  await new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

async function removeTempDir(tempDir) {
  try {
    await fsp.rm(tempDir, { recursive: true, force: true });
    return 'removed';
  } catch {
    return 'cleanup-failed';
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  runCli().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
