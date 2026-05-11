import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import type { ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import type { StoredChannelData } from '../../domain/channel/types.js';

const CHANNEL_PERSISTENCE_SCHEMA_VERSION = 1;

interface ChannelPersistenceFile {
  schemaVersion: typeof CHANNEL_PERSISTENCE_SCHEMA_VERSION;
  storedChannelData: StoredChannelData | null;
  currentChannelId: string | null;
}

interface RawChannelPersistenceFile {
  schemaVersion?: unknown;
  storedChannelData?: unknown;
  currentChannelId?: unknown;
}

type ChannelPersistenceFileReadResult =
  | { status: 'present' | 'missing'; value: ChannelPersistenceFile; needsCurrentChannelIdRepair?: boolean }
  | { status: 'corrupt' };

export interface DesktopChannelPersistenceStoreOptions {
  persistenceFilePath: string;
  fileSystem?: DesktopChannelPersistenceFileSystem;
}

export interface DesktopChannelPersistenceFileSystem {
  readFile(filePath: string, encoding: 'utf8'): Promise<string>;
  mkdir(directoryPath: string, options: { recursive: true }): Promise<void>;
  writeFile(
    filePath: string,
    content: string,
    options: { encoding: 'utf8'; mode: number },
  ): Promise<void>;
  rename(sourcePath: string, destinationPath: string): Promise<void>;
  chmod(filePath: string, mode: number): Promise<void>;
}

export class DesktopChannelPersistenceStore implements ChannelPersistenceStoragePort {
  private readonly persistenceFilePath: string;
  private readonly fileSystem: DesktopChannelPersistenceFileSystem;
  private mutationChain: Promise<void> = Promise.resolve();
  private temporaryWriteCounter = 0;

  public constructor(options: DesktopChannelPersistenceStoreOptions) {
    this.persistenceFilePath = options.persistenceFilePath;
    this.fileSystem = options.fileSystem ?? NODE_CHANNEL_PERSISTENCE_FILE_SYSTEM;
  }

  public async readStoredChannelData(): Promise<string | null> {
    return this.enqueueMutation(async () => {
      const readResult = await this.readPersistenceFile();
      if (readResult.status === 'corrupt') {
        await this.writePersistenceFile(createEmptyChannelPersistenceFile());
        return null;
      }
      if (readResult.value.storedChannelData === null) {
        return null;
      }
      return JSON.stringify(readResult.value.storedChannelData);
    });
  }

  public async writeStoredChannelData(encoded: string): Promise<void> {
    await this.enqueueMutation(async () => {
      const parsed = JSON.parse(encoded) as StoredChannelData;
      const readResult = await this.readPersistenceFile();
      const existing = readResult.status === 'present' || readResult.status === 'missing'
        ? readResult.value
        : createEmptyChannelPersistenceFile();
      const hasCurrentChannelId = Object.prototype.hasOwnProperty.call(parsed, 'currentChannelId');
      await this.writePersistenceFile({
        schemaVersion: CHANNEL_PERSISTENCE_SCHEMA_VERSION,
        storedChannelData: parsed,
        currentChannelId: normalizeCurrentChannelId(
          hasCurrentChannelId ? parsed.currentChannelId : existing.currentChannelId,
        ),
      });
    });
  }

  public async clearStoredChannelData(): Promise<void> {
    await this.enqueueMutation(async () => {
      const readResult = await this.readPersistenceFile();
      const existing = readResult.status === 'present' || readResult.status === 'missing'
        ? readResult.value
        : createEmptyChannelPersistenceFile();
      await this.writePersistenceFile({
        ...existing,
        storedChannelData: null,
        currentChannelId: null,
      });
    });
  }

  public async readCurrentChannelId(): Promise<string | null> {
    return this.enqueueMutation(async () => {
      const readResult = await this.readPersistenceFile();
      if (readResult.status === 'corrupt') {
        return null;
      }
      return normalizeCurrentChannelId(readResult.value.currentChannelId);
    });
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    await this.enqueueMutation(async () => {
      const readResult = await this.readPersistenceFile();
      const existing = readResult.status === 'present' || readResult.status === 'missing'
        ? readResult.value
        : createEmptyChannelPersistenceFile();
      await this.writePersistenceFile({
        ...existing,
        currentChannelId: normalizeCurrentChannelId(channelId),
      });
    });
  }

  private async readPersistenceFile(): Promise<ChannelPersistenceFileReadResult> {
    let content: string;
    try {
      content = await this.fileSystem.readFile(this.persistenceFilePath, 'utf8');
    } catch (error) {
      if (isNodeFileError(error, 'ENOENT')) {
        return { status: 'missing', value: createEmptyChannelPersistenceFile() };
      }
      throw error;
    }

    let parsed: ReturnType<typeof parseChannelPersistenceFile>;
    try {
      parsed = parseChannelPersistenceFile(content);
    } catch {
      return { status: 'corrupt' };
    }
    if (parsed.needsCurrentChannelIdRepair) {
      await this.writePersistenceFile(parsed.value);
    }
    return {
      status: 'present',
      value: parsed.value,
    };
  }

  private async writePersistenceFile(value: ChannelPersistenceFile): Promise<void> {
    await this.fileSystem.mkdir(path.dirname(this.persistenceFilePath), { recursive: true });
    this.temporaryWriteCounter += 1;
    const temporaryPath = `${this.persistenceFilePath}.${String(process.pid)}.${String(this.temporaryWriteCounter)}.tmp`;
    await this.fileSystem.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
      encoding: 'utf8',
      mode: 0o600,
    });
    await this.fileSystem.rename(temporaryPath, this.persistenceFilePath);
    await this.fileSystem.chmod(this.persistenceFilePath, 0o600);
  }

  private enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const run = this.mutationChain.then(operation, operation);
    this.mutationChain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
}

