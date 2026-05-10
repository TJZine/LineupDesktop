import test from 'node:test';
import assert from 'node:assert/strict';

import { DesktopPlayerAdapter } from '../main/player/desktopPlayerAdapter.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostEvent,
  NativePlayerHostPort,
} from '../main/player/nativePlayerHostPort.js';
import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerErrorCategory,
  type PlayerEvent,
  type PlayerMediaSummary,
  type PlayerTrackSummary,
} from '../contracts/player.js';
import type { RendererIntentEnvelope } from '../contracts/ipc.js';

class FakeNativePlayerHost implements NativePlayerHostPort {
  readonly commands: PlayerCommand[] = [];
  readonly cleanupRequestIds: Array<string | null> = [];
  executeResult: NativePlayerHostCommandResult = { ok: true };
  cleanupError: Error | null = null;

  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    this.commands.push(command);
    return this.executeResult;
  }

  async cleanup(requestId: string | null): Promise<void> {
    this.cleanupRequestIds.push(requestId);
    if (this.cleanupError !== null) {
      throw this.cleanupError;
    }
  }
}

class DeferredNativePlayerHost implements NativePlayerHostPort {
  readonly commands: PlayerCommand[] = [];
  readonly cleanupRequestIds: Array<string | null> = [];
  readonly resolvers: Array<(result: NativePlayerHostCommandResult) => void> = [];

  async execute(command: PlayerCommand): Promise<NativePlayerHostCommandResult> {
    this.commands.push(command);
    return new Promise<NativePlayerHostCommandResult>((resolve) => {
      this.resolvers.push(resolve);
    });
  }

  async cleanup(requestId: string | null): Promise<void> {
    this.cleanupRequestIds.push(requestId);
  }

  resolveNext(result: NativePlayerHostCommandResult = { ok: true }): void {
    const resolve = this.resolvers.shift();
    assert.ok(resolve, 'expected pending native host command');
    resolve(result);
  }
}

const media: PlayerMediaSummary = {
  id: 'media-1',
  title: 'Episode 1',
  durationMs: 120_000,
  container: 'mkv',
};

const audioTrack: PlayerTrackSummary = {
  id: 'audio-ui-1',
  kind: 'audio',
  label: 'English',
  language: 'en',
  deliveryType: 'embedded',
  selected: true,
  available: true,
};

const subtitleTrack: PlayerTrackSummary = {
  id: 'subtitle-ui-1',
  kind: 'subtitle',
  label: 'English CC',
  language: 'en',
  deliveryType: 'sidecar',
  selected: false,
  available: true,
};

function loadEnvelope(requestId = 'request-load-1'): RendererIntentEnvelope<unknown> {
  return {
    intent: 'player.load',
    requestId,
    payload: {
      media,
      policy: {
        autoplay: true,
        startPositionMs: 5_000,
        preferredAudioTrackId: 'audio-ui-1',
        preferredSubtitleTrackId: null,
      },
      capabilityProfileId: 'desktop-adapter-safe',
    },
  };
}

function emptyEnvelope(
  intent: RendererIntentEnvelope<unknown>['intent'],
  requestId: string,
): RendererIntentEnvelope<unknown> {
  return { intent, requestId, payload: {} };
}

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
      `renderer-facing adapter value contains forbidden key ${key}`,
    );
    assertNoForbiddenKeys(child);
  }
}

function assertErrorEvent(events: readonly PlayerEvent[], category: PlayerErrorCategory): PlayerEvent {
  const errorEvent = events.find((event) => event.event === 'error');
  assert.ok(errorEvent, 'expected error event');
  assert.equal(errorEvent.error.category, category);
  assertNoForbiddenKeys(errorEvent);
  return errorEvent;
}

function assertTextAbsent(value: unknown, text: string): void {
  assert.equal(JSON.stringify(value).includes(text), false, `unexpected renderer-facing text ${text}`);
}

