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
  getFakeEpgChannels,
  type EpgProgramViewModel,
} from '../../renderer/epg.js';

test('EPG guide view creates deterministic slots and clipped program spans', () => {
  const view = createEpgGuideView(createEpgState());

  assert.equal(view.slots.length, 6);
  assert.equal(view.slots[0].label, '8:00 PM');
  assert.equal(view.slots[5].label, '10:30 PM');
  assert.equal(view.rows.length, 4);

  const selectedProgram = view.selectedProgram;
  assert.equal(selectedProgram.id, 'liminal-archive');
  assert.equal(selectedProgram.columnStart, 2);
  assert.equal(selectedProgram.columnSpan, 2);

  const clippedProgram = view.rows[0].programs.find(
    (program) => program.id === 'liminal-cold-open',
  );
  assert.equal(clippedProgram?.columnStart, 1);
  assert.equal(clippedProgram?.columnSpan, 1);
});

test('EPG fake schedule formatting uses deterministic UTC labels', () => {
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

test('EPG actions move the fake window and normalize selection to visible programs', () => {
  const initial = createEpgState();
  const later = applyEpgAction(initial, 'nextWindow');
  const laterView = createEpgGuideView(later);

  assert.equal(later.windowStartMs, EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS);
  assert.equal(laterView.windowStartMs, later.windowStartMs);
  assert.equal(laterView.selectedProgram.id, 'liminal-archive');

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
  assert.equal(nextChannelView.selectedProgram.channelId, 'channel-vault');
  assert.equal(nextChannelView.selectedProgram.id, 'vault-feature');

  const nextProgram = applyEpgAction(nextChannel, 'nextProgram');
  assert.equal(createEpgGuideView(nextProgram).selectedProgram.id, 'vault-notes');

  const previousProgram = applyEpgAction(nextProgram, 'previousProgram');
  assert.equal(createEpgGuideView(previousProgram).selectedProgram.id, 'vault-feature');

  const firstProgram = applyEpgAction(previousProgram, 'previousProgram');
  assert.equal(createEpgGuideView(firstProgram).selectedProgram.id, 'vault-feature');
});

test('fake EPG schedule view models avoid Plex and player privileged renderer fields', () => {
  assert.equal(containsPlexForbiddenRendererField(getFakeEpgChannels()), false);
  assert.equal(containsPlexForbiddenRendererField(createEpgGuideView(createEpgState())), false);
});
