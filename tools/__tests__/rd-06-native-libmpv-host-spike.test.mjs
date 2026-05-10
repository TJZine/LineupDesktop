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

test('parseArgs accepts RD-06 preflight, WID smoke, render API, and native presentation modes', () => {
  assert.deepEqual(parseArgs(['--mode', 'preflight', '--out', 'docs/runs/rd-06-native-libmpv-host-spike']), {
    mode: 'preflight',
    out: 'docs/runs/rd-06-native-libmpv-host-spike',
    durationMs: 5000,
    dummyInput: 'local-and-http',
    fullscreenMode: null,
  });

  const widSmoke = parseArgs(['--mode', 'wid-smoke', '--duration-ms', '7500', '--dummy-input', 'local-and-http']);
  assert.equal(widSmoke.mode, 'wid-smoke');
  assert.equal(widSmoke.durationMs, 7500);
  assert.equal(widSmoke.dummyInput, 'local-and-http');
  assert.equal(widSmoke.fullscreenMode, null);
  assert.match(widSmoke.out, /rd-06-native-libmpv-host-spike/u);

  const renderPreflight = parseArgs(['--mode', 'render-api-preflight']);
  assert.equal(renderPreflight.mode, 'render-api-preflight');

  const renderSmoke = parseArgs([
    '--mode',
    'render-api-smoke',
    '--duration-ms',
    '5000',
    '--dummy-input',
    'local-and-http',
    '--fullscreen-mode',
    'browser-window',
  ]);
  assert.equal(renderSmoke.mode, 'render-api-smoke');
  assert.equal(renderSmoke.fullscreenMode, 'browser-window');

  const nativePresentationPreflight = parseArgs(['--mode', 'native-presentation-preflight']);
  assert.equal(nativePresentationPreflight.mode, 'native-presentation-preflight');

  const nativePresentationSmoke = parseArgs([
    '--mode',
    'native-presentation-smoke',
    '--duration-ms',
    '5000',
    '--dummy-input',
    'local-and-http',
    '--fullscreen-mode',
    'native-presentation-host',
  ]);
  assert.equal(nativePresentationSmoke.mode, 'native-presentation-smoke');
  assert.equal(nativePresentationSmoke.fullscreenMode, 'native-presentation-host');
});