test('desktop player adapter maps renderer intents to closed player commands', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));
  await adapter.dispatchRendererIntent(emptyEnvelope('player.play', 'request-play-1'));
  await adapter.dispatchRendererIntent({
    intent: 'player.seekAbsolute',
    requestId: 'request-seek-1',
    payload: { positionMs: 42_000 },
  });
  await adapter.dispatchRendererIntent({
    intent: 'player.setVolume',
    requestId: 'request-volume-1',
    payload: { volume: 0.5 },
  });
  await adapter.dispatchRendererIntent({
    intent: 'player.selectAudio',
    requestId: 'request-audio-1',
    payload: { trackId: 'audio-ui-2' },
  });
  await adapter.dispatchRendererIntent({
    intent: 'player.selectSubtitle',
    requestId: 'request-subtitle-1',
    payload: { trackId: null },
  });

  assert.deepEqual(
    host.commands.map((command) => command.command),
    ['load', 'play', 'seek.absolute', 'volume.set', 'track.audio.select', 'track.subtitle.select'],
  );
  const loadCommand = host.commands.find((command) => command.command === 'load');
  const seekCommand = host.commands.find((command) => command.command === 'seek.absolute');
  const audioCommand = host.commands.find((command) => command.command === 'track.audio.select');
  const subtitleCommand = host.commands.find((command) => command.command === 'track.subtitle.select');
  assert.equal(loadCommand?.requestId, 'request-load-1');
  assert.equal(seekCommand?.payload.positionMs, 42_000);
  assert.equal(audioCommand?.payload.trackId, 'audio-ui-2');
  assert.equal(subtitleCommand?.payload.trackId, null);
  assertNoForbiddenKeys(host.commands);
});

test('desktop player adapter emits renderer-safe snapshots and host events', async () => {
  const host = new FakeNativePlayerHost();
  host.executeResult = {
    ok: true,
    events: [
      {
        type: 'media.loaded',
        requestId: 'request-load-1',
        media,
        durationMs: 120_000,
        tracks: [audioTrack, subtitleTrack],
      },
      {
        type: 'playback.state',
        requestId: 'request-load-1',
        status: 'playing',
        playing: true,
      },
      {
        type: 'time.updated',
        requestId: 'request-load-1',
        positionMs: 12_000,
        durationMs: 120_000,
      },
    ],
  };
  const adapter = new DesktopPlayerAdapter(host);

  const result = await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));

  assert.equal(result.accepted, true);
  assert.equal(result.snapshot.status, 'playing');
  assert.equal(result.snapshot.playing, true);
  assert.equal(result.snapshot.positionMs, 12_000);
  assert.equal(result.snapshot.selectedAudioTrackId, 'audio-ui-1');
  assert.equal(result.events.some((event) => event.event === 'media.loaded'), true);
  assert.equal(result.events.some((event) => event.event === 'time.updated'), true);
  assert.equal(result.events.some((event) => event.event === 'command.settled' && event.ok), true);
  assertNoForbiddenKeys(result);
});

test('desktop player adapter ignores stale host events by request id', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-current'));

  const events = adapter.handleHostEvent({
    type: 'time.updated',
    requestId: 'request-previous',
    positionMs: 90_000,
    durationMs: 120_000,
  } satisfies NativePlayerHostEvent);

  assert.equal(adapter.getSnapshot().requestId, 'request-current');
  assert.equal(adapter.getSnapshot().positionMs, 5_000);
  assert.equal(events[0]?.event, 'warning');
  if (events[0]?.event === 'warning') {
    assert.equal(events[0].warning.category, 'stale-request');
  }
  assertNoForbiddenKeys(events);
});

test('desktop player adapter quarantines older pending load events from newer snapshots', async () => {
  const host = new DeferredNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  const oldDispatch = adapter.dispatchRendererIntent(loadEnvelope('request-older'));
  const newDispatch = adapter.dispatchRendererIntent(loadEnvelope('request-newer'));

  assert.equal(adapter.getPendingRequestCount(), 2);
  assert.equal(adapter.getSnapshot().requestId, 'request-newer');

  const events = adapter.handleHostEvent({
    type: 'media.loaded',
    requestId: 'request-older',
    media: { ...media, id: 'media-older' },
    durationMs: 120_000,
    tracks: [audioTrack],
  } satisfies NativePlayerHostEvent);

  assert.equal(adapter.getSnapshot().requestId, 'request-newer');
  assert.notEqual(adapter.getSnapshot().media?.id, 'media-older');
  assert.equal(events[0]?.event, 'warning');
  if (events[0]?.event === 'warning') {
    assert.equal(events[0].warning.category, 'stale-request');
  }

  host.resolveNext();
  host.resolveNext();
  await Promise.all([oldDispatch, newDispatch]);
  assertNoForbiddenKeys(events);
});

