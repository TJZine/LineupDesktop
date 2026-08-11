import type { EpgChannelRowViewModel } from './epg.js';
import type { GuideCompleteRowInterval } from './guideRowDensity.js';

export const GUIDE_DOM_ROW_CAP = 24;
export const GUIDE_DOM_CELL_CAP = 400;
export const GUIDE_ROW_BUFFER = 2;
export const GUIDE_DOM_TIME_BUFFER_MS = 120 * 60_000;

export type GuidePerformanceProfile = 'auto' | 'reduced-resource';

export interface GuidePerformanceProfileConfig {
  /** Upper bound retained for cache/warm-page geometry; foreground sizing is viewport-derived. */
  readonly channelLimit: 24;
  readonly timeBufferMs: number;
  readonly maximumEntries: 6 | 12;
  readonly maximumPrograms: 6_000 | 12_000;
}

export const REDUCED_RESOURCE_GUIDE_PRELOAD_PROFILE: GuidePerformanceProfileConfig = Object.freeze({
  channelLimit: 24,
  timeBufferMs: 360 * 60_000,
  maximumEntries: 6,
  maximumPrograms: 6_000,
});

export const AUTO_GUIDE_PRELOAD_PROFILE: GuidePerformanceProfileConfig = Object.freeze({
  channelLimit: 24,
  timeBufferMs: 360 * 60_000,
  maximumEntries: 12,
  maximumPrograms: 12_000,
});

export interface GuideVirtualRangeInput {
  readonly rows: readonly EpgChannelRowViewModel[];
  readonly scrollTop: number;
  readonly viewportHeight: number;
  readonly rowOuterSize: number;
  readonly rowStartOffset?: number;
  readonly completeRowInterval?: GuideCompleteRowInterval;
  readonly windowStartMs: number;
  readonly windowEndMs: number;
  readonly focusedRowIndex: number;
  readonly focusedProgramId: string | null;
  readonly rowOffset?: number;
  readonly totalRowCount?: number;
}

export function projectGuideForegroundChannelLimit(completeVisibleRows: number, overscanRows = GUIDE_ROW_BUFFER): number {
  const visible = Number.isFinite(completeVisibleRows) ? Math.max(1, Math.trunc(completeVisibleRows)) : 1;
  const overscan = Number.isFinite(overscanRows) ? Math.max(0, Math.trunc(overscanRows)) : 0;
  return Math.min(GUIDE_DOM_ROW_CAP, visible + overscan * 2);
}

export interface GuideVirtualRange {
  readonly rowIndexes: readonly number[];
  readonly rowPlacements: readonly { readonly rowIndex: number; readonly gapBefore: number }[];
  readonly programIds: ReadonlySet<string>;
  readonly leadingRows: number;
  readonly trailingRows: number;
}

