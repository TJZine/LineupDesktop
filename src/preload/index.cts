import type { IpcRendererEvent } from 'electron';
import type * as Electron from 'electron';
import {
  channelSetupValidationFailure,
  createChannelSetupEmptyRequest,
  isChannelSetupStatusResult,
} from './channelBridgeGuards.cjs';
import type {
  DiagnosticsExportSupportBundleResult,
  DiagnosticsGetSummaryResult,
  DiagnosticsRecordRendererEventResult,
  DiagnosticsRendererEventEnvelope,
  DiagnosticRecord,
} from '../contracts/diagnostics.js';
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
import type {
  PlexCancelPinRequest,
  PlexCancelPinValue,
  PlexGetHomeUsersValue,
  PlexGetMetadataRequest,
  PlexGetMetadataValue,
  PlexIpcResult,
  PlexListLibraryItemsRequest,
  PlexListLibraryItemsValue,
  PlexListLibrarySectionsValue,
  PlexPollPinRequest,
  PlexPollPinValue,
  PlexRefreshServersValue,
  PlexRequestPinValue,
  PlexRestoreSelectedServerValue,
  PlexRendererMediaType,
  PlexRuntimeError,
  PlexRuntimeSnapshot,
  PlexSearchLibraryRequest,
  PlexSearchLibraryValue,
  PlexSelectServerRequest,
  PlexSelectServerValue,
  PlexSwitchHomeUserRequest,
  PlexSwitchHomeUserValue,
} from '../contracts/plex.js';

const { contextBridge, ipcRenderer } = require('electron') as typeof Electron;

/**
 * Sandboxed preload exposes only the typed bridge: main events are
 * runtime-guarded before callbacks, invoke results are typed envelopes expected
 * from authorized handlers, and privileged objects/secrets are not
 * intentionally forwarded.
 */
const LINEUP_SHELL_GET_CAPABILITIES_CHANNEL = 'lineup:shell:getCapabilities';
const LINEUP_WINDOW_INTENT_CHANNEL = 'lineup:window:intent';
const LINEUP_SHELL_STATUS_CHANGED_CHANNEL = 'lineup:shell:statusChanged';
const LINEUP_PLAYER_COMMAND_CHANNEL = 'lineup:player:command';
const LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL = 'lineup:player:getSnapshot';
const LINEUP_PLAYER_CLEANUP_CHANNEL = 'lineup:player:cleanup';
const LINEUP_PLAYER_EVENT_CHANNEL = 'lineup:player:event';
const LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL =
  'lineup:diagnostics:recordRendererEvent';
const LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL =
  'lineup:diagnostics:getSummary';
const LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL =
  'lineup:diagnostics:exportSupportBundle';
const LINEUP_PLEX_GET_SNAPSHOT_CHANNEL = 'lineup:plex:getSnapshot';
const LINEUP_PLEX_REQUEST_PIN_CHANNEL = 'lineup:plex:requestPin';
const LINEUP_PLEX_POLL_PIN_CHANNEL = 'lineup:plex:pollPin';
const LINEUP_PLEX_CANCEL_PIN_CHANNEL = 'lineup:plex:cancelPin';
const LINEUP_PLEX_GET_HOME_USERS_CHANNEL = 'lineup:plex:getHomeUsers';
const LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL = 'lineup:plex:switchHomeUser';
const LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL = 'lineup:plex:restoreSelectedServer';
const LINEUP_PLEX_REFRESH_SERVERS_CHANNEL = 'lineup:plex:refreshServers';
const LINEUP_PLEX_SELECT_SERVER_CHANNEL = 'lineup:plex:selectServer';
const LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL = 'lineup:plex:listLibrarySections';
const LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL = 'lineup:plex:listLibraryItems';
const LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL = 'lineup:plex:searchLibrary';
const LINEUP_PLEX_GET_METADATA_CHANNEL = 'lineup:plex:getMetadata';
const LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL = 'lineup:channelSetup:getStatus';
const PLEX_REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const PLEX_DEFAULT_PAGE_SIZE = 100;
const PLEX_MAX_PAGE_SIZE = 5000;
const PLEX_MAX_SHORT_STRING_LENGTH = 256;
const PLEX_RUNTIME_OPERATIONS = ['getSnapshot', 'requestPin', 'pollPin', 'cancelPin', 'getHomeUsers', 'switchHomeUser', 'restoreSelectedServer', 'refreshServers', 'selectServer', 'listLibrarySections', 'listLibraryItems', 'searchLibrary', 'getMetadata'] as const;
const PLEX_RUNTIME_ERROR_CODES = ['PLEX_UNAUTHORIZED', 'PLEX_VALIDATION_FAILED', 'PLEX_CANCELLED', 'PLEX_STALE_RESULT', 'PLEX_AUTH_REQUIRED', 'PLEX_AUTH_INVALID', 'PLEX_PIN_EXPIRED', 'PLEX_PIN_TIMEOUT', 'PLEX_RATE_LIMITED', 'PLEX_SERVER_UNREACHABLE', 'PLEX_ACCESS_DENIED', 'PLEX_RESOURCE_NOT_FOUND', 'PLEX_STORAGE_UNAVAILABLE', 'PLEX_STORAGE_CORRUPT', 'PLEX_PARSE_FAILED', 'PLEX_LIBRARY_FAILED', 'PLEX_UNKNOWN'] as const;
type PreloadPlexRuntimeOperation = (typeof PLEX_RUNTIME_OPERATIONS)[number];
const DIAGNOSTICS_REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN =
  /(?:[?&][^\s=]*(?:token|auth|secret|credential|password)[^\s=]*=|\b[\w-]*(?:token|auth|secret|credential|password)[\w-]*\s*[:=]|\b(?:authorization|x-plex-token|authHeaders|rawAuthHeaders|bearer|basic|token)\b\s*\S*|(?:[A-Za-z]:\\|\\\\[^\\\s]+\\[^\\\s]+|\/(?:Users|home|var|tmp|private|Volumes|Library)(?:\/|\s+Application\s+Support(?:\/|\b)))|\b(?:pid|processId|process|argv|env|stderr|stdout|crashDump|minidump|rawLog|rawIpc(?:Frame)?|nativeHandle|native_handle|libmpvObject|engineId)[\w-]*\s*[:=]?)/iu;
