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
  shutdown(): Promise<void>;
  cancelActive(): Promise<'accepted' | 'unavailable' | 'failed' | 'skipped'>;
  startReview(config: NormalizedChannelSetupConfig): Promise<ChannelRuntimeActionOutcome>;
  applyReviewed(confirmReplace: boolean): Promise<ChannelRuntimeActionOutcome>;
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
  let shutdownRequested = false;

  const publish = (next: ChannelRuntimeRendererState): void => {
    state = next;
    if (!shutdownRequested) input.onStateChanged();
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
    publish({
      ...state,
      pending: false,
      statusText: 'Channel setup failed',
      errorText: 'Channel setup operation timed out. Try again.',
    });
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
      cancellationRequested = false;
      publish({ ...clearChannelRuntimeActionState(state), operation: null });
    },
    shutdown: async () => {
      if (shutdownRequested) return;
      shutdownRequested = true;
      cancellationRequested = true;
      actionSequence += 1;
      const operation = state.operation;
      if (
        operation === null ||
        operation.state === 'review-ready' ||
        operation.state === 'succeeded' ||
        operation.state === 'failed' ||
        operation.state === 'canceled' ||
        operation.state === 'canceling' ||
        operation.phase === 'persist' ||
        operation.phase === 'refresh-guide'
      ) return;
      await input.bridge.cancel({ operationId: operation.operationId }).catch(() => undefined);
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
        if (!state.pending) return 'skipped';
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
    startReview: async (config) => {
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
      if (reviewed.state !== 'review-ready') return 'failed';
      return reviewed.result.status === 'blocked' || reviewed.result.planId === null
        ? 'skipped'
        : 'succeeded';
    },
    applyReviewed: async (confirmReplace) => {
      const reviewed = state.operation;
      if (
        state.pending ||
        reviewed?.kind !== 'review' ||
        reviewed.state !== 'review-ready' ||
        reviewed.result.planId === null ||
        reviewed.result.status === 'blocked'
      ) return 'skipped';
      cancellationRequested = false;
      const sequence = ++actionSequence;
      publish({
        ...state,
        pending: true,
        statusText: 'Preparing channel build',
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
