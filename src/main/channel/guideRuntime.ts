import type {
  EpgChannelViewModel,
  EpgCurrentProgramViewModel,
  EpgPresentationSource,
  EpgProgramViewModel,
  GuideLibraryFilterOption,
  GuideLibraryFilterState,
  GuidePresentationSource,
} from '../../contracts/guide.js';
import { randomBytes } from 'node:crypto';
import type { ChannelClock, ChannelLogger } from '../../domain/channel/interfaces.js';
import { ContentResolver } from '../../domain/channel/contentResolver.js';
import type { ChannelRepository } from '../../domain/channel/channelRepository.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import type {
  ResolvedContentItem as SchedulerContentItem,
  ScheduledProgram,
  SchedulerPlaybackMode,
} from '../../domain/scheduler/types.js';
import type { ResolvedContentItem as ChannelContentItem } from '../../domain/channel/types.js';
import type { ChannelConfig } from '../../domain/channel/types.js';
import type { PlexLibraryMinimalAdapter } from './plexLibraryMinimalAdapter.js';
import type { GuideArtworkOwner } from './guideArtworkOwner.js';
import type { ChannelPublicReferenceGeneration, ChannelPublicReferenceOwner } from './channelPublicReferenceOwner.js';
import type { DesktopGuidePreferencesStore } from './desktopGuidePreferencesStore.js';
import { DesktopGuidePreferencesStoreError } from './desktopGuidePreferencesStore.js';
import { channelLibraryIds, libraryIdsFromContentSource } from './channelLibraryIds.js';

export type GuidePastItemsWindowSetting = 'auto' | '0' | '15' | '30';

export interface GuidePastItemsWindowSnapshot {
  revision: number;
  pastItemsWindow: GuidePastItemsWindowSetting;
  libraryTabsEnabled?: boolean;
}

export class GuidePresentationCurrentnessError extends Error {
  public constructor() {
    super('Guide presentation settings changed while loading.');
    this.name = 'GuidePresentationCurrentnessError';
  }
}

type GuideContextResult = Readonly<{ ok: true; snapshot: Readonly<{ activeProfileId: string; selectedServerId: string }> }> |
  Readonly<{ ok: false }> | null;

export class GuideRuntime {
  private readonly repository: ChannelRepository;
  private readonly contentResolver: ContentResolver;
  private readonly activeChannelScheduler: ChannelScheduler;
  private readonly clock: ChannelClock;
  private readonly onChannelTuned?: (channelId: string) => void | Promise<void>;
  private readonly logger: ChannelLogger;
  private readonly guideArtworkOwner: GuideArtworkOwner | null;
  private readonly loadLineupRevision: (() => Promise<number>) | null;
  private readonly preferencesStore: DesktopGuidePreferencesStore | null;
  private readonly guideContextSource: Readonly<{ getBuilderContextForMain(): GuideContextResult }> | null;
  private readonly getLibraryTabsEnabled: () => boolean | Promise<boolean>;
  private readonly getPastItemsWindowSnapshot: () => Promise<GuidePastItemsWindowSnapshot>;
  private readonly createScopeToken: () => string;
  private activeScopeKey: string | null = null;
  private activeScopeToken: string | null = null;

  constructor(input: {
    repository: ChannelRepository;
    plexLibraryAdapter: PlexLibraryMinimalAdapter;
    activeChannelScheduler: ChannelScheduler;
    clock?: ChannelClock;
    onChannelTuned?: (channelId: string) => void | Promise<void>;
    logger?: ChannelLogger;
    guideArtworkOwner?: GuideArtworkOwner;
    loadLineupRevision?: () => Promise<number>;
    preferencesStore?: DesktopGuidePreferencesStore;
    guideContextSource?: Readonly<{ getBuilderContextForMain(): GuideContextResult }>;
    getLibraryTabsEnabled?: () => boolean | Promise<boolean>;
    getPastItemsWindowSnapshot?: () => Promise<GuidePastItemsWindowSnapshot>;
    createScopeToken?: () => string;
  }) {
    this.repository = input.repository;
    this.clock = input.clock ?? { now: () => Date.now() };
    this.contentResolver = new ContentResolver(
      input.plexLibraryAdapter,
      this.clock,
      input.logger ?? { warn: () => undefined, error: () => undefined },
    );
    this.activeChannelScheduler = input.activeChannelScheduler;
    this.onChannelTuned = input.onChannelTuned;
    this.logger = input.logger ?? { warn: () => undefined, error: () => undefined };
    this.guideArtworkOwner = input.guideArtworkOwner ?? null;
    this.loadLineupRevision = input.loadLineupRevision ?? null;
    this.preferencesStore = input.preferencesStore ?? null;
    this.guideContextSource = input.guideContextSource ?? null;
    this.getLibraryTabsEnabled = input.getLibraryTabsEnabled ?? (() => true);
    this.getPastItemsWindowSnapshot = input.getPastItemsWindowSnapshot ?? (async () => ({
      revision: 0,
      pastItemsWindow: 'auto',
    }));
    this.createScopeToken = input.createScopeToken ?? (() => `guide-scope-${randomBytes(16).toString('hex')}`);
  }

