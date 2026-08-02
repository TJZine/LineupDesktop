import {
  createEpgPresentationStates,
  createEpgShellView,
  createInfoPanelView,
  type EpgInfoPanelViewModel,
  type EpgPresentationStateViewModel,
  type EpgShellViewModel,
} from './guidePresentation.js';
import type { ArtworkRef } from '../contracts/artwork.js';

export type EpgActionId =
  | 'previousWindow'
  | 'nextWindow'
  | 'previousChannel'
  | 'nextChannel'
  | 'previousProgram'
  | 'nextProgram';

export type EpgDirection = 'up' | 'down' | 'left' | 'right';

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
  artwork: ArtworkRef | null;
}

export interface EpgChannelViewModel {
  id: string;
  number: string;
  name: string;
  programs: readonly EpgProgramViewModel[];
}

export type EpgPresentationState =
  | 'ready'
  | 'loading'
  | 'empty-channels'
  | 'empty-programs'
  | 'error';

export interface EpgState {
  windowStartMs: number;
  selectedChannelId: string;
  selectedProgramId: string;
  presentationState: EpgPresentationState;
  presentationGeneration: number;
  tuneError: string | null;
}

export interface EpgTimeSlotViewModel {
  startsAtMs: number;
  endsAtMs: number;
  label: string;
}

export type EpgProgramTemporalState = 'past' | 'current' | 'upcoming';
export type EpgProgramWidthTier = 'wide' | 'medium' | 'narrow';

export interface EpgProgramCellViewModel extends EpgProgramViewModel {
  channelId: string;
  focusId: string;
  presentationGeneration: number;
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
  presentationGeneration: number;
  tuneError: string | null;
  nowMs: number;
  windowStartMs: number;
  windowEndMs: number;
  slots: readonly EpgTimeSlotViewModel[];
  rows: readonly EpgChannelRowViewModel[];
  selectedProgram: EpgProgramCellViewModel | null;
  shell: EpgShellViewModel;
  infoPanel: EpgInfoPanelViewModel | null;
  state: EpgPresentationStateViewModel;
}

export interface EpgPresentationSource {
  channels: readonly EpgChannelViewModel[];
  nowWatching: EpgCurrentProgramViewModel | null;
  nowMs?: number;
}

export interface NormalizedEpgPresentationSource extends Omit<EpgPresentationSource, 'nowMs'> {
  readonly nowMs: number;
}

export interface EpgCurrentProgramViewModel {
  title: string;
  subtitle: string;
  channelId: string;
  startsAtMs: number;
  endsAtMs: number;
}

export interface EpgDirectionResult {
  state: EpgState;
  handled: boolean;
  windowChanged: boolean;
}

export const EPG_SLOT_DURATION_MS = 30 * 60 * 1000;
export const EPG_VISIBLE_SLOT_COUNT = 6;
export const EPG_WINDOW_DURATION_MS = EPG_SLOT_DURATION_MS * EPG_VISIBLE_SLOT_COUNT;

/** An honest startup value. Product Guide rows arrive only from the scheduler bridge. */
export const EMPTY_EPG_PRESENTATION_SOURCE: EpgPresentationSource = {
  channels: [],
  nowWatching: null,
};

/** Retained until the Package 6 fixture bundle is removed; it contains no schedule fixture. */
export const DEFAULT_EPG_PRESENTATION_SOURCE = EMPTY_EPG_PRESENTATION_SOURCE;

export function normalizeEpgPresentation(
  presentation: EpgPresentationSource,
): NormalizedEpgPresentationSource {
  const nowMs = isValidTime(presentation.nowMs) ? presentation.nowMs : Date.now();
  return { ...presentation, nowMs };
}

export function createEpgState(
  presentation: EpgPresentationSource = EMPTY_EPG_PRESENTATION_SOURCE,
  presentationGeneration = 0,
): EpgState {
  const initialSelection = deriveInitialEpgSelection(presentation);
  return {
    ...initialSelection,
    presentationState: classifyPresentation(presentation, initialSelection.windowStartMs),
    presentationGeneration,
    tuneError: null,
  };
}

export function getDefaultEpgPresentationChannels(): readonly EpgChannelViewModel[] {
  return EMPTY_EPG_PRESENTATION_SOURCE.channels;
}

export function createGuideProgramFocusId(channelId: string, programId: string): string {
  return `guide-program-${encodeURIComponent(channelId)}--${encodeURIComponent(programId)}`;
}

