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
}

export interface EpgChannelRowViewModel {
  id: string;
  number: string;
  name: string;
  programs: readonly EpgProgramCellViewModel[];
  isSelected: boolean;
}

export interface EpgGuideViewModel {
  windowStartMs: number;
  windowEndMs: number;
  slots: readonly EpgTimeSlotViewModel[];
  rows: readonly EpgChannelRowViewModel[];
  selectedProgram: EpgProgramCellViewModel;
}

export const EPG_SLOT_DURATION_MS = 30 * 60 * 1000;
export const EPG_VISIBLE_SLOT_COUNT = 6;
export const EPG_WINDOW_DURATION_MS = EPG_SLOT_DURATION_MS * EPG_VISIBLE_SLOT_COUNT;
export const EPG_DEMO_BASE_TIME_MS = Date.UTC(2026, 4, 12, 20, 0, 0);

const FAKE_EPG_CHANNELS = [
  {
    id: 'channel-liminal-one',
    number: '101',
    name: 'Liminal One',
    programs: [
      createProgram('liminal-cold-open', 'Signal Warmup', 'Cold open block', -30, 30),
      createProgram('liminal-archive', 'The Midnight Archive', 'Signal Lost', 30, 90),
      createProgram('liminal-after-hours', 'After Hours Cinema', 'Restored feature', 90, 180),
      createProgram('liminal-signoff', 'Analog Signoff', 'Overnight loop', 180, 240),
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
    name: 'Weekend Queue',
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
      createProgram('studio-briefing', 'Lineup Briefing', 'Tonight preview', 0, 60),
      createProgram('studio-roundtable', 'Roundtable', 'Programming notes', 60, 120),
      createProgram('studio-spotlight', 'Creator Spotlight', 'Featured interview', 120, 180),
    ],
  },
] as const satisfies readonly EpgChannelViewModel[];

export function createEpgState(): EpgState {
  return {
    windowStartMs: EPG_DEMO_BASE_TIME_MS,
    selectedChannelId: FAKE_EPG_CHANNELS[0].id,
    selectedProgramId: 'liminal-archive',
  };
}

export function getFakeEpgChannels(): readonly EpgChannelViewModel[] {
  return FAKE_EPG_CHANNELS;
}

export function applyEpgAction(state: EpgState, actionId: EpgActionId): EpgState {
  switch (actionId) {
    case 'previousWindow':
      return normalizeEpgSelection({
        ...state,
        windowStartMs: Math.max(minWindowStartMs(), state.windowStartMs - EPG_SLOT_DURATION_MS),
      });
    case 'nextWindow':
      return normalizeEpgSelection({
        ...state,
        windowStartMs: Math.min(maxWindowStartMs(), state.windowStartMs + EPG_SLOT_DURATION_MS),
      });
    case 'previousChannel':
      return selectChannelByOffset(state, -1);
    case 'nextChannel':
      return selectChannelByOffset(state, 1);
    case 'previousProgram':
      return selectProgramByOffset(state, -1);
    case 'nextProgram':
      return selectProgramByOffset(state, 1);
  }
}

export function createEpgGuideView(state: EpgState): EpgGuideViewModel {
  const normalizedState = normalizeEpgSelection(state);
  const windowEndMs = normalizedState.windowStartMs + EPG_WINDOW_DURATION_MS;
  const slots = Array.from({ length: EPG_VISIBLE_SLOT_COUNT }, (_, index) => {
    const startsAtMs = normalizedState.windowStartMs + index * EPG_SLOT_DURATION_MS;
    return {
      startsAtMs,
      endsAtMs: startsAtMs + EPG_SLOT_DURATION_MS,
      label: formatEpgTime(startsAtMs),
    };
  });

  const rows = FAKE_EPG_CHANNELS.map((channel) => ({
    id: channel.id,
    number: channel.number,
    name: channel.name,
    isSelected: channel.id === normalizedState.selectedChannelId,
    programs: channel.programs
      .filter((program) =>
        isProgramVisible(program, normalizedState.windowStartMs, windowEndMs),
      )
      .map((program) =>
        createProgramCell(program, channel.id, normalizedState, windowEndMs),
      ),
  }));

  const selectedProgram = rows
    .flatMap((row) => row.programs)
    .find((program) => program.isSelected);

  if (selectedProgram === undefined) {
    throw new Error('EPG selection normalization did not produce a visible program');
  }

  return {
    windowStartMs: normalizedState.windowStartMs,
    windowEndMs,
    slots,
    rows,
    selectedProgram,
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
): EpgProgramViewModel {
  return {
    id,
    title,
    subtitle,
    startsAtMs: EPG_DEMO_BASE_TIME_MS + startOffsetMinutes * 60 * 1000,
    endsAtMs: EPG_DEMO_BASE_TIME_MS + endOffsetMinutes * 60 * 1000,
  };
}

function createProgramCell(
  program: EpgProgramViewModel,
  channelId: string,
  state: EpgState,
  windowEndMs: number,
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
  };
}

function normalizeEpgSelection(state: EpgState): EpgState {
  const channel = findChannel(state.selectedChannelId) ?? FAKE_EPG_CHANNELS[0];
  const visiblePrograms = visibleProgramsForChannel(channel, state.windowStartMs);
  const selectedProgram = visiblePrograms.find((program) => program.id === state.selectedProgramId);
  const fallbackProgram = selectedProgram ?? visiblePrograms[0] ?? channel.programs[0];
  return {
    windowStartMs: state.windowStartMs,
    selectedChannelId: channel.id,
    selectedProgramId: fallbackProgram.id,
  };
}

function selectChannelByOffset(state: EpgState, offset: number): EpgState {
  const currentIndex = Math.max(
    0,
    FAKE_EPG_CHANNELS.findIndex((channel) => channel.id === state.selectedChannelId),
  );
  const nextIndex = clamp(currentIndex + offset, 0, FAKE_EPG_CHANNELS.length - 1);
  return normalizeEpgSelection({
    ...state,
    selectedChannelId: FAKE_EPG_CHANNELS[nextIndex].id,
  });
}

function selectProgramByOffset(state: EpgState, offset: number): EpgState {
  const channel = findChannel(state.selectedChannelId) ?? FAKE_EPG_CHANNELS[0];
  const visiblePrograms = visibleProgramsForChannel(channel, state.windowStartMs);
  const currentIndex = Math.max(
    0,
    visiblePrograms.findIndex((program) => program.id === state.selectedProgramId),
  );
  const nextIndex = clamp(currentIndex + offset, 0, visiblePrograms.length - 1);
  return normalizeEpgSelection({
    ...state,
    selectedChannelId: channel.id,
    selectedProgramId: visiblePrograms[nextIndex]?.id ?? channel.programs[0].id,
  });
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

function findChannel(channelId: string): EpgChannelViewModel | undefined {
  return FAKE_EPG_CHANNELS.find((channel) => channel.id === channelId);
}

function minWindowStartMs(): number {
  return EPG_DEMO_BASE_TIME_MS;
}

function maxWindowStartMs(): number {
  return EPG_DEMO_BASE_TIME_MS + EPG_SLOT_DURATION_MS * 2;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