  async getPagedPresentation(input: {
    startTimeMs: number;
    durationMs: number;
    channelOffset: number;
    channelLimit: number;
    generation: ChannelPublicReferenceGeneration;
    publicReferenceOwner: ChannelPublicReferenceOwner;
  }): Promise<GuidePresentationSource> {
    if (this.preferencesStore === null || this.guideContextSource === null) {
      throw new Error('Guide preferences are unavailable.');
    }
    const settingsSnapshot = await this.getPastItemsWindowSnapshot();
    const capturedNowMs = this.clock.now();
    let preference = await this.activatePreferenceScope(input.generation);
    const libraryRows = deriveLibraries(input.generation, input.publicReferenceOwner);
    const tabsEnabled = (settingsSnapshot.libraryTabsEnabled ?? await this.getLibraryTabsEnabled()) && libraryRows.length > 1;
    const validSelection = preference.selectedLibraryId === null ||
      libraryRows.some((library) => library.rawId === preference.selectedLibraryId);
    if ((!tabsEnabled || !validSelection) && preference.selectedLibraryId !== null) {
      preference = await this.preferencesStore.normalizeSelection(preference.scopeToken, preference.revision);
    }
    const selectedRawLibraryId = tabsEnabled ? preference.selectedLibraryId : null;
    const eligibleChannels = input.generation.channels
      .filter((channel) => channel.hidden !== true)
      .filter((channel) => selectedRawLibraryId === null || channelLibraryIds(channel).includes(selectedRawLibraryId));
    const minimumStartTimeMs = computeGuideMinimumStartTimeMs(
      capturedNowMs,
      settingsSnapshot.pastItemsWindow,
      eligibleChannels,
      selectedRawLibraryId,
    );
    const effectiveStartTimeMs = Math.max(input.startTimeMs, minimumStartTimeMs);
    const eligible = eligibleChannels
      .map((channel) => ({
        channel,
        publicId: input.publicReferenceOwner.projectChannelReference(input.generation, channel.id),
      }))
      .sort((left, right) => left.channel.number - right.channel.number || compareUtf16(left.publicId, right.publicId));
    const total = eligible.length;
    const maximumOffset = Math.max(0, total - input.channelLimit);
    const offset = Math.min(input.channelOffset, maximumOffset);
    const page = eligible.slice(offset, offset + input.channelLimit);
    const resolved = await Promise.all(page.map(async ({ channel }) => {
      let items: ChannelContentItem[] = [];
      try { items = await this.contentResolver.resolveSource(channel.contentSource); }
      catch (error) { this.logContentResolutionFailure('GuideRuntime.getPagedPresentation.channel', channel, error); }
      if (items.length === 0) return { channel, items, programs: [] as EpgProgramViewModel[] };
      const scheduler = createSchedulerForChannel(channel, items, this.clock);
      const programs = scheduler.getScheduleWindow(effectiveStartTimeMs, effectiveStartTimeMs + input.durationMs).programs
        .map((program) => mapScheduledProgramToViewModel(
          program, channel.id, items, this.guideArtworkOwner, input.generation.lineupRevision,
        ))
        .sort(compareProgram)
        .slice(0, 200);
      return { channel, items, programs };
    }));
    const raw: EpgPresentationSource = {
      channels: resolved.map(({ channel, programs }) => ({
        id: channel.id,
        number: String(channel.number),
        name: channel.name,
        programs,
      })),
      nowWatching: this.projectNowWatchingForPage(resolved),
    };
    const projected = input.publicReferenceOwner.projectPresentation(input.generation, raw);
    const channels = applyFairProgramCap(projected.channels, 1_000);
    const libraries: GuideLibraryFilterOption[] = libraryRows.map(({ rawId: _rawId, ...library }) => library);
    const libraryFilter: GuideLibraryFilterState = {
      scopeToken: preference.scopeToken,
      revision: preference.revision,
      libraries,
      selectedLibraryId: tabsEnabled && preference.selectedLibraryId !== null
        ? input.publicReferenceOwner.projectLibraryReference(input.generation, preference.selectedLibraryId)
        : null,
      persistenceStatus: preference.persistenceStatus,
    };
    const latestSettingsSnapshot = await this.getPastItemsWindowSnapshot();
    if (latestSettingsSnapshot.revision !== settingsSnapshot.revision ||
      latestSettingsSnapshot.pastItemsWindow !== settingsSnapshot.pastItemsWindow ||
      latestSettingsSnapshot.libraryTabsEnabled !== settingsSnapshot.libraryTabsEnabled) {
      throw new GuidePresentationCurrentnessError();
    }
    return {
      ...projected,
      channels,
      channelWindow: { offset, total },
      libraryFilter,
      minimumStartTimeMs,
    };
  }

