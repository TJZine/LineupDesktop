import {
  createEpgPresentationStates,
  createEpgShellView,
  createInfoPanelView,
  type EpgInfoPanelViewModel,
  type EpgPresentationStateViewModel,
  type EpgShellViewModel,
} from './guidePresentation.js';

export type EpgActionId =
  | 'previousWindow'
  | 'nextWindow'
  | 'previousChannel'
  | 'nextChannel'
  | 'previousProgram'
  | 'nextProgram';

export interface EpgProgramViewModel {
  id: string;
  title: string;
  subtitle: string;
  description: string;
  showTitle: string;
  episodeLabel: string;
  rating: string;
  quality: readonly string[];
  genres: readonly string[];
  startsAtMs: number;
  endsAtMs: number;
}

export interface EpgChannelViewModel {
  id: string;
  number: string;
  name: string;
  programs: readonly EpgProgramViewModel[];
}

export interface EpgState {
  windowStartMs: number;
  selectedChannelId: string;
  selectedProgramId: string;
  presentationState: EpgPresentationState;
}

export interface EpgTimeSlotViewModel {
  startsAtMs: number;
  endsAtMs: number;
  label: string;
}

export interface EpgProgramCellViewModel extends EpgProgramViewModel {
  channelId: string;
  columnStart: number;
  columnSpan: number;
  isSelected: boolean;
  temporalState: EpgProgramTemporalState;
  progressPercent: number;
  widthTier: EpgProgramWidthTier;
  timeLabel: string;
}

export interface EpgChannelRowViewModel {
  id: string;
  number: string;
  name: string;
  programs: readonly EpgProgramCellViewModel[];
  isSelected: boolean;
}

export interface EpgGuideViewModel {
  presentationState: EpgPresentationState;
  windowStartMs: number;
  windowEndMs: number;
  slots: readonly EpgTimeSlotViewModel[];
  rows: readonly EpgChannelRowViewModel[];
  selectedProgram: EpgProgramCellViewModel | null;
  shell: EpgShellViewModel;
  infoPanel: EpgInfoPanelViewModel | null;
  state: EpgPresentationStateViewModel;
}

export const EPG_SLOT_DURATION_MS = 30 * 60 * 1000;
export const EPG_VISIBLE_SLOT_COUNT = 6;
export const EPG_WINDOW_DURATION_MS = EPG_SLOT_DURATION_MS * EPG_VISIBLE_SLOT_COUNT;
export const EPG_DEMO_BASE_TIME_MS = Date.UTC(2026, 4, 12, 20, 0, 0);

export type EpgProgramTemporalState = 'past' | 'current' | 'upcoming';
export type EpgProgramWidthTier = 'wide' | 'medium' | 'narrow';

export type EpgPresentationState = 'ready' | 'loading' | 'empty' | 'error';

export interface EpgPresentationSource {
  channels: readonly EpgChannelViewModel[];
  nowWatching: EpgCurrentProgramViewModel;
}

export interface EpgCurrentProgramViewModel {
  title: string;
  subtitle: string;
  channelId: string;
  startsAtMs: number;
  endsAtMs: number;
}

