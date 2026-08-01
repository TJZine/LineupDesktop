import assert from 'node:assert/strict';
import test from 'node:test';

import { toRendererSafeFailureMessage } from '../../renderer/rendererSafeFailureMessage.js';

const FALLBACK = 'Operation failed.';

test('renderer-safe failure messages preserve bounded plain text', () => {
  assert.equal(
    toRendererSafeFailureMessage('  Playback\noperation\tfailed.  ', FALLBACK),
    'Playback operation failed.',
  );
  assert.equal(
    toRendererSafeFailureMessage('x'.repeat(220), FALLBACK),
    'x'.repeat(180),
  );
});

test('renderer-safe failure messages fail closed for locations, URLs, and credential vocabulary', () => {
  const sensitiveMessages = [
    ['ht', 'tps://example.invalid/media'].join(''),
    ['fi', 'le:', '/', '/', '/', 'var', '/', 'media', '/', 'item'].join(''),
    ['custom', '://runtime/item'].join(''),
    ['Failed at ', '/', 'var', '/', 'media', '/', 'item'].join(''),
    ['Failed at ', '/', 'tmp', '/', 'item'].join(''),
    ['Failure:', '/', 'opt', '/', 'media'].join(''),
    ['Failed at ', '~', '/', 'media', '/', 'item'].join(''),
    ['Failed at ', 'C', ':', '\\', 'media', '\\', 'item'].join(''),
    ['Failed at ', 'D', ':', '/', 'media', '/', 'item'].join(''),
    ['Failed at ', '\\', '\\', 'server', '\\', 'share'].join(''),
    ['Authentication ', 'token was rejected'].join(''),
    ['Credential ', 'header was rejected'].join(''),
    '   ',
  ];

  for (const message of sensitiveMessages) {
    assert.equal(toRendererSafeFailureMessage(message, FALLBACK), FALLBACK, message);
  }
});
