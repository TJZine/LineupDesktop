import {
  createCustomChannelDeleteRequest,
  createCustomChannelDraftRequest,
  createCustomChannelDuplicateDraftRequest,
  createCustomChannelEmptyRequest,
  createCustomChannelListMediaRequest,
  createCustomChannelMetadataRequest,
  createCustomChannelReorderRequest,
  createCustomChannelVisibilityRequest,
  customChannelValidationFailure,
  isCustomChannelDraftResult,
  isCustomChannelMediaPageResult,
  isCustomChannelMetadataResult,
  isCustomChannelMutationResult,
  isCustomChannelSnapshotResult,
  isCustomChannelValidationResult,
} from './customChannelBridgeGuards.cjs';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type {
  CustomChannelDraftValidationSummary,
  CustomChannelMutationResult,
} from '../contracts/customChannels.js';

export type CustomChannelBridgeInvoke = (
  channel: string,
  request: { requestId: string; payload: unknown },
) => Promise<unknown>;

export type CustomChannelBridgeChannels = {
  getSnapshot: string;
  listMedia: string;
  getMediaMetadata: string;
  validateDraft: string;
  saveDraft: string;
  deleteChannel: string;
  duplicateChannelDraft: string;
  reorderChannels: string;
  setChannelVisibility: string;
};

export function createCustomChannelBridge(
  invoke: CustomChannelBridgeInvoke,
  channels: CustomChannelBridgeChannels,
): LineupDesktopPreloadApi['customChannels'] {
  return {
    getSnapshot: async () => {
      const request = createCustomChannelEmptyRequest('getSnapshot');
      try {
        const result = await invoke(channels.getSnapshot, request);
        return isCustomChannelSnapshotResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'getSnapshot');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'getSnapshot',
          'Custom channel invoke failed.',
        );
      }
    },
    listMedia: async (input) => {
      const request = createCustomChannelListMediaRequest(input);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.listMedia, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelMediaPageResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'listMedia');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'listMedia',
          'Custom channel invoke failed.',
        );
      }
    },
    getMediaMetadata: async (input) => {
      const request = createCustomChannelMetadataRequest(input);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.getMediaMetadata, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelMetadataResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'getMediaMetadata');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'getMediaMetadata',
          'Custom channel invoke failed.',
        );
      }
    },
    validateDraft: async (input) => {
      const request = createCustomChannelDraftRequest<CustomChannelDraftValidationSummary>(
        'validateDraft',
        input,
      );
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.validateDraft, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelValidationResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'validateDraft');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'validateDraft',
          'Custom channel invoke failed.',
        );
      }
    },
    saveDraft: async (input) => {
      const request = createCustomChannelDraftRequest<CustomChannelMutationResult>(
        'saveDraft',
        input,
      );
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.saveDraft, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelMutationResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'saveDraft');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'saveDraft',
          'Custom channel invoke failed.',
        );
      }
    },
    deleteChannel: async (input) => {
      const request = createCustomChannelDeleteRequest(input);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.deleteChannel, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelMutationResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'deleteChannel');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'deleteChannel',
          'Custom channel invoke failed.',
        );
      }
    },
    duplicateChannelDraft: async (input) => {
      const request = createCustomChannelDuplicateDraftRequest(input);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.duplicateChannelDraft, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelDraftResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'duplicateChannelDraft');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'duplicateChannelDraft',
          'Custom channel invoke failed.',
        );
      }
    },
    reorderChannels: async (input) => {
      const request = createCustomChannelReorderRequest(input);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.reorderChannels, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelMutationResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'reorderChannels');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'reorderChannels',
          'Custom channel invoke failed.',
        );
      }
    },
    setChannelVisibility: async (input) => {
      const request = createCustomChannelVisibilityRequest(input);
      if (!request.ok) return request.result;
      try {
        const result = await invoke(channels.setChannelVisibility, {
          requestId: request.requestId,
          payload: request.payload,
        });
        return isCustomChannelMutationResult(result, request.requestId)
          ? result
          : customChannelValidationFailure(request.requestId, 'setChannelVisibility');
      } catch {
        return customChannelValidationFailure(
          request.requestId,
          'setChannelVisibility',
          'Custom channel invoke failed.',
        );
      }
    },
  };
}
