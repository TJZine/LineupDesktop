import assert from 'node:assert/strict';
import test from 'node:test';

import type { PlayerEvent, PlayerIpcResult, PlayerSnapshot } from '../../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createPlayerOverlayController, type PlayerOverlayTimerHost } from '../../renderer/playerOverlayController.js';
import { subscribePlayerBridge } from '../../renderer/playerBridgeSubscription.js';
import { createPlayerOverlayState } from '../../renderer/overlays.js';
import { createPlayerOverlayView } from '../../renderer/overlayViewModels.js';
import { createEmptyPlayerSnapshot, type PlayerOverlayPresentationSource } from '../../renderer/playerOverlayPresentation.js';

test('OSD, mini-guide, and number timers use exact frozen boundaries and clean up', async () => {
  const harness = createHarness(playingSnapshot());
  assert.equal(harness.controller.requestOsd(), true);
  assert.equal(harness.state().activeOverlayId, 'playerOsd');
  harness.timers.advance(2_999);
  assert.equal(harness.state().activeOverlayId, 'playerOsd');
  harness.timers.advance(1);
  assert.equal(harness.state().activeOverlayId, null);

  harness.controller.requestMiniGuide();
  harness.timers.advance(7_999);
  assert.equal(harness.state().activeOverlayId, 'miniGuide');
  harness.timers.advance(1);
  assert.equal(harness.state().activeOverlayId, null);

  harness.controller.handleInput('digit9');
  harness.timers.advance(1_999);
  assert.equal(harness.state().channelNumberStatus, 'editing');
  harness.timers.advance(1);
  assert.equal(harness.state().channelNumberStatus, 'error');
  harness.timers.advance(2_000);
  assert.equal(harness.state().activeOverlayId, null);
});

test('OSD requests preserve higher overlay owners, including pending playback options', async () => {
  const nowPlaying = createHarness(playingSnapshot());
  nowPlaying.controller.requestNowPlaying();
  const nowPlayingState = nowPlaying.state();
  nowPlaying.controller.requestOsd();
  assert.deepEqual(nowPlaying.state(), nowPlayingState);

  const miniGuide = createHarness(playingSnapshot());
  miniGuide.controller.requestMiniGuide();
  const miniGuideState = miniGuide.state();
  miniGuide.controller.requestOsd();
  assert.deepEqual(miniGuide.state(), miniGuideState);

  const options = createHarness(playingSnapshot());
  options.controller.requestOsd();
  options.controller.openOptions('audio');
  const optionsState = options.state();
  options.controller.requestOsd();
  assert.deepEqual(options.state(), optionsState);

  const pendingOptions = createHarness(playingSnapshot());
  pendingOptions.controller.requestOsd();
  pendingOptions.controller.openOptions('audio');
  await pendingOptions.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  const pendingOptionsState = pendingOptions.state();
  pendingOptions.controller.requestOsd();
  assert.deepEqual(pendingOptions.state(), pendingOptionsState);
});

test('Space selects play/pause, suppresses duplicates, and settles by command request', async () => {
  const dispatches: string[] = [];
  const harness = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      dispatches.push(envelope.intent);
      return accepted(envelope.requestId);
    },
  });
  harness.controller.handleInput('space');
  harness.controller.handleInput('space');
  assert.deepEqual(dispatches, ['player.pause']);
  harness.controller.handlePlayerEvent({ event: 'command.settled', requestId: 'unmatched', command: 'pause', ok: true });
  harness.controller.handlePlayerEvent({ event: 'command.settled', requestId: 'renderer-pause-1', command: 'pause', ok: true });
  harness.controller.handleInput('space');
  assert.deepEqual(dispatches, ['player.pause', 'player.pause']);

  harness.setSnapshot({ ...playingSnapshot(), status: 'paused', playing: false });
  harness.controller.handlePlayerEvent({ event: 'command.settled', requestId: 'renderer-pause-2', command: 'pause', ok: true });
  harness.controller.handleInput('space');
  assert.equal(dispatches.at(-1), 'player.play');
});

test('late rejected Space dispatch cannot clear a newer pending command after route invalidation', async () => {
  const first = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['dispatch']>>>();
  const requestIds: string[] = [];
  const harness = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      requestIds.push(envelope.requestId);
      return requestIds.length === 1 ? first.promise : accepted(envelope.requestId);
    },
  });

  harness.controller.handleInput('space');
  harness.controller.routeLeave();
  harness.controller.handleInput('space');
  first.reject(new Error('late private failure'));
  await flushPromiseQueue();

  harness.controller.handleInput('space');
  assert.equal(requestIds.length, 2);
  harness.controller.handlePlayerEvent({
    event: 'command.settled', requestId: requestIds[1] ?? '', command: 'pause', ok: true,
  });
  harness.controller.handleInput('space');
  assert.equal(requestIds.length, 3);
});

