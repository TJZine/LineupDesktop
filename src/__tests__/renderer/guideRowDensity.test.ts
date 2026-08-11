import assert from 'node:assert/strict';
import test from 'node:test';

import {
  completeGuideRowCount,
  GUIDE_COMFORTABLE_ROW_HEIGHT,
  GUIDE_COMPACT_ROW_HEIGHT,
  GUIDE_MAX_COMPLETE_ROW_FLOOR,
  GUIDE_MINIMUM_COMPLETE_ROW_FLOOR,
  GUIDE_STANDARD_COMPLETE_ROW_FLOOR,
  guideCompleteRowFloor,
  projectGuideCompleteRowInterval,
  resolveGuideRowDensity,
} from '../../renderer/guideRowDensity.js';
import {
  createSettingsGuideSettingsSettlementOwner,
  type GuideSettingsValues,
} from '../../renderer/settings/guideSettingsSettlement.js';

test('Guide density keeps the frozen pure 108px/72px treatments and complete-row math', () => {
  assert.equal(resolveGuideRowDensity('comfortable', { width: 1_920, height: 1_080 }).rowHeight, GUIDE_COMFORTABLE_ROW_HEIGHT);
  assert.equal(resolveGuideRowDensity('compact', { width: 1_920, height: 1_080 }).rowHeight, GUIDE_COMPACT_ROW_HEIGHT);
  assert.equal(completeGuideRowCount(108 * 8 + 107, GUIDE_COMFORTABLE_ROW_HEIGHT), 8);
  assert.equal(completeGuideRowCount(108 * 8 + 1, GUIDE_COMFORTABLE_ROW_HEIGHT), 8);
  assert.equal(completeGuideRowCount(107, GUIDE_COMFORTABLE_ROW_HEIGHT), 0, 'partial row is not reported as complete');
  assert.equal(completeGuideRowCount(72 * 5 + 4 * 12, GUIDE_COMPACT_ROW_HEIGHT, 12), 5);
  assert.deepEqual(projectGuideCompleteRowInterval(720, 300, 0, GUIDE_COMFORTABLE_ROW_HEIGHT, 16), {
    start: 0,
    count: 3,
    remainingHeight: 420,
  });
  assert.deepEqual(projectGuideCompleteRowInterval(720, 300, 344, GUIDE_COMFORTABLE_ROW_HEIGHT, 16), {
    start: 1,
    count: 5,
    remainingHeight: 720,
  });
  assert.deepEqual(projectGuideCompleteRowInterval(100, 300, 344, GUIDE_COMFORTABLE_ROW_HEIGHT, 16), {
    start: 1,
    count: 0,
    remainingHeight: 100,
  });
});

test('Guide density floors map only the frozen 100% envelopes and honest scaled/narrow fallbacks', () => {
  assert.equal(guideCompleteRowFloor({ width: 3_840, height: 2_160, devicePixelRatio: 1 }), GUIDE_MAX_COMPLETE_ROW_FLOOR);
  assert.equal(guideCompleteRowFloor({ width: 1_920, height: 1_080, devicePixelRatio: 1 }), GUIDE_STANDARD_COMPLETE_ROW_FLOOR);
  assert.equal(guideCompleteRowFloor({ width: 1_536, height: 864, devicePixelRatio: 1.25 }), GUIDE_MINIMUM_COMPLETE_ROW_FLOOR);
  assert.equal(guideCompleteRowFloor({ width: 1_280, height: 720, devicePixelRatio: 1.5 }), GUIDE_MINIMUM_COMPLETE_ROW_FLOOR);
  assert.equal(guideCompleteRowFloor({ width: 1_280, height: 720, devicePixelRatio: 1 }), GUIDE_MINIMUM_COMPLETE_ROW_FLOOR);
});

