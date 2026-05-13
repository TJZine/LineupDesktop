import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import {
  DIAGNOSTIC_TRUNCATION_LIMITS,
  type RedactionScanReport,
} from '../../../contracts/diagnostics.js';
import { DiagnosticEventStore } from '../../../main/diagnostics/diagnosticEventStore.js';
import {
  SupportBundleExporter,
  type SupportBundleRedactionScannerOptions,
} from '../../../main/diagnostics/supportBundleExporter.js';
import { SUPPORT_BUNDLE_DIRECTORY_PREFIX } from '../../../main/diagnostics/supportBundlePaths.js';

test('diagnostic event store bounds records and serializes only sanitized records', () => {
  const store = new DiagnosticEventStore({
    maxRecords: 3,
    clock: () => 1234,
    idGenerator: createIdGenerator('diag'),
  });
  const unsafePath = ['/Users/example/Library/Application', 'Support/Lineup/media.mkv'].join(' ');
  const unsafeNativeKey = [['native', 'Handle'].join(''), '987654321'].join(' ');

  for (let index = 0; index < 5; index += 1) {
    store.record({
      surface: 'main',
      category: 'lifecycle',
      severity: 'info',
      status: 'observed',
      operation: `operation-${String(index)}`,
      message: `message ${unsafePath} ${['p', 'id'].join('')} 12345`,
      context: {
        safe: 'value',
        path: unsafePath,
        [unsafeNativeKey]: 'unsafe-key',
      },
    });
  }

  const records = store.getRecords();
  assert.equal(records.length, 3);
  assert.deepEqual(records.map((record) => record.operation), ['operation-2', 'operation-3', 'operation-4']);
  const serialized = store.serializeNdjson();
  assert.equal(serialized.includedRecordCount, 3);
  assert.equal(serialized.content.includes('Support/Lineup/media.mkv'), false);
  assert.equal(serialized.content.includes('12345'), false);
  assert.equal(serialized.content.includes('987654321'), false);
  assert.equal(serialized.content.includes('"path"'), false);
  assert.equal(store.getSummary().recordCount, 3);
  assert.equal(store.getSummary().surfaceCounts.main, 3);
});

test('diagnostic event store hard-caps retention at the RD-17 limit', () => {
  const store = new DiagnosticEventStore({
    maxRecords: 1000,
    idGenerator: createIdGenerator('cap'),
  });

  for (let index = 0; index < DIAGNOSTIC_TRUNCATION_LIMITS.storeRecords + 100; index += 1) {
    store.record({
      surface: 'main',
      category: 'unknown',
      severity: 'info',
      status: 'observed',
      operation: `operation-${String(index)}`,
      message: 'bounded retention',
    });
  }

  const records = store.getRecords(1000);
  assert.equal(records.length, DIAGNOSTIC_TRUNCATION_LIMITS.storeRecords);
  assert.equal(store.getSummary().recordCount, DIAGNOSTIC_TRUNCATION_LIMITS.storeRecords);
  assert.equal(records[0]?.operation, 'operation-100');
});

