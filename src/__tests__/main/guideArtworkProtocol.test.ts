import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import ts from 'typescript';

type ProtocolModule = {
  LINEUP_CSP: string;
  registerLineupProtocolHandler(
    rendererRoot: string,
    owner?: { get(refId: string): Promise<{ bytes: Uint8Array; mimeType: string } | null> },
  ): void;
  serveLineupProtocolRequest(
    request: { url: string; method: string },
    rendererRoot: string,
    owner?: { get(refId: string): Promise<{ bytes: Uint8Array; mimeType: string } | null> },
  ): Promise<Response>;
};

async function loadProtocolModule(onHandle?: (handler: (request: Request) => Promise<Response>) => void): Promise<ProtocolModule> {
  const source = await readFile(new URL('../../main/protocol.ts', import.meta.url), 'utf8');
  const exportsObject: Record<string, unknown> = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: 'src/main/protocol.ts',
  }).outputText;
  new Function('require', 'exports', 'module', compiled)(
    (moduleName: string) => {
      if (moduleName === 'node:fs/promises') return { default: {} };
      if (moduleName === 'electron') return {
        net: {},
        protocol: {
          handle: (_scheme: string, handler: (request: Request) => Promise<Response>) => onHandle?.(handler),
        },
      };
      if (moduleName === 'node:url') return { pathToFileURL: () => new URL('file:///unused') };
      if (moduleName === './rendererProtocolPolicy.js') {
        return { resolveRendererProtocolRequest: () => ({ ok: false }) };
      }
      if (moduleName === '../contracts/artwork.js') {
        return { ARTWORK_REF_ID_PATTERN: /^artwork-[A-Za-z0-9_-]{16,96}$/u };
      }
      return assert.fail(`unexpected require ${moduleName}`);
    },
    exportsObject,
    moduleObject,
  );
  return moduleObject.exports as ProtocolModule;
}

const refId = 'artwork-abcdefghijklmnopqrstuvwx';

test('registered lineup handler routes the fixed artwork bearer GET to its owner', async () => {
  let registered = false;
  let handler: (request: Request) => Promise<Response> = async () => assert.fail('handler not registered');
  const module = await loadProtocolModule((value) => { registered = true; handler = value; });
  module.registerLineupProtocolHandler('/unused', {
    get: async () => ({ bytes: new Uint8Array([7]), mimeType: 'image/webp' }),
  });
  assert.equal(registered, true);
  const response = await handler(new Request(`lineup://shell/artwork/${refId}`));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'image/webp');
});

test('fixed self-origin artwork GET serves only owner-approved image bytes and headers', async () => {
  const { LINEUP_CSP, serveLineupProtocolRequest } = await loadProtocolModule();
  const calls: string[] = [];
  const response = await serveLineupProtocolRequest(
    { url: `lineup://shell/artwork/${refId}`, method: 'GET' },
    '/unused',
    {
      get: async (received) => {
        calls.push(received);
        return { bytes: new Uint8Array([1, 2]), mimeType: 'image/png' };
      },
    },
  );
  assert.equal(response.status, 200);
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [1, 2]);
  assert.deepEqual(calls, [refId]);
  assert.equal(response.headers.get('content-type'), 'image/png');
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(response.headers.get('content-security-policy'), LINEUP_CSP);
  assert.match(LINEUP_CSP, /img-src 'self'/u);
});

test('method, query, fragment, traversal, invalid segments, and unknown refs fail closed', async () => {
  const { serveLineupProtocolRequest } = await loadProtocolModule();
  let calls = 0;
  const owner = { get: async () => { calls += 1; return null; } };
  const requests = [
    { url: `lineup://shell/artwork/${refId}`, method: 'POST' },
    { url: `lineup://shell/artwork/${refId}?x=1`, method: 'GET' },
    { url: `lineup://shell/artwork/${refId}#x`, method: 'GET' },
    { url: 'lineup://shell/artwork/../index.html', method: 'GET' },
    { url: `lineup://shell/artwork/${refId}/extra`, method: 'GET' },
    { url: 'lineup://shell/artwork/', method: 'GET' },
    { url: 'lineup://shell/artwork/not-a-ref', method: 'GET' },
  ];
  for (const request of requests) {
    const response = await serveLineupProtocolRequest(request, '/unused', owner);
    assert.equal(response.status, 404);
    assert.equal(await response.text(), 'Not found.');
  }
  assert.equal(calls, 0);

  const unknown = await serveLineupProtocolRequest(
    { url: `lineup://shell/artwork/${refId}`, method: 'GET' }, '/unused', owner,
  );
  assert.equal(unknown.status, 404);
  assert.equal(calls, 1);
});
