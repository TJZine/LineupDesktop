import { createHash } from 'node:crypto';
import {
  createChannelBuilderIdentityOperations,
  type ChannelBuilderIncrementalSha256,
} from '../../domain/channelBuilder/planIdentity.js';
import { createChannelSetupPlanner } from '../../domain/channelBuilder/planner.js';
import type {
  ChannelBuilderPlannerInput,
  ChannelBuilderPlannerOutput,
} from '../../domain/channelBuilder/types.js';

function createNativeSha256(): ChannelBuilderIncrementalSha256 {
  const hash = createHash('sha256');
  let digested = false;
  const requireOpen = (): void => {
    if (digested) throw new TypeError('SHA-256 digest is already finalized.');
  };
  return {
    updateUtf8(value): void {
      requireOpen();
      hash.update(value, 'utf8');
    },
    digestHex(): string {
      requireOpen();
      digested = true;
      return hash.digest('hex');
    },
  };
}

export const channelBuilderProductionIdentityOperations =
  createChannelBuilderIdentityOperations(createNativeSha256);

const productionPlanner = createChannelSetupPlanner(
  channelBuilderProductionIdentityOperations,
);

export function buildProductionChannelSetupPlan(
  input: ChannelBuilderPlannerInput,
): ChannelBuilderPlannerOutput {
  return productionPlanner(input);
}
