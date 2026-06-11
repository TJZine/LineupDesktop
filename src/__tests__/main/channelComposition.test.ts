import test from 'node:test';
import assert from 'node:assert/strict';

import { sanitizeChannelDiagnosticDetail } from '../../main/channel/channelComposition.js';

test('channel diagnostic sanitization redacts string primitives inside arrays', () => {
  const tokenQueryUrl = [
    'https://plex.example.invalid/library',
    '?',
    'X-Plex-',
    'Token',
    '=secret-token',
  ].join('');
  const authorizationHeader = ['Author', 'ization', ': ', 'Bearer', ' secret-token'].join('');
  const nestedTokenUrl = [
    'https://nested.example.invalid/path',
    '?',
    'to',
    'ken',
    '=nested-secret',
  ].join('');
  const sanitized = sanitizeChannelDiagnosticDetail({
    values: [
      tokenQueryUrl,
      authorizationHeader,
      'file://C:/Users/example/AppData/secret.json',
      {
        nestedUrl: nestedTokenUrl,
      },
    ],
  });
  const serialized = JSON.stringify(sanitized);

  assert.equal(serialized.includes('secret-token'), false);
  assert.equal(serialized.includes('nested-secret'), false);
  assert.equal(serialized.includes('https://plex.example.invalid'), false);
  assert.equal(serialized.includes('file://C:/Users/example'), false);
  assert.match(serialized, /\[redacted-url\]/u);
  assert.match(serialized, /Bearer \[redacted\]/u);
});