export const DEFAULT_EPG_PRESENTATION_SOURCE = {
  channels: [
  {
    id: 'channel-liminal-one',
    number: '101',
    name: 'Liminal One',
    programs: [
      createProgram('liminal-cold-open', 'Signal Warmup', 'Cold open block', -30, 30, {
        showTitle: 'Lineup Live',
        episodeLabel: 'S1 E1',
        description: 'A short warmup block before the main channel run begins.',
        genres: ['Variety', 'Short'],
        rating: 'TV-PG',
        quality: ['HD', 'AAC'],
      }),
      createProgram('liminal-archive', 'The Midnight Archive', 'Signal Lost', 30, 90, {
        showTitle: 'The Midnight Archive',
        episodeLabel: 'S2 E4',
        description: 'A late-night archive episode with restored metadata, show title, rating, and guide details.',
        genres: ['Mystery', 'Drama', 'Archive'],
        rating: 'TV-14',
        quality: ['1080p', 'HDR', '5.1'],
      }),
      createProgram('liminal-after-hours', 'After Hours Cinema', 'Restored feature', 90, 180, {
        showTitle: 'After Hours Cinema',
        episodeLabel: 'Feature',
        description: 'A feature-length block that demonstrates wide guide cells and upcoming program presentation.',
        genres: ['Cinema', 'Restored'],
        rating: 'PG',
        quality: ['4K', 'Direct'],
      }),
      createProgram('liminal-signoff', 'Analog Signoff', 'Overnight loop', 180, 240, {
        showTitle: 'Analog Signoff',
        episodeLabel: 'Loop',
        description: 'A quiet overnight loop used by the UI to show late-window cells.',
        genres: ['Ambient'],
        rating: 'TV-G',
        quality: ['HD'],
      }),
    ],
  },
  {
    id: 'channel-vault',
    number: '204',
    name: 'The Vault',
    programs: [
      createProgram('vault-feature', 'Restored Feature', 'Studio print', 0, 90),
      createProgram('vault-notes', 'Director Notes', 'Production stories', 90, 120),
      createProgram('vault-double-feature', 'Double Feature', 'Late set', 120, 210),
    ],
  },
  {
    id: 'channel-weekend',
    number: '310',
    name: 'Weekend Queue With A Long Channel Name',
    programs: [
      createProgram('weekend-pilot', 'Pilot Block', 'First episodes', 0, 30),
      createProgram('weekend-marathon', 'Comfort Marathon', 'Season stretch', 30, 150),
      createProgram('weekend-wrap', 'Queue Wrap', 'Next picks', 150, 210),
    ],
  },
  {
    id: 'channel-studio',
    number: '420',
    name: 'Studio Desk',
    programs: [
      createProgram('studio-briefing', 'Lineup Briefing', 'Tonight lookahead', 0, 60),
      createProgram('studio-roundtable', 'Roundtable', 'Programming notes', 60, 120),
      createProgram('studio-spotlight', 'Creator Spotlight', 'Featured interview', 120, 180),
    ],
  },
] as const satisfies readonly EpgChannelViewModel[],
  nowWatching: {
    title: 'The Midnight Archive',
    subtitle: 'Episode 4 - Signal Lost',
    channelId: 'channel-liminal-one',
    startsAtMs: EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS,
    endsAtMs: EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS * 3,
  },
} as const satisfies EpgPresentationSource;

export function createEpgState(
  presentation: EpgPresentationSource = DEFAULT_EPG_PRESENTATION_SOURCE,
): EpgState {
  const initialSelection = deriveInitialEpgSelection(presentation);
  return {
    ...initialSelection,
    presentationState: initialSelection.selectedProgramId.length > 0 ? 'ready' : 'empty',
  };
}

export function getDefaultEpgPresentationChannels(): readonly EpgChannelViewModel[] {
  return DEFAULT_EPG_PRESENTATION_SOURCE.channels;
}

export function applyEpgAction(
  state: EpgState,
  actionId: EpgActionId,
  presentation: EpgPresentationSource = DEFAULT_EPG_PRESENTATION_SOURCE,
): EpgState {
  switch (actionId) {
    case 'previousWindow':
      return normalizeEpgSelection({
        ...state,
        windowStartMs: Math.max(
          minWindowStartMs(presentation),
          state.windowStartMs - EPG_SLOT_DURATION_MS,
        ),
      }, presentation);
    case 'nextWindow':
      return normalizeEpgSelection({
        ...state,
        windowStartMs: Math.min(
          maxWindowStartMs(presentation),
          state.windowStartMs + EPG_SLOT_DURATION_MS,
        ),
      }, presentation);
    case 'previousChannel':
      return selectChannelByOffset(state, -1, presentation);
    case 'nextChannel':
      return selectChannelByOffset(state, 1, presentation);
    case 'previousProgram':
      return selectProgramByOffset(state, -1, presentation);
    case 'nextProgram':
      return selectProgramByOffset(state, 1, presentation);
  }
}

export function setEpgPresentationState(
  state: EpgState,
  presentationState: EpgPresentationState,
): EpgState {
  return { ...state, presentationState };
}

