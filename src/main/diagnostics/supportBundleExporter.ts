import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import {
  DIAGNOSTIC_REDACTION_VERSION,
  DIAGNOSTIC_SCHEMA_VERSION,
  SUPPORT_BUNDLE_SCHEMA_VERSION,
  type DiagnosticContextValue,
  type DiagnosticsError,
  type RedactionScanReport,
  type SupportBundleExportFailure,
  type SupportBundleExportResult,
  isDiagnosticForbiddenFieldKey,
  redactDiagnosticText,
} from '../../contracts/diagnostics.js';
import type { PlayerSnapshot } from '../../contracts/player.js';
import type { DiagnosticEventStore, SerializedDiagnosticRecords } from './diagnosticEventStore.js';
import { createSupportBundleId, createSupportBundleTarget } from './supportBundlePaths.js';

export interface SupportBundleExporterOptions {
  eventStore: DiagnosticEventStore;
  parentDirectoryProvider: () => Promise<string | null> | string | null;
  redactionScanner: SupportBundleRedactionScanner;
  fileSystem?: SupportBundleFileSystem;
  clock?: () => number;
  bundleIdGenerator?: (createdAtMs: number) => string;
  appVersion?: string;
  platformFamily?: string;
  shellMode?: string;
  playerSnapshotProvider?: () => PlayerSnapshot | null | Promise<PlayerSnapshot | null>;
  crashRecoveryProvider?: () => unknown | Promise<unknown>;
  environmentProvider?: () => unknown | Promise<unknown>;
}

export interface SupportBundleFileSystem {
  mkdir(directoryPath: string, options: { recursive: false; mode: number }): Promise<void>;
  writeFile(filePath: string, content: string, options: { encoding: 'utf8'; mode: number }): Promise<void>;
  rm(directoryPath: string, options: { recursive: true; force: true }): Promise<void>;
}

export interface SupportBundleRedactionScannerOptions {
  truncatedRecordCount: number;
  omittedFileCount: number;
  timestampMs: number;
}

export type SupportBundleRedactionScanner = (
  bundleDirectoryPath: string,
  options: SupportBundleRedactionScannerOptions,
) => Promise<RedactionScanReport> | RedactionScanReport;

type SupportBundleExportOutcome = SupportBundleExportResult | SupportBundleExportFailure;

const REQUIRED_BUNDLE_FILES = [
  'manifest.json',
  'diagnostics.ndjson',
  'crash-recovery.json',
  'player-snapshot.json',
  'environment.json',
  'redaction-report.json',
] as const;

const TEXT_ENCODER = new TextEncoder();

export class SupportBundleExporter {
  readonly #options: SupportBundleExporterOptions;
  readonly #fileSystem: SupportBundleFileSystem;
  readonly #clock: () => number;
  readonly #bundleIdGenerator: (createdAtMs: number) => string;

  public constructor(options: SupportBundleExporterOptions) {
    this.#options = options;
    this.#fileSystem = options.fileSystem ?? NODE_SUPPORT_BUNDLE_FILE_SYSTEM;
    this.#clock = options.clock ?? Date.now;
    this.#bundleIdGenerator = options.bundleIdGenerator ?? ((createdAtMs) => createSupportBundleId(createdAtMs));
  }

