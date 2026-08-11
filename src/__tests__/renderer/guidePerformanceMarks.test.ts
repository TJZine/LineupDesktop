import assert from 'node:assert/strict';
import test from 'node:test';
import { GuidePerformanceMarkOwner, classifyGuideKeyboardInput } from '../../renderer/guidePerformanceMarks.js';

test('Guide marks expose the seven closed semantic lifecycles and clear immediately', () => {
  const marks: Array<{ name: string; detail: Record<string, unknown> }> = [];
  const cleared: string[] = [];
  const owner = new GuidePerformanceMarkOwner({
    mark: (name, { detail }) => marks.push({ name, detail }),
    clearMarks: (name) => cleared.push(name),
  });
  owner.inputReceived('page');
  owner.inputAccepted('page', 24);
  const request = owner.requestStarted(3, 24, 12, 1_000, 7_200_000, 'foreground');
  owner.requestSettled(request, 3, 'renderer-cache', true, 'foreground');
  owner.stateAccepted(3, 'ready', 24);
  const reconcile = owner.reconcileStarted(3);
  owner.reconcileEnded(reconcile, 3);

  assert.deepEqual(marks.map(({ name }) => name), [
    'lineup-guide-v1:input-received', 'lineup-guide-v1:input-accepted',
    'lineup-guide-v1:request-start', 'lineup-guide-v1:request-settled',
    'lineup-guide-v1:state-accepted', 'lineup-guide-v1:reconcile-start',
    'lineup-guide-v1:reconcile-end',
  ]);
  assert.deepEqual(cleared, marks.map(({ name }) => name));
  assert.deepEqual(marks[2]?.detail, {
    sequence: request, generation: 3, channelOffset: 24, channelLimit: 12,
    windowStartMs: 1_000, windowDurationMs: 7_200_000, requestOrigin: 'foreground',
  });
  assert.deepEqual(marks[3]?.detail, {
    sequence: request, generation: 3, channelOffset: 24, channelLimit: 12,
    windowStartMs: 1_000, windowDurationMs: 7_200_000, requestClass: 'renderer-cache',
    requestOrigin: 'foreground', accepted: true,
  });
  assert.deepEqual(marks[4]?.detail, {
    sequence: request, generation: 3, stateClass: 'ready', targetIndex: 24,
  });
  assert.equal(marks[0]?.detail.sequence, marks[1]?.detail.sequence);
  assert.equal(request, marks[0]?.detail.sequence);
});

test('Guide chains a queued loading generation only to its matching request', () => {
  const details: Record<string, unknown>[] = [];
  const owner = new GuidePerformanceMarkOwner({
    mark: (_name, { detail }) => details.push(detail),
    clearMarks: () => undefined,
  });
  const oldRequest = owner.requestStarted(1, 0, 12, 0, 1_000, 'poll');
  owner.stateAccepted(2, 'loading', -1);
  const nextRequest = owner.requestStarted(2, 12, 12, 0, 1_000, 'foreground');
  assert.notEqual(details[1]?.sequence, oldRequest);
  assert.equal(nextRequest, details[1]?.sequence);
});

test('Guide chains polling work to the matching queued loading generation', () => {
  const details: Record<string, unknown>[] = [];
  const owner = new GuidePerformanceMarkOwner({
    mark: (_name, { detail }) => details.push(detail),
    clearMarks: () => undefined,
  });
  owner.stateAccepted(7, 'loading', -1);
  const loadingSequence = details[0]?.sequence;

  const pollSequence = owner.requestStarted(7, 24, 12, 0, 1_000, 'poll');

  assert.equal(pollSequence, loadingSequence);
  assert.equal(details[1]?.requestOrigin, 'poll');
});

test('Guide polling reuse does not consume a newer semantic input', () => {
  const details: Record<string, unknown>[] = [];
  const owner = new GuidePerformanceMarkOwner({
    mark: (_name, { detail }) => details.push(detail),
    clearMarks: () => undefined,
  });
  owner.stateAccepted(7, 'loading', -1);
  owner.inputReceived('arrow');
  const inputSequence = details[1]?.sequence;
  owner.requestStarted(7, 0, 12, 0, 1_000, 'poll');

  const foregroundSequence = owner.requestStarted(8, 12, 12, 0, 1_000, 'foreground');

  assert.equal(foregroundSequence, inputSequence);
});

test('Guide input classification stays within the fixed vocabulary', () => {
  assert.equal(classifyGuideKeyboardInput({ key: 'PageDown' }), 'page');
  assert.equal(classifyGuideKeyboardInput({ key: 'ArrowLeft' }), 'arrow');
  assert.equal(classifyGuideKeyboardInput({ key: 'Enter' }), 'other');
});

test('Guide does not reuse a reconciled keyboard receipt for another input source', () => {
  const details: Record<string, unknown>[] = [];
  const owner = new GuidePerformanceMarkOwner({
    mark: (_name, { detail }) => details.push(detail),
    clearMarks: () => undefined,
  });
  owner.inputReceived('arrow');
  owner.inputAccepted('arrow');
  const reconcile = owner.reconcileStarted(0);
  owner.reconcileEnded(reconcile, 0);
  owner.inputAccepted('arrow');
  assert.equal(details.at(-1)?.inputKind, 'other');
  assert.notEqual(details.at(-1)?.sequence, details[1]?.sequence);
});

test('Guide mark and clear failures are independently fail-open', () => {
  let clears = 0;
  const throwingMark = new GuidePerformanceMarkOwner({
    mark: () => { throw new Error('mark failed'); },
    clearMarks: () => { clears += 1; },
  });
  assert.doesNotThrow(() => throwingMark.inputReceived('arrow'));
  assert.equal(clears, 1);
  const throwingClear = new GuidePerformanceMarkOwner({
    mark: () => undefined,
    clearMarks: () => { throw new Error('clear failed'); },
  });
  assert.doesNotThrow(() => throwingClear.inputAccepted('pointer'));
});
