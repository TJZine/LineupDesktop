import {
  customChannelFailure,
  customChannelSuccess,
  type CustomChannelDraftInput,
  type CustomChannelContentEntryInput,
  type CustomChannelDraftResult,
  type CustomChannelDraftValidationSummary,
  type CustomChannelIpcResult,
  type CustomChannelMutationResult,
  type CustomChannelOperation,
  type CustomChannelRuntimeError,
  type CustomChannelSnapshot,
} from '../../contracts/customChannels.js';
import {
  buildCustomChannelCreateInput,
  ChannelAuthoringService,
  type ChannelClock,
  type ChannelConfig,
  type ChannelContentSource,
  type ChannelCreateInput,
  type ChannelLogger,
  type StoredChannelData,
} from '../../domain/channel/index.js';
import {
  ChannelPersistenceStore,
  type ChannelAggregate,
  type ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import { cloneOwnEnumerableStringRecordWithNullPrototype } from '../../domain/channel/channelDomainClone.js';
import type { ChannelBuilderChannelProvenanceV1 } from '../../domain/channelBuilder/types.js';
import {
  findNextAvailableNumber,
  orderChannels,
  summarizeCustomChannelSnapshot,
} from './customChannelMutationMapper.js';
import { recordCustomChannelDiagnostic } from './customChannelDiagnostics.js';
import type { CustomChannelRefreshReason, CustomChannelSchedulerRefreshHook } from './customChannelSchedulerRefresh.js';
import { ChannelLineupMutationCoordinator } from './channelLineupMutationCoordinator.js';

export interface CustomChannelRuntimeOptions {
  storage: ChannelPersistenceStoragePort;
  clock?: ChannelClock;
  logger?: Pick<ChannelLogger, 'warn'>;
  generateId?: () => string;
  onChannelsChanged?: CustomChannelSchedulerRefreshHook;
  mutationCoordinator?: ChannelLineupMutationCoordinator;
}

export class CustomChannelRuntime {
  private readonly repository: ChannelRepository;
  private readonly clock: ChannelClock;
  private readonly authoring: ChannelAuthoringService;
  private readonly logger?: Pick<ChannelLogger, 'warn'>;
  private readonly onChannelsChanged?: CustomChannelSchedulerRefreshHook;
  private readonly mutationCoordinator: ChannelLineupMutationCoordinator;

  public constructor(options: CustomChannelRuntimeOptions) {
    this.clock = options.clock ?? { now: () => Date.now() };
    this.logger = options.logger;
    this.onChannelsChanged = options.onChannelsChanged;
    const store = new ChannelPersistenceStore(options.storage);
    this.repository = new ChannelRepository({
      store,
      clock: this.clock,
      logger: options.logger,
    });
    this.mutationCoordinator =
      options.mutationCoordinator ?? new ChannelLineupMutationCoordinator(store);
    this.authoring = new ChannelAuthoringService({
      generateId: options.generateId ?? (() => `channel-${this.clock.now()}-${Math.random().toString(36).slice(2)}`),
      now: () => this.clock.now(),
    });
  }

  public getRepository(): ChannelRepository {
    return this.repository;
  }

  public async getSnapshot(
    requestId: string,
  ): Promise<CustomChannelIpcResult<CustomChannelSnapshot>> {
    try {
      return customChannelSuccess(requestId, await this.loadSnapshot());
    } catch (error) {
      return this.failure(requestId, 'getSnapshot', error);
    }
  }

  public async validateDraft(
    requestId: string,
    draft: CustomChannelDraftInput,
  ): Promise<CustomChannelIpcResult<CustomChannelDraftValidationSummary>> {
    try {
      const loaded = await this.repository.loadNormalized();
      return customChannelSuccess(requestId, this.validateDraftAgainstChannels(draft, loaded?.data.channels ?? []));
    } catch (error) {
      return this.failure(requestId, 'validateDraft', error);
    }
  }

  public async saveDraft(
    requestId: string,
    draft: CustomChannelDraftInput,
  ): Promise<CustomChannelIpcResult<CustomChannelMutationResult>> {
    return this.enqueueMutation(requestId, 'saveDraft', async () => {
      const outcome: {
        rejection: CustomChannelIpcResult<CustomChannelMutationResult> | null;
        changedChannelId: string | null;
      } = { rejection: null, changedChannelId: null };
      const mutation = await this.mutationCoordinator.mutateCustomLineup({
        mutate: (current) => {
          const state = stateFromLoaded(current.storedChannelData ?? undefined);
          const validation = this.validateDraftAgainstChannels(draft, state.channels);
          if (!validation.valid) {
            outcome.rejection = customChannelFailure(requestId, validationError('saveDraft'));
            return current as typeof current;
          }
          const build = buildCustomChannelCreateInput(draft, state.channels);
          if (!build.ok) {
            outcome.rejection = customChannelFailure(requestId, validationError('saveDraft'));
            return current as typeof current;
          }
          const existingIndex = draft.id === undefined
            ? -1
            : state.channels.findIndex((channel) => channel.id === draft.id);
          if (draft.id !== undefined && existingIndex < 0) {
            outcome.rejection = customChannelFailure(requestId, notFoundError('saveDraft'));
            return current as typeof current;
          }
          if (existingIndex >= 0 && !hasExpectedRevision(draft, state.channels[existingIndex]!)) {
            outcome.rejection = customChannelFailure(requestId, conflictError('saveDraft'));
            return current as typeof current;
          }
          const savedAt = this.clock.now();
          const changedChannel = existingIndex >= 0
            ? this.updateExistingChannel(state.channels, existingIndex, build.input)
            : this.createNewChannel(state.channels, build.input);
          changedChannel.itemCount = estimateItemCount(changedChannel);
          changedChannel.totalDurationMs = estimateDurationMs(changedChannel);
          changedChannel.lastContentRefresh = savedAt;
          const currentChannelId = existingIndex >= 0 &&
            state.currentChannelId === changedChannel.id &&
            changedChannel.hidden === true
            ? chooseAdjacentVisibleChannelId(state.channels, existingIndex, changedChannel.id)
            : keepVisibleCurrentOrFirst(state.currentChannelId, state.channels);
          outcome.changedChannelId = changedChannel.id;
          return aggregateWithCustomState(current, {
            channels: state.channels,
            channelOrder: ensureOrderForChannels(state.channelOrder, state.channels),
            currentChannelId,
            savedAt,
          }, existingIndex >= 0 ? [changedChannel.id] : []);
        },
        shouldCommit: () => outcome.rejection === null,
      });
      if (outcome.rejection !== null) return outcome.rejection;
      if (mutation.status !== 'committed' || outcome.changedChannelId === null) {
        throw new Error('Custom channel save did not commit.');
      }
      const snapshot = snapshotFromAggregate(mutation.aggregate, this.clock.now());
      await this.refresh('saveDraft', 'save', outcome.changedChannelId);
      return customChannelSuccess(
        requestId,
        mutationResult(snapshot, outcome.changedChannelId),
      );
    });
  }

  public async deleteChannel(
    requestId: string,
    payload: { channelId: string; confirm: boolean },
  ): Promise<CustomChannelIpcResult<CustomChannelMutationResult>> {
    return this.enqueueMutation(requestId, 'deleteChannel', async () => {
      if (payload.confirm !== true) return customChannelFailure(requestId, validationError('deleteChannel'));
      let rejected = false;
      const mutation = await this.mutationCoordinator.mutateCustomLineup({
        mutate: (current) => {
          const state = stateFromLoaded(current.storedChannelData ?? undefined);
          const deletedIndex = state.channels.findIndex(
            (channel) => channel.id === payload.channelId,
          );
          if (deletedIndex < 0) {
            rejected = true;
            return current as typeof current;
          }
          const nextChannels = state.channels.filter(
            (channel) => channel.id !== payload.channelId,
          );
          return aggregateWithCustomState(current, {
            channels: nextChannels,
            channelOrder: state.channelOrder.filter((id) => id !== payload.channelId),
            currentChannelId: state.currentChannelId === payload.channelId
              ? chooseAdjacentVisibleChannelId(
                  state.channels,
                  deletedIndex,
                  payload.channelId,
                )
              : keepVisibleCurrentOrFirst(state.currentChannelId, nextChannels),
            savedAt: this.clock.now(),
          }, [payload.channelId]);
        },
        shouldCommit: () => !rejected,
      });
      if (rejected) return customChannelFailure(requestId, notFoundError('deleteChannel'));
      if (mutation.status !== 'committed') throw new Error('Custom channel delete did not commit.');
      const snapshot = snapshotFromAggregate(mutation.aggregate, this.clock.now());
      await this.refresh('deleteChannel', 'delete', payload.channelId);
      return customChannelSuccess(requestId, mutationResult(snapshot, payload.channelId));
    });
  }

  public async duplicateChannelDraft(
    requestId: string,
    channelId: string,
  ): Promise<CustomChannelIpcResult<CustomChannelDraftResult>> {
    try {
      const state = stateFromLoaded((await this.repository.loadNormalized())?.data);
      const channel = state.channels.find((candidate) => candidate.id === channelId);
      if (channel === undefined) {
        return customChannelFailure(requestId, notFoundError('duplicateChannelDraft'));
      }
      const draft = draftFromChannel(channel, findNextAvailableNumber(state.channels) ?? channel.number);
      return customChannelSuccess(requestId, {
        draft,
        validation: this.validateDraftAgainstChannels(draft, state.channels),
      });
    } catch (error) {
      return this.failure(requestId, 'duplicateChannelDraft', error);
    }
  }

  public async reorderChannels(
    requestId: string,
    channelIds: readonly string[],
  ): Promise<CustomChannelIpcResult<CustomChannelMutationResult>> {
    return this.enqueueMutation(requestId, 'reorderChannels', async () => {
      let rejected = false;
      const mutation = await this.mutationCoordinator.mutateCustomLineup({
        mutate: (current) => {
          const state = stateFromLoaded(current.storedChannelData ?? undefined);
          if (!isCompleteChannelOrder(channelIds, state.channels)) {
            rejected = true;
            return current as typeof current;
          }
          return aggregateWithCustomState(current, {
            channels: state.channels,
            channelOrder: [...channelIds],
            currentChannelId: keepVisibleCurrentOrFirst(
              state.currentChannelId,
              state.channels,
            ),
            savedAt: this.clock.now(),
          }, []);
        },
        shouldCommit: () => !rejected,
      });
      if (rejected) return customChannelFailure(requestId, validationError('reorderChannels'));
      if (mutation.status !== 'committed') throw new Error('Custom channel reorder did not commit.');
      const snapshot = snapshotFromAggregate(mutation.aggregate, this.clock.now());
      await this.refresh('reorderChannels', 'reorder', null);
      return customChannelSuccess(requestId, mutationResult(snapshot, null));
    });
  }

  public async setChannelVisibility(
    requestId: string,
    payload: { channelId: string; hidden: boolean },
  ): Promise<CustomChannelIpcResult<CustomChannelMutationResult>> {
    return this.enqueueMutation(requestId, 'setChannelVisibility', async () => {
      if (typeof payload.hidden !== 'boolean') {
        return customChannelFailure(requestId, validationError('setChannelVisibility'));
      }
      let rejected = false;
      const mutation = await this.mutationCoordinator.mutateCustomLineup({
        mutate: (current) => {
          const state = stateFromLoaded(current.storedChannelData ?? undefined);
          const channel = state.channels.find(
            (candidate) => candidate.id === payload.channelId,
          );
          if (channel === undefined) {
            rejected = true;
            return current as typeof current;
          }
          channel.hidden = payload.hidden;
          channel.updatedAt = this.clock.now();
          const channelIndex = state.channels.findIndex(
            (candidate) => candidate.id === payload.channelId,
          );
          return aggregateWithCustomState(current, {
            channels: state.channels,
            channelOrder: state.channelOrder,
            currentChannelId:
              state.currentChannelId === payload.channelId && payload.hidden
                ? chooseAdjacentVisibleChannelId(
                    state.channels,
                    channelIndex,
                    payload.channelId,
                  )
                : keepVisibleCurrentOrFirst(
                    state.currentChannelId,
                    state.channels,
                  ),
            savedAt: this.clock.now(),
          }, []);
        },
        shouldCommit: () => !rejected,
      });
      if (rejected) {
        return customChannelFailure(requestId, notFoundError('setChannelVisibility'));
      }
      if (mutation.status !== 'committed') {
        throw new Error('Custom channel visibility did not commit.');
      }
      const snapshot = snapshotFromAggregate(mutation.aggregate, this.clock.now());
      await this.refresh('setChannelVisibility', 'visibility', payload.channelId);
      return customChannelSuccess(requestId, mutationResult(snapshot, payload.channelId));
    });
  }

  private validateDraftAgainstChannels(
    draft: CustomChannelDraftInput,
    channels: readonly ChannelConfig[],
  ): CustomChannelDraftValidationSummary {
    const result = buildCustomChannelCreateInput(draft, channels);
    return { valid: result.ok, issues: result.ok ? [] : result.issues };
  }

  private createNewChannel(channels: ChannelConfig[], input: ChannelCreateInput): ChannelConfig {
    const channel = this.authoring.createChannel(input, channels);
    channels.push(channel);
    return channel;
  }

  private updateExistingChannel(
    channels: ChannelConfig[],
    index: number,
    input: ChannelCreateInput,
  ): ChannelConfig {
    const current = channels[index];
    const peers = channels.filter((_, candidateIndex) => candidateIndex !== index);
    const updated = this.authoring.updateChannel(current, input, peers);
    channels[index] = updated;
    return updated;
  }

  private async enqueueMutation<TValue>(
    requestId: string,
    operation: CustomChannelOperation,
    run: () => Promise<CustomChannelIpcResult<TValue>>,
  ): Promise<CustomChannelIpcResult<TValue>> {
    const result = await run().catch(
      (error: unknown) => this.failure<TValue>(requestId, operation, error),
    );
    recordCustomChannelDiagnostic(this.logger, {
      operation,
      status: result.ok ? 'succeeded' : 'failed',
      channelCount: result.ok && isMutationResult(result.value) ? result.value.snapshot.channels.length : undefined,
      changedChannelId: result.ok && isMutationResult(result.value) ? result.value.changedChannelId : undefined,
      errorCode: result.ok ? undefined : result.error.code,
    });
    return result;
  }

  private async loadSnapshot(): Promise<CustomChannelSnapshot> {
    const loaded = await this.repository.loadNormalized();
    return summarizeCustomChannelSnapshot({
      data: loaded?.data ?? null,
      repaired: loaded?.didMutate ?? false,
      updatedAtMs: this.clock.now(),
      storage: loaded === null ? 'not-configured' : 'ready',
    });
  }

  private async refresh(operation: CustomChannelOperation, reason: CustomChannelRefreshReason, changedChannelId: string | null): Promise<void> {
    try { await this.onChannelsChanged?.({ operation, reason, changedChannelId }); }
    catch { this.logger?.warn('Custom channel refresh failed after committed mutation.', { operation, reason, changedChannelId }); }
  }

  private failure<TValue>(
    requestId: string,
    operation: CustomChannelOperation,
    error: unknown,
  ): CustomChannelIpcResult<TValue> {
    const runtimeError = mapRuntimeError(error, operation);
    recordCustomChannelDiagnostic(this.logger, { operation, status: 'failed', errorCode: runtimeError.code });
    return customChannelFailure(requestId, runtimeError);
  }
}

function aggregateWithCustomState(
  current: Readonly<ChannelAggregate>,
  data: StoredChannelData,
  clearProvenanceIds: readonly string[],
): ChannelAggregate {
  const builder = current.channelBuilderState;
  return {
    ...current,
    storedChannelData: data,
    currentChannelId: data.currentChannelId,
    channelBuilderState:
      builder === null
        ? null
        : {
            ...builder,
            channelProvenance: cloneProvenanceWithout(
              builder.channelProvenance,
              clearProvenanceIds,
            ),
          },
  };
}

function cloneProvenanceWithout(
  provenance: Readonly<Record<string, ChannelBuilderChannelProvenanceV1>>,
  removedIds: readonly string[],
): Record<string, ChannelBuilderChannelProvenanceV1> {
  const cloned = cloneOwnEnumerableStringRecordWithNullPrototype(
    provenance,
    (marker) => ({ ...marker }),
  );
  for (const channelId of removedIds) delete cloned[channelId];
  return cloned;
}

function snapshotFromAggregate(
  aggregate: Readonly<ChannelAggregate>,
  updatedAtMs: number,
): CustomChannelSnapshot {
  return summarizeCustomChannelSnapshot({
    data: aggregate.storedChannelData,
    repaired: false,
    updatedAtMs,
    storage: 'ready',
  });
}

function stateFromLoaded(data: StoredChannelData | undefined): StoredChannelData {
  return {
    channels: orderChannels(data?.channels ?? [], data?.channelOrder ?? []),
    channelOrder: data?.channelOrder ?? [],
    currentChannelId: data?.currentChannelId ?? null,
    savedAt: data?.savedAt ?? 0,
  };
}

function mutationResult(
  snapshot: CustomChannelSnapshot,
  changedChannelId: string | null,
): CustomChannelMutationResult {
  return { snapshot, changedChannelId, currentChannelId: snapshot.currentChannelId };
}

function isMutationResult(value: unknown): value is CustomChannelMutationResult {
  return value !== null && typeof value === 'object' && 'snapshot' in value;
}

function hasExpectedRevision(draft: CustomChannelDraftInput, channel: ChannelConfig): boolean {
  return draft.expectedRevision === revisionForChannel(channel);
}

function revisionForChannel(channel: ChannelConfig): string {
  return `updatedAt:${String(channel.updatedAt)}`;
}

function keepVisibleCurrentOrFirst(currentChannelId: string | null, channels: readonly ChannelConfig[]): string | null {
  if (currentChannelId !== null && channels.some((channel) => channel.id === currentChannelId && channel.hidden !== true)) {
    return currentChannelId;
  }
  return channels.find((channel) => channel.hidden !== true)?.id ?? null;
}

function chooseAdjacentVisibleChannelId(
  orderedChannels: readonly ChannelConfig[],
  fromIndex: number,
  excludedChannelId: string,
): string | null {
  for (let index = fromIndex + 1; index < orderedChannels.length; index++) {
    const channel = orderedChannels[index];
    if (channel?.id !== excludedChannelId && channel?.hidden !== true) return channel.id;
  }
  for (let index = fromIndex - 1; index >= 0; index--) {
    const channel = orderedChannels[index];
    if (channel?.id !== excludedChannelId && channel?.hidden !== true) return channel.id;
  }
  return null;
}

function ensureOrderForChannels(channelOrder: readonly string[], channels: readonly ChannelConfig[]): string[] {
  const ids = new Set(channels.map((channel) => channel.id));
  const ordered = channelOrder.filter((id) => ids.delete(id));
  return [...ordered, ...channels.filter((channel) => ids.has(channel.id)).map((channel) => channel.id)];
}

function isCompleteChannelOrder(channelIds: readonly string[], channels: readonly ChannelConfig[]): boolean {
  if (channelIds.length !== channels.length) return false;
  const expected = new Set(channels.map((channel) => channel.id));
  const seen = new Set<string>();
  for (const id of channelIds) {
    if (!expected.has(id) || seen.has(id)) return false;
    seen.add(id);
  }
  return true;
}

function estimateItemCount(channel: ChannelConfig): number {
  return channel.contentSource.type === 'manual' ? channel.contentSource.items.length : channel.itemCount;
}

function estimateDurationMs(channel: ChannelConfig): number {
  return channel.contentSource.type === 'manual'
    ? channel.contentSource.items.reduce((sum, item) => sum + item.durationMs, 0)
    : channel.totalDurationMs;
}

function draftFromChannel(channel: ChannelConfig, number: number): CustomChannelDraftInput {
  return {
    number,
    name: `${channel.name} Copy`,
    description: channel.description,
    color: channel.color,
    icon: channel.icon,
    hidden: false,
    content: draftContentFromSource(channel.contentSource),
    playbackMode: channel.playbackMode,
    blockSize: channel.blockSize,
    sortOrder: channel.sortOrder,
    startTimeAnchor: channel.startTimeAnchor,
    skipIntros: channel.skipIntros,
    skipCredits: channel.skipCredits,
  };
}

function draftContentFromSource(source: ChannelContentSource): CustomChannelContentEntryInput[] {
  switch (source.type) {
    case 'library':
      return [{
        type: 'library',
        sourceId: source.libraryId,
        title: source.libraryId,
        mediaType: source.libraryType,
        includeWatched: source.includeWatched,
      }];
    case 'show':
      return [{
        type: 'show',
        sourceId: source.showKey,
        title: source.showName,
        ...(source.seasonFilter ? { seasonFilter: [...source.seasonFilter] } : {}),
      }];
    case 'collection':
      return [{ type: 'collection', sourceId: source.collectionKey, title: source.collectionName }];
    case 'playlist':
      return [{ type: 'playlist', sourceId: source.playlistKey, title: source.playlistName }];
    case 'manual':
      return source.items.map((item) => ({
        type: 'manualItem',
        ratingKey: item.ratingKey,
        title: item.title,
        durationMs: item.durationMs,
        mediaType: 'movie',
      }));
    case 'mixed':
      return source.sources.flatMap(draftContentFromSource);
  }
}

function validationError(operation: CustomChannelOperation): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_VALIDATION_FAILED',
    message: 'Custom channel request is invalid.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function notFoundError(operation: CustomChannelOperation): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_NOT_FOUND',
    message: 'Custom channel was not found.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function conflictError(operation: CustomChannelOperation): CustomChannelRuntimeError {
  return {
    code: 'CUSTOM_CHANNEL_CONFLICT',
    message: 'Custom channel was modified before this draft was saved.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function mapRuntimeError(error: unknown, operation: CustomChannelOperation): CustomChannelRuntimeError {
  const corrupt =
    error instanceof SyntaxError ||
    (
      error instanceof Error &&
      (
        error.name === 'CorruptChannelPersistenceDataError' ||
        error.name === 'CorruptChannelPersistenceFileError' ||
        error.name === 'UnsupportedChannelPersistenceSchemaError'
      )
    );
  return {
    code: corrupt ? 'CUSTOM_CHANNEL_STORAGE_CORRUPT' : 'CUSTOM_CHANNEL_STORAGE_UNAVAILABLE',
    message: corrupt
      ? 'Custom channel data could not be recovered.'
      : 'Custom channel storage is unavailable.',
    retryable: true,
    recoverable: true,
    operation,
  };
}
