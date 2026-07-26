import test from 'node:test';
import assert from 'node:assert/strict';
import { setImmediate } from 'node:timers';

import { DesktopPlayerAdapter } from '../../../main/player/desktopPlayerAdapter.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import {
  normalizeNativeHelperFailure,
  parseNativeHelperProcessMessage,
} from '../../../main/player/nativeHelperProtocolCodec.js';
import type {
  NativePlayerHostCommandResult,
  NativePlayerHostEvent,
  NativePlayerHostLifecycleFailure,
  NativePlayerHostPort,
} from '../../../main/player/nativePlayerHostPort.js';
import {
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  type PlayerCommand,
  type PlayerErrorCategory,
  type PlayerEvent,
  type PlayerLoadCommandPayload,
  type PlayerMediaSummary,
  type PlayerTrackSummary,
} from '../../../contracts/player.js';
import type { RendererIntentEnvelope } from '../../../contracts/ipc.js';
import type { PrivilegedPlaybackDispatchContext } from '../../../main/player/privilegedPlaybackDispatchContext.js';

class FakeNativePlayerHost implements NativePlayerHostPort {
  readonly commands: PlayerCommand[] = [];
  readonly cleanupRequestIds: Array<string | null> = [];
  private readonly eventListeners = new Set<(event: NativePlayerHostEvent) => void>();
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

  onEvent(listener: (event: NativePlayerHostEvent) => void): () => void {
    this.eventListeners.add(listener);
    return () => {
      this.eventListeners.delete(listener);
    };
  }

  emitEvent(event: NativePlayerHostEvent): void {
    for (const listener of [...this.eventListeners]) {
      listener(event);
    }
  }
}

class LifecycleFakeNativePlayerHost extends FakeNativePlayerHost {
  private readonly listeners = new Set<(failure: NativePlayerHostLifecycleFailure) => void>();