export function createEpgGuideView(
  state: EpgState,
  presentation: EpgPresentationSource = DEFAULT_EPG_PRESENTATION_SOURCE,
): EpgGuideViewModel {
  const normalizedState = normalizeEpgSelection(state, presentation);
  const windowEndMs = normalizedState.windowStartMs + EPG_WINDOW_DURATION_MS;
  const slots = Array.from({ length: EPG_VISIBLE_SLOT_COUNT }, (_, index) => {
    const startsAtMs = normalizedState.windowStartMs + index * EPG_SLOT_DURATION_MS;
    return {
      startsAtMs,
      endsAtMs: startsAtMs + EPG_SLOT_DURATION_MS,
      label: formatEpgTime(startsAtMs),
    };
  });

  const showRows = normalizedState.presentationState === 'ready';
  const rows = showRows ? presentation.channels.map((channel) => ({
    id: channel.id,
    number: channel.number,
    name: channel.name,
    isSelected: channel.id === normalizedState.selectedChannelId,
    programs: channel.programs
      .filter((program) =>
        isProgramVisible(program, normalizedState.windowStartMs, windowEndMs),
      )
      .map((program) =>
        createProgramCell(
          program,
          channel.id,
          normalizedState,
          windowEndMs,
          presentation.nowWatching.startsAtMs,
        ),
      ),
  })) : [];

  const selectedProgram = rows
    .flatMap((row) => row.programs)
    .find((program) => program.isSelected);

  if (normalizedState.presentationState === 'ready' && selectedProgram === undefined) {
    throw new Error('EPG selection normalization did not produce a visible program');
  }

  return {
    presentationState: normalizedState.presentationState,
    windowStartMs: normalizedState.windowStartMs,
    windowEndMs,
    slots,
    rows,
    selectedProgram: selectedProgram ?? null,
    shell: createEpgShellView(presentation.channels, presentation.nowWatching),
    infoPanel: selectedProgram === undefined ? null : createInfoPanelView(selectedProgram),
    state: createEpgPresentationStates()[normalizedState.presentationState],
  };
}

export function calculateProgramSpan(
  program: EpgProgramViewModel,
  windowStartMs: number,
  windowEndMs: number,
): { columnStart: number; columnSpan: number } | null {
  if (!isProgramVisible(program, windowStartMs, windowEndMs)) {
    return null;
  }

  const clippedStartMs = Math.max(program.startsAtMs, windowStartMs);
  const clippedEndMs = Math.min(program.endsAtMs, windowEndMs);
  const columnStart = Math.floor((clippedStartMs - windowStartMs) / EPG_SLOT_DURATION_MS) + 1;
  const columnEnd = Math.ceil((clippedEndMs - windowStartMs) / EPG_SLOT_DURATION_MS) + 1;
  return {
    columnStart,
    columnSpan: Math.max(1, columnEnd - columnStart),
  };
}

export function formatEpgTimeWindow(startsAtMs: number, endsAtMs: number): string {
  return `${formatEpgTime(startsAtMs)} - ${formatEpgTime(endsAtMs)}`;
}

export function formatEpgTime(valueMs: number): string {
  const date = new Date(valueMs);
  const hour24 = date.getUTCHours();
  const hour = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const minute = String(date.getUTCMinutes()).padStart(2, '0');
  const period = hour24 < 12 ? 'AM' : 'PM';
  return `${hour}:${minute} ${period}`;
}

function createProgram(
  id: string,
  title: string,
  subtitle: string,
  startOffsetMinutes: number,
  endOffsetMinutes: number,
  options: Partial<Pick<EpgProgramViewModel, 'description' | 'showTitle' | 'episodeLabel' | 'rating' | 'quality' | 'genres'>> = {},
): EpgProgramViewModel {
  return {
    id,
    title,
    subtitle,
    description: options.description ?? `${title} is scheduled in this renderer-safe guide state.`,
    showTitle: options.showTitle ?? title,
    episodeLabel: options.episodeLabel ?? 'Program',
    rating: options.rating ?? 'TV-PG',
    quality: options.quality ?? ['HD', 'Stereo'],
    genres: options.genres ?? ['Lineup'],
    startsAtMs: EPG_DEMO_BASE_TIME_MS + startOffsetMinutes * 60 * 1000,
    endsAtMs: EPG_DEMO_BASE_TIME_MS + endOffsetMinutes * 60 * 1000,
  };
}

function createProgramCell(
  program: EpgProgramViewModel,
  channelId: string,
  state: EpgState,
  windowEndMs: number,
  referenceNowMs: number,
): EpgProgramCellViewModel {
  const span = calculateProgramSpan(program, state.windowStartMs, windowEndMs);
  if (span === null) {
    throw new Error(`Visible EPG program ${program.id} did not produce a span`);
  }

  return {
    ...program,
    channelId,
    columnStart: span.columnStart,
    columnSpan: span.columnSpan,
    isSelected: channelId === state.selectedChannelId && program.id === state.selectedProgramId,
    temporalState: getProgramTemporalState(program, referenceNowMs),
    progressPercent: getProgramProgressPercent(program, referenceNowMs),
    widthTier: getProgramWidthTier(span.columnSpan),
    timeLabel: formatEpgTimeWindow(program.startsAtMs, program.endsAtMs),
  };
}

