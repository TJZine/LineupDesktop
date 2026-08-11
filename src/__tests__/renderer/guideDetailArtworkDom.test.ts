import assert from 'node:assert/strict';
import test from 'node:test';

import type { ArtworkRef } from '../../contracts/artwork.js';
import { createEpgGuideView, createEpgState } from '../../renderer/epg.js';
import { renderEpgGuideDom, renderGuideDetailArtwork } from '../../renderer/epg/guideDom.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import type { RouteWorkflowViewModel } from '../../renderer/workflow.js';
import {
  cssDeclaration,
  extractCssAtRuleBody,
  extractCssRule,
} from './cssAtRuleTestUtils.js';

class FakeElement {
  readonly dataset: Record<string, string> = {};
  readonly attributes = new Map<string, string>();
  hidden = false;
  textContent = '';
  setAttribute(name: string, value: string): void { this.attributes.set(name, value); }
}

class FakeImage extends FakeElement {
  alt = '';
  decoding = '';
  draggable = true;
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  get src(): string { return this.attributes.get('src') ?? ''; }
  set src(value: string) { this.attributes.set('src', value); }
  getAttribute(name: string): string | null { return this.attributes.get(name) ?? null; }
  removeAttribute(name: string): void { this.attributes.delete(name); }
}

function render(poster: ArtworkRef | null, generation = 1, background: ArtworkRef | null = null) {
  const nowMs = 1_000;
  const presentation = {
    nowMs,
    channels: [{
      id: 'channel-1', number: '1', name: 'Channel One', programs: [{
        id: 'program-1', title: 'Program One', subtitle: '', description: 'Description',
        showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [],
        startsAtMs: nowMs, endsAtMs: nowMs + 60_000,
        artwork: { poster, background, logo: null },
      }],
    }],
    nowWatching: null,
  };
  const guide = createEpgGuideView(createEpgState(presentation, generation, 'wide'), presentation);
  const figure = new FakeElement();
  const image = new FakeImage();
  const placeholder = new FakeElement();
  const backgroundSurface = new FakeElement();
  const backgroundImage = new FakeImage();
  const dom = {
    epgDetailBackgroundElement: backgroundSurface,
    epgDetailBackgroundImageElement: backgroundImage,
    epgDetailArtworkElement: figure,
    epgDetailPosterElement: image,
    epgDetailArtworkPlaceholderElement: placeholder,
  } as unknown as Pick<RendererDomBindings,
    'epgDetailBackgroundElement' | 'epgDetailBackgroundImageElement' |
    'epgDetailArtworkElement' | 'epgDetailPosterElement' | 'epgDetailArtworkPlaceholderElement'>;
  const view = { guide } as unknown as RouteWorkflowViewModel;
  renderGuideDetailArtwork(view, dom);
  return { view, dom, figure, image, placeholder, backgroundSurface, backgroundImage };
}

test('detail poster owns loading, available, error, and same-generation no-loop states', () => {
  const artwork = {
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster' as const, expiresAtMs: 2_000,
    altText: '', status: 'available' as const,
  };
  const harness = render(artwork);
  assert.equal(harness.figure.dataset.artworkState, 'loading');
  assert.equal(harness.placeholder.textContent, 'Loading artwork…');
  assert.equal(harness.image.src, 'lineup://shell/artwork/artwork-ABCDEFGHIJKLMNOP');
  assert.equal(harness.image.alt, 'Poster for Program One');
  harness.image.onload?.();
  assert.equal(harness.figure.dataset.artworkState, 'available');

  const failed = render(artwork);
  failed.image.onerror?.();
  assert.equal(failed.figure.dataset.artworkState, 'error');
  assert.equal(failed.placeholder.textContent, 'Artwork unavailable');
  assert.equal(failed.image.getAttribute('src'), null);
  renderGuideDetailArtwork(failed.view, failed.dom);
  assert.equal(failed.figure.dataset.artworkState, 'error');
  assert.equal(failed.image.getAttribute('src'), null);

  const retriedView = {
    ...failed.view,
    guide: { ...failed.view.guide, presentationGeneration: 2,
      infoPanel: failed.view.guide.infoPanel === null ? null : {
        ...failed.view.guide.infoPanel, presentationGeneration: 2,
      } },
  };
  renderGuideDetailArtwork(retriedView, failed.dom);
  assert.equal(failed.figure.dataset.artworkState, 'loading');
  assert.equal(failed.image.src, 'lineup://shell/artwork/artwork-ABCDEFGHIJKLMNOP');
});

