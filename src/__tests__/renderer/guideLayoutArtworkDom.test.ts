import test from 'node:test';
import assert from 'node:assert/strict';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import { projectNativePlayerPresentationMode } from '../../renderer/guidePresentation.js';

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

  assert.match(base, /:root\[data-native-presentation-aperture="open"\],\s*:root\[data-native-presentation-aperture="open"\] body,[\s\S]*?\.screen-stack \{\s*background: transparent;/u);
  assert.match(base, /data-native-presentation-aperture="open"\]\[data-native-presentation-mode="player-full"\][\s\S]*?\.screen\[data-screen="player"\]/u);
  assert.match(base, /data-native-presentation-aperture="open"\]\[data-native-presentation-mode="guide-overlay-full"\][\s\S]*?\.screen\[data-screen="guide"\]/u);
  assert.match(base, /data-native-presentation-aperture="open"\]\[data-native-presentation-mode="guide-classic-pip"\][\s\S]*?\.screen\[data-screen="guide"\]/u);
  assert.doesNotMatch(base, /:root\s*,\s*body\s*\{[^}]*background:\s*transparent/su);

  assert.match(guide, /:root\[data-native-presentation-mode="guide-classic-pip"\] \.epg-shell\[data-epg-layout="classic"\] \{\s*padding-right: calc\(var\(--native-pip-width\) \+ \(var\(--native-pip-inset\) \* 2\)\);/u);
  assert.doesNotMatch(guide, /^\.epg-shell\[data-epg-layout="classic"\]\s*\{\s*padding-right:/mu);
  const classicAperture = guide.slice(guide.indexOf(':root[data-native-presentation-aperture="open"]'));
  assert.match(classicAperture, /linear-gradient\(var\(--color-surface\), var\(--color-surface\)\) left/u);
  assert.match(classicAperture, /linear-gradient\(var\(--color-surface\), var\(--color-surface\)\) right top/u);
  assert.match(classicAperture, /linear-gradient\(var\(--color-surface\), var\(--color-surface\)\) right bottom/u);
});
