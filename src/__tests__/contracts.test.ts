import test from 'node:test';
import assert from 'node:assert/strict';

import {
  RENDERER_FORBIDDEN_PAYLOAD_KEYS,
  type RendererIntent,
} from '../contracts/ipc.js';
import { REDACTION_BOUNDARY } from '../contracts/redaction.js';
import type { PlaybackCapabilityProfile, PlayerSnapshot } from '../contracts/player.js';

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
