import test from 'node:test';
import assert from 'node:assert/strict';

import {
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
  PLAYER_RENDERER_INTENTS,
  RENDERER_FORBIDDEN_PAYLOAD_KEYS,
  type PlayerRendererIntent,
  type RendererIntent,
} from '../../contracts/ipc.js';
import { REDACTION_BOUNDARY } from '../../contracts/redaction.js';
import {
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  isRendererSafePlayerEvent,
  type PlaybackCapabilityProfile,
  type PlayerCommand,
  type PlayerDispatchResult,
  type PlayerError,
  type PlayerEvent,
  type PlayerIpcResult,
  type PlayerRendererSafeDiagnostic,
  type PlayerSnapshot,
  type PlayerTrackSummary,
} from '../../contracts/player.js';
import {
  LINEUP_PROTOCOL_ORIGIN,
  shellFailure,
  shellSuccess,
  isShellStatusEvent,
  isWindowFullscreenIntentEnvelope,
  type LineupDesktopPreloadApi,
  type ShellCapabilities,
} from '../../contracts/shell.js';
import {
  DIAGNOSTIC_CATEGORIES,
  DIAGNOSTIC_REDACTION_VERSION,
  DIAGNOSTIC_RESULT_VALUES,
  DIAGNOSTIC_SCHEMA_VERSION,
  DIAGNOSTIC_SEVERITIES,
  DIAGNOSTIC_STATUSES,
  DIAGNOSTIC_SURFACES,
  DIAGNOSTIC_TRUNCATION_LIMITS,
  DIAGNOSTICS_REQUEST_ID_PATTERN,
  DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE,
  DIAGNOSTICS_RENDERER_EVENT_CATEGORIES,
  DIAGNOSTICS_RENDERER_EVENT_SEVERITIES,
  DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE,
  DIAGNOSTICS_ERROR_CODES,
  REDACTION_SCAN_FINDING_LABELS,
  SUPPORT_BUNDLE_SCHEMA_VERSION,
  isSafeRendererDiagnosticContextValue,
  type DiagnosticsRendererEventEnvelope,
  type DiagnosticRecord,
  type DiagnosticsError,
  type DiagnosticsResult,
  type RedactionScanReport,
  type SupportBundleExportFailure,
  type SupportBundleExportResult,
} from '../../contracts/diagnostics.js';
import {
  DIAGNOSTIC_FORBIDDEN_FIELD_KEYS,
  RD17_DIAGNOSTIC_FORBIDDEN_FIELD_KEYS,
} from '../../contracts/redaction.js';

function assertNoForbiddenKeys(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) {
      assertNoForbiddenKeys(item);
    }
    return;
  }

  if (value === null || typeof value !== 'object') {
    return;
  }

  for (const [key, child] of Object.entries(value)) {
    assert.equal(
      PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS.includes(
        key as (typeof PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS)[number],
      ),
      false,
      `renderer-facing player contract contains forbidden key ${key}`,
    );
    assert.equal(
      DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.includes(
        key as (typeof DIAGNOSTIC_FORBIDDEN_FIELD_KEYS)[number],
      ),
      false,
      `renderer-facing diagnostics contract contains forbidden key ${key}`,
    );
    assertNoForbiddenKeys(child);
  }
}

test('renderer-facing payload contract forbids privileged fields', () => {
  assert.deepEqual([...RENDERER_FORBIDDEN_PAYLOAD_KEYS].sort(), [
    'authHeaders',
    'credentialMaterial',
    'electronApi',
    'engineId',
    'libmpvObject',
    'nativeHandle',
    'nodeApi',
    'partKey',
    'persistentToken',
    'rawAuthHeaders',
    'rawMediaUrl',
    'rawPlexPayload',
    'secretDiagnostics',
    'streamKey',
    'tokenizedUrl',
  ]);
  assert.deepEqual([...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS].sort(), [
    'authHeaders',
    'credentialMaterial',
    'electronApi',
    'engineId',
    'libmpvObject',
    'nativeHandle',
    'nodeApi',
    'partKey',
    'persistentToken',
    'rawAuthHeaders',
    'rawMediaUrl',
    'rawPlexPayload',
    'secretDiagnostics',
    'streamKey',
    'tokenizedUrl',
  ]);
});

test('redaction boundary keeps renderer unprivileged', () => {
  assert.equal(REDACTION_BOUNDARY.rendererMayPersistSecrets, false);
  assert.equal(REDACTION_BOUNDARY.rendererMayReceiveRawAuthHeaders, false);
  assert.equal(REDACTION_BOUNDARY.rendererMayReceiveNativeHandles, false);
  assert.equal(REDACTION_BOUNDARY.diagnosticsMustBeRedacted, true);
});