const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'] as const;
const DIAGNOSTIC_SURFACES = [
  'renderer',
  'preload',
  'main',
  'player-ipc',
  'desktop-player-adapter',
  'native-host-process',
  'plex-playback-runtime',
  'support-bundle',
  'redaction',
] as const;
const DIAGNOSTIC_CATEGORIES = [
  'lifecycle',
  'ipc',
  'validation',
  'playback',
  'helper-crash',
  'helper-restart',
  'cleanup',
  'support-bundle-export',
  'redaction-scan',
  'security-boundary',
  'unknown',
] as const;
const DIAGNOSTIC_SEVERITIES = [
  'debug',
  'info',
  'warning',
  'error',
] as const;
const DIAGNOSTIC_STATUSES = [
  'observed',
  'started',
  'succeeded',
  'failed',
  'rejected',
  'ignored',
  'redacted',
  'truncated',
  'cancelled',
] as const;
const DIAGNOSTICS_RENDERER_EVENT_CATEGORIES = [
  'lifecycle',
  'validation',
  'ipc',
  'support-bundle-export',
] as const;
const DIAGNOSTICS_RENDERER_EVENT_SEVERITIES = [
  'info',
  'warning',
  'error',
] as const;
const DIAGNOSTICS_ERROR_CODES = [
  'DIAGNOSTICS_UNAUTHORIZED',
  'DIAGNOSTICS_VALIDATION_FAILED',
  'DIAGNOSTICS_EXPORT_CANCELLED',
  'DIAGNOSTICS_EXPORT_FAILED',
  'DIAGNOSTICS_REDACTION_FAILED',
  'DIAGNOSTICS_UNAVAILABLE',
  'DIAGNOSTICS_UNKNOWN',
] as const;
const REDACTION_SCAN_FINDING_LABELS = [
  'token-query-parameter',
  'raw-auth-header',
  'credential-scheme',
  'header-map-credential',
  'secret-field-value',
  'privileged-diagnostic-field-value',
  'oauth-token-path-segment',
  'raw-filesystem-path',
  'raw-process-data',
  'native-handle',
  'raw-ipc-frame',
] as const;
const DIAGNOSTIC_FORBIDDEN_FIELD_KEYS = [
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
  'path',
  'filePath',
  'directory',
  'userData',
  'home',
  'username',
  'env',
  'argv',
  'pid',
  'process',
  'stderr',
  'stdout',
  'crashDump',
  'minidump',
  'stack',
  'rawLog',
  'rawIpc',
  'mediaPath',
  'localPath',
  'serverUri',
  'connectionUri',
  'privatePlaybackDescriptor',
  'headers',
  'authorization',
  'token',
  'credential',
  'secret',
] as const;
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
const PLEX_FORBIDDEN_STORAGE_FIELD_KEYS = [
  'appPath',
  'userDataPath',
  'filesystemPath',
  'encryptedSecret',
  'encryptedSecretBase64',
  'secretValue',
  'secretPlaintext',
] as const;
const PLEX_FORBIDDEN_CONNECTION_FIELD_KEYS = [
  'serverUri',
  'rawServerUri',
  'connectionUri',
  'rawConnectionUri',
  'address',
  'port',
  'uri',
  'url',
] as const;
const PLEX_FORBIDDEN_HEADER_FIELD_KEYS = [
  'headers',
  'rawHeaders',
  'authorization',
  'X-Plex-Token',
  'header',
] as const;
const PLEX_FORBIDDEN_TOKEN_FIELD_KEYS = [
  'authToken',
  'accessToken',
  'access_token',
  'authenticationToken',
  'token',
  'accountToken',
  'activeToken',
  'plexToken',
  'clientSecret',
  'secret',
  'credential',
  'password',
] as const;
const PLEX_FORBIDDEN_PAYLOAD_FIELD_KEYS = [
  'rawPayload',
  'mediaFile',
  'mediaPart',
  'file',
  'path',
  'thumb',
  'art',
  'banner',
  'clearLogo',
] as const;
const PLEX_FORBIDDEN_RENDERER_FIELD_KEYS = [
  ...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  ...PLEX_FORBIDDEN_STORAGE_FIELD_KEYS,
  ...PLEX_FORBIDDEN_CONNECTION_FIELD_KEYS,
  ...PLEX_FORBIDDEN_HEADER_FIELD_KEYS,
  ...PLEX_FORBIDDEN_TOKEN_FIELD_KEYS,
  ...PLEX_FORBIDDEN_PAYLOAD_FIELD_KEYS,
] as const;
const PLEX_FORBIDDEN_RENDERER_FIELD_KEYS_LOWER = new Set(
  PLEX_FORBIDDEN_RENDERER_FIELD_KEYS.map((field) => field.toLowerCase()),
);
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

function diagnosticsValidationFailure(
  requestId: string,
  message: string,
): DiagnosticsRecordRendererEventResult | DiagnosticsGetSummaryResult {
  return {
    ok: false,
    requestId,
    error: {
      code: 'DIAGNOSTICS_VALIDATION_FAILED',
      message,
      recoverable: false,
      retryable: false,
    },
  };
}

function diagnosticsExportValidationFailure(message: string): DiagnosticsExportSupportBundleResult {
  return {
    status: 'failed',
    error: {
      code: 'DIAGNOSTICS_VALIDATION_FAILED',
      message,
      recoverable: false,
      retryable: false,
    },
  };
}

type PlexValidationResult<TPayload> =
  | { ok: true; payload: TPayload }
  | { ok: false; message: string };

function createPlexRequest<TPayload>(
  operation: PreloadPlexRuntimeOperation,
  payload: TPayload,
): { requestId: string; payload: TPayload } {
  const requestPrefix = isPreloadPlexRuntimeOperation(operation)
    ? `plex-${operation}`
    : 'plex-request';
  const requestId = createRequestId(requestPrefix);
  return {
    requestId: PLEX_REQUEST_ID_PATTERN.test(requestId)
      ? requestId
      : createRequestId('plex-request'),
    payload,
  };
}

function isPreloadPlexRuntimeOperation(
  value: unknown,
): value is PreloadPlexRuntimeOperation {
  return isStringInSet(value, PLEX_RUNTIME_OPERATIONS);
}

function plexValidationFailure<TValue>(
  operation: PreloadPlexRuntimeOperation,
  message: string,
  requestId = createRequestId('plex-validation'),
): PlexIpcResult<TValue> {
  const error: PlexRuntimeError = {
    code: PLEX_RUNTIME_ERROR_CODES[1],
    message,
    retryable: false,
    recoverable: false,
    operation,
  };
  return { ok: false, requestId, error };
}

function createPlexEmptyRequest(operation: PreloadPlexRuntimeOperation): {
  requestId: string;
  payload: Record<string, never>;
} {
  return createPlexRequest(operation, {});
}

