import assert from 'node:assert/strict';
import test from 'node:test';

import guideBridgeModule from '../../preload/guideBridge.cjs';

type GuideBridge = {
  getPresentation(input: { startTimeMs: number; durationMs: number; channelOffset?: number; channelLimit?: number }): Promise<unknown>;
  setLibraryFilter(input: { expectedScopeToken: string; expectedRevision: number; libraryId: string | null }): Promise<unknown>;
};

const createGuideBridge = guideBridgeModule.createGuideBridge as (
  invoke: (channel: string, request: { requestId: string; payload: unknown }) => Promise<unknown>,
  channels: { getPresentation: string; setLibraryFilter: string; tuneChannel: string },
  createRequestId: (prefix: string) => string,
) => GuideBridge;
const createPlayerTuneBridge = guideBridgeModule.createPlayerTuneBridge as (
  invoke: (channel: string, request: { requestId: string; payload: unknown }) => Promise<unknown>,
  channel: string,
  createRequestId: (prefix: string) => string,
) => (input: { channelId: string }) => Promise<{ ok: boolean; error?: { code: string } }>;

function presentation(artwork: unknown, overrides: Record<string, unknown> = {}): unknown {
  return {
    channels: [{
      id: 'channel-1', number: '1', name: 'Channel One', programs: [{
        id: 'program-1', title: 'Program One', subtitle: '', description: 'Description',
        showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [],
        startsAtMs: 1, endsAtMs: 2, artwork, ...overrides,
      }],
    }],
    nowWatching: null,
    minimumStartTimeMs: 0,
    channelWindow: { offset: 0, total: 1 },
    libraryFilter: { scopeToken: 'scope-1', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'missing' },
  };
}

async function invokeWith(value: unknown): Promise<{ ok: boolean; error?: { code: string } }> {
  const bridge = createGuideBridge(
    async (_channel, request) => ({ ok: true, requestId: request.requestId, value }),
    { getPresentation: 'guide:get-presentation', setLibraryFilter: 'guide:set-library-filter', tuneChannel: 'player:tune' },
    () => 'guide-artwork-request-1',
  );
  return await bridge.getPresentation({ startTimeMs: 0, durationMs: 60_000 }) as {
    ok: boolean;
    error?: { code: string };
  };
}

test('guide bridge accepts only the strict poster artwork reference vocabulary', async () => {
  const available = {
    id: 'artwork-ABCDEFGHIJKLMNOP',
    kind: 'poster',
    expiresAtMs: 100,
    altText: 'Program One poster',
    status: 'available',
  };
  assert.equal((await invokeWith(presentation(available))).ok, true);
  assert.equal((await invokeWith(presentation(null))).ok, true);

  const invalidArtwork = [
    { ...available, id: 'unsafe' },
    { ...available, kind: 'background' },
    { ...available, status: 'missing' },
    { ...available, expiresAtMs: Number.NaN },
    { ...available, altText: 'x'.repeat(161) },
    { ...available, extra: true },
  ];
  for (const artwork of invalidArtwork) {
    const result = await invokeWith(presentation(artwork));
    assert.equal(result.ok, false);
    assert.equal(result.error?.code, 'GUIDE_VALIDATION_FAILED');
  }
});

test('guide bridge validates the required finite nonnegative minimum start bound', async () => {
  const base = presentation(null) as Record<string, unknown>;
  const missing = { ...base };
  delete missing.minimumStartTimeMs;
  const invalid = [
    missing,
    { ...base, extra: true },
    { ...base, minimumStartTimeMs: 1.5 },
    { ...base, minimumStartTimeMs: -1 },
    { ...base, minimumStartTimeMs: Number.MAX_SAFE_INTEGER + 1 },
    { ...base, minimumStartTimeMs: Number.NaN },
    { ...base, minimumStartTimeMs: Number.POSITIVE_INFINITY },
    { ...base, minimumStartTimeMs: '0' },
    { ...base, minimumStartTimeMs: null },
    { ...base, minimumStartTimeMs: {} },
  ];
  for (const value of invalid) {
    const result = await invokeWith(value);
    assert.equal(result.ok, false);
    assert.equal(result.error?.code, 'GUIDE_VALIDATION_FAILED');
  }
  assert.equal((await invokeWith(base)).ok, true);
});

test('guide bridge enforces bounded title and description fields', async () => {
  const artwork = {
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 100,
    altText: '', status: 'placeholder',
  };
  assert.equal((await invokeWith(presentation(artwork, { title: 'x'.repeat(161) }))).ok, false);
  assert.equal((await invokeWith(presentation(artwork, { description: 'x'.repeat(601) }))).ok, false);
});

