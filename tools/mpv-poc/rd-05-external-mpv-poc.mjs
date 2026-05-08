import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import http from 'node:http';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as setNodeTimeout, clearTimeout as clearNodeTimeout } from 'node:timers';
import { fileURLToPath } from 'node:url';
import { Buffer } from 'node:buffer';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const defaultOutDir = path.join(repoRoot, 'docs/runs/rd-05-external-mpv-poc');
const dummyHeader = Object.freeze({ name: 'X-Lineup-POC', value: 'rd-05-dummy' });
const evidenceFiles = Object.freeze([
  'manifest.redacted.json',
  'events.redacted.ndjson',
  'summary.redacted.md',
]);

const forbiddenEvidencePatterns = [
  { label: 'remote-url', pattern: /\bhttps?:\/\//iu },
  { label: 'absolute-user-path', pattern: /\/Users\/|\/Volumes\/|\/private\/|\/var\/folders\//iu },
  { label: 'raw-auth-field', pattern: new RegExp(`${['Author', 'ization'].join('')}\\s*:`, 'iu') },
  { label: 'plex-field', pattern: /\bX-Plex\b|Plex-specific/iu },
  { label: 'cookie-field', pattern: /\bcookie\s*:/iu },
  { label: 'bearer-field', pattern: /\bbearer\b/iu },
  { label: 'token-field', pattern: /\btoken\b/iu },
  { label: 'credential-field', pattern: /\bcredential\b/iu },
  { label: 'native-log', pattern: /\b(?:stderr|stdout|crash dump|process args)\b/iu },
];

export function resolveExecutable(commandName, envPath = process.env.PATH ?? '') {
  if (commandName.includes(path.sep)) {
    return isExecutable(commandName) ? commandName : null;
  }

  for (const segment of envPath.split(path.delimiter)) {
    if (!segment) {
      continue;
    }
    const candidate = path.join(segment, commandName);
    if (isExecutable(candidate)) {
      return candidate;
    }
  }

  return null;
}

export function getMpvVersionSummary(mpvPath) {
  const result = spawnSync(mpvPath, ['--version'], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024,
    timeout: 5000,
  });

  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error('mpv --version failed');
  }

  return result.stdout
    .split(/\r?\n/u)
    .filter(Boolean)
    .slice(0, 3)
    .map((line) => line.replace(/[^\x20-\x7E]/gu, '').slice(0, 120));
}

export function buildDummyHeaderField(header = dummyHeader) {
  return `${header.name}: ${header.value}`;
}

export function assertDummyHeaderPolicy(headerField) {
  if (headerField !== buildDummyHeaderField()) {
    throw new Error('RD-05 POC permits only the approved dummy header field');
  }

  const lower = headerField.toLowerCase();
  const forbidden = [
    'authorization',
    'cookie',
    'bearer',
    'credential',
    'x-plex',
    'plex',
    'token',
  ];
  for (const term of forbidden) {
    if (lower.includes(term)) {
      throw new Error(`RD-05 POC forbidden header term: ${term}`);
    }
  }
}

export function buildMpvInvocation({ mpvPath = 'mpv', ipcSocketPath, mediaUrl, headerField = buildDummyHeaderField() }) {
  assertDummyHeaderPolicy(headerField);
  if (!ipcSocketPath || !mediaUrl) {
    throw new Error('mpv invocation requires an IPC socket and media URL');
  }

  const args = [
    '--no-config',
    '--idle=yes',
    `--input-ipc-server=${ipcSocketPath}`,
    `--http-header-fields=${headerField}`,
    '--start=0.5',
    '--vo=null',
    '--ao=null',
    '--no-terminal',
    '--msg-level=all=no',
    mediaUrl,
  ];

  return { command: mpvPath, args };
}

export function sanitizeCommandName(command) {
  if (!Array.isArray(command) || command.length === 0) {
    return 'unknown';
  }
  if (command[0] === 'get_property' && typeof command[1] === 'string') {
    return `get_property:${command[1]}`;
  }
  if (typeof command[0] === 'string') {
    return command[0];
  }
  return 'unknown';
}