/** Pure Desktop Guide row/cell projection. Layout values are sampled by the DOM lifecycle owner. */
export function projectGuideVirtualRange(input: GuideVirtualRangeInput): GuideVirtualRange {
  const rowOffset = Math.max(0, Math.trunc(input.rowOffset ?? 0));
  const rowCount = Math.max(input.rows.length, Math.trunc(input.totalRowCount ?? input.rows.length));
  if (rowCount === 0) {
    return { rowIndexes: [], rowPlacements: [], programIds: new Set(), leadingRows: 0, trailingRows: 0 };
  }
  const rowOuterSize = positiveFinite(input.rowOuterSize, 1);
  const scrollTop = Math.max(0, finite(input.scrollTop, 0) - Math.max(0, finite(input.rowStartOffset ?? 0, 0)));
  const viewportHeight = Math.max(1, finite(input.viewportHeight, rowOuterSize));
  const firstVisible = clamp(Math.floor(scrollTop / rowOuterSize), 0, rowCount - 1);
  const lastVisible = clamp(Math.ceil((scrollTop + viewportHeight) / rowOuterSize) - 1, firstVisible, rowCount - 1);
  const intervalStart = input.completeRowInterval === undefined
    ? firstVisible
    : clamp(Math.trunc(input.completeRowInterval.start), 0, rowCount - 1);
  const intervalCount = input.completeRowInterval === undefined
    ? lastVisible - firstVisible + 1
    : Math.max(0, Math.trunc(input.completeRowInterval.count));
  const intervalEnd = intervalCount === 0
    ? intervalStart
    : clamp(intervalStart + intervalCount - 1, intervalStart, rowCount - 1);
  // Keep the original viewport/overscan projection so spacer geometry remains
  // stable; the complete interval is applied by the DOM owner as the
  // presentation boundary for mounted rows.
  const projectionStart = firstVisible;
  const projectionEnd = lastVisible;
  const visibleCount = projectionEnd - projectionStart + 1;
  const visibleRowsClamped = visibleCount > GUIDE_DOM_ROW_CAP;
  const clampedVisibleStart = visibleRowsClamped
    ? clamp(
      input.focusedRowIndex >= projectionStart && input.focusedRowIndex <= projectionEnd
        ? input.focusedRowIndex - Math.floor(GUIDE_DOM_ROW_CAP / 2)
        : projectionStart,
      projectionStart,
      projectionEnd - GUIDE_DOM_ROW_CAP + 1,
    )
    : projectionStart;
  const clampedVisibleEnd = visibleRowsClamped
    ? clampedVisibleStart + GUIDE_DOM_ROW_CAP - 1
    : projectionEnd;
  const candidates = new Set<number>();
  for (let index = Math.max(0, clampedVisibleStart - GUIDE_ROW_BUFFER);
    index <= Math.min(rowCount - 1, clampedVisibleEnd + GUIDE_ROW_BUFFER); index += 1) candidates.add(index);

  const protectedRows = new Set<number>();
  const protectedStart = visibleRowsClamped
    ? clampedVisibleStart
    : intervalCount > 0 ? intervalStart : 1;
  const protectedEnd = visibleRowsClamped
    ? clampedVisibleEnd
    : intervalCount > 0 ? intervalEnd : 0;
  for (let index = protectedStart; index <= protectedEnd; index += 1) protectedRows.add(index);
  if (!visibleRowsClamped && input.focusedRowIndex >= 0 && input.focusedRowIndex < rowCount && protectedRows.size < GUIDE_DOM_ROW_CAP) {
    candidates.add(input.focusedRowIndex);
    protectedRows.add(input.focusedRowIndex);
  }
  const availableIndexes = new Set(input.rows.map((row, localIndex) => row.absoluteIndex ?? rowOffset + localIndex));
  const rowIndexes = [...candidates].filter((index) => availableIndexes.has(index));
  while (rowIndexes.length > GUIDE_DOM_ROW_CAP) {
    const evictable = rowIndexes.filter((index) => !protectedRows.has(index));
    const source = evictable;
    if (source.length === 0) break;
    const remove = source.sort((left, right) => rowDistance(right, projectionStart, projectionEnd) - rowDistance(left, projectionStart, projectionEnd))[0];
    if (remove === undefined) throw new RangeError('Guide row eviction could not satisfy the mounted row cap.');
    rowIndexes.splice(rowIndexes.indexOf(remove), 1);
  }
  rowIndexes.sort((left, right) => left - right);

  const cells = rowIndexes.flatMap((rowIndex) => (input.rows.find(
    (row, localIndex) => (row.absoluteIndex ?? rowOffset + localIndex) === rowIndex,
  )?.programs ?? [])
    .filter((program) => program.startsAtMs < input.windowEndMs + GUIDE_DOM_TIME_BUFFER_MS
      && program.endsAtMs > input.windowStartMs - GUIDE_DOM_TIME_BUFFER_MS)
    .map((program) => ({
      id: program.id,
      focused: rowIndex === input.focusedRowIndex && program.id === input.focusedProgramId,
      visible: program.startsAtMs < input.windowEndMs && program.endsAtMs > input.windowStartMs,
      distance: timeDistance(program.startsAtMs, program.endsAtMs, input.windowStartMs, input.windowEndMs),
    })));
  cells.sort((left, right) => Number(right.focused) - Number(left.focused)
    || Number(right.visible) - Number(left.visible)
    || left.distance - right.distance
    || left.id.localeCompare(right.id));
  const programIds = new Set(cells.slice(0, GUIDE_DOM_CELL_CAP).map((cell) => cell.id));
  const rowPlacements = rowIndexes.map((rowIndex, index) => ({
    rowIndex,
    gapBefore: rowIndex - (index === 0 ? 0 : (rowIndexes[index - 1] ?? rowIndex) + 1),
  }));
  return {
    rowIndexes,
    rowPlacements,
    programIds,
    leadingRows: rowIndexes[0] ?? 0,
    trailingRows: rowCount - 1 - (rowIndexes[rowIndexes.length - 1] ?? rowCount - 1),
  };
}