  onLifecycleFailure(listener: (failure: NativePlayerHostLifecycleFailure) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  emitLifecycleFailure(failure: NativePlayerHostLifecycleFailure): void {
    for (const listener of [...this.listeners]) {
      listener(failure);
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

function runtimeLoadCommand(requestId = 'request-load-1'): PlayerCommand {
  return {
    command: 'load',
    requestId,
    payload: loadEnvelope(requestId).payload as PlayerLoadCommandPayload,
  };
}

function privilegedContext(requestId = 'request-load-1'): PrivilegedPlaybackDispatchContext {
  return {
    privatePlayback: {
      requestId,
      decisionKind: 'direct-play',
      playbackUrl: 'https://plex.example.invalid/library/parts/1/file.mp4',
      credentialHeader: { name: 'X-Plex-Token', value: 'private-token' },
      selectedConnection: {
        protocol: 'https',
        address: 'plex.example.invalid',
        port: 443,
        local: true,
        relay: false,
      },
      media,
      setup: {
        playbackMode: 'direct-play',
        mediaPath: '/library/metadata/1',
        variantId: 'variant-1',
        partPath: '/library/parts/1/file.mp4',
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: { video: [], audio: [], subtitle: [] },
      },
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
  host.executeResult = {
    ok: true,
    events: [
      {
        type: 'media.loaded',
        requestId: 'request-load-1',
        media,
        durationMs: 120_000,
        tracks: [
          audioTrack,
          { ...audioTrack, id: 'audio-ui-2', label: 'French' },
          subtitleTrack,
        ],
      },
    ],
  };
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
    payload: { trackId: 'audio-ui-2', snapshotRequestId: 'request-load-1' },
  });
  await adapter.dispatchRendererIntent({
    intent: 'player.selectSubtitle',
    requestId: 'request-subtitle-1',
    payload: { trackId: null, snapshotRequestId: 'request-load-1' },
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

test('native helper protocol codec normalizes failure codes and rejects top-level arrays', () => {
  assert.deepEqual(
    normalizeNativeHelperFailure({
      code: 'helper failed: bad-code',
      category: 'helper-failure',
      recoverable: false,
      retryable: true,
    }),
    {
      code: 'HELPER_FAILED__BAD_CODE',
      category: 'helper-failure',
      message: 'The player helper failed while handling the command.',
      recoverable: false,
      retryable: true,
    },
  );

  const result = parseNativeHelperProcessMessage('[]');
  assert.equal('error' in result, true);
  if ('error' in result) {
    assert.equal(result.error.code, 'PLAYER_HELPER_MALFORMED_OUTPUT');
  }
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

test('desktop player adapter records helper lifecycle failures without raw process details', async () => {
  const host = new LifecycleFakeNativePlayerHost();
  const emittedEvents: PlayerEvent[] = [];
  const diagnostics = new DiagnosticEventStore({ clock: () => 1_000, idGenerator: () => 'adapter-lifecycle' });
  const adapter = new DesktopPlayerAdapter(host, {
    onEvents: (events) => emittedEvents.push(...events),
    diagnosticEventStore: diagnostics,
  });

  await adapter.dispatchRendererIntent(loadEnvelope('request-lifecycle'));

  host.emitLifecycleFailure({
    requestId: null,
    error: {
      code: 'PLAYER_HELPER_EXITED',
      category: 'helper-failure',
      message: 'raw exit code 123',
      recoverable: true,
      retryable: true,
    },
  });

  const snapshot = adapter.getSnapshot();
  const errorEvent = emittedEvents.find((event) => event.event === 'error');

  assert.ok(errorEvent);
  assert.equal(errorEvent.error.category, 'helper-failure');
  assert.equal(errorEvent.error.message, 'The player helper stopped unexpectedly.');
  assert.equal(snapshot.status, 'error');
  assert.equal(snapshot.lastError?.category, 'helper-failure');
  assertTextAbsent(emittedEvents, 'raw exit code');
  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
  assertTextAbsent(diagnostics.getRecords(), 'raw exit code');
  assertNoForbiddenKeys(emittedEvents);
  assertNoForbiddenKeys(snapshot);
});

test('desktop player adapter keeps lifecycle reporting after normal cleanup and reuse', async () => {
  const host = new LifecycleFakeNativePlayerHost();
  const emittedEvents: PlayerEvent[] = [];
  const adapter = new DesktopPlayerAdapter(host, {
    onEvents: (events) => emittedEvents.push(...events),
  });

  await adapter.dispatchRendererIntent(loadEnvelope('request-before-cleanup'));
  const cleanup = await adapter.cleanup();
  assert.equal(cleanup.accepted, true);
  await adapter.dispatchRendererIntent(loadEnvelope('request-after-cleanup'));

  host.emitLifecycleFailure({
    requestId: null,
    error: {
      code: 'PLAYER_HELPER_EXITED',
      category: 'helper-failure',
      message: 'raw exit code after cleanup',
      recoverable: true,
      retryable: true,
    },
  });

  const errorEvent = [...emittedEvents].reverse().find((event) => event.event === 'error');
  assert.ok(errorEvent);
  assert.equal(errorEvent.error.category, 'helper-failure');
  assert.equal(adapter.getSnapshot().status, 'error');
  assertTextAbsent(emittedEvents, 'raw exit code after cleanup');
  assertNoForbiddenKeys(emittedEvents);
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
  const diagnostics = new DiagnosticEventStore({ clock: () => 2_000, idGenerator: () => 'adapter-cleanup' });
  const adapter = new DesktopPlayerAdapter(host, { diagnosticEventStore: diagnostics });

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
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 1);
  assertTextAbsent(diagnostics.getRecords(), 'nativeHandle');
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

  assert.equal(host.commands.length, 0);
  assertErrorEvent(result.events, 'validation-failure');
  assert.deepEqual(result.snapshot, before);
  assert.deepEqual(adapter.getSnapshot(), before);
});

test('desktop player adapter rejects renderer loads in production mode without mutating active snapshot', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host, { rejectRendererLoad: true });

  const runtimeResult = await adapter.dispatchRuntimeCommand(
    runtimeLoadCommand('request-runtime-load'),
    privilegedContext('request-runtime-load'),
  );
  assert.equal(runtimeResult.accepted, true);
  const activeSnapshot = adapter.getSnapshot();

  const rejected = await adapter.dispatchRendererIntent(loadEnvelope('request-renderer-load'));

  assert.equal(rejected.accepted, false);
  assertErrorEvent(rejected.events, 'unsupported-capability');
  assert.equal(host.commands.length, 1);
  assert.deepEqual(rejected.snapshot, activeSnapshot);
  assert.deepEqual(adapter.getSnapshot(), activeSnapshot);
});

test('desktop player adapter rejects duplicate in-flight renderer request IDs before host dispatch', async () => {
  const host = new DeferredNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  const first = adapter.dispatchRendererIntent(emptyEnvelope('player.play', 'request-duplicate'));
  await new Promise<void>((resolve) => setImmediate(resolve));
  const second = await adapter.dispatchRendererIntent(emptyEnvelope('player.pause', 'request-duplicate'));

  assert.equal(second.accepted, false);
  assertErrorEvent(second.events, 'validation-failure');
  assert.equal(host.commands.length, 1);

  host.resolveNext();
  assert.equal((await first).accepted, true);
});

test('desktop player adapter rejects duplicate in-flight runtime request IDs before host dispatch', async () => {
  const host = new DeferredNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  const first = adapter.dispatchRuntimeCommand(
    runtimeLoadCommand('request-runtime-duplicate'),
    privilegedContext('request-runtime-duplicate'),
  );
  await new Promise<void>((resolve) => setImmediate(resolve));
  const second = await adapter.dispatchRuntimeCommand(
    runtimeLoadCommand('request-runtime-duplicate'),
    privilegedContext('request-runtime-duplicate'),
  );

  assert.equal(second.accepted, false);
  assertErrorEvent(second.events, 'validation-failure');
  assert.equal(host.commands.length, 1);

  host.resolveNext();
  assert.equal((await first).accepted, true);
});

test('desktop player adapter rejects missing privileged runtime context without mutating active snapshot', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRuntimeCommand(
    runtimeLoadCommand('request-runtime-load'),
    privilegedContext('request-runtime-load'),
  );
  const activeSnapshot = adapter.getSnapshot();

  const rejected = await adapter.dispatchRuntimeCommand(runtimeLoadCommand('request-missing-context'), null);

  assert.equal(rejected.accepted, false);
  assertErrorEvent(rejected.events, 'validation-failure');
  assert.equal(host.commands.length, 1);
  assert.deepEqual(rejected.snapshot, activeSnapshot);
  assert.deepEqual(adapter.getSnapshot(), activeSnapshot);
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

test('desktop player adapter rejects a malformed returned event batch atomically', async () => {
  for (const dispatchKind of ['renderer', 'runtime'] as const) {
    const host = new FakeNativePlayerHost();
    const adapter = new DesktopPlayerAdapter(host);
    await adapter.dispatchRendererIntent(loadEnvelope(`request-${dispatchKind}-load`));
    const before = adapter.getSnapshot();
    host.executeResult = {
      ok: true,
      events: [
        {
          type: 'time.updated',
          requestId: before.requestId,
          positionMs: 42_000,
          durationMs: 120_000,
        },
        {
          type: 'time.updated',
          requestId: before.requestId,
          positionMs: -1,
          durationMs: 120_000,
        },
      ] as unknown as NativePlayerHostEvent[],
    };

    const result =
      dispatchKind === 'renderer'
        ? await adapter.dispatchRendererIntent({
            intent: 'player.setVolume',
            requestId: `request-${dispatchKind}-volume`,
            payload: { volume: 0.25 },
          })
        : await adapter.dispatchRuntimeCommand({
            command: 'volume.set',
            requestId: `request-${dispatchKind}-volume`,
            payload: { volume: 0.25 },
          });

    assert.equal(result.accepted, true);
    assert.deepEqual(result.snapshot, before);
    assert.deepEqual(adapter.getSnapshot(), before);
    assert.equal(result.events.filter((event) => event.event === 'error').length, 1);
    assert.equal(result.events.filter((event) => event.event === 'time.updated').length, 0);
    assert.equal(
      result.events.filter((event) => event.event === 'command.settled' && !event.ok).length,
      1,
    );
    assert.equal(
      result.events.some((event) => event.event === 'command.settled' && event.ok),
      false,
    );
    assertErrorEvent(result.events, 'validation-failure');
    assertNoForbiddenKeys(result);
  }
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
  const diagnostics = new DiagnosticEventStore({ clock: () => 3_000, idGenerator: () => 'adapter-host-failure' });
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
  const adapter = new DesktopPlayerAdapter(host, { diagnosticEventStore: diagnostics });

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
  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 0);
  assert.equal(diagnostics.getRecords().some((record) => record.category === 'playback'), true);
  assertTextAbsent(diagnostics.getRecords(), 'RAW_NATIVE_HANDLE');
});

test('desktop player adapter shared diagnostics summary counts one helper crash incident', async () => {
  const host = new FakeNativePlayerHost();
  const diagnostics = new DiagnosticEventStore({ clock: () => 4_000, idGenerator: () => 'adapter-shared-crash' });
  host.executeResult = {
    ok: false,
    error: {
      code: 'PLAYER_HELPER_EXITED',
      category: 'helper-failure',
      message: 'raw helper close detail',
      recoverable: true,
      retryable: true,
    },
  };
  diagnostics.record({
    surface: 'native-host-process',
    category: 'helper-crash',
    severity: 'error',
    status: 'failed',
    operation: 'helper.command',
    message: 'Player helper lifecycle failure observed.',
    requestId: 'request-shared-crash',
    result: 'failure',
    context: { code: 'PLAYER_HELPER_EXITED' },
  });
  const adapter = new DesktopPlayerAdapter(host, { diagnosticEventStore: diagnostics });

  const result = await adapter.dispatchRendererIntent(loadEnvelope('request-shared-crash'));

  assertErrorEvent(result.events, 'helper-failure');
  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
  assert.equal(diagnostics.getCrashRecoverySummary().events.filter((event) => event.category === 'helper-crash').length, 1);
  assert.equal(diagnostics.getRecords().filter((event) => event.category === 'playback').length, 1);
  assertTextAbsent(diagnostics.getRecords(), 'raw helper close detail');
});

test('desktop player adapter shared diagnostics summary counts one unscoped lifecycle crash incident', async () => {
  const host = new LifecycleFakeNativePlayerHost();
  const diagnostics = new DiagnosticEventStore({ clock: () => 6_000, idGenerator: () => 'adapter-shared-lifecycle' });
  const adapter = new DesktopPlayerAdapter(host, { diagnosticEventStore: diagnostics });
  await adapter.dispatchRendererIntent(loadEnvelope('request-shared-lifecycle'));
  diagnostics.record({
    surface: 'native-host-process',
    category: 'helper-crash',
    severity: 'warning',
    status: 'observed',
    operation: 'helper.lifecycle',
    message: 'Player helper lifecycle failure observed.',
    result: 'ignored',
    context: { code: 'PLAYER_HELPER_EXITED' },
  });

  host.emitLifecycleFailure({
    requestId: null,
    error: {
      code: 'PLAYER_HELPER_EXITED',
      category: 'helper-failure',
      message: 'raw idle close detail',
      recoverable: true,
      retryable: true,
    },
  });

  assert.equal(diagnostics.getCrashRecoverySummary().helperCrashCount, 1);
  assert.equal(diagnostics.getCrashRecoverySummary().events.filter((event) => event.category === 'helper-crash').length, 2);
  assert.equal(adapter.getSnapshot().requestId, 'request-shared-lifecycle');
  assert.equal(adapter.getSnapshot().lastError?.requestId, 'request-shared-lifecycle');
  assertTextAbsent(diagnostics.getRecords(), 'raw idle close detail');
});

test('desktop player adapter shared diagnostics summary counts one cleanup incident', async () => {
  const host = new FakeNativePlayerHost();
  const diagnostics = new DiagnosticEventStore({ clock: () => 5_000, idGenerator: () => 'adapter-shared-cleanup' });
  host.cleanupError = new Error('nativeHandle=shared-cleanup-secret');
  diagnostics.record({
    surface: 'native-host-process',
    category: 'cleanup',
    severity: 'error',
    status: 'failed',
    operation: 'helper.cleanup',
    message: 'Player helper cleanup failed.',
    requestId: 'request-shared-cleanup',
    result: 'failure',
    context: { code: 'PLAYER_CLEANUP_FAILED' },
  });
  const adapter = new DesktopPlayerAdapter(host, { diagnosticEventStore: diagnostics });
  await adapter.dispatchRendererIntent(loadEnvelope('request-shared-cleanup'));

  const result = await adapter.cleanup();

  assert.equal(result.accepted, false);
  assert.equal(diagnostics.getCrashRecoverySummary().cleanupFailureCount, 1);
  assert.equal(diagnostics.getCrashRecoverySummary().events.filter((event) => event.category === 'cleanup').length, 2);
  assertTextAbsent(diagnostics.getRecords(), 'shared-cleanup-secret');
});

test('desktop player adapter validates audio and subtitle track selection commands against snapshot tracks', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);

  // 1. Dispatch selectAudio when no tracks exist -> expect validation failure
  const result1 = await adapter.dispatchRendererIntent({
    intent: 'player.selectAudio',
    requestId: 'sel-aud-invalid',
    payload: { trackId: 'audio-ui-1', snapshotRequestId: 'missing-load' },
  } as RendererIntentEnvelope<unknown>);
  assert.equal(host.commands.length, 0);
  assertErrorEvent(result1.events, 'stale-request');

  // 2. Load media to populate tracks
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
    ],
  };
  await adapter.dispatchRendererIntent(loadEnvelope('request-load-1'));

  // 3. Dispatch selectAudio with valid trackId -> expect success (host command executed)
  const result2 = await adapter.dispatchRendererIntent({
    intent: 'player.selectAudio',
    requestId: 'sel-aud-valid',
    payload: { trackId: 'audio-ui-1', snapshotRequestId: 'request-load-1' },
  } as RendererIntentEnvelope<unknown>);
  assert.equal(result2.accepted, true);
  assert.equal(host.commands.length, 2); // load, track.audio.select
  assert.equal(host.commands[1]?.command, 'track.audio.select');

  // 4. Dispatch selectSubtitle with invalid trackId -> expect validation failure
  const result3 = await adapter.dispatchRendererIntent({
    intent: 'player.selectSubtitle',
    requestId: 'sel-sub-invalid',
    payload: { trackId: 'subtitle-ui-invalid', snapshotRequestId: 'request-load-1' },
  } as RendererIntentEnvelope<unknown>);
  assertErrorEvent(result3.events, 'validation-failure');

  // 5. Dispatch selectSubtitle with null (turn off) -> expect success
  const result4 = await adapter.dispatchRendererIntent({
    intent: 'player.selectSubtitle',
    requestId: 'sel-sub-null',
    payload: { trackId: null, snapshotRequestId: 'request-load-1' },
  } as RendererIntentEnvelope<unknown>);
  assert.equal(result4.accepted, true);
  assert.equal(host.commands[2]?.command, 'track.subtitle.select');
});

test('desktop player adapter rejects stale snapshot track selection commands before host dispatch', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  host.executeResult = {
    ok: true,
    events: [
      {
        type: 'media.loaded',
        requestId: 'request-current-load',
        media,
        durationMs: 120_000,
        tracks: [audioTrack, subtitleTrack],
      },
    ],
  };
  await adapter.dispatchRendererIntent(loadEnvelope('request-current-load'));

  const result = await adapter.dispatchRendererIntent({
    intent: 'player.selectAudio',
    requestId: 'request-stale-select',
    payload: { trackId: 'audio-ui-1', snapshotRequestId: 'request-previous-load' },
  } as RendererIntentEnvelope<unknown>);

  assert.equal(result.accepted, false);
  assert.equal(host.commands.length, 1);
  assert.equal(result.events[0]?.event, 'error');
  assert.equal(result.events[0]?.error.category, 'stale-request');
  assertTextAbsent(result.events, 'request-previous-load');
});

test('desktop player adapter accepts validated quality host events', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-quality-load'));

  const events = adapter.handleHostEvent({
    type: 'quality.changed',
    requestId: 'request-quality-load',
    quality: {
      mode: 'direct-play',
      videoCodec: 'h264',
      audioCodec: 'aac',
      sourceDynamicRange: 'hdr10',
      outputDynamicRangeStatus: 'unproven',
    },
  } satisfies NativePlayerHostEvent);

  assert.equal(events.some((event) => event.event === 'quality.changed'), true);
  assert.equal(adapter.getSnapshot().quality.videoCodec, 'h264');
  assert.equal(adapter.getSnapshot().quality.outputDynamicRangeStatus, 'unproven');
  assertNoForbiddenKeys(events);
});

