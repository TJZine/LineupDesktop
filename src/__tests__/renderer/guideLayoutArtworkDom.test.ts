import test from 'node:test';
import assert from 'node:assert/strict';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import { projectNativePlayerPresentationMode } from '../../renderer/guidePresentation.js';
import { cssDeclaration, extractCssRule, normalizeCss } from './cssTestUtils.js';

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
  const normalizedBase = normalizeCss(base);
  const normalizedGuide = normalizeCss(guide);
  const aperture = extractCssRule(normalizedBase, ':root[data-native-presentation-aperture="open"]');
  assert.equal(cssDeclaration(aperture, 'background'), 'transparent');
  for (const selector of [
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="player-full"] .screen[data-screen="player"]',
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="guide-overlay-full"] .screen[data-screen="guide"]',
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="guide-classic-pip"] .screen[data-screen="guide"]',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(normalizedBase, selector), 'background'), 'transparent');
  }
  assert.notEqual(cssDeclaration(extractCssRule(normalizedBase, ':root'), 'background'), 'transparent');

  const classicPip = extractCssRule(
    normalizedGuide,
    ':root[data-native-presentation-mode="guide-classic-pip"] .epg-shell[data-epg-layout="classic"]',
  );
  assert.equal(
    cssDeclaration(classicPip, 'padding-right'),
    'calc(var(--native-pip-width) + (var(--native-pip-inset) * 2))',
  );
  assert.equal(
    cssDeclaration(extractCssRule(normalizedGuide, '.epg-shell[data-epg-layout="classic"]'), 'padding-right'),
    null,
  );
  const classicAperture = extractCssRule(
    normalizedGuide,
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="guide-classic-pip"] .screen[data-screen="guide"] .screen__content',
  );
  const background = cssDeclaration(classicAperture, 'background');
  assert.ok(background?.includes('linear-gradient(var(--color-surface), var(--color-surface)) left'));
  assert.ok(background?.includes('linear-gradient(var(--color-surface), var(--color-surface)) right top'));
  assert.ok(background?.includes('linear-gradient(var(--color-surface), var(--color-surface)) right bottom'));
});

test('forced-color player overlay CSS targets the semantic presentation surface', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const overlays = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/player-overlays.css', import.meta.url),
    'utf8',
  );
  const forcedPresentation = extractCssRule(
    normalizeCss(overlays),
    '[data-player-presentation-surface]',
    { atRule: '@media (forced-colors: active)' },
  );
  assert.equal(cssDeclaration(forcedPresentation, 'background'), 'Canvas');
  assert.equal(
    extractCssRule(
      normalizeCss(overlays),
      '.player-surface',
      { atRule: '@media (forced-colors: active)' },
    ),
    null,
  );
});

test('Guide density no longer compresses row geometry', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const guide = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/guide-epg.css', import.meta.url),
    'utf8',
  );
  const normalized = normalizeCss(guide);
  assert.equal(extractCssRule(normalized, '.epg-shell[data-guide-density="compact"]'), null);
  assert.equal(extractCssRule(normalized, '.epg-shell[data-guide-density="comfortable"]'), null);
  assert.equal(normalized.includes('--guide-row-height: 72px'), false);
  assert.equal(cssDeclaration(extractCssRule(normalized, '.epg-grid__channel'), 'height'), 'var(--guide-row-height)');
  assert.equal(cssDeclaration(extractCssRule(normalized, '.screen[data-screen="guide"] .epg-grid__program'), 'top'), '4px');
  assert.equal(cssDeclaration(extractCssRule(normalized, '.screen[data-screen="guide"] .epg-grid__program'), 'bottom'), '4px');
  assert.equal(cssDeclaration(extractCssRule(normalized, '.screen[data-screen="guide"] .epg-grid__program'), 'padding'), 'var(--space-2) var(--space-4)');
});