test('diagnostics contract freezes RD-17 schema versions and vocabulary', () => {
  assert.equal(DIAGNOSTIC_SCHEMA_VERSION, 1);
  assert.equal(DIAGNOSTIC_REDACTION_VERSION, 'rd17-redaction-v1');
  assert.equal(SUPPORT_BUNDLE_SCHEMA_VERSION, 1);
  assert.deepEqual([...DIAGNOSTIC_SURFACES], [
    'renderer',
    'preload',
    'main',
    'player-ipc',
    'desktop-player-adapter',
    'native-host-process',
    'plex-playback-runtime',
    'support-bundle',
    'redaction',
  ]);
  assert.deepEqual([...DIAGNOSTIC_CATEGORIES], [
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
  ]);
  assert.deepEqual([...DIAGNOSTIC_SEVERITIES], ['debug', 'info', 'warning', 'error']);
  assert.deepEqual([...DIAGNOSTIC_STATUSES], [
    'observed',
    'started',
    'succeeded',
    'failed',
    'rejected',
    'ignored',
    'redacted',
    'truncated',
    'cancelled',
  ]);
  assert.deepEqual([...DIAGNOSTIC_RESULT_VALUES], ['success', 'failure', 'cancelled', 'ignored']);
  assert.deepEqual([...DIAGNOSTICS_RENDERER_EVENT_CATEGORIES], [
    'lifecycle',
    'validation',
    'ipc',
    'support-bundle-export',
  ]);
  assert.deepEqual([...DIAGNOSTICS_RENDERER_EVENT_SEVERITIES], ['info', 'warning', 'error']);
  assert.deepEqual([...DIAGNOSTICS_ERROR_CODES], [
    'DIAGNOSTICS_UNAUTHORIZED',
    'DIAGNOSTICS_VALIDATION_FAILED',
    'DIAGNOSTICS_EXPORT_CANCELLED',
    'DIAGNOSTICS_EXPORT_FAILED',
    'DIAGNOSTICS_REDACTION_FAILED',
    'DIAGNOSTICS_UNAVAILABLE',
    'DIAGNOSTICS_UNKNOWN',
  ]);
});

test('diagnostics renderer event envelope is narrow and renderer-originated', () => {
  const envelope: DiagnosticsRendererEventEnvelope = {
    requestId: 'diagnostics-request-1',
    event: {
      surface: 'renderer',
      category: 'support-bundle-export',
      severity: 'info',
      operation: 'support-bundle.export.click',
      message: 'Support bundle export requested from settings.',
      context: { route: 'settings', focused: true },
    },
  };

  assert.equal(envelope.event.surface, 'renderer');
  assert.equal(Object.hasOwn(envelope.event, 'status'), false);
  assert.equal(Object.hasOwn(envelope.event, 'timestampMs'), false);
  assert.equal(Object.hasOwn(envelope.event, 'path'), false);
  assertNoForbiddenKeys(envelope);
});

