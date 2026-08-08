import type { EpgChannelRowViewModel } from './epg.js';

export const GUIDE_DOM_ROW_CAP = 24;
export const GUIDE_DOM_CELL_CAP = 400;
export const GUIDE_ROW_BUFFER = 3;
export const GUIDE_DOM_TIME_BUFFER_MS = 120 * 60_000;

export interface GuidePreloadProfile {
  readonly channelLimit: 12 | 24;
  readonly timeBufferMs: number;
  readonly maximumEntries: 6 | 12;
  readonly maximumPrograms: 6_000 | 12_000;
}

export const DEFAULT_GUIDE_PRELOAD_PROFILE: GuidePreloadProfile = Object.freeze({
  channelLimit: 12,
  timeBufferMs: 120 * 60_000,
  maximumEntries: 6,
  maximumPrograms: 6_000,
});

export const AGGRESSIVE_GUIDE_PRELOAD_PROFILE: GuidePreloadProfile = Object.freeze({
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
  readonly windowStartMs: number;
  readonly windowEndMs: number;
  readonly focusedRowIndex: number;
  readonly focusedProgramId: string | null;
}

export interface GuideVirtualRange {
  readonly rowIndexes: readonly number[];
  readonly rowPlacements: readonly { readonly rowIndex: number; readonly gapBefore: number }[];
  readonly programIds: ReadonlySet<string>;
  readonly leadingRows: number;
  readonly trailingRows: number;
  readonly visibleRowsClamped: boolean;
}

/** Pure Desktop Guide row/cell projection. Layout values are sampled by the DOM lifecycle owner. */
export function projectGuideVirtualRange(input: GuideVirtualRangeInput): GuideVirtualRange {
  const rowCount = input.rows.length;
  if (rowCount === 0) {
    return { rowIndexes: [], rowPlacements: [], programIds: new Set(), leadingRows: 0, trailingRows: 0, visibleRowsClamped: false };
  }
  const rowOuterSize = positiveFinite(input.rowOuterSize, 1);
  const scrollTop = Math.max(0, finite(input.scrollTop, 0) - Math.max(0, finite(input.rowStartOffset ?? 0, 0)));
  const viewportHeight = Math.max(1, finite(input.viewportHeight, rowOuterSize));
  const firstVisible = clamp(Math.floor(scrollTop / rowOuterSize), 0, rowCount - 1);
  const lastVisible = clamp(Math.ceil((scrollTop + viewportHeight) / rowOuterSize) - 1, firstVisible, rowCount - 1);
  const visibleCount = lastVisible - firstVisible + 1;
  const visibleRowsClamped = visibleCount > GUIDE_DOM_ROW_CAP;
  const clampedVisibleStart = visibleRowsClamped
    ? clamp(
      input.focusedRowIndex >= firstVisible && input.focusedRowIndex <= lastVisible
        ? input.focusedRowIndex - Math.floor(GUIDE_DOM_ROW_CAP / 2)
        : firstVisible,
      firstVisible,
      lastVisible - GUIDE_DOM_ROW_CAP + 1,
    )
    : firstVisible;
  const clampedVisibleEnd = visibleRowsClamped ? clampedVisibleStart + GUIDE_DOM_ROW_CAP - 1 : lastVisible;
  const candidates = new Set<number>();
  for (let index = Math.max(0, clampedVisibleStart - GUIDE_ROW_BUFFER);
    index <= Math.min(rowCount - 1, clampedVisibleEnd + GUIDE_ROW_BUFFER); index += 1) candidates.add(index);

  const protectedRows = new Set<number>();
  for (let index = clampedVisibleStart; index <= clampedVisibleEnd; index += 1) protectedRows.add(index);
  if (!visibleRowsClamped && input.focusedRowIndex >= 0 && input.focusedRowIndex < rowCount && protectedRows.size < GUIDE_DOM_ROW_CAP) {
    candidates.add(input.focusedRowIndex);
    protectedRows.add(input.focusedRowIndex);
  }
  const rowIndexes = [...candidates];
  while (rowIndexes.length > GUIDE_DOM_ROW_CAP) {
    const evictable = rowIndexes.filter((index) => !protectedRows.has(index));
    const source = evictable;
    if (source.length === 0) break;
    const remove = source.sort((left, right) => rowDistance(right, firstVisible, lastVisible) - rowDistance(left, firstVisible, lastVisible))[0];
    if (remove === undefined) throw new RangeError('Guide row eviction could not satisfy the mounted row cap.');
    rowIndexes.splice(rowIndexes.indexOf(remove), 1);
  }
  rowIndexes.sort((left, right) => left - right);

  const cells = rowIndexes.flatMap((rowIndex) => (input.rows[rowIndex]?.programs ?? [])
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
    visibleRowsClamped,
  };
}

export interface GuideCacheEntry<T> {
  readonly key: string;
  readonly value: T;
  readonly programCount: number;
  readonly focused: boolean;
  readonly current: boolean;
}

export class GuidePresentationLru<T> {
  readonly #entries = new Map<string, GuideCacheEntry<T>>();
  #programCount = 0;

  constructor(private readonly profile: GuidePreloadProfile) {}

  get size(): number { return this.#entries.size; }
  get programCount(): number { return this.#programCount; }

  get(key: string, protection: Readonly<{ focused: boolean; current: boolean }> = { focused: false, current: false }): T | null {
    const entry = this.#entries.get(key);
    if (entry === undefined) return null;
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

  #evict(): void {
    while (this.#entries.size > this.profile.maximumEntries || this.#programCount > this.profile.maximumPrograms) {
      const candidates = [...this.#entries.values()].filter((entry) => !entry.focused && !entry.current);
      const victim = candidates[0];
      if (victim === undefined) {
        const newest = [...this.#entries.values()].at(-1);
        if (newest === undefined) break;
        this.#entries.delete(newest.key);
        this.#programCount -= newest.programCount;
        continue;
      }
      this.#entries.delete(victim.key);
      this.#programCount -= victim.programCount;
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
  guideDensity: string;
  aggressivePreload: boolean;
}>): string {
  return JSON.stringify([
    input.scopeToken,
    input.revision,
    input.selectedLibraryId,
    input.pastItemsWindow,
    input.guideDensity,
    input.aggressivePreload,
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