test('desktop player adapter quarantines stale host events after cleanup', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-current'));
  await adapter.cleanup();
  const before = adapter.getSnapshot();

  const events = adapter.handleHostEvent({
    type: 'time.updated',
    requestId: 'request-current',
    positionMs: 90_000,
    durationMs: 120_000,
  } satisfies NativePlayerHostEvent);

  assert.deepEqual(adapter.getSnapshot(), before);
  assert.equal(events[0]?.event, 'warning');
  if (events[0]?.event === 'warning') {
    assert.equal(events[0].warning.category, 'stale-request');
  }
  assertNoForbiddenKeys(events);
});

test('desktop player adapter quarantines unscoped host errors after cleanup', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-current'));
  await adapter.cleanup();
  const before = adapter.getSnapshot();

  const events = adapter.handleHostEvent({
    type: 'error',
    requestId: null,
    error: {
      code: 'RAW_NATIVE_HANDLE',
      category: 'helper-failure',
      message: 'raw helper failure detail',
      recoverable: false,
      retryable: false,
    },
  } satisfies NativePlayerHostEvent);

  assert.deepEqual(adapter.getSnapshot(), before);
  assert.equal(events[0]?.event, 'warning');
  if (events[0]?.event === 'warning') {
    assert.equal(events[0].warning.category, 'stale-request');
  }
  assertTextAbsent(events, 'RAW_NATIVE_HANDLE');
  assertTextAbsent(events, 'raw helper failure detail');
  assertNoForbiddenKeys(events);
});

test('desktop player adapter redacts diagnostics and maps helper crash safely', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));

  const events = adapter.handleHelperCrash();

  const errorEvent = assertErrorEvent(events, 'helper-failure');
  if (errorEvent.event === 'error') {
    assert.equal(errorEvent.error.code, 'PLAYER_HELPER_CRASHED');
    assert.equal(errorEvent.error.diagnostic?.component, 'desktop-player-adapter');
    assert.equal(errorEvent.error.diagnostic?.reason, 'helper terminated');
  }
  assert.equal(adapter.getSnapshot().status, 'error');
  assertNoForbiddenKeys(adapter.getSnapshot());
});

test('desktop player adapter clears pending request ids on helper crash', async () => {
  const host = new DeferredNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  const pendingDispatch = adapter.dispatchRendererIntent(loadEnvelope('request-crashing'));

  assert.equal(adapter.getPendingRequestCount(), 1);
  const events = adapter.handleHelperCrash();

  assert.equal(adapter.getPendingRequestCount(), 0);
  assertErrorEvent(events, 'helper-failure');
  assert.equal(adapter.getSnapshot().status, 'error');

  host.resolveNext();
  await pendingDispatch;
  assertNoForbiddenKeys(events);
});

test('desktop player adapter cleans up requests and maps cleanup failure safely', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));
  assert.equal(adapter.getPendingRequestCount(), 0);

  const clean = await adapter.cleanup();
  assert.equal(clean.accepted, true);
  assert.equal(host.cleanupRequestIds[0], 'request-load-1');
  assert.equal(clean.snapshot.status, 'idle');

  await adapter.dispatchRendererIntent(loadEnvelope('request-load-2'));
  host.cleanupError = new Error('nativeHandle=secret');
  const failed = await adapter.cleanup();

  assert.equal(failed.accepted, false);
  assertErrorEvent(failed.events, 'cleanup-failure');
  assertNoForbiddenKeys(failed);
});

