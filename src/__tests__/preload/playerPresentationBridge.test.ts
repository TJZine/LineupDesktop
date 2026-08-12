import test from 'node:test';
import assert from 'node:assert/strict';
import playerPresentationBridgeModule from '../../preload/playerPresentationBridge.cjs';

const { createPlayerPresentationBridge } = playerPresentationBridgeModule;

const full = { documentEpoch: 4, revision: 7, requestId: 'request-1', mode: 'player-full' as const, rect: { x: 0, y: 0, width: 1, height: 1 } };

test('player presentation bridge forwards the exact closed request and validates applied result', async () => {
  const calls: unknown[] = [];
  const bridge = createPlayerPresentationBridge(async (_channel, input) => {
    calls.push(input);
    return { ok: true, status: 'applied', documentEpoch: 4, revision: 7 };
  }, 'lineup:player:updatePresentation');
  assert.deepEqual(await bridge(full), { ok: true, status: 'applied', documentEpoch: 4, revision: 7 });
  assert.deepEqual(calls, [full]);
});

test('player presentation bridge rejects malformed input locally with independently safe correlations', async () => {
  let calls = 0;
  const bridge = createPlayerPresentationBridge(async () => { calls += 1; return null; }, 'channel');
  const result = await bridge({ ...full, revision: 0 } as typeof full);
  assert.deepEqual(result, {
    ok: false, status: 'rejected', documentEpoch: 4, revision: null,
    error: { code: 'PLAYER_PRESENTATION_REJECTED', message: 'Player presentation request was rejected.', recoverable: true, retryable: false },
  });
  assert.equal(calls, 0);
});

test('player presentation bridge rejects the complete malformed request matrix without IPC', async () => {
  let calls = 0;
  const bridge = createPlayerPresentationBridge(async () => { calls += 1; return null; }, 'channel');
  const badNumbers = [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, Number.NaN, Number.POSITIVE_INFINITY, '1'];
  const cases: unknown[] = [
    undefined, null, [], new Date(),
    { ...full, rect: undefined },
    { ...full, extra: true },
    ...badNumbers.map((documentEpoch) => ({ ...full, documentEpoch })),
    ...badNumbers.map((revision) => ({ ...full, revision })),
    { ...full, requestId: '' },
    { ...full, requestId: 'bad request' },
    { ...full, requestId: 'x'.repeat(121) },
    { ...full, mode: 'popup' },
    { ...full, rect: null },
    { ...full, rect: { x: 0, y: 0, width: 1, height: 1, extra: true } },
    { ...full, rect: { x: 0, y: 0, width: 1 } },
    { ...full, rect: { x: Number.NaN, y: 0, width: 1, height: 1 } },
    { ...full, rect: { x: -0.1, y: 0, width: 1, height: 1 } },
    { ...full, rect: { x: 0, y: 0, width: 0, height: 1 } },
    { ...full, rect: { x: 0.1, y: 0, width: 1, height: 1 } },
    { ...full, mode: 'hidden', rect: { x: 0, y: 0, width: 1, height: 1 } },
    { ...full, mode: 'guide-classic-pip', rect: null },
    { ...full, mode: 'guide-overlay-full', rect: { x: 0, y: 0, width: 0.5, height: 1 } },
  ];
  for (const value of cases) {
    const result = await bridge(value as typeof full);
    assert.equal(result.ok, false, JSON.stringify(value));
    assert.equal(result.status, 'rejected');
  }
  assert.equal(calls, 0);
});

test('player presentation bridge maps invoke rejection and malformed envelopes to local rejected', async () => {
  const throwing = createPlayerPresentationBridge(async () => { throw new Error('nativeHandle=private'); }, 'channel');
  assert.deepEqual(await throwing(full), {
    ok: false,
    status: 'rejected',
    documentEpoch: 4,
    revision: 7,
    error: {
      code: 'PLAYER_PRESENTATION_REJECTED',
      message: 'Player presentation request was rejected.',
      recoverable: true,
      retryable: false,
    },
  });
  const malformed = createPlayerPresentationBridge(async () => ({ ok: true, status: 'applied', documentEpoch: 4, revision: 8 }), 'channel');
  assert.equal((await malformed(full)).ok, false);
});

test('player presentation bridge validates exact status-bound failure vocabulary', async () => {
  const exact = {
    ok: false, status: 'timeout', documentEpoch: 4, revision: 7,
    error: { code: 'PLAYER_PRESENTATION_TIMEOUT', message: 'Native presentation request timed out.', recoverable: true, retryable: true },
  } as const;
  const accepted = createPlayerPresentationBridge(async () => exact, 'channel');
  assert.deepEqual(await accepted(full), exact);

  const malformedResults: unknown[] = [
    undefined, null, [], new Date(),
    { ...exact, extra: true },
    { ...exact, status: 'unknown' },
    { ...exact, documentEpoch: 0 },
    { ...exact, revision: Number.NaN },
    { ...exact, error: { ...exact.error, code: 'PLAYER_PRESENTATION_LIFECYCLE_FAILURE' } },
    { ...exact, error: { ...exact.error, message: 'wrong' } },
    { ...exact, error: { ...exact.error, recoverable: false } },
    { ...exact, error: { ...exact.error, retryable: false } },
    { ...exact, error: { ...exact.error, extra: true } },
    { ok: true, status: 'applied', documentEpoch: 4, revision: 7, error: exact.error },
    { ok: true, status: 'applied', documentEpoch: 4, revision: 7, extra: true },
    { ok: true, status: 'applied', documentEpoch: 4, revision: 8 },
    { ...exact, documentEpoch: 5 },
  ];
  for (const value of malformedResults) {
    const bridge = createPlayerPresentationBridge(async () => value, 'channel');
    const result = await bridge(full);
    assert.equal(result.ok, false);
    assert.equal(result.status, 'rejected');
  }
});

test('player presentation bridge enforces epoch-negotiation status semantics', async () => {
  const negotiating = { ...full, documentEpoch: null };
  for (const status of ['applied', 'deferred', 'hidden'] as const) {
    const bridge = createPlayerPresentationBridge(async () => ({
      ok: true, status, documentEpoch: 5, revision: 7,
    }), 'channel');
    assert.deepEqual(await bridge(negotiating), {
      ok: true, status, documentEpoch: 5, revision: 7,
    });
  }

  for (const result of [
    { ok: true, status: 'unsupported', documentEpoch: 5, revision: 7 },
    { ok: true, status: 'applied', documentEpoch: 0, revision: 7 },
    { ok: true, status: 'applied', documentEpoch: 5, revision: 8 },
  ] as const) {
    const bridge = createPlayerPresentationBridge(async () => result, 'channel');
    assert.equal((await bridge(negotiating)).status, 'rejected');
  }

  const deferredAfterNegotiation = createPlayerPresentationBridge(async () => ({
    ok: true, status: 'deferred', documentEpoch: 4, revision: 7,
  }), 'channel');
  assert.equal((await deferredAfterNegotiation(full)).status, 'rejected');
});
