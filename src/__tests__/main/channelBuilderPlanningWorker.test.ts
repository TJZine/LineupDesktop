import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createDefaultChannelSetupConfig,
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
  type ChannelBuilderPlannerInput,
} from '../../domain/channelBuilder/index.js';
import {
  ChannelBuilderPlanningWorker,
  type ChannelBuilderPlanningWorkerPort,
} from '../../main/channel/channelBuilderPlanningWorker.js';
import { buildProductionChannelSetupPlan } from '../../main/channel/channelBuilderProductionPlanner.js';

test('planning worker uses the fixed entry and accepts one validated result', async () => {
  const workers: FakeWorker[] = [];
  let workerUrl = '';
  const owner = new ChannelBuilderPlanningWorker({
    createWorker: (url) => {
      workerUrl = url.href;
      const worker = new FakeWorker();
      workers.push(worker);
      return worker;
    },
  });
  const input = planningInput();
  const expected = buildProductionChannelSetupPlan(input);
  const planned = owner.plan(input, new AbortController().signal);
  assert.match(workerUrl, /\/channelBuilderPlanningWorkerEntry\.js$/u);
  assert.deepEqual(workers[0]?.messages, [{ kind: 'plan', jobId: 1, input }]);
  workers[0]?.emit('message', { kind: 'planned', jobId: 1, output: expected });
  assert.deepEqual(await planned, expected);
  owner.shutdown();
  assert.equal(workers[0]?.terminateCalls, 1);
});

test('planning worker rejects busy, aborts by terminating, and lazily restarts', async () => {
  const workers: FakeWorker[] = [];
  const owner = new ChannelBuilderPlanningWorker({
    createWorker: () => {
      const worker = new FakeWorker();
      workers.push(worker);
      return worker;
    },
  });
  const input = planningInput();
  const firstController = new AbortController();
  const first = owner.plan(input, firstController.signal);
  await assert.rejects(
    owner.plan(input, new AbortController().signal),
    hasCode('CHANNEL_BUSY'),
  );
  firstController.abort();
  await assert.rejects(first, hasCode('CHANNEL_PLANNING_CANCELED'));
  assert.equal(workers[0]?.terminateCalls, 1);

  const second = owner.plan(input, new AbortController().signal);
  assert.equal(workers.length, 2);
  workers[0]?.emit('message', {
    kind: 'planned',
    jobId: 1,
    output: buildProductionChannelSetupPlan(input),
  });
  workers[1]?.emit('message', {
    kind: 'planned',
    jobId: 2,
    output: buildProductionChannelSetupPlan(input),
  });
  await second;
  owner.shutdown();
});

test('planning worker rejects protocol failure safely and permits a later worker', async () => {
  const workers: FakeWorker[] = [];
  const owner = new ChannelBuilderPlanningWorker({
    createWorker: () => {
      const worker = new FakeWorker();
      workers.push(worker);
      return worker;
    },
  });
  const input = planningInput();
  const first = owner.plan(input, new AbortController().signal);
  workers[0]?.emit('message', { kind: 'planned', jobId: 99, output: {} });
  await assert.rejects(first, hasCode('CHANNEL_UNKNOWN'));
  assert.equal(workers[0]?.terminateCalls, 1);

  const second = owner.plan(input, new AbortController().signal);
  workers[1]?.emit('message', { kind: 'failed', jobId: 2 });
  await assert.rejects(second, hasCode('CHANNEL_UNKNOWN'));
  owner.shutdown();
  owner.shutdown();
});

class FakeWorker implements ChannelBuilderPlanningWorkerPort {
  readonly messages: unknown[] = [];
  terminateCalls = 0;
  private readonly listeners = new Map<string, Set<(value?: unknown) => void>>();

  on(event: 'message' | 'error' | 'exit', listener: (value?: unknown) => void): this {
    const listeners = this.listeners.get(event) ?? new Set();
    listeners.add(listener);
    this.listeners.set(event, listeners);
    return this;
  }

  postMessage(message: unknown): void {
    this.messages.push(message);
  }

  removeAllListeners(): this {
    this.listeners.clear();
    return this;
  }

  async terminate(): Promise<number> {
    this.terminateCalls += 1;
    return 0;
  }

  emit(event: 'message' | 'error' | 'exit', value?: unknown): void {
    for (const listener of this.listeners.get(event) ?? []) listener(value);
  }
}

function planningInput(): ChannelBuilderPlannerInput {
  const config = createDefaultChannelSetupConfig({
    serverId: 'server',
    selectedLibraryIds: ['library'],
  });
  if (!config.ok) throw new Error('Planning fixture config failed.');
  const context = {
    contextEpoch: 1,
    profileBinding: createProfileBinding('profile'),
    serverBinding: createServerBinding('server'),
    librarySetBinding: createLibrarySetBinding([
      { libraryId: 'library', libraryUuid: 'uuid' },
    ]),
  };
  return {
    normalizedConfig: config.config,
    facetSnapshot: {
      context,
      libraries: [],
      playlists: [],
      collections: [],
      tags: [],
      recentlyAdded: [],
      aggregate: {
        status: 'ready',
        warningCodes: [],
        omittedMalformedCount: 0,
        omittedCappedCount: 0,
      },
    },
    existingLineup: [],
    clock: { nowMs: 1 },
    seed: 'worker-test',
  };
}

function hasCode(code: string): (error: unknown) => boolean {
  return (error) =>
    typeof error === 'object' &&
    error !== null &&
    'code' in error &&
    error.code === code;
}
