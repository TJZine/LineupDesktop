import { randomUUID } from 'node:crypto';

import type {
  ChannelSetupBuildCounts,
  ChannelSetupBuildProgress,
  ChannelSetupBuildResult,
  ChannelSetupCancelResult,
  ChannelSetupConfigDraft,
  ChannelSetupPreview,
  ChannelSetupRecordSummary,
  ChannelSetupReview,
  ChannelSetupWorkflowError,
  ChannelSetupWorkflowIpcResult,
} from '../../../contracts/channel.js';
import {
  allocateChannelSetupNumbers,
  buildChannelSetupPlan,
  diffChannelSetupPlan,
  mergeChannelSetupMatch,
  normalizeChannelSetupConfig,
  type ChannelSetupPlan,
  type ChannelSetupPlannedChannel,
} from '../../../domain/channel/setupPlanning/index.js';
import { cloneContentFilters, cloneContentSource } from '../../../domain/channel/channelDomainClone.js';
import type { ChannelRepository } from '../../../domain/channel/channelRepository.js';
import type { ChannelConfig, StoredChannelData } from '../../../domain/channel/types.js';
import type { DesktopChannelSetupRecordStore } from '../../persistence/desktopChannelSetupRecordStore.js';
import type { GuideRuntime } from '../guideRuntime.js';
import type { DesktopPlexRuntime } from '../../plex/desktopPlexRuntime.js';
import { LivePlexTransportError } from '../../plex/livePlexTransport.js';
import { CorruptChannelPersistenceDataError } from '../../../domain/channel/channelPersistenceStore.js';
import { CorruptChannelPersistenceFileError } from '../../persistence/desktopChannelPersistenceStore.js';
import type { ChannelSetupFacetSource } from './desktopPlexSetupFacetSource.js';

const ACCEPTED_BUILD_ID_CAPACITY = 1024;

interface ActiveBuild {
  buildId: string;
  requestId: string;
  abortController: AbortController;
  phase: 'pre-apply' | 'applying';
  sequence: number;
}

export class DesktopChannelSetupRuntime {
  private readonly activeBySender = new Map<number, ActiveBuild>();
  private readonly acceptedBuildIdsBySender = new Map<number, Set<string>>();
  private readonly unsubscribeContextInvalidation: (() => void) | null;

  public constructor(private readonly options: {
    repository: ChannelRepository;
    facetSource: ChannelSetupFacetSource;
    recordStore: DesktopChannelSetupRecordStore;
    guideRuntime: GuideRuntime;
    plexRuntime: DesktopPlexRuntime;
    nowMs?: () => number;
    createChannelId?: () => string;
  }) {
    this.unsubscribeContextInvalidation = typeof options.plexRuntime.subscribeChannelSetupContextInvalidation === 'function'
      ? options.plexRuntime.subscribeChannelSetupContextInvalidation(() => {
          for (const active of this.activeBySender.values()) active.abortController.abort();
        })
      : null;
  }

  public async getRecord(requestId: string): Promise<ChannelSetupWorkflowIpcResult<ChannelSetupRecordSummary>> {
    try {
      const context = await this.options.plexRuntime.withActiveChannelSetupContext(async (value) => value);
      return success(requestId, await this.options.recordStore.getRecord(context.profileId, context.serverId));
    } catch (error) {
      return failure(requestId, mapError(error, 'getRecord'));
    }
  }

  public async preview(
    requestId: string,
    draft: ChannelSetupConfigDraft,
  ): Promise<ChannelSetupWorkflowIpcResult<ChannelSetupPreview>> {
    try {
      const plan = await this.createPlan(draft, new AbortController().signal);
      return success(requestId, toPreview(plan));
    } catch (error) {
      return failure(requestId, mapError(error, 'preview'));
    }
  }

  public async review(
    requestId: string,
    draft: ChannelSetupConfigDraft,
  ): Promise<ChannelSetupWorkflowIpcResult<ChannelSetupReview>> {
    try {
      const plan = await this.createPlan(draft, new AbortController().signal);
      const existing = (await this.options.repository.loadNormalized())?.data.channels ?? [];
      const diff = diffChannelSetupPlan(existing, plan.channels, plan.config.buildMode);
      return success(requestId, {
        preview: toPreview(plan),
        diff: {
          summary: diff.summary,
          samples: {
            created: diff.samples.created.map(sanitizeReviewName),
            removed: diff.samples.removed.map(sanitizeReviewName),
            unchanged: diff.samples.unchanged.map(sanitizeReviewName),
          },
        },
      });
    } catch (error) {
      return failure(requestId, mapError(error, 'review'));
    }
  }