function validatePlexPositiveId(value: unknown, label: string): PlexValidationResult<number> {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    !Number.isInteger(value) ||
    value <= 0
  ) {
    return { ok: false, message: `${label} is invalid.` };
  }
  return { ok: true, payload: Math.floor(value) };
}

function validatePlexRequiredString(
  value: unknown,
  label: string,
): PlexValidationResult<string> {
  if (typeof value !== 'string') {
    return { ok: false, message: `${label} is invalid.` };
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > PLEX_MAX_SHORT_STRING_LENGTH) {
    return { ok: false, message: `${label} is invalid.` };
  }
  return { ok: true, payload: trimmed };
}

function validatePlexOptionalString(
  value: unknown,
  label: string,
): PlexValidationResult<string | undefined> {
  if (value === undefined) {
    return { ok: true, payload: undefined };
  }
  if (typeof value !== 'string') {
    return { ok: false, message: `${label} is invalid.` };
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > PLEX_MAX_SHORT_STRING_LENGTH) {
    return { ok: false, message: `${label} is invalid.` };
  }
  return { ok: true, payload: trimmed };
}

function validatePlexOptionalPin(value: unknown): PlexValidationResult<string | null | undefined> {
  if (value === undefined || value === null) {
    return { ok: true, payload: value };
  }
  if (typeof value !== 'string') {
    return { ok: false, message: 'Plex home pin is invalid.' };
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 64) {
    return { ok: false, message: 'Plex home pin is invalid.' };
  }
  return { ok: true, payload: trimmed };
}

function validatePlexOffset(value: unknown): PlexValidationResult<number | undefined> {
  if (value === undefined) {
    return { ok: true, payload: undefined };
  }
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return { ok: false, message: 'Plex library offset is invalid.' };
  }
  return { ok: true, payload: Math.floor(value) };
}

function validatePlexLimit(value: unknown): PlexValidationResult<number | undefined> {
  if (value === undefined) {
    return { ok: true, payload: undefined };
  }
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    !Number.isInteger(value) ||
    value > PLEX_MAX_PAGE_SIZE
  ) {
    return { ok: false, message: 'Plex library limit is invalid.' };
  }
  return { ok: true, payload: value };
}

function validatePlexPositiveLimit(value: unknown): PlexValidationResult<number | undefined> {
  const limit = validatePlexLimit(value);
  if (!limit.ok) {
    return limit;
  }
  if (limit.payload !== undefined && limit.payload <= 0) {
    return { ok: false, message: 'Plex library limit is invalid.' };
  }
  return limit;
}

const PLEX_SAFE_FILTER_KEY_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/u;
const PLEX_SAFE_LIBRARY_FILTER_KEYS = new Set(['actor', 'audienceRating', 'collection', 'contentRating', 'country', 'decade', 'director', 'episode.unwatched', 'genre', 'hdr', 'producer', 'rating', 'resolution', 'studio', 'subtitleLanguage', 'type', 'unwatched', 'watched', 'writer', 'year']);
const PLEX_SAFE_MEDIA_TYPES = new Set<PlexRendererMediaType>(['movie', 'show', 'episode', 'track', 'clip']);

function validatePlexLibraryFilter(
  value: unknown,
): PlexValidationResult<Readonly<Record<string, string | number>> | undefined> {
  if (value === undefined) {
    return { ok: true, payload: undefined };
  }
  if (!isPlainRecord(value)) {
    return { ok: false, message: 'Plex library filter is invalid.' };
  }
  const filter: Record<string, string | number> = {};
  for (const [key, child] of Object.entries(value)) {
    if (!PLEX_SAFE_FILTER_KEY_PATTERN.test(key) || !PLEX_SAFE_LIBRARY_FILTER_KEYS.has(key)) {
      return { ok: false, message: 'Plex library filter is invalid.' };
    }
    if (typeof child === 'number' && Number.isFinite(child)) {
      filter[key] = child;
      continue;
    }
    if (typeof child === 'string' && child.length > 0 && child.length <= 256) {
      filter[key] = child;
      continue;
    }
    return { ok: false, message: 'Plex library filter is invalid.' };
  }
  return { ok: true, payload: filter };
}

function validatePlexSearchTypes(
  value: unknown,
): PlexValidationResult<readonly PlexRendererMediaType[] | undefined> {
  if (value === undefined) {
    return { ok: true, payload: undefined };
  }
  if (!Array.isArray(value) || value.length > PLEX_SAFE_MEDIA_TYPES.size) {
    return { ok: false, message: 'Plex search types are invalid.' };
  }
  const types: PlexRendererMediaType[] = [];
  for (const type of value) {
    if (!PLEX_SAFE_MEDIA_TYPES.has(type)) {
      return { ok: false, message: 'Plex search types are invalid.' };
    }
    types.push(type);
  }
  return { ok: true, payload: types };
}

function validatePlexPinRequest(
  input: unknown,
  label: string,
): PlexValidationResult<{ pinId: number }> {
  if (!isPlainRecord(input)) {
    return { ok: false, message: `${label} is invalid.` };
  }
  const pinId = validatePlexPositiveId(input.pinId, 'Plex pin id');
  if (!pinId.ok) {
    return pinId;
  }
  return { ok: true, payload: { pinId: pinId.payload } };
}

function validatePlexSwitchHomeUserRequest(
  input: unknown,
): PlexValidationResult<PlexSwitchHomeUserRequest['payload']> {
  if (!isPlainRecord(input)) {
    return { ok: false, message: 'Plex home user request is invalid.' };
  }
  const userId = validatePlexRequiredString(input.userId, 'Plex home user id');
  if (!userId.ok) {
    return userId;
  }
  const pin = validatePlexOptionalPin(input.pin);
  if (!pin.ok) {
    return pin;
  }
  return {
    ok: true,
    payload: pin.payload === undefined
      ? { userId: userId.payload }
      : { userId: userId.payload, pin: pin.payload },
  };
}

function validatePlexSelectServerRequest(
  input: unknown,
): PlexValidationResult<PlexSelectServerRequest['payload']> {
  if (!isPlainRecord(input)) {
    return { ok: false, message: 'Plex server request is invalid.' };
  }
  const serverId = validatePlexRequiredString(input.serverId, 'Plex server id');
  if (!serverId.ok) {
    return serverId;
  }
  return { ok: true, payload: { serverId: serverId.payload } };
}

