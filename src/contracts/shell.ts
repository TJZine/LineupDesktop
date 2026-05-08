import type { RendererIntentEnvelope } from './ipc.js';

export const LINEUP_PROTOCOL_ORIGIN = 'lineup://shell' as const;
export const LINEUP_SHELL_URL = 'lineup://shell/index.html' as const;
export const LINEUP_APP_NAME = 'Lineup Desktop' as const;

export const SHELL_CAPABILITY_PLATFORMS = ['darwin', 'linux', 'win32', 'unknown'] as const;
export const SHELL_MODES = ['development', 'smoke', 'production'] as const;
export const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'] as const;
export const SHELL_ERROR_CODES = [
  'unauthorized',
  'validation-failed',
  'operation-failed',
] as const;

export type ShellCapabilityPlatform = (typeof SHELL_CAPABILITY_PLATFORMS)[number];
export type ShellMode = (typeof SHELL_MODES)[number];
export type ShellStatusValue = (typeof SHELL_STATUS_VALUES)[number];
export type ShellErrorCode = (typeof SHELL_ERROR_CODES)[number];

export interface ShellCapabilities {
  appName: typeof LINEUP_APP_NAME;
  appVersion: string;
  platform: ShellCapabilityPlatform;
  shellMode: ShellMode;
  protocolOrigin: typeof LINEUP_PROTOCOL_ORIGIN;
}

export interface ShellStatusEvent {
  status: ShellStatusValue;
  timestampMs: number;
}

export interface WindowFullscreenState {
  enabled: boolean;
}

export type ShellIpcResult<T> =
  | { ok: true; value: T; requestId: string }
  | {
      ok: false;
      error: { code: ShellErrorCode; message: string };
      requestId: string;
    };

export type WindowFullscreenIntentEnvelope = RendererIntentEnvelope<Record<string, never>> & {
  intent: 'window.enterFullscreen' | 'window.exitFullscreen';
};

export interface LineupDesktopPreloadApi {
  shell: {
    getCapabilities: () => Promise<ShellIpcResult<ShellCapabilities>>;
    onStatusChanged: (listener: (event: ShellStatusEvent) => void) => () => void;
  };
  window: {
    setFullscreen: (
      enabled: boolean,
    ) => Promise<ShellIpcResult<WindowFullscreenState>>;
  };
}

export function isShellStatusEvent(value: unknown): value is ShellStatusEvent {
  if (!isPlainRecord(value)) {
    return false;
  }
  return (
    typeof value.timestampMs === 'number' &&
    Number.isFinite(value.timestampMs) &&
    SHELL_STATUS_VALUES.includes(value.status as ShellStatusValue)
  );
}

export function isWindowFullscreenIntentEnvelope(
  value: unknown,
): value is WindowFullscreenIntentEnvelope {
  if (!isPlainRecord(value) || typeof value.requestId !== 'string') {
    return false;
  }
  if (
    value.intent !== 'window.enterFullscreen' &&
    value.intent !== 'window.exitFullscreen'
  ) {
    return false;
  }
  if (!isPlainRecord(value.payload)) {
    return false;
  }
  return Object.keys(value.payload).length === 0;
}

export function shellSuccess<T>(requestId: string, value: T): ShellIpcResult<T> {
  return { ok: true, value, requestId };
}

export function shellFailure<T>(
  requestId: string,
  code: ShellErrorCode,
  message: string,
): ShellIpcResult<T> {
  return { ok: false, error: { code, message }, requestId };
}

export function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}