test('desktop player adapter rejects invalid renderer payloads before host calls', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  const before = adapter.getSnapshot();

  const result = await adapter.dispatchRendererIntent({
    intent: 'player.load',
    requestId: 'request-invalid',
    payload: {
      media: {
        id: 'media-1',
        title: 'Episode 1',
        rawMediaUrl: 'redacted-by-rejection',
      },
      policy: { autoplay: true },
    },
  } as RendererIntentEnvelope<unknown>);

  assert.equal(result.accepted, false);
  assert.equal(host.commands.length, 0);
  assertErrorEvent(result.events, 'validation-failure');
  assert.deepEqual(result.snapshot, before);
  assert.deepEqual(adapter.getSnapshot(), before);
});

test('desktop player adapter rejects unsupported payload fields without echoing field names', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  const before = adapter.getSnapshot();

  const result = await adapter.dispatchRendererIntent({
    intent: 'player.setVolume',
    requestId: 'request-unsupported-field',
    payload: {
      volume: 0.25,
      sensitiveTokenLookingField: 'do-not-echo',
    },
  } as RendererIntentEnvelope<unknown>);

  assert.equal(result.accepted, false);
  assert.equal(host.commands.length, 0);
  assertErrorEvent(result.events, 'validation-failure');
  assert.deepEqual(result.snapshot, before);
  assert.deepEqual(adapter.getSnapshot(), before);
  assertTextAbsent(result, 'sensitiveTokenLookingField');
  assertTextAbsent(result, 'do-not-echo');
});

test('desktop player adapter rejects invalid host events before mutation', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));

  const before = adapter.getSnapshot();
  const events = adapter.handleHostEvent({
    type: 'time.updated',
    requestId: 'request-load-1',
    positionMs: -1,
    durationMs: 120_000,
  });
  const after = adapter.getSnapshot();

  assertErrorEvent(events, 'validation-failure');
  assert.deepEqual(after, before);
  assertNoForbiddenKeys(after);
});

test('desktop player adapter excludes forbidden fields from host events and errors', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));

  const forbiddenMediaEvents = adapter.handleHostEvent({
    type: 'media.loaded',
    requestId: 'request-load-1',
    media: {
      id: 'media-2',
      title: 'Episode 2',
      tokenizedUrl: 'redacted-by-rejection',
    },
    durationMs: 10_000,
  });
  const forbiddenErrorEvents = adapter.handleHostEvent({
    type: 'error',
    requestId: 'request-load-1',
    error: {
      code: 'PLAYER_NATIVE_FAILURE',
      category: 'engine-failure',
      message: 'Native player failed.',
      recoverable: false,
      retryable: false,
      diagnostic: {
        component: 'native-host',
        operation: 'playback',
        secretDiagnostics: 'redacted-by-rejection',
      },
    },
  });

  assertErrorEvent(forbiddenMediaEvents, 'validation-failure');
  assertErrorEvent(forbiddenErrorEvents, 'validation-failure');
  assert.notEqual(adapter.getSnapshot().media?.id, 'media-2');
  assertNoForbiddenKeys(adapter.getSnapshot());
});

test('desktop player adapter normalizes host failure strings before renderer exposure', async () => {
  const host = new FakeNativePlayerHost();
  host.executeResult = {
    ok: false,
    error: {
      code: 'RAW_NATIVE_HANDLE',
      category: 'helper-failure',
      message: 'rawMediaUrl and nativeHandle details are hidden',
      recoverable: true,
      retryable: true,
    },
  };
  const adapter = new DesktopPlayerAdapter(host);

  const result = await adapter.dispatchRendererIntent(emptyEnvelope('player.play', 'request-play-1'));

  assertErrorEvent(result.events, 'helper-failure');
  assertTextAbsent(result, 'RAW_NATIVE_HANDLE');
  assertTextAbsent(result, 'rawMediaUrl');
  assertTextAbsent(result, 'nativeHandle');
  assert.equal(
    result.events.some((event) => {
      if (event.event !== 'command.settled' || event.ok) {
        return false;
      }
      return event.error?.code === 'PLAYER_HOST_HELPER_FAILURE';
    }),
    true,
  );
});