  public async build(input: {
    senderId: number;
    requestId: string;
    buildId: string;
    draft: ChannelSetupConfigDraft;
    confirmReplace: boolean;
    onProgress(progress: ChannelSetupBuildProgress, sequence: number): void;
  }): Promise<ChannelSetupWorkflowIpcResult<ChannelSetupBuildResult>> {
    const admissionError = this.admitBuild(input.senderId, input.buildId, input.requestId);
    if (admissionError) return failure(input.requestId, admissionError);
    const active = this.activeBySender.get(input.senderId)!;
    let counts = emptyCounts();
    const warnings: string[] = [];
    const emit = (progress: ChannelSetupBuildProgress) => {
      active.sequence += 1;
      try {
        input.onProgress(progress, active.sequence);
      } catch {
        // Progress observers never own or reclassify the main-owned build.
      }
    };
    try {
      const config = normalizeChannelSetupConfig(input.draft);
      if (config.buildMode === 'replace' && input.confirmReplace !== true) {
        return failure(input.requestId, workflowError(
          'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
          'Replacing channels requires explicit confirmation.',
          'build',
        ));
      }
      const loadedFacets = await this.options.facetSource.load(
        config,
        active.abortController.signal,
        emit,
      );
      this.throwIfCanceled(active);
      const plan = buildChannelSetupPlan(config, loadedFacets.snapshot);
      if (loadedFacets.snapshot.libraries.length !== config.selectedLibraryIds.length) {
        throw workflowError(
          'CHANNEL_VALIDATION_FAILED',
          'One or more selected libraries are no longer available.',
          'build',
        );
      }
      if (plan.channels.length === 0) {
        throw workflowError(
          'CHANNEL_VALIDATION_FAILED',
          'No channels match the selected setup options.',
          'build',
        );
      }
      warnings.push(...plan.warnings.map(sanitizePublicText));
      counts = { ...counts, plannedGeneratedCount: plan.selectedGeneratedCount, reachedMaxChannels: plan.reachedMaxChannels };
      emit(progress('build_pending', 1, 1, 'Preparing channel changes'));
      const loaded = await this.options.repository.loadNormalized();
      this.throwIfCanceled(active);
      const final = materializeBuild(
        loaded?.data ?? null,
        plan,
        this.nowMs(),
        this.options.createChannelId ?? randomUUID,
      );
      counts = final.counts;
      emit(progress('create_channels', counts.createdCount + counts.updatedCount, counts.plannedGeneratedCount, 'Creating channels'));
      this.throwIfCanceled(active);
      active.phase = 'applying';
      emit(progress('apply_channels', 0, 1, 'Saving channels'));
      await this.options.repository.saveStoredChannelData(final.data);
      emit(progress('apply_channels', 1, 1, 'Channels saved'));
      let recordWarning = false;
      try {
        await this.options.recordStore.saveRecord({
          profileId: loadedFacets.profileId,
          serverId: loadedFacets.serverId,
          config,
          nowMs: this.nowMs(),
        });
      } catch {
        recordWarning = true;
        warnings.push('Channels were saved, but builder settings could not be recorded.');
      }
      emit(progress('refresh_guide', 0, 1, 'Refreshing Guide'));
      const guideRefresh = await this.options.guideRuntime.refreshAfterChannelSetupCommit(
        active.abortController.signal,
      );
      emit(progress('done', 1, 1, 'Channel setup complete'));
      return success(input.requestId, {
        kind: recordWarning ? 'committed-with-record-warning' : 'committed',
        buildId: input.buildId,
        counts,
        warnings,
        guideRefresh,
      });
    } catch (error) {
      if (active.abortController.signal.aborted && active.phase === 'pre-apply') {
        return success(input.requestId, { kind: 'canceled', buildId: input.buildId, counts, warnings });
      }
      return success(input.requestId, {
        kind: 'failed',
        buildId: input.buildId,
        counts: { ...counts, errorCount: counts.errorCount + 1 },
        warnings,
        error: active.phase === 'applying'
          ? { code: 'CHANNEL_STORAGE_UNAVAILABLE', message: fixedErrorMessage('CHANNEL_STORAGE_UNAVAILABLE'), retryable: true, recoverable: true, operation: 'build' }
          : mapError(error, 'build'),
      });
    } finally {
      if (this.activeBySender.get(input.senderId) === active) this.activeBySender.delete(input.senderId);
    }
  }