test('bridge request timeouts clear tune and command ownership through normal failure paths', async () => {
  const never = new Promise<never>(() => undefined);
  let dispatchCount = 0;
  const command = createHarness(playingSnapshot(), {
    dispatch: async () => {
      dispatchCount += 1;
      return never;
    },
  });
  command.controller.handleInput('space');
  command.timers.advance(29_999);
  await flushPromiseQueue();
  assert.deepEqual(command.diagnostics, []);
  command.timers.advance(1);
  await flushPromiseQueue();
  assert.deepEqual(command.diagnostics, ['Player command timed out.']);
  command.controller.handleInput('space');
  assert.equal(dispatchCount, 2);

  const track = createHarness(playingSnapshot(), {
    dispatch: async () => never,
  });
  track.controller.requestOsd();
  track.controller.openOptions('audio');
  const trackRequest = track.controller.selectTrack(
    'audio',
    'audio-alt',
    'overlay-audio-track-audio-alt',
  );
  track.timers.advance(30_000);
  await trackRequest;
  assert.equal(track.state().pendingTrackFocusId, null);
  assert.equal(track.state().playbackOptionsError, 'Track selection timed out.');
  assert.equal(track.focus.at(-1), 'overlay-audio-track-audio-alt');

  const tune = createHarness(playingSnapshot(), {
    tuneChannel: async () => never,
  });
  tune.controller.requestMiniGuide();
  const tuneRequest = tune.controller.tune('two', 'miniGuide');
  tune.timers.advance(30_000);
  await tuneRequest;
  assert.equal(tune.state().pendingTuneChannelId, null);
  assert.equal(tune.state().transitionChannelId, null);
  assert.equal(tune.state().miniGuideError, 'Channel tune timed out.');
});

test('accepted commands retain a settlement deadline and release it on matching settlement', async () => {
  let unresolvedDispatches = 0;
  const unresolved = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      unresolvedDispatches += 1;
      return accepted(envelope.requestId);
    },
  });
  unresolved.controller.handleInput('space');
  await flushPromiseQueue();
  unresolved.timers.advance(29_999);
  assert.deepEqual(unresolved.diagnostics, []);
  unresolved.timers.advance(1);
  await flushPromiseQueue();
  assert.deepEqual(unresolved.diagnostics, ['Player command timed out.']);
  unresolved.controller.handleInput('space');
  assert.equal(unresolvedDispatches, 2);

  let settledDispatches = 0;
  const settled = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      settledDispatches += 1;
      return accepted(envelope.requestId);
    },
  });
  settled.controller.handleInput('space');
  await flushPromiseQueue();
  settled.controller.handlePlayerEvent({
    event: 'command.settled',
    requestId: 'renderer-pause-1',
    command: 'pause',
    ok: true,
  });
  settled.timers.advance(30_000);
  assert.deepEqual(settled.diagnostics, []);
  settled.controller.handleInput('space');
  assert.equal(settledDispatches, 2);

  const track = createHarness(playingSnapshot());
  track.controller.requestOsd();
  track.controller.openOptions('audio');
  await track.controller.selectTrack(
    'audio',
    'audio-alt',
    'overlay-audio-track-audio-alt',
  );
  track.timers.advance(30_000);
  assert.equal(track.state().pendingTrackFocusId, null);
  assert.equal(track.state().playbackOptionsError, 'Track selection timed out.');
});

test('route leave and dispose cancel owned bridge deadlines without late failures', async () => {
  const never = new Promise<never>(() => undefined);
  const routeLeave = createHarness(playingSnapshot(), {
    dispatch: async () => never,
  });
  routeLeave.controller.handleInput('space');
  routeLeave.controller.routeLeave();
  await flushPromiseQueue();
  routeLeave.timers.advance(30_000);
  assert.deepEqual(routeLeave.diagnostics, []);

  const dispose = createHarness(playingSnapshot(), {
    dispatch: async () => never,
  });
  dispose.controller.handleInput('space');
  dispose.controller.dispose();
  await flushPromiseQueue();
  dispose.timers.advance(30_000);
  assert.deepEqual(dispose.diagnostics, []);
  assert.equal(dispose.controller.handleInput('space'), false);
});

