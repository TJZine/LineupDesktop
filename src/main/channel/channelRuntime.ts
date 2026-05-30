import {
  ChannelAuthoringService,
  type ChannelClock,
  type ChannelLogger,
} from '../../domain/channel/index.js';
import { ChannelPersistenceStore, type ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import { ChannelRepository } from '../../domain/channel/channelRepository.js';
import type { ChannelConfig, ChannelCreateInput, ResolvedContentItem } from '../../domain/channel/types.js';
import {
  channelSetupFailure,
  channelSetupSuccess,
  type ChannelSetupCommitMode,
  type ChannelSetupIpcResult,
  type ChannelSetupRuntimeError,
  type ChannelSetupSummary,
} from '../../contracts/channel.js';
import type { PlexLibrarySectionSummary, PlexMediaItemSummary, PlexRuntimeSnapshot } from '../../contracts/plex.js';
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
        const items = await this.getInitialContentForSection(requestId, section);
        if (!items.ok) {
          return channelSetupFailure(requestId, channelContentValidationError('commit'));
        }
        sectionContent.push({ section, items: items.value });
      }

      for (const { section, items } of sectionContent) {
        const next = this.authoring.createChannel(
          createChannelInputForSection(section),
          committedChannels,
        );
        next.itemCount = items.length;
        next.totalDurationMs = items.reduce((sum, item) => sum + item.durationMs, 0);
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
  ): Promise<{ ok: true; value: ResolvedContentItem[] } | { ok: false }> {
    const result = await this.plexRuntime?.listLibraryItems(
      `channel-setup-items-${requestId}-${section.id}`,
      { sectionId: section.id, offset: 0, limit: 100 },
    );
    if (!result?.ok || result.value.items.length === 0) {
      return { ok: false };
    }
    return { ok: true, value: result.value.items.map(mapPlexMediaItemToResolvedContentItem) };
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

function mapPlexMediaItemToResolvedContentItem(
  item: PlexMediaItemSummary,
  index: number,
): ResolvedContentItem {
  return {
    ratingKey: item.ratingKey,
    type: item.type === 'show' || item.type === 'episode' ? item.type : 'movie',
    title: item.title,
    fullTitle: item.grandparentTitle ? `${item.grandparentTitle} - ${item.title}` : item.title,
    ...(item.grandparentTitle !== undefined ? { showTitle: item.grandparentTitle } : {}),
    durationMs: item.durationMs,
    thumb: null,
    year: item.year,
    ...(item.seasonNumber !== undefined ? { seasonNumber: item.seasonNumber } : {}),
    ...(item.episodeNumber !== undefined ? { episodeNumber: item.episodeNumber } : {}),
    scheduledIndex: index,
    ...(item.rating !== undefined ? { rating: item.rating } : {}),
    ...(item.contentRating !== undefined ? { contentRating: item.contentRating } : {}),
    ...(item.genres !== undefined ? { genres: [...item.genres] } : {}),
    ...(item.directors !== undefined ? { directors: [...item.directors] } : {}),
    ...(item.summary.length > 0 ? { summary: item.summary } : {}),
    ...(item.viewCount !== undefined ? { watched: item.viewCount > 0 } : {}),
    addedAt: item.addedAtMs,
  };
}