test('support bundle exporter creates required files under a new child directory with safe result', async () => {
  const parentDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-support-bundle-'));
  const store = new DiagnosticEventStore({
    clock: () => 1000,
    idGenerator: createIdGenerator('record'),
  });
  store.record({
    surface: 'main',
    category: 'support-bundle-export',
    severity: 'info',
    status: 'started',
    operation: 'support-bundle.export',
    message: 'Export started.',
    requestId: 'request-1',
    context: { count: 1 },
  });

  const exporter = new SupportBundleExporter({
    eventStore: store,
    parentDirectoryProvider: () => parentDirectory,
    redactionScanner: scanDirectoryForTest,
    clock: () => 2000,
    bundleIdGenerator: () => 'bundle-1',
    appVersion: 'test-version',
    platformFamily: 'test-platform',
    shellMode: 'test-shell',
    crashRecoveryProvider: () => createUnsafeProviderSummary(),
    environmentProvider: () => createUnsafeProviderSummary(),
    playerSnapshotProvider: () => createUnsafePlayerSnapshot(),
  });

  const result = await exporter.exportSupportBundle();

  assert.equal(result.status, 'succeeded');
  assert.equal(result.bundleDirectoryName, `${SUPPORT_BUNDLE_DIRECTORY_PREFIX}bundle-1`);
  assert.equal(result.bundleId, 'bundle-1');
  assert.equal(result.createdAtMs, 2000);
  assert.equal(result.fileCount, 6);
  assert.deepEqual([...result.includedFiles].sort(), [
    'crash-recovery.json',
    'diagnostics.ndjson',
    'environment.json',
    'manifest.json',
    'player-snapshot.json',
    'redaction-report.json',
  ]);
  assert.equal(result.redactionReport.status, 'passed');
  assert.equal(result.redactionReport.scannedFileCount, 6);
  assert.equal(JSON.stringify(result).includes(parentDirectory), false);

  const bundleDirectory = path.join(parentDirectory, result.bundleDirectoryName);
  const fileNames = (await fs.readdir(bundleDirectory)).sort();
  assert.deepEqual(fileNames, [...result.includedFiles].sort());
  const manifest = JSON.parse(await fs.readFile(path.join(bundleDirectory, 'manifest.json'), 'utf8')) as {
    bundleId: string;
    includedFiles: readonly string[];
    explicitOmissions: readonly string[];
  };
  assert.equal(manifest.bundleId, 'bundle-1');
  assert.equal(manifest.includedFiles.includes('diagnostics.ndjson'), true);
  assert.equal(manifest.explicitOmissions.includes('absolute paths'), true);
  const diagnostics = await fs.readFile(path.join(bundleDirectory, 'diagnostics.ndjson'), 'utf8');
  assert.equal(diagnostics.split('\n').filter(Boolean).length, 1);
  for (const fileName of ['crash-recovery.json', 'environment.json', 'player-snapshot.json']) {
    const content = await fs.readFile(path.join(bundleDirectory, fileName), 'utf8');
    assert.equal(content.includes('12345'), false);
    assert.equal(content.includes('987654321'), false);
    assert.equal(content.includes('Support/Lineup/media.mkv'), false);
    assert.equal(content.includes('credential12345'), false);
    assert.match(content, /\[redacted\]/u);
  }
  assert.equal(store.getSummary().lastExportStatus, 'succeeded');
});

test('support bundle exporter cleans up and returns safe failure when redaction scan fails', async () => {
  const parentDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-support-bundle-fail-'));
  const store = new DiagnosticEventStore({
    clock: () => 1000,
    idGenerator: createIdGenerator('record'),
  });
  const failingReport = createScanReport('failed');
  const exporter = new SupportBundleExporter({
    eventStore: store,
    parentDirectoryProvider: () => parentDirectory,
    redactionScanner: () => failingReport,
    clock: () => 2000,
    bundleIdGenerator: () => 'scan-failure',
  });

  const result = await exporter.exportSupportBundle();

  assert.equal(result.status, 'failed');
  assert.equal(result.error.code, 'DIAGNOSTICS_REDACTION_FAILED');
  assert.equal(result.redactionReport?.status, 'failed');
  assert.equal(JSON.stringify(result).includes(parentDirectory), false);
  await assert.rejects(
    fs.stat(path.join(parentDirectory, `${SUPPORT_BUNDLE_DIRECTORY_PREFIX}scan-failure`)),
    { code: 'ENOENT' },
  );
  assert.equal(store.getSummary().lastExportStatus, 'failed');
  assert.equal(store.getSummary().redactionFailureCount, 1);
});

test('support bundle exporter returns a safe cancellation envelope without creating a directory', async () => {
  const store = new DiagnosticEventStore();
  const exporter = new SupportBundleExporter({
    eventStore: store,
    parentDirectoryProvider: () => null,
    redactionScanner: () => createScanReport('passed'),
    bundleIdGenerator: () => 'unused',
  });

  const result = await exporter.exportSupportBundle();

  assert.equal(result.status, 'cancelled');
  assert.equal(result.error.code, 'DIAGNOSTICS_EXPORT_CANCELLED');
  assert.equal(store.getSummary().lastExportStatus, 'cancelled');
});

