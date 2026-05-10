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
  PLAYER_RENDERER_INTENTS,
  RENDERER_FORBIDDEN_PAYLOAD_KEYS,
  type PlayerRendererIntent,
  type RendererIntent,
} from '../contracts/ipc.js';
import { REDACTION_BOUNDARY } from '../contracts/redaction.js';
import {
  PLAYER_ERROR_CATEGORIES,
  PLAYER_COMMAND_VALUES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  PLAYER_STATUS_VALUES,
  PLAYER_TRACK_DELIVERY_TYPE_VALUES,
  PLAYER_TRACK_KIND_VALUES,
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
} from '../contracts/player.js';
import {
  LINEUP_PROTOCOL_ORIGIN,
  LINEUP_SHELL_URL,
  SHELL_STATUS_VALUES,
  isShellStatusEvent,
  isWindowFullscreenIntentEnvelope,
  shellFailure,
  shellSuccess,
  type LineupDesktopPreloadApi,
  type ShellCapabilities,
} from '../contracts/shell.js';
import {
  isAllowedShellOrigin,
  isAllowedShellUrl,
  isAuthorizedShellIpcRequest,
} from '../main/shellSecurity.js';
import preloadVocabulary from '../preload/vocabulary.cjs';

const {
  PLAYER_COMMAND_VALUES: PRELOAD_PLAYER_COMMAND_VALUES,
  PLAYER_ERROR_CATEGORIES: PRELOAD_PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS: PRELOAD_PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  PLAYER_RENDERER_INTENT_VALUES: PRELOAD_PLAYER_RENDERER_INTENT_VALUES,
  PLAYER_STATUS_VALUES: PRELOAD_PLAYER_STATUS_VALUES,
  PLAYER_TRACK_DELIVERY_TYPE_VALUES: PRELOAD_PLAYER_TRACK_DELIVERY_TYPE_VALUES,
  PLAYER_TRACK_KIND_VALUES: PRELOAD_PLAYER_TRACK_KIND_VALUES,
  SHELL_STATUS_VALUES: PRELOAD_SHELL_STATUS_VALUES,
} = preloadVocabulary;

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

test('preload guard vocabulary matches contract vocabulary', () => {
  assert.deepEqual([...PRELOAD_SHELL_STATUS_VALUES], [...SHELL_STATUS_VALUES]);
  assert.deepEqual([...PRELOAD_PLAYER_ERROR_CATEGORIES], [...PLAYER_ERROR_CATEGORIES]);
  assert.deepEqual(
    [...PRELOAD_PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS],
    [...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS],
  );
  assert.deepEqual([...PRELOAD_PLAYER_STATUS_VALUES], [...PLAYER_STATUS_VALUES]);
  assert.deepEqual([...PRELOAD_PLAYER_COMMAND_VALUES], [...PLAYER_COMMAND_VALUES]);
  assert.deepEqual([...PRELOAD_PLAYER_RENDERER_INTENT_VALUES], [...PLAYER_RENDERER_INTENTS]);
  assert.deepEqual([...PRELOAD_PLAYER_TRACK_KIND_VALUES], [...PLAYER_TRACK_KIND_VALUES]);
  assert.deepEqual(
    [...PRELOAD_PLAYER_TRACK_DELIVERY_TYPE_VALUES],
    [...PLAYER_TRACK_DELIVERY_TYPE_VALUES],
  );
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
});

test('preload API contract exposes shell, window, and player methods only', () => {
  type ApiKeys = keyof LineupDesktopPreloadApi;
  const apiKeys: ApiKeys[] = ['shell', 'window', 'player'];
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

  assert.deepEqual(apiKeys, ['shell', 'window', 'player']);
  assert.deepEqual(shellKeys, ['getCapabilities', 'onStatusChanged']);
  assert.deepEqual(windowKeys, ['setFullscreen']);
  assert.deepEqual(playerKeys, ['dispatch', 'getSnapshot', 'cleanup', 'onEvent']);
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

test('shell URL and IPC authorization reject unexpected senders and origins', () => {
  assert.equal(isAllowedShellUrl(LINEUP_SHELL_URL), true);
  assert.equal(isAllowedShellUrl('lineup://shell/other.html'), false);
  assert.equal(isAllowedShellOrigin('lineup://shell/index.html'), true);
  assert.equal(isAllowedShellOrigin('https://example.com'), false);

  const authorized = {
    senderMatchesShell: true,
    senderDestroyed: false,
    senderUrl: LINEUP_SHELL_URL,
    frameUrl: LINEUP_SHELL_URL,
    frameIsMainFrame: true,
  };

  assert.equal(isAuthorizedShellIpcRequest(authorized), true);
  assert.equal(
    isAuthorizedShellIpcRequest({ ...authorized, senderMatchesShell: false }),
    false,
  );
  assert.equal(isAuthorizedShellIpcRequest({ ...authorized, senderDestroyed: true }), false);
  assert.equal(
    isAuthorizedShellIpcRequest({ ...authorized, senderUrl: 'lineup://shell/other.html' }),
    false,
  );
  assert.equal(
    isAuthorizedShellIpcRequest({ ...authorized, frameUrl: 'https://example.com' }),
    false,
  );
  assert.equal(isAuthorizedShellIpcRequest({ ...authorized, frameIsMainFrame: false }), false);
});
