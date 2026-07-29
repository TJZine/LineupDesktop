import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
  LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL,
  LINEUP_SETTINGS_REPLACE_CHANNEL,
} from '../../contracts/ipc.js';
import {
  desktopSettingsFailure,
  desktopSettingsSuccess,
  createDesktopSettingsView,
  isDesktopSettingsGetAudioOutputsRequest,
  isDesktopSettingsGetSnapshotRequest,
  isDesktopSettingsReplaceRequest,
  normalizeDesktopSettingsReplaceValues,
  readDesktopSettingsRequestId,
  type DesktopSettingsIpcResult,
  type DesktopAudioOutputList,
  type DesktopSettingsView,
} from '../../contracts/settings.js';
import {
  DesktopSettingsStoreError,
  type DesktopSettingsStore,
} from '../persistence/desktopSettingsStore.js';
import type { DesktopSettingsPolicy } from './desktopSettingsPolicy.js';
import type { SettingsAudioOutputOwner } from './settingsAudioOutputOwner.js';

export interface RegisterSettingsIpcHandlersOptions {
  store: Pick<DesktopSettingsStore, 'loadSnapshot' | 'replace'>;
  policy?: Pick<DesktopSettingsPolicy, 'acceptSnapshot' | 'getCapabilityProjection'>;
  audioOutputOwner?: Pick<SettingsAudioOutputOwner, 'getAudioOutputs'>;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  ipcMain: Pick<IpcMain, 'handle' | 'removeHandler'>;
}

export type SettingsIpcTeardown = () => void;

export function registerSettingsIpcHandlers(
  options: RegisterSettingsIpcHandlersOptions,
): SettingsIpcTeardown {
  const ipc = options.ipcMain;

  ipc.handle(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL, async (event, payload: unknown) => {
    const requestId = readDesktopSettingsRequestId(payload);
    if (!options.isAuthorizedEvent(event)) {
      return desktopSettingsFailure(requestId, 'unauthorized');
    }
    if (!isDesktopSettingsGetSnapshotRequest(payload)) {
      return desktopSettingsFailure(requestId, 'validation-failed');
    }
    try {
      return desktopSettingsSuccess(
        payload.requestId,
        createPolicyView(options, await options.store.loadSnapshot()),
      );
    } catch (error: unknown) {
      return storeFailure(payload.requestId, error);
    }
  });

  ipc.handle(LINEUP_SETTINGS_REPLACE_CHANNEL, async (event, payload: unknown) => {
    const requestId = readDesktopSettingsRequestId(payload);
    if (!options.isAuthorizedEvent(event)) {
      return desktopSettingsFailure(requestId, 'unauthorized');
    }
    if (!isDesktopSettingsReplaceRequest(payload)) {
      return desktopSettingsFailure(requestId, 'validation-failed');
    }
    let snapshot: Awaited<ReturnType<typeof options.store.replace>>;
    try {
      snapshot = await options.store.replace(
        payload.expectedRevision,
        normalizeDesktopSettingsReplaceValues(payload.values),
      );
    } catch (error: unknown) {
      return storeFailure(payload.requestId, error);
    }
    try {
      options.policy?.acceptSnapshot(snapshot);
    } catch {
      // The durable replace already committed; policy refresh is best-effort here.
    }
    return desktopSettingsSuccess(payload.requestId, createPolicyView(options, snapshot));
  });

  ipc.handle(LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL, async (event, payload: unknown) => {
    const requestId = readDesktopSettingsRequestId(payload);
    if (!options.isAuthorizedEvent(event)) {
      return desktopSettingsFailure(requestId, 'unauthorized');
    }
    if (!isDesktopSettingsGetAudioOutputsRequest(payload)) {
      return desktopSettingsFailure(requestId, 'validation-failed');
    }
    try {
      if (options.audioOutputOwner === undefined) {
        return desktopSettingsSuccess(
          payload.requestId,
          unavailableAudioOutputs('helper-unavailable'),
        );
      }
      return desktopSettingsSuccess(payload.requestId, await options.audioOutputOwner.getAudioOutputs());
    } catch {
      return desktopSettingsFailure(payload.requestId, 'operation-failed');
    }
  });

  return () => {
    ipc.removeHandler(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL);
    ipc.removeHandler(LINEUP_SETTINGS_REPLACE_CHANNEL);
    ipc.removeHandler(LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL);
  };
}

function createPolicyView(
  options: RegisterSettingsIpcHandlersOptions,
  snapshot: Parameters<typeof createDesktopSettingsView>[0],
): DesktopSettingsView {
  const view = createDesktopSettingsView(snapshot);
  return {
    snapshot: view.snapshot,
    capabilities: options.policy?.getCapabilityProjection() ?? view.capabilities,
  };
}

function unavailableAudioOutputs(
  reason: 'helper-unavailable',
): DesktopAudioOutputList {
  return {
    status: 'unavailable',
    reason,
    outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
  };
}

function storeFailure(
  requestId: string,
  error: unknown,
): DesktopSettingsIpcResult<DesktopSettingsView> {
  if (error instanceof DesktopSettingsStoreError) {
    return desktopSettingsFailure(requestId, error.code);
  }
  return desktopSettingsFailure(requestId, 'operation-failed');
}