test('support bundle exporter wraps parent provider failures in a safe envelope', async () => {
  const unsafePath = ['/Users/example/Library/Application', 'Support/Lineup/media.mkv'].join(' ');
  const store = new DiagnosticEventStore();
  const exporter = new SupportBundleExporter({
    eventStore: store,
    parentDirectoryProvider: () => {
      throw new Error(`failed at ${unsafePath}`);
    },
    redactionScanner: () => createScanReport('passed'),
    bundleIdGenerator: () => 'unused',
  });

  const result = await exporter.exportSupportBundle();

  assert.equal(result.status, 'failed');
  assert.equal(result.error.code, 'DIAGNOSTICS_EXPORT_FAILED');
  assert.equal(JSON.stringify(result).includes('Support/Lineup/media.mkv'), false);
  assert.equal(store.getSummary().lastExportStatus, 'failed');
});

test('support bundle exporter wraps bad target and id generation in a safe envelope', async () => {
  const parentDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-support-bundle-target-'));
  const cases: ReadonlyArray<{
    name: string;
    parentDirectoryProvider: () => string;
    bundleIdGenerator: () => string;
  }> = [
    {
      name: 'bad-parent',
      parentDirectoryProvider: () => '',
      bundleIdGenerator: () => 'unused',
    },
    {
      name: 'bad-id',
      parentDirectoryProvider: () => parentDirectory,
      bundleIdGenerator: () => {
        throw new Error(`${['native', 'Handle'].join('')} 987654321`);
      },
    },
  ];

  for (const testCase of cases) {
    const store = new DiagnosticEventStore();
    const exporter = new SupportBundleExporter({
      eventStore: store,
      parentDirectoryProvider: testCase.parentDirectoryProvider,
      redactionScanner: () => createScanReport('passed'),
      bundleIdGenerator: testCase.bundleIdGenerator,
    });

    const result = await exporter.exportSupportBundle();

    assert.equal(result.status, 'failed', testCase.name);
    assert.equal(result.error.code, 'DIAGNOSTICS_EXPORT_FAILED', testCase.name);
    assert.equal(JSON.stringify(result).includes('987654321'), false, testCase.name);
    assert.equal(JSON.stringify(result).includes(parentDirectory), false, testCase.name);
    assert.equal(store.getSummary().lastExportStatus, 'failed', testCase.name);
  }
});

test('support bundle exporter does not expose filesystem failure paths with spaces', async () => {
  const parentDirectory = ['/Users/example/Library/Application', 'Support/Lineup Selected Folder'].join(' ');
  const targetDirectory = path.join(parentDirectory, `${SUPPORT_BUNDLE_DIRECTORY_PREFIX}mkdir-failure`);
  const store = new DiagnosticEventStore();
  const exporter = new SupportBundleExporter({
    eventStore: store,
    parentDirectoryProvider: () => parentDirectory,
    redactionScanner: () => createScanReport('passed'),
    bundleIdGenerator: () => 'mkdir-failure',
    fileSystem: {
      mkdir: async () => {
        throw new Error(`mkdir failed at ${targetDirectory}`);
      },
      writeFile: async () => {
        throw new Error('write should not run');
      },
      rm: async () => undefined,
    },
  });

  const result = await exporter.exportSupportBundle();
  const serializedFailure = JSON.stringify(result);

  assert.equal(result.status, 'failed');
  assert.equal(result.error.code, 'DIAGNOSTICS_EXPORT_FAILED');
  assert.equal(serializedFailure.includes(parentDirectory), false);
  assert.equal(serializedFailure.includes(targetDirectory), false);
  assert.equal(serializedFailure.includes('Application Support'), false);
  assert.equal(serializedFailure.includes('Lineup Selected Folder'), false);
  assert.equal(serializedFailure.includes('example'), false);
  assert.equal(serializedFailure.includes('mkdir-failure'), false);
  assert.equal(store.getSummary().lastExportStatus, 'failed');
});

