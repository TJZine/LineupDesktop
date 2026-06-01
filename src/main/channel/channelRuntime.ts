import {
  ChannelAuthoringService,
  type ChannelClock,
  type ChannelLogger,
} from '../../domain/channel/index.js';
import { ChannelPersistenceStore, type ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import type { ChannelConfig, ChannelCreateInput } from '../../domain/channel/types.js';
import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupCommitMode,
  type ChannelSetupIpcResult,
  type ChannelSetupRuntimeError,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';
import type { PlexIpcResult, PlexLibrarySectionSummary, PlexListLibraryItemsValue, PlexMediaItemSummary, PlexRuntimeSnapshot } from '../../contracts/plex.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';

export interface ChannelRuntimeOptions {
  storage: ChannelPersistenceStoragePort;
  plexRuntime?: Pick<DesktopPlexRuntime, 'getSnapshot' | 'listLibraryItems'>;
  clock?: ChannelClock;
  logger?: ChannelLogger;
  generateId?: () => string;
}

export class ChannelRuntime {
  private readonly repository: ChannelRepository;
  private readonly clock: ChannelClock;
  private readonly authoring: ChannelAuthoringService;
  private readonly plexRuntime?: Pick<DesktopPlexRuntime, 'getSnapshot' | 'listLibraryItems'>;
  private commitQueue: Promise<void> = Promise.resolve();

  public constructor(options: ChannelRuntimeOptions) {
    this.clock = options.clock ?? { now: () => Date.now() };
    this.plexRuntime = options.plexRuntime;
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
          channels: [],
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
      return channelSetupFailure(requestId, mapChannelRuntimeError(error, 'getStatus'));
    }
  }

  public async commit(
    requestId: string,
    input: {
      mode: ChannelSetupCommitMode;
      sectionIds: readonly string[];
      confirmReplace?: boolean;
    },
  ): Promise<ChannelSetupIpcResult<ChannelSetupSummary>> {
    const operation = this.commitQueue
      .catch(() => undefined)
      .then(() => this.commitExclusive(requestId, input));
    this.commitQueue = operation.then(
      () => undefined,
      () => undefined,
    );
    return operation;
  }

  private async commitExclusive(
    requestId: string,
    input: {
      mode: ChannelSetupCommitMode;
      sectionIds: readonly string[];
      confirmReplace?: boolean;
    },
  ): Promise<ChannelSetupIpcResult<ChannelSetupSummary>> {
    try {
      if (this.plexRuntime === undefined) {
        return channelSetupFailure(requestId, plexRequiredError('commit'));
      }
      const snapshotResult = this.plexRuntime.getSnapshot(`channel-setup-plex-${requestId}`);
      if (!snapshotResult.ok) {
        return channelSetupFailure(requestId, plexRequiredError('commit'));
      }
      const snapshot = snapshotResult.value;
      const selectedSections = validateCommitSections(snapshot, input.sectionIds);
      if (!selectedSections.ok) {
        return channelSetupFailure(requestId, channelSectionValidationError('commit'));
      }
      if (
        snapshot.auth.profile === null ||
        snapshot.servers.selected === null ||
        selectedSections.value.length === 0
      ) {
        return channelSetupFailure(requestId, plexRequiredError('commit'));
      }

      const loaded = await this.repository.loadNormalized();
      const existingChannels = loaded?.data.channels ?? [];
      if (input.mode === 'replace' && existingChannels.length > 0 && input.confirmReplace !== true) {
        return channelSetupFailure(requestId, {
          code: 'CHANNEL_REPLACE_CONFIRMATION_REQUIRED',
          message: 'Replacing persisted channels requires confirmation.',
          retryable: false,
          recoverable: true,
          operation: 'commit',
        });
      }

      const baseChannels = input.mode === 'append' ? existingChannels : [];
      const committedChannels = [...baseChannels];
      const sectionContent = [];
      for (const section of selectedSections.value) {
        const content = await this.getInitialContentForSection(requestId, section);
        if (!content.ok) {
          return channelSetupFailure(requestId, channelContentValidationError('commit'));
        }
        sectionContent.push({ section, content: content.value });
      }

      for (const { section, content } of sectionContent) {
        const next = this.authoring.createChannel(
          createChannelInputForSection(section),
          committedChannels,
        );
        next.itemCount = content.itemCount;
        next.totalDurationMs = content.totalDurationMs;
        next.lastContentRefresh = this.clock.now();
        committedChannels.push(next);
      }

      const savedAt = this.clock.now();
      const currentChannelId = chooseCommittedCurrentChannelId({
        mode: input.mode,
        loadedCurrentChannelId: loaded?.data.currentChannelId ?? null,
        committedChannels,
      });
      await this.repository.saveStoredChannelData({
        channels: committedChannels,
        channelOrder: committedChannels.map((channel) => channel.id),
        currentChannelId,
        savedAt,
      });
      await this.repository.saveCurrentChannelId(currentChannelId);

      return channelSetupSuccess(requestId, summarizeLoadedChannels({
        channels: committedChannels,
        currentChannelId,
        repaired: false,
        updatedAtMs: savedAt,
      }));
    } catch (error) {
      return channelSetupFailure(requestId, mapChannelRuntimeError(error, 'commit'));
    }
  }

  private async getInitialContentForSection(
    requestId: string,
    section: PlexLibrarySectionSummary,
  ): Promise<{ ok: true; value: { itemCount: number; totalDurationMs: number } } | { ok: false }> {
    const limit = 100;
    let itemCount = 0;
    let totalDurationMs = 0;
    let offset = 0;
    let firstResult: PlexIpcResult<PlexListLibraryItemsValue> | undefined;

    while (true) {
      const result = await this.plexRuntime?.listLibraryItems(
        `channel-setup-items-${requestId}-${section.id}-${offset}`,
        { sectionId: section.id, offset, limit },
      );
      firstResult ??= result;
      if (result?.ok !== true) {
        if (itemCount === 0 && shouldUseSectionContentCountFallback(section, result)) {
          return sectionContentCountFallback(section);
        }
        return { ok: false };
      }
      if (result.value.items.length === 0) {
        break;
      }
      itemCount += result.value.items.length;
      totalDurationMs += result.value.items.reduce(
        (sum, item) => sum + sanitizeDurationMs(item.durationMs),
        0,
      );
      if (result.value.items.length < limit) {
        break;
      }
      offset += result.value.items.length;
    }

    if (itemCount > 0) {
      return {
        ok: true,
        value: {
          itemCount,
          totalDurationMs,
        },
      };
    }
    if (
      shouldUseSectionContentCountFallback(section, firstResult)
    ) {
      return sectionContentCountFallback(section);
    }
    return { ok: false };
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
    channels: input.channels.map((channel) => ({
      id: channel.id,
      number: channel.number,
      name: channel.name,
      sourceLibraryId: channel.sourceLibraryId ?? null,
      sourceLibraryName: channel.sourceLibraryName ?? null,
      itemCount: channel.itemCount,
    })),
    updatedAtMs: input.updatedAtMs,
    recovery: {
      loaded: input.channels.length > 0,
      repaired: input.repaired,
    },
  };
}