  public cancelBuild(senderId: number, buildId: string): ChannelSetupCancelResult {
    const active = this.activeBySender.get(senderId);
    if (!active || active.buildId !== buildId) return { buildId, status: 'not-active' };
    if (active.phase === 'applying') return { buildId, status: 'too-late' };
    active.abortController.abort();
    return { buildId, status: 'accepted' };
  }

  public releaseSender(senderId: number): void {
    const active = this.activeBySender.get(senderId);
    if (active?.phase === 'pre-apply') active.abortController.abort();
    this.acceptedBuildIdsBySender.delete(senderId);
  }

  public shutdown(): void {
    this.unsubscribeContextInvalidation?.();
    for (const active of this.activeBySender.values()) active.abortController.abort();
    this.activeBySender.clear();
    this.acceptedBuildIdsBySender.clear();
  }

  private async createPlan(draft: ChannelSetupConfigDraft, signal: AbortSignal): Promise<ChannelSetupPlan> {
    const config = normalizeChannelSetupConfig(draft);
    if (config.selectedLibraryIds.length === 0) {
      throw workflowError('CHANNEL_VALIDATION_FAILED', 'Select at least one library.', 'preview');
    }
    const loaded = await this.options.facetSource.load(config, signal);
    return buildChannelSetupPlan(config, loaded.snapshot);
  }

  private admitBuild(senderId: number, buildId: string, requestId: string): ChannelSetupWorkflowError | null {
    if (this.activeBySender.has(senderId)) {
      return workflowError('CHANNEL_BUILD_ACTIVE', 'A channel build is already active.', 'build');
    }
    const acceptedBuildIds = this.acceptedBuildIdsBySender.get(senderId) ?? new Set<string>();
    if (acceptedBuildIds.has(buildId)) {
      return workflowError('CHANNEL_BUILD_ID_REUSED', 'This build identifier was already used.', 'build');
    }
    if (acceptedBuildIds.size >= ACCEPTED_BUILD_ID_CAPACITY) {
      return workflowError('CHANNEL_BUILD_ID_CAPACITY', 'Build identifier capacity has been reached.', 'build');
    }
    acceptedBuildIds.add(buildId);
    this.acceptedBuildIdsBySender.set(senderId, acceptedBuildIds);
    this.activeBySender.set(senderId, {
      buildId,
      requestId,
      abortController: new AbortController(),
      phase: 'pre-apply',
      sequence: 0,
    });
    return null;
  }

  private throwIfCanceled(active: ActiveBuild): void {
    if (active.abortController.signal.aborted) throw workflowError(
      'CHANNEL_BUILD_CANCELED', 'Channel build was canceled.', 'build',
    );
  }

  private nowMs(): number { return (this.options.nowMs ?? Date.now)(); }
}

function materializeBuild(
  existingData: StoredChannelData | null,
  plan: ChannelSetupPlan,
  nowMs: number,
  createId: () => string,
): { data: StoredChannelData; counts: ChannelSetupBuildCounts } {
  const existing = existingData?.channels ?? [];
  const diff = diffChannelSetupPlan(existing, plan.channels, plan.config.buildMode);
  const allocation = allocateChannelSetupNumbers(existing, diff.created.length, plan.config.buildMode);
  const created = diff.created.slice(0, allocation.numbers.length).map((planned, index) => (
    createChannel(planned, allocation.numbers[index]!, nowMs, createId())
  ));
  let channels: ChannelConfig[];
  if (plan.config.buildMode === 'replace') channels = created;
  else if (plan.config.buildMode === 'append') channels = [...existing, ...created];
  else channels = [
    ...diff.preserved,
    ...diff.matched.map(({ existing: channel, planned }) => ({
      ...mergeChannelSetupMatch(channel, planned, nowMs),
      name: sanitizeChannelName(planned.name),
    })),
    ...created,
  ];
  channels.sort((left, right) => left.number - right.number || left.id.localeCompare(right.id));
  const survivingIds = new Set(channels.map((channel) => channel.id));
  const currentChannelId = existingData?.currentChannelId && survivingIds.has(existingData.currentChannelId)
    ? existingData.currentChannelId
    : channels[0]?.id ?? null;
  return {
    data: { channels, channelOrder: channels.map((channel) => channel.id), currentChannelId, savedAt: nowMs },
    counts: {
      plannedGeneratedCount: plan.selectedGeneratedCount,
      createdCount: created.length,
      updatedCount: plan.config.buildMode === 'merge' ? diff.matched.length : 0,
      preservedCount: plan.config.buildMode === 'replace'
        ? 0
        : plan.config.buildMode === 'merge'
          ? diff.preserved.length
          : existing.length,
      removedCount: diff.removed.length,
      skippedCount: plan.droppedByMinItemsCount + plan.droppedByPlanCapCount + (diff.created.length - created.length),
      reachedMaxChannels: plan.reachedMaxChannels,
      channelNumberCapacityExhausted: allocation.exhausted,
      errorCount: 0,
    },
  };
}

