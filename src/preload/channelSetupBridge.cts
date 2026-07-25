import {
  channelSetupValidationFailure,
  createChannelSetupEmptyRequest,
  createChannelSetupOperationRequest,
  createChannelSetupStartApplyRequest,
  createChannelSetupStartReviewRequest,
  isChannelSetupAcceptedResult,
  isChannelSetupCancelResult,
  isChannelSetupOperationResult,
  isChannelSetupSummaryResult,
} from './channelBridgeGuards.cjs';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { ChannelSetupIpcResult } from '../contracts/channel.js';

export type ChannelSetupBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export type ChannelSetupBridgeChannels = {
  getStatus: string;
  startReview: string;
  startApply: string;
  getOperation: string;
  cancel: string;
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
        return isChannelSetupSummaryResult(result, request.requestId)
          ? result
          : channelSetupValidationFailure(request.requestId, 'getStatus');
      } catch {
        return channelSetupValidationFailure(request.requestId, 'getStatus');
      }
    },
    startReview: (input) =>
      invokeRequest(
        createChannelSetupStartReviewRequest(input),
        channels.startReview,
        'startReview',
        invoke,
        isChannelSetupAcceptedResult,
      ),
    startApply: (input) =>
      invokeRequest(
        createChannelSetupStartApplyRequest(input),
        channels.startApply,
        'startApply',
        invoke,
        isChannelSetupAcceptedResult,
      ),
    getOperation: (input) =>
      invokeRequest(
        createChannelSetupOperationRequest(input, 'getOperation'),
        channels.getOperation,
        'getOperation',
        invoke,
        isChannelSetupOperationResult,
      ),
    cancel: (input) =>
      invokeRequest(
        createChannelSetupOperationRequest(input, 'cancel'),
        channels.cancel,
        'cancel',
        invoke,
        isChannelSetupCancelResult,
      ),
  };
}

async function invokeRequest<T>(
  request:
    | { ok: true; requestId: string; payload: unknown }
    | { ok: false; result: ChannelSetupIpcResult<never> },
  channel: string,
  operation: 'startReview' | 'startApply' | 'getOperation' | 'cancel',
  invoke: ChannelSetupBridgeInvoke,
  isResult: (value: unknown, requestId: string) => value is ChannelSetupIpcResult<T>,
): Promise<ChannelSetupIpcResult<T>> {
  if (!request.ok) return request.result;
  try {
    const result = await invoke(channel, {
      requestId: request.requestId,
      payload: request.payload,
    });
    return isResult(result, request.requestId)
      ? result
      : channelSetupValidationFailure(request.requestId, operation);
  } catch {
    return channelSetupValidationFailure(request.requestId, operation);
  }
}