function mapChannelRuntimeError(
  error: unknown,
  operation: ChannelSetupRuntimeError['operation'],
): ChannelSetupRuntimeError {
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
    operation,
  };
}

function plexRequiredError(operation: ChannelSetupRuntimeError['operation']): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_PLEX_REQUIRED',
    message: 'Plex profile, server, and library selection are required.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function channelContentValidationError(
  operation: ChannelSetupRuntimeError['operation'],
): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Selected Plex libraries did not return usable channel content.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function channelSectionValidationError(
  operation: ChannelSetupRuntimeError['operation'],
): ChannelSetupRuntimeError {
  return {
    code: 'CHANNEL_VALIDATION_FAILED',
    message: 'Selected Plex library ids are invalid.',
    retryable: false,
    recoverable: true,
    operation,
  };
}

function chooseCommittedCurrentChannelId(input: {
  mode: ChannelSetupCommitMode;
  loadedCurrentChannelId: string | null;
  committedChannels: readonly ChannelConfig[];
}): string | null {
  if (
    input.mode === 'append' &&
    input.loadedCurrentChannelId !== null &&
    input.committedChannels.some((channel) => channel.id === input.loadedCurrentChannelId)
  ) {
    return input.loadedCurrentChannelId;
  }
  return input.committedChannels[0]?.id ?? null;
}

