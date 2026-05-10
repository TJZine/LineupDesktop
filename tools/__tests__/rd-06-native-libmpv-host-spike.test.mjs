import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

import {
  assertDummyHeaderPolicy,
  assertHelperInitPolicy,
  buildDummyHeaderField,
  buildHelperInitPayload,
  buildHelperSpawn,
  buildNativePrerequisiteEvidence,
  createDummyVisualMediaBuffer,
  parseArgs,
  sanitizeHelperEvent,
  scanForbiddenEvidenceContent,
  validatePreflightFacts,
} from '../libmpv-spike/rd-06-native-libmpv-host-spike.mjs';

const helperSource = fs.readFileSync(
  new URL('../libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs', import.meta.url),
  'utf8',
);

test('parseArgs accepts RD-06 preflight and WID smoke modes', () => {
  assert.deepEqual(parseArgs(['--mode', 'preflight', '--out', 'docs/runs/rd-06-native-libmpv-host-spike']), {
    mode: 'preflight',
    out: 'docs/runs/rd-06-native-libmpv-host-spike',
    durationMs: 5000,
    dummyInput: 'local-and-http',
  });

  const widSmoke = parseArgs(['--mode', 'wid-smoke', '--duration-ms', '7500', '--dummy-input', 'local-and-http']);
  assert.equal(widSmoke.mode, 'wid-smoke');
  assert.equal(widSmoke.durationMs, 7500);
  assert.equal(widSmoke.dummyInput, 'local-and-http');
  assert.match(widSmoke.out, /rd-06-native-libmpv-host-spike/u);
});

test('parseArgs rejects unsupported modes and dummy input policies', () => {
  assert.throws(() => parseArgs(['--mode', 'external-mpv']), /preflight or wid-smoke/u);
  assert.throws(() => parseArgs(['--mode', 'wid-smoke', '--dummy-input', 'real-server']), /local-and-http/u);
  assert.throws(() => parseArgs(['--mode', 'wid-smoke', '--duration-ms', '100']), /duration-ms/u);
});

test('validatePreflightFacts requires Windows, Electron, dotnet, mpv, and libmpv', () => {
  assert.equal(validatePreflightFacts({
    platform: 'win32',
    node: 'v22.21.1',
    electronExecutable: process.execPath,
    dotnetExecutable: 'dotnet',
    mpvExecutable: process.execPath,
    libmpvDll: process.execPath,
  }).status, 'passed');

  const blocked = validatePreflightFacts({
    platform: 'darwin',
    node: 'v22.21.1',
    electronExecutable: null,
    dotnetExecutable: null,
    mpvExecutable: 'missing',
    libmpvDll: 'missing',
  });
  assert.equal(blocked.status, 'blocked');
  assert.ok(blocked.checks.some((check) => check.name === 'windows' && !check.ok));
});

test('dummy header policy allows only the RD-06 non-secret header', () => {
  assert.equal(buildDummyHeaderField(), 'X-Lineup-RD06: dummy');
  assert.doesNotThrow(() => assertDummyHeaderPolicy());
  assert.throws(
    () => assertDummyHeaderPolicy({ name: ['Author', 'ization'].join(''), value: 'sample' }),
    /approved dummy header/u,
  );
  assert.throws(
    () => assertDummyHeaderPolicy({ name: ['X-Plex', 'Token'].join('-'), value: 'sample' }),
    /approved dummy header/u,
  );
  assert.throws(
    () => assertDummyHeaderPolicy({ name: 'Cookie', value: 'sample' }),
    /approved dummy header/u,
  );
});

test('dummy visual media fixture is a visual GIF, not audio-only WAV', () => {
  const media = createDummyVisualMediaBuffer();
  assert.equal(media.subarray(0, 6).toString('ascii'), 'GIF89a');
  assert.notEqual(media.subarray(0, 4).toString('ascii'), 'RIFF');
});

test('helper source enforces exact RD-06 dummy HTTP header before setting mpv option', () => {
  assert.match(helperSource, /headerName != "X-Lineup-RD06" \|\| headerValue != "dummy"/u);
  assert.match(helperSource, /"dummy-header-policy"/u);
  assert.match(helperSource, /SetOption\(mpv, "http-header-fields", \$"\{headerName\}: \{headerValue\}"\)/u);
});

test('helper source exposes libmpv client API version evidence', () => {
  assert.match(helperSource, /mpv_client_api_version/u);
  assert.match(helperSource, /"libmpv-client-api"/u);
  assert.match(helperSource, /"libmpvClientApiMajor"/u);
  assert.match(helperSource, /"libmpvClientApiMinor"/u);
});

