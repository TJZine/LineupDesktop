import test from 'node:test';
import assert from 'node:assert/strict';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import { projectNativePlayerPresentationMode } from '../../renderer/guidePresentation.js';
import {
  cssDeclaration,
  containsCssSelector,
  extractCssAtRuleBody,
  extractCssRule,
} from './cssAtRuleTestUtils.js';

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
  assert.equal((root.innerHTML.match(/data-epg-detail-background(?:\s|>)/gu) ?? []).length, 1);
  assert.equal((root.innerHTML.match(/data-epg-detail-background-image(?:\s|>)/gu) ?? []).length, 1);
  assert.doesNotMatch(root.innerHTML, /data-epg-detail-logo/u);
  const detailStart = root.innerHTML.indexOf('class="guide-detail"');
  const gridStart = root.innerHTML.indexOf('id="guide-grid"');
  assert.ok(detailStart >= 0 && detailStart < gridStart, 'detail surface precedes the grid shell');
  assert.match(root.innerHTML, /class="screen-stack" data-static-screens-mounted/u);
  assert.doesNotMatch(root.innerHTML, /class="screen-stack"[^>]*aria-live=/u);
  assert.match(root.innerHTML, /class="guide-detail"[^>]+data-guide-layout="classic"/u);
  assert.match(root.innerHTML, /id="guide-grid"[^>]+role="grid"[^>]+aria-label="Guide schedule grid"/u);
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
  for (const selector of [
    ':root[data-native-presentation-aperture="open"]',
    ':root[data-native-presentation-aperture="open"] body',
    ':root[data-native-presentation-aperture="open"] .app-shell',
    ':root[data-native-presentation-aperture="open"] [data-static-screen-root]',
    ':root[data-native-presentation-aperture="open"] .screen-stack',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(base, selector), 'background'), 'transparent');
  }

  for (const selector of [
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="player-full"] .screen[data-screen="player"]',
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="guide-overlay-full"] .screen[data-screen="guide"]',
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="guide-classic-pip"] .screen[data-screen="guide"]',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(base, selector), 'background'), 'transparent');
  }

  const root = extractCssRule(base, ':root');
  assert.equal(cssDeclaration(root, 'background'), 'var(--color-app-bg)');

  const classicPip = extractCssRule(
    guide,
    ':root[data-native-presentation-mode="guide-classic-pip"] .epg-shell[data-epg-layout="classic"]',
  );
  assert.equal(
    cssDeclaration(classicPip, 'padding-inline-end'),
    'calc(var(--native-pip-width) + (var(--native-pip-inset) * 2))',
  );
  const classicDetailPip = extractCssRule(
    guide,
    ':root[data-native-presentation-mode="guide-classic-pip"] .guide-detail[data-guide-layout="classic"]',
  );
  assert.equal(
    cssDeclaration(classicDetailPip, 'margin-inline-end'),
    'calc(var(--native-pip-width) + (var(--native-pip-inset) * 2))',
  );
  assert.equal(containsCssSelector(guide, '.epg-shell[data-epg-layout="classic"]'), false);

  const classicAperture = extractCssRule(
    guide,
    ':root[data-native-presentation-aperture="open"][data-native-presentation-mode="guide-classic-pip"] .screen[data-screen="guide"] .screen__content',
  );
  const classicBackground = cssDeclaration(classicAperture, 'background');
  assert.ok(classicBackground?.includes('linear-gradient(var(--color-surface), var(--color-surface)) left'));
  assert.ok(classicBackground?.includes('linear-gradient(var(--color-surface), var(--color-surface)) right top'));
  assert.ok(classicBackground?.includes('linear-gradient(var(--color-surface), var(--color-surface)) right bottom'));
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
  const presentationSurface = extractCssRule(forcedColors ?? '', '[data-player-presentation-surface]');
  assert.equal(cssDeclaration(presentationSurface, 'background'), 'Canvas');
  assert.equal(containsCssSelector(forcedColors ?? '', '.player-surface'), false);
});