  async setLibraryFilter(input: {
    generation: ChannelPublicReferenceGeneration;
    publicReferenceOwner: ChannelPublicReferenceOwner;
    expectedScopeToken: string;
    expectedRevision: number;
    libraryId: string | null;
    loadCurrentGeneration: () => Promise<ChannelPublicReferenceGeneration>;
    isCommitCurrent?: () => boolean | Promise<boolean>;
  }): Promise<GuideLibraryFilterState> {
    if (this.preferencesStore === null) throw new Error('Guide preferences are unavailable.');
    await this.activatePreferenceScope(input.generation);
    const libraries = deriveLibraries(input.generation, input.publicReferenceOwner);
    const rawLibraryId = input.libraryId === null ? null : input.publicReferenceOwner.resolveLibrary(input.generation, input.libraryId);
    if (input.libraryId !== null && (rawLibraryId === null || !libraries.some((library) => library.rawId === rawLibraryId))) {
      throw new Error('Guide library is unavailable.');
    }
    const snapshot = await this.preferencesStore.setLibraryFilter(
      input.expectedScopeToken,
      input.expectedRevision,
      rawLibraryId,
      async () => {
        if (!(await (input.isCommitCurrent?.() ?? true))) return false;
        let currentGeneration: ChannelPublicReferenceGeneration;
        try {
          currentGeneration = await input.loadCurrentGeneration();
        } catch {
          throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
        }
        if (currentGeneration.fingerprint !== input.generation.fingerprint ||
          this.activeScopeToken !== input.expectedScopeToken) {
          throw new DesktopGuidePreferencesStoreError('GUIDE_FILTER_SCOPE_STALE');
        }
        return await (input.isCommitCurrent?.() ?? true);
      },
    );
    return {
      scopeToken: snapshot.scopeToken,
      revision: snapshot.revision,
      libraries: libraries.map(({ rawId: _rawId, ...library }) => library),
      selectedLibraryId: rawLibraryId === null ? null : input.publicReferenceOwner.projectLibraryReference(input.generation, rawLibraryId),
      persistenceStatus: snapshot.persistenceStatus,
    };
  }

  invalidatePreferenceScope(): void {
    this.activeScopeKey = null;
    this.activeScopeToken = null;
    this.preferencesStore?.clearActiveScope();
  }

  isPreferenceScopeCurrent(scopeToken: string): boolean {
    return this.activeScopeToken === scopeToken;
  }

  private async activatePreferenceScope(generation: ChannelPublicReferenceGeneration) {
    if (this.preferencesStore === null || this.guideContextSource === null) throw new Error('Guide preferences are unavailable.');
    const context = this.guideContextSource.getBuilderContextForMain();
    if (context === null || !context.ok) throw new Error('Guide scope is unavailable.');
    const scopeKey = JSON.stringify([context.snapshot.selectedServerId, context.snapshot.activeProfileId, generation.fingerprint]);
    if (scopeKey !== this.activeScopeKey || this.activeScopeToken === null) {
      this.activeScopeKey = scopeKey;
      this.activeScopeToken = this.createScopeToken();
    }
    return this.preferencesStore.activateScope({
      serverId: context.snapshot.selectedServerId,
      profileId: context.snapshot.activeProfileId,
      scopeToken: this.activeScopeToken,
    });
  }

