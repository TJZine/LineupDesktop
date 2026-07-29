import test from 'node:test';
import assert from 'node:assert/strict';

import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';

const safeEvent = {
  surface: 'main' as const,
  category: 'playback' as const,
  severity: 'debug' as const,
  status: 'observed' as const,
  operation: 'settings.policy',
  message: 'Fixed-schema settings diagnostic.',
  result: 'ignored' as const,
  context: { reason: 'fixed-reason', count: 1 },
};

test('settings diagnostics admission gates only additional debug families', () => {
  const store = new DiagnosticEventStore();
  assert.equal(store.recordSettingsDebug(safeEvent), null);
  assert.equal(store.recordSubtitleDebug(safeEvent), null);

  store.setSettingsAdmission({
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: false,
  });
  assert.ok(store.recordSettingsDebug(safeEvent));
  assert.equal(store.recordSubtitleDebug(safeEvent), null);

  store.setSettingsAdmission({
    debugLoggingEnabled: true,
    subtitleDebugLoggingEnabled: true,
  });
  assert.ok(store.recordSubtitleDebug(safeEvent));
  assert.equal(store.getRecords().length, 2);
});

test('settings diagnostics admission never suppresses existing warnings, errors, or cleanup', () => {
  const store = new DiagnosticEventStore();
  store.setSettingsAdmission({
    debugLoggingEnabled: false,
    subtitleDebugLoggingEnabled: false,
  });
  store.record({
    ...safeEvent,
    category: 'cleanup',
    severity: 'error',
    status: 'failed',
    operation: 'helper.cleanup',
    message: 'Player helper cleanup failed.',
    result: 'failure',
  });
  assert.equal(store.getRecords().length, 1);
  assert.equal(store.getRecords()[0]?.category, 'cleanup');
});
