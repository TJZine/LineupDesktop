import assert from 'node:assert/strict';
import test from 'node:test';

import type { PlayerSnapshot } from '../../contracts/player.js';
import {
  appendChannelDigit,
  closeTopOverlay,
  createPlayerOverlayState,
  moveMiniGuide,
  openMiniGuide,
  openNowPlaying,
  openOsd,
  openPlaybackOptions,
  reconcileSnapshotState,
} from '../../renderer/overlays.js';
import { createPlayerOverlayView } from '../../renderer/overlayViewModels.js';
import { createEmptyPlayerSnapshot, type PlayerOverlayPresentationSource } from '../../renderer/playerOverlayPresentation.js';

test('Player starts native, focusless, and without fixture presentation', () => {
  const presentation = source(snapshot('idle'), []);
  const view = createPlayerOverlayView(createPlayerOverlayState(presentation), presentation);

  assert.equal(view.baseline, 'native');
  assert.equal(view.activeOverlayId, null);
  assert.equal(view.activeFocusId, null);
  assert.deepEqual(view.stack, []);
  assert.equal(view.nowPlaying.title, undefined);
  assert.equal(view.currentChannel, null);
});

test('status projection exhaustively maps loading, native, seeking retention, and terminal errors', () => {
  const loading = ['loading', 'buffering', 'stalled'] as const;
  const native = ['idle', 'ready', 'playing', 'paused', 'ended'] as const;
  for (const status of loading) {
    assert.equal(createPlayerOverlayView(createPlayerOverlayState(), source(snapshot(status))).baseline, 'loading');
  }
  for (const status of native) {
    assert.equal(createPlayerOverlayView(createPlayerOverlayState(), source(snapshot(status))).baseline, 'native');
  }
  assert.equal(createPlayerOverlayView(createPlayerOverlayState(), source(snapshot('seeking'))).baseline, 'loading');
  const retained = { ...createPlayerOverlayState(), activeOverlayId: 'playerOsd' as const };
  assert.equal(createPlayerOverlayView(retained, source(snapshot('seeking'))).baseline, 'native');
  for (const status of ['error', 'destroyed'] as const) {
    const view = createPlayerOverlayView(createPlayerOverlayState(), source(snapshot(status)));
    assert.equal(view.baseline, 'error');
    assert.equal(view.visibleOverlays.playerError, true);
  }
});

test('OSD refuses zero controls and focuses the one/two eligible controls', () => {
  const base = createPlayerOverlayState();
  assert.equal(openOsd(base, snapshot('playing')).activeOverlayId, null);

  const audio = snapshot('playing', [track('a1', 'audio', true), track('a2', 'audio')]);
  const audioState = openOsd(base, audio);
  assert.equal(createPlayerOverlayView(audioState, source(audio)).activeFocusId, 'overlay-osd-audio');

  const subtitle = snapshot('paused', [track('s1', 'subtitle')]);
  const subtitleState = openOsd(base, subtitle);
  assert.equal(createPlayerOverlayView(subtitleState, source(subtitle)).activeFocusId, 'overlay-osd-subtitles');

  const both = snapshot('ready', [track('a1', 'audio', true), track('a2', 'audio'), track('s1', 'subtitle')]);
  assert.equal(createPlayerOverlayView(openOsd(base, both), source(both)).activeFocusId, 'overlay-osd-audio');
});

test('Info requires a real current program, replaces lower owners, and refuses over options', () => {
  const presentation = source(snapshot('playing'), channels());
  const mini = openMiniGuide(createPlayerOverlayState(presentation), presentation);
  assert.equal(openNowPlaying(mini, true, false).activeOverlayId, 'nowPlaying');
  assert.equal(openNowPlaying(mini, false, false), mini);
  const options = { ...mini, activeOverlayId: 'playbackOptions' as const };
  assert.equal(openNowPlaying(options, true, false), options);
});

test('mini-guide projects exactly five circular rows and page movement wraps', () => {
  const presentation = source(snapshot('playing'), channels(6));
  const opened = openMiniGuide(createPlayerOverlayState(presentation), presentation);
  const paged = moveMiniGuide(opened, presentation, 5);
  const view = createPlayerOverlayView(paged, presentation);
  assert.equal(view.miniGuideChannels.length, 5);
  assert.equal(view.miniGuideChannels.filter((channel) => channel.selected).length, 1);
  assert.equal(paged.miniGuideSelectedChannelId, 'channel-6');
});

test('mini-guide projects each short-catalog channel once with one selected row', () => {
  for (const count of [1, 2, 4]) {
    const presentation = source(snapshot('playing'), channels(count));
    const selectedId = presentation.channels.at(-1)?.id ?? null;
    const state = {
      ...openMiniGuide(createPlayerOverlayState(presentation), presentation),
      miniGuideSelectedChannelId: selectedId,
    };
    const rows = createPlayerOverlayView(state, presentation).miniGuideChannels;

    assert.equal(rows.length, count, `${String(count)} channel rows`);
    assert.equal(new Set(rows.map((channel) => channel.id)).size, count, `${String(count)} unique channel ids`);
    assert.equal(rows.filter((channel) => channel.selected).length, 1, `${String(count)} selected rows`);
  }
});