test('desktop player adapter snapshots clone playback quality state', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-quality-clone-load'));
  adapter.handleHostEvent({
    type: 'quality.changed',
    requestId: 'request-quality-clone-load',
    quality: {
      mode: 'direct-play',
      sourceDynamicRange: 'hlg',
      outputDynamicRangeStatus: 'unknown',
    },
  } satisfies NativePlayerHostEvent);

  const snapshot = adapter.getSnapshot();
  snapshot.quality.sourceDynamicRange = 'sdr';

  assert.equal(adapter.getSnapshot().quality.sourceDynamicRange, 'hlg');
});

test('desktop player adapter receives async host events through host event callback', async () => {
  const host = new FakeNativePlayerHost();
  const emittedEvents: PlayerEvent[] = [];
  const adapter = new DesktopPlayerAdapter(host, {
    onEvents: (events) => emittedEvents.push(...events),
  });
  await adapter.dispatchRendererIntent(loadEnvelope('request-async-load'));

  host.emitEvent({
    type: 'time.updated',
    requestId: 'request-async-load',
    positionMs: 32_000,
    durationMs: 120_000,
  });

  assert.equal(adapter.getSnapshot().positionMs, 32_000);
  assert.equal(emittedEvents.some((event) => event.event === 'time.updated'), true);
  assertNoForbiddenKeys(emittedEvents);
});

