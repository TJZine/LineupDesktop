import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LivePlexTransport,
  LivePlexTransportError,
  normalizeGuideArtworkLocator,
  PLEX_TOKEN_HEADER_NAME,
} from '../../main/plex/livePlexTransport.js';

const capturedCredential = ['captured', 'credential', 'value'].join('-');

function connection(uri = 'https://plex.invalid:32400/base/path') {
  const parsed = new URL(uri);
  return {
    uri,
    protocol: parsed.protocol === 'http:' ? 'http' as const : 'https' as const,
    address: parsed.hostname,
    port: Number(parsed.port || (parsed.protocol === 'http:' ? 80 : 443)),
    local: true,
    relay: false,
    latencyMs: 1,
  };
}

test('normalizeGuideArtworkLocator accepts only the anchored Plex poster grammar', () => {
  assert.equal(normalizeGuideArtworkLocator('/library/metadata/1/thumb'), '/library/metadata/1/thumb');
  assert.equal(
    normalizeGuideArtworkLocator('/library/metadata/123/thumb/1700000000'),
    '/library/metadata/123/thumb/1700000000',
  );
  const rejected = [
    '',
    'library/metadata/1/thumb',
    '/library/metadata/x/thumb',
    '/library/metadata/1/thumb/x',
    '/library/metadata/1/art',
    '/library/metadata/1/banner',
    '/library/metadata/1/clearLogo',
    '/library/metadata/1/thumb/1/extra',
    '/library/metadata/1/thumb/',
    '//library/metadata/1/thumb',
    '/library//metadata/1/thumb',
    '/library/./metadata/1/thumb',
    '/library/../metadata/1/thumb',
    '/library/metadata/1/%2e/thumb',
    '/library/metadata/1/%2f/thumb',
    '/library/metadata/1/%5c/thumb',
    '/library/metadata/1/th%75mb',
    'https://plex.invalid/library/metadata/1/thumb',
    '//plex.invalid/library/metadata/1/thumb',
    ' /library/metadata/1/thumb',
    '/library/metadata/1/thumb ',
    '/library/meta data/1/thumb',
    '/library/metadata/1/thumb\n',
    '/library/metadata/1/thumbé',
    '/library\\metadata/1/thumb',
    '/library/metadata/1/thumb?size=1',
    '/library/metadata/1/thumb#fragment',
    '/user:pass@host/library/metadata/1/thumb',
    '/library/metadata/1/thumb'.padEnd(513, 'x'),
  ];
  for (const locator of rejected) {
    assert.throws(() => normalizeGuideArtworkLocator(locator), LivePlexTransportError, locator);
  }
});

test('guide artwork GET stays byte-identical on the captured origin and sends credentials only in headers', async () => {
  const calls: Array<{ url: URL; init: RequestInit }> = [];
  const transport = new LivePlexTransport({
    fetch: async (input, init) => {
      calls.push({ url: new URL(String(input)), init: init ?? {} });
      return new Response(new Uint8Array([1, 2, 3]), {
        status: 200,
        headers: { 'content-type': 'image/jpeg' },
      });
    },
  });
  const result = await transport.fetchGuideArtwork({
    connection: connection(),
    token: capturedCredential,
    locator: '/library/metadata/123/thumb/1700000000',
  });

  assert.deepEqual([...result.bytes], [1, 2, 3]);
  assert.equal(result.mimeType, 'image/jpeg');
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url.origin, 'https://plex.invalid:32400');
  assert.equal(calls[0]?.url.pathname, '/library/metadata/123/thumb/1700000000');
  assert.equal(calls[0]?.url.search, '');
  assert.equal(calls[0]?.init.method, 'GET');
  assert.equal(calls[0]?.init.redirect, 'error');
  assert.equal(new Headers(calls[0]?.init.headers).get(PLEX_TOKEN_HEADER_NAME), capturedCredential);
});

test('default ports, base paths, and bracketed IPv6 preserve captured-origin containment', async () => {
  const urls: string[] = [];
  const transport = new LivePlexTransport({
    fetch: async (input) => {
      urls.push(String(input));
      return new Response(new Uint8Array([1]), { headers: { 'content-type': 'image/webp' } });
    },
  });
  await transport.fetchGuideArtwork({
    connection: connection('https://plex.invalid/base/path'),
    token: capturedCredential,
    locator: '/library/metadata/1/thumb',
  });
  await transport.fetchGuideArtwork({
    connection: connection('http://[::1]:32400/base/path'),
    token: capturedCredential,
    locator: '/library/metadata/1/thumb',
  });
  assert.equal(new URL(urls[0] ?? '').origin, 'https://plex.invalid');
  assert.equal(new URL(urls[0] ?? '').pathname, '/library/metadata/1/thumb');
  assert.equal(new URL(urls[1] ?? '').origin, 'http://[::1]:32400');
});