export function normalizeTrack(track, index = 0) {
  const kind = normalizeKind(track?.type);
  const language = normalizeLanguage(track?.lang);
  const codec = normalizeShortField(track?.codec ?? track?.codecDesc ?? track?.format);
  const normalized = {
    label: `track-${index + 1}`,
    kind,
    selected: Boolean(track?.selected),
    language,
    codec,
  };

  const channels = Number(track?.audioChannels ?? track?.demuxChannels);
  if (Number.isInteger(channels) && channels > 0 && channels <= 16) {
    normalized.channelCount = channels;
  }

  return normalized;
}

export function summarizeIpcResponse(response) {
  if (!response || typeof response !== 'object') {
    return { category: 'unavailable' };
  }
  if (response.error && response.error !== 'success') {
    return { category: 'error' };
  }
  return { category: 'success' };
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

export function createWavBuffer({ durationSeconds = 30, sampleRate = 44100, frequency = 440 } = {}) {
  const samples = Math.floor(durationSeconds * sampleRate);
  const dataBytes = samples * 2;
  const buffer = Buffer.alloc(44 + dataBytes);

  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataBytes, 40);

  for (let sample = 0; sample < samples; sample += 1) {
    const value = Math.round(Math.sin((2 * Math.PI * frequency * sample) / sampleRate) * 12000);
    buffer.writeInt16LE(value, 44 + sample * 2);
  }

  return buffer;
}