test('different tune target supersedes stale completion and only current success reconciles', async () => {
  const tunes: Array<Deferred<{ ok: true; value: never; requestId: string }>> = [];
  let statusRefresh = 0;
  let guideRefresh = 0;
  const harness = createHarness(playingSnapshot(), {
    tuneChannel: async () => {
      const pending = deferred<{ ok: true; value: never; requestId: string }>();
      tunes.push(pending);
      return pending.promise;
    },
    refreshChannelStatus: async () => { statusRefresh += 1; },
    refreshGuidePresentation: async () => { guideRefresh += 1; },
  });
  harness.controller.requestMiniGuide();
  const first = harness.controller.tune('one', 'miniGuide');
  const second = harness.controller.tune('two', 'miniGuide');
  harness.timers.advance(175);
  assert.equal(harness.state().transitionVisible, true);
  tunes[0]?.resolve({ ok: true, value: undefined as never, requestId: 'first' });
  await first;
  assert.equal(statusRefresh, 0);
  tunes[1]?.resolve({ ok: true, value: undefined as never, requestId: 'second' });
  await second;
  assert.equal(statusRefresh, 1);
  assert.equal(guideRefresh, 1);
  assert.equal(harness.state().lastTuneChannelId, 'two');
});

test('track selection waits for matching settlement and keeps exact focus on local failure', async () => {
  const harness = createHarness(playingSnapshot());
  harness.controller.requestOsd();
  harness.controller.openOptions('audio');
  await harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  assert.equal(harness.state().pendingTrackFocusId, 'overlay-audio-track-audio-alt');

  harness.controller.handlePlayerEvent({
    event: 'track.selection.changed', requestId: 'playback-1', audioTrackId: 'audio-alt', subtitleTrackId: null, videoTrackId: null,
  });
  assert.equal(harness.state().activeOverlayId, 'playbackOptions');
  harness.controller.handlePlayerEvent({ event: 'command.settled', requestId: 'renderer-select-audio-1', command: 'track.audio.select', ok: false, error: safeError() });
  assert.equal(harness.state().activeOverlayId, 'playbackOptions');
  assert.equal(harness.state().playbackOptionsFocusId, 'overlay-audio-track-audio-alt');
  assert.equal(harness.state().playbackOptionsError, 'Safe failure.');
});

test('late rejected track dispatch cannot fail a newer pending selection after route invalidation', async () => {
  const first = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['dispatch']>>>();
  const requestIds: string[] = [];
  const harness = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      requestIds.push(envelope.requestId);
      return requestIds.length === 1 ? first.promise : accepted(envelope.requestId);
    },
  });

  harness.controller.requestOsd();
  harness.controller.openOptions('audio');
  const staleSelection = harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  harness.controller.routeLeave();
  harness.controller.requestOsd();
  harness.controller.openOptions('audio');
  await harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');

  first.reject(new Error('late private failure'));
  await staleSelection;
  assert.equal(harness.state().pendingTrackFocusId, 'overlay-audio-track-audio-alt');
  assert.equal(harness.state().playbackOptionsError, null);
  await harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  assert.equal(requestIds.length, 2);

  harness.controller.handlePlayerEvent({
    event: 'command.settled', requestId: requestIds[1] ?? '', command: 'track.audio.select', ok: true,
  });
  assert.equal(harness.state().pendingTrackFocusId, null);
});

test('authoritative terminal state and route/dispose invalidate overlays and late work', async () => {
  const tune = deferred<{ ok: true; value: never; requestId: string }>();
  let refreshes = 0;
  const harness = createHarness(playingSnapshot(), {
    tuneChannel: async () => tune.promise,
    refreshChannelStatus: async () => { refreshes += 1; },
  });
  harness.controller.requestMiniGuide();
  const pending = harness.controller.tune('one', 'miniGuide');
  harness.controller.routeLeave();
  tune.resolve({ ok: true, value: undefined as never, requestId: 'late' });
  await pending;
  assert.equal(refreshes, 0);
  assert.equal(harness.state().activeOverlayId, null);

  harness.controller.reconcileSnapshot({ ...playingSnapshot(), status: 'error', playing: false, lastError: safeError() }, true);
  assert.equal(harness.state().activeOverlayId, null);
  harness.controller.dispose();
  assert.equal(harness.controller.handleInput('up'), false);
});

test('all Space status/playing pairs dispatch only the three frozen consistent intents', () => {
  const statuses: PlayerSnapshot['status'][] = [
    'idle', 'loading', 'ready', 'playing', 'paused', 'buffering', 'seeking', 'stalled', 'ended', 'error', 'destroyed',
  ];
  for (const status of statuses) {
    for (const playing of [false, true]) {
      const intents: string[] = [];
      const harness = createHarness({ ...playingSnapshot(), status, playing }, {
        dispatch: async (envelope) => {
          intents.push(envelope.intent);
          return accepted(envelope.requestId);
        },
      });
      assert.equal(harness.controller.handleInput('space'), true);
      const expected = status === 'playing' && playing
        ? ['player.pause']
        : (status === 'ready' || status === 'paused') && !playing
          ? ['player.play']
          : [];
      assert.deepEqual(intents, expected, `${status}/${String(playing)}`);
      const inconsistent = (status === 'playing' && !playing) ||
        ((status === 'ready' || status === 'paused') && playing);
      assert.equal(harness.diagnostics.length, inconsistent ? 1 : 0, `${status}/${String(playing)} diagnostics`);
    }
  }
});

