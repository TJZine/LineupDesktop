import test from 'node:test';
import assert from 'node:assert/strict';

import {
  waitForFullscreenState,
  type FullscreenObservationScheduler,
  type FullscreenObservationWindow,
} from '../../main/smokeFullscreenAssertions.js';

test('fullscreen observation handles enter and leave events before state', async () => {
  for (const enabled of [true, false]) {
    const scheduler = new FakeScheduler();
    const window = new FakeFullscreenWindow(!enabled);
    const observation = waitForFullscreenState(window, enabled, scheduler);

    window.emit(enabled ? 'enter-full-screen' : 'leave-full-screen');
    window.fullscreen = enabled;
    scheduler.advance(25);

    assert.equal(await observation, true);
    assertClean(window, scheduler);
  }
});

test('fullscreen observation handles state before the correct event', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(false);
  const observation = waitForFullscreenState(window, true, scheduler);

  window.fullscreen = true;
  scheduler.advance(25);
  window.emit('enter-full-screen');

  assert.equal(await observation, true);
  assertClean(window, scheduler);
});

test('fullscreen observation rejects event-only completion at the existing deadline', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(false);
  const observation = waitForFullscreenState(window, true, scheduler);

  window.emit('enter-full-screen');
  scheduler.advance(5000);

  assert.equal(await observation, false);
  assertClean(window, scheduler);
});

test('fullscreen observation rejects state-only completion at the existing deadline', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(false);
  const observation = waitForFullscreenState(window, true, scheduler);

  window.fullscreen = true;
  scheduler.advance(5000);

  assert.equal(await observation, false);
  assertClean(window, scheduler);
});

test('fullscreen observation rejects destruction and cleans pending callbacks', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(false);
  const observation = waitForFullscreenState(window, true, scheduler);

  window.destroyed = true;
  scheduler.advance(25);

  assert.equal(await observation, false);
  assertClean(window, scheduler);
});

test('fullscreen observation accepts an already-satisfied initial state without listeners or timers', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(true);

  assert.equal(await waitForFullscreenState(window, true, scheduler), true);
  assertClean(window, scheduler);
});

test('fullscreen observation ignores the opposite event', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(false);
  const observation = waitForFullscreenState(window, true, scheduler);

  window.emit('leave-full-screen');
  window.fullscreen = true;
  scheduler.advance(5000);

  assert.equal(await observation, false);
  assertClean(window, scheduler);
});

test('fullscreen deadline reconciles a valid transition after the last interval poll', async () => {
  const scheduler = new FakeScheduler();
  const window = new FakeFullscreenWindow(false);
  const observation = waitForFullscreenState(window, true, scheduler);

  scheduler.advance(4975);
  window.emit('enter-full-screen');
  window.fullscreen = true;
  scheduler.advance(25);

  assert.equal(await observation, true);
  assertClean(window, scheduler);
});

function assertClean(window: FakeFullscreenWindow, scheduler: FakeScheduler): void {
  assert.equal(window.listenerCount(), 0);
  assert.equal(scheduler.pendingCount(), 0);
}

class FakeFullscreenWindow implements FullscreenObservationWindow {
  destroyed = false;
  readonly listeners = new Map<'enter-full-screen' | 'leave-full-screen', Set<() => void>>();

  constructor(public fullscreen: boolean) {}

  isDestroyed(): boolean { return this.destroyed; }
  isFullScreen(): boolean { return this.fullscreen; }
  on(event: 'enter-full-screen' | 'leave-full-screen', listener: () => void): void {
    const listeners = this.listeners.get(event) ?? new Set();
    listeners.add(listener);
    this.listeners.set(event, listeners);
  }
  off(event: 'enter-full-screen' | 'leave-full-screen', listener: () => void): void {
    this.listeners.get(event)?.delete(listener);
  }
  emit(event: 'enter-full-screen' | 'leave-full-screen'): void {
    for (const listener of [...(this.listeners.get(event) ?? [])]) listener();
  }
  listenerCount(): number {
    return [...this.listeners.values()].reduce((total, listeners) => total + listeners.size, 0);
  }
}

class FakeScheduler implements FullscreenObservationScheduler<number> {
  private nowMs = 0;
  private nextId = 1;
  private readonly tasks = new Map<number, { dueAtMs: number; callback: () => void }>();

  setTimeout(callback: () => void, delayMs: number): number {
    const id = this.nextId++;
    this.tasks.set(id, { dueAtMs: this.nowMs + delayMs, callback });
    return id;
  }
  clearTimeout(handle: number): void { this.tasks.delete(handle); }
  advance(durationMs: number): void {
    const targetMs = this.nowMs + durationMs;
    while (true) {
      const next = [...this.tasks.entries()]
        .filter(([, task]) => task.dueAtMs <= targetMs)
        .sort(([leftId, left], [rightId, right]) => left.dueAtMs - right.dueAtMs || leftId - rightId)[0];
      if (next === undefined) break;
      const [id, task] = next;
      this.tasks.delete(id);
      this.nowMs = task.dueAtMs;
      task.callback();
    }
    this.nowMs = targetMs;
  }
  pendingCount(): number { return this.tasks.size; }
}