test('WID smoke source merges repeated proof events before pass/fail evaluation', () => {
  const source = fs.readFileSync(
    new URL('../libmpv-spike/rd-06-native-libmpv-host-spike.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /const requiredProofs = collectProofs\(events\)/u);
  assert.match(source, /fileLoaded: current\.fileLoaded === true \|\| event\.fileLoaded === true/u);
  assert.match(source, /activePlayback: current\.activePlayback === true \|\| event\.activePlayback === true/u);
  assert.doesNotMatch(source, /new Map\(events\.map\(\(event\) => \[event\.proof, event\]\)\)/u);
});

test('native prerequisite evidence records provenance without local paths', () => {
  const evidence = buildNativePrerequisiteEvidence({
    mpvExecutable: process.execPath,
    libmpvDll: process.execPath,
  }, ['mpv v0.41.0-524-g5921fe50b']);

  assert.deepEqual(evidence, {
    mpvExecutable: 'resolved-local-prerequisite',
    libmpvDll: 'resolved-local-prerequisite',
    libmpvDllName: path.basename(process.execPath),
    mpvVersion: ['mpv v0.41.0-524-g5921fe50b'],
    libmpvClientApiVersion: 'requires-helper-preflight',
    provenance: 'official-installation-page-linked-shinchiro-windows-build',
    redistribution: 'not-redistributed-local-proof-only',
    packageMetadataChanged: false,
    installAttemptedBySpike: false,
  });
  assert.deepEqual(scanForbiddenEvidenceContent(JSON.stringify(evidence)), []);
});

test('helper init policy keeps private values out of args and env and uses stdin once', () => {
  const init = buildHelperInitPayload({
    requestId: 'rd06-test',
    libmpvDll: '<local-libmpv>',
    parentWid: '<private-parent-attachment>',
    localMedia: '<dummy-local-media>',
    httpMedia: '<dummy-http-media>',
    durationMs: 5000,
  });
  const spawnPolicy = buildHelperSpawn('dotnet', '<temp-helper>');

  assert.equal(spawnPolicy.shell, false);
  assert.equal(spawnPolicy.stdio[0], 'pipe');
  assert.equal(spawnPolicy.stdio[2], 'ignore');
  assert.doesNotThrow(() => assertHelperInitPolicy(spawnPolicy, init));

  assert.throws(
    () => assertHelperInitPolicy({ ...spawnPolicy, args: [spawnPolicy.args[0], init.parentWid] }, init),
    /must not be passed/u,
  );
  assert.throws(
    () => assertHelperInitPolicy({ ...spawnPolicy, env: { RD06_MEDIA: init.httpMedia } }, init),
    /must not be passed/u,
  );
});

test('sanitizeHelperEvent drops raw helper payload fields', () => {
  const sanitized = sanitizeHelperEvent({
    kind: 'observed',
    proof: 'local-media',
    category: 'success',
    fileLoaded: true,
    activePlayback: true,
    visiblePixelsObserved: true,
    libmpvClientApiMajor: 2,
    libmpvClientApiMinor: 5,
    parentWid: '<private-parent-attachment>',
    localMedia: '<dummy-local-media>',
    httpMedia: '<dummy-http-media>',
    raw: 'ignored',
  });

  assert.deepEqual(sanitized, {
    kind: 'observed',
    proof: 'local-media',
    category: 'success',
    fileLoaded: true,
    activePlayback: true,
    visiblePixelsObserved: true,
    libmpvClientApiMajor: 2,
    libmpvClientApiMinor: 5,
  });
});

test('scanForbiddenEvidenceContent catches raw paths, URLs, native values, and secret-shaped fields', () => {
  assert.deepEqual(scanForbiddenEvidenceContent('dummy inputs only and private-stdio-once'), []);
  assert.ok(scanForbiddenEvidenceContent(`${['ht', 'tp'].join('')}://127.0.0.1:34567/dummy.wav`).includes('raw-url'));
  assert.ok(scanForbiddenEvidenceContent(`C:${'\\'}Users${'\\'}example${'\\'}dummy.wav`).includes('windows-local-path'));
  assert.ok(scanForbiddenEvidenceContent('hwnd <redacted>').includes('native-value'));
  assert.ok(scanForbiddenEvidenceContent(`${['Author', 'ization'].join('')}: sample`).includes('raw-auth-field'));
  assert.ok(scanForbiddenEvidenceContent(`${['X-Plex', 'Token'].join('-')}: sample`).includes('plex-field'));
});