test('rejected locator and failed pre-fetch base parsing never touch fetch', async () => {
  let calls = 0;
  const transport = new LivePlexTransport({ fetch: async () => {
    calls += 1;
    return new Response();
  } });
  await assert.rejects(transport.fetchGuideArtwork({
    connection: connection(), token: capturedCredential, locator: '/library/metadata/1/art',
  }), LivePlexTransportError);
  await assert.rejects(transport.fetchGuideArtwork({
    connection: { ...connection(), uri: 'not a base uri' },
    token: capturedCredential,
    locator: '/library/metadata/1/thumb',
  }), LivePlexTransportError);
  await assert.rejects(transport.fetchGuideArtwork({
    connection: { ...connection(), uri: 'https://user:pass@plex.invalid:32400/base' },
    token: capturedCredential,
    locator: '/library/metadata/1/thumb',
  }), LivePlexTransportError);
  assert.equal(calls, 0);
});

test('guide artwork timeout is injectable, fast, and its failure remains redacted', { timeout: 1_000 }, async () => {
  const transport = new LivePlexTransport({
    guideArtworkTimeoutMs: 20,
    fetch: async (_input, init) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new Error('upstream aborted')), { once: true });
    }),
  });
  const pending = transport.fetchGuideArtwork({
    connection: connection(), token: capturedCredential,
    locator: '/library/metadata/1/thumb',
  });
  await assert.rejects(pending, (error: unknown) => {
    assert.ok(error instanceof LivePlexTransportError);
    assert.equal(error.code, 'timeout');
    assert.doesNotMatch(error.message, /captured|credential|plex\.invalid|library\/metadata/u);
    return true;
  });
});

test('guide artwork transport cancels response bodies before early HTTP, MIME, and length failures', async () => {
  const canceled: string[] = [];
  const response = (label: string, status: number, headers: Record<string, string>) => new Response(
    new ReadableStream<Uint8Array>({
      pull() { /* keep the body open until the transport cancels it */ },
      cancel() { canceled.push(label); },
    }),
    { status, headers },
  );
  const responses = [
    response('http', 500, { 'content-type': 'image/png' }),
    response('mime', 200, { 'content-type': 'text/html' }),
    response('length', 200, { 'content-type': 'image/jpeg', 'content-length': '1500001' }),
  ];
  const transport = new LivePlexTransport({ fetch: async () => responses.shift()! });
  for (const locator of ['/library/metadata/1/thumb', '/library/metadata/2/thumb', '/library/metadata/3/thumb']) {
    await assert.rejects(transport.fetchGuideArtwork({
      connection: connection(), token: capturedCredential, locator,
    }), LivePlexTransportError);
  }
  assert.deepEqual(canceled, ['http', 'mime', 'length']);
});

test('guide artwork transport rejects MIME and size violations and honors abort', async () => {
  const badMime = new LivePlexTransport({
    fetch: async () => new Response('not image', { headers: { 'content-type': 'text/html' } }),
  });
  await assert.rejects(badMime.fetchGuideArtwork({
    connection: connection(), token: capturedCredential, locator: '/library/metadata/1/thumb',
  }), LivePlexTransportError);

  const oversized = new LivePlexTransport({
    fetch: async () => new Response(new Uint8Array(1_500_001), {
      headers: { 'content-type': 'image/png' },
    }),
  });
  await assert.rejects(oversized.fetchGuideArtwork({
    connection: connection(), token: capturedCredential, locator: '/library/metadata/1/thumb',
  }), LivePlexTransportError);

  const aborting = new LivePlexTransport({
    fetch: async (_input, init) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
    }),
  });
  const controller = new AbortController();
  const pending = aborting.fetchGuideArtwork({
    connection: connection(), token: capturedCredential,
    locator: '/library/metadata/1/thumb', signal: controller.signal,
  });
  controller.abort();
  await assert.rejects(pending, (error: unknown) =>
    error instanceof LivePlexTransportError && error.code === 'aborted');
});
