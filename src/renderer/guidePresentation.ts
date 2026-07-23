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
  nowWatching: ProgramSummaryViewModel | null;
  nowWatchingChannelLabel: string | null;
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
  nowWatching: EpgCurrentProgramViewModel | null,
): EpgShellViewModel {
  const shared = {
    brandLabel: 'LINEUP',
    layoutMode: 'classic' as const,
    focusHint: 'OK Select · LEFT/RIGHT Navigate · BACK Close',
  };
  if (nowWatching === null) {
    return { ...shared, nowWatching: null, nowWatchingChannelLabel: null };
  }
  const channel = channels.find((candidate) => candidate.id === nowWatching.channelId);
  return {
    ...shared,
    nowWatching: {
      title: nowWatching.title,
      subtitle: nowWatching.subtitle,
      channelNumber: channel?.number ?? '',
      channelName: channel?.name ?? '',
      startsAtMs: nowWatching.startsAtMs,
      endsAtMs: nowWatching.endsAtMs,
    },
    nowWatchingChannelLabel: channel === undefined ? null : `${channel.number} - ${channel.name}`,
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
    'empty-channels': {
      state: 'empty-channels',
      label: 'No channels available',
      detail: 'Add channels from setup to populate this guide.',
    },
    'empty-programs': {
      state: 'empty-programs',
      label: 'No programs in this window',
      detail: 'Refresh the schedule or adjust your channel lineup.',
    },
    error: {
      state: 'error',
      label: 'Guide unavailable',
      detail: 'The guide could not be shown. Try again from the route controls.',
    },
  };
}
