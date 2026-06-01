import test from 'node:test';
import assert from 'node:assert/strict';

import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import {
  EPG_DEMO_BASE_TIME_MS,
  EPG_SLOT_DURATION_MS,
  applyEpgAction,
  calculateProgramSpan,
  createEpgGuideView,
  createEpgState,
  formatEpgTime,
  formatEpgTimeWindow,
  getDefaultEpgPresentationChannels,
  setEpgPresentationState,
  type EpgProgramViewModel,
} from '../../renderer/epg.js';

test('EPG guide view creates deterministic slots and clipped program spans', () => {
  const view = createEpgGuideView(createEpgState());

  assert.equal(view.slots.length, 6);
  assert.equal(view.slots[0].label, '8:00 PM');
  assert.equal(view.slots[5].label, '10:30 PM');
  assert.equal(view.rows.length, 4);
  assert.equal(view.rows.some((row) => row.name.includes('Long Channel Name')), true);

  const selectedProgram = view.selectedProgram;
  assert.notEqual(selectedProgram, null);
  if (selectedProgram === null) return;
  assert.equal(selectedProgram.id, 'liminal-cold-open');
  assert.equal(selectedProgram.columnStart, 1);
  assert.equal(selectedProgram.columnSpan, 1);
  assert.equal(selectedProgram.temporalState, 'past');
  assert.equal(selectedProgram.progressPercent, 0);
  assert.equal(selectedProgram.widthTier, 'narrow');
  assert.equal(selectedProgram.timeLabel, '7:30 PM - 8:30 PM');

  const clippedProgram = view.rows[0].programs.find(
    (program) => program.id === 'liminal-cold-open',
  );
  assert.equal(clippedProgram?.columnStart, 1);
  assert.equal(clippedProgram?.columnSpan, 1);
  assert.equal(clippedProgram?.temporalState, 'past');
});

test('EPG guide view exposes upstream-shaped shell, info panel, and route states', () => {
  const view = createEpgGuideView(createEpgState());

  assert.equal(view.shell.brandLabel, 'LINEUP');
  assert.equal(view.shell.layoutMode, 'classic');
  assert.match(view.shell.focusHint, /OK Select/u);
  assert.equal(view.shell.nowWatchingChannelLabel, '101 - Liminal One');
  assert.equal(view.infoPanel?.eyebrow, 'Lineup Live');
  assert.equal(view.infoPanel?.subtitle, 'S1 E1');
  assert.deepEqual(view.infoPanel?.badges, ['TV-PG', 'HD', 'AAC']);
  assert.match(view.infoPanel?.description ?? '', /warmup block/u);
  assert.equal(view.state.state, 'ready');
});

test('EPG schedule formatting uses deterministic UTC labels', () => {
  assert.equal(formatEpgTime(Date.UTC(2026, 4, 12, 0, 0, 0)), '12:00 AM');
  assert.equal(formatEpgTime(Date.UTC(2026, 4, 12, 12, 0, 0)), '12:00 PM');
  assert.equal(
    formatEpgTimeWindow(
      EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS,
      EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS * 3,
    ),
    '8:30 PM - 9:30 PM',
  );
});

test('EPG span helper returns null for programs outside the visible window', () => {
  const outsideProgram: EpgProgramViewModel = {
    id: 'outside-window',
    title: 'Outside Window',
    subtitle: 'Not visible',
    description: 'Outside the guide window.',
    showTitle: 'Outside Window',
    episodeLabel: 'Program',
    rating: 'TV-PG',
    quality: ['HD'],
    genres: ['Lineup'],
    startsAtMs: EPG_DEMO_BASE_TIME_MS - EPG_SLOT_DURATION_MS * 3,
    endsAtMs: EPG_DEMO_BASE_TIME_MS - EPG_SLOT_DURATION_MS * 2,
  };

  assert.equal(
    calculateProgramSpan(
      outsideProgram,
      EPG_DEMO_BASE_TIME_MS,
      EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS * 6,
    ),
    null,
  );
});

test('EPG actions move the guide window and normalize selection to visible programs', () => {
  const initial = createEpgState();
  const later = applyEpgAction(initial, 'nextWindow');
  const laterView = createEpgGuideView(later);

  assert.equal(later.windowStartMs, EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS);
  assert.equal(laterView.windowStartMs, later.windowStartMs);
  assert.equal(laterView.selectedProgram?.id, 'liminal-archive');

  const latest = applyEpgAction(applyEpgAction(later, 'nextWindow'), 'nextWindow');
  assert.equal(latest.windowStartMs, EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS * 2);

  const clamped = applyEpgAction(latest, 'nextWindow');
  assert.equal(clamped.windowStartMs, latest.windowStartMs);
});

test('EPG channel and program actions stay inside visible guide bounds', () => {
  const initial = createEpgState();
  const nextChannel = applyEpgAction(initial, 'nextChannel');
  const nextChannelView = createEpgGuideView(nextChannel);

  assert.equal(nextChannel.selectedChannelId, 'channel-vault');
  assert.equal(nextChannelView.selectedProgram?.channelId, 'channel-vault');
  assert.equal(nextChannelView.selectedProgram?.id, 'vault-feature');

  const nextProgram = applyEpgAction(nextChannel, 'nextProgram');
  assert.equal(createEpgGuideView(nextProgram).selectedProgram?.id, 'vault-notes');

  const previousProgram = applyEpgAction(nextProgram, 'previousProgram');
  assert.equal(createEpgGuideView(previousProgram).selectedProgram?.id, 'vault-feature');

  const firstProgram = applyEpgAction(previousProgram, 'previousProgram');
  assert.equal(createEpgGuideView(firstProgram).selectedProgram?.id, 'vault-feature');
});

test('EPG now-watching banner remains tied to current program when guide focus moves', () => {
  const initial = createEpgState();
  const initialView = createEpgGuideView(initial);
  const moved = applyEpgAction(initial, 'nextChannel');
  const movedView = createEpgGuideView(moved);

  assert.equal(movedView.selectedProgram?.channelId, 'channel-vault');
  assert.equal(initialView.shell.nowWatchingChannelLabel, '101 - Liminal One');
  assert.equal(movedView.shell.nowWatchingChannelLabel, '101 - Liminal One');
  assert.equal(movedView.shell.nowWatching.title, 'The Midnight Archive');
});

test('guide presentation state variants are mutually exclusive', () => {
  for (const state of ['loading', 'empty', 'error'] as const) {
    const view = createEpgGuideView(setEpgPresentationState(createEpgState(), state));
    assert.equal(view.presentationState, state);
    assert.equal(view.state.state, state);
    assert.equal(view.rows.length, 0);
    assert.equal(view.selectedProgram, null);
    assert.equal(view.infoPanel, null);
  }

  const ready = createEpgGuideView(createEpgState());
  assert.equal(ready.presentationState, 'ready');
  assert.equal(ready.rows.length > 0, true);
  assert.notEqual(ready.selectedProgram, null);
});

test('EPG presentation view models avoid Plex and player privileged renderer fields', () => {
  assert.equal(containsPlexForbiddenRendererField(getDefaultEpgPresentationChannels()), false);
  assert.equal(containsPlexForbiddenRendererField(createEpgGuideView(createEpgState())), false);
});