  private projectNowWatchingForPage(
    resolved: readonly { channel: ChannelConfig; items: readonly ChannelContentItem[]; programs: readonly EpgProgramViewModel[] }[],
  ): EpgCurrentProgramViewModel | null {
    const state = this.activeChannelScheduler.getState();
    if (!state.isActive || state.currentProgram === null) return null;
    const row = resolved.find(({ channel }) => channel.id === state.channelId);
    return row === undefined ? null : mapCurrentProgram(state.currentProgram, row.channel.id, [...row.items]);
  }

  async getPresentation(
    startTimeMs: number,
    durationMs: number,
  ): Promise<EpgPresentationSource> {
    const lineupRevision = this.guideArtworkOwner === null || this.loadLineupRevision === null
      ? null
      : await this.loadLineupRevision();
    const loaded = await this.repository.loadNormalized();
    const visibleChannels = loaded?.data.channels.filter(isVisibleChannel) ?? [];
    if (!loaded || visibleChannels.length === 0) {
      return {
        channels: [],
        nowWatching: null,
      };
    }

    const epgChannels: EpgChannelViewModel[] = await Promise.all(
      visibleChannels.map(async (channel) => {
        let channelItems: ChannelContentItem[] = [];
        try {
          channelItems = await this.contentResolver.resolveSource(channel.contentSource);
        } catch (error) {
          this.logContentResolutionFailure('GuideRuntime.getPresentation.channel', channel, error);
        }

        if (channelItems.length === 0) {
          return {
            id: channel.id,
            number: String(channel.number),
            name: channel.name,
            programs: [],
          };
        }

        const scheduler = createSchedulerForChannel(channel, channelItems, this.clock);
        const window = scheduler.getScheduleWindow(startTimeMs, startTimeMs + durationMs);
        const programs = window.programs.map((prog) =>
          mapScheduledProgramToViewModel(
            prog,
            channel.id,
            channelItems,
            this.guideArtworkOwner,
            lineupRevision,
          ),
        );

        return {
          id: channel.id,
          number: String(channel.number),
          name: channel.name,
          programs,
        };
      }),
    );

    let nowWatching: EpgCurrentProgramViewModel | null = null;
    const currentChannel = visibleChannels.find(
      (c) => c.id === loaded.data.currentChannelId,
    );

    if (currentChannel) {
      const state = this.activeChannelScheduler.getState();
      if (state.isActive && state.currentProgram && state.channelId === currentChannel.id) {
        let currentItems: ChannelContentItem[] = [];
        try {
          currentItems = await this.contentResolver.resolveSource(currentChannel.contentSource);
        } catch (error) {
          this.logContentResolutionFailure('GuideRuntime.getPresentation.nowWatching.active', currentChannel, error);
        }
        nowWatching = mapCurrentProgram(state.currentProgram, currentChannel.id, currentItems);
      } else {
        // Fallback calculation if active scheduler is not loaded yet
        let currentItems: ChannelContentItem[] = [];
        try {
          currentItems = await this.contentResolver.resolveSource(currentChannel.contentSource);
        } catch (error) {
          this.logContentResolutionFailure('GuideRuntime.getPresentation.nowWatching.fallback', currentChannel, error);
        }
        if (currentItems.length > 0) {
          const scheduler = createSchedulerForChannel(currentChannel, currentItems, this.clock);
          const currentProgram = scheduler.getCurrentProgram();
          if (currentProgram && currentProgram.isCurrent) {
            nowWatching = mapCurrentProgram(currentProgram, currentChannel.id, currentItems);
          }
        }
      }
    }

    return {
      channels: epgChannels,
      nowWatching,
    };
  }

