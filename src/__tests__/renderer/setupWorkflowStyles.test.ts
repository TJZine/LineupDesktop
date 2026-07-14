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

  assert.match(root.innerHTML, /data-staged-owner="library"[^]*setup-owner__header[^]*setup-status[^]*setup-owner__body[^]*setup-owner__actions/u);
  assert.match(root.innerHTML, /data-staged-owner="progress"[^>]*>\s*<header class="setup-owner__header"[^]*<div class="setup-owner__body setup-operation-state"[^]*<footer class="setup-owner__actions"/u);
  assert.match(root.innerHTML, /data-staged-owner="result"[^>]*>\s*<header class="setup-owner__header"[^]*<div class="setup-owner__body setup-operation-state"[^]*<footer class="setup-owner__actions"/u);
});

test('setup markup keeps primary Channel Setup titles with step and content below', () => {
  const root = { innerHTML: '', querySelector: () => null };
  mountStaticRendererDom({
    querySelector: (selector: string) => selector === '[data-static-screen-root]' ? root : null,
  } as unknown as Document);
  assert.match(root.innerHTML, /class="setup-owner__title">Channel Setup<\/h2><span class="setup-owner__step">Step 1 of 3<\/span><div class="setup-owner__intro">/u);
  assert.match(root.innerHTML, /class="setup-owner__title">Channel Setup<\/h2><span class="setup-owner__step">Step 2 of 3<\/span><div class="setup-owner__intro">/u);
  assert.match(root.innerHTML, /class="setup-owner__title">Channel Setup<\/h2><span class="setup-owner__step">Step 3 of 3<\/span><div class="setup-owner__intro">/u);
});

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