async function runCli() {
  const options = parseArgs(process.argv.slice(2));
  const outDir = path.resolve(repoRoot, options.out ?? defaultOutDir);
  if (options.input !== 'local-dummy-http') {
    throw new Error('RD-05 POC only supports --input local-dummy-http');
  }

  const mpvPath = resolveExecutable('mpv');
  if (!mpvPath) {
    throw new Error('mpv was not found on PATH');
  }
  const mpvVersion = getMpvVersionSummary(mpvPath);

  await fsp.mkdir(outDir, { recursive: true });
  const tempDir = await fsp.mkdtemp(path.join(outDir, 'tmp-'));
  const mediaPath = path.join(tempDir, 'dummy.wav');
  const ipcSocketPath = path.join(tempDir, 'mpv-ipc.sock');
  const events = [];
  const cleanup = {
    mpvProcess: 'not-started',
    ipcSocketRemoved: false,
    httpServerClosed: false,
    tempInputs: 'not-started',
    evidenceScanPassed: false,
  };

  let server;
  let child;
  let finalEvidenceFindingCount = 0;

  try {
    await fsp.writeFile(mediaPath, createWavBuffer());
    const requestFacts = { count: 0, dummyHeaderReceived: false, forbiddenHeaderSeen: false };
    server = await startDummyHttpServer(mediaPath, requestFacts);
    const mediaUrl = `http://127.0.0.1:${server.address().port}/media.wav`;
    const invocation = buildMpvInvocation({ mpvPath, ipcSocketPath, mediaUrl });

    child = spawn(invocation.command, invocation.args, {
      cwd: repoRoot,
      env: { PATH: process.env.PATH ?? '' },
      stdio: 'ignore',
    });

    const ipc = createMpvIpcClient(await connectToMpvIpc(ipcSocketPath, child));
    const commandResults = [];

    commandResults.push(await pollIpcCommand(
      () => ipc.send(['get_property', 'track-list'], 1),
      (result) => Array.isArray(result.rawData) && result.rawData.length > 0,
      5000,
    ));
    commandResults.push(await pollIpcCommand(
      () => ipc.send(['get_property', 'time-pos'], 2),
      (result) => result.category === 'success' && Number.isFinite(result.rawData),
      3000,
    ));
    await delay(Math.max(250, Math.min(options.durationMs, 3000)));
    commandResults.push(await ipc.send(['stop'], 3));
    ipc.markAfterStop();
    await delay(250);
    const eventsAfterStopBeforeQuit = ipc.getEventsAfterStopCount();
    commandResults.push(await ipc.send(['quit'], 4));
    ipc.close();

    const exitInfo = await waitForChildExit(child, 3000);
    cleanup.mpvProcess = exitInfo.killedByHarness ? 'killed-by-harness' : 'exited';

    const trackResponse = commandResults.find((result) => result.commandName === 'get_property:track-list');
    const trackList = Array.isArray(trackResponse?.rawData)
      ? trackResponse.rawData.map((track, index) => normalizeTrack(track, index))
      : [];
    const timeResponse = commandResults.find((result) => result.commandName === 'get_property:time-pos');

    events.push(...commandResults.map(({ requestId, commandName, category }) => ({
      kind: 'ipc-command',
      requestId,
      commandName,
      category,
    })));

    events.push({
      kind: 'http-observation',
      requestCount: requestFacts.count,
      dummyHeaderObserved: requestFacts.dummyHeaderReceived,
      forbiddenHeaderObserved: requestFacts.forbiddenHeaderSeen,
    });

    const manifest = {
      poc: 'rd-05-external-mpv',
      input: 'local-dummy-http',
      mpv: {
        resolved: true,
        versionSummary: mpvVersion,
      },
      invocationPolicy: {
        shellInterpolation: false,
        configDisabled: true,
        ipcPrivateToScript: true,
        dummyHeaderOnly: true,
        startOffsetSeconds: 0.5,
        outputSuppressed: true,
      },
      observations: {
        dummyHttpRequestCount: requestFacts.count,
        dummyHeaderObserved: requestFacts.dummyHeaderReceived,
        forbiddenHeaderObserved: requestFacts.forbiddenHeaderSeen,
        trackCount: trackList.length,
        tracks: trackList,
        timePositionCategory: categorizeTimePosition(timeResponse?.rawData),
        stopCommandCategory: commandResults.find((result) => result.commandName === 'stop')?.category ?? 'unavailable',
        sanitizedMpvEvents: ipc.getEventCounts(),
        eventsAfterStopBeforeQuit,
      },
      cleanup,
    };

    await writeEvidence(outDir, manifest, events);
  } finally {
    if (child && child.exitCode === null && !child.killed) {
      child.kill('SIGTERM');
      cleanup.mpvProcess = 'killed-by-harness';
    }
    if (server) {
      await closeServer(server);
      cleanup.httpServerClosed = true;
    }
    cleanup.ipcSocketRemoved = await removeIfExists(ipcSocketPath);
    cleanup.tempInputs = await removeTempDir(tempDir);

    const manifestPath = path.join(outDir, 'manifest.redacted.json');
    if (fs.existsSync(manifestPath)) {
      const manifest = JSON.parse(await fsp.readFile(manifestPath, 'utf8'));
      manifest.cleanup = cleanup;
      await fsp.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    }

    const findings = await scanEvidenceDirectory(outDir);
    cleanup.evidenceScanPassed = findings.length === 0;
    if (fs.existsSync(manifestPath)) {
      const manifest = JSON.parse(await fsp.readFile(manifestPath, 'utf8'));
      manifest.cleanup = cleanup;
      await fsp.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
      await writeSummary(outDir, manifest);
      const finalFindings = await scanEvidenceDirectory(outDir);
      finalEvidenceFindingCount = finalFindings.length;
    }
  }

  if (finalEvidenceFindingCount > 0) {
    throw new Error(`redacted evidence scan failed: ${finalEvidenceFindingCount} finding(s)`);
  }
}

