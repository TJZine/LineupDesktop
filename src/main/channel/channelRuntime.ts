import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupAcceptedOperation,
  type ChannelSetupCancelResult,
  type ChannelSetupIpcResult,
  type ChannelSetupOperationResult,
  type ChannelSetupRuntimeError,
  type ChannelSetupSummary,
  type NormalizedChannelSetupConfig,
} from '../../contracts/channel.js';
import type { ChannelClock, ChannelLogger } from '../../domain/channel/index.js';
import {
  ChannelPersistenceStore,
  type ChannelAggregate,
  type ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import type { ChannelBuilderRuntime } from './channelBuilderRuntime.js';
import type {
  ChannelPublicReferenceOwner,
  ChannelPublicReferenceGeneration,
} from './channelPublicReferenceOwner.js';

export interface ChannelRuntimeOptions {
  storage: ChannelPersistenceStoragePort;
  builderRuntime: ChannelBuilderRuntime;
  publicReferenceOwner: ChannelPublicReferenceOwner;
  clock?: ChannelClock;
  logger?: ChannelLogger;
}

export class ChannelRuntime {
  private readonly store: ChannelPersistenceStore;
  private readonly repository: ChannelRepository;
  private readonly builderRuntime: ChannelBuilderRuntime;
  private readonly clock: ChannelClock;
  private readonly publicReferenceOwner: ChannelPublicReferenceOwner;

  constructor(options: ChannelRuntimeOptions) {
    this.clock = options.clock ?? { now: () => Date.now() };
    this.store = new ChannelPersistenceStore(options.storage);
    this.repository = new ChannelRepository({
      store: this.store,
      clock: this.clock,
      logger: options.logger,
    });
    this.builderRuntime = options.builderRuntime;
    this.publicReferenceOwner = options.publicReferenceOwner;
  }

  getRepository(): ChannelRepository {
    return this.repository;
  }

  readChannelAggregate(): Promise<ChannelAggregate> {
    return this.store.readChannelAggregate();
  }

  async loadPublicReferenceGeneration(): Promise<ChannelPublicReferenceGeneration> {
    return this.publicReferenceOwner.createGeneration(await this.store.readChannelAggregate());
  }

  async getStatus(requestId: string): Promise<ChannelSetupIpcResult<ChannelSetupSummary>> {
    try {
      const aggregate = await this.store.readChannelAggregate();
      const generation = this.publicReferenceOwner.createGeneration(aggregate);
      return channelSetupSuccess(
        requestId,
        this.publicReferenceOwner.projectStatus(generation, aggregate, this.clock.now()),
      );
    } catch (error) {
      return channelSetupFailure(requestId, mapStorageError(error, 'getStatus'));
    }
  }

  startReview(
    requestId: string,
    config: NormalizedChannelSetupConfig,
  ): ChannelSetupIpcResult<ChannelSetupAcceptedOperation> {
    return this.builderRuntime.startReview(requestId, config);
  }

  startApply(
    requestId: string,
    input: Readonly<{ planId: string; confirmReplace: boolean }>,
  ): ChannelSetupIpcResult<ChannelSetupAcceptedOperation> {
    return this.builderRuntime.startApply(requestId, input);
  }

  getOperation(
    requestId: string,
    operationId: string,
  ): ChannelSetupIpcResult<ChannelSetupOperationResult> {
    return this.builderRuntime.getOperation(requestId, operationId);
  }

  cancel(
    requestId: string,
    operationId: string,
  ): ChannelSetupIpcResult<ChannelSetupCancelResult> {
    return this.builderRuntime.cancel(requestId, operationId);
  }

  shutdown(): void {
    this.builderRuntime.shutdown();
  }
}

function mapStorageError(
  error: unknown,
  operation: 'getStatus' | 'startReview' | 'startApply',
): ChannelSetupRuntimeError {
  const corrupt =
    error instanceof SyntaxError ||
    (error instanceof Error &&
      (
        error.name === 'CorruptChannelPersistenceDataError' ||
        error.name === 'CorruptChannelPersistenceFileError' ||
        error.name === 'UnsupportedChannelPersistenceSchemaError'
      ));
  return {
    code: corrupt ? 'CHANNEL_STORAGE_CORRUPT' : 'CHANNEL_STORAGE_UNAVAILABLE',
    message: corrupt
      ? 'Channel storage could not be loaded.'
      : 'Channel storage is unavailable.',
    retryable: !corrupt,
    recoverable: true,
    operation,
  };
}
