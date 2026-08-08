import test from 'node:test';
import assert from 'node:assert/strict';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import { projectNativePlayerPresentationMode } from '../../renderer/guidePresentation.js';
import { extractCssAtRuleBody } from './cssAtRuleTestUtils.js';

test('Guide layouts retain one artwork subtree and one native presentation aperture', () => {
  const root = {
    innerHTML: '',
    querySelector: () => null,
    querySelectorAll: () => [],
  };
  const documentRef = {
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document;
  mountStaticRendererDom(documentRef);
  assert.equal((root.innerHTML.match(/data-player-presentation-surface/gu) ?? []).length, 1);
  assert.equal((root.innerHTML.match(/data-epg-detail-artwork(?:\s|>)/gu) ?? []).length, 1);
  assert.equal((root.innerHTML.match(/data-epg-detail-poster/gu) ?? []).length, 1);
});

test('Classic is playing-only PIP while Overlay and Player remain full modes', () => {
  const snapshot = {
    requestId: 'media-1', status: 'playing' as const, media: null, capabilityProfileId: null,
    seekSupport: 'unknown' as const, positionMs: 0, durationMs: null, bufferedRanges: [], playing: true,
    volume: 1, muted: false, playbackRate: 1, selectedAudioTrackId: null, selectedSubtitleTrackId: null,
    selectedVideoTrackId: null, tracks: [], quality: { mode: 'unknown' as const, sourceDynamicRange: 'unknown' as const, outputDynamicRangeStatus: 'unknown' as const }, lastError: null,
  };
  const shell = { bootstrap: 'ready' as const, exitConfirmOpen: false, inlineError: null } as never;
  assert.equal(projectNativePlayerPresentationMode({ route: 'player', guideLayout: 'classic', snapshot, shell }), 'player-full');
  assert.equal(projectNativePlayerPresentationMode({ route: 'guide', guideLayout: 'overlay', snapshot, shell }), 'guide-overlay-full');
  assert.equal(projectNativePlayerPresentationMode({ route: 'guide', guideLayout: 'classic', snapshot, shell }), 'guide-classic-pip');
  assert.equal(projectNativePlayerPresentationMode({ route: 'guide', guideLayout: 'classic', snapshot: { ...snapshot, playing: false, status: 'paused' }, shell }), 'hidden');
});

test('native aperture CSS makes only acknowledged page compositions transparent and reserves exact Classic geometry', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const fs = processValue.getBuiltinModule('node:fs');
  const base = fs.readFileSync(new URL('../../renderer/styles/base.css', import.meta.url), 'utf8');
  const guide = fs.readFileSync(new URL('../../renderer/styles/guide-epg.css', import.meta.url), 'utf8');
  assert.match(
    base,
    /:root\[data-native-presentation-aperture="open"\],\s*:root\[data-native-presentation-aperture="open"\]\s+body,\s*:root\[data-native-presentation-aperture="open"\]\s+\.app-shell,\s*:root\[data-native-presentation-aperture="open"\]\s+\[data-static-screen-root\],\s*:root\[data-native-presentation-aperture="open"\]\s+\.screen-stack\s*\{\s*background:\s*transparent;\s*\}/u,
  );
  assert.match(
    base,
    /:root\[data-native-presentation-aperture="open"\]\[data-native-presentation-mode="player-full"\]\s*\.screen\[data-screen="player"\],\s*:root\[data-native-presentation-aperture="open"\]\[data-native-presentation-mode="guide-overlay-full"\]\s*\.screen\[data-screen="guide"\],\s*:root\[data-native-presentation-aperture="open"\]\[data-native-presentation-mode="guide-classic-pip"\]\s*\.screen\[data-screen="guide"\]\s*\{\s*background:\s*transparent;\s*\}/u,
  );
  assert.match(base, /:root\s*\{[^{}]*background:\s*var\(--color-app-bg\);/u);
  assert.doesNotMatch(base, /:root\s*\{[^{}]*background:\s*transparent;/u);

  assert.match(
    guide,
    /:root\[data-native-presentation-mode="guide-classic-pip"\]\s*\.epg-shell\[data-epg-layout="classic"\]\s*\{\s*padding-right:\s*calc\(var\(--native-pip-width\)\s*\+\s*\(var\(--native-pip-inset\)\s*\*\s*2\)\);\s*\}/u,
  );
  assert.doesNotMatch(guide, /^\.epg-shell\[data-epg-layout="classic"\]\s*\{[^{}]*padding-right:/mu);
  assert.match(
    guide,
    /:root\[data-native-presentation-aperture="open"\]\[data-native-presentation-mode="guide-classic-pip"\]\s+\.screen\[data-screen="guide"\]\s+\.screen__content\s*\{[^{}]*background:\s*linear-gradient\(var\(--color-surface\),\s*var\(--color-surface\)\) left[^{}]*,\s*linear-gradient\(var\(--color-surface\),\s*var\(--color-surface\)\) right top[^{}]*,\s*linear-gradient\(var\(--color-surface\),\s*var\(--color-surface\)\) right bottom[^{}]*;[^{}]*\}/u,
  );
});

test('forced-color player overlay CSS targets the semantic presentation surface', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const overlays = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/player-overlays.css', import.meta.url),
    'utf8',
  );
  const forcedColors = extractCssAtRuleBody(overlays, '@media (forced-colors: active)');
  assert.ok(forcedColors !== null);
  assert.match(
    forcedColors,
    /\[data-player-presentation-surface\]\s*\{[^{}]*background:\s*Canvas;[^{}]*\}/u,
  );
  assert.doesNotMatch(forcedColors, /\.player-surface\s*\{/u);
});

test('Guide density no longer compresses row geometry', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const guide = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/guide-epg.css', import.meta.url),
    'utf8',
  );
  assert.doesNotMatch(guide, /\.epg-shell\[data-guide-density="(?:compact|comfortable)"\]\s*\{/u);
  assert.doesNotMatch(guide, /--guide-row-height:\s*72px/u);
  assert.match(guide, /\.epg-grid__channel\s*\{[^{}]*height:\s*var\(--guide-row-height\);/u);
  assert.match(
    guide,
    /\.screen\[data-screen="guide"\]\s*\.epg-grid__program\s*\{[^{}]*top:\s*4px;[^{}]*bottom:\s*4px;[^{}]*padding:\s*var\(--space-2\)\s+var\(--space-4\);[^{}]*\}/u,
  );
});