test('diagnostics result and support bundle contracts remain renderer-safe', () => {
  const record: DiagnosticRecord = {
    schemaVersion: DIAGNOSTIC_SCHEMA_VERSION,
    id: 'diagnostic-1',
    timestampMs: 1,
    surface: 'main',
    category: 'redaction-scan',
    severity: 'info',
    status: 'succeeded',
    operation: 'support-bundle.scan',
    message: 'Support bundle scan passed.',
    requestId: 'diagnostic-request-1',
    result: 'success',
    context: { fileCount: 3, retryable: false, status: 'passed', value: null },
  };
  const error: DiagnosticsError = {
    code: 'DIAGNOSTICS_REDACTION_FAILED',
    message: 'Support bundle scan failed.',
    recoverable: true,
    retryable: false,
    diagnostic: record,
  };
  const success: DiagnosticsResult<DiagnosticRecord> = {
    ok: true,
    requestId: 'diagnostic-request-1',
    value: record,
  };
  const failure: DiagnosticsResult<DiagnosticRecord> = {
    ok: false,
    requestId: 'diagnostic-request-2',
    error,
  };
  const cancellation: DiagnosticsResult<DiagnosticRecord> = {
    ok: false,
    requestId: 'diagnostic-request-3',
    cancelled: true,
    error: { ...error, code: 'DIAGNOSTICS_EXPORT_CANCELLED' },
  };
  const report: RedactionScanReport = {
    redactionVersion: DIAGNOSTIC_REDACTION_VERSION,
    scannedFileCount: 4,
    scannedByteCount: 512,
    findingCount: 0,
    findingsByLabel: {},
    truncatedRecordCount: 0,
    omittedFileCount: 0,
    status: 'passed',
    timestampMs: 1,
  };
  const exportResult: SupportBundleExportResult = {
    status: 'succeeded',
    bundleId: 'bundle-1',
    bundleDirectoryName: 'lineup-desktop-support-bundle-1',
    createdAtMs: 1,
    fileCount: 4,
    byteCount: 512,
    includedFiles: ['manifest.json', 'diagnostics.ndjson'],
    redactionReport: report,
  };
  const exportFailure: SupportBundleExportFailure = {
    status: 'failed',
    error,
    redactionReport: { ...report, status: 'failed', findingCount: 1 },
  };

  assert.deepEqual(Object.keys(success).sort(), ['ok', 'requestId', 'value']);
  assert.deepEqual(Object.keys(failure).sort(), ['error', 'ok', 'requestId']);
  assert.deepEqual(Object.keys(cancellation).sort(), ['cancelled', 'error', 'ok', 'requestId']);
  assert.equal(Object.hasOwn(exportResult, 'path'), false);
  assert.equal(Object.hasOwn(exportResult, 'filePath'), false);
  assert.equal(Object.hasOwn(exportFailure, 'path'), false);
  assertNoForbiddenKeys(success);
  assertNoForbiddenKeys(failure);
  assertNoForbiddenKeys(cancellation);
  assertNoForbiddenKeys(exportResult);
  assertNoForbiddenKeys(exportFailure);
});

test('diagnostics redaction policy unions prior forbidden fields with RD-17 fields', () => {
  for (const key of [
    ...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
    ...RENDERER_FORBIDDEN_PAYLOAD_KEYS,
    ...RD17_DIAGNOSTIC_FORBIDDEN_FIELD_KEYS,
  ]) {
    assert.equal(
      DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.includes(key),
      true,
      `diagnostic forbidden keys include ${key}`,
    );
  }
  assert.equal(DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.includes('privatePlaybackDescriptor'), true);
  assert.equal(DIAGNOSTIC_FORBIDDEN_FIELD_KEYS.includes('rawIpc'), true);
});

test('diagnostics truncation and scanner report vocabulary match RD-17 Unit 1', () => {
  assert.deepEqual(DIAGNOSTIC_TRUNCATION_LIMITS, {
    rawInputBytes: 65_536,
    messageCharacters: 512,
    operationCharacters: 80,
    requestIdCharacters: 120,
    contextKeyCharacters: 64,
    contextStringCharacters: 256,
    contextEntries: 16,
    nativeOutputSampleCharacters: 1024,
    storeRecords: 500,
    exportRecords: 500,
    diagnosticsNdjsonBytes: 1_048_576,
  });
  assert.equal(DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE, '^[A-Za-z0-9._-]{1,120}$');
  assert.equal(DIAGNOSTICS_REQUEST_ID_PATTERN.test('diagnostic-request_1.2'), true);
  assert.equal(DIAGNOSTICS_REQUEST_ID_PATTERN.test('/Users/example/request'), false);
  assert.equal(DIAGNOSTICS_REQUEST_ID_PATTERN.test('C:\\Users\\example\\request'), false);
  assert.equal(
    DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE.includes('rawIpc'),
    true,
  );
  assert.equal(isSafeRendererDiagnosticContextValue('settings'), true);
  assert.equal(isSafeRendererDiagnosticContextValue('/Users/example/private.mov'), false);
  assert.equal(isSafeRendererDiagnosticContextValue('C:\\Users\\example\\private.mov'), false);
  assert.equal(isSafeRendererDiagnosticContextValue('\\\\server\\share\\private.mov'), false);
  assert.equal(isSafeRendererDiagnosticContextValue('/Library/Application Support/private.mov'), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['access_', 'token=abc123'].join('')), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['oauth', 'Token=abc123'].join('')), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['raw', 'IpcFrame:channel'].join('')), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['process', 'Id=12345'].join('')), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['native_', 'handle=0xabc'].join('')), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['Bear', 'er abcdefgh1234'].join('')), false);
  assert.equal(isSafeRendererDiagnosticContextValue(['p', 'id 12345'].join('')), false);
  assert.deepEqual([...REDACTION_SCAN_FINDING_LABELS], [
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
  ]);
});

