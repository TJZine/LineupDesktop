import test from 'node:test';
import assert from 'node:assert/strict';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import { hasPlayerForbiddenPrivilegedField } from '../../contracts/player.js';
import {
  applyPlayerOverlayAction,
  createFakePlayerSnapshot,
  createPlayerOverlayState,
  createPlayerOverlayView,
  getFakeOverlayChannels,
  PLAYER_OVERLAY_IDLE_FOCUS_ID,
  resolvePlayerOverlayFocusId,
} from '../../renderer/overlays.js';

test('overlay state starts with now-playing, channel badge, and OSD visible', () => {
  const state = createPlayerOverlayState();
  const view = createPlayerOverlayView(state);

  assert.deepEqual(view.stack, ['channelBadge', 'nowPlaying', 'playerOsd']);
  assert.equal(view.visibleOverlays.playerOsd, true);
  assert.equal(view.visibleOverlays.nowPlaying, true);
  assert.equal(view.visibleOverlays.channelBadge, true);
  assert.equal(view.activeOverlayId, 'playerOsd');
  assert.equal(view.activeFocusId, 'overlay-mini-guide');
  assert.equal(view.nowPlaying.title, 'The Midnight Archive');
  assert.equal(view.nowPlaying.progressPercent, 20);
});

test('overlay stack keeps mini guide focused above passive badge overlays', () => {
  const state = applyPlayerOverlayAction(createPlayerOverlayState(), 'openMiniGuide');
  const view = createPlayerOverlayView(state);

  assert.equal(view.visibleOverlays.miniGuide, true);
  assert.equal(view.visibleOverlays.channelBadge, true);
  assert.equal(view.activeOverlayId, 'miniGuide');
  assert.equal(view.activeFocusId, 'overlay-mini-next');

  const closed = applyPlayerOverlayAction(state, 'closeTopOverlay');
  const closedView = createPlayerOverlayView(closed);
  assert.equal(closedView.visibleOverlays.miniGuide, false);
  assert.equal(closedView.activeOverlayId, 'playerOsd');
});

test('mini guide channel selection updates the selected channel and badge summary', () => {
  const next = applyPlayerOverlayAction(createPlayerOverlayState(), 'nextMiniGuideChannel');
  const view = createPlayerOverlayView(next);

  assert.equal(view.selectedMiniGuideChannel.number, '204');
  assert.equal(view.channelBadge.name, 'The Vault');
  assert.deepEqual(
    view.miniGuideChannels.map((channel) => [channel.number, channel.selected]),
    [
      ['101', false],
      ['204', true],
      ['310', false],
      ['411', false],
      ['512', false],
    ],
  );

  const previous = applyPlayerOverlayAction(next, 'previousMiniGuideChannel');
  assert.equal(createPlayerOverlayView(previous).selectedMiniGuideChannel.number, '101');
});

test('channel number buffer accepts digits, expires stale input, and tunes matches', () => {
  const initial = createPlayerOverlayState();
  const one = applyPlayerOverlayAction(initial, 'channelDigit2', 1_000);
  const two = applyPlayerOverlayAction(one, 'channelDigit0', 1_500);
  const three = applyPlayerOverlayAction(two, 'channelDigit4', 2_000);
  const view = createPlayerOverlayView(three);

  assert.equal(view.visibleOverlays.channelNumber, true);
  assert.equal(view.channelNumberBuffer, '204');
  assert.equal(view.channelNumberDisplay, '204');
  assert.equal(view.activeOverlayId, 'channelNumber');

  const tuned = applyPlayerOverlayAction(three, 'commitChannelNumber', 2_100);
  const tunedView = createPlayerOverlayView(tuned);
  assert.equal(tunedView.selectedMiniGuideChannel.number, '204');
  assert.equal(tunedView.channelNumberBuffer, '');
  assert.equal(tunedView.visibleOverlays.channelNumber, false);

  const stale = applyPlayerOverlayAction(two, 'channelDigit1', 4_500);
  assert.equal(createPlayerOverlayView(stale).channelNumberBuffer, '1');
});

test('playback options cycle renderer-local track and volume state', () => {
  const initial = createPlayerOverlayState();
  const options = applyPlayerOverlayAction(initial, 'togglePlaybackOptions');
  const audio = applyPlayerOverlayAction(options, 'cycleAudioTrack');
  const subtitle = applyPlayerOverlayAction(audio, 'cycleSubtitleTrack');
  const louder = applyPlayerOverlayAction(subtitle, 'volumeUp');
  const muted = applyPlayerOverlayAction(louder, 'toggleMute');
  const view = createPlayerOverlayView(muted);

  assert.equal(view.visibleOverlays.playbackOptions, true);
  assert.equal(view.activeOverlayId, 'playbackOptions');
  assert.equal(view.playbackOptions.selectedAudioLabel, 'Commentary');
  assert.equal(view.playbackOptions.selectedSubtitleLabel, 'English');
  assert.equal(view.playbackOptions.volumePercent, 82);
  assert.equal(view.playbackOptions.muted, true);
  assert.equal(view.playbackOptions.audioTracks.some((track) => !track.available), true);
  assert.equal(view.playbackOptions.subtitleTracks.some((track) => track.meta === 'Burn-in'), true);
  assert.match(view.playbackOptions.playbackSummary, /Direct Play .*Video Transcode/u);
});