  async tuneChannel(channelId: string): Promise<void> {
    const loaded = await this.repository.loadNormalized();
    if (!loaded) {
      throw new Error('No channels configured');
    }
    const channel = loaded.data.channels.find((c) => c.id === channelId && isVisibleChannel(c));
    if (!channel) {
      throw new Error(`Channel not found: ${channelId}`);
    }

    const channelItems = await this.contentResolver.resolveSource(channel.contentSource);
    if (channelItems.length === 0) {
      throw new Error(`No items resolved for channel: ${channelId}`);
    }

    const schedulerItems = channelItems.map(toSchedulerContentItem);
    const schedulerPlaybackMode: SchedulerPlaybackMode =
      channel.playbackMode === 'random' ? 'shuffle' : channel.playbackMode;

    await this.repository.saveCurrentChannelId(channelId);

    this.activeChannelScheduler.loadChannel({
      channelId: channel.id,
      anchorTime: channel.startTimeAnchor,
      content: schedulerItems,
      playbackMode: schedulerPlaybackMode,
      shuffleSeed: channel.shuffleSeed ?? 0,
      blockSize: channel.blockSize,
    });

    await this.notifyChannelTuned(channelId);
  }

  async initializeActiveChannel(): Promise<void> {
    const loaded = await this.repository.loadNormalized();
    const visibleChannels = loaded?.data.channels.filter(isVisibleChannel) ?? [];
    if (!loaded || visibleChannels.length === 0) {
      return;
    }
    const currentChannelId = visibleChannels.some((channel) => channel.id === loaded.data.currentChannelId)
      ? loaded.data.currentChannelId
      : visibleChannels[0]?.id;
    if (currentChannelId) {
      try {
        await this.tuneChannel(currentChannelId);
      } catch (error) {
        this.logger.error('GuideRuntime initializeActiveChannel failed to tune channel.', {
          currentChannelId,
          error: summarizeError(error),
        });
      }
    }
  }

  async refreshActiveChannelSelection(): Promise<void> {
    const loaded = await this.repository.loadNormalized();
    if (!loaded || loaded.data.channels.length === 0) {
      this.activeChannelScheduler.unloadChannel();
      return;
    }
    const currentChannel = loaded.data.channels.find((channel) =>
      channel.id === loaded.data.currentChannelId && channel.hidden !== true
    );
    if (!currentChannel) {
      const fallbackChannel = loaded.data.channels.find((channel) => channel.hidden !== true);
      if (fallbackChannel) {
        await this.tuneChannel(fallbackChannel.id);
        return;
      }
      this.activeChannelScheduler.unloadChannel();
      return;
    }
    await this.tuneChannel(currentChannel.id);
  }

  private logContentResolutionFailure(operation: string, channel: ChannelConfig, error: unknown): void {
    this.logger.error('GuideRuntime failed to resolve channel content.', {
      operation,
      channelId: channel.id,
      contentSource: channel.contentSource,
      error: summarizeError(error),
    });
  }

  private async notifyChannelTuned(channelId: string): Promise<void> {
    if (!this.onChannelTuned) {
      return;
    }
    try {
      await this.onChannelTuned(channelId);
    } catch (error) {
      this.logger.error('GuideRuntime onChannelTuned callback failed.', {
        channelId,
        error: summarizeError(error),
      });
    }
  }
}

function isVisibleChannel(channel: ChannelConfig): boolean {
  return channel.hidden !== true;
}

export function computeGuideMinimumStartTimeMs(
  nowMs: number,
  setting: GuidePastItemsWindowSetting,
  visibleChannels: readonly ChannelConfig[],
  selectedRawLibraryId: string | null,
): number {
  if (!Number.isFinite(nowMs) || nowMs < 0) {
    throw new Error('Guide clock value is invalid.');
  }
  const captured = new Date(nowMs);
  if (!Number.isFinite(captured.getTime())) {
    throw new Error('Guide clock date is invalid.');
  }
  const pastMinutes = setting === 'auto'
    ? isGuideShowOnlyScope(visibleChannels, selectedRawLibraryId) ? 0 : 15
    : Number(setting);
  const elapsedMs = pastMinutes * 60_000;
  const slotStartMs = Math.floor((nowMs - elapsedMs) / 1_800_000) * 1_800_000;
  const localMidnight = new Date(nowMs);
  localMidnight.setHours(0, 0, 0, 0);
  const minimumStartTimeMs = Math.max(0, slotStartMs, localMidnight.getTime());
  if (!Number.isSafeInteger(minimumStartTimeMs) || minimumStartTimeMs < 0) {
    throw new Error('Guide minimum start time is invalid.');
  }
  return minimumStartTimeMs;
}

