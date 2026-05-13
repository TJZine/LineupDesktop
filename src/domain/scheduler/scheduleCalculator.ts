import { SCHEDULER_ERROR_MESSAGES } from './constants.js';
import type { IShuffleGenerator } from './interfaces.js';
import { applyPlaybackOrdering } from './shared/playbackOrdering.js';
import type {
  ResolvedContentItem,
  ScheduleConfig,
  ScheduledProgram,
  ScheduleIndex,
  SchedulerPlaybackMode,
} from './types.js';

function assertNeverPlaybackMode(mode: never): never {
  throw new Error(`Unknown scheduler playback mode: ${String(mode)}`);
}

export function buildScheduleIndex(
  config: ScheduleConfig,
  shuffler: IShuffleGenerator,
  generatedAt = config.anchorTime,
): ScheduleIndex {
  if (config.content.length === 0) {
    throw new Error(SCHEDULER_ERROR_MESSAGES.EMPTY_CHANNEL);
  }

  const orderedItems = applyPlaybackMode(
    config.content,
    config.playbackMode,
    config.shuffleSeed,
    shuffler,
    config.blockSize,
  );

  const itemStartOffsets: number[] = [];
  let cumulativeOffset = 0;

  for (const item of orderedItems) {
    if (!isValidItemDuration(item.durationMs)) {
      throw new Error(SCHEDULER_ERROR_MESSAGES.INVALID_ITEM_DURATION);
    }
    itemStartOffsets.push(cumulativeOffset);
    cumulativeOffset += item.durationMs;
  }

  if (cumulativeOffset === 0) {
    throw new Error(SCHEDULER_ERROR_MESSAGES.INVALID_SCHEDULE_DURATION);
  }

  return {
    channelId: config.channelId,
    generatedAt,
    totalLoopDurationMs: cumulativeOffset,
    itemStartOffsets,
    orderedItems,
  };
}

/**
 * Program lookup is deterministic from anchor time, cumulative item offsets,
 * and modular loop position, including wraparound before the anchor.
 */
function isValidItemDuration(value: number): boolean {
  return Number.isFinite(value) && Number.isInteger(value) && value > 0;
}

export function binarySearchForItem(positionInLoop: number, itemStartOffsets: number[]): number {
  let low = 0;
  let high = itemStartOffsets.length - 1;

  while (low < high) {
    const mid = Math.ceil((low + high + 1) / 2);
    const midOffset = itemStartOffsets[mid];
    if (midOffset !== undefined && midOffset <= positionInLoop) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }

  return low;
}

export function calculateProgramAtTime(
  queryTime: number,
  index: ScheduleIndex,
  anchorTime: number,
  currentTime = queryTime,
): ScheduledProgram {
  const { totalLoopDurationMs, itemStartOffsets, orderedItems } = index;
  const elapsedSinceAnchor = queryTime - anchorTime;
  const loopNumber = Math.floor(elapsedSinceAnchor / totalLoopDurationMs);
  const positionInLoop =
    ((elapsedSinceAnchor % totalLoopDurationMs) + totalLoopDurationMs) % totalLoopDurationMs;
  const itemIndex = binarySearchForItem(positionInLoop, itemStartOffsets);
  const itemStartOffset = itemStartOffsets[itemIndex] ?? 0;
  const offsetInItem = positionInLoop - itemStartOffset;

  const item = orderedItems[itemIndex];
  if (!item) {
    throw new Error('Item not found at index ' + String(itemIndex));
  }

  const loopStartTime = anchorTime + loopNumber * totalLoopDurationMs;
  const absoluteStart = loopStartTime + itemStartOffset;
  const absoluteEnd = absoluteStart + item.durationMs;

  return {
    item,
    scheduledStartTime: absoluteStart,
    scheduledEndTime: absoluteEnd,
    elapsedMs: offsetInItem,
    remainingMs: item.durationMs - offsetInItem,
    scheduleIndex: itemIndex,
    loopNumber,
    streamDescriptor: null,
    isCurrent: currentTime >= absoluteStart && currentTime < absoluteEnd,
  };
}

export function calculateNextProgram(
  currentProgram: ScheduledProgram,
  index: ScheduleIndex,
  anchorTime: number,
  currentTime = currentProgram.scheduledStartTime + currentProgram.elapsedMs,
): ScheduledProgram {
  return calculateProgramAtTime(currentProgram.scheduledEndTime, index, anchorTime, currentTime);
}

export function calculatePreviousProgram(
  currentProgram: ScheduledProgram,
  index: ScheduleIndex,
  anchorTime: number,
  currentTime = currentProgram.scheduledStartTime + currentProgram.elapsedMs,
): ScheduledProgram {
  const previousIndex =
    currentProgram.scheduleIndex > 0 ? currentProgram.scheduleIndex - 1 : index.orderedItems.length - 1;
  const previousItem = index.orderedItems[previousIndex];
  if (!previousItem) {
    throw new Error('Item not found at index ' + String(previousIndex));
  }
  return calculateProgramAtTime(
    currentProgram.scheduledStartTime - previousItem.durationMs,
    index,
    anchorTime,
    currentTime,
  );
}

export function applyPlaybackMode(
  items: ResolvedContentItem[],
  mode: SchedulerPlaybackMode,
  seed: number,
  shuffler: IShuffleGenerator,
  blockSize?: number,
): ResolvedContentItem[] {
  switch (mode) {
    case 'sequential':
    case 'shuffle':
    case 'block':
      return applyPlaybackOrdering({
        items,
        mode,
        seed,
        blockSize,
        shuffleItems: (values, seedValue) => shuffler.shuffle(values, seedValue),
      });
    default:
      return assertNeverPlaybackMode(mode);
  }
}

const MAX_WINDOW_PROGRAMS = 1000;

export function generateScheduleWindow(
  startTime: number,
  endTime: number,
  index: ScheduleIndex,
  anchorTime: number,
  output?: ScheduledProgram[],
  currentTime = startTime,
): ScheduledProgram[] {
  const programs = output ?? [];
  programs.length = 0;

  if (endTime <= startTime) {
    return programs;
  }

  let currentProgram = calculateProgramAtTime(startTime, index, anchorTime, currentTime);
  programs.push(currentProgram);

  while (currentProgram.scheduledEndTime < endTime && programs.length < MAX_WINDOW_PROGRAMS) {
    currentProgram = calculateNextProgram(currentProgram, index, anchorTime, currentTime);
    programs.push(currentProgram);
  }

  return programs;
}