test('playback request replacement invalidates Space and track generations without stale UI', async () => {
  const dispatches: string[] = [];
  const harness = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      dispatches.push(envelope.requestId);
      return accepted(envelope.requestId);
    },
  });
  harness.controller.requestOsd();
  harness.controller.openOptions('audio');
  await harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  assert.equal(harness.state().pendingTrackFocusId, 'overlay-audio-track-audio-alt');

  harness.setSnapshot({ ...playingSnapshot(), requestId: 'playback-2' });
  assert.equal(harness.state().activeOverlayId, null);
  assert.equal(harness.state().pendingTrackFocusId, null);
  harness.controller.handlePlayerEvent({
    event: 'command.settled', requestId: dispatches[0] ?? '', command: 'track.audio.select', ok: false, error: safeError(),
  });
  assert.equal(harness.state().playbackOptionsError, null);

  harness.controller.handleInput('space');
  harness.setSnapshot({ ...playingSnapshot(), requestId: 'playback-3' });
  harness.controller.handlePlayerEvent({ event: 'command.settled', requestId: dispatches[1] ?? '', command: 'pause', ok: true });
  harness.controller.handleInput('space');
  assert.equal(dispatches.length, 3);
});

test('subtitle Off completion restores native surface when its invoking OSD control disappears', async () => {
  const selectedSubtitle = {
    ...playingSnapshot(),
    selectedAudioTrackId: 'audio-main',
    selectedSubtitleTrackId: 'subtitle-one',
    tracks: [
      { id: 'audio-main', kind: 'audio' as const, label: 'Main', selected: true, available: true },
      { id: 'subtitle-one', kind: 'subtitle' as const, label: 'English', selected: true, available: true },
    ],
  };
  const harness = createHarness(selectedSubtitle);
  harness.controller.requestOsd();
  harness.controller.openOptions('subtitle');
  await harness.controller.selectTrack('subtitle', null, 'overlay-subtitle-track-off');
  harness.setSnapshot({
    ...selectedSubtitle,
    selectedSubtitleTrackId: null,
    tracks: selectedSubtitle.tracks.filter((track) => track.kind === 'audio'),
  });
  harness.controller.handlePlayerEvent({
    event: 'command.settled', requestId: 'renderer-select-subtitle-1', command: 'track.subtitle.select', ok: true,
  });
  assert.equal(harness.state().activeOverlayId, null);
  assert.equal(harness.focus.at(-1), null);
});

test('terminal states refuse Info and mini-guide while recovery success suppresses the old error owner', () => {
  const harness = createHarness({ ...playingSnapshot(), status: 'error', playing: false, lastError: safeError() });
  assert.equal(harness.controller.requestNowPlaying(), true);
  assert.equal(harness.controller.requestMiniGuide(), true);
  assert.equal(harness.state().activeOverlayId, null);

  harness.controller.retry();
  assert.equal(harness.state().retryTransitionActive, true);
  assert.equal(createPlayerOverlayView(harness.state(), presentation(harness.snapshot())).visibleOverlays.playerError, false);
  harness.setSnapshot({ ...playingSnapshot(), status: 'loading', playing: false, lastError: safeError() });
  assert.equal(harness.state().retryTransitionActive, false);
  harness.setSnapshot({ ...playingSnapshot(), status: 'ready', playing: false, lastError: null });
  assert.equal(harness.state().transitionChannelId, null);
  assert.equal(harness.state().retryTransitionActive, false);
});

test('failed, thrown, and superseded tune results never start stale reconciliation', async () => {
  let refreshes = 0;
  const rejected = createHarness(playingSnapshot(), {
    tuneChannel: async () => ({
      ok: false,
      requestId: 'reject',
      error: { code: 'TUNE_FAILED', message: 'Safe failure.', retryable: true, recoverable: true, operation: 'player.tuneChannel' },
    }),
    refreshChannelStatus: async () => { refreshes += 1; },
  });
  rejected.controller.requestMiniGuide();
  await rejected.controller.tune('one', 'miniGuide');
  assert.equal(refreshes, 0);
  assert.equal(rejected.state().activeOverlayId, 'miniGuide');
  assert.equal(rejected.state().miniGuideError, 'Safe failure.');

  const thrown = createHarness(playingSnapshot(), {
    tuneChannel: async () => { throw new Error('private failure'); },
    refreshChannelStatus: async () => { refreshes += 1; },
  });
  thrown.controller.requestMiniGuide();
  await thrown.controller.tune('one', 'miniGuide');
  assert.equal(refreshes, 0);
  assert.equal(thrown.state().miniGuideError, 'Channel tune failed.');
});

