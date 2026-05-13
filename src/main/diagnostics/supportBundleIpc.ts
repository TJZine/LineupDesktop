import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

import type { BrowserWindow, IpcMain, IpcMainInvokeEvent } from 'electron';

import {
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
} from '../../contracts/ipc.js';
import {
  DIAGNOSTIC_REDACTION_VERSION,
  DIAGNOSTICS_REQUEST_ID_PATTERN,
  DIAGNOSTICS_RENDERER_EVENT_CATEGORIES,
  DIAGNOSTICS_RENDERER_EVENT_SEVERITIES,
  type DiagnosticsError,
  type DiagnosticsExportSupportBundleResult,
  type DiagnosticsGetSummaryResult,
  type DiagnosticsRecordRendererEventResult,
  type DiagnosticsRendererEventEnvelope,
  type RedactionScanReport,
  containsDiagnosticForbiddenField,
  isDiagnosticForbiddenFieldKey,
  isSafeRendererDiagnosticContextValue,
} from '../../contracts/diagnostics.js';
import type { ShellMode } from '../../contracts/shell.js';
import type { PlayerSnapshot } from '../../contracts/player.js';
import type { DiagnosticEventStore } from './diagnosticEventStore.js';
import { SupportBundleExporter, type SupportBundleRedactionScannerOptions } from './supportBundleExporter.js';

type DiagnosticsIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;

export interface RegisterDiagnosticsIpcHandlersOptions {
  eventStore: DiagnosticEventStore;
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  getShellWindow?: () => BrowserWindow | null;
  parentDirectoryProvider?: () => Promise<string | null> | string | null;
  playerSnapshotProvider?: () => PlayerSnapshot | null | Promise<PlayerSnapshot | null>;
  appVersion?: string;
  ipcMain?: DiagnosticsIpcMain;
}

export type DiagnosticsIpcTeardown = () => void;

const DIAGNOSTICS_IPC_CHANNELS = [
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
] as const;

const SAFE_TEXT_FILE_PATTERN = /\.(json|ndjson|txt)$/u;

export function registerDiagnosticsIpcHandlers(
  options: RegisterDiagnosticsIpcHandlersOptions,
): DiagnosticsIpcTeardown {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();

  ipcMain.handle(
    LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
    (event, payload: unknown): DiagnosticsRecordRendererEventResult => {
      const requestId = getDiagnosticsRequestId(payload) ?? options.createRequestId('diagnostics-event');
      if (!options.isAuthorizedEvent(event)) {
        return diagnosticsFailure(requestId, unauthorizedError('Renderer diagnostic event is not authorized.'));
      }
      if (!isDiagnosticsRendererEventEnvelope(payload)) {
        recordRejectedRendererEvent(options.eventStore, requestId);
        return diagnosticsFailure(
          requestId,
          validationError('Renderer diagnostic event payload is invalid.'),
        );
      }

      const record = options.eventStore.record({
        surface: 'renderer',
        category: payload.event.category,
        severity: payload.event.severity,
        status: 'observed',
        operation: payload.event.operation,
        message: payload.event.message,
        requestId: payload.requestId,
        context: payload.event.context,
      });
      return diagnosticsSuccess(payload.requestId, record);
    },
  );

  ipcMain.handle(
    LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
    (event, ...args: unknown[]): DiagnosticsGetSummaryResult => {
      const requestId = options.createRequestId('diagnostics-summary');
      if (!options.isAuthorizedEvent(event)) {
        return diagnosticsFailure(requestId, unauthorizedError('Diagnostics summary request is not authorized.'));
      }
      if (args.length > 0) {
        return diagnosticsFailure(requestId, validationError('Diagnostics summary request payload is invalid.'));
      }
      return diagnosticsSuccess(requestId, options.eventStore.getSummary());
    },
  );

  ipcMain.handle(
    LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
    async (event, ...args: unknown[]): Promise<DiagnosticsExportSupportBundleResult> => {
      if (!options.isAuthorizedEvent(event)) {
        return exportFailure('failed', unauthorizedError('Support bundle export is not authorized.'));
      }
      if (args.length > 0) {
        options.eventStore.record({
          surface: 'support-bundle',
          category: 'security-boundary',
          severity: 'warning',
          status: 'rejected',
          operation: 'support-bundle.export',
          message: 'Support bundle export rejected renderer-supplied payload.',
          result: 'failure',
        });
        return exportFailure('failed', validationError('Support bundle export request payload is invalid.'));
      }

      options.eventStore.record({
        surface: 'support-bundle',
        category: 'support-bundle-export',
        severity: 'info',
        status: 'started',
        operation: 'support-bundle.export',
        message: 'Support bundle export started.',
      });

      const exporter = new SupportBundleExporter({
        eventStore: options.eventStore,
        parentDirectoryProvider:
          options.parentDirectoryProvider ?? createDialogParentDirectoryProvider(options),
        redactionScanner: scanSupportBundleDirectory,
        appVersion: options.appVersion,
        platformFamily: process.platform,
        shellMode: options.shellMode,
        playerSnapshotProvider: options.playerSnapshotProvider,
        crashRecoveryProvider: () => options.eventStore.getCrashRecoverySummary(),
        environmentProvider: () => ({
          platformFamily: process.platform,
          shellMode: options.shellMode,
          appVersion: options.appVersion ?? '0.0.0',
        }),
      });
      const result = await exporter.exportSupportBundle();
      options.eventStore.record({
        surface: 'support-bundle',
        category: 'support-bundle-export',
        severity: result.status === 'succeeded' ? 'info' : result.status === 'cancelled' ? 'warning' : 'error',
        status: result.status,
        operation: 'support-bundle.export',
        message: `Support bundle export ${result.status}.`,
        result: result.status === 'succeeded' ? 'success' : result.status === 'cancelled' ? 'cancelled' : 'failure',
        context:
          result.status === 'succeeded'
            ? {
                bundleId: result.bundleId,
                bundleDirectoryName: result.bundleDirectoryName,
                fileCount: result.fileCount,
                byteCount: result.byteCount,
                redactionStatus: result.redactionReport.status,
              }
            : { code: result.error.code },
      });
      return result;
    },
  );

  return () => {
    for (const channel of DIAGNOSTICS_IPC_CHANNELS) {
      ipcMain.removeHandler(channel);
    }
  };
}

