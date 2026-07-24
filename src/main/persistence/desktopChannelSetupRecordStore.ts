import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

import type { ChannelSetupConfig, ChannelSetupRecordSummary } from '../../contracts/channel.js';
import { normalizeChannelSetupConfig } from '../../domain/channel/setupPlanning/index.js';

const SCHEMA_VERSION = 1;

export interface ChannelSetupRecord {
  profileId: string;
  serverId: string;
  config: ChannelSetupConfig;
  createdAtMs: number;
  updatedAtMs: number;
}

interface ChannelSetupRecordFile {
  schemaVersion: typeof SCHEMA_VERSION;
  records: ChannelSetupRecord[];
}

export interface DesktopChannelSetupRecordFileSystem {
  readFile(filePath: string, encoding: 'utf8'): Promise<string>;
  mkdir(directoryPath: string, options: { recursive: true }): Promise<void>;
  writeFile(filePath: string, content: string, options: { encoding: 'utf8'; mode: number }): Promise<void>;
  rename(sourcePath: string, destinationPath: string): Promise<void>;
  chmod(filePath: string, mode: number): Promise<void>;
}

export class DesktopChannelSetupRecordStore {
  private mutationChain: Promise<void> = Promise.resolve();
  private temporaryWriteCounter = 0;

  public constructor(private readonly options: {
    persistenceFilePath: string;
    fileSystem?: DesktopChannelSetupRecordFileSystem;
  }) {}

  public async getRecord(profileId: string, serverId: string): Promise<ChannelSetupRecordSummary> {
    return this.enqueue<ChannelSetupRecordSummary>(async () => {
      const read = await this.readFile();
      if (read.status !== 'ready') return { status: read.status };
      const record = read.value.records.find((candidate) => (
        candidate.profileId === profileId && candidate.serverId === serverId
      ));
      if (!record) return { status: 'missing' };
      return {
        status: 'ready',
        config: normalizeChannelSetupConfig(record.config),
        createdAtMs: record.createdAtMs,
        updatedAtMs: record.updatedAtMs,
      };
    }).catch((): ChannelSetupRecordSummary => ({ status: 'unavailable' }));
  }

  public async saveRecord(input: {
    profileId: string;
    serverId: string;
    config: ChannelSetupConfig;
    nowMs: number;
  }): Promise<void> {
    await this.enqueue(async () => {
      const read = await this.readFile();
      if (read.status === 'corrupt' || read.status === 'unsupported-version') {
        throw new Error(`Channel setup record is ${read.status}.`);
      }
      if (read.status === 'unavailable') throw new Error('Channel setup record is unavailable.');
      const file: ChannelSetupRecordFile = read.status === 'missing'
        ? { schemaVersion: SCHEMA_VERSION, records: [] }
        : read.status === 'ready'
          ? read.value
          : (() => { throw new Error('Channel setup record is unavailable.'); })();
      const index = file.records.findIndex((record) => (
        record.profileId === input.profileId && record.serverId === input.serverId
      ));
      const existing = index >= 0 ? file.records[index] : undefined;
      const record: ChannelSetupRecord = {
        profileId: input.profileId,
        serverId: input.serverId,
        config: normalizeChannelSetupConfig(input.config),
        createdAtMs: existing?.createdAtMs ?? input.nowMs,
        updatedAtMs: input.nowMs,
      };
      const records = [...file.records];
      if (index >= 0) records[index] = record;
      else records.push(record);
      await this.writeFile({ schemaVersion: SCHEMA_VERSION, records });
    });
  }

  private async readFile(): Promise<
    | { status: 'ready'; value: ChannelSetupRecordFile }
    | { status: 'missing' | 'corrupt' | 'unsupported-version' | 'unavailable' }
  > {
    let content: string;
    try {
      content = await (this.options.fileSystem ?? NODE_FILE_SYSTEM).readFile(
        this.options.persistenceFilePath,
        'utf8',
      );
    } catch (error) {
      if (isNodeFileError(error, 'ENOENT')) return { status: 'missing' };
      return { status: 'unavailable' };
    }
    try {
      const raw: unknown = JSON.parse(content);
      if (isObject(raw) && typeof raw.schemaVersion === 'number' && raw.schemaVersion > SCHEMA_VERSION) {
        return { status: 'unsupported-version' };
      }
      const value = parseRecordFile(raw);
      return value ? { status: 'ready', value } : { status: 'corrupt' };
    } catch {
      return { status: 'corrupt' };
    }
  }