test('guide bridge accepts the renderer-safe hostile-input projection', async () => {
  const artwork = {
    id: 'artwork-ABCDEFGHIJKLMNOP', kind: 'poster', expiresAtMs: 100,
    altText: '[redacted]', status: 'available',
  };
  const result = await invokeWith(presentation(artwork, {
    title: '[redacted]', subtitle: '‹subtitle› [link]',
  }));
  assert.equal(result.ok, true);
});

test('guide bridge enforces channel, row, aggregate, and library relation bounds', async () => {
  const row = (channelIndex: number, programCount: number) => ({
    id: `channel-${channelIndex}`, number: String(channelIndex), name: `Channel ${channelIndex}`,
    programs: Array.from({ length: programCount }, (_, programIndex) => ({
      id: `program-${channelIndex}-${programIndex}`, title: 'Program', subtitle: '', description: '',
      showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [],
      startsAtMs: programIndex * 2 + 1, endsAtMs: programIndex * 2 + 2, artwork: null,
    })),
  });
  const withChannels = (channels: unknown[], libraryFilter: unknown = {
    scopeToken: 'scope', revision: 0, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready',
  }) => ({ channels, nowWatching: null, minimumStartTimeMs: 0, channelWindow: { offset: 0, total: channels.length }, libraryFilter });
  assert.equal((await invokeWith(withChannels(Array.from({ length: 24 }, (_, index) => row(index, 0))))).ok, true);
  assert.equal((await invokeWith(withChannels(Array.from({ length: 25 }, (_, index) => row(index, 0))))).ok, false);
  assert.equal((await invokeWith(withChannels([row(1, 201)]))).ok, false);
  assert.equal((await invokeWith(withChannels(Array.from({ length: 6 }, (_, index) => row(index, index < 5 ? 200 : 1))))).ok, false);

  const library = { id: 'library-a', name: 'Alpha', contentKind: 'show' };
  assert.equal((await invokeWith(withChannels([], {
    scopeToken: 'scope', revision: 0, libraries: [library, library], selectedLibraryId: null, persistenceStatus: 'ready',
  }))).ok, false);
  assert.equal((await invokeWith(withChannels([], {
    scopeToken: 'scope', revision: 0, libraries: [library], selectedLibraryId: 'library-b', persistenceStatus: 'ready',
  }))).ok, false);
});

test('guide bridge invokes the one filter channel with exact CAS payload and validates relational success', async () => {
  const invocations: Array<{ channel: string; request: { requestId: string; payload: unknown } }> = [];
  const bridge = createGuideBridge(async (channel, request) => {
    invocations.push({ channel, request });
    return {
      ok: true,
      requestId: request.requestId,
      value: {
        scopeToken: 'scope-1', revision: 4,
        libraries: [{ id: 'library-a', name: 'Alpha', contentKind: 'show' }],
        selectedLibraryId: 'library-a', persistenceStatus: 'ready',
      },
    };
  }, { getPresentation: 'guide:get', setLibraryFilter: 'lineup:guide:setLibraryFilter', tuneChannel: 'player:tune' }, () => 'filter-request');
  const result = await bridge.setLibraryFilter({ expectedScopeToken: 'scope-1', expectedRevision: 3, libraryId: 'library-a' }) as { ok: boolean };
  assert.equal(result.ok, true);
  assert.deepEqual(invocations, [{
    channel: 'lineup:guide:setLibraryFilter',
    request: { requestId: 'filter-request', payload: { expectedScopeToken: 'scope-1', expectedRevision: 3, libraryId: 'library-a' } },
  }]);

  for (const invalid of [
    { expectedScopeToken: 'scope-1', expectedRevision: -1, libraryId: null },
    { expectedScopeToken: 'scope-1', expectedRevision: 0, libraryId: null, extra: true },
  ]) {
    const before: number = invocations.length;
    assert.equal(((await bridge.setLibraryFilter(invalid as never)) as { ok: boolean }).ok, false);
    assert.equal(invocations.length, before);
  }
});

test('guide bridge rejects invalid channel paging before invocation', async () => {
  let calls = 0;
  const bridge = createGuideBridge(async () => { calls += 1; return {}; },
    { getPresentation: 'guide:get', setLibraryFilter: 'guide:set', tuneChannel: 'player:tune' }, () => 'guide-request');
  const invalid = [
    { channelOffset: -1 }, { channelOffset: 1.5 }, { channelOffset: Number.MAX_SAFE_INTEGER + 1 },
    { channelLimit: 0 }, { channelLimit: 25 }, { channelLimit: 1.5 },
  ];
  for (const paging of invalid) {
    const result = await bridge.getPresentation({ startTimeMs: 0, durationMs: 1, ...paging }) as {
      ok: boolean; error?: { code: string };
    };
    assert.equal(result.ok, false);
    assert.equal(result.error?.code, 'GUIDE_VALIDATION_FAILED');
  }
  assert.equal(calls, 0);
});

