import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DIAGNOSTIC_REDACTION_VERSION,
  type DiagnosticsExportSupportBundleResult,
  type RedactionScanReport,
} from '../../contracts/diagnostics.js';
import {
  activateWorkflowRoute,
  applyWorkflowSettingsAction,
  createWorkflowState,
} from '../../renderer/workflow.js';
import { applySupportBundleExportResult } from '../../renderer/supportBundleExport.js';

test('support bundle export result applies succeeded status through renderer sanitization', async () => {
  const state = await applySupportBundleExportResult(
    () => createWorkflowState('settings'),
    async (): Promise<DiagnosticsExportSupportBundleResult> => ({
      status: 'succeeded',
      bundleId: 'bundle-1',
      bundleDirectoryName: 'lineup-desktop-support-bundle-1',
      createdAtMs: 1,
      fileCount: 6,
      byteCount: 512,
      includedFiles: ['manifest.json'],
      redactionReport: createReport(),
    }),
  );

  assert.deepEqual(state.settingsDraft.supportBundleExport, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-bundle-1',
    fileCount: 6,
    redactionStatus: 'passed',
  });
});

test('support bundle export result applies to the latest workflow state', async () => {
  let currentState = applyWorkflowSettingsAction(createWorkflowState('settings'), 'exportSupportBundle');
  const pendingExport = createDeferred<DiagnosticsExportSupportBundleResult>();
  const pendingState = applySupportBundleExportResult(
    () => currentState,
    () => pendingExport.promise,
  );

  currentState = activateWorkflowRoute(
    applyWorkflowSettingsAction(currentState, 'cycleGuideDensity'),
    'guide',
  );
  pendingExport.resolve({
    status: 'succeeded',
    bundleId: 'bundle-2',
    bundleDirectoryName: 'lineup-desktop-support-bundle-2',
    createdAtMs: 1,
    fileCount: 6,
    byteCount: 512,
    includedFiles: ['manifest.json'],
    redactionReport: createReport(),
  });

  const state = await pendingState;

  assert.equal(state.routeState.activeRoute, 'guide');
  assert.equal(state.settingsDraft.guideDensity, 'compact');
  assert.deepEqual(state.settingsDraft.supportBundleExport, {
    status: 'succeeded',
    bundleDirectoryName: 'lineup-desktop-support-bundle-2',
    fileCount: 6,
    redactionStatus: 'passed',
  });
});

test('support bundle export rejection clears exporting state without exposing details', async () => {
  const state = await applySupportBundleExportResult(
    () => createWorkflowState('settings'),
    async () => {
      throw new Error('tokenizedUrl=https://secret.example');
    },
  );

  assert.deepEqual(state.settingsDraft.supportBundleExport, {
    status: 'failed',
    bundleDirectoryName: null,
    fileCount: null,
    redactionStatus: null,
  });
  assert.equal(JSON.stringify(state).includes('secret.example'), false);
});

function createDeferred<T>(): {
  promise: Promise<T>;
  resolve(value: T): void;
} {
  let resolvePromise: (value: T) => void = () => undefined;
  const promise = new Promise<T>((resolve) => {
    resolvePromise = resolve;
  });
  return {
    promise,
    resolve: resolvePromise,
  };
}

function createReport(overrides: Partial<RedactionScanReport> = {}): RedactionScanReport {
  return {
    redactionVersion: DIAGNOSTIC_REDACTION_VERSION,
    scannedFileCount: 6,
    scannedByteCount: 512,
    findingCount: 0,
    findingsByLabel: {},
    truncatedRecordCount: 0,
    omittedFileCount: 0,
    status: 'passed',
    timestampMs: 1,
    ...overrides,
  };
}