test('player command, event, and snapshot contracts carry request ids', () => {
  const intent: RendererIntent = 'player.play';
  const playerIntent: PlayerRendererIntent = 'player.load';
  const loadCommand: PlayerCommand = {
    command: 'load',
    requestId: 'player-request-1',
    payload: {
      media: {
        id: 'media-1',
        title: 'Episode 1',
        durationMs: 1_800_000,
        container: 'mkv',
      },
      policy: {
        autoplay: true,
        startPositionMs: 30_000,
        preferredAudioTrackId: 'audio-ui-1',
        preferredSubtitleTrackId: null,
      },
      capabilityProfileId: 'profile-contract-safe',
    },
  };
  const seekCommand: PlayerCommand = {
    command: 'seek.absolute',
    requestId: 'player-request-1',
    payload: { positionMs: 60_000 },
  };
  const snapshot: PlayerSnapshot = {
    requestId: 'player-request-1',
    status: 'playing',
    media: loadCommand.payload.media,
    capabilityProfileId: 'profile-contract-safe',
    positionMs: 60_000,
    durationMs: 1_800_000,
    bufferedRanges: [{ startMs: 0, endMs: 120_000 }],
    playing: true,
    volume: 0.75,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: 'audio-ui-1',
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: 'video-ui-1',
    tracks: [],
    lastError: null,
  };
  const event: PlayerEvent = {
    event: 'state.changed',
    requestId: snapshot.requestId,
    snapshot,
  };

  assert.equal(intent, 'player.play');
  assert.equal(playerIntent, 'player.load');
  assert.equal(loadCommand.requestId, 'player-request-1');
  assert.equal(seekCommand.payload.positionMs, 60_000);
  assert.equal(event.requestId, snapshot.requestId);
  assertNoForbiddenKeys(loadCommand);
  assertNoForbiddenKeys(snapshot);
  assertNoForbiddenKeys(event);
});

test('player renderer intents are closed and separate from shell window intents', () => {
  assert.deepEqual([...PLAYER_RENDERER_INTENTS], [
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
  ]);
  assert.equal((PLAYER_RENDERER_INTENTS as readonly string[]).includes('window.enterFullscreen'), false);
});

test('player events make stale updates identifiable without engine state', () => {
  const snapshot: PlayerSnapshot = {
    requestId: 'player-request-current',
    status: 'playing',
    media: { id: 'media-current', title: 'Current' },
    capabilityProfileId: 'profile-contract-safe',
    positionMs: 2_000,
    durationMs: null,
    bufferedRanges: [],
    playing: true,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    lastError: null,
  };
  const staleEvent: PlayerEvent = {
    event: 'time.updated',
    requestId: 'player-request-previous',
    positionMs: 90_000,
    durationMs: 120_000,
  };

  assert.notEqual(staleEvent.requestId, snapshot.requestId);
  assert.equal(staleEvent.event, 'time.updated');
});

test('player capability profile records platform-neutral facts', () => {
  const profile: PlaybackCapabilityProfile = {
    id: 'profile-contract-safe',
    containerFormats: ['mp4', 'mkv'],
    videoCodecs: ['h264', 'hevc'],
    audioCodecs: ['aac', 'ac3'],
    subtitleDeliveryModes: ['embedded', 'sidecar', 'external', 'burn-in'],
    headerAuthSetup: 'supported',
    seek: 'supported',
    volume: 'supported',
    audioTrackSwitching: 'unknown',
    subtitleTrackSwitching: 'unknown',
    overlayComposition: 'unproven',
    fullscreenHandling: 'unknown',
    livePlayback: 'unsupported',
    diagnostics: 'supported',
  };

  assert.equal(profile.headerAuthSetup, 'supported');
  assert.equal(profile.overlayComposition, 'unproven');
  assert.equal(profile.livePlayback, 'unsupported');
  assert.equal(Object.hasOwn(profile, 'backend'), false);
  assertNoForbiddenKeys(profile);
});

test('player track ids are opaque renderer ids only', () => {
  const audioTrack: PlayerTrackSummary = {
    id: 'audio-ui-1',
    kind: 'audio',
    label: 'English 5.1',
    language: 'en',
    codec: 'ac3',
    channelCount: 6,
    deliveryType: 'embedded',
    default: true,
    selected: true,
    available: true,
  };
  const subtitleTrack: PlayerTrackSummary = {
    id: 'subtitle-ui-1',
    kind: 'subtitle',
    label: 'English SDH',
    language: 'en',
    format: 'srt',
    deliveryType: 'sidecar',
    forced: false,
    selected: false,
    available: true,
  };

  assert.equal(audioTrack.id, 'audio-ui-1');
  assert.equal(subtitleTrack.deliveryType, 'sidecar');
  assertNoForbiddenKeys(audioTrack);
  assertNoForbiddenKeys(subtitleTrack);
});

