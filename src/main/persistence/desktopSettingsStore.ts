import { randomBytes } from 'node:crypto';
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
  open(filePath: string, flags: 'wx', mode: number): Promise<DesktopSettingsFileHandle>;
  rename(sourcePath: string, destinationPath: string): Promise<void>;
  unlink(filePath: string): Promise<void>;
}

export interface DesktopSettingsFileHandle {
  writeFile(content: string, encoding: 'utf8'): Promise<void>;
  chmod(mode: number): Promise<void>;
  sync(): Promise<void>;
  close(): Promise<void>;
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
  randomHex128?: () => string;
}

interface StoredDesktopSettingsRecord {
  schemaVersion: typeof SETTINGS_SCHEMA_VERSION;
  revision: number;
  values: DesktopSettingsValues;
}

const nodeFileSystem: DesktopSettingsFileSystem = {
  readFile: (filePath, encoding) => fs.readFile(filePath, encoding),
  mkdir: (directoryPath, options) => fs.mkdir(directoryPath, options),
  open: async (filePath, flags, mode) => {
    const handle = await fs.open(filePath, flags, mode);
    return {
      writeFile: async (content, encoding) => {
        await handle.writeFile(content, { encoding });
      },
      chmod: (nextMode) => handle.chmod(nextMode),
      sync: () => handle.sync(),
      close: () => handle.close(),
    };
  },
  rename: (sourcePath, destinationPath) => fs.rename(sourcePath, destinationPath),
  unlink: (filePath) => fs.unlink(filePath),
};

const TEMP_FILE_OPEN_ATTEMPTS = 8;
const randomHex128Pattern = /^[0-9a-f]{32}$/u;

export class DesktopSettingsStore {
  private readonly settingsFilePath: string;
  private readonly fileSystem: DesktopSettingsFileSystem;
  private readonly randomHex128: () => string;
  private operationChain: Promise<void> = Promise.resolve();

  constructor(options: DesktopSettingsStoreOptions) {
    this.settingsFilePath = options.settingsFilePath;
    this.fileSystem = options.fileSystem ?? nodeFileSystem;
    this.randomHex128 = options.randomHex128 ?? (() => randomBytes(16).toString('hex'));
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
    if (isPlainRecord(parsed) && parsed.schemaVersion !== SETTINGS_SCHEMA_VERSION) {
      return defaultSnapshot('corrupt');
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

  private async writeRecord(record: StoredDesktopSettingsRecord): Promise<void> {
    const parentDirectory = path.dirname(this.settingsFilePath);
    let tempFilePath: string | null = null;
    let ownsTempFile = false;
    try {
      await this.fileSystem.mkdir(parentDirectory, { recursive: true });
      let handle: DesktopSettingsFileHandle | null = null;
      for (let attempt = 0; attempt < TEMP_FILE_OPEN_ATTEMPTS; attempt += 1) {
        const suffix = this.randomHex128();
        if (!randomHex128Pattern.test(suffix)) {
          throw new DesktopSettingsStoreError('operation-failed');
        }
        const candidatePath = `${this.settingsFilePath}.${suffix}.tmp`;
        try {
          handle = await this.fileSystem.open(candidatePath, 'wx', 0o600);
          tempFilePath = candidatePath;
          break;
        } catch (error: unknown) {
          if (isNodeErrorCode(error, 'EEXIST')) continue;
          throw error;
        }
      }
      if (handle === null || tempFilePath === null) {
        throw new DesktopSettingsStoreError('operation-failed');
      }
      ownsTempFile = true;

      let handleStageFailed = false;
      let handleStageError: unknown;
      try {
        await handle.writeFile(`${JSON.stringify(record)}\n`, 'utf8');
        await handle.chmod(0o600);
        await handle.sync();
      } catch (error: unknown) {
        handleStageFailed = true;
        handleStageError = error;
      }
      try {
        await handle.close();
      } catch (error: unknown) {
        if (!handleStageFailed) {
          handleStageFailed = true;
          handleStageError = error;
        }
      }
      if (handleStageFailed) {
        throw handleStageError;
      }

      await this.fileSystem.rename(tempFilePath, this.settingsFilePath);
      ownsTempFile = false;
    } catch {
      if (ownsTempFile && tempFilePath !== null) {
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
  status: 'missing' | 'corrupt',
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

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function isNodeErrorCode(error: unknown, code: string): boolean {
  return error instanceof Error && 'code' in error && error.code === code;
}
