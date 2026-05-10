export const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'] as const;

export const PLAYER_ERROR_CATEGORIES = [
  'source',
  'authentication',
  'authorization',
  'network',
  'unsupported-media',
  'unsupported-capability',
  'timeout',
  'aborted',
  'stale-request',
  'engine-failure',
  'helper-failure',
  'render-failure',
  'track-failure',
  'cleanup-failure',
  'validation-failure',
  'unknown',
] as const;

export const PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS = [
  'rawMediaUrl',
  'tokenizedUrl',
  'authHeaders',
  'rawAuthHeaders',
  'persistentToken',
  'credentialMaterial',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
] as const;

export const PLAYER_STATUS_VALUES = [
  'idle',
  'loading',
  'ready',
  'buffering',
  'playing',
  'paused',
  'seeking',
  'stalled',
  'ended',
  'error',
  'destroyed',
] as const;

export const PLAYER_COMMAND_VALUES = [
  'load',
  'play',
  'pause',
  'stop',
  'seek.absolute',
  'seek.relative',
  'volume.set',
  'mute.set',
  'track.audio.select',
  'track.subtitle.select',
] as const;

export const PLAYER_RENDERER_INTENT_VALUES = [
  'player.load',
  'player.play',
  'player.pause',
  'player.stop',
  'player.seekAbsolute',
  'player.seekRelative',
  'player.setVolume',
  'player.setMute',
  'player.selectAudio',
  'player.selectSubtitle',
] as const;

export const PLAYER_TRACK_KIND_VALUES = ['audio', 'subtitle', 'video'] as const;

export const PLAYER_TRACK_DELIVERY_TYPE_VALUES = [
  'embedded',
  'sidecar',
  'external',
  'burned-in',
  'unknown',
] as const;