test('Guide time range no longer compresses row geometry', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const guide = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/guide-epg.css', import.meta.url),
    'utf8',
  );
  assert.equal(containsCssSelector(guide, '.epg-grid__channel[data-channel-current="true"]::before'), false);
  assert.equal(containsCssSelector(guide, '.epg-grid__channel[data-channel-tuned="true"]::after'), false);
  assert.equal(cssDeclaration(extractCssRule(guide, '.epg-grid__channel-status'), 'content'), null);
  const shell = extractCssRule(guide, '.epg-shell');
  assert.equal(cssDeclaration(shell, '--guide-row-height'), '108px');
  const comfortable = extractCssRule(guide, '.epg-shell[data-guide-row-density-effective="comfortable"]');
  assert.equal(cssDeclaration(comfortable, '--guide-row-height'), '108px');
  const compact = extractCssRule(guide, '.epg-shell[data-guide-row-density-effective="compact"]');
  assert.equal(cssDeclaration(compact, '--guide-row-height'), '72px');
  for (const selector of [
    '.epg-shell[data-guide-row-density-effective="compact"] .epg-cell-subtitle',
    '.epg-shell[data-guide-row-density-effective="compact"] .epg-badge--episode',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(guide, selector), 'display'), 'none');
  }
  const channel = extractCssRule(guide, '.epg-grid__channel');
  assert.equal(cssDeclaration(channel, 'height'), 'var(--guide-row-height)');
  assert.equal(cssDeclaration(channel, 'box-sizing'), 'border-box');
  const grid = extractCssRule(guide, '.epg-grid');
  assert.equal(cssDeclaration(grid, 'overflow'), 'auto');
  const bufferRow = extractCssRule(guide, '.epg-grid__row--buffer');
  assert.equal(cssDeclaration(bufferRow, 'visibility'), 'hidden');
  assert.equal(cssDeclaration(bufferRow, 'pointer-events'), 'none');
  const reducedMotion = extractCssAtRuleBody(guide, '@media (prefers-reduced-motion: reduce)');
  const reducedSelected = extractCssRule(
    reducedMotion ?? '',
    '.epg-grid__program[data-selected-program="true"] .epg-cell-title',
  );
  assert.equal(cssDeclaration(reducedSelected, 'animation'), 'none !important');
  const forcedColors = extractCssAtRuleBody(guide, '@media (forced-colors: active)');
  const forcedBackground = extractCssRule(forcedColors ?? '', '[data-epg-detail-background-image]');
  assert.equal(cssDeclaration(forcedBackground, 'display'), 'none');
});

test('Guide Classic and Overlay owners expose explicit shell, rail, and marker roles', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const guide = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/guide-epg.css', import.meta.url),
    'utf8',
  );
  for (const selector of [
    '.epg-shell[data-epg-layout="overlay"] .epg-classic-header',
    '.epg-shell[data-epg-layout="classic"] .epg-now-watching-banner',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(guide, selector), 'display'), 'none');
  }
  const currentCell = extractCssRule(guide, '.epg-grid__program[data-temporal-state="current"]');
  assert.equal(cssDeclaration(currentCell, 'border-color'), 'var(--color-focus-border)');
  const upcomingCell = extractCssRule(guide, '.epg-grid__program[data-temporal-state="upcoming"]');
  assert.equal(cssDeclaration(upcomingCell, 'border-color'), 'var(--color-border-strong)');
  for (const [selector, outline] of [
    ['.epg-grid__program:focus-visible', 'var(--focus-ring-width) solid var(--color-focus)'],
    ['.epg-grid__program.is-focused', 'var(--focus-ring-width) solid var(--color-focus)'],
    ['.epg-library-tab:focus-visible', '3px solid Highlight'],
    ['.epg-library-tab.is-focused', 'var(--focus-ring-width) solid var(--color-focus)'],
  ] as const) {
    assert.equal(
      cssDeclaration(extractCssRule(guide, selector), 'outline'),
      outline,
    );
  }
  const past = extractCssRule(guide, '.epg-grid__program[data-temporal-state="past"]');
  assert.equal(cssDeclaration(past, 'opacity'), '0.62');
  for (const selector of [
    '.epg-grid__program[data-temporal-state="past"][data-selected-program="true"]',
    '.epg-grid__program[data-temporal-state="past"]:focus-visible',
    '.epg-grid__program[data-temporal-state="past"].is-focused',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(guide, selector), 'opacity'), '1');
  }
  const forcedColors = extractCssAtRuleBody(guide, '@media (forced-colors: active)');
  for (const selector of [
    '.epg-grid__program[data-temporal-state="past"][data-selected-program="true"]',
    '.epg-grid__program[data-temporal-state="past"]:focus-visible',
    '.epg-grid__program[data-temporal-state="past"].is-focused',
  ]) {
    assert.equal(cssDeclaration(extractCssRule(forcedColors ?? '', selector), 'opacity'), '1');
  }
});