function validateCommitSections(
  snapshot: PlexRuntimeSnapshot,
  sectionIds: readonly string[],
): { ok: true; value: PlexLibrarySectionSummary[] } | { ok: false } {
  if (
    sectionIds.length === 0 ||
    sectionIds.some((id) => !isSafeCommitSectionId(id))
  ) {
    return { ok: false };
  }
  const selectedSections = [];
  for (const sectionId of sectionIds) {
    const section = snapshot.library.sections.find((candidate) => (
      (candidate.type === 'movie' || candidate.type === 'show') &&
      candidate.id === sectionId
    ));
    if (section === undefined) {
      return { ok: false };
    }
    selectedSections.push(section);
  }
  return { ok: true, value: selectedSections };
}

function isSafeCommitSectionId(value: unknown): value is string {
  return typeof value === 'string' &&
    value.trim() === value &&
    value.length > 0 &&
    value.length <= 120 &&
    /^[A-Za-z0-9._-]+$/u.test(value);
}

function hasPositiveSectionContentCount(
  section: PlexLibrarySectionSummary,
): section is PlexLibrarySectionSummary & { contentCount: number } {
  return typeof section.contentCount === 'number' &&
    Number.isFinite(section.contentCount) &&
    section.contentCount > 0;
}

function shouldUseSectionContentCountFallback(
  section: PlexLibrarySectionSummary,
  result: PlexIpcResult<PlexListLibraryItemsValue> | undefined,
): section is PlexLibrarySectionSummary & { contentCount: number } {
  return hasPositiveSectionContentCount(section) &&
    (result?.ok === true || isRetryablePlexItemProbeFailure(result));
}

function sectionContentCountFallback(
  section: PlexLibrarySectionSummary & { contentCount: number },
): { ok: true; value: { itemCount: number; totalDurationMs: number } } {
  return {
    ok: true,
    value: {
      itemCount: section.contentCount,
      totalDurationMs: 0,
    },
  };
}

const RETRYABLE_ITEM_PROBE_ERROR_CODES = new Set([
  'PLEX_RATE_LIMITED',
  'PLEX_SERVER_UNREACHABLE',
  'PLEX_LIBRARY_FAILED',
]);

function isRetryablePlexItemProbeFailure(
  result: PlexIpcResult<PlexListLibraryItemsValue> | undefined,
): boolean {
  return result?.ok === false &&
    result.error.operation === 'listLibraryItems' &&
    result.error.retryable === true &&
    RETRYABLE_ITEM_PROBE_ERROR_CODES.has(result.error.code);
}

function createChannelInputForSection(section: PlexLibrarySectionSummary): ChannelCreateInput {
  const libraryType = section.type === 'show' ? 'show' : 'movie';
  return {
    name: section.title,
    sourceLibraryId: section.id,
    sourceLibraryName: section.title,
    buildStrategy: 'libraryFallback',
    isAutoGenerated: true,
    contentSource: {
      type: 'library',
      libraryId: section.id,
      libraryType,
      includeWatched: true,
    },
    playbackMode: libraryType === 'show' ? 'shuffle' : 'sequential',
    skipIntros: false,
    skipCredits: false,
  };
}

function sanitizeDurationMs(value: PlexMediaItemSummary['durationMs']): number {
  return Number.isFinite(value) && value > 0 ? value : 0;
}
