import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';

import { resolveRendererProtocolRequest } from '../../main/rendererProtocolPolicy.js';

const rendererRoot = path.resolve('/safe/renderer');

test('renderer protocol policy resolves only approved self-owned MIME types', () => {
  assert.deepEqual(resolveRendererProtocolRequest('lineup://shell/index.html', rendererRoot), {
    ok: true,
    filePath: path.join(rendererRoot, 'index.html'),
    contentType: 'text/html; charset=utf-8',
    isIndex: true,
  });
  assert.deepEqual(resolveRendererProtocolRequest('lineup://shell/assets/lineup-logo-mark.png', rendererRoot), {
    ok: true,
    filePath: path.join(rendererRoot, 'assets', 'lineup-logo-mark.png'),
    contentType: 'image/png',
    isIndex: false,
  });
  assert.equal(resolveRendererProtocolRequest('lineup://shell/styles/base.css', rendererRoot).ok, true);
  assert.equal(resolveRendererProtocolRequest('lineup://shell/index.js', rendererRoot).ok, true);
});

test('renderer protocol policy rejects malformed, remote, query, traversal, root, and unlisted requests', () => {
  for (const urlText of [
    'not a URL',
    'https://shell/index.html',
    'lineup://remote/index.html',
    'lineup://shell:444/index.html',
    'lineup://user@shell/index.html',
    'lineup://shell/',
    'lineup://shell',
    'lineup://shell/index.html?cache=1',
    'lineup://shell/../outside.js',
    'lineup://shell/%2e%2e/outside.js',
    'lineup://shell/%2Foutside.js',
    'lineup://shell/%ZZ.js',
    'lineup://shell/assets/logo.svg',
    'lineup://shell/assets/logo.PNG',
  ]) {
    assert.deepEqual(resolveRendererProtocolRequest(urlText, rendererRoot), { ok: false }, urlText);
  }
});