test('desktop player adapter keeps media-option events under active playback request custody', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  host.executeResult = {
    ok: true,
    events: [
      {
        type: 'media.loaded',
        requestId: 'request-playback-load',
        media,
        durationMs: 120_000,
        tracks: [
          audioTrack,
          { ...audioTrack, id: 'audio-ui-2', label: 'French', selected: false },
          subtitleTrack,
        ],
      },
    ],
  };
  await adapter.dispatchRendererIntent(loadEnvelope('request-playback-load'));
  host.executeResult = { ok: true };
  await adapter.dispatchRendererIntent({
    intent: 'player.selectAudio',
    requestId: 'request-select-command',
    payload: { trackId: 'audio-ui-2', snapshotRequestId: 'request-playback-load' },
  } as RendererIntentEnvelope<unknown>);

  const acceptedEvents = adapter.handleHostEvent({
    type: 'track.selection.changed',
    requestId: 'request-playback-load',
    audioTrackId: 'audio-ui-2',
    subtitleTrackId: null,
    videoTrackId: null,
  } satisfies NativePlayerHostEvent);
  const staleEvents = adapter.handleHostEvent({
    type: 'quality.changed',
    requestId: 'request-select-command',
    quality: { mode: 'direct-play', sourceDynamicRange: 'unknown', outputDynamicRangeStatus: 'unproven' },
  } satisfies NativePlayerHostEvent);

  assert.equal(adapter.getSnapshot().selectedAudioTrackId, 'audio-ui-2');
  assert.equal(adapter.getSnapshot().tracks.find((track) => track.id === 'audio-ui-1')?.selected, false);
  assert.equal(adapter.getSnapshot().tracks.find((track) => track.id === 'audio-ui-2')?.selected, true);
  assert.equal(acceptedEvents.some((event) => event.event === 'track.selection.changed'), true);
  assert.equal(staleEvents[0]?.event, 'warning');
  assertNoForbiddenKeys([acceptedEvents, staleEvents]);
});

