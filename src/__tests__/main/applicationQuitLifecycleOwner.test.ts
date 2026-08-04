import assert from 'node:assert/strict';
import test from 'node:test';
import { setImmediate } from 'node:timers';
import { setTimeout as delay } from 'node:timers/promises';

import { ApplicationQuitLifecycleOwner } from '../../main/applicationQuitLifecycleOwner.js';

test('quit lifecycle prevents re-entry, drains late startup owners, then allows one final quit', async () => {
  const startup = deferred<void>();
  const events: string[] = [];
  let cleanupCalls = 0;
  let quitCalls = 0;
  const owner = new ApplicationQuitLifecycleOwner({
    cleanupCurrentOwners: async () => {
      cleanupCalls += 1;
      events.push(`cleanup-${String(cleanupCalls)}`);
    },
    waitForStartupSettlement: async () => {
      events.push('startup-wait');
      await startup.promise;
      events.push('startup-settled');
    },
    quit: () => {
      quitCalls += 1;
      events.push('quit');
    },
    reportDiagnostic: () => assert.fail('successful quit must not report a diagnostic'),
  });
  const firstEvent = beforeQuitEvent();
  const inProgressEvent = beforeQuitEvent();

  owner.handleBeforeQuit(firstEvent.event);
  owner.handleBeforeQuit(inProgressEvent.event);
  await settle();

  assert.equal(owner.isQuitRequested(), true);
  assert.equal(firstEvent.prevented, 1);
  assert.equal(inProgressEvent.prevented, 1);
  assert.equal(cleanupCalls, 1);
  assert.equal(quitCalls, 0);
  assert.deepEqual(events, ['cleanup-1', 'startup-wait']);

  startup.resolve();
  await settle();

  assert.equal(cleanupCalls, 2);
  assert.equal(quitCalls, 1);
  assert.deepEqual(events, [
    'cleanup-1',
    'startup-wait',
    'startup-settled',
    'cleanup-2',
    'quit',
  ]);

  const finalEvent = beforeQuitEvent();
  owner.handleBeforeQuit(finalEvent.event);
  assert.equal(finalEvent.prevented, 0);
  assert.equal(cleanupCalls, 2);
  assert.equal(quitCalls, 1);
});

test('quit lifecycle contains cleanup and diagnostic failures without skipping the final drain', async () => {
  const events: string[] = [];
  const reported: string[] = [];
  let cleanupCalls = 0;
  let quitCalls = 0;
  const owner = new ApplicationQuitLifecycleOwner({
    cleanupCurrentOwners: async () => {
      cleanupCalls += 1;
      events.push(`cleanup-${String(cleanupCalls)}`);
      if (cleanupCalls === 1) throw new Error('first cleanup failed');
    },
    waitForStartupSettlement: async () => {
      events.push('startup-settled');
      throw new Error('startup settlement failed');
    },
    quit: () => {
      quitCalls += 1;
      events.push('quit');
    },
    reportDiagnostic: (message) => {
      reported.push(message);
      if (reported.length === 1) throw new Error('diagnostic sink failed');
    },
  });
  const firstEvent = beforeQuitEvent();

  owner.handleBeforeQuit(firstEvent.event);
  await settle();

  assert.equal(firstEvent.prevented, 1);
  assert.equal(cleanupCalls, 2);
  assert.equal(quitCalls, 1);
  assert.deepEqual(events, ['cleanup-1', 'startup-settled', 'cleanup-2', 'quit']);
  assert.deepEqual(reported, [
    'Application cleanup failed during quit',
    'Application startup did not settle during quit',
  ]);
});

test('quit lifecycle bounds a stalled startup drain and still completes the final cleanup sweep', async () => {
  const reported: Array<{ message: string; error: unknown }> = [];
  let cleanupCalls = 0;
  let quitCalls = 0;
  const owner = new ApplicationQuitLifecycleOwner({
    cleanupCurrentOwners: async () => { cleanupCalls += 1; },
    waitForStartupSettlement: () => new Promise<never>(() => undefined),
    quit: () => { quitCalls += 1; },
    reportDiagnostic: (message, error) => { reported.push({ message, error }); },
    startupSettlementTimeoutMs: 1,
  });
  const event = beforeQuitEvent();

  owner.handleBeforeQuit(event.event);
  await delay(10);

  assert.equal(event.prevented, 1);
  assert.equal(cleanupCalls, 2);
  assert.equal(quitCalls, 1);
  assert.equal(reported.length, 1);
  assert.equal(reported[0]?.message, 'Application startup did not settle during quit');
  assert.match(String(reported[0]?.error), /startup settlement timed out/u);

  const finalEvent = beforeQuitEvent();
  owner.handleBeforeQuit(finalEvent.event);
  assert.equal(finalEvent.prevented, 0);
  assert.equal(cleanupCalls, 2);
  assert.equal(quitCalls, 1);
});

function beforeQuitEvent(): {
  event: { preventDefault(): void };
  readonly prevented: number;
} {
  let prevented = 0;
  return {
    event: { preventDefault: () => { prevented += 1; } },
    get prevented() { return prevented; },
  };
}

interface Deferred<T> {
  promise: Promise<T>;
  resolve(value: T): void;
}

function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  return {
    promise: new Promise<T>((done) => { resolve = done; }),
    resolve,
  };
}

async function settle(): Promise<void> {
  await new Promise<void>((resolve) => setImmediate(resolve));
}