export function isGuideShowOnlyScope(
  channels: readonly ChannelConfig[],
  selectedRawLibraryId: string | null,
): boolean {
  if (channels.length === 0) return false;
  return channels.every((channel) => {
    const source = channel.contentSource;
    return source.type === 'library' &&
      source.libraryType === 'show' &&
      (selectedRawLibraryId === null || source.libraryId === selectedRawLibraryId) &&
      (channel.sourceLibraryId === undefined || channel.sourceLibraryId === source.libraryId);
  });
}

function deriveLibraries(
  generation: ChannelPublicReferenceGeneration,
  owner: ChannelPublicReferenceOwner,
): Array<GuideLibraryFilterOption & { rawId: string }> {
  const accumulated = new Map<string, { names: string[]; kinds: Set<'show' | 'movie' | 'mixed'> }>();
  for (const channel of generation.channels.filter(isVisibleChannel)) {
    for (const rawId of channelLibraryIds(channel)) {
      const value = accumulated.get(rawId) ?? { names: [], kinds: new Set() };
      if (channel.sourceLibraryId === rawId && channel.sourceLibraryName) value.names.push(channel.sourceLibraryName);
      value.kinds.add(contentKindForLibrary(channel.contentSource, rawId));
      accumulated.set(rawId, value);
    }
  }
  return [...accumulated].map(([rawId, value]) => {
    const distinctKinds = [...value.kinds];
    return {
      rawId,
      id: owner.projectLibraryReference(generation, rawId),
      name: owner.projectLibraryName(value.names[0] ?? 'Library'),
      contentKind: distinctKinds.length === 1 ? distinctKinds[0]! : 'mixed',
    };
  }).sort((left, right) => compareUtf16(left.name.toLowerCase(), right.name.toLowerCase()) || compareUtf16(left.id, right.id));
}

function contentKindForLibrary(source: ChannelConfig['contentSource'], rawId: string): 'show' | 'movie' | 'mixed' {
  if (source.type === 'library') return source.libraryId === rawId ? source.libraryType : 'mixed';
  if (source.type !== 'mixed') return 'mixed';
  const matching = source.sources.filter((child) => libraryIdsFromContentSource(child).includes(rawId));
  if (matching.length !== 1 || source.sources.length !== 1) return 'mixed';
  return contentKindForLibrary(matching[0]!, rawId);
}

function compareProgram(left: EpgProgramViewModel, right: EpgProgramViewModel): number {
  return left.startsAtMs - right.startsAtMs || left.endsAtMs - right.endsAtMs || compareUtf16(left.id, right.id);
}

function applyFairProgramCap(
  channels: readonly EpgChannelViewModel[],
  cap: number,
): readonly EpgChannelViewModel[] {
  const retained = channels.map(() => 0);
  let total = 0;
  for (let index = 0; total < cap; index += 1) {
    let admitted = false;
    channels.forEach((channel, channelIndex) => {
      if (total < cap && channel.programs[index] !== undefined) {
        retained[channelIndex] = index + 1;
        total += 1;
        admitted = true;
      }
    });
    if (!admitted) break;
  }
  return channels.map((channel, index) => ({ ...channel, programs: channel.programs.slice(0, retained[index]) }));
}

function compareUtf16(left: string, right: string): number {
  const length = Math.min(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const difference = left.charCodeAt(index) - right.charCodeAt(index);
    if (difference !== 0) return difference;
  }
  return left.length - right.length;
}

function createSchedulerForChannel(
  channel: ChannelConfig,
  items: readonly ChannelContentItem[],
  clock: ChannelClock,
): ChannelScheduler {
  const schedulerItems = items.map(toSchedulerContentItem);
  const schedulerPlaybackMode: SchedulerPlaybackMode =
    channel.playbackMode === 'random' ? 'shuffle' : channel.playbackMode;
  const scheduler = new ChannelScheduler({ clock });
  scheduler.loadChannel({
    channelId: channel.id,
    anchorTime: channel.startTimeAnchor,
    content: schedulerItems,
    playbackMode: schedulerPlaybackMode,
    shuffleSeed: channel.shuffleSeed ?? 0,
    blockSize: channel.blockSize,
  });
  return scheduler;
}