test('real incremental player subscription events do not extend an open OSD deadline', () => {
  const harness = createHarness(playingSnapshot());
  let emit = (_event: PlayerEvent): void => undefined;
  const subscription = subscribePlayerBridge({
    player: {
      onEvent: (listener) => { emit = listener; return () => undefined; },
      getSnapshot: async () => ({ ok: true, requestId: 'snapshot', value: harness.snapshot() }),
    } as LineupDesktopPreloadApi['player'],
    diagnostics: {
      recordRendererEvent: async () => ({ ok: true, requestId: 'diagnostic', value: undefined }),
      getSummary: async () => { throw new Error('unused'); },
      exportSupportBundle: async () => { throw new Error('unused'); },
    } as unknown as LineupDesktopPreloadApi['diagnostics'],
    getSnapshot: harness.snapshot,
    setSnapshot: harness.replaceSnapshot,
    onSnapshot: harness.controller.reconcileSnapshot,
    onEvent: harness.controller.handlePlayerEvent,
    render: () => undefined,
  });
  harness.controller.requestOsd();
  harness.timers.advance(1_000);
  emit({ event: 'time.updated', requestId: 'playback-1', positionMs: 100, durationMs: 1_000 });
  emit({ event: 'buffer.updated', requestId: 'playback-1', bufferedRanges: [{ startMs: 0, endMs: 500 }] });
  emit({ event: 'quality.changed', requestId: 'playback-1', quality: { mode: 'direct-play', sourceDynamicRange: 'sdr', outputDynamicRangeStatus: 'sdr' } });
  harness.timers.advance(1_999);
  assert.equal(harness.state().activeOverlayId, 'playerOsd');
  harness.timers.advance(1);
  assert.equal(harness.state().activeOverlayId, null);
  subscription.unsubscribe();
});

test('options retain custody through same-request load states and settle without reopening ineligible OSD', async () => {
  const harness = createHarness(playingSnapshot());
  harness.controller.requestOsd();
  harness.controller.openOptions('audio');
  await harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  harness.setSnapshot({ ...playingSnapshot(), status: 'buffering', playing: false });
  assert.equal(harness.state().activeOverlayId, 'playbackOptions');
  assert.equal(harness.state().pendingTrackFocusId, 'overlay-audio-track-audio-alt');
  harness.controller.handlePlayerEvent({
    event: 'command.settled', requestId: 'renderer-select-audio-1', command: 'track.audio.select', ok: true,
  });
  assert.equal(harness.state().activeOverlayId, null);
  assert.equal(harness.focus.at(-1), null);
});