export function isEpgProgramPlayable(program: Pick<EpgProgramViewModel, 'startsAtMs' | 'endsAtMs'>, nowMs: number): boolean {
  return program.startsAtMs <= nowMs && nowMs < program.endsAtMs;
}

export function applyEpgAction(
  state: EpgState,
  actionId: EpgActionId,
  presentation: EpgPresentationSource,
): EpgState {
  switch (actionId) {
    case 'previousWindow':
      return moveWindow(state, -1, presentation);
    case 'nextWindow':
      return moveWindow(state, 1, presentation);
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

export function moveEpgSelection(
  state: EpgState,
  direction: EpgDirection,
  presentation: EpgPresentationSource,
): EpgDirectionResult {
  if (state.presentationState !== 'ready') {
    return { state, handled: false, windowChanged: false };
  }
  if (direction === 'left' || direction === 'right') {
    const offset = direction === 'left' ? -1 : 1;
    const adjacent = selectProgramByOffset(state, offset, presentation);
    if (adjacent.selectedProgramId !== state.selectedProgramId) {
      return { state: adjacent, handled: true, windowChanged: false };
    }
    const shifted = moveWindowIntent(state, offset);
    return {
      state: shifted,
      handled: true,
      windowChanged: shifted.windowStartMs !== state.windowStartMs,
    };
  }

  const moved = selectNearestProgramOnAdjacentChannel(
    state,
    direction === 'up' ? -1 : 1,
    presentation,
  );
  return {
    state: moved,
    handled: true,
    windowChanged: false,
  };
}

export function pageEpgSelection(
  state: EpgState,
  offset: -5 | 5,
  presentation: EpgPresentationSource,
): EpgDirectionResult {
  if (state.presentationState !== 'ready') {
    return { state, handled: false, windowChanged: false };
  }
  return {
    state: selectNearestProgramOnAdjacentChannel(state, offset, presentation),
    handled: true,
    windowChanged: false,
  };
}

export function focusEpgNow(
  state: EpgState,
  presentation: EpgPresentationSource,
  nowMs: number,
): EpgState {
  if (state.presentationState !== 'ready' || !isValidTime(nowMs)) return state;
  const windowStartMs = snapWindowStartMs(nowMs);
  const focusedChannel = findChannel(state.selectedChannelId, presentation);
  const currentProgram = focusedChannel?.programs.find((program) =>
    isEpgProgramPlayable(program, nowMs));
  return normalizeEpgSelection({
    ...state,
    windowStartMs,
    selectedChannelId: focusedChannel?.id ?? state.selectedChannelId,
    selectedProgramId: currentProgram?.id ?? state.selectedProgramId,
    tuneError: null,
  }, presentation, false);
}

export function setEpgPresentationState(
  state: EpgState,
  presentationState: EpgPresentationState,
  presentationGeneration = state.presentationGeneration,
): EpgState {
  return {
    ...state,
    presentationState,
    presentationGeneration,
    tuneError: presentationState === 'ready' ? state.tuneError : null,
  };
}

export function setEpgTuneError(state: EpgState, tuneError: string | null): EpgState {
  return state.presentationState === 'ready' ? { ...state, tuneError } : state;
}

export function selectEpgProgram(
  state: EpgState,
  channelId: string,
  programId: string,
  presentation: EpgPresentationSource,
): EpgState {
  if (state.presentationState !== 'ready') return state;
  const channel = findChannel(channelId, presentation);
  const program = channel === undefined
    ? undefined
    : visibleProgramsForChannel(channel, state.windowStartMs).find((candidate) => candidate.id === programId);
  return program === undefined ? state : {
    ...state,
    selectedChannelId: channelId,
    selectedProgramId: programId,
    tuneError: null,
  };
}

export function createEpgGuideView(
  state: EpgState,
  presentation: EpgPresentationSource,
): EpgGuideViewModel {
  const presentationForRender = normalizeEpgPresentation(presentation);
  const normalizedState = normalizeEpgSelection(state, presentation);
  const windowEndMs = normalizedState.windowStartMs + EPG_WINDOW_DURATION_MS;
  const slots = Array.from({ length: EPG_VISIBLE_SLOT_COUNT }, (_, index) => {
    const startsAtMs = normalizedState.windowStartMs + index * EPG_SLOT_DURATION_MS;
    return { startsAtMs, endsAtMs: startsAtMs + EPG_SLOT_DURATION_MS, label: formatEpgTime(startsAtMs) };
  });
  const rows = normalizedState.presentationState === 'ready'
    ? presentation.channels.map((channel) => ({
      id: channel.id,
      number: channel.number,
      name: channel.name,
      isSelected: channel.id === normalizedState.selectedChannelId,
      programs: visibleProgramsForChannel(channel, normalizedState.windowStartMs).map((program) => createProgramCell(
        program,
        channel.id,
        normalizedState,
        windowEndMs,
        presentationForRender.nowMs,
      )),
    }))
    : [];
  const selectedProgram = rows.flatMap((row) => row.programs).find((program) => program.isSelected) ?? null;

  return {
    presentationState: normalizedState.presentationState,
    presentationGeneration: normalizedState.presentationGeneration,
    tuneError: normalizedState.tuneError,
    nowMs: presentationForRender.nowMs,
    windowStartMs: normalizedState.windowStartMs,
    windowEndMs,
    slots,
    rows,
    selectedProgram,
    shell: createEpgShellView(presentation.channels, presentationForRender.nowWatching),
    infoPanel: selectedProgram === null ? null : createInfoPanelView(selectedProgram),
    state: createEpgPresentationStates()[normalizedState.presentationState],
  };
}

export function findEpgProgramCell(
  state: EpgState,
  presentation: EpgPresentationSource,
  channelId: string,
  programId: string,
): EpgProgramCellViewModel | null {
  return createEpgGuideView(state, presentation).rows
    .find((row) => row.id === channelId)?.programs
    .find((program) => program.id === programId) ?? null;
}

export function calculateProgramSpan(
  program: EpgProgramViewModel,
  windowStartMs: number,
  windowEndMs: number,
): { columnStart: number; columnSpan: number } | null {
  if (!isProgramVisible(program, windowStartMs, windowEndMs)) return null;
  const clippedStartMs = Math.max(program.startsAtMs, windowStartMs);
  const clippedEndMs = Math.min(program.endsAtMs, windowEndMs);
  const columnStart = Math.floor((clippedStartMs - windowStartMs) / EPG_SLOT_DURATION_MS) + 1;
  const columnEnd = Math.ceil((clippedEndMs - windowStartMs) / EPG_SLOT_DURATION_MS) + 1;
  return { columnStart, columnSpan: Math.max(1, columnEnd - columnStart) };
}

export function formatEpgTimeWindow(startsAtMs: number, endsAtMs: number): string {
  return `${formatEpgTime(startsAtMs)} - ${formatEpgTime(endsAtMs)}`;
}

export function formatEpgTime(valueMs: number): string {
  const date = new Date(valueMs);
  const hour24 = date.getHours();
  const hour = hour24 % 12 === 0 ? 12 : hour24 % 12;
  const minute = String(date.getMinutes()).padStart(2, '0');
  return `${hour}:${minute} ${hour24 < 12 ? 'AM' : 'PM'}`;
}

export function updateEpgState(
  state: EpgState,
  presentation: EpgPresentationSource,
  presentationGeneration = state.presentationGeneration + 1,
): EpgState {
  const initial = deriveInitialEpgSelection(presentation);
  const presentationState = classifyPresentation(presentation, initial.windowStartMs);
  if (presentationState !== 'ready') {
    return {
      windowStartMs: initial.windowStartMs,
      selectedChannelId: '',
      selectedProgramId: '',
      presentationState,
      presentationGeneration,
      tuneError: null,
    };
  }
  return normalizeEpgSelection({
    ...state,
    presentationState: 'ready',
    presentationGeneration,
    tuneError: null,
  }, presentation);
}

function createProgramCell(
  program: EpgProgramViewModel,
  channelId: string,
  state: EpgState,
  windowEndMs: number,
  nowMs: number,
): EpgProgramCellViewModel {
  const span = calculateProgramSpan(program, state.windowStartMs, windowEndMs);
  if (span === null) throw new Error(`Visible EPG program ${program.id} did not produce a span`);
  return {
    ...program,
    channelId,
    focusId: createGuideProgramFocusId(channelId, program.id),
    presentationGeneration: state.presentationGeneration,
    columnStart: span.columnStart,
    columnSpan: span.columnSpan,
    isSelected: channelId === state.selectedChannelId && program.id === state.selectedProgramId,
    temporalState: getProgramTemporalState(program, nowMs),
    progressPercent: getProgramProgressPercent(program, nowMs),
    widthTier: getProgramWidthTier(span.columnSpan),
    timeLabel: formatEpgTimeWindow(program.startsAtMs, program.endsAtMs),
  };
}

function getProgramTemporalState(program: EpgProgramViewModel, nowMs: number): EpgProgramTemporalState {
  if (program.endsAtMs <= nowMs) return 'past';
  return isEpgProgramPlayable(program, nowMs) ? 'current' : 'upcoming';
}

function getProgramProgressPercent(program: EpgProgramViewModel, nowMs: number): number {
  if (!isEpgProgramPlayable(program, nowMs)) return 0;
  return Math.round(((nowMs - program.startsAtMs) / Math.max(1, program.endsAtMs - program.startsAtMs)) * 100);
}

function getProgramWidthTier(columnSpan: number): EpgProgramWidthTier {
  return columnSpan >= 3 ? 'wide' : columnSpan === 2 ? 'medium' : 'narrow';
}

function classifyPresentation(presentation: EpgPresentationSource, windowStartMs: number): EpgPresentationState {
  if (presentation.channels.length === 0) return 'empty-channels';
  return presentation.channels.some((channel) => visibleProgramsForChannel(channel, windowStartMs).length > 0)
    ? 'ready'
    : 'empty-programs';
}

function normalizeEpgSelection(
  state: EpgState,
  presentation: EpgPresentationSource,
  clampWindow = true,
): EpgState {
  if (state.presentationState !== 'ready') return state;
  const windowStartMs = clampWindow ? clampWindowStartMs(state.windowStartMs, presentation) : state.windowStartMs;
  const selectedChannel = findChannel(state.selectedChannelId, presentation);
  const channel = selectedChannel !== undefined && visibleProgramsForChannel(selectedChannel, windowStartMs).length > 0
    ? selectedChannel
    : presentation.channels.find((candidate) => visibleProgramsForChannel(candidate, windowStartMs).length > 0);
  if (channel === undefined) {
    return { ...state, windowStartMs, selectedChannelId: '', selectedProgramId: '', presentationState: 'empty-programs' };
  }
  const visiblePrograms = visibleProgramsForChannel(channel, windowStartMs);
  const selectedProgram = visiblePrograms.find((program) => program.id === state.selectedProgramId) ?? visiblePrograms[0];
  return {
    ...state,
    windowStartMs,
    selectedChannelId: channel.id,
    selectedProgramId: selectedProgram?.id ?? '',
  };
}

function moveWindow(state: EpgState, offset: number, presentation: EpgPresentationSource): EpgState {
  return normalizeEpgSelection({
    ...state,
    windowStartMs: clampWindowStartMs(state.windowStartMs + offset * EPG_SLOT_DURATION_MS, presentation),
    tuneError: null,
  }, presentation);
}

function moveWindowIntent(state: EpgState, offset: number): EpgState {
  return {
    ...state,
    windowStartMs: state.windowStartMs + offset * EPG_SLOT_DURATION_MS,
    tuneError: null,
  };
}

function selectChannelByOffset(state: EpgState, offset: number, presentation: EpgPresentationSource): EpgState {
  return selectNearestProgramOnAdjacentChannel(state, offset, presentation);
}

function selectNearestProgramOnAdjacentChannel(
  state: EpgState,
  offset: number,
  presentation: EpgPresentationSource,
): EpgState {
  const visibleChannels = presentation.channels.filter(
    (channel) => visibleProgramsForChannel(channel, state.windowStartMs).length > 0,
  );
  const currentIndex = visibleChannels.findIndex((channel) => channel.id === state.selectedChannelId);
  const nextChannel = visibleChannels[clamp((currentIndex < 0 ? 0 : currentIndex) + offset, 0, visibleChannels.length - 1)];
  if (nextChannel === undefined) return state;
  const currentProgram = findChannel(state.selectedChannelId, presentation)?.programs.find(
    (program) => program.id === state.selectedProgramId,
  );
  const candidates = visibleProgramsForChannel(nextChannel, state.windowStartMs);
  const selected = currentProgram === undefined ? candidates[0] : [...candidates].sort((left, right) => {
    const overlapDifference = overlapMs(right, currentProgram) - overlapMs(left, currentProgram);
    if (overlapDifference !== 0) return overlapDifference;
    return centerDistanceMs(left, currentProgram) - centerDistanceMs(right, currentProgram);
  })[0];
  return selected === undefined ? state : {
    ...state,
    selectedChannelId: nextChannel.id,
    selectedProgramId: selected.id,
    tuneError: null,
  };
}

function selectProgramByOffset(state: EpgState, offset: number, presentation: EpgPresentationSource): EpgState {
  const channel = findChannel(state.selectedChannelId, presentation);
  if (channel === undefined) return state;
  const programs = visibleProgramsForChannel(channel, state.windowStartMs);
  const currentIndex = programs.findIndex((program) => program.id === state.selectedProgramId);
  const next = programs[clamp((currentIndex < 0 ? 0 : currentIndex) + offset, 0, programs.length - 1)];
  return next === undefined ? state : { ...state, selectedProgramId: next.id, tuneError: null };
}

function visibleProgramsForChannel(channel: EpgChannelViewModel, windowStartMs: number): readonly EpgProgramViewModel[] {
  const windowEndMs = windowStartMs + EPG_WINDOW_DURATION_MS;
  return channel.programs.filter((program) => isProgramVisible(program, windowStartMs, windowEndMs));
}

function isProgramVisible(program: EpgProgramViewModel, windowStartMs: number, windowEndMs: number): boolean {
  return program.startsAtMs < windowEndMs && program.endsAtMs > windowStartMs;
}

function deriveInitialEpgSelection(
  presentation: EpgPresentationSource,
): Pick<EpgState, 'windowStartMs' | 'selectedChannelId' | 'selectedProgramId'> {
  const normalized = normalizeEpgPresentation(presentation);
  const firstEntry = listPresentationPrograms(presentation)[0];
  const anchorMs = presentation.nowWatching?.startsAtMs ?? firstEntry?.program.startsAtMs ?? normalized.nowMs;
  const windowStartMs = clampWindowStartMs(snapWindowStartMs(anchorMs), presentation);
  const preferredChannel = findChannel(presentation.nowWatching?.channelId ?? '', presentation);
  const channels = preferredChannel === undefined
    ? presentation.channels
    : [preferredChannel, ...presentation.channels.filter((channel) => channel.id !== preferredChannel.id)];
  for (const channel of channels) {
    const programs = visibleProgramsForChannel(channel, windowStartMs);
    const program = programs.find((candidate) => presentation.nowWatching !== null
      && candidate.startsAtMs === presentation.nowWatching.startsAtMs
      && candidate.endsAtMs === presentation.nowWatching.endsAtMs) ?? programs[0];
    if (program !== undefined) return { windowStartMs, selectedChannelId: channel.id, selectedProgramId: program.id };
  }
  return { windowStartMs, selectedChannelId: '', selectedProgramId: '' };
}

function findChannel(channelId: string, presentation: EpgPresentationSource): EpgChannelViewModel | undefined {
  return presentation.channels.find((channel) => channel.id === channelId);
}

function listPresentationPrograms(presentation: EpgPresentationSource): readonly { channel: EpgChannelViewModel; program: EpgProgramViewModel }[] {
  return presentation.channels.flatMap((channel) => channel.programs.map((program) => ({ channel, program })));
}

function minWindowStartMs(presentation: EpgPresentationSource): number {
  const firstStartMs = listPresentationPrograms(presentation).reduce<number | null>(
    (minimum, entry) => minimum === null || entry.program.startsAtMs < minimum ? entry.program.startsAtMs : minimum,
    null,
  );
  return snapWindowStartMs(firstStartMs ?? presentation.nowMs ?? Date.now());
}

function maxWindowStartMs(presentation: EpgPresentationSource): number {
  const lastEndMs = listPresentationPrograms(presentation).reduce<number | null>(
    (maximum, entry) => maximum === null || entry.program.endsAtMs > maximum ? entry.program.endsAtMs : maximum,
    null,
  );
  const minimum = minWindowStartMs(presentation);
  return lastEndMs === null ? minimum : Math.max(minimum, snapWindowStartMs(lastEndMs - EPG_WINDOW_DURATION_MS));
}

function clampWindowStartMs(windowStartMs: number, presentation: EpgPresentationSource): number {
  return clamp(windowStartMs, minWindowStartMs(presentation), maxWindowStartMs(presentation));
}

function overlapMs(left: EpgProgramViewModel, right: EpgProgramViewModel): number {
  return Math.max(0, Math.min(left.endsAtMs, right.endsAtMs) - Math.max(left.startsAtMs, right.startsAtMs));
}

function centerDistanceMs(left: EpgProgramViewModel, right: EpgProgramViewModel): number {
  return Math.abs((left.startsAtMs + left.endsAtMs) - (right.startsAtMs + right.endsAtMs));
}

function snapWindowStartMs(valueMs: number): number {
  return Math.floor(valueMs / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS;
}

function isValidTime(value: number | undefined): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}
