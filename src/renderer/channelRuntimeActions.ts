import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import {
  applyChannelStatusResult,
  createChannelRuntimeRendererState,
  markChannelCommitPending,
  markChannelRuntimePending,
  type ChannelRuntimeRendererState,
} from './channelRuntimeState.js';
import type { ChannelSetupCommitMode } from '../contracts/channel.js';

export interface ChannelRuntimeController {
  getState(): ChannelRuntimeRendererState;
  loadStatus(): Promise<void>;
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
  let operationSequence = 0;

  return {
    getState: () => state,
    loadStatus: async () => {
      if (state.pending) {
        return;
      }
      const operationId = ++operationSequence;
      state = markChannelRuntimePending(state);
      input.onStateChanged();
      const result = await input.bridge.getStatus();
      if (operationId !== operationSequence) {
        return;
      }
      state = applyChannelStatusResult(state, result);
      input.onStateChanged();
    },
    commit: async (commitInput) => {
      if (state.pending) {
        return;
      }
      const operationId = ++operationSequence;
      state = markChannelCommitPending(state, commitInput.mode);
      input.onStateChanged();
      const result = await input.bridge.commit(commitInput);
      if (operationId !== operationSequence) {
        return;
      }
      state = applyChannelStatusResult(state, result);
      input.onStateChanged();
    },
  };
}
