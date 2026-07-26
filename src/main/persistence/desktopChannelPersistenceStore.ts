import { constants as fsConstants } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

import {
  type ChannelAggregate,
  type ChannelAggregateMutationRequest,
  type ChannelAggregateMutationResult,
  type ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import { decodeStoredChannelData, encodeStoredChannelData } from '../../domain/channel/storedChannelDataCodec.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import {
  cloneChannelBuilderProvenance,
  isChannelBuilderPersistedStateV1,
  normalizeChannelBuilderPersistedStateV1,
} from '../../domain/channelBuilder/persistence.js';
import type { ChannelBuilderPersistedStateV1 } from '../../domain/channelBuilder/types.js';
import { cloneChannelForOwnership } from '../../domain/channel/channelDomainClone.js';
import {
  isChannelPersistenceReadyCapability,
  type ChannelPersistenceReadyCapability,
} from './channelPersistenceBootstrapOwner.js';

const CHANNEL_PERSISTENCE_SCHEMA_VERSION = 1;
const randomHexPattern = /^[a-f0-9]{32}$/u;

type FileIdentity = Readonly<{ dev: number | bigint; ino: number | bigint }>;

export interface DesktopChannelPersistenceFileStat extends FileIdentity {
  mode: number;
  isFile(): boolean;
  isSymbolicLink(): boolean;
}

export interface DesktopChannelPersistenceFileHandle {
  readFile(encoding: 'utf8'): Promise<string>;
  writeFile(content: string, encoding: 'utf8'): Promise<void>;
  chmod(mode: number): Promise<void>;
  sync(): Promise<void>;
  stat(): Promise<DesktopChannelPersistenceFileStat>;
  close(): Promise<void>;
}

export interface DesktopChannelPersistenceFileSystem {
  lstat(filePath: string): Promise<DesktopChannelPersistenceFileStat>;
  open(
    filePath: string,
    flags: number,
    mode?: number,
  ): Promise<DesktopChannelPersistenceFileHandle>;
  rename(sourcePath: string, destinationPath: string): Promise<void>;
  unlink(filePath: string): Promise<void>;
}

export interface DesktopChannelPersistenceStoreOptions {
  readyCapability: ChannelPersistenceReadyCapability;
  fileSystem?: DesktopChannelPersistenceFileSystem;
  randomHex128?: () => string;
  warn?: (code: 'CHANNEL_TEMP_CLEANUP_MISMATCH') => void;
}

export class UnsupportedChannelPersistenceSchemaError extends Error {
  public constructor() {
    super('Unsupported channel persistence schema.');
    this.name = 'UnsupportedChannelPersistenceSchemaError';
  }
}

export class CorruptChannelPersistenceFileError extends Error {
  public constructor() {
    super('Channel persistence file is corrupt.');
    this.name = 'CorruptChannelPersistenceFileError';
  }
}

export class ChannelPersistenceUnavailableError extends Error {
  public constructor() {
    super('Channel storage is unavailable.');
    this.name = 'ChannelPersistenceUnavailableError';
  }
}

type ParsedOuterFile = Readonly<{
  aggregate: ChannelAggregate;
  needsRepair: boolean;
}>;

export class DesktopChannelPersistenceStore implements ChannelPersistenceStoragePort {
  private readonly capability: ChannelPersistenceReadyCapability;
  private readonly fileSystem: DesktopChannelPersistenceFileSystem;
  private readonly randomHex128: () => string;
  private readonly warn: (code: 'CHANNEL_TEMP_CLEANUP_MISMATCH') => void;
  private mutationChain: Promise<void> = Promise.resolve();

  public constructor(options: DesktopChannelPersistenceStoreOptions) {
    if (!isChannelPersistenceReadyCapability(options.readyCapability)) {
      throw new TypeError('Channel persistence ready capability is required.');
    }
    if (
      path.dirname(options.readyCapability.persistenceFilePath) !==
      options.readyCapability.canonicalParentPath
    ) {
      throw new TypeError('Channel persistence destination does not match its capability.');
    }
    this.capability = options.readyCapability;
    this.fileSystem = options.fileSystem ?? NODE_FILE_SYSTEM;
    this.randomHex128 =
      options.randomHex128 ?? (() => crypto.randomBytes(16).toString('hex'));
    this.warn = options.warn ?? (() => undefined);
  }

  public readStoredChannelData(): Promise<string | null> {
    return this.enqueueMutation(async () => {
      const aggregate = await this.readChannelAggregateUnlocked(false);
      return aggregate.storedChannelData === null
        ? null
        : encodeStoredChannelData(aggregate.storedChannelData);
    });
  }

