export type DesktopIpcOwner = 'renderer' | 'preload' | 'main' | 'native-helper';

export type RendererIntent =
  | 'player.load'
  | 'player.play'
  | 'player.pause'
  | 'player.stop'
  | 'player.selectAudio'
  | 'player.selectSubtitle'
  | 'window.enterFullscreen'
  | 'window.exitFullscreen';

export interface RendererIntentEnvelope<TPayload = unknown> {
  intent: RendererIntent;
  requestId: string;
  payload: TPayload;
}

export const LINEUP_SHELL_GET_CAPABILITIES_CHANNEL =
  'lineup:shell:getCapabilities' as const;

export const LINEUP_WINDOW_INTENT_CHANNEL = 'lineup:window:intent' as const;

export const LINEUP_SHELL_STATUS_CHANGED_CHANNEL =
  'lineup:shell:statusChanged' as const;

export const RENDERER_FORBIDDEN_PAYLOAD_KEYS = [
  'persistentToken',
  'rawAuthHeaders',
  'tokenizedUrl',
  'nativeHandle',
] as const;

export type RendererForbiddenPayloadKey =
  (typeof RENDERER_FORBIDDEN_PAYLOAD_KEYS)[number];