function isExecutable(candidate) {
  try {
    fs.accessSync(candidate, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function parseArgs(args) {
  const options = { out: defaultOutDir, input: 'local-dummy-http', durationMs: 3000 };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    const value = args[index + 1];
    if (arg === '--out' && value) {
      options.out = value;
      index += 1;
    } else if (arg === '--input' && value) {
      options.input = value;
      index += 1;
    } else if (arg === '--duration-ms' && value) {
      options.durationMs = Number(value);
      index += 1;
    } else {
      throw new Error(`unknown or incomplete argument: ${arg}`);
    }
  }

  if (!Number.isInteger(options.durationMs) || options.durationMs < 500 || options.durationMs > 10000) {
    throw new Error('--duration-ms must be an integer from 500 to 10000');
  }

  return options;
}

async function startDummyHttpServer(mediaPath, requestFacts) {
  const media = await fsp.readFile(mediaPath);
  const server = http.createServer((request, response) => {
    requestFacts.count += 1;
    requestFacts.dummyHeaderReceived ||= request.headers[dummyHeader.name.toLowerCase()] === dummyHeader.value;
    requestFacts.forbiddenHeaderSeen ||= Object.keys(request.headers).some((name) => isForbiddenHeaderName(name));

    response.writeHead(200, {
      'Content-Type': 'audio/wav',
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
  return lower.includes('authorization') ||
    lower.includes('cookie') ||
    lower.includes('bearer') ||
    lower.includes('credential') ||
    lower.includes('x-plex') ||
    lower.includes('plex') ||
    lower.includes('token');
}

async function connectToMpvIpc(ipcSocketPath, child) {
  const started = Date.now();
  while (Date.now() - started < 5000) {
    if (child.exitCode !== null) {
      throw new Error('mpv exited before IPC became available');
    }
    if (fs.existsSync(ipcSocketPath)) {
      return await new Promise((resolve, reject) => {
        const socket = net.createConnection(ipcSocketPath);
        socket.once('connect', () => resolve(socket));
        socket.once('error', reject);
      });
    }
    await delay(100);
  }
  throw new Error('timed out waiting for mpv IPC socket');
}

function createMpvIpcClient(socket) {
  let buffer = '';
  let afterStop = false;
  let eventsAfterStopCount = 0;
  const eventCounts = new Map();
  const pendingRequests = new Map();
  const pendingEvents = new Map();

  socket.on('data', (chunk) => {
    buffer += chunk.toString('utf8');
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';
    for (const line of lines) {
      if (!line.trim()) {
        continue;
      }
      const parsed = JSON.parse(line);
      if (typeof parsed.request_id === 'number' && pendingRequests.has(parsed.request_id)) {
        pendingRequests.get(parsed.request_id).resolve(parsed);
        pendingRequests.delete(parsed.request_id);
        continue;
      }
      if (typeof parsed.event === 'string') {
        const eventName = normalizeShortField(parsed.event);
        eventCounts.set(eventName, (eventCounts.get(eventName) ?? 0) + 1);
        if (afterStop) {
          eventsAfterStopCount += 1;
        }
        const waiters = pendingEvents.get(parsed.event) ?? [];
        pendingEvents.delete(parsed.event);
        for (const resolve of waiters) {
          resolve();
        }
      }
    }
  });

  socket.once('error', (error) => {
    for (const pending of pendingRequests.values()) {
      pending.reject(error);
    }
    pendingRequests.clear();
  });

  return {
    async send(command, requestId) {
      const commandName = sanitizeCommandName(command);
      const payload = JSON.stringify({ command, request_id: requestId });
      const response = await new Promise((resolve, reject) => {
        const timeout = setNodeTimeout(() => {
          pendingRequests.delete(requestId);
          reject(new Error(`IPC command timed out: ${commandName}`));
        }, 2500);
        pendingRequests.set(requestId, {
          resolve: (value) => {
            clearNodeTimeout(timeout);
            resolve(value);
          },
          reject: (error) => {
            clearNodeTimeout(timeout);
            reject(error);
          },
        });
        socket.write(`${payload}\n`);
      });

      const summary = summarizeIpcResponse(response);
      return {
        requestId,
        commandName,
        category: summary.category,
        rawData: response?.data,
      };
    },
    waitForEvent(eventName, timeoutMs) {
      if ((eventCounts.get(normalizeShortField(eventName)) ?? 0) > 0) {
        return Promise.resolve();
      }
      return new Promise((resolve, reject) => {
        const timeout = setNodeTimeout(() => {
          reject(new Error(`timed out waiting for mpv event: ${eventName}`));
        }, timeoutMs);
        const waiters = pendingEvents.get(eventName) ?? [];
        waiters.push(() => {
          clearNodeTimeout(timeout);
          resolve();
        });
        pendingEvents.set(eventName, waiters);
      });
    },
    markAfterStop() {
      afterStop = true;
    },
    getEventCounts() {
      return Object.fromEntries([...eventCounts.entries()].sort(([left], [right]) => left.localeCompare(right)));
    },
    getEventsAfterStopCount() {
      return eventsAfterStopCount;
    },
    close() {
      socket.end();
    },
  };
}

async function pollIpcCommand(commandFactory, isReady, timeoutMs) {
  const started = Date.now();
  let lastResult;
  while (Date.now() - started < timeoutMs) {
    lastResult = await commandFactory();
    if (isReady(lastResult)) {
      return lastResult;
    }
    await delay(250);
  }
  return lastResult;
}

async function waitForChildExit(child, timeoutMs) {
  if (child.exitCode !== null) {
    return { killedByHarness: false };
  }

  return await new Promise((resolve) => {
    const timeout = setNodeTimeout(() => {
      child.kill('SIGTERM');
      resolve({ killedByHarness: true });
    }, timeoutMs);

    child.once('exit', () => {
      clearNodeTimeout(timeout);
      resolve({ killedByHarness: false });
    });
  });
}

function categorizeTimePosition(value) {
  return Number.isFinite(value) && value >= 0.4 ? 'nonzero-or-start-offset-observed' : 'unavailable';
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
    '# RD-05 External mpv POC Redacted Summary',
    '',
    `- mpv: ${manifest.mpv.versionSummary[0] ?? 'unknown'}`,
    `- input: ${manifest.input}`,
    `- dummy HTTP requests: ${manifest.observations.dummyHttpRequestCount}`,
    `- dummy header observed: ${manifest.observations.dummyHeaderObserved ? 'yes' : 'no'}`,
    `- forbidden header observed: ${manifest.observations.forbiddenHeaderObserved ? 'yes' : 'no'}`,
    `- track count: ${manifest.observations.trackCount}`,
    `- time position: ${manifest.observations.timePositionCategory}`,
    `- stop command: ${manifest.observations.stopCommandCategory}`,
    `- events after stop before quit: ${manifest.observations.eventsAfterStopBeforeQuit}`,
    `- process cleanup: ${manifest.cleanup.mpvProcess}`,
    `- IPC socket removed: ${manifest.cleanup.ipcSocketRemoved ? 'yes' : 'no'}`,
    `- HTTP server closed: ${manifest.cleanup.httpServerClosed ? 'yes' : 'no'}`,
    `- temp inputs: ${manifest.cleanup.tempInputs}`,
    `- forbidden field scan: ${manifest.cleanup.evidenceScanPassed ? 'passed' : 'failed'}`,
    '',
  ];
  await fsp.writeFile(path.join(outDir, 'summary.redacted.md'), lines.join('\n'));
}

function normalizeKind(value) {
  if (value === 'audio' || value === 'sub' || value === 'video') {
    return value;
  }
  return 'unknown';
}

function normalizeLanguage(value) {
  if (typeof value !== 'string') {
    return 'und';
  }
  const lower = value.toLowerCase();
  return /^[a-z]{2,3}$/u.test(lower) ? lower : 'und';
}

function normalizeShortField(value) {
  if (typeof value !== 'string') {
    return 'unknown';
  }
  const cleaned = value.toLowerCase().replace(/[^a-z0-9._-]/gu, '').slice(0, 32);
  return cleaned || 'unknown';
}

function delay(ms) {
  return new Promise((resolve) => {
    setNodeTimeout(resolve, ms);
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

async function removeIfExists(targetPath) {
  try {
    await fsp.unlink(targetPath);
    return true;
  } catch (error) {
    if (error.code === 'ENOENT') {
      return true;
    }
    return false;
  }
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
