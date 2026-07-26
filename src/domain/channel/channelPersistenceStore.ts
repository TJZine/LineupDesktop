import { decodeStoredChannelData, encodeStoredChannelData } from './storedChannelDataCodec.js';
import type { StoredChannelData } from './types.js';
import type { ChannelBuilderPersistedStateV1 } from '../channelBuilder/types.js';

export class CorruptChannelPersistenceDataError extends Error {
  public constructor() {
    super('Stored channel data is corrupt.');
    this.name = 'CorruptChannelPersistenceDataError';
  }
}

export interface ChannelPersistenceStoragePort {
  readStoredChannelData(): Promise<string | null>;
  /**
   * Persists the complete stored channel snapshot. Implementations that keep a
   * separate current-channel index must update that index from the encoded
   * snapshot in the same mutation.
   */
  writeStoredChannelData(encoded: string): Promise<void>;
  /**
   * Clears the stored channel snapshot and any separate current-channel pointer
   * in one storage mutation.
   */
  clearStoredChannelData(): Promise<void>;
  readCurrentChannelId(): Promise<string | null>;
  writeCurrentChannelId(channelId: string | null): Promise<void>;
  readChannelAggregate(): Promise<ChannelAggregate>;
  mutateChannelAggregate(
    request: ChannelAggregateMutationRequest,
  ): Promise<ChannelAggregateMutationResult>;
}

export type ChannelAggregate = Readonly<{
  storedChannelData: StoredChannelData | null;
  currentChannelId: string | null;
  lineupRevision: number;
  channelBuilderState: ChannelBuilderPersistedStateV1 | null;
}>;

export type ChannelAggregateMutate = (
  current: Readonly<ChannelAggregate>,
) => ChannelAggregate;

export type ChannelAggregateMutationRequest =
  | Readonly<{
      kind: 'builder-lineup';
      expectedLineupRevision: number;
      mutate: ChannelAggregateMutate;
      onCommitBarrier: () => 'proceed' | 'cancel';
    }>
  | Readonly<{
      kind: 'custom-lineup';
      expectedLineupRevision: null;
      mutate: ChannelAggregateMutate;
      onCommitBarrier: () => 'proceed' | 'cancel';
    }>
  | Readonly<{
      kind: 'current-channel';
      mutate: ChannelAggregateMutate;
      onCommitBarrier: () => 'proceed' | 'cancel';
    }>;

export type ChannelAggregateMutationResult =
  | Readonly<{ status: 'committed'; aggregate: ChannelAggregate }>
  | Readonly<{ status: 'conflict'; actualLineupRevision: number }>
  | Readonly<{ status: 'canceled' }>;

export class ChannelPersistenceStore {
  public constructor(private readonly storage: ChannelPersistenceStoragePort) {}

  public async readStoredChannelData(): Promise<Partial<StoredChannelData> | null> {
    const raw = await this.storage.readStoredChannelData();
    if (raw === null) {
      return null;
    }
    if (raw.trim().length === 0) {
      return null;
    }

    const parsed = decodeStoredChannelData(raw);
    if (parsed === null) {
      throw new CorruptChannelPersistenceDataError();
    }
    return parsed;
  }

  public async writeStoredChannelData(data: StoredChannelData): Promise<void> {
    await this.storage.writeStoredChannelData(encodeStoredChannelData(data));
  }

  public async clearStoredChannelData(): Promise<void> {
    await this.storage.clearStoredChannelData();
  }

  public async readCurrentChannelId(): Promise<string | null> {
    const raw = await this.storage.readCurrentChannelId();
    if (raw === null) {
      return null;
    }

    const normalized = raw.trim();
    if (normalized.length === 0) {
      return null;
    }
    return normalized;
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    const normalized = channelId?.trim() ?? '';
    await this.storage.writeCurrentChannelId(normalized.length > 0 ? normalized : null);
  }

  public readChannelAggregate(): Promise<ChannelAggregate> {
    return this.storage.readChannelAggregate();
  }

  public mutateChannelAggregate(
    request: ChannelAggregateMutationRequest,
  ): Promise<ChannelAggregateMutationResult> {
    return this.storage.mutateChannelAggregate(request);
  }
}