function createChannel(
  planned: ChannelSetupPlannedChannel,
  number: number,
  nowMs: number,
  id: string,
): ChannelConfig {
  return {
    id,
    number,
    name: sanitizeChannelName(planned.name),
    isAutoGenerated: true,
    buildStrategy: planned.buildStrategy,
    ...(planned.sourceLibraryId === undefined ? {} : { sourceLibraryId: planned.sourceLibraryId }),
    ...(planned.sourceLibraryName === undefined ? {} : { sourceLibraryName: planned.sourceLibraryName }),
    lineupReplicaIndex: planned.lineupReplicaIndex,
    isPlaybackModeVariant: planned.isPlaybackModeVariant,
    contentSource: cloneContentSource(planned.contentSource),
    playbackMode: planned.playbackMode,
    shuffleSeed: planned.shuffleSeed,
    ...(planned.blockSize === undefined ? {} : { blockSize: planned.blockSize }),
    ...(planned.contentFilters === undefined ? {} : { contentFilters: cloneContentFilters(planned.contentFilters) }),
    ...(planned.sortOrder === undefined ? {} : { sortOrder: planned.sortOrder }),
    startTimeAnchor: nowMs,
    skipIntros: false,
    skipCredits: false,
    createdAt: nowMs,
    updatedAt: nowMs,
    lastContentRefresh: nowMs,
    itemCount: planned.eligibleItemCount ?? 0,
    totalDurationMs: 0,
  };
}

function toPreview(plan: ChannelSetupPlan): ChannelSetupPreview {
  return {
    status: plan.channels.length === 0 ? 'blocked' : 'ready',
    config: plan.config,
    estimates: plan.estimates,
    eligibleGeneratedCount: plan.eligibleGeneratedCount,
    selectedGeneratedCount: plan.selectedGeneratedCount,
    droppedByMinItemsCount: plan.droppedByMinItemsCount,
    droppedByPlanCapCount: plan.droppedByPlanCapCount,
    reachedMaxChannels: plan.reachedMaxChannels,
    warnings: plan.warnings.map(sanitizePublicText),
    ...(plan.channels.length === 0 ? { message: 'No channels match these options.', failureReason: 'empty' as const } : {}),
  };
}

function progress(
  task: ChannelSetupBuildProgress['task'],
  current: number,
  total: number | null,
  label: string,
): ChannelSetupBuildProgress { return { task, current, total, label, detail: label }; }

function emptyCounts(): ChannelSetupBuildCounts {
  return {
    plannedGeneratedCount: 0, createdCount: 0, updatedCount: 0, preservedCount: 0,
    removedCount: 0, skippedCount: 0, reachedMaxChannels: false,
    channelNumberCapacityExhausted: false, errorCount: 0,
  };
}

function workflowError(
  code: ChannelSetupWorkflowError['code'],
  message: string,
  operation: ChannelSetupWorkflowError['operation'],
): ChannelSetupWorkflowError {
  return { code, message, retryable: false, recoverable: code !== 'CHANNEL_UNAUTHORIZED', operation };
}

function mapError(error: unknown, operation: ChannelSetupWorkflowError['operation']): ChannelSetupWorkflowError {
  if (isWorkflowError(error)) return workflowError(error.code, fixedErrorMessage(error.code), operation);
  if (error instanceof LivePlexTransportError) {
    return { code: 'CHANNEL_PLEX_REQUIRED', message: fixedErrorMessage('CHANNEL_PLEX_REQUIRED'), retryable: error.retryable, recoverable: true, operation };
  }
  if (error instanceof CorruptChannelPersistenceDataError || error instanceof CorruptChannelPersistenceFileError ||
    (error instanceof Error && error.name === 'CorruptChannelPersistenceFileError')) {
    return { code: 'CHANNEL_STORAGE_CORRUPT', message: fixedErrorMessage('CHANNEL_STORAGE_CORRUPT'), retryable: false, recoverable: true, operation };
  }
  if (error instanceof Error && error.name === 'UnsupportedChannelPersistenceSchemaError') {
    return { code: 'CHANNEL_STORAGE_UNSUPPORTED_VERSION', message: fixedErrorMessage('CHANNEL_STORAGE_UNSUPPORTED_VERSION'), retryable: false, recoverable: true, operation };
  }
  if (isNodeStorageError(error)) {
    return { code: 'CHANNEL_STORAGE_UNAVAILABLE', message: fixedErrorMessage('CHANNEL_STORAGE_UNAVAILABLE'), retryable: true, recoverable: true, operation };
  }
  return { code: 'CHANNEL_UNKNOWN', message: fixedErrorMessage('CHANNEL_UNKNOWN'), retryable: true, recoverable: true, operation };
}

