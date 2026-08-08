import test from 'node:test';
import assert from 'node:assert/strict';
import { createNativePlayerPresentationController } from '../../renderer/player/nativePlayerPresentationController.js';
import type { PlayerPresentationRequest, PlayerPresentationResult } from '../../contracts/player.js';
import type { NativePlayerPresentationIntent } from '../../renderer/player/nativePlayerPresentationController.js';

test('renderer presentation controller opens only after the exact current applied acknowledgement', async () => {
  const element = fakeElement();
  const calls: PlayerPresentationRequest[] = [];
  let intent: NativePlayerPresentationIntent = { mode: 'player-full', requestId: 'media-1' };
  const controller = createNativePlayerPresentationController({
    element,
    updatePresentation: async (request) => {
      calls.push(request);
      return request.documentEpoch === null
        ? { ok: true, status: 'deferred', documentEpoch: 3, revision: request.revision }
        : { ok: true, status: 'applied', documentEpoch: 3, revision: request.revision };
    },
    getIntent: () => intent,
    viewport: () => ({ width: 1000, height: 700 }),
  });
  controller.reconcile();
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(calls.length, 2);
  assert.equal(element.dataset.nativePresentationAperture, 'open');
  intent = { mode: 'hidden' as const, requestId: 'media-1' };
  controller.reconcile();
  assert.equal(element.dataset.nativePresentationAperture, 'opaque');
});

test('renderer presentation controller retains one active and one latest request', async () => {
  const element = fakeElement();
  const requests: PlayerPresentationRequest[] = [];
  const resolvers: Array<(result: PlayerPresentationResult) => void> = [];
  const controller = createNativePlayerPresentationController({
    element,
    updatePresentation: (request) => { requests.push(request); return new Promise((resolve) => resolvers.push(resolve)); },
    getIntent: () => ({ mode: 'player-full', requestId: 'media-1' }),
    viewport: () => ({ width: 1000, height: 700 }),
  });
  for (let index = 0; index < 100; index += 1) controller.reconcile();
  assert.equal(requests.length, 1);
  const firstRequest = requireAt(requests, 0);
  resolvers[0]?.({ ok: true, status: 'deferred', documentEpoch: 2, revision: firstRequest.revision });
  await Promise.resolve();
  assert.equal(requests.length, 2);
});

test('renderer presentation controller measures the first Classic request after composing Classic layout', async () => {
  const root = fakeElement();
  const element = fakeElement(() => {
    assert.equal(root.dataset.nativePresentationMode, 'guide-classic-pip');
    return domRect(600, 20, 980, 234);
  });
  const requests: PlayerPresentationRequest[] = [];
  const controller = createNativePlayerPresentationController({
    element,
    compositionElement: root,
    updatePresentation: async (request) => {
      requests.push(request);
      return request.documentEpoch === null
        ? { ok: true, status: 'deferred', documentEpoch: 4, revision: request.revision }
        : { ok: true, status: 'applied', documentEpoch: 4, revision: request.revision };
    },
    getIntent: () => ({ mode: 'guide-classic-pip', requestId: 'media-1' }),
    viewport: () => ({ width: 1000, height: 700 }),
  });
  controller.reconcile();
  await flushPromises();
  assert.equal(requests.length, 2);
  assert.deepEqual(requireAt(requests, 0).rect, {
    x: 0.6,
    y: 20 / 700,
    width: 0.38,
    height: 214 / 700,
  });
  assert.equal(root.dataset.nativePresentationAperture, 'open');
});

test('renderer presentation controller ignores an applied acknowledgement when a newer request is queued', async () => {
  const root = fakeElement();
  const element = fakeElement();
  const requests: PlayerPresentationRequest[] = [];
  const pending: Array<(result: PlayerPresentationResult) => void> = [];
  let automatic = true;
  const controller = createNativePlayerPresentationController({
    element,
    compositionElement: root,
    updatePresentation: (request) => {
      requests.push(request);
      if (automatic) {
        return Promise.resolve(request.documentEpoch === null
          ? { ok: true, status: 'deferred', documentEpoch: 7, revision: request.revision }
          : { ok: true, status: 'applied', documentEpoch: 7, revision: request.revision });
      }
      return new Promise((resolve) => pending.push(resolve));
    },
    getIntent: () => ({ mode: 'player-full', requestId: 'media-1' }),
    viewport: () => ({ width: 1000, height: 700 }),
  });
  controller.reconcile();
  await flushPromises();
  automatic = false;
  controller.reconcile();
  controller.reconcile();
  assert.equal(root.dataset.nativePresentationAperture, 'opaque');
  const active = requireAt(requests, 2);
  pending[0]?.({ ok: true, status: 'applied', documentEpoch: 7, revision: active.revision });
  await flushPromises();
  assert.equal(root.dataset.nativePresentationAperture, 'opaque');
  const latest = requireAt(requests, 3);
  pending[1]?.({ ok: true, status: 'applied', documentEpoch: 7, revision: latest.revision });
  await flushPromises();
  assert.equal(root.dataset.nativePresentationAperture, 'open');
});

