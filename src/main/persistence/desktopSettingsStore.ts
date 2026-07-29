import fs from 'node:fs/promises';
import path from 'node:path';

import {
  SETTINGS_SCHEMA_VERSION,
  createDefaultDesktopSettingsValues,
  isDesktopSettingsValues,
  isSafeRevision,
  type DesktopSettingsErrorCode,
  type DesktopSettingsSnapshot,
  type DesktopSettingsValues,
} from '../../contracts/settings.js';

export interface DesktopSettingsFileSystem {
  readFile(filePath: string, encoding: 'utf8'): Promise<string>;
  mkdir(directoryPath: string, options: { recursive: true }): Promise<unknown>;
  writeFile(filePath: string, content: string, options: { encoding: 'utf8'; mode: number }): Promise<void>;
  chmod(filePath: string, mode: number): Promise<void>;
  rename(sourcePath: string, destinationPath: string): Promise<void>;
  unlink(filePath: string): Promise<void>;
}

export class DesktopSettingsStoreError extends Error {
  readonly code: DesktopSettingsErrorCode;

  constructor(code: DesktopSettingsErrorCode) {
    super('Desktop settings store operation failed.');
    this.name = 'DesktopSettingsStoreError';
    this.code = code;
  }
}

export interface DesktopSettingsStoreOptions {
  settingsFilePath: string;
  fileSystem?: DesktopSettingsFileSystem;
  processId?: number;
  migrationEventSink?: (event: DesktopSettingsMigrationEvent) => void;
}

interface StoredDesktopSettingsRecord {
  schemaVersion: typeof SETTINGS_SCHEMA_VERSION;
  revision: number;
  values: DesktopSettingsValues;
}

interface StoredDesktopSettingsVersionOneRecord {
  schemaVersion: 1;
  revision: number;
  values: {
    launchMode: 'windowed' | 'fullscreen';
    guideDensity: 'comfortable' | 'compact';
    previewBadgesEnabled: boolean;
    setupReminderEnabled: boolean;
  };
}

export interface DesktopSettingsMigrationEvent {
  fromVersion: 1;
  toVersion: 2;
  status: 'succeeded' | 'failed';
  revision: number;
}

const nodeFileSystem: DesktopSettingsFileSystem = {
  readFile: (filePath, encoding) => fs.readFile(filePath, encoding),
  mkdir: (directoryPath, options) => fs.mkdir(directoryPath, options),
  writeFile: (filePath, content, options) => fs.writeFile(filePath, content, options),
  chmod: (filePath, mode) => fs.chmod(filePath, mode),
  rename: (sourcePath, destinationPath) => fs.rename(sourcePath, destinationPath),
  unlink: (filePath) => fs.unlink(filePath),
};

export class DesktopSettingsStore {
  private readonly settingsFilePath: string;
  private readonly fileSystem: DesktopSettingsFileSystem;
  private readonly processId: number;
  private readonly migrationEventSink: ((event: DesktopSettingsMigrationEvent) => void) | undefined;
  private operationChain: Promise<void> = Promise.resolve();
  private tempCounter = 0;

  constructor(options: DesktopSettingsStoreOptions) {
    this.settingsFilePath = options.settingsFilePath;
    this.fileSystem = options.fileSystem ?? nodeFileSystem;
    this.processId = options.processId ?? process.pid;
    this.migrationEventSink = options.migrationEventSink;
  }

  loadSnapshot(): Promise<DesktopSettingsSnapshot> {
    return this.enqueue(() => this.readSnapshot());
  }

  replace(
    expectedRevision: number,
    values: DesktopSettingsValues,
  ): Promise<DesktopSettingsSnapshot> {
    return this.enqueue(async () => {
      const current = await this.readSnapshot();
      if (current.status === 'unsupported-version') {
        throw new DesktopSettingsStoreError('unsupported-version');
      }
      if (current.revision !== expectedRevision) {
        throw new DesktopSettingsStoreError('revision-conflict');
      }
      if (current.revision === Number.MAX_SAFE_INTEGER) {
        throw new DesktopSettingsStoreError('operation-failed');
      }
      const record: StoredDesktopSettingsRecord = {
        schemaVersion: SETTINGS_SCHEMA_VERSION,
        revision: current.revision + 1,
        values: { ...values },
      };
      await this.writeRecord(record);
      return {
        ...record,
        status: 'ready',
      };
    });
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.operationChain.then(operation, operation);
    this.operationChain = result.then(() => undefined, () => undefined);
    return result;
  }

  private async readSnapshot(): Promise<DesktopSettingsSnapshot> {
    let content: string;
    try {
      content = await this.fileSystem.readFile(this.settingsFilePath, 'utf8');
    } catch (error: unknown) {
      if (isNodeErrorCode(error, 'ENOENT')) {
        return defaultSnapshot('missing');
      }
      throw new DesktopSettingsStoreError('storage-unavailable');
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(content) as unknown;
    } catch {
      return defaultSnapshot('corrupt');
    }
    if (isStoredDesktopSettingsVersionOneRecord(parsed)) {
      return this.migrateVersionOneRecord(parsed);
    }
    if (isPlainRecord(parsed) &&
      Number.isInteger(parsed.schemaVersion) &&
      parsed.schemaVersion !== SETTINGS_SCHEMA_VERSION) {
      return defaultSnapshot(parsed.schemaVersion === 1 ? 'corrupt' : 'unsupported-version');
    }
    if (!isStoredDesktopSettingsRecord(parsed)) {
      return defaultSnapshot('corrupt');
    }
    return {
      schemaVersion: SETTINGS_SCHEMA_VERSION,
      revision: parsed.revision,
      status: 'ready',
      values: { ...parsed.values },
    };
  }