test('number entry is real-catalog-only state with no placeholder channel', () => {
  const state = appendChannelDigit(appendChannelDigit(createPlayerOverlayState(), '1'), '2');
  const view = createPlayerOverlayView(state, source(snapshot('playing'), []));
  assert.equal(view.channelNumberDisplay, '12_');
  assert.equal(view.activeOverlayId, 'channelNumber');
  assert.equal(view.currentChannel, null);
  assert.deepEqual(view.miniGuideChannels, []);
});

test('playback options expose only available real tracks and subtitle Off', () => {
  const player = snapshot('playing', [
    track('audio-main', 'audio', true),
    track('audio-alt', 'audio'),
    { ...track('audio-gone', 'audio'), available: false },
    track('sub-one', 'subtitle'),
  ]);
  const osd = openOsd(createPlayerOverlayState(), player);
  const audio = openPlaybackOptions(osd, player, 'audio');
  const audioView = createPlayerOverlayView(audio, source(player)).playbackOptions;
  assert.deepEqual(audioView?.tracks.map((item) => item.trackId), ['audio-main', 'audio-alt']);

  const subtitle = openPlaybackOptions(osd, player, 'subtitle');
  assert.deepEqual(
    createPlayerOverlayView(subtitle, source(player)).playbackOptions?.tracks.map((item) => item.trackId),
    [null, 'sub-one'],
  );
  assert.equal(closeTopOverlay(subtitle).activeOverlayId, 'playerOsd');
});

test('authoritative terminal snapshots close normal overlays without inventing errors', () => {
  const opened = { ...createPlayerOverlayState(), activeOverlayId: 'miniGuide' as const };
  assert.equal(reconcileSnapshotState(opened, snapshot('error')).activeOverlayId, null);
  assert.equal(reconcileSnapshotState(opened, snapshot('destroyed')).activeOverlayId, null);
  assert.equal(reconcileSnapshotState(opened, snapshot('paused')).activeOverlayId, 'miniGuide');
});

test('player error exposes deterministic Retry, Skip, and Guide fallback actions', () => {
  const errored = snapshot('error');
  const actionable = createPlayerOverlayView(
    createPlayerOverlayState(),
    source(errored, channels()),
  );
  assert.equal(actionable.retryVisible, true);
  assert.equal(actionable.skipVisible, true);
  assert.equal(actionable.guideVisible, false);
  assert.equal(actionable.activeFocusId, 'overlay-player-retry');

  for (const recoveryPendingAction of ['retry-current', 'skip-next'] as const) {
    const busy = createPlayerOverlayView(
      {
        ...createPlayerOverlayState(),
        retryPending: true,
        recoveryPendingAction,
      },
      source(errored, channels()),
    );
    assert.equal(busy.retryVisible, true);
    assert.equal(busy.skipVisible, true);
    assert.equal(busy.retryBusy, true);
    assert.equal(busy.skipBusy, true);
  }

  const skipOnlyChannels = channels().map((channel) => ({
    ...channel,
    currentProgram: undefined,
  }));
  const skipOnly = createPlayerOverlayView(
    createPlayerOverlayState(),
    source(errored, skipOnlyChannels),
  );
  assert.equal(skipOnly.retryVisible, false);
  assert.equal(skipOnly.skipVisible, true);
  assert.equal(skipOnly.activeFocusId, 'overlay-player-skip');

  const guideOnlyChannels = channels().map((channel) => ({
    ...channel,
    currentProgram: undefined,
    nextProgram: undefined,
  }));
  const guideOnly = createPlayerOverlayView(
    createPlayerOverlayState(),
    source(errored, guideOnlyChannels),
  );
  assert.equal(guideOnly.retryVisible, false);
  assert.equal(guideOnly.skipVisible, false);
  assert.equal(guideOnly.guideVisible, true);
  assert.equal(guideOnly.activeFocusId, 'overlay-player-guide');
});

function source(
  playerSnapshot: PlayerSnapshot,
  channelList: PlayerOverlayPresentationSource['channels'] = channels(),
): PlayerOverlayPresentationSource {
  return { channels: channelList, currentChannelId: channelList[0]?.id ?? null, playerSnapshot, nowMs: 1_000 };
}

function snapshot(
  status: PlayerSnapshot['status'],
  tracks: PlayerSnapshot['tracks'] = [],
): PlayerSnapshot {
  return {
    ...createEmptyPlayerSnapshot(),
    requestId: status === 'idle' ? null : 'playback-1',
    status,
    playing: status === 'playing',
    tracks,
    selectedAudioTrackId: tracks.find((item) => item.kind === 'audio' && item.selected)?.id ?? null,
    selectedSubtitleTrackId: tracks.find((item) => item.kind === 'subtitle' && item.selected)?.id ?? null,
    lastError: status === 'error' ? {
      code: 'PLAYBACK_FAILED', category: 'engine-failure', message: 'Playback failed.', recoverable: true, retryable: true,
    } : null,
  };
}

function track(id: string, kind: 'audio' | 'subtitle', selected = false) {
  return { id, kind, label: id, selected, available: true } as const;
}

function channels(count = 2) {
  return Array.from({ length: count }, (_, index) => ({
    id: `channel-${index + 1}`,
    number: String(index + 1),
    name: `Channel ${index + 1}`,
    currentProgram: { id: `program-${index + 1}`, title: `Program ${index + 1}`, startsAtMs: 0, endsAtMs: 2_000 },
    nextProgram: { id: `next-${index + 1}`, title: `Next ${index + 1}`, startsAtMs: 2_000, endsAtMs: 3_000 },
    progressPercent: 50,
  }));
}
