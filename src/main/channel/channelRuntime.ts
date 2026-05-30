import {
  type ChannelClock,
  type ChannelLogger,
} from '../../domain/channel/index.js';
import { ChannelPersistenceStore, type ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import type { ChannelConfig } from '../../domain/channel/types.js';
import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupIpcResult,
  type ChannelSetupRuntimeError,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';

export interface ChannelRuntimeOptions {
  storage: ChannelPersistenceStoragePort;
  clock?: ChannelClock;
  logger?: ChannelLogger;
}

export class ChannelRuntime {
  private readonly repository: ChannelRepository;
  private readonly clock: ChannelClock;

  public constructor(options: ChannelRuntimeOptions) {
    this.clock = options.clock ?? { now: () => Date.now() };
    this.repository = new ChannelRepository({
      store: new ChannelPersistenceStore(options.storage),
      clock: this.clock,
      logger: options.logger,
    });
  }

  public async getStatus(
    requestId: string,
  ): Promise<ChannelSetupIpcResult<ChannelSetupSummary>> {
    try {
      const loaded = await this.repository.loadNormalized();
      if (loaded === null) {
        return channelSetupSuccess(requestId, {
          status: 'not-configured',
          channelCount: 0,
          currentChannelId: null,
          currentChannelNumber: null,
          currentChannelName: null,
          channelNumbers: [],
          updatedAtMs: this.clock.now(),
          recovery: { loaded: false, repaired: false },
        });
      }

      return channelSetupSuccess(requestId, summarizeLoadedChannels({
        channels: loaded.data.channels,
        currentChannelId: loaded.data.currentChannelId,
        repaired: loaded.didMutate,
        updatedAtMs: this.clock.now(),
      }));
    } catch (error) {
      return channelSetupFailure(requestId, mapChannelRuntimeError(error));
    }
  }
}

function summarizeLoadedChannels(input: {
  channels: readonly ChannelConfig[];
  currentChannelId: string | null;
  repaired: boolean;
  updatedAtMs: number;
}): ChannelSetupSummary {
  const currentChannel =
    input.currentChannelId === null
      ? null
      : input.channels.find((channel) => channel.id === input.currentChannelId) ?? null;

  return {
    status: input.channels.length > 0 ? 'configured' : 'not-configured',
    channelCount: input.channels.length,
    currentChannelId: currentChannel?.id ?? null,
    currentChannelNumber: currentChannel?.number ?? null,
    currentChannelName: currentChannel?.name ?? null,
    channelNumbers: input.channels.map((channel) => channel.number),
    updatedAtMs: input.updatedAtMs,
    recovery: {
      loaded: input.channels.length > 0,
      repaired: input.repaired,
    },
  };
}

function mapChannelRuntimeError(error: unknown): ChannelSetupRuntimeError {
  const code =
    error instanceof SyntaxError
      ? 'CHANNEL_STORAGE_CORRUPT'
      : error instanceof Error && error.name === 'CorruptChannelPersistenceDataError'
        ? 'CHANNEL_STORAGE_CORRUPT'
        : error instanceof Error && error.name === 'CorruptChannelPersistenceFileError'
          ? 'CHANNEL_STORAGE_CORRUPT'
          : error instanceof Error && error.name === 'UnsupportedChannelPersistenceSchemaError'
            ? 'CHANNEL_STORAGE_CORRUPT'
            : 'CHANNEL_STORAGE_UNAVAILABLE';

  return {
    code,
    message:
      code === 'CHANNEL_STORAGE_CORRUPT'
        ? 'Channel setup data could not be recovered.'
        : 'Channel setup storage is unavailable.',
    retryable: true,
    recoverable: true,
    operation: 'getStatus',
  };
}
