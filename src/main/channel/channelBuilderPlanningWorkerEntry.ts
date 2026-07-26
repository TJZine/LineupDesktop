import { parentPort } from 'node:worker_threads';

import type { ChannelBuilderPlannerInput } from '../../domain/channelBuilder/types.js';
import { buildProductionChannelSetupPlan } from './channelBuilderProductionPlanner.js';

if (parentPort === null) {
  throw new Error('Channel Builder planning worker requires a parent port.');
}
const planningPort = parentPort;

planningPort.on('message', (message: unknown) => {
  if (!isPlanMessage(message)) {
    planningPort.postMessage({ kind: 'failed', jobId: readJobId(message) });
    return;
  }
  try {
    const output = buildProductionChannelSetupPlan(message.input);
    planningPort.postMessage({ kind: 'planned', jobId: message.jobId, output });
  } catch {
    planningPort.postMessage({ kind: 'failed', jobId: message.jobId });
  }
});

function isPlanMessage(
  value: unknown,
): value is Readonly<{ kind: 'plan'; jobId: number; input: ChannelBuilderPlannerInput }> {
  return (
    isPlainRecord(value) &&
    hasExactKeys(value, ['kind', 'jobId', 'input']) &&
    value.kind === 'plan' &&
    Number.isSafeInteger(value.jobId) &&
    (value.jobId as number) > 0 &&
    isPlainRecord(value.input)
  );
}

function readJobId(value: unknown): number {
  return isPlainRecord(value) && Number.isSafeInteger(value.jobId) && (value.jobId as number) > 0
    ? value.jobId as number
    : 0;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasExactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length &&
    actual.every((key, index) => key === expected[index]);
}