  private async migrateVersionOneRecord(
    record: StoredDesktopSettingsVersionOneRecord,
  ): Promise<DesktopSettingsSnapshot> {
    if (record.revision === Number.MAX_SAFE_INTEGER) {
      throw new DesktopSettingsStoreError('operation-failed');
    }
    const revision = record.revision + 1;
    const values: DesktopSettingsValues = {
      ...createDefaultDesktopSettingsValues(),
      launchMode: record.values.launchMode,
      guideDensity: record.values.guideDensity,
      previewBadgesEnabled: record.values.previewBadgesEnabled,
      setupReminderEnabled: record.values.setupReminderEnabled,
    };
    const migratedRecord: StoredDesktopSettingsRecord = {
      schemaVersion: SETTINGS_SCHEMA_VERSION,
      revision,
      values,
    };
    try {
      await this.writeRecord(migratedRecord);
    } catch {
      this.emitMigrationEvent({ fromVersion: 1, toVersion: 2, status: 'failed', revision });
      throw new DesktopSettingsStoreError('operation-failed');
    }
    this.emitMigrationEvent({ fromVersion: 1, toVersion: 2, status: 'succeeded', revision });
    return {
      ...migratedRecord,
      status: 'ready',
    };
  }

  private emitMigrationEvent(event: DesktopSettingsMigrationEvent): void {
    try {
      this.migrationEventSink?.(event);
    } catch {
      // Fixed migration diagnostics are best-effort and cannot change storage outcomes.
    }
  }

  private async writeRecord(record: StoredDesktopSettingsRecord): Promise<void> {
    const parentDirectory = path.dirname(this.settingsFilePath);
    const tempFilePath = `${this.settingsFilePath}.${String(this.processId)}.${String(++this.tempCounter)}.tmp`;
    let tempWriteStarted = false;
    try {
      await this.fileSystem.mkdir(parentDirectory, { recursive: true });
      tempWriteStarted = true;
      await this.fileSystem.writeFile(
        tempFilePath,
        `${JSON.stringify(record)}\n`,
        { encoding: 'utf8', mode: 0o600 },
      );
      await this.fileSystem.chmod(tempFilePath, 0o600);
      await this.fileSystem.rename(tempFilePath, this.settingsFilePath);
    } catch {
      if (tempWriteStarted) {
        try {
          await this.fileSystem.unlink(tempFilePath);
        } catch {
          // Cleanup is best-effort and never replaces the primary save failure.
        }
      }
      throw new DesktopSettingsStoreError('operation-failed');
    }
  }
}

function defaultSnapshot(
  status: 'missing' | 'corrupt' | 'unsupported-version',
): DesktopSettingsSnapshot {
  return {
    schemaVersion: SETTINGS_SCHEMA_VERSION,
    revision: 0,
    status,
    values: createDefaultDesktopSettingsValues(),
  };
}

function isStoredDesktopSettingsRecord(value: unknown): value is StoredDesktopSettingsRecord {
  return isPlainRecord(value) &&
    Object.keys(value).length === 3 &&
    Object.hasOwn(value, 'schemaVersion') &&
    Object.hasOwn(value, 'revision') &&
    Object.hasOwn(value, 'values') &&
    value.schemaVersion === SETTINGS_SCHEMA_VERSION &&
    isSafeRevision(value.revision) &&
    isDesktopSettingsValues(value.values);
}

function isStoredDesktopSettingsVersionOneRecord(
  value: unknown,
): value is StoredDesktopSettingsVersionOneRecord {
  if (!isPlainRecord(value) ||
    Object.keys(value).length !== 3 ||
    value.schemaVersion !== 1 ||
    !isSafeRevision(value.revision) ||
    !isPlainRecord(value.values) ||
    Object.keys(value.values).length !== 4) {
    return false;
  }
  return Object.hasOwn(value.values, 'launchMode') &&
    Object.hasOwn(value.values, 'guideDensity') &&
    Object.hasOwn(value.values, 'previewBadgesEnabled') &&
    Object.hasOwn(value.values, 'setupReminderEnabled') &&
    (value.values.launchMode === 'windowed' || value.values.launchMode === 'fullscreen') &&
    (value.values.guideDensity === 'comfortable' || value.values.guideDensity === 'compact') &&
    typeof value.values.previewBadgesEnabled === 'boolean' &&
    typeof value.values.setupReminderEnabled === 'boolean';
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function isNodeErrorCode(error: unknown, code: string): boolean {
  return error instanceof Error && 'code' in error && error.code === code;
}
