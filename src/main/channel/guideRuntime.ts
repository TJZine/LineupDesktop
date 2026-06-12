import type {
  EpgChannelViewModel,
  EpgCurrentProgramViewModel,
  EpgPresentationSource,
  EpgProgramViewModel,
} from '../../contracts/guide.js';
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

export class GuideRuntime {
  private readonly repository: ChannelRepository;
  private readonly contentResolver: ContentResolver;
  private readonly activeChannelScheduler: ChannelScheduler;
  private readonly clock: ChannelClock;
  private readonly onChannelTuned?: (channelId: string) => void | Promise<void>;
  private readonly logger: ChannelLogger;

  constructor(input: {
    repository: ChannelRepository;
    plexLibraryAdapter: PlexLibraryMinimalAdapter;
    activeChannelScheduler: ChannelScheduler;
    clock?: ChannelClock;
    onChannelTuned?: (channelId: string) => void | Promise<void>;
    logger?: ChannelLogger;
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
  }

  async getPresentation(
    startTimeMs: number,
    durationMs: number,
  ): Promise<EpgPresentationSource> {
    const loaded = await this.repository.loadNormalized();
    if (!loaded || loaded.data.channels.length === 0) {
      return {
        channels: [],
        nowWatching: null,
      };
    }

    const epgChannels: EpgChannelViewModel[] = await Promise.all(
      loaded.data.channels.map(async (channel) => {
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
          mapScheduledProgramToViewModel(prog, channel.id, channelItems),
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
    const currentChannel = loaded.data.channels.find(
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
    const channel = loaded.data.channels.find((c) => c.id === channelId);
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
    if (!loaded || loaded.data.channels.length === 0) {
      return;
    }
    const currentChannelId = loaded.data.currentChannelId || loaded.data.channels[0]?.id;
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
    if (!loaded || loaded.data.channels.length === 0 || !loaded.data.currentChannelId) {
      this.activeChannelScheduler.unloadChannel();
      return;
    }
    const currentChannel = loaded.data.channels.find((channel) =>
      channel.id === loaded.data.currentChannelId && channel.hidden !== true
    );
    if (!currentChannel) {
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
  };
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
