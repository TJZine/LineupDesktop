import type { IpcRendererEvent } from 'electron';
import type * as Electron from 'electron';
import type {
  LineupDesktopPreloadApi,
  ShellCapabilities,
  ShellIpcResult,
  ShellStatusEvent,
  WindowFullscreenState,
} from '../contracts/shell.js';
import type {
  PlayerDispatchResult,
  PlayerEvent,
  PlayerIpcResult,
  PlayerSnapshot,
} from '../contracts/player.js';
import type { PlayerRendererIntentEnvelope } from '../contracts/ipc.js';

const { contextBridge, ipcRenderer } = require('electron') as typeof Electron;

/** Sandboxed preload exposes only the typed bridge: main events are runtime-guarded before callbacks, invoke results are typed envelopes expected from authorized handlers, and privileged objects/secrets are not intentionally forwarded. */ const LINEUP_SHELL_GET_CAPABILITIES_CHANNEL = 'lineup:shell:getCapabilities';
const LINEUP_WINDOW_INTENT_CHANNEL = 'lineup:window:intent';
const LINEUP_SHELL_STATUS_CHANGED_CHANNEL = 'lineup:shell:statusChanged';
const LINEUP_PLAYER_COMMAND_CHANNEL = 'lineup:player:command';
const LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL = 'lineup:player:getSnapshot';
const LINEUP_PLAYER_CLEANUP_CHANNEL = 'lineup:player:cleanup';
const LINEUP_PLAYER_EVENT_CHANNEL = 'lineup:player:event';
const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'] as const;
const PLAYER_ERROR_CATEGORIES = [
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
const PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS = [
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
const PLAYER_STATUS_VALUES = [
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
const PLAYER_COMMAND_VALUES = [
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
const PLAYER_RENDERER_INTENT_VALUES = [
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
const PLAYER_TRACK_KIND_VALUES = ['audio', 'subtitle', 'video'] as const;
const PLAYER_TRACK_DELIVERY_TYPE_VALUES = [
  'embedded',
  'sidecar',
  'external',
  'burned-in',
  'unknown',
] as const;

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
  if (!isPlainRecord(value)) {
    return false;
  }
  return (
    typeof value.timestampMs === 'number' &&
    Number.isFinite(value.timestampMs) &&
    isStringInSet(value.status, SHELL_STATUS_VALUES)
  );
}

function isPlayerRendererIntentEnvelope(value: unknown): value is PlayerRendererIntentEnvelope<unknown> {
  return (
    isPlainRecord(value) &&
    isStringInSet(value.intent, PLAYER_RENDERER_INTENT_VALUES) &&
    typeof value.requestId === 'string' &&
    value.requestId.trim().length > 0 &&
    Object.hasOwn(value, 'payload')
  );
}

function isPlayerEvent(value: unknown): value is PlayerEvent {
  if (!isPlainRecord(value) || hasForbiddenPrivilegedField(value)) {
    return false;
  }

  switch (value.event) {
    case 'state.changed':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'snapshot']) &&
        isNullableNonEmptyString(value.requestId) &&
        isPlayerSnapshot(value.snapshot)
      );
    case 'time.updated':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'positionMs', 'durationMs']) &&
        isNonEmptyString(value.requestId) &&
        isFiniteNonNegativeNumber(value.positionMs) &&
        isNullableFiniteNonNegativeNumber(value.durationMs)
      );
    case 'buffer.updated':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'bufferedRanges']) &&
        isNonEmptyString(value.requestId) &&
        isTimeRanges(value.bufferedRanges)
      );
    case 'media.loaded':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'media', 'durationMs']) &&
        isNonEmptyString(value.requestId) &&
        isPlayerMediaSummary(value.media) &&
        isNullableFiniteNonNegativeNumber(value.durationMs)
      );
    case 'tracks.changed':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'tracks']) &&
        isNonEmptyString(value.requestId) &&
        isPlayerTracks(value.tracks)
      );
    case 'track.selection.changed':
      return (
        hasOnlyKeys(value, [
          'event',
          'requestId',
          'audioTrackId',
          'subtitleTrackId',
          'videoTrackId',
        ]) &&
        isNonEmptyString(value.requestId) &&
        isNullableNonEmptyString(value.audioTrackId) &&
        isNullableNonEmptyString(value.subtitleTrackId) &&
        isNullableNonEmptyString(value.videoTrackId)
      );
    case 'command.settled': {
      if (
        !isNonEmptyString(value.requestId) ||
        !isStringInSet(value.command, PLAYER_COMMAND_VALUES) ||
        typeof value.ok !== 'boolean'
      ) {
        return false;
      }
      if (value.ok) {
        return hasOnlyKeys(value, ['event', 'requestId', 'command', 'ok']);
      }
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'command', 'ok', 'error']) &&
        isPlayerError(value.error)
      );
    }
    case 'ended':
      return (
        hasOnlyKeys(value, ['event', 'requestId']) &&
        isNonEmptyString(value.requestId)
      );
    case 'warning':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'warning']) &&
        isNullableNonEmptyString(value.requestId) &&
        isPlayerError(value.warning)
      );
    case 'error':
      return (
        hasOnlyKeys(value, ['event', 'requestId', 'error']) &&
        isNullableNonEmptyString(value.requestId) &&
        isPlayerError(value.error)
      );
    default:
      return false;
  }
}

