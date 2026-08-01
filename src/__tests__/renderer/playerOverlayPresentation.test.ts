import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createEmptyPlayerSnapshot,
  createPlayerOverlayPresentation,
  firstEligibleOsdFocusId,
  isSleepControlEligible,
} from '../../renderer/playerOverlayPresentation.js';

test('presentation joins persisted channels to scheduler programs and omits missing data', () => {
  const presentation = createPlayerOverlayPresentation({
    playerSnapshot: createEmptyPlayerSnapshot(),
    nowMs: 150,
    channelSummary: {
      status: 'configured', lineupRevision: 1, channelCount: 2, currentChannelId: 'one', currentChannelNumber: 1,
      currentChannelName: 'One', channelNumbers: [1, 2], updatedAtMs: 1,
      recovery: { loaded: true, repaired: false },
      builder: { completion: 'unknown', normalizedConfig: null, completedAtMs: null },
      channels: [
        { id: 'one', number: 1, name: 'One', sourceLibraryId: null, sourceLibraryName: null, itemCount: 1 },
        { id: 'two', number: 2, name: 'Two', sourceLibraryId: null, sourceLibraryName: null, itemCount: 0 },
      ],
    },
    guidePresentation: {
      nowWatching: null,
      nowMs: 150,
      channels: [{
        id: 'one', number: '1', name: 'One', programs: [
          program('current', 'Current', 100, 200),
          program('next', 'Next', 200, 300),
        ],
      }],
    },
  });

  assert.equal(presentation.currentChannelId, 'one');
  assert.equal(presentation.channels[0]?.currentProgram?.title, 'Current');
  assert.equal(presentation.channels[0]?.nextProgram?.title, 'Next');
  assert.equal(presentation.channels[0]?.progressPercent, 50);
  assert.equal(presentation.channels[1]?.currentProgram, undefined);
  assert.equal(Object.hasOwn(presentation.channels[1] ?? {}, 'currentProgram'), false);
});

test('presentation does not create placeholder channels when runtime data is absent', () => {
  const presentation = createPlayerOverlayPresentation({
    playerSnapshot: createEmptyPlayerSnapshot(), channelSummary: null, guidePresentation: null, nowMs: 0,
  });
  assert.deepEqual(presentation.channels, []);
  assert.equal(presentation.playerSnapshot.seekSupport, 'unknown');
  assert.equal(presentation.currentChannelId, null);
});

test('OSD focus projection keeps Sleep request-bound and orders Subtitles, Sleep, Audio', () => {
  const empty = createEmptyPlayerSnapshot();
  const ready = { ...empty, requestId: 'request-one', status: 'ready' as const };
  assert.equal(isSleepControlEligible(empty), false);
  assert.equal(isSleepControlEligible(ready), true);
  assert.equal(firstEligibleOsdFocusId(ready), 'overlay-osd-sleep');
  assert.equal(firstEligibleOsdFocusId({
    ...ready,
    tracks: [{ id: 'subtitle-one', kind: 'subtitle', label: 'English', selected: false, available: true }],
  }), 'overlay-osd-subtitles');
  assert.equal(firstEligibleOsdFocusId({
    ...empty,
    status: 'playing',
    playing: true,
    tracks: [
      { id: 'audio-one', kind: 'audio', label: 'Main', selected: true, available: true },
      { id: 'audio-two', kind: 'audio', label: 'Alt', selected: false, available: true },
    ],
    selectedAudioTrackId: 'audio-one',
  }), 'overlay-osd-audio');
});

function program(id: string, title: string, startsAtMs: number, endsAtMs: number) {
  return {
    id, title, subtitle: '', description: '', showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [], startsAtMs, endsAtMs,
  };
}