test('guide bridge rejects mismatched filter success and nonclosed error code-operation pairs', async () => {
  const call = async (value: unknown) => {
    const bridge = createGuideBridge(async (_channel, request) => ({ ...(value as object), requestId: request.requestId }),
      { getPresentation: 'guide:get', setLibraryFilter: 'guide:set', tuneChannel: 'player:tune' }, () => 'filter-request');
    return await bridge.setLibraryFilter({ expectedScopeToken: 'scope', expectedRevision: 1, libraryId: null }) as { ok: boolean; error?: { code: string } };
  };
  const state = { scopeToken: 'scope', revision: 2, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' };
  assert.equal((await call({ ok: true, value: state })).ok, true);
  assert.equal((await call({ ok: true, value: { ...state, scopeToken: 'other' } })).ok, false);
  assert.equal((await call({ ok: true, value: { ...state, revision: 3 } })).ok, false);
  const error = { message: 'Safe failure.', retryable: true, recoverable: true, operation: 'setLibraryFilter' };
  assert.equal((await call({ ok: false, error: { ...error, code: 'GUIDE_FILTER_REVISION_CONFLICT' } })).error?.code, 'GUIDE_FILTER_REVISION_CONFLICT');
  assert.equal((await call({ ok: false, error: { ...error, code: 'GUIDE_TUNE_FAILED' } })).error?.code, 'GUIDE_VALIDATION_FAILED');
  assert.equal((await call({ ok: false, error: { ...error, code: 'GUIDE_FILTER_REVISION_CONFLICT', operation: 'getPresentation' } })).error?.code, 'GUIDE_VALIDATION_FAILED');
});

test('guide bridge closes presentation and tune error vocabulary to exact operations', async () => {
  const runtimeError = (code: string, operation: string) => ({
    ok: false, error: { code, operation, message: 'Safe failure.', retryable: true, recoverable: true },
  });
  const guideResult = async (value: unknown) => {
    const bridge = createGuideBridge(async (_channel, request) => ({ ...(value as object), requestId: request.requestId }),
      { getPresentation: 'guide:get', setLibraryFilter: 'guide:set', tuneChannel: 'player:tune' }, () => 'guide-request');
    return await bridge.getPresentation({ startTimeMs: 0, durationMs: 1 }) as { ok: boolean; error?: { code: string } };
  };
  assert.equal((await guideResult(runtimeError('GUIDE_PRESENTATION_STALE', 'getPresentation'))).error?.code,
    'GUIDE_PRESENTATION_STALE');
  assert.equal((await guideResult(runtimeError('GUIDE_TUNE_FAILED', 'getPresentation'))).error?.code,
    'GUIDE_VALIDATION_FAILED');
  const tuneResult = async (value: unknown) => {
    const tune = createPlayerTuneBridge(async (_channel, request) => ({ ...(value as object), requestId: request.requestId }),
      'player:tune', () => 'tune-request');
    return tune({ channelId: 'channel-a' });
  };
  assert.equal((await tuneResult(runtimeError('GUIDE_TUNE_FAILED', 'tuneChannel'))).error?.code, 'GUIDE_TUNE_FAILED');
  assert.equal((await tuneResult(runtimeError('GUIDE_PRESENTATION_FAILED', 'tuneChannel'))).error?.code,
    'GUIDE_VALIDATION_FAILED');
});

test('guide filter mutation rejection returns the fixed local failure without a second invocation', async () => {
  let calls = 0;
  const bridge = createGuideBridge(async () => { calls += 1; throw new Error('private rejection'); },
    { getPresentation: 'guide:get', setLibraryFilter: 'guide:set', tuneChannel: 'player:tune' }, () => 'filter-request');
  const result = await bridge.setLibraryFilter({ expectedScopeToken: 'scope', expectedRevision: 0, libraryId: null }) as {
    ok: false; error: { code: string; operation: string; message: string };
  };
  assert.equal(calls, 1);
  assert.deepEqual(result.error, {
    code: 'GUIDE_VALIDATION_FAILED', operation: 'setLibraryFilter', message: 'Internal IPC invoke failed.',
    retryable: false, recoverable: false,
  });
});
