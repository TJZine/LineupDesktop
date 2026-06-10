import {
  channelSetupValidationFailure,
  createChannelSetupCommitRequest,
  createChannelSetupEmptyRequest,
  isChannelSetupResult,
} from './channelBridgeGuards.cjs';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';

export type ChannelSetupBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export type ChannelSetupBridgeChannels = {
  getStatus: string;
  commit: string;
};

export function createChannelSetupBridge(
  invoke: ChannelSetupBridgeInvoke,
  channels: ChannelSetupBridgeChannels,
): LineupDesktopPreloadApi['channelSetup'] {
  return {
    getStatus: async () => {
      const request = createChannelSetupEmptyRequest();
      try {
        const result = await invoke(channels.getStatus, request);
        return isChannelSetupResult(result, request.requestId)
          ? result
          : channelSetupValidationFailure(request.requestId, 'getStatus');
      } catch {
        return channelSetupValidationFailure(request.requestId, 'getStatus');
      }
    },
    commit: async (input) => {
      const request = createChannelSetupCommitRequest(input);
      if (!request.ok) {
        return request.result;
      }
      try {
        const result = await invoke(channels.commit, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isChannelSetupResult(result, request.requestId)
          ? result
          : channelSetupValidationFailure(request.requestId, 'commit');
      } catch {
        return channelSetupValidationFailure(request.requestId, 'commit');
      }
    },
  };
}
