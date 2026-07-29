import type { IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
  LINEUP_SETTINGS_REPLACE_CHANNEL,
} from '../../contracts/ipc.js';
import {
  desktopSettingsFailure,
  desktopSettingsSuccess,
  createDesktopSettingsView,
  isDesktopSettingsGetSnapshotRequest,
  isDesktopSettingsReplaceRequest,
  normalizeDesktopSettingsReplaceValues,
  readDesktopSettingsRequestId,
  type DesktopSettingsIpcResult,
  type DesktopSettingsView,
} from '../../contracts/settings.js';
import {
  DesktopSettingsStoreError,
  type DesktopSettingsStore,
} from '../persistence/desktopSettingsStore.js';

export interface RegisterSettingsIpcHandlersOptions {
  store: Pick<DesktopSettingsStore, 'loadSnapshot' | 'replace'>;
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
        createDesktopSettingsView(await options.store.loadSnapshot()),
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
    try {
      const snapshot = await options.store.replace(
        payload.expectedRevision,
        normalizeDesktopSettingsReplaceValues(payload.values),
      );
      return desktopSettingsSuccess(payload.requestId, createDesktopSettingsView(snapshot));
    } catch (error: unknown) {
      return storeFailure(payload.requestId, error);
    }
  });

  return () => {
    ipc.removeHandler(LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL);
    ipc.removeHandler(LINEUP_SETTINGS_REPLACE_CHANNEL);
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