test('desktop player adapter updates volume and mute snapshot after successful host commands', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  await adapter.dispatchRendererIntent(loadEnvelope('request-volume-load'));

  const volume = await adapter.dispatchRendererIntent({
    intent: 'player.setVolume',
    requestId: 'request-volume-set',
    payload: { volume: 0.25 },
  } as RendererIntentEnvelope<unknown>);
  const mute = await adapter.dispatchRendererIntent({
    intent: 'player.setMute',
    requestId: 'request-mute-set',
    payload: { muted: true },
  } as RendererIntentEnvelope<unknown>);

  assert.equal(volume.snapshot.volume, 0.25);
  assert.equal(mute.snapshot.muted, true);
  assert.equal(adapter.getSnapshot().volume, 0.25);
  assert.equal(adapter.getSnapshot().muted, true);
  assert.equal(volume.events.some((event) => event.event === 'state.changed'), true);
  assert.equal(mute.events.some((event) => event.event === 'state.changed'), true);
});

test('desktop player adapter rejects invalid track IDs without echoing raw IDs', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  host.executeResult = {
    ok: true,
    events: [
      {
        type: 'media.loaded',
        requestId: 'request-redacted-track-load',
        media,
        durationMs: 120_000,
        tracks: [audioTrack, subtitleTrack],
      },
    ],
  };
  await adapter.dispatchRendererIntent(loadEnvelope('request-redacted-track-load'));
  const rawTrackId = 'raw-rejected-track-id';

  const result = await adapter.dispatchRendererIntent({
    intent: 'player.selectSubtitle',
    requestId: 'request-redacted-track',
    payload: { trackId: rawTrackId, snapshotRequestId: 'request-redacted-track-load' },
  } as RendererIntentEnvelope<unknown>);

  assert.equal(result.accepted, false);
  assertErrorEvent(result.events, 'validation-failure');
  assertTextAbsent(result.events, rawTrackId);
  assertTextAbsent(result.snapshot, rawTrackId);
  assertNoForbiddenKeys(result);
});

