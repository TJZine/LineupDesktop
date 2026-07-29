import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import {
  isSettingsGetSnapshotRequest,
  isSettingsAudioOutputResult,
  isSettingsReplaceRequest,
  isSettingsResult,
  readSettingsRequestId,
  settingsBridgeFailure,
} from './settingsBridgeGuards.cjs';

export type SettingsBridgeInvoke = (channel: string, input: unknown) => Promise<unknown>;

export interface SettingsBridgeChannels {
  getSnapshot: string;
  replace: string;
  getAudioOutputs: string;
}

export function createSettingsBridge(
  invoke: SettingsBridgeInvoke,
  channels: SettingsBridgeChannels,
): LineupDesktopPreloadApi['settings'] {
  return {
    getSnapshot: async (input) => {
      const requestId = readSettingsRequestId(input);
      if (!isSettingsGetSnapshotRequest(input)) {
        return settingsBridgeFailure(requestId, 'validation-failed');
      }
      return invokeSettings(invoke, channels.getSnapshot, input, requestId);
    },
    replace: async (input) => {
      const requestId = readSettingsRequestId(input);
      if (!isSettingsReplaceRequest(input)) {
        return settingsBridgeFailure(requestId, 'validation-failed');
      }
      return invokeSettings(invoke, channels.replace, input, requestId);
    },
    getAudioOutputs: async (input) => {
      const requestId = readSettingsRequestId(input);
      if (!isSettingsGetSnapshotRequest(input)) {
        return settingsBridgeFailure(requestId, 'validation-failed');
      }
      let result: unknown;
      try {
        result = await invoke(channels.getAudioOutputs, input);
      } catch {
        return settingsBridgeFailure(requestId, 'operation-failed');
      }
      if (!isSettingsAudioOutputResult(result, requestId)) {
        return settingsBridgeFailure(requestId, 'validation-failed');
      }
      return result as Awaited<
        ReturnType<LineupDesktopPreloadApi['settings']['getAudioOutputs']>
      >;
    },
  };
}

async function invokeSettings(
  invoke: SettingsBridgeInvoke,
  channel: string,
  input: unknown,
  requestId: string,
) {
  let result: unknown;
  try {
    result = await invoke(channel, input);
  } catch {
    return settingsBridgeFailure(requestId, 'operation-failed');
  }
  if (!isSettingsResult(result, requestId)) {
    return settingsBridgeFailure(requestId, 'validation-failed');
  }
  return result as Awaited<ReturnType<LineupDesktopPreloadApi['settings']['getSnapshot']>>;
}
