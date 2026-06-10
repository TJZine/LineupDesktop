import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createEpgState,
  updateEpgState,
  DEFAULT_EPG_PRESENTATION_SOURCE,
  type EpgPresentationSource,
} from '../../renderer/epg.js';

test('updateEpgState retains current channel and program selection when valid', () => {
  const initial = createEpgState();
  const updated = updateEpgState(initial, DEFAULT_EPG_PRESENTATION_SOURCE);

  assert.equal(updated.selectedChannelId, initial.selectedChannelId);
  assert.equal(updated.selectedProgramId, initial.selectedProgramId);
  assert.equal(updated.windowStartMs, initial.windowStartMs);
  assert.equal(updated.presentationState, 'ready');
});

test('updateEpgState falls back to initial selection when selected channel is missing', () => {
  const initial = createEpgState();
  initial.selectedChannelId = 'non-existent-channel';

  const updated = updateEpgState(initial, DEFAULT_EPG_PRESENTATION_SOURCE);

  assert.notEqual(updated.selectedChannelId, 'non-existent-channel');
  assert.equal(updated.selectedChannelId, 'channel-liminal-one');
  assert.equal(updated.selectedProgramId, 'liminal-archive');
  assert.equal(updated.presentationState, 'ready');
});

test('updateEpgState picks fallback program on same channel when selected program is missing', () => {
  const initial = createEpgState();
  initial.selectedProgramId = 'missing-program-id';

  const updated = updateEpgState(initial, DEFAULT_EPG_PRESENTATION_SOURCE);

  assert.equal(updated.selectedChannelId, 'channel-liminal-one');
  assert.notEqual(updated.selectedProgramId, 'missing-program-id');
  assert.equal(updated.selectedProgramId, 'liminal-archive');
  assert.equal(updated.presentationState, 'ready');
});

test('updateEpgState clamps windowStartMs when it drifts out of new presentation bounds', () => {
  const initial = createEpgState();
  initial.windowStartMs = initial.windowStartMs + 12 * 60 * 60 * 1000; // 12 hours later

  const updated = updateEpgState(initial, DEFAULT_EPG_PRESENTATION_SOURCE);

  assert.equal(updated.windowStartMs, 1778619600000);
});

test('updateEpgState sets empty state when presentation contains no channels', () => {
  const initial = createEpgState();
  const emptyPresentation: EpgPresentationSource = {
    channels: [],
    nowWatching: null,
  };

  const updated = updateEpgState(initial, emptyPresentation);

  assert.equal(updated.selectedChannelId, '');
  assert.equal(updated.selectedProgramId, '');
  assert.equal(updated.presentationState, 'empty');
});
