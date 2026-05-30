import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import {
  applyChannelStatusResult,
  createChannelRuntimeRendererState,
  markChannelRuntimePending,
  type ChannelRuntimeRendererState,
} from './channelRuntimeState.js';

export interface ChannelRuntimeController {
  getState(): ChannelRuntimeRendererState;
  loadStatus(): Promise<void>;
}

export function createChannelRuntimeController(input: {
  bridge: LineupDesktopPreloadApi['channelSetup'];
  onStateChanged(): void;
}): ChannelRuntimeController {
  let state = createChannelRuntimeRendererState();

  return {
    getState: () => state,
    loadStatus: async () => {
      state = markChannelRuntimePending(state);
      input.onStateChanged();
      const result = await input.bridge.getStatus();
      state = applyChannelStatusResult(state, result);
      input.onStateChanged();
    },
  };
}
