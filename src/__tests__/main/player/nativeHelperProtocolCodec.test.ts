import test from 'node:test';
import assert from 'node:assert/strict';

import {
  isNativeHelperPresentationUpdate,
  toNativeHelperPresentationUpdate,
} from '../../../main/player/nativeHelperProtocolCodec.js';
import type { NativePlayerPresentationUpdate } from '../../../main/player/nativePlayerHostPort.js';

type SequencedPresentationUpdate = NativePlayerPresentationUpdate & { operationId: string };

const valid: SequencedPresentationUpdate = {
  operationId: 'presentation-1',
  documentEpoch: 2,
  revision: 3,
  parentHwnd: '18446744073709551615',
  parentPid: 2_147_483_647,
  loadedRequestId: 'media-1',
  mode: 'guide-classic-pip',
  bounds: { x: 0.6, y: 0.02, width: 0.38, height: 0.3 },
};

test('native helper presentation codec accepts only exact mode-coupled updates', () => {
  assert.equal(isNativeHelperPresentationUpdate(valid), true);
  assert.deepEqual(toNativeHelperPresentationUpdate(valid), {
    type: 'presentation.update', version: 1, ...valid,
  });
  assert.equal(isNativeHelperPresentationUpdate({
    ...valid, loadedRequestId: null, mode: 'hidden', bounds: null,
  }), true);
  assert.equal(isNativeHelperPresentationUpdate({
    ...valid, mode: 'player-full', bounds: { x: 0, y: 0, width: 1, height: 1 },
  }), true);
});

test('native helper presentation codec rejects malformed grammar, numeric, and coupling vectors', () => {
  const malformed: unknown[] = [
    null,
    [],
    { ...valid, extra: true },
    { ...valid, operationId: '' },
    { ...valid, operationId: 'bad id' },
    { ...valid, operationId: 'x'.repeat(121) },
    { ...valid, documentEpoch: 0 },
    { ...valid, documentEpoch: 1.5 },
    { ...valid, documentEpoch: Number.MAX_SAFE_INTEGER + 1 },
    { ...valid, revision: Number.NaN },
    { ...valid, parentHwnd: '0' },
    { ...valid, parentHwnd: '-1' },
    { ...valid, parentHwnd: '18446744073709551616' },
    { ...valid, parentPid: 0 },
    { ...valid, parentPid: 2_147_483_648 },
    { ...valid, loadedRequestId: 'bad request' },
    { ...valid, mode: 'popup' },
    { ...valid, mode: 'hidden', bounds: valid.bounds },
    { ...valid, mode: 'player-full', bounds: null },
    { ...valid, mode: 'player-full', bounds: valid.bounds },
    { ...valid, mode: 'guide-classic-pip', loadedRequestId: null },
    { ...valid, bounds: { ...valid.bounds, extra: true } },
    { ...valid, bounds: { ...valid.bounds, width: 0 } },
    { ...valid, bounds: { ...valid.bounds, x: Number.POSITIVE_INFINITY } },
    { ...valid, bounds: { ...valid.bounds, x: 0.7 } },
  ];
  for (const value of malformed) {
    assert.equal(isNativeHelperPresentationUpdate(value), false, JSON.stringify(value));
    assert.throws(
      () => toNativeHelperPresentationUpdate(value as SequencedPresentationUpdate),
      /presentation update is invalid/u,
    );
  }
});
