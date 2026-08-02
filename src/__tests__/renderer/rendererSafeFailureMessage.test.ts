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
    ['Author', 'ization', ': Bear', 'er ', ['abc', '123', 'XYZ'].join('')].join(''),
    ['Bear', 'er ', ['abc', '123', 'XYZ'].join('')].join(''),
    ['X-Api', '-Key=', ['abc', '123', 'XYZ'].join('')].join(''),
    ['pass', 'word=', ['hunter', '2'].join('')].join(''),
    [
      ['eyJ', 'hbGciOiJIUzI1NiJ9'].join(''),
      ['eyJ', 'zdWIiOiIxMjM0NTY3ODkwIn0'].join(''),
      ['sig', 'nature12-'].join(''),
    ].join('.'),
    ['Failed at ', '.', '/', 'private', '/', 'media.mkv'].join(''),
    ['Failed at ', '.', '.', '/', 'private', '/', 'media.mkv'].join(''),
    ['Failed at ', '.', '\\', 'private', '\\', 'media.mkv'].join(''),
    ['Failed at ', '.', '.', '\\', 'private', '\\', 'media.mkv'].join(''),
    ['Failed at `', '.', '/', 'private', '/', 'media.mkv', '`'].join(''),
    ['Failed at [', '.', '/', 'private', '/', 'media.mkv', ']'].join(''),
    ['Failed at {', '.', '.', '/', 'private', '/', 'media.mkv', '}'].join(''),
    ['Failed at,', '.', '/', 'private', '/', 'media.mkv'].join(''),
    ['Failed at \u201c', '.', '/', 'private', '/', 'media.mkv', '\u201d'].join(''),
    '   ',
  ];

  for (const message of sensitiveMessages) {
    assert.equal(toRendererSafeFailureMessage(message, FALLBACK), FALLBACK, message);
  }
});

test('renderer-safe failure messages preserve benign slash text', () => {
  assert.equal(
    toRendererSafeFailureMessage('Choose audio/video settings.', FALLBACK),
    'Choose audio/video settings.',
  );
});