test('support bundle exporter never merges into an existing target directory', async () => {
  const parentDirectory = await fs.mkdtemp(path.join(os.tmpdir(), 'lineup-support-bundle-existing-'));
  await fs.mkdir(path.join(parentDirectory, `${SUPPORT_BUNDLE_DIRECTORY_PREFIX}existing`));
  const store = new DiagnosticEventStore();
  const exporter = new SupportBundleExporter({
    eventStore: store,
    parentDirectoryProvider: () => parentDirectory,
    redactionScanner: () => createScanReport('passed'),
    bundleIdGenerator: () => 'existing',
  });

  const result = await exporter.exportSupportBundle();

  assert.equal(result.status, 'failed');
  assert.equal(result.error.code, 'DIAGNOSTICS_EXPORT_FAILED');
  assert.equal(JSON.stringify(result).includes(parentDirectory), false);
  assert.deepEqual(await fs.readdir(path.join(parentDirectory, `${SUPPORT_BUNDLE_DIRECTORY_PREFIX}existing`)), []);
});

test('diagnostic ndjson serialization reports records omitted by byte limit', () => {
  const store = new DiagnosticEventStore({
    maxRecords: DIAGNOSTIC_TRUNCATION_LIMITS.storeRecords,
    idGenerator: createIdGenerator('byte-limit'),
  });
  for (let index = 0; index < 10; index += 1) {
    store.record({
      surface: 'main',
      category: 'unknown',
      severity: 'info',
      status: 'observed',
      operation: 'large-record',
      message: 'x'.repeat(DIAGNOSTIC_TRUNCATION_LIMITS.messageCharacters),
    });
  }

  const serialized = store.serializeNdjson(2);

  assert.equal(serialized.includedRecordCount, 2);
  assert.equal(serialized.truncatedRecordCount, 8);
});

function createIdGenerator(prefix: string): () => string {
  let counter = 0;
  return () => {
    counter += 1;
    return `${prefix}-${String(counter)}`;
  };
}

function createUnsafeProviderSummary(): Record<string, unknown> {
  const processKey = ['p', 'id'].join('');
  const nativeKey = ['native', 'Handle'].join('');
  return {
    [processKey]: 12345,
    [nativeKey]: 987654321,
    path: ['/Users/example/Library/Application', 'Support/Lineup/media.mkv'].join(' '),
    secret: ['credential', '12345'].join(''),
    safeStatus: 'failed',
  };
}

function createUnsafePlayerSnapshot() {
  const processKey = ['p', 'id'].join('');
  const nativeKey = ['native', 'Handle'].join('');
  return {
    requestId: null,
    status: 'idle',
    media: null,
    capabilityProfileId: null,
    positionMs: 0,
    durationMs: null,
    bufferedRanges: [],
    playing: false,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    lastError: null,
    [processKey]: 12345,
    [nativeKey]: 987654321,
    mediaPath: ['/Users/example/Library/Application', 'Support/Lineup/media.mkv'].join(' '),
    credential: ['credential', '12345'].join(''),
  } as const;
}

async function scanDirectoryForTest(
  root: string,
  options: SupportBundleRedactionScannerOptions,
): Promise<RedactionScanReport> {
  const fileNames = await fs.readdir(root);
  let scannedByteCount = 0;
  for (const fileName of fileNames) {
    scannedByteCount += (await fs.stat(path.join(root, fileName))).size;
  }
  return {
    redactionVersion: 'rd17-redaction-v1',
    scannedFileCount: fileNames.length,
    scannedByteCount,
    findingCount: 0,
    findingsByLabel: {},
    truncatedRecordCount: options.truncatedRecordCount,
    omittedFileCount: options.omittedFileCount,
    status: 'passed',
    timestampMs: options.timestampMs,
  };
}

function createScanReport(status: RedactionScanReport['status']): RedactionScanReport {
  return {
    redactionVersion: 'rd17-redaction-v1',
    scannedFileCount: 6,
    scannedByteCount: 100,
    findingCount: status === 'passed' ? 0 : 1,
    findingsByLabel: status === 'passed' ? {} : { 'raw-filesystem-path': 1 },
    truncatedRecordCount: 0,
    omittedFileCount: 0,
    status,
    timestampMs: 1000,
  };
}