function isDiagnosticsRendererEventEnvelope(
  value: unknown,
): value is DiagnosticsRendererEventEnvelope {
  if (
    !isPlainRecord(value) ||
    !isNonEmptyString(value.requestId) ||
    !DIAGNOSTICS_REQUEST_ID_PATTERN.test(value.requestId) ||
    containsDiagnosticForbiddenField(value)
  ) {
    return false;
  }
  if (!hasOnlyKeys(value, ['requestId', 'event'])) {
    return false;
  }
  const event = value.event;
  return (
    isPlainRecord(event) &&
    hasOnlyKeys(event, ['surface', 'category', 'severity', 'operation', 'message'], ['context']) &&
    event.surface === 'renderer' &&
    isStringInSet(event.category, DIAGNOSTICS_RENDERER_EVENT_CATEGORIES) &&
    isStringInSet(event.severity, DIAGNOSTICS_RENDERER_EVENT_SEVERITIES) &&
    isNonEmptyString(event.operation) &&
    isNonEmptyString(event.message) &&
    (event.context === undefined || isSafeRendererContext(event.context))
  );
}

function isSafeRendererContext(value: unknown): boolean {
  if (!isPlainRecord(value) || containsDiagnosticForbiddenField(value)) {
    return false;
  }
  return Object.entries(value).every(([key, child]) => {
    return !isDiagnosticForbiddenFieldKey(key) && isDiagnosticContextValue(child);
  });
}

function isDiagnosticContextValue(value: unknown): boolean {
  if (
    value === null ||
    typeof value === 'boolean' ||
    (typeof value === 'number' && Number.isFinite(value))
  ) {
    return true;
  }
  return typeof value === 'string' && isSafeRendererDiagnosticContextValue(value);
}

function recordRejectedRendererEvent(eventStore: DiagnosticEventStore, requestId: string): void {
  eventStore.record({
    surface: 'main',
    category: 'security-boundary',
    severity: 'warning',
    status: 'rejected',
    operation: 'diagnostics.recordRendererEvent',
    message: 'Renderer diagnostic event payload was rejected.',
    requestId,
    result: 'failure',
  });
}

function diagnosticsSuccess<T>(requestId: string, value: T): { ok: true; requestId: string; value: T } {
  return { ok: true, requestId, value };
}

function diagnosticsFailure(
  requestId: string,
  error: DiagnosticsError,
): { ok: false; requestId: string; error: DiagnosticsError } {
  return { ok: false, requestId, error };
}

function exportFailure(
  status: 'failed' | 'cancelled',
  error: DiagnosticsError,
): DiagnosticsExportSupportBundleResult {
  return { status, error };
}

function unauthorizedError(message: string): DiagnosticsError {
  return {
    code: 'DIAGNOSTICS_UNAUTHORIZED',
    message,
    recoverable: false,
    retryable: false,
  };
}

function validationError(message: string): DiagnosticsError {
  return {
    code: 'DIAGNOSTICS_VALIDATION_FAILED',
    message,
    recoverable: false,
    retryable: false,
  };
}

function getDiagnosticsRequestId(payload: unknown): string | null {
  if (
    isPlainRecord(payload) &&
    isNonEmptyString(payload.requestId) &&
    DIAGNOSTICS_REQUEST_ID_PATTERN.test(payload.requestId)
  ) {
    return payload.requestId;
  }
  return null;
}

function createDialogParentDirectoryProvider(
  options: Pick<RegisterDiagnosticsIpcHandlersOptions, 'getShellWindow'>,
): () => Promise<string | null> {
  return async () => {
    const dialog = getElectronDialog();
    const result = await dialog.showOpenDialog(options.getShellWindow?.() ?? undefined, {
      title: 'Export Lineup Desktop Support Bundle',
      buttonLabel: 'Export',
      properties: ['openDirectory', 'createDirectory'],
    });
    if (result.canceled || result.filePaths.length !== 1) {
      return null;
    }
    return result.filePaths[0] ?? null;
  };
}

