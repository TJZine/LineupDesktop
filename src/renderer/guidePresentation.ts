import type {
  EpgChannelViewModel,
  EpgCurrentProgramViewModel,
  EpgPresentationState,
  EpgProgramCellViewModel,
} from './epg.js';

export interface ProgramSummaryViewModel {
  title: string;
  subtitle: string;
  channelNumber: string;
  channelName: string;
  startsAtMs: number;
  endsAtMs: number;
}

export interface EpgShellViewModel {
  brandLabel: string;
  layoutMode: 'classic';
  focusHint: string;
  nowWatching: ProgramSummaryViewModel;
  nowWatchingChannelLabel: string;
}

export interface EpgInfoPanelViewModel {
  eyebrow: string;
  title: string;
  subtitle: string;
  timeLabel: string;
  description: string;
  badges: readonly string[];
  genres: string;
}

export interface EpgPresentationStateViewModel {
  state: EpgPresentationState;
  label: string;
  detail: string;
}

export function createEpgShellView(
  channels: readonly EpgChannelViewModel[],
  nowWatching: EpgCurrentProgramViewModel,
): EpgShellViewModel {
  const channelNumber = selectedChannelNumber(channels, nowWatching.channelId);
  const channelName = selectedChannelName(channels, nowWatching.channelId);
  return {
    brandLabel: 'LINEUP',
    layoutMode: 'classic',
    focusHint: 'OK Select - Left/Right Navigate - Back Close',
    nowWatching: {
      title: nowWatching.title,
      subtitle: nowWatching.subtitle,
      channelNumber,
      channelName,
      startsAtMs: nowWatching.startsAtMs,
      endsAtMs: nowWatching.endsAtMs,
    },
    nowWatchingChannelLabel: `${channelNumber} - ${channelName}`,
  };
}

export function createInfoPanelView(program: EpgProgramCellViewModel): EpgInfoPanelViewModel {
  return {
    eyebrow: program.showTitle,
    title: program.title,
    subtitle: program.episodeLabel,
    timeLabel: program.timeLabel,
    description: program.description,
    badges: [program.rating, ...program.quality],
    genres: program.genres.join(' - '),
  };
}

export function createEpgPresentationStates(): Readonly<Record<EpgPresentationState, EpgPresentationStateViewModel>> {
  return {
    ready: {
      state: 'ready',
      label: 'Guide ready',
      detail: 'Channel rows, time slots, focused programs, and details are available.',
    },
    loading: {
      state: 'loading',
      label: 'Loading guide',
      detail: 'Schedule rows are preparing for the selected lineup.',
    },
    empty: {
      state: 'empty',
      label: 'No channels available',
      detail: 'Add channels from setup to populate this guide.',
    },
    error: {
      state: 'error',
      label: 'Guide unavailable',
      detail: 'The guide could not be shown. Try again from the route controls.',
    },
  };
}

function selectedChannelNumber(channels: readonly EpgChannelViewModel[], channelId: string): string {
  return channels.find((channel) => channel.id === channelId)?.number ?? '';
}

function selectedChannelName(channels: readonly EpgChannelViewModel[], channelId: string): string {
  return channels.find((channel) => channel.id === channelId)?.name ?? '';
}