const NODE_CHANNEL_PERSISTENCE_FILE_SYSTEM: DesktopChannelPersistenceFileSystem = {
  readFile: (filePath, encoding) => fs.readFile(filePath, encoding),
  mkdir: async (directoryPath, options) => {
    await fs.mkdir(directoryPath, options);
  },
  writeFile: async (filePath, content, options) => {
    await fs.writeFile(filePath, content, options);
  },
  rename: async (sourcePath, destinationPath) => {
    await fs.rename(sourcePath, destinationPath);
  },
  chmod: async (filePath, mode) => {
    await fs.chmod(filePath, mode);
  },
};

function createEmptyChannelPersistenceFile(): ChannelPersistenceFile {
  return {
    schemaVersion: CHANNEL_PERSISTENCE_SCHEMA_VERSION,
    storedChannelData: null,
    currentChannelId: null,
  };
}

function parseChannelPersistenceFile(content: string): {
  value: ChannelPersistenceFile;
  needsCurrentChannelIdRepair: boolean;
} {
  const parsed: unknown = JSON.parse(content);
  if (!isChannelPersistenceFile(parsed)) {
    throw new Error('Channel persistence file schema is invalid.');
  }
  return {
    value: {
      schemaVersion: CHANNEL_PERSISTENCE_SCHEMA_VERSION,
      storedChannelData: parsed.storedChannelData,
      currentChannelId: normalizeRawCurrentChannelId(parsed.currentChannelId),
    },
    needsCurrentChannelIdRepair: !isRawCurrentChannelIdValid(parsed.currentChannelId),
  };
}

function isChannelPersistenceFile(value: unknown): value is RawChannelPersistenceFile & {
  schemaVersion: typeof CHANNEL_PERSISTENCE_SCHEMA_VERSION;
  storedChannelData: StoredChannelData | null;
} {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  const candidate = value as RawChannelPersistenceFile;
  return (
    candidate.schemaVersion === CHANNEL_PERSISTENCE_SCHEMA_VERSION &&
    (candidate.storedChannelData === null || isStoredChannelData(candidate.storedChannelData))
  );
}

function isStoredChannelData(value: unknown): value is StoredChannelData {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Partial<StoredChannelData>;
  return (
    Array.isArray(candidate.channels) &&
    candidate.channels.every((channel) => channel !== null && typeof channel === 'object' && !Array.isArray(channel)) &&
    Array.isArray(candidate.channelOrder) &&
    candidate.channelOrder.every((channelId) => typeof channelId === 'string') &&
    (candidate.currentChannelId === null || typeof candidate.currentChannelId === 'string') &&
    typeof candidate.savedAt === 'number' &&
    Number.isFinite(candidate.savedAt)
  );
}

function normalizeCurrentChannelId(channelId: string | null | undefined): string | null {
  const normalized = channelId?.trim() ?? '';
  return normalized.length > 0 ? normalized : null;
}

function normalizeRawCurrentChannelId(channelId: unknown): string | null {
  return typeof channelId === 'string' ? normalizeCurrentChannelId(channelId) : null;
}

function isRawCurrentChannelIdValid(channelId: unknown): boolean {
  return channelId === null || typeof channelId === 'string';
}

function isNodeFileError(error: unknown, code: string): boolean {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof error.code === 'string' &&
    error.code === code
  );
}
