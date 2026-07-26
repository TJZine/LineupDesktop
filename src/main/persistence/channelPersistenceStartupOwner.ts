import {
  ChannelPersistenceStore,
  type ChannelAggregate,
  type ChannelAggregateMutationRequest,
  type ChannelAggregateMutationResult,
  type ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import type { ChannelClock } from '../../domain/channel/interfaces.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import type { DesktopChannelPersistenceStore } from './desktopChannelPersistenceStore.js';

export type ChannelPersistenceStartupError =
  | Readonly<{
      code: 'CHANNEL_STORAGE_CORRUPT';
      message: 'Channel storage could not be loaded.';
    }>
  | Readonly<{
      code: 'CHANNEL_STORAGE_UNAVAILABLE';
      message: 'Channel storage is unavailable.';
    }>;

export type ChannelPersistenceStartupResult =
  | Readonly<{
      ok: true;
      aggregate: ChannelAggregate;
      repaired: boolean;
    }>
  | Readonly<{ ok: false; error: ChannelPersistenceStartupError }>;

export class ChannelPersistenceStartupOwner {
  public constructor(
    private readonly options: Readonly<{
      store: DesktopChannelPersistenceStore;
      clock: ChannelClock;
    }>,
  ) {}

  public async loadAndRepair(): Promise<ChannelPersistenceStartupResult> {
    try {
      const loaded = await this.options.store.loadForStartup();
      const memory = new StartupAggregateStorage(loaded.aggregate);
      const repository = new ChannelRepository({
        store: new ChannelPersistenceStore(memory),
        clock: this.options.clock,
      });
      const normalized = await repository.loadNormalized();
      const aggregate: ChannelAggregate = {
        ...loaded.aggregate,
        storedChannelData: normalized?.data ?? null,
        currentChannelId: normalized?.data.currentChannelId ?? null,
      };
      const repaired =
        loaded.present &&
        (loaded.needsRepair ||
          normalized?.didMutate === true ||
          JSON.stringify(aggregate) !== JSON.stringify(loaded.aggregate));
      if (repaired && loaded.destinationIdentity !== null) {
        await this.options.store.repairForStartup(aggregate, loaded.destinationIdentity);
      }
      return { ok: true, aggregate, repaired };
    } catch (error) {
      if (
        error instanceof Error &&
        (error.name === 'CorruptChannelPersistenceFileError' ||
          error.name === 'UnsupportedChannelPersistenceSchemaError' ||
          error.name === 'CorruptChannelPersistenceDataError')
      ) {
        return {
          ok: false,
          error: {
            code: 'CHANNEL_STORAGE_CORRUPT',
            message: 'Channel storage could not be loaded.',
          },
        };
      }
      return {
        ok: false,
        error: {
          code: 'CHANNEL_STORAGE_UNAVAILABLE',
          message: 'Channel storage is unavailable.',
        },
      };
    }
  }
}

class StartupAggregateStorage implements ChannelPersistenceStoragePort {
  public constructor(private aggregate: ChannelAggregate) {}

  public async readStoredChannelData(): Promise<string | null> {
    return this.aggregate.storedChannelData === null
      ? null
      : JSON.stringify(this.aggregate.storedChannelData);
  }

  public async writeStoredChannelData(encoded: string): Promise<void> {
    this.aggregate = {
      ...this.aggregate,
      storedChannelData: JSON.parse(encoded) as StoredChannelData,
    };
  }

  public async clearStoredChannelData(): Promise<void> {
    this.aggregate = { ...this.aggregate, storedChannelData: null, currentChannelId: null };
  }

  public async readCurrentChannelId(): Promise<string | null> {
    return this.aggregate.currentChannelId;
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    this.aggregate = { ...this.aggregate, currentChannelId: channelId };
  }

  public async readChannelAggregate(): Promise<ChannelAggregate> {
    return this.aggregate;
  }

  public async mutateChannelAggregate(
    request: ChannelAggregateMutationRequest,
  ): Promise<ChannelAggregateMutationResult> {
    this.aggregate = request.mutate(this.aggregate);
    return { status: 'committed', aggregate: this.aggregate };
  }
}