export interface GuideCacheEntry<T> {
  readonly key: string;
  readonly value: T;
  /** Epoch timestamp captured when the entry's response was accepted. */
  readonly fetchedAtMs: number;
  readonly programCount: number;
  readonly focused: boolean;
  readonly current: boolean;
}

export interface GuideCacheFreshness {
  readonly nowMs: number;
  readonly maxAgeMs: number;
}

export class GuidePresentationLru<T> {
  readonly #entries = new Map<string, GuideCacheEntry<T>>();
  #programCount = 0;

  constructor(private readonly profile: GuidePerformanceProfileConfig) {}

  get(
    key: string,
    protection: Readonly<{ focused: boolean; current: boolean }> = { focused: false, current: false },
    freshness?: GuideCacheFreshness,
  ): T | null {
    const entry = this.#entries.get(key);
    if (entry === undefined) return null;
    if (freshness !== undefined && freshness.nowMs - entry.fetchedAtMs >= freshness.maxAgeMs) {
      this.#delete(key);
      return null;
    }
    this.set({
      ...entry,
      focused: entry.focused || protection.focused,
      current: entry.current || protection.current,
    });
    return entry.value;
  }

  set(entry: GuideCacheEntry<T>): void {
    if (entry.focused || entry.current) {
      for (const [key, value] of this.#entries) {
        if ((entry.focused && value.focused) || (entry.current && value.current)) {
          this.#entries.set(key, {
            ...value,
            focused: entry.focused ? false : value.focused,
            current: entry.current ? false : value.current,
          });
        }
      }
    }
    const previous = this.#entries.get(entry.key);
    if (previous !== undefined) this.#programCount -= previous.programCount;
    this.#entries.delete(entry.key);
    this.#entries.set(entry.key, entry);
    this.#programCount += entry.programCount;
    this.#evict();
  }

  clear(): void {
    this.#entries.clear();
    this.#programCount = 0;
  }

  #delete(key: string): void {
    const entry = this.#entries.get(key);
    if (entry === undefined) return;
    this.#entries.delete(key);
    this.#programCount -= entry.programCount;
  }

  #evict(): void {
    while (this.#entries.size > this.profile.maximumEntries || this.#programCount > this.profile.maximumPrograms) {
      const candidates = [...this.#entries.values()].filter((entry) => !entry.focused && !entry.current);
      const victim = candidates[0];
      if (victim === undefined) {
        const newest = [...this.#entries.values()].at(-1);
        if (newest === undefined) break;
        this.#delete(newest.key);
        continue;
      }
      this.#delete(victim.key);
    }
  }
}

export function guideCacheKey(startTimeMs: number, durationMs: number, channelOffset: number, channelLimit: number): string {
  return `${String(startTimeMs)}:${String(durationMs)}:${String(channelOffset)}:${String(channelLimit)}`;
}

export function projectGuideCacheIdentity(input: Readonly<{
  scopeToken: string;
  revision: number;
  selectedLibraryId: string | null;
  pastItemsWindow: string;
  guideTimeRange: string;
  guidePerformanceProfile: string;
}>): string {
  return JSON.stringify([
    input.scopeToken,
    input.revision,
    input.selectedLibraryId,
    input.pastItemsWindow,
    input.guideTimeRange,
    input.guidePerformanceProfile,
  ]);
}

function rowDistance(index: number, first: number, last: number): number {
  return index < first ? first - index : index > last ? index - last : 0;
}

function timeDistance(start: number, end: number, windowStart: number, windowEnd: number): number {
  if (start < windowEnd && end > windowStart) return 0;
  return end <= windowStart ? windowStart - end : start - windowEnd;
}

function finite(value: number, fallback: number): number { return Number.isFinite(value) ? value : fallback; }
function positiveFinite(value: number, fallback: number): number { return Number.isFinite(value) && value > 0 ? value : fallback; }
function clamp(value: number, minimum: number, maximum: number): number { return Math.min(maximum, Math.max(minimum, value)); }