test('stale load and error callbacks cannot mutate a replacement artwork request', () => {
  const first = { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster' as const, expiresAtMs: 2_000, altText: 'First', status: 'available' as const };
  const second = { ...first, id: 'artwork-QRSTUVWXYZabcdef', altText: 'Second' };
  const harness = render(first);
  const staleLoad = harness.image.onload;
  const staleError = harness.image.onerror;
  const replacement = render(second, 2).view;
  renderGuideDetailArtwork(replacement, harness.dom);
  staleLoad?.();
  staleError?.();
  assert.equal(harness.figure.dataset.artworkState, 'loading');
  assert.equal(harness.image.src, 'lineup://shell/artwork/artwork-QRSTUVWXYZabcdef');
  harness.image.onload?.();
  assert.equal(harness.figure.dataset.artworkState, 'available');
});

test('selected background fetches independently and keeps the decorative surface inaccessible', () => {
  const harness = render(
    { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 2_000, altText: 'Poster', status: 'available' },
    1,
    { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background', expiresAtMs: 2_000, altText: 'Background', status: 'available' },
  );
  assert.equal(harness.backgroundSurface.dataset.backgroundState, 'loading');
  assert.equal(harness.backgroundSurface.dataset.backgroundSource, 'background');
  assert.equal(harness.backgroundImage.src, 'lineup://shell/artwork/artwork-QRSTUVWXYZabcdef');
  assert.equal(harness.backgroundImage.alt, '');
  assert.equal(harness.backgroundSurface.attributes.get('aria-hidden'), 'true');
  assert.equal(harness.backgroundImage.attributes.get('aria-hidden'), 'true');
  assert.equal(harness.backgroundImage.dataset.artworkRefId, 'artwork-QRSTUVWXYZabcdef');
  harness.backgroundImage.onload?.();
  assert.equal(harness.backgroundSurface.dataset.backgroundState, 'available');
  assert.equal(harness.backgroundImage.hidden, false);
  assert.equal(harness.image.src, 'lineup://shell/artwork/artwork-ABCDEFGHIJKLMNOP');
});

test('background failure falls back once to the selected poster treatment, then to theme without retry loops', () => {
  const withPoster = render(
    { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 2_000, altText: 'Poster', status: 'available' },
    1,
    { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background', expiresAtMs: 2_000, altText: 'Background', status: 'available' },
  );
  withPoster.backgroundImage.onerror?.();
  assert.equal(withPoster.backgroundSurface.dataset.backgroundState, 'poster-fallback');
  assert.equal(withPoster.backgroundSurface.dataset.backgroundSource, 'poster');
  assert.equal(withPoster.backgroundSurface.dataset.backgroundFallback, 'poster');
  assert.equal(withPoster.backgroundSurface.dataset.backgroundCause, 'error');
  assert.equal(withPoster.backgroundImage.getAttribute('src'), null);
  assert.equal(withPoster.backgroundImage.onload, null);
  assert.equal(withPoster.backgroundImage.onerror, null);
  assert.equal(withPoster.backgroundImage.alt, '');
  assert.equal(withPoster.backgroundImage.dataset.artworkRefId, undefined);
  assert.equal(withPoster.backgroundImage.dataset.artworkGeneration, undefined);
  renderGuideDetailArtwork(withPoster.view, withPoster.dom);
  assert.equal(withPoster.backgroundSurface.dataset.backgroundState, 'poster-fallback');
  assert.equal(withPoster.backgroundSurface.dataset.backgroundSource, 'poster');
  assert.equal(withPoster.backgroundImage.getAttribute('src'), null);

  const themeOnly = render(
    null,
    1,
    { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background', expiresAtMs: 2_000, altText: 'Background', status: 'available' },
  );
  themeOnly.backgroundImage.onerror?.();
  assert.equal(themeOnly.backgroundSurface.dataset.backgroundState, 'error');
  assert.equal(themeOnly.backgroundSurface.dataset.backgroundSource, 'theme');
  assert.equal(themeOnly.backgroundImage.getAttribute('src'), null);
});

test('background failures stay suppressed across same-generation selection churn but retry in a new generation', () => {
  const poster = { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster' as const, expiresAtMs: 2_000, altText: 'Poster', status: 'available' as const };
  const backgroundA = { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background' as const, expiresAtMs: 2_000, altText: 'A', status: 'available' as const };
  const backgroundB = { id: 'artwork-zyxwvutsrqponmlk', kind: 'background' as const, expiresAtMs: 2_000, altText: 'B', status: 'available' as const };

  const missingChurn = render(poster, 1, backgroundA);
  missingChurn.backgroundImage.onerror?.();
  renderGuideDetailArtwork(render(poster, 1, null).view, missingChurn.dom);
  renderGuideDetailArtwork(render(poster, 1, backgroundB).view, missingChurn.dom);
  missingChurn.backgroundImage.onerror?.();
  renderGuideDetailArtwork(render(poster, 1, backgroundA).view, missingChurn.dom);
  assert.equal(missingChurn.backgroundSurface.dataset.backgroundState, 'poster-fallback');
  assert.equal(missingChurn.backgroundImage.getAttribute('src'), null);
  assert.equal(missingChurn.backgroundImage.onload, null);

  const repeatedFailure = render(poster, 1, backgroundA);
  repeatedFailure.backgroundImage.onerror?.();
  renderGuideDetailArtwork(render(poster, 1, backgroundB).view, repeatedFailure.dom);
  repeatedFailure.backgroundImage.onerror?.();
  renderGuideDetailArtwork(render(poster, 1, backgroundA).view, repeatedFailure.dom);
  assert.equal(repeatedFailure.backgroundImage.getAttribute('src'), null);
  assert.equal(repeatedFailure.backgroundImage.onload, null);

  const newGeneration = render(poster, 1, backgroundA);
  newGeneration.backgroundImage.onerror?.();
  renderGuideDetailArtwork(render(poster, 2, backgroundA).view, newGeneration.dom);
  assert.equal(newGeneration.backgroundImage.src, 'lineup://shell/artwork/artwork-QRSTUVWXYZabcdef');
  assert.notEqual(newGeneration.backgroundImage.onload, null);
  newGeneration.backgroundImage.onload?.();
  assert.equal(newGeneration.backgroundSurface.dataset.backgroundState, 'available');
});

test('missing, placeholder, and expired backgrounds use poster or theme fallback without filling the poster slot', () => {
  const poster = { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster' as const, expiresAtMs: 2_000, altText: 'Poster', status: 'available' as const };
  for (const background of [
    null,
    { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background' as const, expiresAtMs: 2_000, altText: 'Background', status: 'placeholder' as const },
    { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background' as const, expiresAtMs: 999, altText: 'Background', status: 'available' as const },
  ]) {
    const harness = render(poster, 1, background);
    assert.equal(harness.backgroundSurface.dataset.backgroundState, 'poster-fallback');
    assert.equal(harness.backgroundSurface.dataset.backgroundSource, 'poster');
    assert.equal(harness.backgroundImage.getAttribute('src'), null);
    assert.equal(harness.image.src, 'lineup://shell/artwork/artwork-ABCDEFGHIJKLMNOP');
  }

  const theme = render(null);
  assert.equal(theme.backgroundSurface.dataset.backgroundState, 'missing');
  assert.equal(theme.backgroundSurface.dataset.backgroundSource, 'theme');
  assert.equal(theme.backgroundImage.getAttribute('src'), null);
  assert.equal(theme.image.getAttribute('src'), null);

  const backgroundOnly = render(null, 1, {
    id: 'artwork-QRSTUVWXYZabcdef', kind: 'background', expiresAtMs: 2_000,
    altText: 'Background', status: 'available',
  });
  assert.equal(backgroundOnly.backgroundSurface.dataset.backgroundState, 'loading');
  assert.equal(backgroundOnly.backgroundImage.src, 'lineup://shell/artwork/artwork-QRSTUVWXYZabcdef');
  assert.equal(backgroundOnly.image.getAttribute('src'), null);
});

test('null logo keeps the title-text fallback and never creates a logo request', () => {
  const harness = render(null);
  const title = new FakeElement();
  renderEpgGuideDom(harness.view, {
    ...harness.dom,
    epgDetailTitleElement: title,
    epgDetailChannelElement: null,
    epgDetailTimeElement: null,
    epgDetailDescriptionElement: null,
    epgGridElement: null,
  } as unknown as RendererDomBindings);
  assert.equal(harness.view.guide.infoPanel?.artwork.logo, null);
  assert.equal(title.textContent, 'Program One');
  assert.equal(harness.image.getAttribute('src'), null);
  assert.equal(harness.backgroundImage.getAttribute('src'), null);
});

test('stale background callbacks cannot mutate a replacement generation or reference', () => {
  const first = render(
    { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 2_000, altText: 'Poster', status: 'available' },
    1,
    { id: 'artwork-QRSTUVWXYZabcdef', kind: 'background', expiresAtMs: 2_000, altText: 'First', status: 'available' },
  );
  const staleLoad = first.backgroundImage.onload;
  const staleError = first.backgroundImage.onerror;
  const replacement = render(
    { id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 2_000, altText: 'Poster', status: 'available' },
    2,
    { id: 'artwork-zyxwvutsrqponmlk', kind: 'background', expiresAtMs: 2_000, altText: 'Second', status: 'available' },
  ).view;
  renderGuideDetailArtwork(replacement, first.dom);
  staleLoad?.();
  staleError?.();
  assert.equal(first.backgroundSurface.dataset.backgroundState, 'loading');
  assert.equal(first.backgroundImage.src, 'lineup://shell/artwork/artwork-zyxwvutsrqponmlk');
  first.backgroundImage.onload?.();
  assert.equal(first.backgroundSurface.dataset.backgroundState, 'available');
});

test('error cleanup removes request identity, handlers, source, and alt text', () => {
  const harness = render({
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 2_000,
    altText: 'Poster', status: 'available',
  });
  harness.image.onerror?.();
  assert.equal(harness.image.getAttribute('src'), null);
  assert.equal(harness.image.alt, '');
  assert.equal(harness.image.dataset.artworkRefId, undefined);
  assert.equal(harness.image.dataset.artworkGeneration, undefined);
  assert.equal(harness.image.onload, null);
  assert.equal(harness.image.onerror, null);
});

test('detail copy is clamped at its renderer boundary', () => {
  const harness = render(null);
  const title = new FakeElement();
  const description = new FakeElement();
  const view = {
    ...harness.view,
    guide: {
      ...harness.view.guide,
      infoPanel: { ...harness.view.guide.infoPanel!, title: 'T'.repeat(200), description: 'D'.repeat(700) },
    },
  };
  renderEpgGuideDom(view, {
    ...harness.dom,
    epgDetailTitleElement: title,
    epgDetailDescriptionElement: description,
    epgDetailChannelElement: null,
    epgDetailTimeElement: null,
    epgGridElement: null,
  } as unknown as RendererDomBindings);
  assert.equal(title.textContent.length, 160);
  assert.equal(description.textContent.length, 600);
});

test('null, placeholder, and expired artwork render the fixed missing state', () => {
  const missing = render(null);
  assert.equal(missing.figure.dataset.artworkState, 'missing');
  assert.equal(missing.placeholder.textContent, 'Artwork unavailable');
  const placeholder = render({
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 2_000,
    altText: '', status: 'placeholder',
  });
  assert.equal(placeholder.figure.dataset.artworkState, 'missing');
  assert.equal(placeholder.placeholder.textContent, 'Artwork unavailable');
  const expired = render({
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 999,
    altText: '', status: 'available',
  });
  assert.equal(expired.figure.dataset.artworkState, 'missing');
  assert.equal(expired.placeholder.textContent, 'Artwork unavailable');

  const backgroundOnly = render(null, 1, {
    id: 'artwork-QRSTUVWXYZabcdef', kind: 'background', expiresAtMs: 2_000,
    altText: 'Background', status: 'available',
  });
  assert.equal(backgroundOnly.figure.dataset.artworkState, 'missing');
  assert.equal(backgroundOnly.image.getAttribute('src'), null);
});

test('fixed Classic markup owns exactly one poster, placeholder, copy, and description surface', () => {
  const root = { innerHTML: '', querySelector: () => null };
  const documentDouble = {
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  };
  mountStaticRendererDom(documentDouble as unknown as Document);
  const guideStart = root.innerHTML.indexOf('<section id="screen-guide"');
  const guideEnd = root.innerHTML.indexOf('<section id="screen-settings"', guideStart);
  const guide = root.innerHTML.slice(guideStart, guideEnd);
  assert.equal(guide.match(/data-epg-detail-artwork(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-poster(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-background(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-background-image(?:\s|>)/gu)?.length, 1);
  assert.doesNotMatch(guide, /data-epg-detail-logo/u);
  assert.equal(guide.match(/data-epg-detail-artwork-placeholder(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-description(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-eyebrow(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-subtitle(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-badges(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-genres(?:\s|>)/gu)?.length, 1);
  assert.match(guide, /data-guide-info-panel[^>]+aria-live="polite"/u);
  assert.match(guide, /data-epg-detail-title[^>]+data-title-fallback="text"/u);
  assert.match(guide, /data-guide-layout="classic"/u);
  assert.match(guide, /data-epg-detail-artwork-placeholder aria-hidden="true"/u);
  assert.match(guide, /data-epg-detail-background[^>]+aria-hidden="true"/u);
  assert.match(guide, /data-epg-detail-background-image[^>]+aria-hidden="true"/u);
  assert.match(guide, /class="guide-detail__copy"/u);
});

test('artwork accessibility styles disable motion and preserve forced-color boundaries', () => {
  const processValue = Reflect.get(globalThis, 'process') as {
    getBuiltinModule(name: string): { readFileSync(path: URL, encoding: 'utf8'): string };
  };
  const css = processValue.getBuiltinModule('node:fs').readFileSync(
    new URL('../../renderer/styles/guide-epg.css', import.meta.url),
    'utf8',
  );
  const reducedMotion = extractCssAtRuleBody(css, '@media (prefers-reduced-motion: reduce)');
  const forcedColors = extractCssAtRuleBody(css, '@media (forced-colors: active)');
  const reducedArtwork = extractCssRule(reducedMotion ?? '', [
    '[data-epg-detail-artwork]',
    '[data-epg-detail-poster]',
    '[data-epg-detail-background]',
    '[data-epg-detail-background-image]',
  ]);
  assert.equal(cssDeclaration(reducedArtwork, 'animation'), 'none !important');
  assert.equal(cssDeclaration(reducedArtwork, 'transition'), 'none !important');

  const forcedArtwork = extractCssRule(forcedColors ?? '', '[data-epg-detail-artwork]');
  assert.equal(cssDeclaration(forcedArtwork, 'border-color'), 'CanvasText');
  assert.equal(cssDeclaration(forcedArtwork, 'outline'), '1px solid CanvasText');
  assert.equal(cssDeclaration(forcedArtwork, 'background'), 'Canvas');

  const forcedBackground = extractCssRule(forcedColors ?? '', '[data-epg-detail-background]');
  assert.equal(cssDeclaration(forcedBackground, 'background'), 'Canvas');
  const forcedBackgroundImage = extractCssRule(forcedColors ?? '', '[data-epg-detail-background-image]');
  assert.equal(cssDeclaration(forcedBackgroundImage, 'display'), 'none');
  const forcedBackgroundScrim = extractCssRule(forcedColors ?? '', '[data-epg-detail-background]::after');
  assert.equal(cssDeclaration(forcedBackgroundScrim, 'display'), 'none');

  const forcedPlaceholder = extractCssRule(forcedColors ?? '', '[data-epg-detail-artwork-placeholder]');
  assert.equal(cssDeclaration(forcedPlaceholder, 'color'), 'CanvasText');

  const metadata = extractCssRule(css, '.guide-detail__badges');
  assert.equal(cssDeclaration(metadata, 'display'), 'flex');
  const badge = extractCssRule(css, '.guide-detail__badges > span');
  assert.equal(cssDeclaration(badge, 'border'), '1px solid var(--osd-pill-border)');
  const currentRail = extractCssRule(css, '.epg-grid__row[data-current-channel="true"] .epg-grid__channel');
  assert.equal(cssDeclaration(currentRail, 'border-inline-start'), '3px solid var(--color-primary)');
  const markerLabel = extractCssRule(css, '.epg-current-time-marker-label');
  assert.equal(cssDeclaration(markerLabel, 'font-size'), '9px');
});

test('CSS media assertions stay contained within the matched at-rule body', () => {
  const body = extractCssAtRuleBody(
    '@media (forced-colors: active) {} [data-epg-detail-artwork] { background: Canvas; }',
    '@media (forced-colors: active)',
  );
  assert.equal(body, '');
  assert.doesNotMatch(body ?? '', /\[data-epg-detail-artwork\]/u);
});