test('explicit tracks.changed loss invalidates pending options during load-like status and late settlement is inert', async () => {
  const harness = createHarness(playingSnapshot());
  harness.controller.requestOsd();
  harness.controller.openOptions('audio');
  await harness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  harness.setSnapshot({ ...playingSnapshot(), status: 'buffering', playing: false, tracks: [] });
  assert.equal(harness.state().activeOverlayId, 'playbackOptions');
  assert.equal(harness.state().pendingTrackFocusId, 'overlay-audio-track-audio-alt');

  let emit = (_event: PlayerEvent): void => undefined;
  const subscription = subscribePlayerBridge({
    player: {
      onEvent: (listener) => { emit = listener; return () => undefined; },
      getSnapshot: async () => ({ ok: true, requestId: 'snapshot', value: harness.snapshot() }),
    } as LineupDesktopPreloadApi['player'],
    diagnostics: { recordRendererEvent: async () => ({ ok: true, value: undefined }) } as unknown as LineupDesktopPreloadApi['diagnostics'],
    getSnapshot: harness.snapshot,
    setSnapshot: harness.replaceSnapshot,
    onSnapshot: harness.controller.reconcileSnapshot,
    onEvent: harness.controller.handlePlayerEvent,
    render: () => undefined,
  });
  emit({
    event: 'tracks.changed', requestId: 'playback-1', tracks: [
      { id: 'audio-main', kind: 'audio', label: 'Main', selected: true, available: true },
      { id: 'audio-third', kind: 'audio', label: 'Third', selected: false, available: true },
    ],
  });
  assert.equal(harness.state().activeOverlayId, 'playbackOptions');
  assert.equal(harness.state().pendingTrackFocusId, null);
  assert.equal(harness.state().playbackOptionsError, 'Track is no longer available.');
  assert.equal(harness.state().playbackOptionsFocusId, 'overlay-audio-track-audio-main');
  assert.equal(harness.focus.at(-1), 'overlay-audio-track-audio-main');

  emit({ event: 'command.settled', requestId: 'renderer-select-audio-1', command: 'track.audio.select', ok: true });
  assert.equal(harness.state().activeOverlayId, 'playbackOptions');
  assert.equal(harness.state().playbackOptionsError, 'Track is no longer available.');
  subscription.unsubscribe();

  const fallback = createHarness(playingSnapshot());
  fallback.controller.requestOsd();
  fallback.controller.openOptions('audio');
  await fallback.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  fallback.setSnapshot({ ...playingSnapshot(), status: 'loading', playing: false, tracks: [] });
  let emitFallback = (_event: PlayerEvent): void => undefined;
  const fallbackSubscription = subscribePlayerBridge({
    player: {
      onEvent: (listener) => { emitFallback = listener; return () => undefined; },
      getSnapshot: async () => ({ ok: true, requestId: 'snapshot', value: fallback.snapshot() }),
    } as LineupDesktopPreloadApi['player'],
    diagnostics: { recordRendererEvent: async () => ({ ok: true, value: undefined }) } as unknown as LineupDesktopPreloadApi['diagnostics'],
    getSnapshot: fallback.snapshot,
    setSnapshot: fallback.replaceSnapshot,
    onSnapshot: fallback.controller.reconcileSnapshot,
    onEvent: fallback.controller.handlePlayerEvent,
    render: () => undefined,
  });
  emitFallback({ event: 'tracks.changed', requestId: 'playback-1', tracks: [] });
  assert.equal(fallback.state().activeOverlayId, null);
  assert.equal(fallback.focus.at(-1), null);
  emitFallback({ event: 'command.settled', requestId: 'renderer-select-audio-1', command: 'track.audio.select', ok: true });
  assert.equal(fallback.state().activeOverlayId, null);
  fallbackSubscription.unsubscribe();
});

test('Info retains custody across mini-guide and number tune success or failure', async () => {
  for (const invoker of ['miniGuide', 'number'] as const) {
    for (const outcome of ['success', 'failure'] as const) {
      const pending = deferred<Awaited<ReturnType<LineupDesktopPreloadApi['player']['tuneChannel']>>>();
      const harness = createHarness(playingSnapshot(), { tuneChannel: async () => pending.promise });
      if (invoker === 'miniGuide') harness.controller.requestMiniGuide();
      else harness.controller.handleInput('digit1');
      const tune = harness.controller.tune('one', invoker);
      harness.controller.requestNowPlaying();
      assert.equal(harness.state().activeOverlayId, 'nowPlaying', `${invoker}/${outcome} pending`);
      pending.resolve(outcome === 'success'
        ? { ok: true, value: undefined as never, requestId: `${invoker}-success` }
        : {
            ok: false, requestId: `${invoker}-failure`,
            error: { code: 'FAILED', message: 'Safe tune failure.', retryable: true, recoverable: true, operation: 'player.tuneChannel' },
          });
      await tune;
      assert.equal(harness.state().activeOverlayId, 'nowPlaying', `${invoker}/${outcome} settled`);
      assert.equal(harness.state().miniGuideError, null, `${invoker}/${outcome} mini error`);
      assert.equal(harness.state().channelNumberStatus, null, `${invoker}/${outcome} number state`);
      if (outcome === 'success') {
        assert.equal(harness.state().transitionChannelId, 'one');
        harness.setSnapshot({ ...playingSnapshot(), status: 'ready', playing: false });
        assert.equal(harness.state().activeOverlayId, 'nowPlaying');
      } else {
        assert.equal(harness.state().transitionChannelId, null);
      }
      assert.equal(harness.controller.closeTop(), true);
      assert.equal(harness.state().activeOverlayId, null, `${invoker}/${outcome} Back`);
    }
  }
});

test('terminal focus and actions delegate recovery then use Guide fallback', () => {
  const harness = createHarness({
    ...playingSnapshot(),
    status: 'error',
    playing: false,
    lastError: safeError(),
  });
  harness.controller.reconcileSnapshot(harness.snapshot(), true);
  assert.equal(harness.focus.at(-1), 'overlay-player-retry');
  assert.equal(harness.controller.handleInput('ok'), false);
  assert.equal(harness.controller.retry(), true);
  assert.equal(harness.state().retryTransitionActive, true);

  const destroyed = createHarness({ ...playingSnapshot(), status: 'destroyed', playing: false, lastError: null });
  destroyed.controller.reconcileSnapshot(destroyed.snapshot(), true);
  assert.equal(destroyed.focus.at(-1), 'overlay-player-guide');
  assert.equal(destroyed.controller.handleInput('ok'), false);
});

