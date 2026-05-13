import type { IpcRendererEvent } from 'electron';
import type * as Electron from 'electron';
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
const DIAGNOSTICS_REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN =
  /(?:[?&][^\s=]*(?:token|auth|secret|credential|password)[^\s=]*=|\b[\w-]*(?:token|auth|secret|credential|password)[\w-]*\s*[:=]|\b(?:authorization|x-plex-token|authHeaders|rawAuthHeaders|bearer|basic|token)\b\s*\S*|(?:[A-Za-z]:\\|\\\\[^\\\s]+\\[^\\\s]+|\/(?:Users|home|var|tmp|private|Volumes|Library)(?:\/|\s+Application\s+Support(?:\/|\b)))|\b(?:pid|processId|process|argv|env|stderr|stdout|crashDump|minidump|rawLog|rawIpc(?:Frame)?|nativeHandle|native_handle|libmpvObject|engineId)[\w-]*\s*[:=]?)/iu;
const SHELL_STATUS_VALUES = ['booting', 'ready', 'closing'] as const;
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

function isDiagnosticsRecordRendererEventResult(
  value: unknown,
): value is DiagnosticsRecordRendererEventResult {
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
  return hasOnlyKeys(value, ['ok', 'requestId', 'error'], ['cancelled']) && isDiagnosticsError(value.error);
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
    isPlainRecord(value.surfaceCounts) &&
    isPlainRecord(value.severityCounts) &&
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
    isPlainRecord(value.findingsByLabel) &&
    Object.keys(value.findingsByLabel).every((key) =>
      (REDACTION_SCAN_FINDING_LABELS as readonly string[]).includes(key),
    ) &&
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
};

contextBridge.exposeInMainWorld('lineupDesktop', lineupDesktop);
