export type PlayerBackend =
  | 'desktop-fake-host'
  | 'desktop-external-mpv-poc'
  | 'desktop-libmpv-helper'
  | 'desktop-libmpv-addon';

export type PlayerStatus =
  | 'idle'
  | 'initializing'
  | 'ready'
  | 'loading'
  | 'buffering'
  | 'playing'
  | 'paused'
  | 'seeking'
  | 'stalled'
  | 'ended'
  | 'error'
  | 'destroyed';

export type PlayerErrorCategory =
  | 'source'
  | 'auth'
  | 'network'
  | 'compatibility'
  | 'engine'
  | 'render'
  | 'operation'
  | 'cleanup'
  | 'unknown';

export interface RendererTrackIdentity {
  uiId: string;
  label: string;
  kind: 'audio' | 'subtitle' | 'video';
}

export interface PlaybackCapabilityProfile {
  backend: PlayerBackend;
  containers: readonly string[];
  videoCodecs: readonly string[];
  audioCodecs: readonly string[];
  subtitleFormats: readonly string[];
  supportsHeaderAuth: boolean;
  supportsNativeFullscreen: boolean;
  supportsOverlayComposition: 'unknown' | 'supported' | 'unsupported';
}

export interface PlayerSnapshot {
  requestId: string | null;
  status: PlayerStatus;
  positionMs: number;
  durationMs: number;
  selectedAudioTrackId: string | null;
  selectedSubtitleTrackId: string | null;
  errorCategory: PlayerErrorCategory | null;
}