function isWorkflowError(error: unknown): error is ChannelSetupWorkflowError {
  if (typeof error !== 'object' || error === null || Array.isArray(error)) return false;
  const keys = Object.keys(error);
  if (keys.length !== 5 || !['code', 'message', 'retryable', 'recoverable', 'operation'].every((key) => keys.includes(key))) return false;
  const code = (error as { code?: unknown }).code;
  return typeof code === 'string' && WORKFLOW_ERROR_CODES.has(code as ChannelSetupWorkflowError['code']);
}
function success<T>(requestId: string, value: T): ChannelSetupWorkflowIpcResult<T> {
  return { ok: true, requestId, value };
}
function failure<T>(requestId: string, error: ChannelSetupWorkflowError): ChannelSetupWorkflowIpcResult<T> {
  return { ok: false, requestId, error };
}

const WORKFLOW_ERROR_CODES = new Set<ChannelSetupWorkflowError['code']>([
  'CHANNEL_UNAUTHORIZED', 'CHANNEL_VALIDATION_FAILED', 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
  'CHANNEL_PLEX_REQUIRED', 'CHANNEL_STORAGE_UNAVAILABLE', 'CHANNEL_STORAGE_CORRUPT',
  'CHANNEL_STORAGE_UNSUPPORTED_VERSION', 'CHANNEL_BUILD_ACTIVE', 'CHANNEL_BUILD_ID_REUSED',
  'CHANNEL_BUILD_ID_CAPACITY', 'CHANNEL_BUILD_CANCELED', 'CHANNEL_BUILD_TOO_LATE', 'CHANNEL_UNKNOWN',
]);

function fixedErrorMessage(code: ChannelSetupWorkflowError['code']): string {
  switch (code) {
    case 'CHANNEL_UNAUTHORIZED': return 'Channel setup request is not authorized.';
    case 'CHANNEL_VALIDATION_FAILED': return 'Channel setup options are invalid or no longer available.';
    case 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED': return 'Replacing channels requires explicit confirmation.';
    case 'CHANNEL_PLEX_REQUIRED': return 'Plex authentication and a selected server are required.';
    case 'CHANNEL_STORAGE_UNAVAILABLE': return 'Channel storage is unavailable.';
    case 'CHANNEL_STORAGE_CORRUPT': return 'Channel storage is corrupt.';
    case 'CHANNEL_STORAGE_UNSUPPORTED_VERSION': return 'Channel storage was created by an unsupported version.';
    case 'CHANNEL_BUILD_ACTIVE': return 'A channel build is already active.';
    case 'CHANNEL_BUILD_ID_REUSED': return 'This build identifier was already used.';
    case 'CHANNEL_BUILD_ID_CAPACITY': return 'Build identifier capacity has been reached.';
    case 'CHANNEL_BUILD_CANCELED': return 'Channel build was canceled.';
    case 'CHANNEL_BUILD_TOO_LATE': return 'Channel build is already being applied.';
    case 'CHANNEL_UNKNOWN': return 'Channel setup could not be completed.';
  }
}
function sanitizeReviewName(value: string): string { return sanitizePublicText(value).slice(0, 80); }
function sanitizeChannelName(value: string): string { return sanitizePublicText(value).slice(0, 120) || 'Plex channel'; }
function sanitizePublicText(value: string): string {
  const normalized = stripControlCharacters(value).trim();
  return /https?:|file:|[A-Za-z]:[\\/]|(?:token|authorization|x-plex-token|header)\s*[:=]/iu.test(normalized)
    ? 'Plex item'
    : normalized.slice(0, 160);
}
function stripControlCharacters(value: string): string {
  return Array.from(value, (character) => {
    const code = character.codePointAt(0) ?? 0;
    return code < 32 || code === 127 ? ' ' : character;
  }).join('');
}
function isNodeStorageError(error: unknown): boolean {
  return error instanceof Error && 'code' in error && typeof error.code === 'string' &&
    ['EACCES', 'EPERM', 'EROFS', 'ENOSPC', 'EIO'].includes(error.code);
}