  public async writeStoredChannelData(encoded: string): Promise<void> {
    const data = decodeStoredChannelData(encoded);
    if (data === null || !isCompleteStoredChannelData(data)) {
      throw new CorruptChannelPersistenceFileError();
    }
    await this.mutateChannelAggregate({
      kind: 'custom-lineup',
      expectedLineupRevision: null,
      mutate: (current) => ({
        ...current,
        storedChannelData: data,
        currentChannelId: data.currentChannelId,
      }),
      onCommitBarrier: () => 'proceed',
    });
  }

  public async clearStoredChannelData(): Promise<void> {
    await this.mutateChannelAggregate({
      kind: 'custom-lineup',
      expectedLineupRevision: null,
      mutate: (current) => ({
        ...current,
        storedChannelData: null,
        currentChannelId: null,
        channelBuilderState: null,
      }),
      onCommitBarrier: () => 'proceed',
    });
  }

  public async readCurrentChannelId(): Promise<string | null> {
    return (await this.readChannelAggregate()).currentChannelId;
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    await this.mutateChannelAggregate({
      kind: 'current-channel',
      mutate: (current) => ({
        ...current,
        currentChannelId: normalizeCurrentChannelId(channelId),
        storedChannelData:
          current.storedChannelData === null
            ? null
            : {
                ...current.storedChannelData,
                currentChannelId: normalizeCurrentChannelId(channelId),
              },
      }),
      onCommitBarrier: () => 'proceed',
    });
  }

  public readChannelAggregate(): Promise<ChannelAggregate> {
    return this.enqueueMutation(() => this.readChannelAggregateUnlocked(false));
  }

  public mutateChannelAggregate(
    request: ChannelAggregateMutationRequest,
  ): Promise<ChannelAggregateMutationResult> {
    return this.enqueueMutation(async () => {
      const destination = await this.readDestination();
      const current =
        destination === null
          ? emptyAggregate()
          : parseOuterFile(destination.content, false).aggregate;
      if (
        request.kind === 'builder-lineup' &&
        request.expectedLineupRevision !== current.lineupRevision
      ) {
        return {
          status: 'conflict',
          actualLineupRevision: current.lineupRevision,
        };
      }
      let replacement: ChannelAggregate;
      try {
        replacement = request.mutate(cloneAggregate(current));
      } catch {
        throw new CorruptChannelPersistenceFileError();
      }
      const normalized = validateReplacementAggregate(replacement, request.kind);
      if (request.kind === 'current-channel' && aggregateBytes(normalized) === aggregateBytes(current)) {
        return { status: 'committed', aggregate: cloneAggregate(current) };
      }
      const next =
        request.kind === 'current-channel'
          ? normalized
          : { ...normalized, lineupRevision: current.lineupRevision + 1 };
      if (!Number.isSafeInteger(next.lineupRevision) || next.lineupRevision < 0) {
        throw new CorruptChannelPersistenceFileError();
      }
      const serialized = serializeAggregate(next);
      if (request.onCommitBarrier() === 'cancel') return { status: 'canceled' };
      await this.writeSerialized(serialized, destination?.prior ?? null);
      return { status: 'committed', aggregate: cloneAggregate(next) };
    });
  }

  public loadForStartup(): Promise<
    ParsedOuterFile & { present: boolean; destinationIdentity: FileIdentity | null }
  > {
    return this.enqueueMutation(async () => {
      const destination = await this.readDestination();
      if (destination === null) {
        return {
          present: false,
          destinationIdentity: null,
          aggregate: emptyAggregate(),
          needsRepair: false,
        };
      }
      const parsed = parseOuterFile(destination.content, true);
      return { present: true, destinationIdentity: destination.prior, ...parsed };
    });
  }

  public repairForStartup(
    aggregate: ChannelAggregate,
    destinationIdentity: FileIdentity,
  ): Promise<void> {
    return this.enqueueMutation(() =>
      this.writeSerialized(serializeAggregate(aggregate), destinationIdentity));
  }

  private async readChannelAggregateUnlocked(allowRepair: boolean): Promise<ChannelAggregate> {
    const destination = await this.readDestination();
    if (destination === null) return emptyAggregate();
    return parseOuterFile(destination.content, allowRepair).aggregate;
  }

