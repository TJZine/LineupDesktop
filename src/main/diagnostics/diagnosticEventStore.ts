import {
  DIAGNOSTIC_CATEGORIES,
  DIAGNOSTIC_SCHEMA_VERSION,
  DIAGNOSTIC_SEVERITIES,
  DIAGNOSTIC_STATUSES,
  DIAGNOSTIC_SURFACES,
  DIAGNOSTIC_TRUNCATION_LIMITS,
  DIAGNOSTIC_REDACTION_VERSION,
  type DiagnosticCategory,
  type DiagnosticContext,
  type DiagnosticRecord,
  type DiagnosticRecordResult,
  type DiagnosticSeverity,
  type DiagnosticsSummary,
  type DiagnosticStatus,
  type DiagnosticSurface,
  type DiagnosticTruncation,
  type RedactionScanReport,
  sanitizeDiagnosticContext,
  sanitizeDiagnosticMessage,
  sanitizeDiagnosticOperation,
  sanitizeDiagnosticRequestId,
} from '../../contracts/diagnostics.js';

export interface DiagnosticEventStoreOptions {
  maxRecords?: number;
  clock?: () => number;
  idGenerator?: () => string;
}

export interface DiagnosticEventInput {
  surface: DiagnosticSurface;
  category: DiagnosticCategory;
  severity: DiagnosticSeverity;
  status: DiagnosticStatus;
  operation: string;
  message: string;
  requestId?: string;
  result?: DiagnosticRecordResult;
  context?: unknown;
}

export interface SerializedDiagnosticRecords {
  content: string;
  includedRecordCount: number;
  truncatedRecordCount: number;
  byteCount: number;
}

export interface DiagnosticCrashRecoverySummary {
  schemaVersion: typeof DIAGNOSTIC_SCHEMA_VERSION;
  helperCrashCount: number;
  helperRestartCount: number;
  cleanupFailureCount: number;
  events: readonly DiagnosticCrashRecoverySummaryEvent[];
}

export interface DiagnosticCrashRecoverySummaryEvent {
  timestampMs: number;
  surface: DiagnosticSurface;
  category: DiagnosticCategory;
  status: DiagnosticStatus;
  operation: string;
  requestId?: string;
  code?: string;
}

const TEXT_ENCODER = new TextEncoder();

export class DiagnosticEventStore {
  readonly #maxRecords: number;
  readonly #clock: () => number;
  readonly #idGenerator: () => string;
  #records: DiagnosticRecord[] = [];
  #lastExportStatus: DiagnosticsSummary['lastExportStatus'] = null;
  #redactionFailureCount = 0;
  #fallbackIdCounter = 0;

