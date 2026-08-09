import assert from 'node:assert/strict';
import process from 'node:process';
import test from 'node:test';
import { clearTimeout, setTimeout } from 'node:timers';
import { setImmediate as waitForImmediate } from 'node:timers/promises';

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

type ArtworkCancellationMode = 'never-settling' | 'rejecting';

function responseWithCancellation(
  mode: ArtworkCancellationMode,
  options: {
    status?: number;
    headers?: Record<string, string>;
    chunkBytes?: number;
    onCancel: () => void;
  },
): Response {
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      if (options.chunkBytes !== undefined) {
        controller.enqueue(new Uint8Array(options.chunkBytes));
      }
    },
    cancel() {
      options.onCancel();
      if (mode === 'never-settling') return new Promise<void>(() => {});
      return Promise.reject(new Error('artwork cancellation failed'));
    },
  });
  return new Response(body, {
    status: options.status ?? 200,
    headers: options.headers,
  });
}

async function assertArtworkFailurePromptly(
  operation: Promise<unknown>,
  expectedCode: LivePlexTransportError['code'],
): Promise<void> {
  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timeoutHandle = setTimeout(() => reject(new Error('artwork failure did not settle promptly')), 1_000);
  });
  try {
    await Promise.race([
      assert.rejects(operation, (error: unknown) => {
        assert.ok(error instanceof LivePlexTransportError);
        assert.equal(error.code, expectedCode);
        return true;
      }),
      timeout,
    ]);
  } finally {
    if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);
  }
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

test('guide artwork transport cancels response bodies and aborts early HTTP, MIME, and length failures', async () => {
  const canceled: string[] = [];
  const signals: Array<{ label: string; signal: AbortSignal }> = [];
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
  const labels = ['http', 'mime', 'length'] as const;
  const transport = new LivePlexTransport({
    fetch: async (_input, init) => {
      const label = labels[signals.length];
      if (label !== undefined && init?.signal !== undefined && init.signal !== null) {
        signals.push({ label, signal: init.signal });
      }
      return responses.shift()!;
    },
  });
  const scenarios = [
    { locator: '/library/metadata/1/thumb', expectedCode: 'server-error' },
    { locator: '/library/metadata/2/thumb', expectedCode: 'parse-error' },
    { locator: '/library/metadata/3/thumb', expectedCode: 'parse-error' },
  ] as const;
  for (const { locator, expectedCode } of scenarios) {
    await assert.rejects(transport.fetchGuideArtwork({
      connection: connection(), token: capturedCredential, locator,
    }), (error: unknown) => error instanceof LivePlexTransportError && error.code === expectedCode);
  }
  assert.deepEqual(canceled, ['http', 'mime', 'length']);
  assert.deepEqual(
    signals.map(({ label, signal }) => [label, signal.aborted]),
    [['http', true], ['mime', true], ['length', true]],
  );
});

test('guide artwork failure does not await never-settling or rejecting response cleanup', async () => {
  const unhandled: unknown[] = [];
  const onUnhandledRejection = (reason: unknown) => unhandled.push(reason);
  process.on('unhandledRejection', onUnhandledRejection);
  try {
    for (const mode of ['never-settling', 'rejecting'] as const) {
      const scenarios: Array<{
        label: string;
        locator: string;
        status?: number;
        headers: Record<string, string>;
        chunkBytes?: number;
        expectedCode: LivePlexTransportError['code'];
      }> = [
        { label: 'http', locator: '/library/metadata/1/thumb', status: 500, headers: { 'content-type': 'image/png' }, expectedCode: 'server-error' as const },
        { label: 'mime', locator: '/library/metadata/2/thumb', headers: { 'content-type': 'text/html' }, expectedCode: 'parse-error' as const },
        { label: 'length', locator: '/library/metadata/3/thumb', headers: { 'content-type': 'image/jpeg', 'content-length': '1500001' }, expectedCode: 'parse-error' as const },
        { label: 'overflow', locator: '/library/metadata/4/thumb', headers: { 'content-type': 'image/png' }, chunkBytes: 1_500_001, expectedCode: 'parse-error' as const },
      ];
      for (const scenario of scenarios) {
        let canceled = false;
        const transport = new LivePlexTransport({
          fetch: async () => responseWithCancellation(mode, {
            ...(scenario.status !== undefined ? { status: scenario.status } : {}),
            headers: scenario.headers,
            ...(scenario.chunkBytes !== undefined ? { chunkBytes: scenario.chunkBytes } : {}),
            onCancel: () => { canceled = true; },
          }),
        });
        await assertArtworkFailurePromptly(
          transport.fetchGuideArtwork({
            connection: connection(), token: capturedCredential,
            locator: scenario.locator,
          }),
          scenario.expectedCode,
        );
        assert.equal(canceled, true, `${mode} ${scenario.label} cleanup was not started`);
      }
    }
    await waitForImmediate();
  } finally {
    process.off('unhandledRejection', onUnhandledRejection);
  }
  assert.deepEqual(unhandled, []);
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
