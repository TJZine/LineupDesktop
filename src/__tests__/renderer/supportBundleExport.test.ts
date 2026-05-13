import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DIAGNOSTIC_REDACTION_VERSION,
  type DiagnosticsExportSupportBundleResult,
  type RedactionScanReport,
} from '../../contracts/diagnostics.js';
import { createWorkflowState } from '../../renderer/workflow.js';
import { applySupportBundleExportResult } from '../../renderer/supportBundleExport.js';

test('support bundle export result applies succeeded status through renderer sanitization', async () => {
  const state = await applySupportBundleExportResult(
    createWorkflowState('settings'),
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

test('support bundle export rejection clears exporting state without exposing details', async () => {
  const state = await applySupportBundleExportResult(
    createWorkflowState('settings'),
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