test('mini-guide pointer activation selects exact row, contains Left, and owns its failure', async () => {
  const tune = deferred<{ ok: false; requestId: string; error: { code: string; message: string; retryable: boolean; recoverable: boolean; operation: string } }>();
  const harness = createHarness(playingSnapshot(), { tuneChannel: async () => tune.promise });
  harness.controller.requestMiniGuide();
  assert.equal(harness.controller.activateMiniGuideChannel('two'), true);
  assert.equal(harness.state().miniGuideSelectedChannelId, 'two');
  assert.equal(harness.state().pendingTuneChannelId, 'two');
  assert.equal(harness.controller.handleInput('left'), true);
  tune.resolve({
    ok: false, requestId: 'mini',
    error: { code: 'FAILED', message: 'Mini failed safely.', retryable: true, recoverable: true, operation: 'player.tuneChannel' },
  });
  await flushPromiseQueue();
  assert.equal(harness.state().miniGuideError, 'Mini failed safely.');
  assert.equal(harness.focus.at(-1), 'overlay-mini-channel-two');
  harness.controller.handleInput('down');
  assert.equal(harness.state().miniGuideError, null);
});

test('transition ownership suppresses duplicate tune and survives a higher overlay cover', () => {
  let tuneCount = 0;
  const tune = deferred<{ ok: true; value: never; requestId: string }>();
  const harness = createHarness(playingSnapshot(), {
    tuneChannel: async () => { tuneCount += 1; return tune.promise; },
  });
  void harness.controller.tune('one', 'miniGuide');
  void harness.controller.tune('one', 'miniGuide');
  assert.equal(tuneCount, 1);
  harness.timers.advance(175);
  assert.equal(harness.state().transitionVisible, true);
  harness.controller.requestNowPlaying();
  let view = createPlayerOverlayView(harness.state(), presentation(harness.snapshot()));
  assert.equal(view.visibleOverlays.nowPlaying, true);
  assert.equal(view.visibleOverlays.transition, false);
  assert.equal(view.visibleOverlays.channelBadge, false);
  harness.controller.closeTop();
  view = createPlayerOverlayView(harness.state(), presentation(harness.snapshot()));
  assert.equal(view.visibleOverlays.transition, true);
});

test('paused OSD persists and warning or unmatched error events are sanitized diagnostics only', () => {
  const harness = createHarness({ ...playingSnapshot(), status: 'paused', playing: false });
  harness.controller.requestOsd();
  harness.timers.advance(30_000);
  assert.equal(harness.state().activeOverlayId, 'playerOsd');
  harness.controller.handlePlayerEvent({ event: 'warning', requestId: null, warning: { ...safeError(), message: ['to', 'ken', 'opaque'].join('') } });
  harness.controller.handlePlayerEvent({ event: 'error', requestId: 'unmatched', error: { ...safeError(), message: ['se', 'cret'].join('') } });
  assert.deepEqual(harness.diagnostics, ['Player warning.', 'Player error.']);
  assert.equal(harness.state().activeOverlayId, 'playerOsd');
});

test('options contain Space, membership loss closes an ineligible family, and tune success updates before refresh', async () => {
  const dispatches: string[] = [];
  const optionsHarness = createHarness(playingSnapshot(), {
    dispatch: async (envelope) => {
      dispatches.push(envelope.intent);
      return accepted(envelope.requestId);
    },
  });
  optionsHarness.controller.requestOsd();
  optionsHarness.controller.openOptions('audio');
  await optionsHarness.controller.selectTrack('audio', 'audio-alt', 'overlay-audio-track-audio-alt');
  optionsHarness.controller.handleInput('space');
  assert.deepEqual(dispatches, ['player.selectAudio']);
  optionsHarness.setSnapshot({
    ...playingSnapshot(),
    tracks: [{ id: 'audio-main', kind: 'audio', label: 'Main', selected: true, available: true }],
  });
  assert.equal(optionsHarness.state().activeOverlayId, null);
  assert.equal(optionsHarness.focus.at(-1), null);

  const refresh = deferred<void>();
  const retryHarness = createHarness({ ...playingSnapshot(), status: 'error', playing: false, lastError: safeError() }, {
    refreshChannelStatus: () => refresh.promise,
  });
  retryHarness.controller.retry();
  await flushPromiseQueue();
  assert.equal(retryHarness.state().retryTransitionActive, true);
  assert.equal(retryHarness.state().activeOverlayId, null);
  refresh.resolve();

  retryHarness.controller.reconcileSnapshot({ ...playingSnapshot(), status: 'ended', playing: false }, false);
  assert.equal(retryHarness.state().transitionChannelId, null);
});