function summarizeError(error: unknown): { name?: string; message: string } | string {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
    };
  }
  try {
    return String(error);
  } catch {
    return 'unknown error';
  }
}

function toSchedulerContentItem(item: ChannelContentItem): SchedulerContentItem {
  return {
    ratingKey: item.ratingKey,
    type: (item.type === 'episode' ? 'episode' : 'movie') as 'movie' | 'episode',
    title: item.title,
    fullTitle: item.fullTitle,
    durationMs: item.durationMs,
    thumb: item.thumb,
    year: item.year,
    scheduledIndex: item.scheduledIndex,
    showTitle: item.showTitle,
    showThumb: item.showThumb ?? undefined,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
  };
}

function mapScheduledProgramToViewModel(
  prog: ScheduledProgram,
  channelId: string,
  originalItems: ChannelContentItem[],
  guideArtworkOwner: GuideArtworkOwner | null,
  lineupRevision: number | null,
): EpgProgramViewModel {
  const original = originalItems.find((item) => item.scheduledIndex === prog.item.scheduledIndex) || prog.item;
  const id = `${channelId}-${prog.scheduledStartTime}`;

  let subtitle = '';
  let episodeLabel = '';
  if (original.type === 'episode') {
    const s = original.seasonNumber !== undefined ? `S${original.seasonNumber}` : '';
    const e = original.episodeNumber !== undefined ? `E${original.episodeNumber}` : '';
    episodeLabel = [s, e].filter(Boolean).join(' ');
    subtitle = original.title;
  }

  const rating = ('contentRating' in original ? original.contentRating : '') || '';
  const quality: string[] = [];
  if ('mediaInfo' in original && original.mediaInfo) {
    if (original.mediaInfo.resolution) {
      quality.push(original.mediaInfo.resolution);
    }
    if (original.mediaInfo.hdr) {
      quality.push(original.mediaInfo.hdr);
    }
    if (original.mediaInfo.audioCodec) {
      quality.push(original.mediaInfo.audioCodec);
    }
  }

  return {
    id,
    title: ('showTitle' in original ? original.showTitle : null) || original.title,
    subtitle,
    description: ('summary' in original ? original.summary : null) || '',
    showTitle: ('showTitle' in original ? original.showTitle : null) || '',
    episodeLabel,
    rating,
    quality,
    genres: ('genres' in original ? original.genres : null) || [],
    startsAtMs: prog.scheduledStartTime,
    endsAtMs: prog.scheduledEndTime,
    artwork: createProgramArtworkRef(original, guideArtworkOwner, lineupRevision),
  };
}

function createProgramArtworkRef(
  item: ChannelContentItem | SchedulerContentItem,
  guideArtworkOwner: GuideArtworkOwner | null,
  lineupRevision: number | null,
) {
  if (guideArtworkOwner === null || lineupRevision === null) return null;
  const thumb = typeof item.thumb === 'string' && item.thumb.length > 0 ? item.thumb : null;
  const showThumb = 'showThumb' in item && typeof item.showThumb === 'string' && item.showThumb.length > 0
    ? item.showThumb
    : null;
  const locator = thumb ?? showThumb;
  if (locator === null) return null;
  const title = ('showTitle' in item ? item.showTitle : null) || item.title;
  return guideArtworkOwner.createRef({ locator, altText: title, lineupRevision });
}

function mapCurrentProgram(
  prog: ScheduledProgram,
  channelId: string,
  originalItems: ChannelContentItem[],
): EpgCurrentProgramViewModel {
  const original = originalItems.find((item) => item.scheduledIndex === prog.item.scheduledIndex) || prog.item;
  let subtitle = '';
  if (original.type === 'episode') {
    const s = original.seasonNumber !== undefined ? `S${original.seasonNumber}` : '';
    const e = original.episodeNumber !== undefined ? `E${original.episodeNumber}` : '';
    const label = [s, e].filter(Boolean).join(' ');
    subtitle = label ? `${label} - ${original.title}` : original.title;
  }

  return {
    title: ('showTitle' in original ? original.showTitle : null) || original.title,
    subtitle,
    channelId,
    startsAtMs: prog.scheduledStartTime,
    endsAtMs: prog.scheduledEndTime,
  };
}