function getProgramTemporalState(
  program: EpgProgramViewModel,
  referenceNowMs: number,
): EpgProgramTemporalState {
  const nowMs = referenceNowMs;
  if (program.endsAtMs <= nowMs) {
    return 'past';
  }
  if (program.startsAtMs <= nowMs && program.endsAtMs > nowMs) {
    return 'current';
  }
  return 'upcoming';
}

function getProgramProgressPercent(
  program: EpgProgramViewModel,
  referenceNowMs: number,
): number {
  if (getProgramTemporalState(program, referenceNowMs) !== 'current') {
    return 0;
  }
  const nowMs = referenceNowMs;
  const durationMs = Math.max(1, program.endsAtMs - program.startsAtMs);
  return Math.round(((nowMs - program.startsAtMs) / durationMs) * 100);
}

function getProgramWidthTier(columnSpan: number): EpgProgramWidthTier {
  if (columnSpan >= 3) {
    return 'wide';
  }
  return columnSpan === 2 ? 'medium' : 'narrow';
}


function normalizeEpgSelection(state: EpgState, presentation: EpgPresentationSource): EpgState {
  const windowStartMs = clampWindowStartMs(state.windowStartMs, presentation);
  const channel = findChannel(state.selectedChannelId, presentation) ?? presentation.channels[0];
  if (channel === undefined) {
    return {
      windowStartMs,
      selectedChannelId: '',
      selectedProgramId: '',
      presentationState: state.presentationState,
    };
  }
  const visiblePrograms = visibleProgramsForChannel(channel, windowStartMs);
  const selectedProgram = visiblePrograms.find((program) => program.id === state.selectedProgramId);
  const fallbackProgram = selectedProgram ?? visiblePrograms[0] ?? channel.programs[0];
  return {
    windowStartMs,
    selectedChannelId: channel.id,
    selectedProgramId: fallbackProgram?.id ?? '',
    presentationState: state.presentationState,
  };
}

function selectChannelByOffset(
  state: EpgState,
  offset: number,
  presentation: EpgPresentationSource,
): EpgState {
  const currentIndex = Math.max(
    0,
    presentation.channels.findIndex((channel) => channel.id === state.selectedChannelId),
  );
  const nextIndex = clamp(currentIndex + offset, 0, presentation.channels.length - 1);
  const nextChannel = presentation.channels[nextIndex];
  if (nextChannel === undefined) {
    return state;
  }
  return normalizeEpgSelection({
    ...state,
    selectedChannelId: nextChannel.id,
  }, presentation);
}

function selectProgramByOffset(
  state: EpgState,
  offset: number,
  presentation: EpgPresentationSource,
): EpgState {
  const channel = findChannel(state.selectedChannelId, presentation) ?? presentation.channels[0];
  if (channel === undefined) {
    return state;
  }
  const visiblePrograms = visibleProgramsForChannel(channel, state.windowStartMs);
  const currentIndex = Math.max(
    0,
    visiblePrograms.findIndex((program) => program.id === state.selectedProgramId),
  );
  const nextIndex = clamp(currentIndex + offset, 0, visiblePrograms.length - 1);
  const fallbackProgramId = visiblePrograms[nextIndex]?.id ?? channel.programs[0]?.id ?? '';
  return normalizeEpgSelection({
    ...state,
    selectedChannelId: channel.id,
    selectedProgramId: fallbackProgramId,
  }, presentation);
}

function visibleProgramsForChannel(
  channel: EpgChannelViewModel,
  windowStartMs: number,
): readonly EpgProgramViewModel[] {
  return channel.programs.filter((program) =>
    isProgramVisible(program, windowStartMs, windowStartMs + EPG_WINDOW_DURATION_MS),
  );
}

function isProgramVisible(
  program: EpgProgramViewModel,
  windowStartMs: number,
  windowEndMs: number,
): boolean {
  return program.startsAtMs < windowEndMs && program.endsAtMs > windowStartMs;
}

function findChannel(
  channelId: string,
  presentation: EpgPresentationSource,
): EpgChannelViewModel | undefined {
  return presentation.channels.find((channel) => channel.id === channelId);
}

