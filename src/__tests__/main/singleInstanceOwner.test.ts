import assert from 'node:assert/strict';
import test from 'node:test';

import { SingleInstanceOwner } from '../../main/singleInstanceOwner.js';

test('secondary instance quits without registering a listener', () => {
  const events: string[] = [];
  const owner = new SingleInstanceOwner({
    app: {
      requestSingleInstanceLock: () => false,
      on: () => events.push('on'),
      off: () => events.push('off'),
      quit: () => events.push('quit'),
    },
    getWindow: () => null,
  });

  assert.deepEqual(owner.acquire(), { primary: false });
  assert.deepEqual(events, ['quit']);
});

test('primary instance retains one listener and only focuses the existing window', () => {
  const events: string[] = [];
  let listener: (() => void) | null = null;
  const owner = new SingleInstanceOwner({
    app: {
      requestSingleInstanceLock: () => true,
      on: (_event, callback) => {
        events.push('on');
        listener = callback;
      },
      off: (_event, callback) => {
        assert.equal(callback, listener);
        events.push('off');
      },
      quit: () => events.push('quit'),
    },
    getWindow: () => ({
      isDestroyed: () => false,
      isMinimized: () => true,
      restore: () => events.push('restore'),
      show: () => events.push('show'),
      focus: () => events.push('focus'),
    }),
  });

  assert.deepEqual(owner.acquire(), { primary: true });
  assert.ok(listener);
  (listener as () => void)();
  owner.teardown();
  owner.teardown();
  assert.deepEqual(events, ['on', 'restore', 'show', 'focus', 'off']);
});