function scanSupportBundleDirectory(
  root: string,
  options: SupportBundleRedactionScannerOptions,
): RedactionScanReport {
  const files = collectSupportBundleFiles(root);
  let scannedByteCount = 0;
  let findingCount = 0;
  const findingsByLabel: Partial<Record<keyof RedactionScanReport['findingsByLabel'], number>> = {};

  for (const relativePath of files) {
    const absolutePath = path.join(root, relativePath);
    const stat = fs.statSync(absolutePath);
    scannedByteCount += stat.size;
    const content = fs.readFileSync(absolutePath, 'utf8');
    const findings = scanSupportBundleContent(content);
    for (const finding of findings) {
      findingsByLabel[finding] = (findingsByLabel[finding] ?? 0) + 1;
      findingCount += 1;
    }
  }

  return {
    redactionVersion: DIAGNOSTIC_REDACTION_VERSION,
    scannedFileCount: files.length,
    scannedByteCount,
    findingCount,
    findingsByLabel,
    truncatedRecordCount: options.truncatedRecordCount,
    omittedFileCount: options.omittedFileCount,
    status: findingCount === 0 ? 'passed' : 'failed',
    timestampMs: options.timestampMs,
  };
}

function collectSupportBundleFiles(root: string): string[] {
  const files: string[] = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isFile() || !SAFE_TEXT_FILE_PATTERN.test(entry.name)) {
      continue;
    }
    files.push(entry.name);
  }
  return files.sort();
}

function scanSupportBundleContent(content: string): Array<keyof RedactionScanReport['findingsByLabel']> {
  const findings: Array<keyof RedactionScanReport['findingsByLabel']> = [];
  if (/[?&][^=\s]*token[^=\s]*=/iu.test(content)) {
    findings.push('token-query-parameter');
  }
  if (/\b(?:authorization|x-plex-token)\s*:/iu.test(content)) {
    findings.push('raw-auth-header');
  }
  if (/\b(?:bearer|basic|token)\s+[A-Za-z0-9._~+/=-]{8,}/iu.test(content)) {
    findings.push('credential-scheme');
  }
  if (/\b(?:path|filePath|directory|userData|home|mediaPath|localPath)\s*[:=]\s*(?:"[A-Za-z]:\\|"\/(?:Users|home|var|tmp|private|Volumes)\/)/u.test(content)) {
    findings.push('raw-filesystem-path');
  }
  if (/\b(?:pid|argv|env|stderr|stdout|crashDump|minidump|rawLog)\s*[:=]\s*(?:"[^"]+"|\d{2,})/iu.test(content)) {
    findings.push('raw-process-data');
  }
  if (/\b(?:nativeHandle|libmpvObject|engineId)\s*[:=]\s*(?:"?0x[0-9a-f]+"?|\d{4,})/iu.test(content)) {
    findings.push('native-handle');
  }
  if (/\brawIpc\s*[:=]/iu.test(content)) {
    findings.push('raw-ipc-frame');
  }
  if (/\b(?:credential|secret|password|authToken|plexToken)\s*[:=]\s*["']?[A-Za-z0-9._~+/=-]{8,}/iu.test(content)) {
    findings.push('secret-field-value');
  }
  return [...new Set(findings)];
}

function getElectronIpcMain(): DiagnosticsIpcMain {
  const require = createRequire(import.meta.url);
  const electron = require('electron') as { ipcMain?: DiagnosticsIpcMain };
  if (electron.ipcMain === undefined) {
    throw new Error('Electron ipcMain is unavailable.');
  }
  return electron.ipcMain;
}

function getElectronDialog(): {
  showOpenDialog: (
    window: BrowserWindow | undefined,
    options: { title: string; buttonLabel: string; properties: string[] },
  ) => Promise<{ canceled: boolean; filePaths: string[] }>;
} {
  const require = createRequire(import.meta.url);
  const electron = require('electron') as {
    dialog?: {
      showOpenDialog: (
        window: BrowserWindow | undefined,
        options: { title: string; buttonLabel: string; properties: string[] },
      ) => Promise<{ canceled: boolean; filePaths: string[] }>;
    };
  };
  if (electron.dialog === undefined) {
    throw new Error('Electron dialog is unavailable.');
  }
  return electron.dialog;
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return (
    typeof value === 'object' &&
    value !== null &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isStringInSet<TValue extends string>(
  value: unknown,
  allowed: readonly TValue[],
): value is TValue {
  return typeof value === 'string' && allowed.includes(value as TValue);
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  requiredKeys: readonly string[],
  optionalKeys: readonly string[] = [],
): boolean {
  const allowed = new Set([...requiredKeys, ...optionalKeys]);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      return false;
    }
  }
  return requiredKeys.every((key) => Object.hasOwn(value, key));
}