  private async readDestination(): Promise<
    Readonly<{ content: string; prior: DesktopChannelPersistenceFileStat }> | null
  > {
    let prior: DesktopChannelPersistenceFileStat;
    try {
      prior = await this.fileSystem.lstat(this.capability.persistenceFilePath);
    } catch (error) {
      if (isNodeFileError(error, 'ENOENT')) return null;
      throw new ChannelPersistenceUnavailableError();
    }
    if (!prior.isFile() || prior.isSymbolicLink()) {
      throw new ChannelPersistenceUnavailableError();
    }
    const flags =
      this.capability.protectionPolicy === 'posix-0600'
        ? fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW
        : fsConstants.O_RDONLY;
    let handle: DesktopChannelPersistenceFileHandle;
    try {
      handle = await this.fileSystem.open(this.capability.persistenceFilePath, flags);
    } catch {
      throw new ChannelPersistenceUnavailableError();
    }
    let destination: Readonly<{
      content: string;
      prior: DesktopChannelPersistenceFileStat;
    }>;
    try {
      const handleStat = await handle.stat();
      if (!sameRegularIdentity(prior, handleStat)) {
        throw new ChannelPersistenceUnavailableError();
      }
      destination = { content: await handle.readFile('utf8'), prior };
    } catch (error) {
      try {
        await handle.close();
      } catch {
        throw error;
      }
      throw error;
    }
    try {
      await handle.close();
    } catch {
      throw new ChannelPersistenceUnavailableError();
    }
    return destination;
  }

  private async writeSerialized(
    content: string,
    expectedDestination: FileIdentity | null,
  ): Promise<void> {
    let temporaryPath: string | null = null;
    let temporaryIdentity: FileIdentity | null = null;
    try {
      for (let attempt = 0; attempt < 8; attempt += 1) {
        const suffix = this.randomHex128();
        if (!randomHexPattern.test(suffix)) throw new ChannelPersistenceUnavailableError();
        const candidate = `${this.capability.persistenceFilePath}.${suffix}.tmp`;
        const flags =
          this.capability.protectionPolicy === 'posix-0600'
            ? fsConstants.O_CREAT |
              fsConstants.O_EXCL |
              fsConstants.O_WRONLY |
              fsConstants.O_NOFOLLOW
            : fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY;
        let handle: DesktopChannelPersistenceFileHandle;
        try {
          handle =
            this.capability.protectionPolicy === 'posix-0600'
              ? await this.fileSystem.open(candidate, flags, 0o600)
              : await this.fileSystem.open(candidate, flags);
        } catch (error) {
          if (isNodeFileError(error, 'EEXIST')) continue;
          throw new ChannelPersistenceUnavailableError();
        }
        temporaryPath = candidate;
        let writeFailure: unknown = null;
        try {
          const opened = await handle.stat();
          if (!opened.isFile() || opened.isSymbolicLink()) {
            throw new ChannelPersistenceUnavailableError();
          }
          temporaryIdentity = opened;
          await handle.writeFile(content, 'utf8');
          if (this.capability.protectionPolicy === 'posix-0600') {
            await handle.chmod(0o600);
          }
          await handle.sync();
          const verified = await handle.stat();
          if (
            !sameRegularIdentity(opened, verified) ||
            (this.capability.protectionPolicy === 'posix-0600' &&
              (verified.mode & 0o777) !== 0o600)
          ) {
            throw new ChannelPersistenceUnavailableError();
          }
        } catch (error) {
          writeFailure = error;
        }
        let closeFailed = false;
        try {
          await handle.close();
        } catch {
          closeFailed = true;
        }
        if (writeFailure !== null) throw writeFailure;
        if (closeFailed) throw new ChannelPersistenceUnavailableError();
        break;
      }
      if (temporaryPath === null || temporaryIdentity === null) {
        throw new ChannelPersistenceUnavailableError();
      }
      const closed = await this.fileSystem.lstat(temporaryPath);
      if (
        !sameRegularIdentity(temporaryIdentity, closed) ||
        (this.capability.protectionPolicy === 'posix-0600' &&
          (closed.mode & 0o777) !== 0o600)
      ) {
        throw new ChannelPersistenceUnavailableError();
      }
      await this.assertDestinationGuard(expectedDestination);
      await this.fileSystem.rename(temporaryPath, this.capability.persistenceFilePath);
      temporaryPath = null;
      temporaryIdentity = null;
    } catch (error) {
      if (temporaryPath !== null && temporaryIdentity !== null) {
        await this.cleanupOwnedTemporary(temporaryPath, temporaryIdentity);
      }
      if (error instanceof CorruptChannelPersistenceFileError) throw error;
      throw new ChannelPersistenceUnavailableError();
    }
  }

  private async assertDestinationGuard(expected: FileIdentity | null): Promise<void> {
    try {
      const current = await this.fileSystem.lstat(this.capability.persistenceFilePath);
      if (expected === null || !sameRegularIdentity(expected, current)) {
        throw new ChannelPersistenceUnavailableError();
      }
    } catch (error) {
      if (isNodeFileError(error, 'ENOENT') && expected === null) return;
      throw error;
    }
  }