function validatePlexListLibraryItemsRequest(
  input: unknown,
): PlexValidationResult<PlexListLibraryItemsRequest['payload']> {
  if (!isPlainRecord(input)) {
    return { ok: false, message: 'Plex library request is invalid.' };
  }
  const sectionId = validatePlexRequiredString(input.sectionId, 'Plex library section id');
  if (!sectionId.ok) {
    return sectionId;
  }
  const offset = validatePlexOffset(input.offset);
  if (!offset.ok) {
    return offset;
  }
  const limit = validatePlexLimit(input.limit);
  if (!limit.ok) {
    return limit;
  }
  const sort = validatePlexOptionalString(input.sort, 'Plex library sort');
  if (!sort.ok) {
    return sort;
  }
  const filter = validatePlexLibraryFilter(input.filter);
  if (!filter.ok) {
    return filter;
  }
  if (input.includeCollections !== undefined && typeof input.includeCollections !== 'boolean') {
    return { ok: false, message: 'Plex library includeCollections flag is invalid.' };
  }
  return {
    ok: true,
    payload: {
      sectionId: sectionId.payload,
      offset: offset.payload ?? 0,
      ...(limit.payload !== undefined ? { limit: limit.payload } : {}),
      ...(sort.payload !== undefined ? { sort: sort.payload } : {}),
      ...(filter.payload !== undefined ? { filter: filter.payload } : {}),
      ...(input.includeCollections !== undefined
        ? { includeCollections: input.includeCollections }
        : {}),
    },
  };
}

function validatePlexSearchLibraryRequest(
  input: unknown,
): PlexValidationResult<PlexSearchLibraryRequest['payload']> {
  if (!isPlainRecord(input)) {
    return { ok: false, message: 'Plex search request is invalid.' };
  }
  const query = validatePlexRequiredString(input.query, 'Plex search query');
  if (!query.ok) {
    return query;
  }
  const sectionId = validatePlexOptionalString(input.sectionId, 'Plex library section id');
  if (!sectionId.ok) {
    return sectionId;
  }
  const limit = validatePlexPositiveLimit(input.limit);
  if (!limit.ok) {
    return limit;
  }
  const types = validatePlexSearchTypes(input.types);
  if (!types.ok) {
    return types;
  }
  return {
    ok: true,
    payload: {
      query: query.payload,
      ...(sectionId.payload !== undefined ? { sectionId: sectionId.payload } : {}),
      limit: limit.payload ?? PLEX_DEFAULT_PAGE_SIZE,
      ...(types.payload !== undefined ? { types: types.payload } : {}),
    },
  };
}

function validatePlexGetMetadataRequest(
  input: unknown,
): PlexValidationResult<PlexGetMetadataRequest['payload']> {
  if (!isPlainRecord(input)) {
    return { ok: false, message: 'Plex metadata request is invalid.' };
  }
  const ratingKey = validatePlexRequiredString(input.ratingKey, 'Plex metadata id');
  if (!ratingKey.ok) {
    return ratingKey;
  }
  return { ok: true, payload: { ratingKey: ratingKey.payload } };
}

function hasForbiddenPlexRendererField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenPlexRendererField(item));
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return (
      PLEX_FORBIDDEN_RENDERER_FIELD_KEYS_LOWER.has(key.toLowerCase()) ||
      hasForbiddenPlexRendererField(child)
    );
  });
}

function isPlexRequestId(value: unknown): value is string {
  return typeof value === 'string' && PLEX_REQUEST_ID_PATTERN.test(value);
}

function isPlexInteger(value: unknown, min = 0): value is number {
  return typeof value === 'number' && Number.isFinite(value) && Number.isInteger(value) && value >= min;
}

function isPlexRuntimeError(
  value: unknown,
  operation: PreloadPlexRuntimeOperation,
): value is PlexRuntimeError {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'retryable', 'recoverable', 'operation'], ['httpStatus']) &&
    isStringInSet(value.code, PLEX_RUNTIME_ERROR_CODES) &&
    isNonEmptyString(value.message) &&
    typeof value.retryable === 'boolean' &&
    typeof value.recoverable === 'boolean' &&
    value.operation === operation &&
    (value.httpStatus === undefined || isFiniteRangeNumber(value.httpStatus, 100, 599))
  );
}

function isPlexIpcResult<TValue>(
  value: unknown,
  operation: PreloadPlexRuntimeOperation, expectedRequestId: string,
  isValue: (value: unknown) => value is TValue,
): value is PlexIpcResult<TValue> {
  if (!isPlainRecord(value) || hasForbiddenPlexRendererField(value) || !isPlexRequestId(value.requestId) || value.requestId !== expectedRequestId) {
    return false;
  }
  if (value.ok === true) {
    return hasOnlyKeys(value, ['ok', 'value', 'requestId']) && isValue(value.value);
  }
  if (value.ok !== false) {
    return false;
  }

  const cancelled = value.cancelled;
  const stale = value.stale;
  if (cancelled !== undefined && cancelled !== true) {
    return false;
  }
  if (stale !== undefined && stale !== true) {
    return false;
  }
  if (cancelled === true && stale === true) {
    return false;
  }
  if (
    !hasOnlyKeys(value, ['ok', 'error', 'requestId'], ['cancelled', 'stale']) ||
    !isPlexRuntimeError(value.error, operation)
  ) {
    return false;
  }
  if (value.error.code === 'PLEX_CANCELLED') {
    return cancelled === true && stale === undefined;
  }
  if (value.error.code === 'PLEX_STALE_RESULT') {
    return stale === true && cancelled === undefined;
  }
  return cancelled === undefined && stale === undefined;
}

async function invokePlex<TValue>(
  channel: string,
  operation: PreloadPlexRuntimeOperation,
  request: { requestId: string; payload: unknown },
  isValue: (value: unknown) => value is TValue,
): Promise<PlexIpcResult<TValue>> {
  let result: unknown;
  try {
    result = await ipcRenderer.invoke(channel, request);
  } catch (error: unknown) {
    const errorName = error instanceof Error ? error.name : typeof error;
    return plexValidationFailure<TValue>(
      operation,
      `Plex invoke failed (${errorName}).`,
      request.requestId,
    );
  }
  return isPlexIpcResult(result, operation, request.requestId, isValue)
    ? result
    : plexValidationFailure<TValue>(operation, 'Plex result is invalid.', request.requestId);
}

function isPlexPinSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'code', 'expiresAtMs', 'claimed']) &&
    isPlexInteger(value.id, 1) &&
    isNonEmptyString(value.code) &&
    isFiniteNonNegativeNumber(value.expiresAtMs) &&
    typeof value.claimed === 'boolean'
  );
}

function isPlexAuthProfileSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['accountId'],
      ['username', 'displayName', 'activeProfileId', 'preferredSubtitleLanguage'],
    ) &&
    isNonEmptyString(value.accountId) &&
    (value.username === undefined || isNonEmptyString(value.username)) &&
    (value.displayName === undefined || isNonEmptyString(value.displayName)) &&
    (value.activeProfileId === undefined || isNonEmptyString(value.activeProfileId)) &&
    (value.preferredSubtitleLanguage === undefined ||
      isNonEmptyString(value.preferredSubtitleLanguage))
  );
}

function isPlexHomeUserSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'title', 'admin', 'protected'], ['restricted']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title) &&
    typeof value.admin === 'boolean' &&
    typeof value.protected === 'boolean' &&
    (value.restricted === undefined || typeof value.restricted === 'boolean')
  );
}

function isPlexServerHealthSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['status', 'connectionKind', 'testedAtMs'], ['latencyMs']) &&
    isStringInSet(value.status, ['ok', 'unreachable', 'auth-required', 'access-denied'] as const) &&
    isStringInSet(value.connectionKind, ['local', 'remote', 'relay', 'unknown'] as const) &&
    (value.latencyMs === undefined || isFiniteNonNegativeNumber(value.latencyMs)) &&
    isFiniteNonNegativeNumber(value.testedAtMs)
  );
}

function isPlexServerSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      [
        'serverId',
        'name',
        'owned',
        'connectionCount',
        'hasLocalConnection',
        'hasRemoteConnection',
        'hasRelayConnection',
        'selected',
      ],
      ['sourceTitle', 'health'],
    ) &&
    isNonEmptyString(value.serverId) &&
    isNonEmptyString(value.name) &&
    typeof value.owned === 'boolean' &&
    (value.sourceTitle === undefined || isNonEmptyString(value.sourceTitle)) &&
    isPlexInteger(value.connectionCount) &&
    typeof value.hasLocalConnection === 'boolean' &&
    typeof value.hasRemoteConnection === 'boolean' &&
    typeof value.hasRelayConnection === 'boolean' &&
    typeof value.selected === 'boolean' &&
    (value.health === undefined || isPlexServerHealthSummary(value.health))
  );
}

function isPlexServerSelectionSummary(value: unknown): boolean {
  if (!isPlainRecord(value)) {
    return false;
  }
  if (value.kind === 'selected') {
    return (
      hasOnlyKeys(value, ['kind', 'server', 'persisted']) &&
      isPlexServerSummary(value.server) &&
      typeof value.persisted === 'boolean'
    );
  }
  return (
    value.kind === 'selection-failed' &&
    hasOnlyKeys(value, ['kind', 'reason', 'persisted'], ['server']) &&
    isStringInSet(
      value.reason,
      ['server-not-found', 'unreachable', 'auth-required', 'access-denied', 'no-persisted-server'] as const,
    ) &&
    value.persisted === false &&
    (value.server === undefined || isPlexServerSummary(value.server))
  );
}

function isPlexLibrarySectionSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['id', 'title', 'type', 'contentCount', 'lastScannedAtMs'], ['episodeCount']) &&
    isNonEmptyString(value.id) &&
    isNonEmptyString(value.title) &&
    isStringInSet(value.type, ['movie', 'show', 'artist', 'photo'] as const) &&
    (value.contentCount === null || isPlexInteger(value.contentCount)) &&
    (value.episodeCount === undefined || isPlexInteger(value.episodeCount)) &&
    isFiniteNonNegativeNumber(value.lastScannedAtMs)
  );
}

function isPlexMediaItemSummary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['ratingKey', 'type', 'title', 'sortTitle', 'summary', 'year', 'durationMs', 'addedAtMs', 'updatedAtMs'],
      [
        'rating',
        'audienceRating',
        'contentRating',
        'genres',
        'directors',
        'actors',
        'studios',
        'grandparentTitle',
        'parentTitle',
        'seasonNumber',
        'episodeNumber',
        'viewOffset',
        'viewCount',
        'lastViewedAtMs',
      ],
    ) &&
    isNonEmptyString(value.ratingKey) &&
    isStringInSet(value.type, ['movie', 'show', 'episode', 'track', 'clip'] as const) &&
    isNonEmptyString(value.title) &&
    typeof value.sortTitle === 'string' &&
    typeof value.summary === 'string' &&
    isPlexInteger(value.year) &&
    isFiniteNonNegativeNumber(value.durationMs) &&
    isFiniteNonNegativeNumber(value.addedAtMs) &&
    isFiniteNonNegativeNumber(value.updatedAtMs) &&
    (value.rating === undefined || isFiniteNonNegativeNumber(value.rating)) &&
    (value.audienceRating === undefined || isFiniteNonNegativeNumber(value.audienceRating)) &&
    (value.contentRating === undefined || typeof value.contentRating === 'string') &&
    (value.genres === undefined || isStringArray(value.genres)) &&
    (value.directors === undefined || isStringArray(value.directors)) &&
    (value.actors === undefined || isStringArray(value.actors)) &&
    (value.studios === undefined || isStringArray(value.studios)) &&
    (value.grandparentTitle === undefined || typeof value.grandparentTitle === 'string') &&
    (value.parentTitle === undefined || typeof value.parentTitle === 'string') &&
    (value.seasonNumber === undefined || isPlexInteger(value.seasonNumber)) &&
    (value.episodeNumber === undefined || isPlexInteger(value.episodeNumber)) &&
    (value.viewOffset === undefined || isFiniteNonNegativeNumber(value.viewOffset)) &&
    (value.viewCount === undefined || isPlexInteger(value.viewCount)) &&
    (value.lastViewedAtMs === undefined || isFiniteNonNegativeNumber(value.lastViewedAtMs))
  );
}

function isStringArray(value: unknown): boolean {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

function isPlexRuntimeSnapshot(value: unknown): value is PlexRuntimeSnapshot {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['auth', 'servers', 'library', 'lastError', 'updatedAtMs']) &&
    isPlexRuntimeSnapshotAuth(value.auth) &&
    isPlexRuntimeSnapshotServers(value.servers) &&
    isPlexRuntimeSnapshotLibrary(value.library) &&
    (value.lastError === null ||
      (isPlainRecord(value.lastError) &&
        isPreloadPlexRuntimeOperation(value.lastError.operation) &&
        isPlexRuntimeError(value.lastError, value.lastError.operation))) &&
    isFiniteNonNegativeNumber(value.updatedAtMs)
  );
}

function isPlexRuntimeSnapshotAuth(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['state', 'pin', 'profile', 'homeUsers', 'credentialStatus']) &&
    isStringInSet(value.state, ['signed-out', 'pin-pending', 'signed-in'] as const) &&
    (value.pin === null || isPlexPinSummary(value.pin)) &&
    (value.profile === null || isPlexAuthProfileSummary(value.profile)) &&
    Array.isArray(value.homeUsers) &&
    value.homeUsers.every(isPlexHomeUserSummary) &&
    isStringInSet(value.credentialStatus, ['missing', 'present', 'unavailable', 'corrupt'] as const)
  );
}

