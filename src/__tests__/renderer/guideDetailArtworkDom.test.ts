import assert from 'node:assert/strict';
import test from 'node:test';

import type { ArtworkRef } from '../../contracts/artwork.js';
import { createEpgGuideView, createEpgState } from '../../renderer/epg.js';
import { renderEpgGuideDom, renderGuideDetailArtwork } from '../../renderer/epg/guideDom.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { mountStaticRendererDom } from '../../renderer/staticDom.js';
import type { RouteWorkflowViewModel } from '../../renderer/workflow.js';
import { cssDeclaration, extractCssRule, normalizeCss } from './cssTestUtils.js';

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

function render(artwork: ArtworkRef | null, generation = 1) {
  const nowMs = 1_000;
  const presentation = {
    nowMs,
    channels: [{
      id: 'channel-1', number: '1', name: 'Channel One', programs: [{
        id: 'program-1', title: 'Program One', subtitle: '', description: 'Description',
        showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [],
        startsAtMs: nowMs, endsAtMs: nowMs + 60_000, artwork,
      }],
    }],
    nowWatching: null,
  };
  const guide = createEpgGuideView(createEpgState(presentation, generation), presentation);
  const figure = new FakeElement();
  const image = new FakeImage();
  const placeholder = new FakeElement();
  const dom = {
    epgDetailArtworkElement: figure,
    epgDetailPosterElement: image,
    epgDetailArtworkPlaceholderElement: placeholder,
  } as unknown as Pick<RendererDomBindings,
    'epgDetailArtworkElement' | 'epgDetailPosterElement' | 'epgDetailArtworkPlaceholderElement'>;
  const view = { guide } as unknown as RouteWorkflowViewModel;
  renderGuideDetailArtwork(view, dom);
  return { view, dom, figure, image, placeholder };
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
  assert.equal(guide.match(/data-epg-detail-artwork-placeholder(?:\s|>)/gu)?.length, 1);
  assert.equal(guide.match(/data-epg-detail-description(?:\s|>)/gu)?.length, 1);
  assert.match(guide, /data-epg-detail-artwork-placeholder aria-hidden="true"/u);
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
  const normalized = normalizeCss(css);
  const reducedArtwork = extractCssRule(normalized, '[data-epg-detail-artwork]', {
    atRule: '@media (prefers-reduced-motion: reduce)',
  });
  const reducedPoster = extractCssRule(normalized, '[data-epg-detail-poster]', {
    atRule: '@media (prefers-reduced-motion: reduce)',
  });
  assert.equal(cssDeclaration(reducedArtwork, 'animation'), 'none !important');
  assert.equal(cssDeclaration(reducedArtwork, 'transition'), 'none !important');
  assert.equal(cssDeclaration(reducedPoster, 'animation'), 'none !important');
  assert.equal(cssDeclaration(reducedPoster, 'transition'), 'none !important');

  const forcedArtwork = extractCssRule(normalized, '[data-epg-detail-artwork]', {
    atRule: '@media (forced-colors: active)',
  });
  const forcedPlaceholder = extractCssRule(normalized, '[data-epg-detail-artwork-placeholder]', {
    atRule: '@media (forced-colors: active)',
  });
  assert.equal(cssDeclaration(forcedArtwork, 'border-color'), 'CanvasText');
  assert.equal(cssDeclaration(forcedArtwork, 'outline'), '1px solid CanvasText');
  assert.equal(cssDeclaration(forcedArtwork, 'background'), 'Canvas');
  assert.equal(cssDeclaration(forcedPlaceholder, 'color'), 'CanvasText');
});
