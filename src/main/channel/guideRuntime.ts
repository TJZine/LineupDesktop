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
import type { PlexLibraryMinimalAdapter } from './plexLibraryMinimalAdapter.js';

export class GuideRuntime {
  private readonly repository: ChannelRepository;
  private readonly contentResolver: ContentResolver;
  private readonly activeChannelScheduler: ChannelScheduler;
  private readonly clock: ChannelClock;
  private readonly onChannelTuned?: (channelId: string) => void | Promise<void>;

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
        } catch {
          // Fallback to empty if resolution fails
        }

        if (channelItems.length === 0) {
          return {
            id: channel.id,
            number: String(channel.number),
            name: channel.name,
            programs: [],
          };
        }

        const schedulerItems = channelItems.map(toSchedulerContentItem);
        const schedulerPlaybackMode: SchedulerPlaybackMode =
          channel.playbackMode === 'random' ? 'shuffle' : channel.playbackMode;

        const scheduler = new ChannelScheduler({ clock: this.clock });
        scheduler.loadChannel({
          channelId: channel.id,
          anchorTime: channel.startTimeAnchor,
          content: schedulerItems,
          playbackMode: schedulerPlaybackMode,
          shuffleSeed: channel.shuffleSeed ?? 0,
          blockSize: channel.blockSize,
        });

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
        } catch {
          // Ignore
        }
        nowWatching = mapCurrentProgram(state.currentProgram, currentChannel.id, currentItems);
      } else {
        // Fallback calculation if active scheduler is not loaded yet
        let currentItems: ChannelContentItem[] = [];
        try {
          currentItems = await this.contentResolver.resolveSource(currentChannel.contentSource);
        } catch {
          // Ignore
        }
        if (currentItems.length > 0) {
          const schedulerItems = currentItems.map(toSchedulerContentItem);
          const schedulerPlaybackMode: SchedulerPlaybackMode =
            currentChannel.playbackMode === 'random' ? 'shuffle' : currentChannel.playbackMode;

          const scheduler = new ChannelScheduler({ clock: this.clock });
          scheduler.loadChannel({
            channelId: currentChannel.id,
            anchorTime: currentChannel.startTimeAnchor,
            content: schedulerItems,
            playbackMode: schedulerPlaybackMode,
            shuffleSeed: currentChannel.shuffleSeed ?? 0,
            blockSize: currentChannel.blockSize,
          });
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

    this.activeChannelScheduler.loadChannel({
      channelId: channel.id,
      anchorTime: channel.startTimeAnchor,
      content: schedulerItems,
      playbackMode: schedulerPlaybackMode,
      shuffleSeed: channel.shuffleSeed ?? 0,
      blockSize: channel.blockSize,
    });

    await this.repository.saveCurrentChannelId(channelId);
    if (this.onChannelTuned) {
      await this.onChannelTuned(channelId);
    }
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
      } catch {
        // Log error internally but do not crash startup
      }
    }
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