function createHarness(snapshot: PlayerSnapshot, overrides: Partial<{
  dispatch: LineupDesktopPreloadApi['player']['dispatch'];
  tuneChannel: LineupDesktopPreloadApi['player']['tuneChannel'];
  refreshChannelStatus: () => Promise<void>;
  refreshGuidePresentation: () => Promise<void>;
}> = {}) {
  let playerSnapshot = snapshot;
  let state = createPlayerOverlayState(presentation(snapshot));
  const timers = new FakeTimers();
  const focus: Array<string | null> = [];
  const diagnostics: string[] = [];
  const controller = createPlayerOverlayController({
    player: {
      dispatch: overrides.dispatch ?? (async (envelope) => accepted(envelope.requestId)),
      tuneChannel: overrides.tuneChannel ?? (async () => ({ ok: true, value: undefined as never, requestId: 'tune' })),
    },
    host: timers,
    getState: () => state,
    setState: (next) => { state = next; },
    getPresentation: () => presentation(playerSnapshot),
    render: () => undefined,
    focus: (id) => { focus.push(id); },
    openGuide: () => undefined,
    refreshChannelStatus: overrides.refreshChannelStatus ?? (async () => undefined),
    refreshGuidePresentation: overrides.refreshGuidePresentation ?? (async () => undefined),
    recordDiagnostic: (_operation, message) => { diagnostics.push(message); },
    recovery: {
      retry: () => {
        state = {
          ...state,
          retryPending: false,
          recoveryPendingAction: null,
          retryTransitionActive: true,
          retryError: null,
        };
        return true;
      },
      skip: () => false,
      reconcileSnapshot: (next) => {
        if (next.status !== 'error' && next.status !== 'destroyed') {
          state = { ...state, retryTransitionActive: false };
        }
      },
      invalidate: () => undefined,
      dispose: () => undefined,
    },
  });
  return {
    controller, timers, focus, diagnostics,
    state: () => state,
    snapshot: () => playerSnapshot,
    replaceSnapshot: (next: PlayerSnapshot) => { playerSnapshot = next; },
    setSnapshot: (next: PlayerSnapshot) => { playerSnapshot = next; controller.reconcileSnapshot(next, true); },
  };
}

function playingSnapshot(): PlayerSnapshot {
  return {
    ...createEmptyPlayerSnapshot(), requestId: 'playback-1', status: 'playing', playing: true,
    selectedAudioTrackId: 'audio-main',
    tracks: [
      { id: 'audio-main', kind: 'audio', label: 'Main', selected: true, available: true },
      { id: 'audio-alt', kind: 'audio', label: 'Alt', selected: false, available: true },
      { id: 'subtitle-one', kind: 'subtitle', label: 'English', selected: false, available: true },
    ],
  };
}

function presentation(playerSnapshot: PlayerSnapshot): PlayerOverlayPresentationSource {
  return {
    playerSnapshot, currentChannelId: 'one', nowMs: 1,
    channels: [
      { id: 'one', number: '1', name: 'One', currentProgram: { id: 'p1', title: 'One now', startsAtMs: 0, endsAtMs: 2 } },
      { id: 'two', number: '2', name: 'Two', currentProgram: { id: 'p2', title: 'Two now', startsAtMs: 0, endsAtMs: 2 } },
    ],
  };
}

function accepted(requestId: string): PlayerIpcResult<{ accepted: boolean; events: readonly PlayerEvent[]; snapshot: PlayerSnapshot }> {
  return { ok: true, requestId, value: { accepted: true, events: [], snapshot: playingSnapshot() } };
}

function safeError() {
  return { code: 'SAFE_FAILURE', category: 'track-failure' as const, message: 'Safe failure.', recoverable: true, retryable: true };
}

interface Deferred<T> { promise: Promise<T>; resolve(value: T): void; reject(reason?: unknown): void }
function deferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  let reject!: (reason?: unknown) => void;
  return { promise: new Promise<T>((done, fail) => { resolve = done; reject = fail; }), resolve, reject };
}

async function flushPromiseQueue(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

class FakeTimers implements PlayerOverlayTimerHost {
  #now = 0;
  #next = 1;
  #timers = new Map<number, { at: number; callback: () => void }>();
  setTimeout(callback: () => void, delayMs: number): number {
    const id = this.#next++;
    this.#timers.set(id, { at: this.#now + delayMs, callback });
    return id;
  }
  clearTimeout(id: number): void { this.#timers.delete(id); }
  advance(deltaMs: number): void {
    const target = this.#now + deltaMs;
    while (true) {
      const due = [...this.#timers.entries()].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
      if (due === undefined) break;
      this.#timers.delete(due[0]);
      this.#now = due[1].at;
      due[1].callback();
    }
    this.#now = target;
  }
}