  public constructor(options: DiagnosticEventStoreOptions = {}) {
    this.#maxRecords = Math.max(
      0,
      Math.min(options.maxRecords ?? DIAGNOSTIC_TRUNCATION_LIMITS.storeRecords, DIAGNOSTIC_TRUNCATION_LIMITS.storeRecords),
    );
    this.#clock = options.clock ?? Date.now;
    this.#idGenerator = options.idGenerator ?? (() => this.createFallbackId());
  }

  public record(input: DiagnosticEventInput): DiagnosticRecord {
    const operation = sanitizeDiagnosticOperation(input.operation);
    const message = sanitizeDiagnosticMessage(input.message);
    const requestId = sanitizeDiagnosticRequestId(input.requestId);
    const context = sanitizeDiagnosticContext(input.context);
    const truncation = mergeDiagnosticTruncation(
      operation.truncation,
      message.truncation,
      requestId.truncation,
      context.truncation,
    );
    const record: DiagnosticRecord = {
      schemaVersion: DIAGNOSTIC_SCHEMA_VERSION,
      id: sanitizeRecordId(this.#idGenerator()),
      timestampMs: normalizeTimestamp(this.#clock()),
      surface: normalizeDiagnosticValue(input.surface, DIAGNOSTIC_SURFACES, 'main'),
      category: normalizeDiagnosticValue(input.category, DIAGNOSTIC_CATEGORIES, 'unknown'),
      severity: normalizeDiagnosticValue(input.severity, DIAGNOSTIC_SEVERITIES, 'info'),
      status: normalizeDiagnosticValue(input.status, DIAGNOSTIC_STATUSES, 'observed'),
      operation: operation.operation,
      message: message.message,
      ...(requestId.requestId !== undefined ? { requestId: requestId.requestId } : {}),
      ...(input.result !== undefined ? { result: input.result } : {}),
      ...(context.context !== undefined ? { context: context.context } : {}),
      ...(truncation !== undefined ? { truncation } : {}),
    };

    this.#records.push(record);
    if (this.#records.length > this.#maxRecords) {
      this.#records = this.#records.slice(this.#records.length - this.#maxRecords);
    }
    return cloneDiagnosticRecord(record);
  }

  public getRecords(limit: number = DIAGNOSTIC_TRUNCATION_LIMITS.exportRecords): readonly DiagnosticRecord[] {
    const boundedLimit = Math.max(0, Math.min(limit, DIAGNOSTIC_TRUNCATION_LIMITS.exportRecords));
    return this.#records.slice(-boundedLimit).map(cloneDiagnosticRecord);
  }

  public serializeNdjson(limit: number = DIAGNOSTIC_TRUNCATION_LIMITS.exportRecords): SerializedDiagnosticRecords {
    const records = this.getRecords(limit);
    const lines: string[] = [];
    let byteCount = 0;
    let omittedForBytes = 0;

    for (const record of records) {
      const line = `${JSON.stringify(record)}\n`;
      const lineBytes = TEXT_ENCODER.encode(line).byteLength;
      if (byteCount + lineBytes > DIAGNOSTIC_TRUNCATION_LIMITS.diagnosticsNdjsonBytes) {
        omittedForBytes += 1;
        continue;
      }
      lines.push(line);
      byteCount += lineBytes;
    }

    return {
      content: lines.join(''),
      includedRecordCount: lines.length,
      truncatedRecordCount: Math.max(0, this.#records.length - records.length) + omittedForBytes,
      byteCount,
    };
  }

  public getSummary(): DiagnosticsSummary {
    const surfaceCounts: Partial<Record<DiagnosticSurface, number>> = {};
    const severityCounts: Partial<Record<DiagnosticSeverity, number>> = {};
    for (const record of this.#records) {
      surfaceCounts[record.surface] = (surfaceCounts[record.surface] ?? 0) + 1;
      severityCounts[record.severity] = (severityCounts[record.severity] ?? 0) + 1;
    }
    return {
      schemaVersion: DIAGNOSTIC_SCHEMA_VERSION,
      redactionVersion: DIAGNOSTIC_REDACTION_VERSION,
      recordCount: this.#records.length,
      lastEventTimestampMs: this.#records.at(-1)?.timestampMs ?? null,
      surfaceCounts,
      severityCounts,
      lastExportStatus: this.#lastExportStatus,
      redactionFailureCount: this.#redactionFailureCount,
    };
  }

  public getCrashRecoverySummary(): DiagnosticCrashRecoverySummary {
    const events = this.#records
      .filter((record) => (
        record.category === 'helper-crash' ||
        record.category === 'helper-restart' ||
        record.category === 'cleanup'
      ))
      .map((record): DiagnosticCrashRecoverySummaryEvent => ({
        timestampMs: record.timestampMs,
        surface: record.surface,
        category: record.category,
        status: record.status,
        operation: record.operation,
        ...(record.requestId !== undefined ? { requestId: record.requestId } : {}),
        ...(typeof record.context?.code === 'string' ? { code: record.context.code } : {}),
      }));
    const helperCrashIncidents = new Set(
      events
        .filter((event) => event.category === 'helper-crash')
        .map((event) => createCrashRecoveryIncidentKey(event)),
    );
    const helperRestartIncidents = new Set(
      events
        .filter((event) => event.category === 'helper-restart')
        .map((event) => createCrashRecoveryIncidentKey(event)),
    );
    const cleanupFailureIncidents = new Set(
      events
        .filter((event) => event.category === 'cleanup' && event.status === 'failed')
        .map((event) => createCrashRecoveryIncidentKey(event)),
    );
    return {
      schemaVersion: DIAGNOSTIC_SCHEMA_VERSION,
      helperCrashCount: helperCrashIncidents.size,
      helperRestartCount: helperRestartIncidents.size,
      cleanupFailureCount: cleanupFailureIncidents.size,
      events,
    };
  }

  public recordExportStatus(status: DiagnosticsSummary['lastExportStatus'], report?: RedactionScanReport): void {
    this.#lastExportStatus = status;
    if (report?.status === 'failed') {
      this.#redactionFailureCount += 1;
    }
  }

  private createFallbackId(): string {
    this.#fallbackIdCounter += 1;
    return `diagnostic-${String(this.#fallbackIdCounter)}`;
  }
}

function normalizeTimestamp(value: number): number {
  return Number.isFinite(value) && value >= 0 ? Math.floor(value) : 0;
}

function normalizeDiagnosticValue<T extends string>(
  value: T,
  allowedValues: readonly T[],
  fallback: T,
): T {
  return allowedValues.includes(value) ? value : fallback;
}

function sanitizeRecordId(value: string): string {
  const requestId = sanitizeDiagnosticRequestId(value).requestId ?? 'diagnostic';
  const safeId = requestId.replace(/[^A-Za-z0-9-]/gu, '-').replace(/-+/gu, '-').replace(/^-|-$/gu, '');
  return safeId.length > 0 ? safeId : 'diagnostic';
}

function mergeDiagnosticTruncation(
  ...items: readonly (DiagnosticTruncation | undefined)[]
): DiagnosticTruncation | undefined {
  const merged: DiagnosticTruncation = {};
  for (const item of items) {
    if (item === undefined) {
      continue;
    }
    Object.assign(merged, item);
  }
  return Object.keys(merged).length > 0 ? merged : undefined;
}

function cloneDiagnosticRecord(record: DiagnosticRecord): DiagnosticRecord {
  return {
    ...record,
    ...(record.context !== undefined ? { context: { ...record.context } satisfies DiagnosticContext } : {}),
    ...(record.truncation !== undefined ? { truncation: { ...record.truncation } } : {}),
  };
}

function createCrashRecoveryIncidentKey(event: DiagnosticCrashRecoverySummaryEvent): string {
  if (event.requestId !== undefined) {
    return `${event.category}:request:${event.requestId}`;
  }
  return `${event.category}:unscoped:${event.code ?? 'unknown'}`;
}
