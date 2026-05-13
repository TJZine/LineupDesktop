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
  rd15NativePresentationProofs,
  sanitizeHelperEvent,
  scanForbiddenEvidenceContent,
  summarizeRd15NativePresentationProofs,
  validatePreflightFacts,
} from '../libmpv-spike/rd-06-native-libmpv-host-spike.mjs';

const helperSource = fs.readFileSync(
  new URL('../libmpv-spike/rd-06-native-libmpv-host-spike-helper.cs', import.meta.url),
  'utf8',
);

const harnessSource = fs.readFileSync(
  new URL('../libmpv-spike/rd-06-native-libmpv-host-spike.mjs', import.meta.url),
  'utf8',
);

function assertOrder(source, orderedNeedles) {
  let previousIndex = -1;
  for (const needle of orderedNeedles) {
    const index = source.indexOf(needle);
    assert.notEqual(index, -1, `missing source marker: ${needle}`);
    assert.ok(index > previousIndex, `source marker out of order: ${needle}`);
    previousIndex = index;
  }
}

function sliceMethodSource(source, signature) {
  const signatureIndex = source.indexOf(signature);
  assert.notEqual(signatureIndex, -1, `missing method signature: ${signature}`);
  const bodyStart = source.indexOf('{', signatureIndex);
  assert.notEqual(bodyStart, -1, `missing method body: ${signature}`);

  let depth = 0;
  for (let index = bodyStart; index < source.length; index += 1) {
    const character = source[index];
    if (character === '{') {
      depth += 1;
    } else if (character === '}') {
      depth -= 1;
      if (depth === 0) {
        return source.slice(signatureIndex, index + 1);
      }
    }
  }

  assert.fail(`missing method closing brace: ${signature}`);
}

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
  assert.match(helperSource, /"render-thread-discipline"/u);
  assert.match(helperSource, /"not-proven-blocking-helper-loop"/u);
  assert.match(harnessSource, /not-proven-merged-capture-sources/u);
  assert.match(harnessSource, /requiredProofs\.get\('render-thread-discipline'\)\?\.category === 'proven'/u);
  assert.match(harnessSource, /requiredProofs\.get\('composition'\)\?\.visiblePixelsObserved === true/u);
  assert.doesNotMatch(harnessSource, /active-playback-composited/u);
});

test('render API smoke gates fullscreen native capture on BrowserWindow fullscreen', () => {
  assert.match(harnessSource, /control: 'fullscreen-native-capture'/u);
  assert.match(harnessSource, /browserWindowFullscreen: true/u);
  assert.match(harnessSource, /config\.renderApi === true/u);
  assert.match(harnessSource, /fullscreenActive && useNativeFullscreenCapture/u);
  assert.match(harnessSource, /fullscreenProof\?\.browserWindowFullscreen === true/u);
  assert.match(harnessSource, /fullscreenNativeCaptureProof\?\.browserWindowFullscreen === true/u);
  assert.match(harnessSource, /fullscreenNativeCapture: summarizeFullscreenNativeCaptureProof/u);
  assert.match(harnessSource, /nativeCaptureObserved/u);
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
  assert.match(harnessSource, /native-presentation-preflight/u);
  assert.match(harnessSource, /native-presentation-smoke/u);
  assert.match(harnessSource, /native-presentation-host/u);
  assert.match(harnessSource, /nativePresentationFullscreen/u);
  assert.match(harnessSource, /requiredProofs\.get\('fullscreen-composition'\)/u);
  assert.match(harnessSource, /fullscreenCompositionProof\?\.nativePresentationFullscreen === true/u);
  assert.match(harnessSource, /fullscreenCompositionObserved/u);
  assert.match(harnessSource, /nativePresentationHost: nativePresentation/u);
  assert.match(helperSource, /RunNativePresentationSmoke/u);
  assert.match(helperSource, /LineupRd06NativePresentationHost/u);
  assert.match(helperSource, /EnterFullscreenHost/u);
  assert.match(helperSource, /MonitorFromWindow/u);
  assert.match(helperSource, /\["proof"\] = "fullscreen-composition"/u);
  assert.match(helperSource, /\["nativePresentationFullscreen"\] = fullscreenHost/u);
  assert.match(helperSource, /native-boundary-composited/u);
  assert.match(helperSource, /DrawOverlay/u);
  assert.match(helperSource, /glScissor/u);
});