  private async writeFile(value: ChannelSetupRecordFile): Promise<void> {
    const fileSystem = this.options.fileSystem ?? NODE_FILE_SYSTEM;
    await fileSystem.mkdir(path.dirname(this.options.persistenceFilePath), { recursive: true });
    this.temporaryWriteCounter += 1;
    const temporaryPath = `${this.options.persistenceFilePath}.${String(process.pid)}.${String(this.temporaryWriteCounter)}.tmp`;
    await fileSystem.writeFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`, {
      encoding: 'utf8',
      mode: 0o600,
    });
    await fileSystem.rename(temporaryPath, this.options.persistenceFilePath);
    await fileSystem.chmod(this.options.persistenceFilePath, 0o600);
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const run = this.mutationChain.then(operation, operation);
    this.mutationChain = run.then(() => undefined, () => undefined);
    return run;
  }
}

const NODE_FILE_SYSTEM: DesktopChannelSetupRecordFileSystem = {
  readFile: (filePath, encoding) => fs.readFile(filePath, encoding),
  mkdir: async (directoryPath, options) => { await fs.mkdir(directoryPath, options); },
  writeFile: async (filePath, content, options) => { await fs.writeFile(filePath, content, options); },
  rename: async (sourcePath, destinationPath) => { await fs.rename(sourcePath, destinationPath); },
  chmod: async (filePath, mode) => { await fs.chmod(filePath, mode); },
};

function parseRecordFile(value: unknown): ChannelSetupRecordFile | null {
  if (!isExactObject(value, ['schemaVersion', 'records']) || value.schemaVersion !== SCHEMA_VERSION || !Array.isArray(value.records)) return null;
  const records: ChannelSetupRecord[] = [];
  const contexts = new Set<string>();
  for (const raw of value.records) {
    if (!isExactObject(raw, ['profileId', 'serverId', 'config', 'createdAtMs', 'updatedAtMs']) ||
      !isNonEmptyString(raw.profileId) || !isNonEmptyString(raw.serverId) ||
      !isExactStoredConfig(raw.config) || !isNonNegativeFiniteNumber(raw.createdAtMs) ||
      !isNonNegativeFiniteNumber(raw.updatedAtMs) || raw.updatedAtMs < raw.createdAtMs) return null;
    const key = `${raw.profileId}\0${raw.serverId}`;
    if (contexts.has(key)) return null;
    contexts.add(key);
    records.push({
      profileId: raw.profileId,
      serverId: raw.serverId,
      config: normalizeChannelSetupConfig(raw.config),
      createdAtMs: raw.createdAtMs,
      updatedAtMs: raw.updatedAtMs,
    });
  }
  return { schemaVersion: SCHEMA_VERSION, records };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function isExactObject(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  return isObject(value) && Object.keys(value).length === keys.length &&
    keys.every((key) => Object.hasOwn(value, key));
}
function isExactStoredConfig(value: unknown): value is ChannelSetupConfig {
  if (!isExactObject(value, [
    'selectedLibraryIds', 'maxChannels', 'buildMode', 'strategyConfig', 'channelExpansion',
    'seriesOrdering', 'actorStudioCombineMode', 'minItemsPerChannel',
  ])) return false;
  if (!Array.isArray(value.selectedLibraryIds) || value.selectedLibraryIds.length === 0 ||
    value.selectedLibraryIds.length > 24 || !value.selectedLibraryIds.every(isSafeIdentifier) ||
    new Set(value.selectedLibraryIds).size !== value.selectedLibraryIds.length ||
    !isIntegerInRange(value.maxChannels, 1, 500) ||
    (value.buildMode !== 'append' && value.buildMode !== 'replace' && value.buildMode !== 'merge') ||
    (value.actorStudioCombineMode !== 'separate' && value.actorStudioCombineMode !== 'combined') ||
    !isIntegerInRange(value.minItemsPerChannel, 1, Number.MAX_SAFE_INTEGER)) return false;
  const strategyKeys = ['playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors'];
  if (!isExactObject(value.strategyConfig, strategyKeys)) return false;
  for (const strategy of strategyKeys) {
    const candidate = value.strategyConfig[strategy];
    if (!isExactObject(candidate, ['enabled', 'priority', 'scope']) ||
      typeof candidate.enabled !== 'boolean' || !isIntegerInRange(candidate.priority, 1, Number.MAX_SAFE_INTEGER) ||
      (candidate.scope !== 'per-library' && candidate.scope !== 'cross-library')) return false;
    if (!['genres', 'directors', 'studios', 'actors'].includes(strategy) && candidate.scope !== 'per-library') return false;
  }
  return isExactObject(value.channelExpansion, [
    'addAlternateLineups', 'alternateLineupCopies', 'variantType', 'variantBlockSize',
  ]) && typeof value.channelExpansion.addAlternateLineups === 'boolean' &&
    isIntegerInRange(value.channelExpansion.alternateLineupCopies, 1, 3) &&
    (value.channelExpansion.variantType === 'none' || value.channelExpansion.variantType === 'sequential' || value.channelExpansion.variantType === 'block') &&
    isIntegerInRange(value.channelExpansion.variantBlockSize, 2, 5) &&
    isExactObject(value.seriesOrdering, ['basePlaybackMode', 'baseBlockSize']) &&
    (value.seriesOrdering.basePlaybackMode === 'shuffle' || value.seriesOrdering.basePlaybackMode === 'sequential' || value.seriesOrdering.basePlaybackMode === 'block') &&
    isIntegerInRange(value.seriesOrdering.baseBlockSize, 2, 5);
}
function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}
function isNonNegativeFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}
function isIntegerInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}
function isSafeIdentifier(value: unknown): value is string {
  return typeof value === 'string' && /^[A-Za-z0-9._-]{1,120}$/u.test(value);
}
function isNodeFileError(error: unknown, code: string): boolean {
  return error instanceof Error && 'code' in error && error.code === code;
}
