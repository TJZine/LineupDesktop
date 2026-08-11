import type {
  EpgChannelViewModel,
  EpgCurrentProgramViewModel,
  EpgPresentationState,
  EpgProgramCellViewModel,
} from './epg.js';
import type { GuideArtworkSet } from '../contracts/artwork.js';
import type { GuideLibraryFilterState } from '../contracts/guide.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type { AppRouteId } from './navigation.js';
import type { PlayerPresentationMode, PlayerSnapshot } from '../contracts/player.js';
import type { DesktopSettingsValues } from '../contracts/settings.js';
import type { RendererShellState } from './shell/shellState.js';

export function projectNativePlayerPresentationMode(input: {
  route: AppRouteId;
  guideLayout: DesktopSettingsValues['guideLayout'];
  snapshot: PlayerSnapshot;
  shell: RendererShellState;
}): PlayerPresentationMode {
  const blocked = input.shell.bootstrap !== 'ready' || input.shell.exitConfirmOpen ||
    input.shell.inlineError !== null || input.snapshot.lastError !== null;
  const presentable = input.snapshot.requestId !== null &&
    ['ready', 'buffering', 'playing', 'paused', 'seeking', 'stalled'].includes(input.snapshot.status);
  if (blocked || !presentable) return 'hidden';
  if (input.route === 'player') return 'player-full';
  if (input.route !== 'guide') return 'hidden';
  if (input.guideLayout === 'overlay') return 'guide-overlay-full';
  return input.snapshot.playing ? 'guide-classic-pip' : 'hidden';
}

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
  artwork: GuideArtworkSet;
  presentationGeneration: number;
}

export interface EpgPresentationStateViewModel {
  state: EpgPresentationState;
  label: string;
  detail: string;
}

export interface GuideLibraryFilterController {
  select(libraryId: string | null): boolean;
  cancel(): void;
  isPending(): boolean;
}

export function createGuideLibraryFilterController(options: {
  guide: LineupDesktopPreloadApi['guide'];
  getActiveRoute(): AppRouteId;
  getFilter(): GuideLibraryFilterState | null;
  applyFilter(filter: GuideLibraryFilterState): void;
  refresh(): void;
  cancelPage(): void;
  handleFailure(message: string): void;
  onPendingChanged(): void;
}): GuideLibraryFilterController {
  let operationGeneration = 0;
  let pending = false;

  const cancel = (): void => {
    operationGeneration += 1;
    if (!pending) return;
    pending = false;
    options.onPendingChanged();
  };

  return {
    select(libraryId) {
      const filter = options.getFilter();
      if (pending || options.getActiveRoute() !== 'guide' || filter === null ||
        (libraryId !== null && !filter.libraries.some((library) => library.id === libraryId))) return false;
      const generation = ++operationGeneration;
      const scopeToken = filter.scopeToken;
      pending = true;
      options.cancelPage();
      options.onPendingChanged();
      void options.guide.setLibraryFilter({
        expectedScopeToken: scopeToken,
        expectedRevision: filter.revision,
        libraryId,
      }).then((result) => {
        if (generation !== operationGeneration) return;
        pending = false;
        if (options.getActiveRoute() !== 'guide' || options.getFilter()?.scopeToken !== scopeToken) {
          options.onPendingChanged();
          return;
        }
        if (!result.ok) {
          options.handleFailure(result.error.message);
          options.onPendingChanged();
          return;
        }
        options.applyFilter(result.value);
        options.onPendingChanged();
        options.refresh();
      }, () => {
        if (generation !== operationGeneration) return;
        pending = false;
        if (options.getActiveRoute() === 'guide' && options.getFilter()?.scopeToken === scopeToken) {
          options.handleFailure('Guide preferences could not be saved.');
        }
        options.onPendingChanged();
      });
      return true;
    },
    cancel,
    isPending: () => pending,
  };
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
    artwork: program.artwork,
    presentationGeneration: program.presentationGeneration,
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
