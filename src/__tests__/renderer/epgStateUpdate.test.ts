import assert from 'node:assert/strict';
import test from 'node:test';
import {
  EPG_SLOT_DURATION_MS,
  createEpgGuideView,
  createEpgState,
  createGuideProgramFocusId,
  updateEpgState,
  type EpgPresentationSource,
} from '../../renderer/epg.js';

const BASE = Date.UTC(2026, 6, 15, 12, 0, 0);
const source: EpgPresentationSource = {
  channels: [{
    id: 'one',
    number: '1',
    name: 'One',
    programs: [{
      id: 'program',
      title: 'Program',
      subtitle: '',
      description: '',
      showTitle: 'Program',
      episodeLabel: '',
      rating: '',
      quality: [],
      genres: [],
      startsAtMs: BASE,
      endsAtMs: BASE + EPG_SLOT_DURATION_MS,
    }],
  }],
  nowWatching: {
    channelId: 'one',
    title: 'Program',
    subtitle: '',
    startsAtMs: BASE,
    endsAtMs: BASE + EPG_SLOT_DURATION_MS,
  },
  nowMs: BASE,
};

test('updateEpgState retains a valid selection and adopts the request generation', () => {
  const initial = createEpgState(source, 2);
  const updated = updateEpgState(initial, source, 3);
  assert.equal(updated.selectedChannelId, 'one');
  assert.equal(updated.selectedProgramId, 'program');
  assert.equal(updated.presentationState, 'ready');
  assert.equal(updated.presentationGeneration, 3);
});

test('updateEpgState replaces missing identities with the current visible schedule', () => {
  const initial = {
    ...createEpgState(source),
    selectedChannelId: 'missing',
    selectedProgramId: 'missing',
  };
  const updated = updateEpgState(initial, source);
  assert.equal(updated.selectedChannelId, 'one');
  assert.equal(updated.selectedProgramId, 'program');
});

test('non-ready refresh classification uses the returned initial window', () => {
  const stale = {
    ...createEpgState(source),
    windowStartMs: BASE + 24 * 60 * 60 * 1_000,
    presentationState: 'loading' as const,
  };

  const updated = updateEpgState(stale, source);

  assert.equal(updated.presentationState, 'ready');
  assert.equal(updated.windowStartMs, BASE);
  assert.equal(updated.selectedProgramId, 'program');
});

test('periodic replacement keeps the selected channel and focuses its deterministic surviving program', () => {
  const selected = {
    ...createEpgState(source),
    selectedChannelId: 'two',
    selectedProgramId: 'removed',
  };
  const replacement: EpgPresentationSource = {
    ...source,
    channels: [
      source.channels[0]!,
      {
        id: 'two', number: '2', name: 'Two', programs: [{
          ...source.channels[0]!.programs[0]!,
          id: 'survivor', title: 'Survivor', showTitle: 'Survivor',
        }],
      },
    ],
  };
  const updated = updateEpgState(selected, replacement, 9);
  const view = createEpgGuideView(updated, replacement);
  assert.equal(updated.selectedChannelId, 'two');
  assert.equal(updated.selectedProgramId, 'survivor');
  assert.equal(view.selectedProgram?.focusId, createGuideProgramFocusId('two', 'survivor'));
});

test('updateEpgState distinguishes no channels from channels without visible programs', () => {
  const initial = createEpgState(source);
  const noChannels = updateEpgState(initial, { channels: [], nowWatching: null, nowMs: BASE });
  assert.equal(noChannels.presentationState, 'empty-channels');
  assert.equal(noChannels.selectedChannelId, '');
  const noPrograms = updateEpgState(initial, {
    channels: [{ id: 'empty', number: '2', name: 'Empty', programs: [] }],
    nowWatching: null,
    nowMs: BASE,
  });
  assert.equal(noPrograms.presentationState, 'empty-programs');
  assert.equal(noPrograms.selectedProgramId, '');
});