test('player error taxonomy and diagnostics stay renderer-safe', () => {
  assert.deepEqual([...PLAYER_ERROR_CATEGORIES], [
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
  ]);

  const diagnostic: PlayerRendererSafeDiagnostic = {
    component: 'player-contract',
    operation: 'load',
    status: 'failed',
    reason: 'redacted setup failure',
    counts: { tracks: 2, retries: 1 },
    capabilityProfileId: 'profile-contract-safe',
    trackIds: ['audio-ui-1', 'subtitle-ui-1'],
    media: { id: 'media-1', title: 'Episode 1' },
    timestampMs: 1,
  };
  const error: PlayerError = {
    code: 'PLAYER_SOURCE_UNAVAILABLE',
    category: 'source',
    message: 'The selected media could not be loaded.',
    recoverable: true,
    retryable: true,
    requestId: 'player-request-1',
    diagnostic,
  };

  assert.equal(error.category, 'source');
  assert.equal(error.diagnostic?.trackIds?.[0], 'audio-ui-1');
  assertNoForbiddenKeys(error);
});

test('shell IPC channel vocabulary uses the approved literals', () => {
  assert.equal(LINEUP_SHELL_GET_CAPABILITIES_CHANNEL, 'lineup:shell:getCapabilities');
  assert.equal(LINEUP_WINDOW_INTENT_CHANNEL, 'lineup:window:intent');
  assert.equal(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, 'lineup:shell:statusChanged');
  assert.equal(LINEUP_PLAYER_COMMAND_CHANNEL, 'lineup:player:command');
  assert.equal(LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL, 'lineup:player:getSnapshot');
  assert.equal(LINEUP_PLAYER_CLEANUP_CHANNEL, 'lineup:player:cleanup');
  assert.equal(LINEUP_PLAYER_EVENT_CHANNEL, 'lineup:player:event');
  assert.equal(
    LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
    'lineup:diagnostics:recordRendererEvent',
  );
  assert.equal(LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL, 'lineup:diagnostics:getSummary');
  assert.equal(
    LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
    'lineup:diagnostics:exportSupportBundle',
  );
});

test('preload API contract exposes shell, window, player, and diagnostics methods only', () => {
  type ApiKeys = keyof LineupDesktopPreloadApi;
  const apiKeys: ApiKeys[] = ['shell', 'window', 'player', 'diagnostics'];
  const shellKeys: Array<keyof LineupDesktopPreloadApi['shell']> = [
    'getCapabilities',
    'onStatusChanged',
  ];
  const windowKeys: Array<keyof LineupDesktopPreloadApi['window']> = ['setFullscreen'];
  const playerKeys: Array<keyof LineupDesktopPreloadApi['player']> = [
    'dispatch',
    'getSnapshot',
    'cleanup',
    'onEvent',
  ];
  const diagnosticsKeys: Array<keyof LineupDesktopPreloadApi['diagnostics']> = [
    'recordRendererEvent',
    'getSummary',
    'exportSupportBundle',
  ];

  assert.deepEqual(apiKeys, ['shell', 'window', 'player', 'diagnostics']);
  assert.deepEqual(shellKeys, ['getCapabilities', 'onStatusChanged']);
  assert.deepEqual(windowKeys, ['setFullscreen']);
  assert.deepEqual(playerKeys, ['dispatch', 'getSnapshot', 'cleanup', 'onEvent']);
  assert.deepEqual(diagnosticsKeys, [
    'recordRendererEvent',
    'getSummary',
    'exportSupportBundle',
  ]);
});

