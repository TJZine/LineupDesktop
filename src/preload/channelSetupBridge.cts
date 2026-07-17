import {
  channelSetupValidationFailure,
  createChannelSetupBuildRequest,
  createChannelSetupCancelRequest,
  createChannelSetupConfigRequest,
  createChannelSetupEmptyRequest,
  createLegacyChannelSetupCommitRequest,
  createLegacyChannelSetupEmptyRequest,
  isChannelSetupBuildResult,
  isChannelSetupCancelResult,
  isChannelSetupPreviewResult,
  isChannelSetupProgressEnvelope,
  isChannelSetupRecordResult,
  isChannelSetupReviewResult,
  isLegacyChannelSetupResult,
  legacyValidationFailure,
} from './channelBridgeGuards.cjs';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { ChannelSetupWorkflowIpcResult } from '../contracts/channel.js';

export type ChannelSetupBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;
export type ChannelSetupBridgeListener = (event: unknown, value: unknown) => void;
export type ChannelSetupBridgeEvents = {
  on(channel: string, listener: ChannelSetupBridgeListener): void;
  removeListener(channel: string, listener: ChannelSetupBridgeListener): void;
};
export type ChannelSetupBridgeChannels = {
  getStatus: string;
  commit: string;
  getRecord: string;
  preview: string;
  review: string;
  build: string;
  cancelBuild: string;
  progress: string;
};

export function createChannelSetupBridge(
  invoke: ChannelSetupBridgeInvoke,
  events: ChannelSetupBridgeEvents,
  channels: ChannelSetupBridgeChannels,
  createRequestId: (prefix: string) => string,
): LineupDesktopPreloadApi['channelSetup'] {
  return {
    getStatus: async () => {
      const request = createLegacyChannelSetupEmptyRequest(createRequestId);
      try {
        const result = await invoke(channels.getStatus, request);
        return isLegacyChannelSetupResult(result, request.requestId, 'getStatus')
          ? result
          : legacyValidationFailure(request.requestId, 'getStatus');
      } catch {
        return legacyValidationFailure(request.requestId, 'getStatus');
      }
    },
    commit: async (input) => {
      const request = createLegacyChannelSetupCommitRequest(input, createRequestId);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.commit, { requestId: request.requestId, payload: request.payload });
        return isLegacyChannelSetupResult(result, request.requestId, 'commit')
          ? result
          : legacyValidationFailure(request.requestId, 'commit');
      } catch {
        return legacyValidationFailure(request.requestId, 'commit');
      }
    },
    getRecord: async () => {
      const request = createChannelSetupEmptyRequest('getRecord', createRequestId);
      return invokeValidated(channels.getRecord, request, 'getRecord', isChannelSetupRecordResult);
    },
    preview: async (input) => {
      const request = createChannelSetupConfigRequest('preview', input, createRequestId);
      return invokeValidated(channels.preview, request, 'preview', isChannelSetupPreviewResult);
    },
    review: async (input) => {
      const request = createChannelSetupConfigRequest('review', input, createRequestId);
      return invokeValidated(channels.review, request, 'review', isChannelSetupReviewResult);
    },
    build: async (input, onProgress) => {
      const request = createChannelSetupBuildRequest(input, createRequestId);
      if (!request.ok) return request.result;
      if (typeof onProgress !== 'function') {
        return channelSetupValidationFailure(request.requestId, 'build', 'Channel setup progress callback is invalid.');
      }
      let lastSequence = 0;
      const listener: ChannelSetupBridgeListener = (_event, value) => {
        if (!isChannelSetupProgressEnvelope(value, request.payload.buildId, request.requestId) ||
          value.sequence <= lastSequence) return;
        lastSequence = value.sequence;
        try { onProgress(value.progress); } catch { /* Renderer callbacks cannot break preload custody. */ }
      };
      events.on(channels.progress, listener);
      try {
        return await invokeValidated(
          channels.build,
          request,
          'build',
          (value, requestId) => isChannelSetupBuildResult(value, requestId, request.payload.buildId),
        );
      } finally {
        events.removeListener(channels.progress, listener);
      }
    },
    cancelBuild: async (input) => {
      const request = createChannelSetupCancelRequest(input, createRequestId);
      if (!request.ok) return request.result;
      return invokeValidated(
        channels.cancelBuild,
        request,
        'cancelBuild',
        (value, requestId) => isChannelSetupCancelResult(value, requestId, request.payload.buildId),
      );
    },
  };

  async function invokeValidated<TValue>(
    channel: string,
    request: { ok: true; requestId: string; payload: unknown } |
      { ok: false; result: ChannelSetupWorkflowIpcResult<TValue> },
    operation: 'getRecord' | 'preview' | 'review' | 'build' | 'cancelBuild',
    guard: (value: unknown, requestId: string) => value is ChannelSetupWorkflowIpcResult<TValue>,
  ): Promise<ChannelSetupWorkflowIpcResult<TValue>> {
    if (!request.ok) return request.result;
    try {
      const result = await invoke(channel, { requestId: request.requestId, payload: request.payload });
      return guard(result, request.requestId)
        ? result
        : channelSetupValidationFailure(request.requestId, operation);
    } catch {
      return channelSetupValidationFailure(request.requestId, operation);
    }
  }
}
