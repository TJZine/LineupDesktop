import assert from 'node:assert/strict';
import test from 'node:test';

import { createDefaultDesktopSettingsValues } from '../../contracts/settings.js';
import {
  applyWorkflowSettingsAction,
  applyWorkflowSettingsValues,
  createWorkflowState,
} from '../../renderer/workflow.js';
import { computeProvisionalEpgMinimumStartTimeMs } from '../../renderer/epg.js';

const FIXED_NOW_MS = 1_783_512_840_000;

test('settings action and persisted-values synchronization share the fixed EPG clock', () => {
  const state = createWorkflowState('settings', {
    channels: [],
    nowWatching: null,
    nowMs: FIXED_NOW_MS,
  });
  const actionState = applyWorkflowSettingsAction(state, 'cyclePastItemsWindow', FIXED_NOW_MS);
  const valuesState = applyWorkflowSettingsValues(
    state,
    { ...createDefaultDesktopSettingsValues(), pastItemsWindow: '0' },
    undefined,
    FIXED_NOW_MS,
  );

  assert.equal(actionState.settingsDraft.pastItemsWindow, '0');
  assert.equal(valuesState.settingsDraft.pastItemsWindow, '0');
  // 2026-07-08T12:14:00Z -> the independently frozen 12:00 UTC slot.
  assert.equal(actionState.epg.minimumStartTimeMs, 1_783_512_000_000);
  assert.equal(actionState.epg.windowStartMs, 1_783_512_000_000);
  assert.deepEqual(actionState.epg, valuesState.epg);
});

test('workflow startup uses its fallback clock unless the Guide captures a clock value', () => {
  const fallbackNowMs = FIXED_NOW_MS;
  const fallbackState = createWorkflowState('settings', { channels: [], nowWatching: null }, fallbackNowMs);
  assert.equal(
    fallbackState.epg.minimumStartTimeMs,
    computeProvisionalEpgMinimumStartTimeMs(fallbackNowMs, 'auto'),
  );

  const capturedNowMs = FIXED_NOW_MS + 60 * 60 * 1_000;
  const capturedState = createWorkflowState(
    'settings',
    { channels: [], nowWatching: null, nowMs: capturedNowMs },
    fallbackNowMs,
  );
  assert.equal(
    capturedState.epg.minimumStartTimeMs,
    computeProvisionalEpgMinimumStartTimeMs(capturedNowMs, 'auto'),
  );
});

test('settings synchronization defaults to the production clock without replacing Date.now', () => {
  const state = createWorkflowState('settings');
  const before = Date.now();
  const actionState = applyWorkflowSettingsAction(state, 'cyclePastItemsWindow');
  const valuesState = applyWorkflowSettingsValues(
    state,
    { ...createDefaultDesktopSettingsValues(), pastItemsWindow: '0' },
  );
  const after = Date.now();

  for (const minimumStartTimeMs of [
    actionState.epg.minimumStartTimeMs,
    valuesState.epg.minimumStartTimeMs,
  ]) {
    if (minimumStartTimeMs === undefined) throw new Error('Expected workflow synchronization to set an EPG minimum start.');
    assert.ok(minimumStartTimeMs >= before - 24 * 60 * 60 * 1_000);
    assert.ok(minimumStartTimeMs <= after);
  }
});