test('player IPC result and dispatch contracts stay renderer-safe', () => {
  const snapshot: PlayerSnapshot = {
    requestId: 'player-request-1',
    status: 'playing',
    media: { id: 'media-1', title: 'Episode 1' },
    capabilityProfileId: 'profile-contract-safe',
    positionMs: 1,
    durationMs: null,
    bufferedRanges: [],
    playing: true,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    lastError: null,
  };
  const dispatch: PlayerDispatchResult = {
    accepted: true,
    events: [{ event: 'state.changed', requestId: 'player-request-1', snapshot }],
    snapshot,
  };
  const success: PlayerIpcResult<PlayerDispatchResult> = {
    ok: true,
    value: dispatch,
    requestId: 'player-request-1',
  };
  const failure: PlayerIpcResult<PlayerDispatchResult> = {
    ok: false,
    requestId: 'player-request-2',
    error: {
      code: 'PLAYER_UNSUPPORTED_CAPABILITY',
      category: 'unsupported-capability',
      message: 'Playback is not available.',
      recoverable: false,
      retryable: false,
      requestId: 'player-request-2',
    },
  };

  assert.equal(Object.hasOwn(dispatch, 'command'), false);
  assert.deepEqual(Object.keys(success).sort(), ['ok', 'requestId', 'value']);
  assert.deepEqual(Object.keys(failure).sort(), ['error', 'ok', 'requestId']);
  assertNoForbiddenKeys(success);
  assertNoForbiddenKeys(failure);
});

test('player event runtime guard rejects unsafe renderer-facing payloads', () => {
  const snapshot: PlayerSnapshot = {
    requestId: 'player-request-1',
    status: 'playing',
    media: { id: 'media-1', title: 'Episode 1' },
    capabilityProfileId: 'profile-contract-safe',
    positionMs: 1,
    durationMs: null,
    bufferedRanges: [],
    playing: true,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    lastError: null,
  };

  assert.equal(
    isRendererSafePlayerEvent({
      event: 'state.changed',
      requestId: 'player-request-1',
      snapshot,
    }),
    true,
  );
  assert.equal(
    isRendererSafePlayerEvent({
      event: 'state.changed',
      requestId: 'player-request-1',
      snapshot: {
        ...snapshot,
        media: { id: 'media-1', title: 'Episode 1', rawMediaUrl: 'redacted' },
      },
    }),
    false,
  );
  assert.equal(
    isRendererSafePlayerEvent({
      event: 'tracks.changed',
      requestId: 'player-request-1',
      tracks: [
        {
          id: 'audio-ui-1',
          kind: 'audio',
          label: 'English',
          selected: true,
          available: true,
          nativeHandle: 'redacted',
        },
      ],
    }),
    false,
  );
  assert.equal(
    isRendererSafePlayerEvent({
      event: 'error',
      requestId: 'player-request-1',
      error: {
        code: 'PLAYER_BAD',
        category: 'native-secret',
        message: 'Bad payload',
        recoverable: false,
        retryable: false,
      },
    }),
    false,
  );
  assert.equal(
    isRendererSafePlayerEvent({
      event: 'command.settled',
      requestId: 'player-request-1',
      command: 'play',
      ok: true,
      error: {
        code: 'PLAYER_BAD',
        category: 'unknown',
        message: 'Should not be attached to ok command.',
        recoverable: false,
        retryable: false,
      },
    }),
    false,
  );
});

test('shell capability and result contracts are renderer-safe', () => {
  const capabilities: ShellCapabilities = {
    appName: 'Lineup Desktop',
    appVersion: '0.0.0',
    platform: 'win32',
    shellMode: 'smoke',
    protocolOrigin: LINEUP_PROTOCOL_ORIGIN,
  };

  assert.deepEqual(shellSuccess('request-1', capabilities), {
    ok: true,
    value: capabilities,
    requestId: 'request-1',
  });
  assert.deepEqual(shellFailure('request-2', 'unauthorized', 'Request is not authorized.'), {
    ok: false,
    error: {
      code: 'unauthorized',
      message: 'Request is not authorized.',
    },
    requestId: 'request-2',
  });
});

test('shell status events and fullscreen intents validate closed', () => {
  assert.equal(isShellStatusEvent({ status: 'ready', timestampMs: 1 }), true);
  assert.equal(isShellStatusEvent({ status: 'ready', timestampMs: Number.NaN }), false);
  assert.equal(isShellStatusEvent({ status: 'secret', timestampMs: 1 }), false);

  assert.equal(
    isWindowFullscreenIntentEnvelope({
      intent: 'window.enterFullscreen',
      requestId: 'request-1',
      payload: {},
    }),
    true,
  );
  assert.equal(
    isWindowFullscreenIntentEnvelope({
      intent: 'window.setFullscreen',
      requestId: 'request-1',
      payload: {},
    }),
    false,
  );
  assert.equal(
    isWindowFullscreenIntentEnvelope({
      intent: 'window.exitFullscreen',
      requestId: 'request-1',
      payload: { enabled: false },
    }),
    false,
  );
});
