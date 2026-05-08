import test from 'node:test';
import assert from 'node:assert/strict';

import {
  assertDummyHeaderPolicy,
  buildDummyHeaderField,
  buildMpvInvocation,
  normalizeTrack,
  scanForbiddenEvidenceContent,
  summarizeIpcResponse,
} from '../mpv-poc/rd-05-external-mpv-poc.mjs';

test('buildMpvInvocation constructs a spawn-ready mpv command without shell policy', () => {
  const invocation = buildMpvInvocation({
    mpvPath: '/bin/mpv',
    ipcSocketPath: '/tmp/lineup-rd-05/ipc.sock',
    mediaUrl: 'http://127.0.0.1:32123/media.wav',
  });

  assert.equal(invocation.command, '/bin/mpv');
  assert.ok(Array.isArray(invocation.args));
  assert.ok(invocation.args.includes('--no-config'));
  assert.ok(invocation.args.includes('--idle=yes'));
  assert.ok(invocation.args.includes('--start=0.5'));
  assert.ok(invocation.args.includes('--vo=null'));
  assert.ok(invocation.args.includes('--ao=null'));
  assert.ok(invocation.args.includes('--no-terminal'));
  assert.ok(invocation.args.includes(`--http-header-fields=${buildDummyHeaderField()}`));
  assert.ok(invocation.args.some((arg) => arg.startsWith('--input-ipc-server=')));
  assert.equal(invocation.args.at(-1), 'http://127.0.0.1:32123/media.wav');
});

test('assertDummyHeaderPolicy allows only the RD-05 dummy header', () => {
  assert.doesNotThrow(() => assertDummyHeaderPolicy(buildDummyHeaderField()));

  assert.throws(
    () => assertDummyHeaderPolicy(`${['Author', 'ization'].join('')}: sample`),
    /only the approved dummy header/u,
  );
  assert.throws(
    () => assertDummyHeaderPolicy(`${['X-Plex', 'Token'].join('-')}: sample`),
    /only the approved dummy header/u,
  );
  assert.throws(
    () => assertDummyHeaderPolicy('Cookie: sample'),
    /only the approved dummy header/u,
  );
});

test('normalizeTrack keeps renderer-safe fields and drops engine-specific fields', () => {
  const normalized = normalizeTrack({
    id: 99,
    srcId: 42,
    type: 'audio',
    selected: true,
    lang: 'EN',
    codec: 'pcm_s16le',
    title: '/Users/example/private-media.wav',
    externalFilename: 'private-media.wav',
    audioChannels: 2,
  }, 0);

  assert.deepEqual(normalized, {
    label: 'track-1',
    kind: 'audio',
    selected: true,
    language: 'en',
    codec: 'pcm_s16le',
    channelCount: 2,
  });
});

test('normalizeTrack redacts unknown or unsafe raw track values', () => {
  const normalized = normalizeTrack({
    type: 'application',
    selected: false,
    lang: 'english/us',
    codec: '../private value',
    audioChannels: 99,
  }, 3);

  assert.deepEqual(normalized, {
    label: 'track-4',
    kind: 'unknown',
    selected: false,
    language: 'und',
    codec: '..privatevalue',
  });
});

test('scanForbiddenEvidenceContent catches raw paths, URLs, and secret-shaped fields', () => {
  assert.deepEqual(scanForbiddenEvidenceContent('input local-dummy-http only'), []);
  assert.ok(scanForbiddenEvidenceContent('http://127.0.0.1:32123/media.wav').includes('remote-url'));
  assert.ok(scanForbiddenEvidenceContent('/Users/example/secret.wav').includes('absolute-user-path'));
  assert.ok(scanForbiddenEvidenceContent(`${['Author', 'ization'].join('')}: sample`).includes('raw-auth-field'));
  assert.ok(scanForbiddenEvidenceContent(`${['X-Plex', 'Token'].join('-')}: sample`).includes('plex-field'));
});

test('summarizeIpcResponse stores only result category', () => {
  assert.deepEqual(summarizeIpcResponse({ error: 'success', data: { raw: 'ignored' } }), {
    category: 'success',
  });
  assert.deepEqual(summarizeIpcResponse({ error: 'property unavailable' }), {
    category: 'error',
  });
  assert.deepEqual(summarizeIpcResponse(null), {
    category: 'unavailable',
  });
});