function isPlayerSnapshot(value: unknown): value is PlayerSnapshot {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, [
      'requestId',
      'status',
      'media',
      'capabilityProfileId',
      'positionMs',
      'durationMs',
      'bufferedRanges',
      'playing',
      'volume',
      'muted',
      'playbackRate',
      'selectedAudioTrackId',
      'selectedSubtitleTrackId',
      'selectedVideoTrackId',
      'tracks',
      'lastError',
    ]) &&
    isNullableNonEmptyString(value.requestId) &&
    isStringInSet(value.status, PLAYER_STATUS_VALUES) &&
    (value.media === null || isPlayerMediaSummary(value.media)) &&
    (value.capabilityProfileId === null || isNonEmptyString(value.capabilityProfileId)) &&
    isFiniteNonNegativeNumber(value.positionMs) &&
    isNullableFiniteNonNegativeNumber(value.durationMs) &&
    isTimeRanges(value.bufferedRanges) &&
    typeof value.playing === 'boolean' &&
    isFiniteRangeNumber(value.volume, 0, 1) &&
    typeof value.muted === 'boolean' &&
    isFiniteNonNegativeNumber(value.playbackRate) &&
    isNullableNonEmptyString(value.selectedAudioTrackId) &&
    isNullableNonEmptyString(value.selectedSubtitleTrackId) &&
    isNullableNonEmptyString(value.selectedVideoTrackId) &&
    isPlayerTracks(value.tracks) &&
    (value.lastError === null || isPlayerError(value.lastError))
  );
}

function isPlayerMediaSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'title'], ['subtitle', 'durationMs', 'container']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title) &&
    (value.subtitle === undefined || typeof value.subtitle === 'string') &&
    (value.durationMs === undefined || isNullableFiniteNonNegativeNumber(value.durationMs)) &&
    (value.container === undefined || typeof value.container === 'string')
  );
}

function isPlayerTracks(value: unknown): boolean {
  return Array.isArray(value) && value.every((track) => isPlayerTrack(track));
}

function isPlayerTrack(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['id', 'kind', 'label', 'selected', 'available'],
      [
        'language',
        'codec',
        'format',
        'channelCount',
        'deliveryType',
        'forced',
        'default',
      ],
    ) &&
    isNonEmptyString(value.id) &&
    isStringInSet(value.kind, PLAYER_TRACK_KIND_VALUES) &&
    isNonEmptyString(value.label) &&
    (value.language === undefined || typeof value.language === 'string') &&
    (value.codec === undefined || typeof value.codec === 'string') &&
    (value.format === undefined || typeof value.format === 'string') &&
    (value.channelCount === undefined || isFiniteRangeNumber(value.channelCount, 1, 64)) &&
    (value.deliveryType === undefined ||
      isStringInSet(value.deliveryType, PLAYER_TRACK_DELIVERY_TYPE_VALUES)) &&
    (value.forced === undefined || typeof value.forced === 'boolean') &&
    (value.default === undefined || typeof value.default === 'boolean') &&
    typeof value.selected === 'boolean' &&
    typeof value.available === 'boolean'
  );
}

function isTimeRanges(value: unknown): boolean {
  if (!Array.isArray(value)) {
    return false;
  }
  return value.every((range) => {
    return (
      isPlainRecord(range) &&
      hasOnlyKeys(range, ['startMs', 'endMs']) &&
      isFiniteNonNegativeNumber(range.startMs) &&
      isFiniteNonNegativeNumber(range.endMs) &&
      range.endMs >= range.startMs
    );
  });
}

function isPlayerError(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['code', 'category', 'message', 'recoverable', 'retryable'],
      ['requestId', 'diagnostic'],
    ) &&
    isNonEmptyString(value.code) &&
    isStringInSet(value.category, PLAYER_ERROR_CATEGORIES) &&
    isNonEmptyString(value.message) &&
    typeof value.recoverable === 'boolean' &&
    typeof value.retryable === 'boolean' &&
    (value.requestId === undefined || isNonEmptyString(value.requestId)) &&
    (value.diagnostic === undefined || isPlayerDiagnostic(value.diagnostic))
  );
}