test('renderer presentation teardown stays opaque when an earlier applied acknowledgement races cleanup', async () => {
  const root = fakeElement();
  const element = fakeElement();
  const requests: PlayerPresentationRequest[] = [];
  const pending: Array<(result: PlayerPresentationResult) => void> = [];
  let automatic = true;
  let inFlight = 0;
  let maximumInFlight = 0;
  const controller = createNativePlayerPresentationController({
    element,
    compositionElement: root,
    updatePresentation: (request) => {
      requests.push(request);
      if (automatic) {
        return Promise.resolve(request.documentEpoch === null
          ? { ok: true, status: 'deferred', documentEpoch: 8, revision: request.revision }
          : { ok: true, status: 'applied', documentEpoch: 8, revision: request.revision });
      }
      inFlight += 1;
      maximumInFlight = Math.max(maximumInFlight, inFlight);
      return new Promise((resolve) => pending.push((result) => { inFlight -= 1; resolve(result); }));
    },
    getIntent: () => ({ mode: 'player-full', requestId: 'media-1' }),
    viewport: () => ({ width: 1000, height: 700 }),
  });
  controller.reconcile();
  await flushPromises();
  automatic = false;
  controller.reconcile();
  const teardown = controller.teardown();
  assert.equal(controller.teardown(), teardown);
  assert.equal(requests.length, 3);
  assert.equal(inFlight, 1);
  const active = requireAt(requests, 2);
  pending[0]?.({ ok: true, status: 'applied', documentEpoch: 8, revision: active.revision });
  await flushPromises();
  assert.equal(requests.length, 4);
  assert.equal(inFlight, 1);
  assert.equal(maximumInFlight, 1);
  assert.equal(root.dataset.nativePresentationAperture, 'opaque');
  assert.equal(root.dataset.nativePresentationMode, 'hidden');
  const hidden = requireAt(requests, 3);
  pending[1]?.({ ok: true, status: 'hidden', documentEpoch: 8, revision: hidden.revision });
  await teardown;
  controller.reconcile();
  assert.equal(requests.length, 4);
  assert.equal(root.dataset.nativePresentationAperture, 'opaque');
});

test('renderer presentation controller observes geometry and disconnects the observer on teardown', async () => {
  const element = fakeElement();
  const root = fakeElement();
  const listeners: Array<() => void> = [];
  let observed: Element | null = null;
  let disconnects = 0;
  const requests: PlayerPresentationRequest[] = [];
  const controller = createNativePlayerPresentationController({
    element,
    compositionElement: root,
    updatePresentation: async (request) => {
      requests.push(request);
      return request.documentEpoch === null
        ? { ok: true, status: 'deferred', documentEpoch: 9, revision: request.revision }
        : { ok: true, status: request.mode === 'hidden' ? 'hidden' : 'applied', documentEpoch: 9, revision: request.revision };
    },
    getIntent: () => ({ mode: 'guide-classic-pip', requestId: 'media-1' }),
    viewport: () => ({ width: 1000, height: 700 }),
    createResizeObserver: (callback) => {
      listeners.push(callback);
      return { observe: (target) => { observed = target; }, disconnect: () => { disconnects += 1; } };
    },
  });
  assert.equal(observed, element);
  assert.equal(root.dataset.nativePresentationAperture, 'opaque');
  requireAt(listeners, 0)();
  await flushPromises();
  assert.equal(requests.length, 2);
  await controller.teardown();
  assert.equal(disconnects, 1);
});

function fakeElement(rect: () => DOMRect = () => domRect(600, 20, 980, 234)): HTMLElement {
  return {
    dataset: {},
    getBoundingClientRect: rect,
  } as unknown as HTMLElement;
}

function domRect(left: number, top: number, right: number, bottom: number): DOMRect {
  return { left, top, right, bottom, width: right - left, height: bottom - top, x: left, y: top, toJSON: () => ({}) };
}

function requireAt<T>(values: T[], index: number): T {
  const value = values[index];
  if (value === undefined) throw new Error(`Expected value at index ${index}.`);
  return value;
}

async function flushPromises(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}