test('desktop player adapter rejects malformed privileged track maps before helper dispatch', async () => {
  const host = new FakeNativePlayerHost();
  const adapter = new DesktopPlayerAdapter(host);
  const context = privilegedContext('request-malformed-track-map');
  const malformedContext = {
    privatePlayback: {
      ...context.privatePlayback,
      setup: {
        ...context.privatePlayback.setup,
        trackMap: { audio: [], subtitle: [] },
      },
    },
  } as unknown as PrivilegedPlaybackDispatchContext;

  const result = await adapter.dispatchRuntimeCommand(
    runtimeLoadCommand('request-malformed-track-map'),
    malformedContext,
  );

  assert.equal(result.accepted, false);
  assert.equal(host.commands.length, 0);
  assertErrorEvent(result.events, 'validation-failure');
  assertTextAbsent(result, 'trackMap');
});

test('desktop player adapter rejects unsafe privileged track-map details before helper dispatch', async () => {
  const cases: Array<{
    name: string;
    setup: unknown;
    absentText: string;
  }> = [
    {
      name: 'extra private-looking field',
      absentText: 'rawMediaUrl',
      setup: {
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: {
          video: [],
          audio: [{ publicTrackId: 'audio-public', privateTrackId: 'audio-private', rawMediaUrl: 'secret' }],
          subtitle: [],
        },
      },
    },
    {
      name: 'duplicate public id',
      absentText: 'duplicated-public-id',
      setup: {
        selectedTrackIds: { video: null, audio: null, subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
        trackMap: {
          video: [],
          audio: [{ publicTrackId: 'duplicated-public-id', privateTrackId: 'audio-private' }],
          subtitle: [{ publicTrackId: 'duplicated-public-id', privateTrackId: 'subtitle-private' }],
        },
      },
    },
    {
      name: 'selected public id missing from map',
      absentText: 'selected-public-id',
      setup: {
        selectedTrackIds: { video: null, audio: 'selected-public-id', subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: 'selected-private-id', subtitle: null },
        trackMap: { video: [], audio: [], subtitle: [] },
      },
    },
    {
      name: 'selected private id does not match map',
      absentText: 'wrong-private-id',
      setup: {
        selectedTrackIds: { video: null, audio: 'selected-public-id', subtitle: null },
        selectedPrivateTrackIds: { video: null, audio: 'wrong-private-id', subtitle: null },
        trackMap: {
          video: [],
          audio: [{ publicTrackId: 'selected-public-id', privateTrackId: 'expected-private-id' }],
          subtitle: [],
        },
      },
    },
  ];

  for (const [index, testCase] of cases.entries()) {
    const host = new FakeNativePlayerHost();
    const adapter = new DesktopPlayerAdapter(host);
    const requestId = `request-unsafe-track-map-${index}`;
    const context = privilegedContext(requestId);
    const malformedContext = {
      privatePlayback: {
        ...context.privatePlayback,
        setup: {
          ...context.privatePlayback.setup,
          ...(testCase.setup as Record<string, unknown>),
        },
      },
    } as unknown as PrivilegedPlaybackDispatchContext;

    const result = await adapter.dispatchRuntimeCommand(runtimeLoadCommand(requestId), malformedContext);

    assert.equal(result.accepted, false, testCase.name);
    assert.equal(host.commands.length, 0, testCase.name);
    assertErrorEvent(result.events, 'validation-failure');
    assertTextAbsent(result, testCase.absentText);
    assertNoForbiddenKeys(result);
  }
});
