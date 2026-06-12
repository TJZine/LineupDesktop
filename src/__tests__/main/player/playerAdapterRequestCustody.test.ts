import test from 'node:test';
import assert from 'node:assert/strict';

import { PlayerAdapterRequestCustody } from '../../../main/player/playerAdapterRequestCustody.js';

function playCommand(requestId: string) {
  return { command: 'play', requestId, payload: {} } as const;
}

function pauseCommand(requestId: string) {
  return { command: 'pause', requestId, payload: {} } as const;
}

test('player adapter request custody tracks pending request ids until settlement', () => {
  const custody = new PlayerAdapterRequestCustody();

  assert.equal(custody.getPendingRequestCount(), 0);
  assert.equal(custody.has('request-1'), false);

  custody.begin(playCommand('request-1'));

  assert.equal(custody.has('request-1'), true);
  assert.equal(custody.getPendingRequestCount(), 1);

  custody.settle('request-1');

  assert.equal(custody.has('request-1'), false);
  assert.equal(custody.getPendingRequestCount(), 0);
});

test('player adapter request custody clears all in-flight requests for lifecycle cleanup', () => {
  const custody = new PlayerAdapterRequestCustody();

  custody.begin(playCommand('request-1'));
  custody.begin(pauseCommand('request-2'));

  assert.equal(custody.getPendingRequestCount(), 2);

  custody.clear();

  assert.equal(custody.has('request-1'), false);
  assert.equal(custody.has('request-2'), false);
  assert.equal(custody.getPendingRequestCount(), 0);
});