function isPlexRuntimeSnapshotServers(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['status', 'selected', 'items', 'lastSelection']) &&
    isStringInSet(value.status, ['idle', 'loading', 'ready', 'failed'] as const) &&
    (value.selected === null || isPlexServerSummary(value.selected)) &&
    Array.isArray(value.items) &&
    value.items.every(isPlexServerSummary) &&
    (value.lastSelection === null || isPlexServerSelectionSummary(value.lastSelection))
  );
}

function isPlexRuntimeSnapshotLibrary(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['status', 'sections', 'selectedSectionId', 'items', 'search', 'metadata']) &&
    isStringInSet(value.status, ['idle', 'loading', 'ready', 'failed'] as const) &&
    Array.isArray(value.sections) &&
    value.sections.every(isPlexLibrarySectionSummary) &&
    (value.selectedSectionId === null || isNonEmptyString(value.selectedSectionId)) &&
    Array.isArray(value.items) &&
    value.items.every(isPlexMediaItemSummary) &&
    (value.search === null || isPlexSearchState(value.search)) &&
    (value.metadata === null || isPlexMediaItemSummary(value.metadata))
  );
}

function isPlexSearchState(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['query', 'items']) &&
    isNonEmptyString(value.query) &&
    Array.isArray(value.items) &&
    value.items.every(isPlexMediaItemSummary)
  );
}

function isPlexSnapshotValue(value: unknown): value is PlexRuntimeSnapshot {
  return isPlexRuntimeSnapshot(value);
}

function isPlexRequestPinValue(value: unknown): value is PlexRequestPinValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['pin', 'snapshot']) &&
    isPlexPinSummary(value.pin) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexPollPinValue(value: unknown): value is PlexPollPinValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['pin', 'profile', 'snapshot']) &&
    isPlexPinSummary(value.pin) &&
    (value.profile === null || isPlexAuthProfileSummary(value.profile)) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexCancelPinValue(value: unknown): value is PlexCancelPinValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['pinId', 'snapshot']) &&
    isPlexInteger(value.pinId, 1) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexGetHomeUsersValue(value: unknown): value is PlexGetHomeUsersValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['users', 'snapshot']) &&
    Array.isArray(value.users) &&
    value.users.every(isPlexHomeUserSummary) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexSwitchHomeUserValue(value: unknown): value is PlexSwitchHomeUserValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['profile', 'snapshot']) &&
    isPlexAuthProfileSummary(value.profile) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexRestoreSelectedServerValue(value: unknown): value is PlexRestoreSelectedServerValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['selection', 'snapshot']) &&
    isPlexServerSelectionSummary(value.selection) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexRefreshServersValue(value: unknown): value is PlexRefreshServersValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['servers', 'snapshot']) &&
    Array.isArray(value.servers) &&
    value.servers.every(isPlexServerSummary) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexSelectServerValue(value: unknown): value is PlexSelectServerValue {
  return isPlexRestoreSelectedServerValue(value);
}

function isPlexListLibrarySectionsValue(value: unknown): value is PlexListLibrarySectionsValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['sections', 'snapshot']) &&
    Array.isArray(value.sections) &&
    value.sections.every(isPlexLibrarySectionSummary) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexListLibraryItemsValue(value: unknown): value is PlexListLibraryItemsValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['sectionId', 'offset', 'limit', 'items', 'snapshot']) &&
    isNonEmptyString(value.sectionId) &&
    isPlexInteger(value.offset) &&
    isPlexInteger(value.limit) &&
    value.limit <= PLEX_MAX_PAGE_SIZE &&
    Array.isArray(value.items) &&
    value.items.every(isPlexMediaItemSummary) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexSearchLibraryValue(value: unknown): value is PlexSearchLibraryValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['query', 'sectionId', 'items', 'snapshot']) &&
    isNonEmptyString(value.query) &&
    (value.sectionId === null || isNonEmptyString(value.sectionId)) &&
    Array.isArray(value.items) &&
    value.items.every(isPlexMediaItemSummary) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
}

function isPlexGetMetadataValue(value: unknown): value is PlexGetMetadataValue {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['item', 'snapshot']) &&
    (value.item === null || isPlexMediaItemSummary(value.item)) &&
    isPlexRuntimeSnapshot(value.snapshot)
  );
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

function readDiagnosticsRequestId(value: unknown): string {
  if (
    isPlainRecord(value) &&
    isNonEmptyString(value.requestId) &&
    DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId)
  ) {
    return value.requestId;
  }
  return createRequestId('diagnostics-validation');
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

function isFiniteNonNegativeNumberMap(value: unknown, allowedKeys: readonly string[]): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, [], allowedKeys) &&
    Object.values(value).every(isFiniteNonNegativeNumber)
  );
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

function hasForbiddenDiagnosticField(value: unknown): boolean {
  if (Array.isArray(value)) {
    return value.some((item) => hasForbiddenDiagnosticField(item));
  }
  if (!isPlainRecord(value)) {
    return false;
  }
  return Object.entries(value).some(([key, child]) => {
    return (
      (DIAGNOSTIC_FORBIDDEN_FIELD_KEYS as readonly string[]).includes(key) ||
      hasForbiddenDiagnosticField(child)
    );
  });
}

function isDiagnosticsRendererEventEnvelope(value: unknown): value is DiagnosticsRendererEventEnvelope {
  if (
    !isPlainRecord(value) ||
    !isNonEmptyString(value.requestId) ||
    !DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId) ||
    hasForbiddenDiagnosticField(value)
  ) {
    return false;
  }
  if (!hasOnlyKeys(value, ['requestId', 'event'])) {
    return false;
  }
  const event = value.event;
  return (
    isPlainRecord(event) &&
    hasOnlyKeys(event, ['surface', 'category', 'severity', 'operation', 'message'], ['context']) &&
    event.surface === 'renderer' &&
    isStringInSet(event.category, DIAGNOSTICS_RENDERER_EVENT_CATEGORIES) &&
    isStringInSet(event.severity, DIAGNOSTICS_RENDERER_EVENT_SEVERITIES) &&
    isNonEmptyString(event.operation) &&
    isNonEmptyString(event.message) &&
    (event.context === undefined || isDiagnosticContext(event.context))
  );
}

