import {
  createEpgPresentationStates,
  createEpgShellView,
  createInfoPanelView,
  type EpgInfoPanelViewModel,
  type EpgPresentationStateViewModel,
  type EpgShellViewModel,
} from './guidePresentation.js';
import type { ArtworkRef } from '../contracts/artwork.js';
import type { GuideLibraryFilterState } from '../contracts/guide.js';
import { GUIDE_DOM_TIME_BUFFER_MS } from './guideVirtualization.js';

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
  guideDensity: EpgGuideDensity;
  minimumStartTimeMs?: number;
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
  channelWindow: { offset: number; total: number };
  libraryFilter: GuideLibraryFilterState | null;
}

export interface EpgPresentationSource {
  channels: readonly EpgChannelViewModel[];
  nowWatching: EpgCurrentProgramViewModel | null;
  nowMs?: number;
  minimumStartTimeMs?: number;
  channelWindow?: { offset: number; total: number };
  libraryFilter?: GuideLibraryFilterState;
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

export type EpgGuideDensity = 'comfortable' | 'compact';

export const EPG_SLOT_DURATION_MS = 30 * 60 * 1000;
export const EPG_VISIBLE_SLOT_COUNT = 6;
export const EPG_WINDOW_DURATION_MS = EPG_SLOT_DURATION_MS * EPG_VISIBLE_SLOT_COUNT;
export const EPG_DETAILED_SLOT_COUNT = 4;
export const EPG_DETAILED_WINDOW_DURATION_MS = EPG_SLOT_DURATION_MS * EPG_DETAILED_SLOT_COUNT;
export const EPG_CHANNEL_PAGE_SIZE = 9;

export function getEpgVisibleSlotCount(density: EpgGuideDensity): number {
  return density === 'comfortable' ? EPG_DETAILED_SLOT_COUNT : EPG_VISIBLE_SLOT_COUNT;
}

export function getEpgWindowDurationMs(density: EpgGuideDensity): number {
  return density === 'comfortable' ? EPG_DETAILED_WINDOW_DURATION_MS : EPG_WINDOW_DURATION_MS;
}

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
  guideDensity: EpgGuideDensity = 'comfortable',
): EpgState {
  const initialSelection = deriveInitialEpgSelection(presentation, guideDensity);
  return {
    guideDensity,
    minimumStartTimeMs: isSafeNonNegativeInteger(presentation.minimumStartTimeMs) ? presentation.minimumStartTimeMs : undefined,
    ...initialSelection,
    presentationState: classifyPresentation(presentation, initialSelection.windowStartMs, guideDensity),
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
  const windowStartMs = Math.max(state.minimumStartTimeMs ?? 0, snapWindowStartMs(nowMs));
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
    : visibleProgramsForChannel(channel, state.windowStartMs, state.guideDensity).find((candidate) => candidate.id === programId);
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
  const windowEndMs = normalizedState.windowStartMs + getEpgWindowDurationMs(normalizedState.guideDensity);
  const slots = Array.from({ length: getEpgVisibleSlotCount(normalizedState.guideDensity) }, (_, index) => {
    const startsAtMs = normalizedState.windowStartMs + index * EPG_SLOT_DURATION_MS;
    return { startsAtMs, endsAtMs: startsAtMs + EPG_SLOT_DURATION_MS, label: formatEpgTime(startsAtMs) };
  });
  const rows = normalizedState.presentationState === 'ready'
    ? presentation.channels.map((channel) => ({
      id: channel.id,
      number: channel.number,
      name: channel.name,
      isSelected: channel.id === normalizedState.selectedChannelId,
      programs: renderProgramsForChannel(channel, normalizedState.windowStartMs, normalizedState.guideDensity).map((program) => createProgramCell(
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
    channelWindow: presentation.channelWindow ?? { offset: 0, total: presentation.channels.length },
    libraryFilter: presentation.libraryFilter ?? null,
  };
}

export function selectEpgPageTarget(
  state: EpgState,
  targetLocalIndex: number,
  presentation: EpgPresentationSource,
): EpgState {
  if (state.presentationState !== 'ready') return state;
  const currentIndex = presentation.channels.findIndex((channel) => channel.id === state.selectedChannelId);
  if (currentIndex < 0) return state;
  return selectNearestProgramOnAdjacentChannel(state, targetLocalIndex - currentIndex, presentation);
}

export interface EpgPageNavigationIntent {
  targetGlobalIndex: number;
  sourceLocalIndex: number;
  channelOffset: number;
  targetLocalIndex: number | null;
  fetchRequired: boolean;
  boundaryClamped: boolean;
}

export interface EpgPresentationSettlement {
  state: EpgState;
  pendingFocusId: string | null | undefined;
}

export function settleEpgPresentation(
  state: EpgState,
  presentation: EpgPresentationSource,
  generation: number,
  pagingTargetGlobalIndex: number | null | undefined,
  restoreSelectedProgramFocus: boolean,
  guideDensity: EpgGuideDensity = state.guideDensity,
  effectiveStartTimeMs?: number,
): EpgPresentationSettlement {
  const minimumStartTimeMs = isSafeNonNegativeInteger(presentation.minimumStartTimeMs)
    ? presentation.minimumStartTimeMs
    : state.minimumStartTimeMs;
  const acceptedWindowStartMs = isValidTime(effectiveStartTimeMs)
    ? Math.max(minimumStartTimeMs ?? 0, effectiveStartTimeMs)
    : undefined;
  let next = updateEpgState({
    ...state,
    minimumStartTimeMs,
    ...(acceptedWindowStartMs === undefined ? {} : { windowStartMs: acceptedWindowStartMs }),
  }, presentation, generation, guideDensity);
  if (acceptedWindowStartMs !== undefined) {
    next = { ...next, windowStartMs: acceptedWindowStartMs };
  }
  if (typeof pagingTargetGlobalIndex === 'number') {
    const window = presentation.channelWindow;
    if (window !== undefined) {
      next = selectEpgPageTarget(next, pagingTargetGlobalIndex - window.offset, presentation);
    }
  }
  const pendingFocusId = pagingTargetGlobalIndex === null
    ? null
    : typeof pagingTargetGlobalIndex === 'number' || restoreSelectedProgramFocus
      ? createEpgGuideView(next, presentation).selectedProgram?.focusId ?? null
      : undefined;
  return { state: next, pendingFocusId };
}

export function settleEpgPresentationFailure(
  state: EpgState,
  message: string,
  generation: number,
  retainLastValid: boolean,
): EpgState {
  return retainLastValid
    ? setEpgTuneError(state, message)
    : setEpgPresentationState(state, 'error', generation);
}

export function resolveEpgPageNavigation(
  state: EpgState,
  presentation: EpgPresentationSource,
  offset: -5 | 5,
  pendingTargetGlobalIndex: number | null = null,
  channelLimit = EPG_CHANNEL_PAGE_SIZE,
): EpgPageNavigationIntent | null {
  const sourceLocalIndex = presentation.channels.findIndex((channel) => channel.id === state.selectedChannelId);
  const window = presentation.channelWindow ?? { offset: 0, total: presentation.channels.length };
  if (sourceLocalIndex < 0 || window.total === 0) return null;
  const base = pendingTargetGlobalIndex ?? window.offset + sourceLocalIndex;
  const targetGlobalIndex = clamp(base + offset, 0, window.total - 1);
  const boundaryClamped = targetGlobalIndex === base;
  const pageEnd = window.offset + presentation.channels.length;
  const inside = targetGlobalIndex >= window.offset && targetGlobalIndex < pageEnd;
  const maximumOffset = Math.max(0, window.total - channelLimit);
  return {
    targetGlobalIndex,
    sourceLocalIndex,
    channelOffset: inside || boundaryClamped ? window.offset : clamp(targetGlobalIndex - sourceLocalIndex, 0, maximumOffset),
    targetLocalIndex: inside ? targetGlobalIndex - window.offset : null,
    fetchRequired: !inside && !boundaryClamped,
    boundaryClamped,
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
  guideDensity: EpgGuideDensity = state.guideDensity,
): EpgState {
  const initial = deriveInitialEpgSelection(presentation, guideDensity);
  const presentationState = classifyPresentation(presentation, initial.windowStartMs, guideDensity);
  const minimumStartTimeMs = isSafeNonNegativeInteger(presentation.minimumStartTimeMs) ? presentation.minimumStartTimeMs : state.minimumStartTimeMs;
  if (presentationState !== 'ready') {
    return {
      guideDensity,
      minimumStartTimeMs,
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
    guideDensity,
    minimumStartTimeMs,
    presentationState: 'ready',
    presentationGeneration,
    tuneError: null,
  }, presentation);
}

export function setEpgGuideDensity(
  state: EpgState,
  presentation: EpgPresentationSource,
  guideDensity: EpgGuideDensity,
): EpgState {
  if (state.guideDensity === guideDensity) return state;
  const next = { ...state, guideDensity };
  if (state.presentationState !== 'ready') return next;

  const selectedProgram = findChannel(state.selectedChannelId, presentation)?.programs.find(
    (program) => program.id === state.selectedProgramId,
  );
  const previousDurationMs = getEpgWindowDurationMs(state.guideDensity);
  const anchorMs = selectedProgram === undefined
    ? state.windowStartMs + previousDurationMs / 2
    : (selectedProgram.startsAtMs + selectedProgram.endsAtMs) / 2;
  const nextDurationMs = getEpgWindowDurationMs(guideDensity);
  const selectionRemainsVisible = selectedProgram !== undefined && isProgramVisible(
    selectedProgram,
    state.windowStartMs,
    state.windowStartMs + nextDurationMs,
  );
  const recenteredStartMs = selectionRemainsVisible
    ? state.windowStartMs
    : clampWindowStartMs(
      snapWindowStartMs(anchorMs - nextDurationMs / 2),
      withStateMinimumStart(presentation, state),
      guideDensity,
    );
  return normalizeEpgSelection({ ...next, windowStartMs: recenteredStartMs }, presentation);
}

export type EpgPastItemsWindowSetting = 'auto' | '0' | '15' | '30';
export function computeProvisionalEpgMinimumStartTimeMs(nowMs: number, setting: EpgPastItemsWindowSetting): number {
  if (!Number.isFinite(nowMs) || nowMs < 0) return 0;
  const pastMinutes = setting === 'auto' ? 15 : Number(setting);
  const slotStartMs = Math.floor((nowMs - pastMinutes * 60_000) / EPG_SLOT_DURATION_MS) * EPG_SLOT_DURATION_MS;
  const localMidnight = new Date(nowMs);
  if (!Number.isFinite(localMidnight.getTime())) return 0;
  localMidnight.setHours(0, 0, 0, 0);
  return Math.max(0, slotStartMs, localMidnight.getTime());
}
export function setEpgPastItemsWindow(
  state: EpgState,
  setting: EpgPastItemsWindowSetting,
  nowMs: number,
  presentation: EpgPresentationSource,
): EpgState {
  const minimumStartTimeMs = computeProvisionalEpgMinimumStartTimeMs(nowMs, setting);
  const next = {
    ...state,
    minimumStartTimeMs,
    windowStartMs: Math.max(minimumStartTimeMs, state.windowStartMs),
  };
  return next.presentationState === 'ready' ? normalizeEpgSelection(next, presentation) : next;
}

function createProgramCell(
  program: EpgProgramViewModel,
  channelId: string,
  state: EpgState,
  windowEndMs: number,
  nowMs: number,
): EpgProgramCellViewModel {
  const span = calculateProgramSpan(program, state.windowStartMs, windowEndMs) ?? {
    columnStart: program.endsAtMs <= state.windowStartMs ? 0 : getEpgVisibleSlotCount(state.guideDensity) + 1,
    columnSpan: 1,
  };
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

function classifyPresentation(
  presentation: EpgPresentationSource,
  windowStartMs: number,
  guideDensity: EpgGuideDensity,
): EpgPresentationState {
  if (presentation.channels.length === 0) return 'empty-channels';
  return presentation.channels.some((channel) => visibleProgramsForChannel(channel, windowStartMs, guideDensity).length > 0)
    ? 'ready'
    : 'empty-programs';
}

function normalizeEpgSelection(
  state: EpgState,
  presentation: EpgPresentationSource,
  clampWindow = true,
): EpgState {
  if (state.presentationState !== 'ready') return state;
  const windowStartMs = clampWindow
    ? clampWindowStartMs(state.windowStartMs, withStateMinimumStart(presentation, state), state.guideDensity)
    : state.windowStartMs;
  const selectedChannel = findChannel(state.selectedChannelId, presentation);
  const channel = selectedChannel !== undefined && visibleProgramsForChannel(selectedChannel, windowStartMs, state.guideDensity).length > 0
    ? selectedChannel
    : presentation.channels.find((candidate) => visibleProgramsForChannel(candidate, windowStartMs, state.guideDensity).length > 0);
  if (channel === undefined) {
    return { ...state, windowStartMs, selectedChannelId: '', selectedProgramId: '', presentationState: 'empty-programs' };
  }
  const visiblePrograms = visibleProgramsForChannel(channel, windowStartMs, state.guideDensity);
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
    windowStartMs: clampWindowStartMs(
      state.windowStartMs + offset * EPG_SLOT_DURATION_MS,
      withStateMinimumStart(presentation, state),
      state.guideDensity,
    ),
    tuneError: null,
  }, presentation);
}

function moveWindowIntent(state: EpgState, offset: number): EpgState {
  return {
    ...state,
    windowStartMs: Math.max(state.minimumStartTimeMs ?? 0, state.windowStartMs + offset * EPG_SLOT_DURATION_MS),
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
    (channel) => visibleProgramsForChannel(channel, state.windowStartMs, state.guideDensity).length > 0,
  );
  const currentIndex = visibleChannels.findIndex((channel) => channel.id === state.selectedChannelId);
  const nextChannel = visibleChannels[clamp((currentIndex < 0 ? 0 : currentIndex) + offset, 0, visibleChannels.length - 1)];
  if (nextChannel === undefined) return state;
  const currentProgram = findChannel(state.selectedChannelId, presentation)?.programs.find(
    (program) => program.id === state.selectedProgramId,
  );
  const candidates = visibleProgramsForChannel(nextChannel, state.windowStartMs, state.guideDensity);
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
  const programs = visibleProgramsForChannel(channel, state.windowStartMs, state.guideDensity);
  const currentIndex = programs.findIndex((program) => program.id === state.selectedProgramId);
  const next = programs[clamp((currentIndex < 0 ? 0 : currentIndex) + offset, 0, programs.length - 1)];
  return next === undefined ? state : { ...state, selectedProgramId: next.id, tuneError: null };
}

function visibleProgramsForChannel(
  channel: EpgChannelViewModel,
  windowStartMs: number,
  guideDensity: EpgGuideDensity,
): readonly EpgProgramViewModel[] {
  const windowEndMs = windowStartMs + getEpgWindowDurationMs(guideDensity);
  return channel.programs.filter((program) => isProgramVisible(program, windowStartMs, windowEndMs));
}

function renderProgramsForChannel(
  channel: EpgChannelViewModel,
  windowStartMs: number,
  guideDensity: EpgGuideDensity,
): readonly EpgProgramViewModel[] {
  const windowEndMs = windowStartMs + getEpgWindowDurationMs(guideDensity);
  const buffered = channel.programs.filter((program) =>
    program.startsAtMs < windowEndMs + GUIDE_DOM_TIME_BUFFER_MS &&
    program.endsAtMs > windowStartMs - GUIDE_DOM_TIME_BUFFER_MS);
  return [
    ...buffered.filter((program) => isProgramVisible(program, windowStartMs, windowEndMs)),
    ...buffered.filter((program) => !isProgramVisible(program, windowStartMs, windowEndMs)),
  ];
}

function isProgramVisible(program: EpgProgramViewModel, windowStartMs: number, windowEndMs: number): boolean {
  return program.startsAtMs < windowEndMs && program.endsAtMs > windowStartMs;
}

function deriveInitialEpgSelection(
  presentation: EpgPresentationSource,
  guideDensity: EpgGuideDensity,
): Pick<EpgState, 'windowStartMs' | 'selectedChannelId' | 'selectedProgramId'> {
  const normalized = normalizeEpgPresentation(presentation);
  const firstEntry = listPresentationPrograms(presentation)[0];
  const anchorMs = presentation.nowWatching?.startsAtMs ?? firstEntry?.program.startsAtMs ?? normalized.nowMs;
  const windowStartMs = clampWindowStartMs(snapWindowStartMs(anchorMs), presentation, guideDensity);
  const preferredChannel = findChannel(presentation.nowWatching?.channelId ?? '', presentation);
  const channels = preferredChannel === undefined
    ? presentation.channels
    : [preferredChannel, ...presentation.channels.filter((channel) => channel.id !== preferredChannel.id)];
  for (const channel of channels) {
    const programs = visibleProgramsForChannel(channel, windowStartMs, guideDensity);
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
  const derived = snapWindowStartMs(firstStartMs ?? presentation.nowMs ?? Date.now());
  return isSafeNonNegativeInteger(presentation.minimumStartTimeMs) ? presentation.minimumStartTimeMs : derived;
}

function withStateMinimumStart(
  presentation: EpgPresentationSource,
  state: EpgState,
): EpgPresentationSource {
  return state.minimumStartTimeMs === undefined
    ? presentation
    : { ...presentation, minimumStartTimeMs: state.minimumStartTimeMs };
}

function maxWindowStartMs(
  presentation: EpgPresentationSource,
  guideDensity: EpgGuideDensity,
): number {
  const lastEndMs = listPresentationPrograms(presentation).reduce<number | null>(
    (maximum, entry) => maximum === null || entry.program.endsAtMs > maximum ? entry.program.endsAtMs : maximum,
    null,
  );
  const minimum = minWindowStartMs(presentation);
  return lastEndMs === null
    ? minimum
    : Math.max(minimum, snapWindowStartMs(lastEndMs - getEpgWindowDurationMs(guideDensity)));
}

function clampWindowStartMs(
  windowStartMs: number,
  presentation: EpgPresentationSource,
  guideDensity: EpgGuideDensity,
): number {
  return clamp(
    windowStartMs,
    minWindowStartMs(presentation),
    maxWindowStartMs(presentation, guideDensity),
  );
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

function isSafeNonNegativeInteger(value: number | undefined): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}
