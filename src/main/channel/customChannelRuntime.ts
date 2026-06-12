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
import { ChannelPersistenceStore, type ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import {
  findNextAvailableNumber,
  orderChannels,
  summarizeCustomChannelSnapshot,
} from './customChannelMutationMapper.js';
import { recordCustomChannelDiagnostic } from './customChannelDiagnostics.js';
import type { CustomChannelRefreshReason, CustomChannelSchedulerRefreshHook } from './customChannelSchedulerRefresh.js';

export interface CustomChannelRuntimeOptions {
  storage: ChannelPersistenceStoragePort;
  clock?: ChannelClock;
  logger?: Pick<ChannelLogger, 'warn'>;
  generateId?: () => string;
  onChannelsChanged?: CustomChannelSchedulerRefreshHook;
}

export class CustomChannelRuntime {
  private readonly repository: ChannelRepository;
  private readonly clock: ChannelClock;
  private readonly authoring: ChannelAuthoringService;
  private readonly logger?: Pick<ChannelLogger, 'warn'>;
  private readonly onChannelsChanged?: CustomChannelSchedulerRefreshHook;
  private mutationQueue: Promise<void> = Promise.resolve();

  public constructor(options: CustomChannelRuntimeOptions) {
    this.clock = options.clock ?? { now: () => Date.now() };
    this.logger = options.logger;
    this.onChannelsChanged = options.onChannelsChanged;
    this.repository = new ChannelRepository({
      store: new ChannelPersistenceStore(options.storage),
      clock: this.clock,
      logger: options.logger,
    });
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
      const loaded = await this.repository.loadNormalized();
      const state = stateFromLoaded(loaded?.data);
      const validation = this.validateDraftAgainstChannels(draft, state.channels);
      if (!validation.valid) {
        return customChannelFailure(requestId, validationError('saveDraft'));
      }
      const build = buildCustomChannelCreateInput(draft, state.channels);
      if (!build.ok) {
        return customChannelFailure(requestId, validationError('saveDraft'));
      }
      const existingIndex = draft.id === undefined
        ? -1
        : state.channels.findIndex((channel) => channel.id === draft.id);
      if (draft.id !== undefined && existingIndex < 0) {
        return customChannelFailure(requestId, notFoundError('saveDraft'));
      }
      if (existingIndex >= 0 && !hasExpectedRevision(draft, state.channels[existingIndex])) {
        return customChannelFailure(requestId, conflictError('saveDraft'));
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
      const snapshot = await this.saveState({
        channels: state.channels,
        channelOrder: ensureOrderForChannels(state.channelOrder, state.channels),
        currentChannelId,
        savedAt,
      });
      await this.refresh('saveDraft', 'save', changedChannel.id);
      return customChannelSuccess(requestId, mutationResult(snapshot, changedChannel.id));
    });
  }

  public async deleteChannel(
    requestId: string,
    payload: { channelId: string; confirm: boolean },
  ): Promise<CustomChannelIpcResult<CustomChannelMutationResult>> {
    return this.enqueueMutation(requestId, 'deleteChannel', async () => {
      if (payload.confirm !== true) return customChannelFailure(requestId, validationError('deleteChannel'));
      const state = stateFromLoaded((await this.repository.loadNormalized())?.data);
      const deletedIndex = state.channels.findIndex((channel) => channel.id === payload.channelId);
      if (deletedIndex < 0) {
        return customChannelFailure(requestId, notFoundError('deleteChannel'));
      }
      const nextChannels = state.channels.filter((channel) => channel.id !== payload.channelId);
      const savedAt = this.clock.now();
      const snapshot = await this.saveState({
        channels: nextChannels,
        channelOrder: state.channelOrder.filter((id) => id !== payload.channelId),
        currentChannelId: state.currentChannelId === payload.channelId
          ? chooseAdjacentVisibleChannelId(state.channels, deletedIndex, payload.channelId)
          : keepVisibleCurrentOrFirst(state.currentChannelId, nextChannels),
        savedAt,
      });
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
      const state = stateFromLoaded((await this.repository.loadNormalized())?.data);
      if (!isCompleteChannelOrder(channelIds, state.channels)) {
        return customChannelFailure(requestId, validationError('reorderChannels'));
      }
      const savedAt = this.clock.now();
      const snapshot = await this.saveState({
        channels: state.channels,
        channelOrder: [...channelIds],
        currentChannelId: keepVisibleCurrentOrFirst(state.currentChannelId, state.channels),
        savedAt,
      });
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
      const state = stateFromLoaded((await this.repository.loadNormalized())?.data);
      const channel = state.channels.find((candidate) => candidate.id === payload.channelId);
      if (channel === undefined) return customChannelFailure(requestId, notFoundError('setChannelVisibility'));
      channel.hidden = payload.hidden;
      channel.updatedAt = this.clock.now();
      const channelIndex = state.channels.findIndex((candidate) => candidate.id === payload.channelId);
      const snapshot = await this.saveState({
        channels: state.channels,
        channelOrder: state.channelOrder,
        currentChannelId: state.currentChannelId === payload.channelId && payload.hidden
          ? chooseAdjacentVisibleChannelId(state.channels, channelIndex, payload.channelId)
          : keepVisibleCurrentOrFirst(state.currentChannelId, state.channels),
        savedAt: this.clock.now(),
      });
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
    const queued = this.mutationQueue.catch(() => undefined).then(run);
    this.mutationQueue = queued.then(() => undefined, () => undefined);
    const result = await queued.catch((error: unknown) => this.failure<TValue>(requestId, operation, error));
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

  private async saveState(data: StoredChannelData): Promise<CustomChannelSnapshot> {
    await this.repository.saveStoredChannelData(data);
    await this.repository.saveCurrentChannelId(data.currentChannelId);
    return summarizeCustomChannelSnapshot({
      data,
      repaired: false,
      updatedAtMs: data.savedAt,
      storage: 'ready',
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