function isDiagnosticContext(value: unknown): boolean {
  if (!isPlainRecord(value) || hasForbiddenDiagnosticField(value)) {
    return false;
  }
  return Object.values(value).every((item) => (
    item === null ||
    (typeof item === 'string' && !DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN.test(item)) ||
    typeof item === 'boolean' ||
    (typeof item === 'number' && Number.isFinite(item))
  ));
}

function isDiagnosticsRecordRendererEventResult(value: unknown): value is DiagnosticsRecordRendererEventResult {
  return isDiagnosticsResult(value, isDiagnosticRecord);
}

function isDiagnosticsGetSummaryResult(value: unknown): value is DiagnosticsGetSummaryResult {
  return isDiagnosticsResult(value, isDiagnosticsSummary);
}

function isDiagnosticsResult<T>(
  value: unknown,
  isValue: (candidate: unknown) => candidate is T,
): boolean {
  if (
    !isPlainRecord(value) ||
    typeof value.ok !== 'boolean' ||
    !isNonEmptyString(value.requestId) ||
    !DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId)
  ) {
    return false;
  }
  if (value.ok) {
    return hasOnlyKeys(value, ['ok', 'requestId', 'value']) && isValue(value.value);
  }
  const hasValidCancellationFlag = value.cancelled === undefined || value.cancelled === true;
  return hasOnlyKeys(value, ['ok', 'requestId', 'error'], ['cancelled']) &&
    hasValidCancellationFlag && isDiagnosticsError(value.error);
}

function isDiagnosticRecord(value: unknown): value is DiagnosticRecord {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      ['schemaVersion', 'id', 'timestampMs', 'surface', 'category', 'severity', 'status', 'operation', 'message'],
      ['requestId', 'result', 'context', 'truncation'],
    ) &&
    value.schemaVersion === 1 &&
    isNonEmptyString(value.id) &&
    isFiniteNonNegativeNumber(value.timestampMs) &&
    value.surface === 'renderer' &&
    isStringInSet(value.category, DIAGNOSTIC_CATEGORIES) &&
    isStringInSet(value.severity, DIAGNOSTIC_SEVERITIES) &&
    isStringInSet(value.status, DIAGNOSTIC_STATUSES) &&
    isNonEmptyString(value.operation) &&
    typeof value.message === 'string' &&
    (value.requestId === undefined || isNonEmptyString(value.requestId)) &&
    (value.context === undefined || isDiagnosticContext(value.context)) &&
    !hasForbiddenDiagnosticField(value)
  );
}

function isDiagnosticsSummary(value: unknown): value is DiagnosticsGetSummaryResult extends { ok: true; value: infer T } ? T : never {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      [
        'schemaVersion',
        'redactionVersion',
        'recordCount',
        'lastEventTimestampMs',
        'surfaceCounts',
        'severityCounts',
        'lastExportStatus',
        'redactionFailureCount',
      ],
    ) &&
    value.schemaVersion === 1 &&
    value.redactionVersion === 'rd17-redaction-v1' &&
    isFiniteNonNegativeNumber(value.recordCount) &&
    (value.lastEventTimestampMs === null || isFiniteNonNegativeNumber(value.lastEventTimestampMs)) &&
    isFiniteNonNegativeNumberMap(value.surfaceCounts, DIAGNOSTIC_SURFACES) &&
    isFiniteNonNegativeNumberMap(value.severityCounts, DIAGNOSTIC_SEVERITIES) &&
    (
      value.lastExportStatus === null ||
      value.lastExportStatus === 'succeeded' ||
      value.lastExportStatus === 'failed' ||
      value.lastExportStatus === 'cancelled'
    ) &&
    isFiniteNonNegativeNumber(value.redactionFailureCount) &&
    !hasForbiddenDiagnosticField(value)
  );
}

function isDiagnosticsExportSupportBundleResult(
  value: unknown,
): value is DiagnosticsExportSupportBundleResult {
  if (!isPlainRecord(value) || hasForbiddenDiagnosticField(value)) {
    return false;
  }
  if (value.status === 'succeeded') {
    return (
      hasOnlyKeys(
        value,
        [
          'status',
          'bundleId',
          'bundleDirectoryName',
          'createdAtMs',
          'fileCount',
          'byteCount',
          'includedFiles',
          'redactionReport',
        ],
      ) &&
      isSafeBundleId(value.bundleId) &&
      isSafeBundleDirectoryName(value.bundleDirectoryName) &&
      isFiniteNonNegativeNumber(value.createdAtMs) &&
      isFiniteNonNegativeNumber(value.fileCount) &&
      isFiniteNonNegativeNumber(value.byteCount) &&
      Array.isArray(value.includedFiles) &&
      value.includedFiles.every(isSafeBundleFileName) &&
      isRedactionScanReport(value.redactionReport)
    );
  }
  return (
    (value.status === 'failed' || value.status === 'cancelled') &&
    hasOnlyKeys(value, ['status', 'error'], ['redactionReport']) &&
    isDiagnosticsError(value.error) &&
    (value.redactionReport === undefined || isRedactionScanReport(value.redactionReport))
  );
}

function isDiagnosticsError(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(value, ['code', 'message', 'recoverable', 'retryable'], ['diagnostic']) &&
    isStringInSet(value.code, DIAGNOSTICS_ERROR_CODES) &&
    typeof value.message === 'string' &&
    typeof value.recoverable === 'boolean' &&
    typeof value.retryable === 'boolean' &&
    (value.diagnostic === undefined || isDiagnosticRecord(value.diagnostic)) &&
    !hasForbiddenDiagnosticField(value)
  );
}

function isRedactionScanReport(value: unknown): boolean {
  return (
    isPlainRecord(value) &&
    hasOnlyKeys(
      value,
      [
        'redactionVersion',
        'scannedFileCount',
        'scannedByteCount',
        'findingCount',
        'findingsByLabel',
        'truncatedRecordCount',
        'omittedFileCount',
        'status',
        'timestampMs',
      ],
    ) &&
    value.redactionVersion === 'rd17-redaction-v1' &&
    isFiniteNonNegativeNumber(value.scannedFileCount) &&
    isFiniteNonNegativeNumber(value.scannedByteCount) &&
    isFiniteNonNegativeNumber(value.findingCount) &&
    isFiniteNonNegativeNumberMap(value.findingsByLabel, REDACTION_SCAN_FINDING_LABELS) &&
    isFiniteNonNegativeNumber(value.truncatedRecordCount) &&
    isFiniteNonNegativeNumber(value.omittedFileCount) &&
    (value.status === 'passed' || value.status === 'failed') &&
    isFiniteNonNegativeNumber(value.timestampMs)
  );
}