test('playback options normalize unknown track ids to the first option when cycling', () => {
  const initial = {
    ...createPlayerOverlayState(),
    selectedAudioTrackId: 'unknown-audio-track',
    selectedSubtitleTrackId: 'unknown-subtitle-track',
  };

  const audio = applyPlayerOverlayAction(initial, 'cycleAudioTrack');
  const subtitle = applyPlayerOverlayAction(audio, 'cycleSubtitleTrack');
  const view = createPlayerOverlayView(subtitle);

  assert.equal(subtitle.selectedAudioTrackId, 'audio-main');
  assert.equal(subtitle.selectedSubtitleTrackId, null);
  assert.equal(view.playbackOptions.selectedAudioLabel, 'Main stereo');
  assert.equal(view.playbackOptions.selectedSubtitleLabel, 'Off');
});

test('primary playback options action opens options above the visible OSD', () => {
  const options = applyPlayerOverlayAction(createPlayerOverlayState(), 'togglePlaybackOptions');
  const view = createPlayerOverlayView(options);

  assert.equal(view.visibleOverlays.playerOsd, true);
  assert.equal(view.visibleOverlays.playbackOptions, true);
  assert.equal(view.activeOverlayId, 'playbackOptions');
  assert.equal(view.activeFocusId, 'overlay-audio-cycle');
  assert.equal(resolvePlayerOverlayFocusId(view), 'overlay-audio-cycle');
});

test('closing the last modal overlay falls back to the visible player OSD toggle focus', () => {
  const passiveOnly = applyPlayerOverlayAction(createPlayerOverlayState(), 'closeTopOverlay');
  const view = createPlayerOverlayView(passiveOnly);

  assert.deepEqual(view.stack, ['channelBadge', 'nowPlaying']);
  assert.equal(view.visibleOverlays.channelBadge, true);
  assert.equal(view.visibleOverlays.nowPlaying, true);
  assert.equal(view.visibleOverlays.playerOsd, false);
  assert.equal(view.activeOverlayId, null);
  assert.equal(view.activeFocusId, null);
  assert.equal(resolvePlayerOverlayFocusId(view), PLAYER_OVERLAY_IDLE_FOCUS_ID);
});

test('overlay view can summarize a renderer-safe player snapshot', () => {
  const snapshot = {
    ...createFakePlayerSnapshot(),
    status: 'paused',
    playing: false,
    positionMs: 30_000,
    durationMs: 60_000,
    media: {
      id: 'snapshot-media',
      title: 'Snapshot Title',
      subtitle: 'Snapshot Subtitle',
      durationMs: 60_000,
      container: 'preview',
    },
  } as const;
  const view = createPlayerOverlayView(createPlayerOverlayState(), snapshot);

  assert.equal(view.nowPlaying.title, 'Snapshot Title');
  assert.equal(view.nowPlaying.subtitle, 'Snapshot Subtitle');
  assert.equal(view.nowPlaying.statusLabel, 'Paused');
  assert.equal(view.nowPlaying.positionLabel, '0:30');
  assert.equal(view.nowPlaying.durationLabel, '1:00');
  assert.equal(view.nowPlaying.progressPercent, 50);
});

test('overlay view clamps now-playing progress to the visible media duration', () => {
  const baseSnapshot = createFakePlayerSnapshot();
  const negativePositionView = createPlayerOverlayView(createPlayerOverlayState(), {
    ...baseSnapshot,
    positionMs: -30_000,
    durationMs: 60_000,
    media: {
      id: 'clamped-media',
      title: 'Clamped Media',
      durationMs: 60_000,
    },
  });

  assert.equal(negativePositionView.nowPlaying.positionLabel, '0:00');
  assert.equal(negativePositionView.nowPlaying.durationLabel, '1:00');
  assert.equal(negativePositionView.nowPlaying.progressPercent, 0);

  const beyondDurationView = createPlayerOverlayView(createPlayerOverlayState(), {
    ...baseSnapshot,
    positionMs: 90_000,
    durationMs: 60_000,
    media: {
      id: 'clamped-media',
      title: 'Clamped Media',
      durationMs: 60_000,
    },
  });

  assert.equal(beyondDurationView.nowPlaying.positionLabel, '1:00');
  assert.equal(beyondDurationView.nowPlaying.durationLabel, '1:00');
  assert.equal(beyondDurationView.nowPlaying.progressPercent, 100);
});

test('fake overlay view models avoid privileged renderer fields', () => {
  const view = createPlayerOverlayView(createPlayerOverlayState());

  assert.equal(containsPlexForbiddenRendererField(getFakeOverlayChannels()), false);
  assert.equal(containsPlexForbiddenRendererField(view), false);
  assert.equal(hasPlayerForbiddenPrivilegedField(view), false);
});
