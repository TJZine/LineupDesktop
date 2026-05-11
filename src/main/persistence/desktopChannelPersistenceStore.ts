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

type ChannelPersistenceFileReadResult =
  | { status: 'present' | 'missing'; value: ChannelPersistenceFile }
  | { status: 'corrupt' };

export interface DesktopChannelPersistenceStoreOptions {
  persistenceFilePath: string;
}

export class DesktopChannelPersistenceStore implements ChannelPersistenceStoragePort {
  private readonly persistenceFilePath: string;
  private mutationChain: Promise<void> = Promise.resolve();
  private temporaryWriteCounter = 0;

  public constructor(options: DesktopChannelPersistenceStoreOptions) {
    this.persistenceFilePath = options.persistenceFilePath;
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
    const readResult = await this.readPersistenceFile();
    if (readResult.status === 'corrupt') {
      return null;
    }
    return normalizeCurrentChannelId(readResult.value.currentChannelId);
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
      content = await fs.readFile(this.persistenceFilePath, 'utf8');
    } catch (error) {
      if (isNodeFileError(error, 'ENOENT')) {
        return { status: 'missing', value: createEmptyChannelPersistenceFile() };
      }
      throw error;
    }

    try {
      return {
        status: 'present',
        value: parseChannelPersistenceFile(content),
      };
    } catch {
      return { status: 'corrupt' };
    }
  }

  private async writePersistenceFile(value: ChannelPersistenceFile): Promise<void> {
    await fs.mkdir(path.dirname(this.persistenceFilePath), { recursive: true });
    this.temporaryWriteCounter += 1;
    const temporaryPath = `${this.persistenceFilePath}.${String(process.pid)}.${String(this.temporaryWriteCounter)}.tmp`;
    await fs.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
      encoding: 'utf8',
      mode: 0o600,
    });
    await fs.rename(temporaryPath, this.persistenceFilePath);
    await fs.chmod(this.persistenceFilePath, 0o600);
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

function createEmptyChannelPersistenceFile(): ChannelPersistenceFile {
  return {
    schemaVersion: CHANNEL_PERSISTENCE_SCHEMA_VERSION,
    storedChannelData: null,
    currentChannelId: null,
  };
}

function parseChannelPersistenceFile(content: string): ChannelPersistenceFile {
  const parsed: unknown = JSON.parse(content);
  if (!isChannelPersistenceFile(parsed)) {
    throw new Error('Channel persistence file schema is invalid.');
  }
  return parsed;
}

function isChannelPersistenceFile(value: unknown): value is ChannelPersistenceFile {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }
  const candidate = value as Partial<ChannelPersistenceFile>;
  return (
    candidate.schemaVersion === CHANNEL_PERSISTENCE_SCHEMA_VERSION &&
    (candidate.storedChannelData === null || isStoredChannelData(candidate.storedChannelData)) &&
    (candidate.currentChannelId === null || typeof candidate.currentChannelId === 'string')
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

function isNodeFileError(error: unknown, code: string): boolean {
  return (
    error instanceof Error &&
    'code' in error &&
    typeof error.code === 'string' &&
    error.code === code
  );
}