function isSafeBundleId(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9-]{1,80}$/u.test(value);
}

function isSafeBundleDirectoryName(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    /^lineup-desktop-support-[A-Za-z0-9-]{1,80}$/u.test(value) &&
    !/[\\/]/u.test(value) &&
    !/^[A-Za-z]:/u.test(value)
  );
}

function isSafeBundleFileName(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9.-]*$/u.test(value) && !/[\\/]/u.test(value);
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
  diagnostics: {
    recordRendererEvent: async (envelope) => {
      if (!isDiagnosticsRendererEventEnvelope(envelope)) {
        return diagnosticsValidationFailure(
          readDiagnosticsRequestId(envelope),
          'Renderer diagnostic event envelope is invalid.',
        ) as DiagnosticsRecordRendererEventResult;
      }
      const result = await ipcRenderer.invoke(
        LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
        envelope,
      );
      return isDiagnosticsRecordRendererEventResult(result)
        ? result
        : diagnosticsValidationFailure(
            envelope.requestId,
            'Renderer diagnostic event result is invalid.',
          ) as DiagnosticsRecordRendererEventResult;
    },
    getSummary: async () => {
      const result = await ipcRenderer.invoke(LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL);
      return isDiagnosticsGetSummaryResult(result)
        ? result
        : diagnosticsValidationFailure(
            createRequestId('diagnostics-summary-validation'),
            'Diagnostics summary result is invalid.',
          ) as DiagnosticsGetSummaryResult;
    },
    exportSupportBundle: async () => {
      const result = await ipcRenderer.invoke(LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL);
      return isDiagnosticsExportSupportBundleResult(result)
        ? result
        : diagnosticsExportValidationFailure('Support bundle export result is invalid.');
    },
  },
  plex: {
    getSnapshot: () =>
      invokePlex(
        LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
        'getSnapshot',
        createPlexEmptyRequest('getSnapshot'),
        isPlexSnapshotValue,
      ),
    requestPin: () =>
      invokePlex(
        LINEUP_PLEX_REQUEST_PIN_CHANNEL,
        'requestPin',
        createPlexEmptyRequest('requestPin'),
        isPlexRequestPinValue,
      ),
    pollPin: (input) => {
      const validated = validatePlexPinRequest(input, 'Plex pin poll request');
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexPollPinValue>('pollPin', validated.message),
        );
      }
      return invokePlex(
        LINEUP_PLEX_POLL_PIN_CHANNEL,
        'pollPin',
        createPlexRequest<PlexPollPinRequest['payload']>('pollPin', validated.payload),
        isPlexPollPinValue,
      );
    },
    cancelPin: (input) => {
      const validated = validatePlexPinRequest(input, 'Plex pin cancellation request');
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexCancelPinValue>('cancelPin', validated.message),
        );
      }
      return invokePlex(
        LINEUP_PLEX_CANCEL_PIN_CHANNEL,
        'cancelPin',
        createPlexRequest<PlexCancelPinRequest['payload']>('cancelPin', validated.payload),
        isPlexCancelPinValue,
      );
    },
    getHomeUsers: () =>
      invokePlex(
        LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
        'getHomeUsers',
        createPlexEmptyRequest('getHomeUsers'),
        isPlexGetHomeUsersValue,
      ),
    switchHomeUser: (input) => {
      const validated = validatePlexSwitchHomeUserRequest(input);
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexSwitchHomeUserValue>('switchHomeUser', validated.message),
        );
      }
      return invokePlex(
        LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
        'switchHomeUser',
        createPlexRequest<PlexSwitchHomeUserRequest['payload']>(
          'switchHomeUser',
          validated.payload,
        ),
        isPlexSwitchHomeUserValue,
      );
    },
    restoreSelectedServer: () =>
      invokePlex(
        LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
        'restoreSelectedServer',
        createPlexEmptyRequest('restoreSelectedServer'),
        isPlexRestoreSelectedServerValue,
      ),
    refreshServers: () =>
      invokePlex(
        LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
        'refreshServers',
        createPlexEmptyRequest('refreshServers'),
        isPlexRefreshServersValue,
      ),
    selectServer: (input) => {
      const validated = validatePlexSelectServerRequest(input);
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexSelectServerValue>('selectServer', validated.message),
        );
      }
      return invokePlex(
        LINEUP_PLEX_SELECT_SERVER_CHANNEL,
        'selectServer',
        createPlexRequest<PlexSelectServerRequest['payload']>(
          'selectServer',
          validated.payload,
        ),
        isPlexSelectServerValue,
      );
    },
    listLibrarySections: () =>
      invokePlex(
        LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
        'listLibrarySections',
        createPlexEmptyRequest('listLibrarySections'),
        isPlexListLibrarySectionsValue,
      ),
    listLibraryItems: (input) => {
      const validated = validatePlexListLibraryItemsRequest(input);
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexListLibraryItemsValue>(
            'listLibraryItems',
            validated.message,
          ),
        );
      }
      return invokePlex(
        LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
        'listLibraryItems',
        createPlexRequest<PlexListLibraryItemsRequest['payload']>(
          'listLibraryItems',
          validated.payload,
        ),
        isPlexListLibraryItemsValue,
      );
    },
    searchLibrary: (input) => {
      const validated = validatePlexSearchLibraryRequest(input);
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexSearchLibraryValue>('searchLibrary', validated.message),
        );
      }
      return invokePlex(
        LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
        'searchLibrary',
        createPlexRequest<PlexSearchLibraryRequest['payload']>(
          'searchLibrary',
          validated.payload,
        ),
        isPlexSearchLibraryValue,
      );
    },
    getMetadata: (input) => {
      const validated = validatePlexGetMetadataRequest(input);
      if (!validated.ok) {
        return Promise.resolve(
          plexValidationFailure<PlexGetMetadataValue>('getMetadata', validated.message),
        );
      }
      return invokePlex(
        LINEUP_PLEX_GET_METADATA_CHANNEL,
        'getMetadata',
        createPlexRequest<PlexGetMetadataRequest['payload']>(
          'getMetadata',
          validated.payload,
        ),
        isPlexGetMetadataValue,
      );
    },
  },
  channelSetup: {
    getStatus: async () => {
      const request = createChannelSetupEmptyRequest();
      try {
        const result = await ipcRenderer.invoke(LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL, request);
        return isChannelSetupStatusResult(result, request.requestId)
          ? result
          : channelSetupValidationFailure(request.requestId);
      } catch {
        return channelSetupValidationFailure(request.requestId);
      }
    },
  },
};

contextBridge.exposeInMainWorld('lineupDesktop', lineupDesktop);
