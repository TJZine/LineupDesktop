import test from 'node:test';
import assert from 'node:assert/strict';

import {
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
  RENDERER_FORBIDDEN_PAYLOAD_KEYS,
  type RendererIntent,
} from '../contracts/ipc.js';
import { REDACTION_BOUNDARY } from '../contracts/redaction.js';
import type { PlaybackCapabilityProfile, PlayerSnapshot } from '../contracts/player.js';
import {
  LINEUP_PROTOCOL_ORIGIN,
  LINEUP_SHELL_URL,
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

test('renderer-facing payload contract forbids privileged fields', () => {
  assert.deepEqual([...RENDERER_FORBIDDEN_PAYLOAD_KEYS].sort(), [
    'nativeHandle',
    'persistentToken',
    'rawAuthHeaders',
    'tokenizedUrl',
  ]);
});

test('redaction boundary keeps renderer unprivileged', () => {
  assert.equal(REDACTION_BOUNDARY.rendererMayPersistSecrets, false);
  assert.equal(REDACTION_BOUNDARY.rendererMayReceiveRawAuthHeaders, false);
  assert.equal(REDACTION_BOUNDARY.rendererMayReceiveNativeHandles, false);
  assert.equal(REDACTION_BOUNDARY.diagnosticsMustBeRedacted, true);
});

test('player contract supports explicit capability and snapshot shapes', () => {
  const intent: RendererIntent = 'player.play';
  const profile: PlaybackCapabilityProfile = {
    backend: 'desktop-fake-host',
    containers: [],
    videoCodecs: [],
    audioCodecs: [],
    subtitleFormats: [],
    supportsHeaderAuth: true,
    supportsNativeFullscreen: false,
    supportsOverlayComposition: 'unknown',
  };
  const snapshot: PlayerSnapshot = {
    requestId: null,
    status: 'idle',
    positionMs: 0,
    durationMs: 0,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    errorCategory: null,
  };

  assert.equal(intent, 'player.play');
  assert.equal(profile.backend, 'desktop-fake-host');
  assert.equal(snapshot.status, 'idle');
});

test('shell IPC channel vocabulary uses the approved literals', () => {
  assert.equal(LINEUP_SHELL_GET_CAPABILITIES_CHANNEL, 'lineup:shell:getCapabilities');
  assert.equal(LINEUP_WINDOW_INTENT_CHANNEL, 'lineup:window:intent');
  assert.equal(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, 'lineup:shell:statusChanged');
});

test('preload API contract exposes only shell and window methods', () => {
  type ApiKeys = keyof LineupDesktopPreloadApi;
  const apiKeys: ApiKeys[] = ['shell', 'window'];
  const shellKeys: Array<keyof LineupDesktopPreloadApi['shell']> = [
    'getCapabilities',
    'onStatusChanged',
  ];
  const windowKeys: Array<keyof LineupDesktopPreloadApi['window']> = ['setFullscreen'];

  assert.deepEqual(apiKeys, ['shell', 'window']);
  assert.deepEqual(shellKeys, ['getCapabilities', 'onStatusChanged']);
  assert.deepEqual(windowKeys, ['setFullscreen']);
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