function deriveInitialEpgSelection(
  presentation: EpgPresentationSource,
): Pick<EpgState, 'windowStartMs' | 'selectedChannelId' | 'selectedProgramId'> {
  const firstProgram = listPresentationPrograms(presentation)[0];
  const preferredChannel =
    findChannel(presentation.nowWatching.channelId, presentation) ??
    firstProgram?.channel ??
    presentation.channels[0];
  const anchorMsCandidates = [
    presentation.nowWatching.startsAtMs,
    firstProgram?.program.startsAtMs,
    EPG_DEMO_BASE_TIME_MS,
  ];

  for (const anchorMs of anchorMsCandidates) {
    if (anchorMs === undefined) {
      continue;
    }
    const windowStartMs = clampWindowStartMs(snapWindowStartMs(anchorMs), presentation);
    const selectedProgram = pickInitialProgramSelection(presentation, preferredChannel, windowStartMs);
    if (selectedProgram !== null) {
      return {
        windowStartMs,
        selectedChannelId: selectedProgram.channel.id,
        selectedProgramId: selectedProgram.program.id,
      };
    }
  }

  return {
    windowStartMs: EPG_DEMO_BASE_TIME_MS,
    selectedChannelId: firstProgram?.channel.id ?? '',
    selectedProgramId: firstProgram?.program.id ?? '',
  };
}

function pickInitialProgramSelection(
  presentation: EpgPresentationSource,
  preferredChannel: EpgChannelViewModel | undefined,
  windowStartMs: number,
): { channel: EpgChannelViewModel; program: EpgProgramViewModel } | null {
  const preferredProgram = preferredChannel === undefined
    ? undefined
    : pickVisibleProgramForChannel(preferredChannel, windowStartMs, presentation.nowWatching);
  if (preferredProgram !== undefined && preferredChannel !== undefined) {
    return { channel: preferredChannel, program: preferredProgram };
  }
  return findFirstVisibleProgram(presentation, windowStartMs);
}

function pickVisibleProgramForChannel(
  channel: EpgChannelViewModel,
  windowStartMs: number,
  nowWatching: EpgCurrentProgramViewModel,
): EpgProgramViewModel | undefined {
  const visiblePrograms = visibleProgramsForChannel(channel, windowStartMs);
  return visiblePrograms.find((program) => programsMatchNowWatching(program, nowWatching))
    ?? visiblePrograms[0];
}

function programsMatchNowWatching(
  program: EpgProgramViewModel,
  nowWatching: EpgCurrentProgramViewModel,
): boolean {
  return program.startsAtMs === nowWatching.startsAtMs &&
    program.endsAtMs === nowWatching.endsAtMs;
}

function findFirstVisibleProgram(
  presentation: EpgPresentationSource,
  windowStartMs: number,
): { channel: EpgChannelViewModel; program: EpgProgramViewModel } | null {
  for (const channel of presentation.channels) {
    const program = visibleProgramsForChannel(channel, windowStartMs)[0];
    if (program !== undefined) {
      return { channel, program };
    }
  }
  return null;
}

function listPresentationPrograms(
  presentation: EpgPresentationSource,
): readonly { channel: EpgChannelViewModel; program: EpgProgramViewModel }[] {
  return presentation.channels.flatMap((channel) =>
    channel.programs.map((program) => ({ channel, program })),
  );
}

function snapWindowStartMs(valueMs: number): number {
  return Math.floor(valueMs / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS;
}

function clampWindowStartMs(
  windowStartMs: number,
  presentation: EpgPresentationSource,
): number {
  return clamp(windowStartMs, minWindowStartMs(presentation), maxWindowStartMs(presentation));
}

function minWindowStartMs(presentation: EpgPresentationSource): number {
  const earliestProgramStartMs = listPresentationPrograms(presentation)
    .reduce<number | null>((minStartMs, entry) => (
      minStartMs === null || entry.program.startsAtMs < minStartMs
        ? entry.program.startsAtMs
        : minStartMs
    ), null);
  return earliestProgramStartMs === null
    ? EPG_DEMO_BASE_TIME_MS
    : snapWindowStartMs(earliestProgramStartMs);
}

function maxWindowStartMs(presentation: EpgPresentationSource): number {
  const lastProgramEndMs = listPresentationPrograms(presentation)
    .reduce<number | null>((maxEndMs, entry) => (
      maxEndMs === null || entry.program.endsAtMs > maxEndMs
        ? entry.program.endsAtMs
        : maxEndMs
    ), null);
  const minWindowStart = minWindowStartMs(presentation);
  if (lastProgramEndMs === null) {
    return minWindowStart;
  }
  return Math.max(
    minWindowStart,
    snapWindowStartMs(lastProgramEndMs - EPG_WINDOW_DURATION_MS),
  );
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
