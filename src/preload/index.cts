import type { IpcRendererEvent } from 'electron';
import type * as Electron from 'electron';
import type {
  LineupDesktopPreloadApi,
  ShellCapabilities,
  ShellIpcResult,
  ShellStatusEvent,
  WindowFullscreenState,
} from '../contracts/shell.js';

const { contextBridge, ipcRenderer } = require('electron') as typeof Electron;

const LINEUP_SHELL_GET_CAPABILITIES_CHANNEL = 'lineup:shell:getCapabilities';
const LINEUP_WINDOW_INTENT_CHANNEL = 'lineup:window:intent';
const LINEUP_SHELL_STATUS_CHANGED_CHANNEL = 'lineup:shell:statusChanged';
const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'];

function createRequestId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function createWindowIntent(enabled: boolean): {
  intent: 'window.enterFullscreen' | 'window.exitFullscreen';
  requestId: string;
  payload: Record<string, never>;
} {
  return {
    intent: enabled ? 'window.enterFullscreen' : 'window.exitFullscreen',
    requestId: createRequestId('window'),
    payload: {},
  };
}

function isShellStatusEvent(value: unknown): value is ShellStatusEvent {
  if (
    typeof value !== 'object' ||
    value === null ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.timestampMs === 'number' &&
    Number.isFinite(candidate.timestampMs) &&
    typeof candidate.status === 'string' &&
    SHELL_STATUS_VALUES.includes(candidate.status)
  );
}

const lineupDesktop: LineupDesktopPreloadApi = {
  shell: {
    getCapabilities: () =>
      ipcRenderer.invoke(LINEUP_SHELL_GET_CAPABILITIES_CHANNEL) as Promise<
        ShellIpcResult<ShellCapabilities>
      >,
    onStatusChanged: (listener) => {
      if (typeof listener !== 'function') {
        throw new TypeError('Status listener must be a function.');
      }

      const safeListener = (_event: IpcRendererEvent, payload: unknown): void => {
        if (isShellStatusEvent(payload)) {
          listener(payload);
        }
      };

      ipcRenderer.on(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, safeListener);
      return () => {
        ipcRenderer.removeListener(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, safeListener);
      };
    },
  },
  window: {
    setFullscreen: (enabled) => {
      if (typeof enabled !== 'boolean') {
        return Promise.resolve({
          ok: false,
          error: {
            code: 'validation-failed',
            message: 'Fullscreen state must be boolean.',
          },
          requestId: createRequestId('window-validation'),
        });
      }
      return ipcRenderer.invoke(
        LINEUP_WINDOW_INTENT_CHANNEL,
        createWindowIntent(enabled),
      ) as Promise<ShellIpcResult<WindowFullscreenState>>;
    },
  },
};

contextBridge.exposeInMainWorld('lineupDesktop', lineupDesktop);
