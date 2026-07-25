import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type {
  ChannelSetupOperation,
  NormalizedChannelSetupConfig,
} from '../contracts/channel.js';
import {
  applyChannelOperation,
  applyChannelStatusResult,
  clearChannelRuntimeActionState,
  createChannelRuntimeRendererState,
  markChannelRuntimeBlocked,
  markChannelRuntimePending,
  sanitizeChannelRuntimeError,
  type ChannelRuntimeRendererState,
} from './channelRuntimeState.js';

export interface ChannelRuntimeController {
  getState(): ChannelRuntimeRendererState;
  loadStatus(): Promise<void>;
  markBlocked(message: string): void;
  clearActionState(): void;
  cancelActive(): Promise<'accepted' | 'unavailable' | 'failed' | 'skipped'>;
  reviewAndApply(input: {
    config: NormalizedChannelSetupConfig;
    confirmReplace: boolean;
  }): Promise<ChannelRuntimeActionOutcome>;
}

export type ChannelRuntimeActionOutcome =
  | 'succeeded'
  | 'failed'
  | 'canceled'
  | 'skipped'
  | 'stale';

export function createChannelRuntimeController(input: {
  bridge: LineupDesktopPreloadApi['channelSetup'];
  onStateChanged(): void;
}): ChannelRuntimeController {
  let state = createChannelRuntimeRendererState();
  let actionSequence = 0;
  let cancellationRequested = false;

  const publish = (next: ChannelRuntimeRendererState): void => {
    state = next;
    input.onStateChanged();
  };
  const loadStatus = async (): Promise<void> => {
    publish(markChannelRuntimePending(state));
    publish(applyChannelStatusResult(state, await input.bridge.getStatus()));
  };
  const poll = async (
    operation: ChannelSetupOperation,
    sequence: number,
  ): Promise<ChannelSetupOperation | null> => {
    let current = operation;
    for (let attempt = 0; attempt < 2_000; attempt += 1) {
      if (sequence !== actionSequence) return null;
      publish(applyChannelOperation(state, current));
      if (
        current.state === 'review-ready' ||
        current.state === 'succeeded' ||
        current.state === 'failed' ||
        current.state === 'canceled'
      ) return current;
      await new Promise<void>((resolve) => globalThis.setTimeout(resolve, 25));
      const result = await input.bridge.getOperation({ operationId: current.operationId });
      if (!result.ok) {
        publish({
          ...state,
          pending: false,
          statusText: 'Channel setup failed',
          errorText: sanitizeChannelRuntimeError(result.error),
        });
        return null;
      }
      current = result.value.operation;
    }
    return null;
  };
  const cancelOperation = async (
    operation: ChannelSetupOperation,
  ): Promise<'accepted' | 'unavailable' | 'failed'> => {
    const result = await input.bridge.cancel({ operationId: operation.operationId });
    if (!result.ok) {
      publish({
        ...state,
        errorText: sanitizeChannelRuntimeError(result.error),
      });
      return 'failed';
    }
    publish(applyChannelOperation(state, result.value.operation));
    return result.value.accepted ? 'accepted' : 'unavailable';
  };

  return {
    getState: () => state,
    loadStatus: async () => {
      if (!state.pending) await loadStatus();
    },
    markBlocked: (message) => {
      actionSequence += 1;
      publish(markChannelRuntimeBlocked(state, message));
    },
    clearActionState: () => {
      actionSequence += 1;
      publish(clearChannelRuntimeActionState(state));
    },
    cancelActive: async () => {
      const operation = state.operation;
      if (operation === null) {
        if (!state.pending) return 'skipped';
        cancellationRequested = true;
        publish({ ...state, statusText: 'Canceling…' });
        return 'accepted';
      }
      if (operation.state === 'review-ready') {
        cancellationRequested = true;
        publish({ ...state, statusText: 'Canceling…' });
        return 'accepted';
      }
      if (
        operation.state === 'succeeded' ||
        operation.state === 'failed' ||
        operation.state === 'canceled'
      ) {
        return 'skipped';
      }
      cancellationRequested = true;
      return cancelOperation(operation);
    },
    reviewAndApply: async ({ config, confirmReplace }) => {
      if (state.pending) return 'skipped';
      cancellationRequested = false;
      const sequence = ++actionSequence;
      publish(markChannelRuntimePending(state, 'Starting channel review'));
      const review = await input.bridge.startReview({ config });
      if (!review.ok) {
        publish({
          ...state,
          pending: false,
          statusText: 'Channel setup failed',
          errorText: sanitizeChannelRuntimeError(review.error),
        });
        return 'failed';
      }
      if (cancellationRequested) {
        const cancellation = await cancelOperation(review.value.operation);
        if (cancellation === 'failed') return 'failed';
      }
      const reviewed = await poll(review.value.operation, sequence);
      if (reviewed === null) return sequence === actionSequence ? 'failed' : 'stale';
      if (reviewed.state === 'canceled') return 'canceled';
      if (
        reviewed.state !== 'review-ready' ||
        reviewed.result.status === 'blocked' ||
        reviewed.result.planId === null
      ) return 'failed';
      publish({
        ...state,
        pending: true,
        statusText: cancellationRequested ? 'Canceling…' : 'Preparing channel build',
      });
      const apply = await input.bridge.startApply({
        planId: reviewed.result.planId,
        confirmReplace,
      });
      if (!apply.ok) {
        publish({
          ...state,
          pending: false,
          statusText: 'Channel setup failed',
          errorText: sanitizeChannelRuntimeError(apply.error),
        });
        return 'failed';
      }
      if (cancellationRequested) {
        const cancellation = await cancelOperation(apply.value.operation);
        if (cancellation === 'failed') return 'failed';
      }
      const applied = await poll(apply.value.operation, sequence);
      if (applied === null) return sequence === actionSequence ? 'failed' : 'stale';
      if (applied.state === 'canceled') return 'canceled';
      if (applied.state !== 'succeeded') return 'failed';
      await loadStatus();
      return 'succeeded';
    },
  };
}