test('native presentation smoke uses RD-15 proof mirror instead of only hard-coded RD06 overlay', () => {
  assert.match(harnessSource, /config\.nativePresentation === true \? buildRd15NativePresentationHtml\(\) : buildRd06OverlayHtml\(\)/u);
  assert.match(harnessSource, /function buildRd15NativePresentationHtml\(\)/u);
  assert.match(harnessSource, /data-rd15-proof="epg"/u);
  assert.match(harnessSource, /data-rd15-proof="osd"/u);
  assert.match(harnessSource, /data-rd15-proof="mini-guide"/u);
  assert.match(harnessSource, /data-rd15-proof="channel-badge"/u);
  assert.match(harnessSource, /data-rd15-proof="settings"/u);
  assert.match(harnessSource, /data-rd15-proof="channel-setup"/u);
  assert.match(harnessSource, /data-rd15-proof="overlays"/u);
  assert.match(harnessSource, /data-rd15-proof-focus/u);
  assert.match(harnessSource, /#00ff00/u);
  assert.match(harnessSource, /function buildRd06OverlayHtml\(\)/u);
  assert.match(harnessSource, /aria-label="rd06-overlay"/u);
});

test('native presentation smoke requires and summarizes named RD-15 UI surfaces', () => {
  assert.deepEqual(rd15NativePresentationProofs, [
    'rd15-ui-epg',
    'rd15-ui-osd',
    'rd15-ui-mini-guide',
    'rd15-ui-channel-badge',
    'rd15-ui-settings',
    'rd15-ui-channel-setup',
    'rd15-ui-overlays',
    'rd15-ui-focus',
  ]);
  assert.match(harnessSource, /const rd15UiProofs = collectRd15NativePresentationProofs\(events\)/u);
  assert.match(harnessSource, /const rd15UiProofsObserved = !nativePresentation \|\| rd15NativePresentationProofs\.every/u);
  assert.match(harnessSource, /rd15NativePresentationModes\.every\(\(presentationMode\)/u);
  assert.match(harnessSource, /hasRd15NativePresentationProof\(rd15UiProofs, proof, presentationMode\)/u);
  assert.match(harnessSource, /event\.markerPixelsObserved !== true/u);
  assert.match(harnessSource, /presentationMode === 'fullscreen'\s*\?\s*event\.desktopPixelsObserved === true/u);
  assert.match(harnessSource, /rd15UiProofsObserved/u);
  assert.match(harnessSource, /rd15NativePresentationUi: nativePresentation \? summarizeRd15NativePresentationProofs\(rd15UiProofs\) : 'not-requested'/u);
  assert.match(harnessSource, /RD-15 native presentation UI/u);

  const summary = summarizeRd15NativePresentationProofs(new Map([
    ['rd15-ui-epg', new Map([
      ['windowed', {
        visiblePixelsObserved: true,
        markerPixelsObserved: true,
        rendererPixelsObserved: true,
      }],
      ['fullscreen', {
        visiblePixelsObserved: true,
        markerPixelsObserved: true,
        desktopPixelsObserved: true,
      }],
    ])],
    ['rd15-ui-focus', new Map([
      ['windowed', {
        visiblePixelsObserved: true,
        markerPixelsObserved: true,
        rendererPixelsObserved: true,
        focused: true,
      }],
      ['fullscreen', {
        visiblePixelsObserved: true,
        markerPixelsObserved: true,
        desktopPixelsObserved: true,
        focused: true,
      }],
    ])],
  ]));
  assert.deepEqual(summary['rd15-ui-epg'], { windowed: 'observed', fullscreen: 'observed' });
  assert.deepEqual(summary['rd15-ui-focus'], { windowed: 'observed', fullscreen: 'observed' });
  assert.deepEqual(summary['rd15-ui-osd'], { windowed: 'unavailable', fullscreen: 'unavailable' });
});

test('RD-15 native presentation UI proof uses pixel capture in windowed and fullscreen modes', () => {
  const rd15ObserverStart = harnessSource.indexOf('async function observeRd15NativePresentationUi');
  const rd15ObserverEnd = harnessSource.indexOf('async function observeActivePlayback', rd15ObserverStart);
  const rd15ObserverSource = harnessSource.slice(rd15ObserverStart, rd15ObserverEnd);

  assert.match(rd15ObserverSource, /await prepareRd15ProofWindow\(window, presentationMode\)/u);
  assert.match(rd15ObserverSource, /window\.setAlwaysOnTop\(true, 'screen-saver'\)/u);
  assert.match(rd15ObserverSource, /window\.setFullScreen\(true\)/u);
  assert.match(rd15ObserverSource, /window\.moveTop\(\)/u);
  assert.match(rd15ObserverSource, /window\.webContents\.capturePage\(\)/u);
  assert.match(rd15ObserverSource, /captureDesktopBitmapForWindow\(window\)/u);
  assert.match(rd15ObserverSource, /scanGreenMarkerPixels\(rendererBitmap, rendererSize, surface\.rect\)/u);
  assert.match(rd15ObserverSource, /scanGreenMarkerPixels\(desktopCapture\.bitmap, desktopCapture\.size, desktopRect\)/u);
  assert.match(rd15ObserverSource, /presentationMode/u);
  assert.match(rd15ObserverSource, /markerPixelsObserved/u);
  assert.match(rd15ObserverSource, /rendererPixelsObserved/u);
  assert.match(rd15ObserverSource, /desktopPixelsObserved/u);
  assert.match(rd15ObserverSource, /pixelSource/u);
  assert.doesNotMatch(rd15ObserverSource, /style\.visibility !== "hidden" && style\.display !== "none"/u);

  assert.match(harnessSource, /await observeRd15NativePresentationUi\(window, 'windowed'\)/u);
  assert.match(harnessSource, /event\.proof === 'fullscreen-composition'/u);
  assert.match(harnessSource, /event\.nativePresentationFullscreen === true/u);
  assert.match(harnessSource, /event\.visiblePixelsObserved === true/u);
  assert.match(harnessSource, /await observeRd15NativePresentationUi\(window, 'fullscreen'\)/u);
  assert.match(harnessSource, /data-rd15-proof-focus autofocus style="position:relative">Mini guide<i class="rd15-green-pixel"/u);
  assertOrder(harnessSource, [
    "event.proof === 'fullscreen-composition'",
    "await observeRd15NativePresentationUi(window, 'fullscreen')",
  ]);
});

test('native presentation fullscreen proof resets only after fullscreen entry and settle', () => {
  assertOrder(helperSource, [
    'bool fullscreenHost = surface.EnterFullscreenHost();',
    'Thread.Sleep(600);',
    'renderThread.ResetProofWindow();',
    'RenderSnapshot fullscreenSnapshot = renderThread.WaitForPixels',
    'DesktopProofPixels desktopPixels = surface.CaptureDesktopProofPixels();',
    '["proof"] = "fullscreen"',
    '["proof"] = "fullscreen-composition"',
  ]);
  assert.doesNotMatch(helperSource, /renderThread\.ResetProofWindow\(\);\s*bool fullscreenHost = surface\.EnterFullscreenHost\(\)/u);
});

test('native presentation smoke records render-thread discipline without helper-owned blocking loop claim', () => {
  const renderPresentationStart = helperSource.indexOf('public RenderSnapshot RenderPresentationFrame');
  const renderPresentationEnd = helperSource.indexOf('public bool EnterFullscreenHost', renderPresentationStart);
  const renderPresentationFrame = helperSource.slice(renderPresentationStart, renderPresentationEnd);
  assert.match(helperSource, /new Thread\(RenderLoop\)/u);
  assert.match(helperSource, /rd06-native-presentation-render/u);
  assert.match(helperSource, /WaitForFreshRenderProgress\(3,/u);
  assert.match(helperSource, /\["proof"\] = "render-thread-discipline"/u);
  assert.match(helperSource, /\["category"\] = renderThreadDisciplineProven \? "proven" : "not-proven"/u);
  assert.match(renderPresentationFrame, /new MpvRenderParam \{ type = MpvRenderParamOpenGlFbo/u);
  assert.match(renderPresentationFrame, /new MpvRenderParam \{ type = MpvRenderParamFlipY/u);
  assert.match(renderPresentationFrame, /NativeMethods\.mpv_render_context_render/u);
  assert.doesNotMatch(renderPresentationFrame, /MpvRenderParamBlockForTargetTime/u);
  assert.match(helperSource, /LoadAndObserve\(mpv, init\.localMedia/u);
  assert.match(helperSource, /RenderThreadProbe/u);
});

test('render-thread discipline requires fresh bounded render progress after proof reset', () => {
  const nativePresentationSource = sliceMethodSource(
    helperSource,
    'private static int RunNativePresentationSmoke',
  );
  const disciplineStart = nativePresentationSource.indexOf(
    'LoadAndObserve(mpv, init.httpMedia, "dummy-http", init.dummyHeaderName, init.dummyHeaderValue, init.durationMs);',
  );
  assert.notEqual(disciplineStart, -1, 'missing native-presentation dummy-http load marker');
  const disciplineSource = nativePresentationSource.slice(disciplineStart);
  assert.match(helperSource, /public bool WaitForFreshRenderProgress\(int minimumFrameCount, int timeoutMs\)/u);
  assert.match(helperSource, /observedFrameCount >= minimumFrameCount/u);
  assert.match(helperSource, /thread\.IsAlive && observedFrameCount >= minimumFrameCount/u);
  assert.match(
    nativePresentationSource,
    /renderThread\.WaitForFreshRenderProgress\(3, Math\.Max\(1000, Math\.Min\(init\.durationMs, 3000\)\)\)/u,
  );
  assertOrder(disciplineSource, [
    'LoadAndObserve(mpv, init.httpMedia, "dummy-http", init.dummyHeaderName, init.dummyHeaderValue, init.durationMs);',
    'renderThread.ResetProofWindow();',
    'renderThread.WaitForFreshRenderProgress(3, Math.Max(1000, Math.Min(init.durationMs, 3000)))',
  ]);
  assert.doesNotMatch(helperSource, /thread\.IsAlive && observedFrameCount > 0/u);
});

test('native presentation render thread stops before render context cleanup', () => {
  assert.match(helperSource, /private volatile bool running;/u);
  assert.match(helperSource, /thread\.Join\(\);/u);
  assert.doesNotMatch(helperSource, /thread\.Join\(\d+\)/u);
});

test('native presentation smoke requires distinct fullscreen composition and helper cleanup evidence', () => {
  assert.match(harnessSource, /const fullscreenCompositionProof = requiredProofs\.get\('fullscreen-composition'\)/u);
  assert.match(harnessSource, /fullscreenCompositionProof\?\.visiblePixelsObserved === true/u);
  assert.match(harnessSource, /fullscreenCompositionProof\?\.nativePresentationFullscreen === true/u);
  assert.match(harnessSource, /nativePresentation\s*\?\s*fullscreenCompositionProof\?\.visiblePixelsObserved === true/u);
  assert.match(harnessSource, /const helperCleanupObserved = !nativePresentation \|\|/u);
  assert.match(harnessSource, /requiredProofs\.get\('helper-cleanup'\)\?\.cleanupObserved === true/u);
  assert.match(harnessSource, /cleanupObserved: current\.cleanupObserved === true \|\| event\.cleanupObserved === true/u);
  assert.match(harnessSource, /proof: 'helper-cleanup'/u);
  assert.match(harnessSource, /const helperTimeoutMs = Math\.max\(12000, Math\.min\(30000, \(config\.durationMs \* 4\) - 1000\)\)/u);
  assert.match(harnessSource, /beginTimeoutCleanup\(\)/u);
  assert.match(harnessSource, /child\.kill\(\)/u);
});

test('timeout cleanup reports success only after child exit is observed', () => {
  assertOrder(harnessSource, [
    'function beginTimeoutCleanup()',
    'timeoutCleanupStarted = true;',
    'child.kill();',
    "finishHelper('timeout-cleanup-not-observed', 1, 'timeout', false);",
    "child.once('exit', (code, signal) => {",
    "const category = timeoutCleanupStarted ? 'timeout-reaped'",
    'finishHelper(category, code, signal, true);',
  ]);
  assert.doesNotMatch(harnessSource, /finishHelper\('timeout-reaped', null, 'timeout', true\)/u);
});

test('electron harness does not hang forever on ready-to-show ordering', () => {
  const source = fs.readFileSync(
    new URL('../libmpv-spike/rd-06-native-libmpv-host-spike.mjs', import.meta.url),
    'utf8',
  );
  const harnessSource = source.slice(source.indexOf('function buildHarnessScript()'));
  assert.match(harnessSource, /Promise\.race\(\[/u);
  assert.match(harnessSource, /window\.once\('ready-to-show', resolve\)/u);
  assert.match(harnessSource, /setTimeout\(resolve, 1000\)/u);
  assert.match(harnessSource, /window\.show\(\)/u);
});

test('failed timeout cleanup prevents native presentation smoke from passing', () => {
  assert.match(harnessSource, /const helperCleanupFailed = events\.some/u);
  assert.match(harnessSource, /event\.proof === 'helper-cleanup'/u);
  assert.match(harnessSource, /event\.cleanupObserved !== true \|\| event\.kind !== 'observed'/u);
  assert.match(harnessSource, /!helperCleanupFailed/u);
  assert.match(harnessSource, /finishHelper\('timeout-cleanup-not-observed', 1, 'timeout', false\)/u);
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

test('sanitizeHelperEvent keeps RD-15 proof booleans while dropping raw fields', () => {
  const sanitized = sanitizeHelperEvent({
    kind: 'observed',
    proof: 'rd15-ui-focus',
    category: 'rd15-ui-fullscreen-desktop-pixels',
    presentationMode: 'fullscreen',
    pixelSource: 'desktop-capturer',
    focused: true,
    visiblePixelsObserved: true,
    markerPixelsObserved: true,
    rendererPixelsObserved: true,
    desktopPixelsObserved: true,
    productIpcPayload: 'ignored',
    localMedia: '<dummy-local-media>',
  });

  assert.deepEqual(sanitized, {
    kind: 'observed',
    proof: 'rd15-ui-focus',
    category: 'rd15-ui-fullscreen-desktop-pixels',
    presentationMode: 'fullscreen',
    pixelSource: 'desktop-capturer',
    visiblePixelsObserved: true,
    focused: true,
    markerPixelsObserved: true,
    rendererPixelsObserved: true,
    desktopPixelsObserved: true,
  });
});

test('RD-15 native presentation proof stays dev-only without product IPC or production helper behavior', () => {
  const rd15MirrorSource = harnessSource.slice(harnessSource.indexOf('function buildRd15NativePresentationHtml()'));
  assert.match(harnessSource, /productIpcUsed: false/u);
  assert.match(harnessSource, /dummyInputsOnly: true/u);
  assert.match(harnessSource, /rendererReceivesPrivilegedValues: false/u);
  assert.match(harnessSource, /window\.webContents\.executeJavaScript/u);
  assert.doesNotMatch(rd15MirrorSource, /ipcRenderer/u);
  assert.doesNotMatch(rd15MirrorSource, /lineupDesktop/u);
  assert.doesNotMatch(rd15MirrorSource, /native-helper/u);
  assert.doesNotMatch(rd15MirrorSource, /tokenized/u);
  assert.doesNotMatch(rd15MirrorSource, /X-Plex/u);
  assert.deepEqual(scanForbiddenEvidenceContent(JSON.stringify({
    observations: summarizeRd15NativePresentationProofs(new Map(rd15NativePresentationProofs.map((proof) => [
      proof,
      new Map([
        ['windowed', {
          visiblePixelsObserved: true,
          markerPixelsObserved: true,
          rendererPixelsObserved: true,
          ...(proof === 'rd15-ui-focus' ? { focused: true } : {}),
        }],
        ['fullscreen', {
          visiblePixelsObserved: true,
          markerPixelsObserved: true,
          desktopPixelsObserved: true,
          ...(proof === 'rd15-ui-focus' ? { focused: true } : {}),
        }],
      ]),
    ]))),
    policy: {
      productIpcUsed: false,
      dummyInputsOnly: true,
      rawUrlsPersisted: false,
      rawLocalPathsPersisted: false,
      rawNativeValuesPersisted: false,
    },
  })), []);
});

test('scanForbiddenEvidenceContent catches raw paths, URLs, native values, and secret-shaped fields', () => {
  assert.deepEqual(scanForbiddenEvidenceContent('dummy inputs only and private-stdio-once'), []);
  assert.ok(scanForbiddenEvidenceContent(`${['ht', 'tp'].join('')}://127.0.0.1:34567/dummy.wav`).includes('raw-url'));
  assert.ok(scanForbiddenEvidenceContent(`C:${'\\'}Users${'\\'}example${'\\'}dummy.wav`).includes('windows-local-path'));
  assert.ok(scanForbiddenEvidenceContent('hwnd <redacted>').includes('native-value'));
  assert.ok(scanForbiddenEvidenceContent(`${['Author', 'ization'].join('')}: sample`).includes('raw-auth-field'));
  assert.ok(scanForbiddenEvidenceContent(`${['X-Plex', 'Token'].join('-')}: sample`).includes('plex-field'));
});