  private async cleanupOwnedTemporary(
    temporaryPath: string,
    identity: FileIdentity,
  ): Promise<void> {
    try {
      const current = await this.fileSystem.lstat(temporaryPath);
      if (!sameRegularIdentity(identity, current)) {
        this.warn('CHANNEL_TEMP_CLEANUP_MISMATCH');
        return;
      }
      await this.fileSystem.unlink(temporaryPath);
    } catch (error) {
      if (!isNodeFileError(error, 'ENOENT')) {
        this.warn('CHANNEL_TEMP_CLEANUP_MISMATCH');
      }
    }
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

const NODE_FILE_SYSTEM: DesktopChannelPersistenceFileSystem = {
  lstat: (filePath) => fs.lstat(filePath),
  open: async (filePath, flags, mode) => {
    const handle = await fs.open(filePath, flags, mode);
    return {
      readFile: (encoding) => handle.readFile({ encoding }),
      writeFile: async (content, encoding) => {
        await handle.writeFile(content, { encoding });
      },
      chmod: (nextMode) => handle.chmod(nextMode),
      sync: () => handle.sync(),
      stat: () => handle.stat(),
      close: () => handle.close(),
    };
  },
  rename: (sourcePath, destinationPath) => fs.rename(sourcePath, destinationPath),
  unlink: (filePath) => fs.unlink(filePath),
};

function parseOuterFile(content: string, allowRepair: boolean): ParsedOuterFile {
  let value: unknown;
  try {
    value = JSON.parse(content);
  } catch {
    throw new CorruptChannelPersistenceFileError();
  }
  if (!isPlainOwnRecord(value)) throw new CorruptChannelPersistenceFileError();
  if (value.schemaVersion !== CHANNEL_PERSISTENCE_SCHEMA_VERSION) {
    throw new UnsupportedChannelPersistenceSchemaError();
  }
  const stored = value.storedChannelData;
  if (stored !== null) {
    const decoded = decodeStoredChannelData(JSON.stringify(stored));
    if (decoded === null || !isCompleteStoredChannelData(decoded)) {
      throw new CorruptChannelPersistenceFileError();
    }
  }
  const storedChannelData = stored as StoredChannelData | null;
  const normalizedCurrent = normalizeCurrentChannelId(value.currentChannelId);
  const nestedCurrent = normalizeCurrentChannelId(storedChannelData?.currentChannelId ?? null);
  let needsRepair = normalizedCurrent !== value.currentChannelId || nestedCurrent !== normalizedCurrent;
  let lineupRevision = 0;
  let invalidRevision = false;
  if (Object.prototype.hasOwnProperty.call(value, 'lineupRevision')) {
    if (Number.isSafeInteger(value.lineupRevision) && (value.lineupRevision as number) >= 0) {
      lineupRevision = value.lineupRevision as number;
    } else if (allowRepair) {
      needsRepair = true;
      invalidRevision = true;
    } else {
      throw new CorruptChannelPersistenceFileError();
    }
  }
  let channelBuilderState: ChannelBuilderPersistedStateV1 | null = null;
  if (Object.prototype.hasOwnProperty.call(value, 'channelBuilderState')) {
    const normalizedBuilder = normalizeChannelBuilderPersistedStateV1(
      value.channelBuilderState,
      new Set(storedChannelData?.channels.map((channel) => channel.id) ?? []),
    );
    if (normalizedBuilder.result !== null) {
      channelBuilderState = invalidRevision ? null : normalizedBuilder.result;
      needsRepair ||= normalizedBuilder.didMutate;
    } else if (allowRepair) {
      needsRepair = true;
    } else {
      throw new CorruptChannelPersistenceFileError();
    }
  }
  if (needsRepair && !allowRepair) throw new CorruptChannelPersistenceFileError();
  return {
    needsRepair,
    aggregate: {
      storedChannelData:
        storedChannelData === null
          ? null
          : { ...storedChannelData, currentChannelId: normalizedCurrent },
      currentChannelId: normalizedCurrent,
      lineupRevision,
      channelBuilderState,
    },
  };
}

function serializeAggregate(aggregate: ChannelAggregate): string {
  const value: Record<string, unknown> = {
    schemaVersion: CHANNEL_PERSISTENCE_SCHEMA_VERSION,
    storedChannelData: aggregate.storedChannelData,
    currentChannelId: aggregate.currentChannelId,
    lineupRevision: aggregate.lineupRevision,
  };
  if (aggregate.channelBuilderState !== null) {
    value.channelBuilderState = aggregate.channelBuilderState;
  }
  return `${JSON.stringify(value, null, 2)}\n`;
}

function validateReplacementAggregate(
  value: unknown,
  kind: ChannelAggregateMutationRequest['kind'],
): ChannelAggregate {
  if (!isPlainOwnRecord(value)) throw new CorruptChannelPersistenceFileError();
  const keys = Object.keys(value);
  if (
    keys.length !== 4 ||
    !['storedChannelData', 'currentChannelId', 'lineupRevision', 'channelBuilderState'].every(
      (key) => keys.includes(key),
    )
  ) {
    throw new CorruptChannelPersistenceFileError();
  }
  const stored = value.storedChannelData;
  if (
    stored !== null &&
    (decodeStoredChannelData(JSON.stringify(stored)) === null ||
      !isCompleteStoredChannelData(stored))
  ) {
    throw new CorruptChannelPersistenceFileError();
  }
  if (
    !Number.isSafeInteger(value.lineupRevision) ||
    (value.lineupRevision as number) < 0 ||
    (value.channelBuilderState !== null &&
      !isChannelBuilderPersistedStateV1(value.channelBuilderState))
  ) {
    throw new CorruptChannelPersistenceFileError();
  }
  const currentChannelId = normalizeCurrentChannelId(value.currentChannelId);
  if (currentChannelId !== value.currentChannelId) throw new CorruptChannelPersistenceFileError();
  const data = stored as StoredChannelData | null;
  if (
    data !== null &&
    normalizeCurrentChannelId(data.currentChannelId) !== currentChannelId
  ) {
    throw new CorruptChannelPersistenceFileError();
  }
  if (
    kind !== 'current-channel' &&
    data !== null &&
    new Set(data.channels.map((channel) => channel.id)).size !== data.channels.length
  ) {
    throw new CorruptChannelPersistenceFileError();
  }
  return value as unknown as ChannelAggregate;
}

function cloneAggregate(value: ChannelAggregate): ChannelAggregate {
  return {
    storedChannelData:
      value.storedChannelData === null
        ? null
        : {
            ...value.storedChannelData,
            channels: value.storedChannelData.channels.map(cloneChannelForOwnership),
            channelOrder: [...value.storedChannelData.channelOrder],
          },
    currentChannelId: value.currentChannelId,
    lineupRevision: value.lineupRevision,
    channelBuilderState:
      value.channelBuilderState === null
        ? null
        : {
            ...value.channelBuilderState,
            normalizedConfig: {
              ...value.channelBuilderState.normalizedConfig,
              selectedLibraryIds: [
                ...value.channelBuilderState.normalizedConfig.selectedLibraryIds,
              ],
              strategyConfig: Object.fromEntries(
                Object.entries(
                  value.channelBuilderState.normalizedConfig.strategyConfig,
                ).map(([key, strategy]) => [key, { ...strategy }]),
              ) as ChannelBuilderPersistedStateV1['normalizedConfig']['strategyConfig'],
              channelExpansion: {
                ...value.channelBuilderState.normalizedConfig.channelExpansion,
              },
              seriesOrdering: {
                ...value.channelBuilderState.normalizedConfig.seriesOrdering,
              },
            },
            channelProvenance: cloneChannelBuilderProvenance(
              value.channelBuilderState.channelProvenance,
            ),
          },
  };
}

function aggregateBytes(value: ChannelAggregate): string {
  return JSON.stringify(value);
}

function emptyAggregate(): ChannelAggregate {
  return {
    storedChannelData: null,
    currentChannelId: null,
    lineupRevision: 0,
    channelBuilderState: null,
  };
}

function normalizeCurrentChannelId(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function isCompleteStoredChannelData(value: unknown): value is StoredChannelData {
  if (!isPlainOwnRecord(value)) return false;
  return (
    Array.isArray(value.channels) &&
    Array.isArray(value.channelOrder) &&
    (value.currentChannelId === null || typeof value.currentChannelId === 'string') &&
    typeof value.savedAt === 'number' &&
    Number.isFinite(value.savedAt)
  );
}

function isPlainOwnRecord(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function sameRegularIdentity(
  expected: FileIdentity,
  actual: DesktopChannelPersistenceFileStat,
): boolean {
  return (
    actual.isFile() &&
    !actual.isSymbolicLink() &&
    actual.dev === expected.dev &&
    actual.ino === expected.ino
  );
}

function isNodeFileError(error: unknown, code: string): boolean {
  return (
    error !== null &&
    typeof error === 'object' &&
    'code' in error &&
    (error as { code?: unknown }).code === code
  );
}
