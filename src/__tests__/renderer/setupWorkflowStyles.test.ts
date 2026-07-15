import test from 'node:test';
import assert from 'node:assert/strict';

import { mountStaticRendererDom } from '../../renderer/staticDom.js';

test('setup workflow exposes the compact shared-panel composition hooks', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);

  const markup = root.innerHTML;
  assert.match(markup, /class="setup-workflow" data-setup-workspace/u);
  assert.match(markup, /class="setup-strategy-split"/u);
  assert.match(markup, /class="setup-strategy-rail"/u);
  assert.match(markup, /class="setup-preview-strip"/u);
  assert.match(markup, /class="setup-progress-bar" role="progressbar"/u);
  assert.match(markup, /class="setup-owner__body setup-review-layout"/u);
  assert.doesNotMatch(markup, /setup-centered|setup-owner--library|setup-owner--preview|setup-owner--build/u);
});

test('all three setup steps and Desktop-only extension labeling share the same owner shell', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);

  assert.match(root.innerHTML, /Step 1 of 3/u);
  assert.match(root.innerHTML, /Step 2 of 3/u);
  assert.match(root.innerHTML, /Step 3 of 3/u);
  assert.match(root.innerHTML, /class="setup-owner__title">Channel Setup/u);
  assert.match(root.innerHTML, /class="setup-owner__step">Desktop extension/u);
  assert.doesNotMatch(root.innerHTML, /Recently added/u);
});

test('setup owner grid reserves a status row only for the library owner', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);

  const library = setupOwnerMarkup(root.innerHTML, 'library');
  const progress = setupOwnerMarkup(root.innerHTML, 'progress');
  const result = setupOwnerMarkup(root.innerHTML, 'result');
  assertOwnerStructure(library, { status: true, bodyClass: 'setup-owner__body' });
  assertOwnerStructure(progress, { status: false, bodyClass: 'setup-owner__body setup-operation-state' });
  assertOwnerStructure(result, { status: false, bodyClass: 'setup-owner__body setup-operation-state' });
});

test('setup markup keeps primary Channel Setup titles with step and content below', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);
  for (const [owner, step] of [['library', 'Step 1 of 3'], ['preview', 'Step 2 of 3'], ['build', 'Step 3 of 3']] as const) {
    const ownerMarkup = setupOwnerMarkup(root.innerHTML, owner);
    assert.match(ownerMarkup, /<h2 class="setup-owner__title">Channel Setup<\/h2>/u);
    assert.match(ownerMarkup, new RegExp(`<span class="setup-owner__step">${step}<\\/span>`, 'u'));
    assert.match(ownerMarkup, /<div class="setup-owner__intro">/u);
  }
});

function setupOwnerMarkup(markup: string, owner: string): string {
  const marker = `data-staged-owner="${owner}"`;
  const start = markup.indexOf(marker);
  assert.notEqual(start, -1, `missing setup owner ${owner}`);
  const next = markup.indexOf('data-staged-owner="', start + marker.length);
  return markup.slice(start, next === -1 ? markup.length : next);
}

function assertOwnerStructure(
  markup: string,
  expected: { status: boolean; bodyClass: string },
): void {
  const headerIndex = markup.indexOf('class="setup-owner__header"');
  const bodyIndex = markup.indexOf(`class="${expected.bodyClass}"`);
  const footerIndex = markup.indexOf('class="setup-owner__actions"');
  assert.ok(headerIndex >= 0 && bodyIndex > headerIndex && footerIndex > bodyIndex);
  assert.equal(markup.includes('class="setup-status"'), expected.status);
}

test('library owner keeps the scoped list hook used by focused row contrast', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);
  assert.match(
    root.innerHTML,
    /data-staged-owner="library"[^]*class="setup-owner__body"[^]*class="setup-library-list" data-plex-sections/u,
  );
});