test('parseArgs rejects unsupported modes and dummy input policies', () => {
  assert.throws(() => parseArgs(['--mode', 'external-mpv']), /native-presentation-preflight/u);
  assert.throws(() => parseArgs(['--mode', 'wid-smoke', '--dummy-input', 'real-server']), /local-and-http/u);
  assert.throws(() => parseArgs(['--mode', 'wid-smoke', '--duration-ms', '100']), /duration-ms/u);
  assert.throws(() => parseArgs(['--mode', 'render-api-smoke']), /fullscreen-mode browser-window/u);
  assert.throws(
    () => parseArgs(['--mode', 'render-api-smoke', '--fullscreen-mode', 'native-window']),
    /fullscreen-mode must be browser-window or native-presentation-host/u,
  );
  assert.throws(
    () => parseArgs(['--mode', 'native-presentation-smoke', '--fullscreen-mode', 'browser-window']),
    /fullscreen-mode native-presentation-host/u,
  );
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

test('helper source probes public libmpv render API symbols', () => {
  assert.match(helperSource, /mpv_render_context_create/u);
  assert.match(helperSource, /mpv_render_context_render/u);
  assert.match(helperSource, /mpv_render_context_update/u);
  assert.match(helperSource, /mpv_render_context_free/u);
  assert.match(helperSource, /"libmpv-render-api-symbols"/u);
  assert.match(helperSource, /NativeLibrary\.TryGetExport\(library, "mpv_render_context_create"/u);
});

test('render API smoke does not overclaim render-thread or composition proof', () => {
  const source = fs.readFileSync(
    new URL('../libmpv-spike/rd-06-native-libmpv-host-spike.mjs', import.meta.url),
    'utf8',
  );
  assert.match(helperSource, /"render-thread-discipline"/u);
  assert.match(helperSource, /"not-proven-blocking-helper-loop"/u);
  assert.match(source, /not-proven-merged-capture-sources/u);
  assert.match(source, /requiredProofs\.get\('render-thread-discipline'\)\?\.category === 'proven'/u);
  assert.match(source, /requiredProofs\.get\('composition'\)\?\.visiblePixelsObserved === true/u);
  assert.doesNotMatch(source, /active-playback-composited/u);
});

test('render API smoke gates fullscreen native capture on BrowserWindow fullscreen', () => {
  const source = fs.readFileSync(
    new URL('../libmpv-spike/rd-06-native-libmpv-host-spike.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /control: 'fullscreen-native-capture'/u);
  assert.match(source, /browserWindowFullscreen: true/u);
  assert.match(source, /config\.renderApi === true/u);
  assert.match(source, /fullscreenActive && useNativeFullscreenCapture/u);
  assert.match(source, /fullscreenProof\?\.browserWindowFullscreen === true/u);
  assert.match(source, /fullscreenNativeCaptureProof\?\.browserWindowFullscreen === true/u);
  assert.match(source, /fullscreenNativeCapture: summarizeFullscreenNativeCaptureProof/u);
  assert.match(source, /nativeCaptureObserved/u);
});

test('helper source handles private fullscreen native capture control', () => {
  assert.match(helperSource, /controlValue == "fullscreen-native-capture"/u);
  assert.match(helperSource, /browserWindowFullscreen = document\.RootElement\.TryGetProperty\("browserWindowFullscreen"/u);
  assert.match(helperSource, /browserWindowFullscreen && surface\.HasVisibleDesktopPixels\(\)/u);
  assert.match(helperSource, /"fullscreen-native-capture"/u);
  assert.match(helperSource, /"desktop-composited-red-pixels"/u);
  assert.match(helperSource, /"nativeCaptureObserved"/u);
});

test('helper source uses Win32 GDI desktop capture scoped to the render child surface', () => {
  assert.match(helperSource, /GetWindowRect\(window, out NativeMethods\.RECT bounds\)/u);
  assert.match(helperSource, /CaptureDesktopRedPixels\(bounds\)/u);
  assert.match(helperSource, /private const int SurfaceTop = 140/u);
  assert.match(helperSource, /nativePresentation \? HwndTopmost : IntPtr\.Zero/u);
  assert.match(helperSource, /GetDC\(IntPtr\.Zero\)/u);
  assert.match(helperSource, /CreateCompatibleDC/u);
  assert.match(helperSource, /CreateCompatibleBitmap/u);
  assert.match(helperSource, /BitBlt/u);
  assert.match(helperSource, /GetDIBits/u);
  assert.match(helperSource, /Srccopy \| Captureblt/u);
  assert.doesNotMatch(helperSource, /GetSystemMetrics/u);
});

test('native presentation smoke uses app-owned fullscreen host and same-boundary composition proof', () => {
  const source = fs.readFileSync(
    new URL('../libmpv-spike/rd-06-native-libmpv-host-spike.mjs', import.meta.url),
    'utf8',
  );
  assert.match(source, /native-presentation-preflight/u);
  assert.match(source, /native-presentation-smoke/u);
  assert.match(source, /native-presentation-host/u);
  assert.match(source, /nativePresentationFullscreen/u);
  assert.match(source, /nativePresentationHost: nativePresentation/u);
  assert.match(helperSource, /RunNativePresentationSmoke/u);
  assert.match(helperSource, /LineupRd06NativePresentationHost/u);
  assert.match(helperSource, /EnterFullscreenHost/u);
  assert.match(helperSource, /MonitorFromWindow/u);
  assert.match(helperSource, /native-boundary-composited/u);
  assert.match(helperSource, /DrawOverlay/u);
  assert.match(helperSource, /glScissor/u);
});

test('native presentation smoke records render-thread discipline without helper-owned blocking loop claim', () => {
  assert.match(helperSource, /new Thread\(RenderLoop\)/u);
  assert.match(helperSource, /rd06-native-presentation-render/u);
  assert.match(helperSource, /\["proof"\] = "render-thread-discipline"/u);
  assert.match(helperSource, /\["category"\] = "proven"/u);
  assert.match(helperSource, /LoadAndObserve\(mpv, init\.localMedia/u);
  assert.match(helperSource, /RenderThreadProbe/u);
});

test('helper source defines minimal render API interop without vendored headers', () => {
  assert.match(helperSource, /private struct MpvRenderParam/u);
  assert.match(helperSource, /private struct MpvOpenGlFbo/u);
  assert.match(helperSource, /private struct MpvOpenGlInitParams/u);
  assert.doesNotMatch(helperSource, /Copyright \(c\).*mpv/iu);
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
    renderApiSymbols: 'requires-render-api-preflight',
    nativePresentationHost: 'not-requested',
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
    renderApi: true,
  });
  const spawnPolicy = buildHelperSpawn('dotnet', '<temp-helper>');

  assert.equal(spawnPolicy.shell, false);
  assert.equal(spawnPolicy.stdio[0], 'pipe');
  assert.equal(spawnPolicy.stdio[2], 'ignore');
  assert.doesNotThrow(() => assertHelperInitPolicy(spawnPolicy, init));
  assert.equal(init.renderApi, true);

  const nativePresentationInit = buildHelperInitPayload({
    requestId: 'rd06-native-presentation-test',
    libmpvDll: '<local-libmpv>',
    localMedia: '<dummy-local-media>',
    httpMedia: '<dummy-http-media>',
    durationMs: 5000,
    renderApi: true,
    nativePresentation: true,
  });
  assert.equal(nativePresentationInit.nativePresentation, true);
  assert.equal('parentWid' in nativePresentationInit, false);

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
    proof: 'fullscreen-native-capture',
    category: 'desktop-composited-red-pixels',
    nativeCaptureObserved: true,
    visiblePixelsObserved: true,
    browserWindowFullscreen: true,
    libmpvClientApiMajor: 2,
    libmpvClientApiMinor: 5,
    parentWid: '<private-parent-attachment>',
    localMedia: '<dummy-local-media>',
    httpMedia: '<dummy-http-media>',
    raw: 'ignored',
  });

  assert.deepEqual(sanitized, {
    kind: 'observed',
    proof: 'fullscreen-native-capture',
    category: 'desktop-composited-red-pixels',
    nativeCaptureObserved: true,
    visiblePixelsObserved: true,
    browserWindowFullscreen: true,
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
