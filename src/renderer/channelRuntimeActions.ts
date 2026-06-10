import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import {
  applyChannelStatusResult,
  clearChannelRuntimeActionState,
  createChannelRuntimeRendererState,
  markChannelCommitPending,
  markChannelRuntimeBlocked,
  markChannelRuntimePending,
  type ChannelRuntimeRendererState,
} from './channelRuntimeState.js';
import type { ChannelSetupCommitMode } from '../contracts/channel.js';

export interface ChannelRuntimeController {
  getState(): ChannelRuntimeRendererState;
  loadStatus(): Promise<void>;
  markBlocked(message: string): void;
  clearActionState(): void;
  commit(input: {
    mode: ChannelSetupCommitMode;
    sectionIds: readonly string[];
    confirmReplace?: boolean;
  }): Promise<void>;
}

export function createChannelRuntimeController(input: {
  bridge: LineupDesktopPreloadApi['channelSetup'];
  onStateChanged(): void;
}): ChannelRuntimeController {
  let state = createChannelRuntimeRendererState();
  let statusSequence = 0;
  let actionSequence = 0;
  let pendingKind: 'status' | 'commit' | null = null;
  let staleCommitNeedsStatusRefresh = false;

  const loadStatusInternal = async (): Promise<void> => {
    const operationId = ++statusSequence;
    pendingKind = 'status';
    state = markChannelRuntimePending(state);
    input.onStateChanged();
    const result = await input.bridge.getStatus();
    if (operationId !== statusSequence) {
      return;
    }
    state = applyChannelStatusResult(state, result);
    pendingKind = null;
    staleCommitNeedsStatusRefresh = false;
    input.onStateChanged();
  };

  return {
    getState: () => state,
    loadStatus: async () => {
      if (state.pending) {
        return;
      }
      await loadStatusInternal();
    },
    markBlocked: (message) => {
      ++actionSequence;
      pendingKind = null;
      staleCommitNeedsStatusRefresh = false;
      state = markChannelRuntimeBlocked(state, message);
      input.onStateChanged();
    },
    clearActionState: () => {
      ++actionSequence;
      const preservePending = pendingKind === 'status' || pendingKind === 'commit';
      if (pendingKind === 'commit') {
        staleCommitNeedsStatusRefresh = true;
      }
      state = clearChannelRuntimeActionState(state, { preservePending });
      if (!preservePending) {
        pendingKind = null;
        staleCommitNeedsStatusRefresh = false;
      }
      input.onStateChanged();
    },
    commit: async (commitInput) => {
      if (state.pending) {
        return;
      }
      const operationId = ++actionSequence;
      pendingKind = 'commit';
      state = markChannelCommitPending(state, commitInput.mode);
      input.onStateChanged();
      const result = await input.bridge.commit(commitInput);
      if (operationId !== actionSequence) {
        if (staleCommitNeedsStatusRefresh) {
          await loadStatusInternal();
        }
        return;
      }
      state = applyChannelStatusResult(state, result);
      pendingKind = null;
      staleCommitNeedsStatusRefresh = false;
      input.onStateChanged();
    },
  };
}