function isPlayerDiagnostic(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['component', 'operation'],
      ['status', 'reason', 'counts', 'capabilityProfileId', 'trackIds', 'media', 'timestampMs'],
    ) &&
    isNonEmptyString(value.component) &&
    isNonEmptyString(value.operation) &&
    (value.status === undefined || typeof value.status === 'string') &&
    (value.reason === undefined || typeof value.reason === 'string') &&
    (value.counts === undefined || isCounts(value.counts)) &&
    (value.capabilityProfileId === undefined || isNonEmptyString(value.capabilityProfileId)) &&
    (value.trackIds === undefined ||
      (Array.isArray(value.trackIds) && value.trackIds.every(isNonEmptyString))) &&
    (value.media === undefined || isDiagnosticMedia(value.media)) &&
    (value.timestampMs === undefined || isFiniteNonNegativeNumber(value.timestampMs))
  );
}

function isCounts(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    Object.values(value).every((item) => typeof item === 'number' && Number.isFinite(item))
  );
}

function isDiagnosticMedia(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'title']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title)
  );
}

function playerValidationFailure<T>(requestId: string, message: string): PlayerIpcResult<T> {
  return {
    ok: false,
    requestId,
    error: {
      code: 'PLAYER_VALIDATION_FAILED',
      category: 'validation-failure',
      message,
      recoverable: false,
      retryable: false,
      requestId,
      diagnostic: {
        component: 'preload-player-bridge',
        operation: 'dispatch',
        status: 'rejected',
        reason: 'invalid renderer request',
      },
    },
  };
}

function createWrapperRequest(prefix: string): { requestId: string } {
  return { requestId: createRequestId(prefix) };
}

function readCommandRequestId(value: unknown): string {
  if (isPlainRecord(value) && isNonEmptyString(value.requestId)) {
    return value.requestId;
  }
  return createRequestId('player-validation');
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isNullableNonEmptyString(value: unknown): value is string | null {
  return value === null || isNonEmptyString(value);
}

function isStringInSet<TValue extends string>(
  value: unknown,
  allowed: readonly TValue[],
): value is TValue {
  return typeof value === 'string' && allowed.includes(value as TValue);
}

function isFiniteNonNegativeNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function isFiniteRangeNumber(value: unknown, min: number, max: number): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}

function isNullableFiniteNonNegativeNumber(value: unknown): value is number | null {
  return value === null || isFiniteNonNegativeNumber(value);
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return requiredKeys.every((key) => Object.hasOwn(value, key));
}

function hasForbiddenPrivilegedField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenPrivilegedField(item));
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return (
      (PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS as readonly string[]).includes(key) ||
      hasForbiddenPrivilegedField(child)
    );
  });
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
  player: {
    dispatch: (envelope) => {
      if (!isPlayerRendererIntentEnvelope(envelope)) {
        return Promise.resolve(
          playerValidationFailure<PlayerDispatchResult>(
            readCommandRequestId(envelope),
            'Player command envelope is invalid.',
          ),
        );
      }
      return ipcRenderer.invoke(
        LINEUP_PLAYER_COMMAND_CHANNEL,
        envelope,
      ) as Promise<PlayerIpcResult<PlayerDispatchResult>>;
    },
    getSnapshot: () =>
      ipcRenderer.invoke(
        LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
        createWrapperRequest('player-snapshot'),
      ) as Promise<PlayerIpcResult<PlayerSnapshot>>,
    cleanup: () =>
      ipcRenderer.invoke(
        LINEUP_PLAYER_CLEANUP_CHANNEL,
        createWrapperRequest('player-cleanup'),
      ) as Promise<PlayerIpcResult<PlayerSnapshot>>,
    onEvent: (listener) => {
      if (typeof listener !== 'function') {
        throw new TypeError('Player event listener must be a function.');
      }

      const safeListener = (_event: IpcRendererEvent, payload: unknown): void => {
        if (isPlayerEvent(payload)) {
          listener(payload);
        }
      };

      ipcRenderer.on(LINEUP_PLAYER_EVENT_CHANNEL, safeListener);
      return () => {
        ipcRenderer.removeListener(LINEUP_PLAYER_EVENT_CHANNEL, safeListener);
      };
    },
  },
};

contextBridge.exposeInMainWorld('lineupDesktop', lineupDesktop);