test('Guide Auto chooses the largest readable treatment meeting its floor and reports undersized grids honestly', () => {
  const fourK = resolveGuideRowDensity('auto', { width: 3_840, height: 2_160, devicePixelRatio: 1 });
  assert.equal(fourK.effective, 'comfortable');
  assert.equal(fourK.completeRows, 20);
  assert.equal(fourK.minimumCompleteRows, 20);
  assert.equal(fourK.floorMet, true);

  const scaled1080 = resolveGuideRowDensity('auto', { width: 1_536, height: 864, devicePixelRatio: 1.25 });
  assert.equal(scaled1080.effective, 'comfortable');
  assert.equal(scaled1080.minimumCompleteRows, 5);
  assert.equal(scaled1080.floorMet, true);

  const hd720 = resolveGuideRowDensity('auto', { width: 1_280, height: 720, devicePixelRatio: 1 });
  assert.equal(hd720.effective, 'comfortable');
  assert.ok(hd720.completeRows >= 5);

  const narrowHighDpi = resolveGuideRowDensity('auto', { width: 1_280, height: 500, devicePixelRatio: 1.5 }, 12);
  assert.equal(narrowHighDpi.effective, 'compact');
  assert.equal(narrowHighDpi.floorMet, true);

  const undersized = resolveGuideRowDensity(
    'auto',
    { width: 3_840, height: 2_160, availableHeight: 300, devicePixelRatio: 1 },
    12,
  );
  assert.equal(undersized.effective, 'compact');
  assert.equal(undersized.completeRows, 3);
  assert.equal(undersized.minimumCompleteRows, 20);
  assert.equal(undersized.floorMet, false);

  const rowRegion = { width: 1_280, height: 720, availableHeight: 420, devicePixelRatio: 1 } as const;
  const comfortableRowRegion = resolveGuideRowDensity('comfortable', rowRegion, 16);
  assert.equal(comfortableRowRegion.completeRows, 3);
  assert.equal(comfortableRowRegion.floorMet, false);
  const autoRowRegion = resolveGuideRowDensity('auto', rowRegion, 16);
  assert.equal(autoRowRegion.effective, 'compact');
  assert.equal(autoRowRegion.completeRows, 4);
  assert.equal(autoRowRegion.minimumCompleteRows, 5);
  assert.equal(autoRowRegion.floorMet, false);

  const fourKRowRegion = resolveGuideRowDensity(
    'auto',
    { width: 3_840, height: 2_160, availableHeight: 2_400, devicePixelRatio: 1 },
    12,
  );
  assert.equal(fourKRowRegion.effective, 'comfortable');
  assert.equal(fourKRowRegion.completeRows, 20);
  assert.equal(fourKRowRegion.floorMet, true);

  const hdRowRegion = resolveGuideRowDensity(
    'auto',
    { width: 1_920, height: 1_080, availableHeight: 948, devicePixelRatio: 1 },
    12,
  );
  assert.equal(hdRowRegion.effective, 'comfortable');
  assert.equal(hdRowRegion.completeRows, 8);
  assert.equal(hdRowRegion.floorMet, true);

  for (const availableHeight of [0, -1, Number.NaN]) {
    const unmeasured = resolveGuideRowDensity(
      'auto',
      { width: 1_280, height: 500, availableHeight, devicePixelRatio: 1 },
      12,
    );
    assert.equal(unmeasured.effective, 'comfortable', `${String(availableHeight)} is not a measured row region`);
  }
  assert.equal(resolveGuideRowDensity(
    'auto',
    { width: 1_280, height: 500, availableHeight: 300, devicePixelRatio: 1 },
    12,
  ).effective, 'compact', 'a positive finite row region participates in Auto density');
});

test('Guide density-only settings do not retain focus or notify Guide refresh settlement', async () => {
  let current: GuideSettingsValues = {
    guideTimeRange: 'wide' as const,
    guidePerformanceProfile: 'auto' as const,
    guideRowDensity: 'auto' as const,
    guideLayout: 'classic' as const,
  };
  let notes = 0;
  let retained = 0;
  let restored = 0;
  const invalidations: string[] = [];
  const reconciliations: boolean[] = [];
  const owner = createSettingsGuideSettingsSettlementOwner({
    getCurrentSettings: () => current,
    getPolling: () => ({
      hasPendingGuideSettingsChange: () => false,
      noteGuideSettingsChange: () => { notes += 1; },
      settleGuideSettings: async () => undefined,
    }),
    retainGuideProgramFocusIntent: () => { retained += 1; },
    restorePendingGuideFocus: () => { restored += 1; },
    invalidateViewportLayout: () => { invalidations.push('invalidate'); },
    reconcileViewport: (allowRefresh) => { reconciliations.push(allowRefresh); },
  });
  const pending = owner.begin(
    { ...current, guideRowDensity: 'compact' },
    () => { current = { ...current, guideRowDensity: 'compact' }; },
  );
  await pending.finish(false);
  assert.equal(notes, 0);
  assert.equal(retained, 0);
  assert.equal(restored, 0);
  assert.deepEqual(invalidations, ['invalidate']);
  assert.deepEqual(reconciliations, [false]);

  const layout = owner.begin(
    { ...current, guideLayout: 'overlay' },
    () => { current = { ...current, guideLayout: 'overlay' }; },
  );
  await layout.finish(false);
  assert.deepEqual(invalidations, ['invalidate', 'invalidate']);
  assert.deepEqual(reconciliations, [false, true]);
});

test('Guide presentation settlement retains and restores only the pending presentation focus intent', async () => {
  let current: GuideSettingsValues = {
    guideTimeRange: 'wide' as const,
    guidePerformanceProfile: 'auto' as const,
    guideRowDensity: 'auto' as const,
    guideLayout: 'classic' as const,
  };
  let pendingGuideChange = false;
  let notes = 0;
  let retained = 0;
  let restored = 0;
  const owner = createSettingsGuideSettingsSettlementOwner({
    getCurrentSettings: () => current,
    getPolling: () => ({
      hasPendingGuideSettingsChange: () => pendingGuideChange,
      noteGuideSettingsChange: () => { notes += 1; pendingGuideChange = true; },
      settleGuideSettings: async () => undefined,
    }),
    retainGuideProgramFocusIntent: () => { retained += 1; },
    restorePendingGuideFocus: () => { restored += 1; },
    invalidateViewportLayout: () => undefined,
    reconcileViewport: () => undefined,
  });

  const presentationChange = owner.begin(
    { ...current, guideTimeRange: 'detailed' },
    () => { current = { ...current, guideTimeRange: 'detailed' }; },
  );
  assert.equal(notes, 1);
  assert.equal(retained, 1);

  const densityChange = owner.begin(
    { ...current, guideRowDensity: 'compact' },
    () => { current = { ...current, guideRowDensity: 'compact' }; },
  );
  await presentationChange.finish(true);
  await densityChange.finish(false);
  assert.equal(notes, 1);
  assert.equal(retained, 1);
  assert.equal(restored, 1);
});