  public async exportSupportBundle(): Promise<SupportBundleExportOutcome> {
    const createdAtMs = normalizeTimestamp(this.#clock());
    const targetResult = await this.createExportTarget(createdAtMs);
    if (targetResult.status !== 'ready') {
      this.#options.eventStore.recordExportStatus(targetResult.status);
      return targetResult;
    }

    const target = targetResult.target;
    const diagnostics = this.#options.eventStore.serializeNdjson();
    let createdTarget = false;

    try {
      await this.#fileSystem.mkdir(target.bundleDirectoryPath, { recursive: false, mode: 0o700 });
      createdTarget = true;
      const files = await this.createBundleFiles({
        bundleId: target.bundleId,
        createdAtMs,
        diagnostics,
      });
      await this.writeBundleFiles(target.bundleDirectoryPath, files);

      const preliminaryReport = await this.scanBundle(target.bundleDirectoryPath, diagnostics, createdAtMs);
      if (preliminaryReport.status === 'failed') {
        await this.cleanupBundle(target.bundleDirectoryPath);
        this.#options.eventStore.recordExportStatus('failed', preliminaryReport);
        return createExportFailure(
          'failed',
          'DIAGNOSTICS_REDACTION_FAILED',
          'Support bundle redaction scan failed.',
          preliminaryReport,
        );
      }

      const redactionReportContent = stringifyBundleJson(preliminaryReport);
      await this.#fileSystem.writeFile(
        path.join(target.bundleDirectoryPath, 'redaction-report.json'),
        redactionReportContent,
        { encoding: 'utf8', mode: 0o600 },
      );
      files.set('redaction-report.json', redactionReportContent);

      const finalReport = await this.scanBundle(target.bundleDirectoryPath, diagnostics, createdAtMs);
      if (finalReport.status === 'failed') {
        await this.cleanupBundle(target.bundleDirectoryPath);
        this.#options.eventStore.recordExportStatus('failed', finalReport);
        return createExportFailure(
          'failed',
          'DIAGNOSTICS_REDACTION_FAILED',
          'Support bundle redaction scan failed.',
          finalReport,
        );
      }

      const finalReportContent = stringifyBundleJson(finalReport);
      await this.#fileSystem.writeFile(
        path.join(target.bundleDirectoryPath, 'redaction-report.json'),
        finalReportContent,
        { encoding: 'utf8', mode: 0o600 },
      );
      files.set('redaction-report.json', finalReportContent);

      this.#options.eventStore.recordExportStatus('succeeded', finalReport);
      return {
        status: 'succeeded',
        bundleId: target.bundleId,
        bundleDirectoryName: target.bundleDirectoryName,
        createdAtMs,
        fileCount: REQUIRED_BUNDLE_FILES.length,
        byteCount: [...files.values()].reduce((total, content) => total + byteLength(content), 0),
        includedFiles: REQUIRED_BUNDLE_FILES,
        redactionReport: finalReport,
      };
    } catch {
      if (createdTarget) {
        await this.cleanupBundle(target.bundleDirectoryPath);
      }
      this.#options.eventStore.recordExportStatus('failed');
      return createExportFailure(
        'failed',
        'DIAGNOSTICS_EXPORT_FAILED',
        'Support bundle export failed.',
      );
    }
  }

  private async createExportTarget(createdAtMs: number): Promise<
    | { status: 'ready'; target: ReturnType<typeof createSupportBundleTarget> }
    | SupportBundleExportFailure
  > {
    let parentDirectory: string | null;
    try {
      parentDirectory = await this.#options.parentDirectoryProvider();
    } catch {
      return createExportFailure(
        'failed',
        'DIAGNOSTICS_EXPORT_FAILED',
        'Support bundle export target could not be prepared.',
      );
    }
    if (parentDirectory === null) {
      return createExportFailure('cancelled', 'DIAGNOSTICS_EXPORT_CANCELLED', 'Support bundle export was cancelled.');
    }
    if (typeof parentDirectory !== 'string') {
      return createExportFailure(
        'failed',
        'DIAGNOSTICS_EXPORT_FAILED',
        'Support bundle export target could not be prepared.',
      );
    }
    try {
      return {
        status: 'ready',
        target: createSupportBundleTarget(parentDirectory, this.#bundleIdGenerator(createdAtMs)),
      };
    } catch {
      return createExportFailure(
        'failed',
        'DIAGNOSTICS_EXPORT_FAILED',
        'Support bundle export target could not be prepared.',
      );
    }
  }

  private async createBundleFiles(input: {
    bundleId: string;
    createdAtMs: number;
    diagnostics: SerializedDiagnosticRecords;
  }): Promise<Map<string, string>> {
    const records = this.#options.eventStore.getRecords();
    const files = new Map<string, string>();
    const includedSurfaces = [...new Set(records.map((record) => record.surface))].sort();
    files.set('manifest.json', stringifyBundleJson({
      schemaVersion: SUPPORT_BUNDLE_SCHEMA_VERSION,
      diagnosticsSchemaVersion: DIAGNOSTIC_SCHEMA_VERSION,
      bundleId: input.bundleId,
      createdAtMs: input.createdAtMs,
      appVersion: redactDiagnosticText(this.#options.appVersion ?? '0.0.0'),
      platformFamily: redactDiagnosticText(this.#options.platformFamily ?? process.platform),
      shellMode: redactDiagnosticText(this.#options.shellMode ?? 'desktop'),
      redactionVersion: DIAGNOSTIC_REDACTION_VERSION,
      includedSurfaces,
      includedFiles: REQUIRED_BUNDLE_FILES,
      explicitOmissions: [
        'raw logs',
        'crash dumps',
        'environment variables',
        'process arguments',
        'absolute paths',
        'auth headers',
        'tokens',
        'native handles',
        'raw IPC frames',
      ],
    }));
    files.set('diagnostics.ndjson', input.diagnostics.content);
    files.set('crash-recovery.json', stringifyBundleJson(
      sanitizeBundleValue(await getOptionalValue(this.#options.crashRecoveryProvider, createInertCrashRecoverySummary())),
    ));
    files.set('player-snapshot.json', stringifyBundleJson(
      sanitizeBundleValue(await getOptionalValue(this.#options.playerSnapshotProvider, createInertPlayerSnapshot())),
    ));
    files.set('environment.json', stringifyBundleJson(
      sanitizeBundleValue(await getOptionalValue(this.#options.environmentProvider, createSafeEnvironmentSummary())),
    ));
    files.set('redaction-report.json', stringifyBundleJson(createPendingRedactionReport(input.createdAtMs)));
    return files;
  }

  private async writeBundleFiles(bundleDirectoryPath: string, files: ReadonlyMap<string, string>): Promise<void> {
    for (const [fileName, content] of files) {
      await this.#fileSystem.writeFile(path.join(bundleDirectoryPath, fileName), content, {
        encoding: 'utf8',
        mode: 0o600,
      });
    }
  }

  private async scanBundle(
    bundleDirectoryPath: string,
    diagnostics: SerializedDiagnosticRecords,
    timestampMs: number,
  ): Promise<RedactionScanReport> {
    return this.#options.redactionScanner(bundleDirectoryPath, {
      truncatedRecordCount: diagnostics.truncatedRecordCount,
      omittedFileCount: 0,
      timestampMs,
    });
  }

  private async cleanupBundle(bundleDirectoryPath: string): Promise<void> {
    try {
      await this.#fileSystem.rm(bundleDirectoryPath, { recursive: true, force: true });
    } catch {
      // Export failures must stay renderer-safe; cleanup best-effort is enough here.
    }
  }
}

const NODE_SUPPORT_BUNDLE_FILE_SYSTEM: SupportBundleFileSystem = {
  mkdir: async (directoryPath, options) => {
    await fs.mkdir(directoryPath, options);
  },
  writeFile: async (filePath, content, options) => {
    await fs.writeFile(filePath, content, options);
  },
  rm: async (directoryPath, options) => {
    await fs.rm(directoryPath, options);
  },
};

function createExportFailure(
  status: SupportBundleExportFailure['status'],
  code: DiagnosticsError['code'],
  message: string,
  redactionReport?: RedactionScanReport,
): SupportBundleExportFailure {
  return {
    status,
    error: {
      code,
      message: redactDiagnosticText(message),
      recoverable: true,
      retryable: status === 'failed',
    },
    ...(redactionReport !== undefined ? { redactionReport } : {}),
  };
}

function createPendingRedactionReport(timestampMs: number): RedactionScanReport {
  return {
    redactionVersion: DIAGNOSTIC_REDACTION_VERSION,
    scannedFileCount: 0,
    scannedByteCount: 0,
    findingCount: 0,
    findingsByLabel: {},
    truncatedRecordCount: 0,
    omittedFileCount: 0,
    status: 'passed',
    timestampMs,
  };
}

function stringifyBundleJson(value: unknown): string {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function byteLength(value: string): number {
  return TEXT_ENCODER.encode(value).byteLength;
}

function normalizeTimestamp(value: number): number {
  return Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
}

async function getOptionalValue<T>(provider: (() => T | Promise<T>) | undefined, fallback: T): Promise<T> {
  return provider === undefined ? fallback : provider();
}

function createInertCrashRecoverySummary(): Record<string, DiagnosticContextValue | readonly unknown[]> {
  return {
    schemaVersion: SUPPORT_BUNDLE_SCHEMA_VERSION,
    helperCrashCount: 0,
    helperRestartCount: 0,
    cleanupFailureCount: 0,
    events: [],
  };
}

function createInertPlayerSnapshot(): PlayerSnapshot {
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
  };
}

function createSafeEnvironmentSummary(): Record<string, DiagnosticContextValue> {
  return {
    schemaVersion: SUPPORT_BUNDLE_SCHEMA_VERSION,
    platformFamily: process.platform,
    runtime: 'electron-main',
  };
}

function sanitizeBundleValue(value: unknown, depth = 0): unknown {
  if (depth > 4) {
    return '[redacted]';
  }
  if (
    value === null ||
    typeof value === 'boolean' ||
    typeof value === 'string' ||
    typeof value === 'number'
  ) {
    if (typeof value === 'string') {
      return redactDiagnosticText(value);
    }
    return typeof value === 'number' && !Number.isFinite(value) ? null : value;
  }
  if (Array.isArray(value)) {
    return value.slice(0, 50).map((item) => sanitizeBundleValue(item, depth + 1));
  }
  if (typeof value !== 'object') {
    return null;
  }

  const sanitized: Record<string, unknown> = {};
  for (const [rawKey, rawValue] of Object.entries(value)) {
    const redactedKey = redactDiagnosticText(rawKey);
    const keyWasRedacted = redactedKey.includes('[redacted]');
    const safeKey = redactedKey.trim().replace(/[^A-Za-z0-9._-]/gu, '-');
    const key = safeKey.length > 0 && !keyWasRedacted ? safeKey : 'redacted-field';
    sanitized[dedupeKey(key, sanitized)] = isDiagnosticForbiddenFieldKey(rawKey) || keyWasRedacted
      ? '[redacted]'
      : sanitizeBundleValue(rawValue, depth + 1);
  }
  return sanitized;
}

function dedupeKey(key: string, record: Record<string, unknown>): string {
  if (!Object.hasOwn(record, key)) {
    return key;
  }
  let index = 2;
  while (Object.hasOwn(record, `${key}-${index}`)) {
    index += 1;
  }
  return `${key}-${index}`;
}
