import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  DESKTOP_SETTINGS_ERROR_CODES,
  DESKTOP_SETTINGS_ERROR_MESSAGES,
  DESKTOP_SETTINGS_LOAD_STATUSES,
  SETTINGS_INVALID_REQUEST_ID,
  SETTINGS_SCHEMA_VERSION,
  desktopSettingsFailure,
  desktopSettingsSuccess,
  isDesktopSettingsGetSnapshotRequest,
  isDesktopSettingsIpcResult,
  isDesktopSettingsReplaceRequest,
  isDesktopSettingsSnapshot,
  isDesktopSettingsValues,
  readDesktopSettingsRequestId,
} from '../../contracts/settings.js';

const values = { ...DEFAULT_DESKTOP_SETTINGS_VALUES };
const snapshot = { schemaVersion: SETTINGS_SCHEMA_VERSION, revision: 2, status: 'ready' as const, values };

test('settings contract freezes exactly four values, defaults, statuses, and error vocabulary', () => {
  assert.deepEqual(values, {
    launchMode: 'windowed', guideDensity: 'comfortable',
    previewBadgesEnabled: true, setupReminderEnabled: true,
  });
  assert.deepEqual([...DESKTOP_SETTINGS_LOAD_STATUSES], ['ready', 'missing', 'corrupt', 'unsupported-version']);
  assert.deepEqual([...DESKTOP_SETTINGS_ERROR_CODES], [
    'unauthorized', 'validation-failed', 'revision-conflict', 'storage-unavailable',
    'unsupported-version', 'operation-failed',
  ]);
  for (const code of DESKTOP_SETTINGS_ERROR_CODES) {
    const failure = desktopSettingsFailure('settings-1', code);
    assert.equal(failure.ok, false);
    assert.equal(failure.ok ? null : failure.error.message, DESKTOP_SETTINGS_ERROR_MESSAGES[code]);
  }
});

test('settings request and record guards require exact shapes and safe revisions', () => {
  assert.equal(isDesktopSettingsValues(values), true);
  assert.equal(isDesktopSettingsValues({ ...values, extra: true }), false);
  assert.equal(isDesktopSettingsGetSnapshotRequest({ requestId: 'settings-get-1' }), true);
  assert.equal(isDesktopSettingsGetSnapshotRequest({ requestId: 'bad id' }), false);
  assert.equal(isDesktopSettingsReplaceRequest({ requestId: 'settings-replace-1', expectedRevision: 2, values }), true);
  assert.equal(isDesktopSettingsReplaceRequest({ requestId: 'settings-replace-1', expectedRevision: -1, values }), false);
  assert.equal(isDesktopSettingsSnapshot(snapshot), true);
  assert.equal(isDesktopSettingsSnapshot({ ...snapshot, revision: Number.MAX_SAFE_INTEGER + 1 }), false);
  assert.equal(readDesktopSettingsRequestId({ requestId: 'bad id' }), SETTINGS_INVALID_REQUEST_ID);
});

test('settings result guards accept only exact envelopes, fixed messages, and matching safe values', () => {
  assert.equal(isDesktopSettingsIpcResult(desktopSettingsSuccess('settings-1', snapshot), isDesktopSettingsSnapshot), true);
  assert.equal(isDesktopSettingsIpcResult(desktopSettingsFailure('settings-1', 'operation-failed'), isDesktopSettingsSnapshot), true);
  assert.equal(isDesktopSettingsIpcResult({
    ok: false, requestId: 'settings-1',
    error: { code: 'operation-failed', message: 'raw C:\\private\\settings.json' },
  }, isDesktopSettingsSnapshot), false);
});
