import type {
  EpgChannelViewModel,
  EpgCurrentProgramViewModel,
  NormalizedEpgPresentationSource,
} from './epg.js';
import type { GuideLibraryFilterState } from '../contracts/guide.js';
import { GUIDE_ROW_BUFFER, type GuidePerformanceProfile } from './guideVirtualization.js';

export const GUIDE_CHANNEL_WINDOW_OVERSCAN = GUIDE_ROW_BUFFER;

export type GuideChannelWindowRow =
  | Readonly<{ state: 'ready'; absoluteIndex: number; channel: EpgChannelViewModel }>
  | Readonly<{ state: 'loading'; absoluteIndex: number }>
  | Readonly<{ state: 'error'; absoluteIndex: number }>;

export interface GuideChannelWindowIntent {
  readonly identity: string;
  readonly epoch: number;
  readonly generation: number;
  readonly channelOffset: number;
  readonly channelLimit: number;
}

export interface GuideChannelWindowProjection {
  readonly rows: readonly GuideChannelWindowRow[];
  readonly offset: number;
  readonly total: number;
  readonly completeVisibleRowCount: number;
  readonly request: GuideChannelWindowIntent | null;
}

interface StoredPage {
  readonly key: string;
  readonly start: number;
  readonly end: number;
  used: number;
}

export class GuideChannelWindow {
  #identity = '';
  #epoch = 0;
  #total = 0;
  #generation = 0;
  #visibleStart = 0;
  #visibleCount = 1;
  #focusedIndex: number | null = null;
  #profile: GuidePerformanceProfile = 'auto';
  #clock = 0;
  readonly #rows = new Map<number, EpgChannelViewModel>();
  readonly #errors = new Set<number>();
  readonly #errorRanges = new Map<number, Readonly<{ start: number; end: number }>>();
  readonly #loading = new Set<number>();
  readonly #requestGeneration = new Map<number, number>();
  readonly #pages = new Map<string, StoredPage>();
  #metadata: Readonly<{
    nowWatching: EpgCurrentProgramViewModel | null;
    nowMs: number;
    minimumStartTimeMs?: number;
    libraryFilter?: GuideLibraryFilterState;
  }> = { nowWatching: null, nowMs: 0 };

  reset(identity: string, profile: GuidePerformanceProfile = this.#profile): void {
    if (identity === this.#identity && profile === this.#profile) return;
    this.#identity = identity;
    this.#profile = profile;
    this.#epoch += 1;
    this.#total = 0;
    this.#generation = 0;
    this.#visibleStart = 0;
    this.#focusedIndex = null;
    this.#rows.clear();
    this.#errors.clear();
    this.#errorRanges.clear();
    this.#loading.clear();
    this.#requestGeneration.clear();
    this.#pages.clear();
    this.#metadata = { nowWatching: null, nowMs: 0 };
  }

  clear(): void {
    this.reset(`${this.#identity}:${String(this.#epoch + 1)}`, this.#profile);
  }

  setProfile(profile: GuidePerformanceProfile): void {
    if (profile === this.#profile) return;
    this.#profile = profile;
    this.#evict();
  }

  setVisible(start: number, completeVisibleRowCount: number, focusedIndex: number | null = this.#focusedIndex): void {
    this.#visibleCount = clampInteger(completeVisibleRowCount, 1, 24);
    const maximumStart = Math.max(0, this.#total - this.#visibleCount);
    this.#visibleStart = clampInteger(start, 0, maximumStart);
    this.#focusedIndex = focusedIndex === null || this.#total === 0
      ? null
      : clampInteger(focusedIndex, 0, this.#total - 1);
    this.#touchVisiblePages();
  }

  beginForeground(generation: number): GuideChannelWindowIntent | null {
    if (this.#total === 0 && this.#rows.size === 0) {
      return this.#intent(generation, this.#visibleStart, this.#foregroundLimit());
    }
    const { start, end } = this.#projectionBounds();
    let firstMissing: number | null = null;
    for (let index = start; index < end; index += 1) {
      if (this.#rows.has(index) || this.#loading.has(index) || this.#errors.has(index)) continue;
      firstMissing = index;
      break;
    }
    if (firstMissing === null) return null;
    const limit = Math.min(this.#foregroundLimit(), this.#total - firstMissing);
    return this.#intent(generation, firstMissing, limit);
  }

  createIntent(generation: number, channelOffset: number, channelLimit: number): GuideChannelWindowIntent {
    return this.#intent(generation, channelOffset, channelLimit);
  }

  markLoading(intent: GuideChannelWindowIntent): boolean {
    if (!this.#isCurrent(intent)) return false;
    const end = this.#total === 0
      ? intent.channelOffset + intent.channelLimit
      : Math.min(this.#total, intent.channelOffset + intent.channelLimit);
    for (let index = intent.channelOffset; index < end; index += 1) {
      if (!this.#rows.has(index)) {
        this.#loading.add(index);
        this.#requestGeneration.set(index, intent.generation);
        this.#errors.delete(index);
        this.#errorRanges.delete(index);
      }
    }
    return true;
  }

  merge(intent: GuideChannelWindowIntent, presentation: NormalizedEpgPresentationSource): boolean {
    const window = presentation.channelWindow;
    if (!this.#isCurrent(intent) || !this.#isLatestRange(intent) || window === undefined || window.offset !== intent.channelOffset ||
      window.total < 0 || presentation.channels.length > intent.channelLimit ||
      window.offset + presentation.channels.length > window.total) return false;
    if (this.#total !== 0 && window.total !== this.#total) {
      this.#rows.clear();
      this.#errors.clear();
      this.#errorRanges.clear();
      this.#loading.clear();
      this.#requestGeneration.clear();
      this.#pages.clear();
    }
    this.#total = window.total;
    this.#generation = Math.max(this.#generation, intent.generation);
    this.#metadata = {
      nowWatching: presentation.nowWatching,
      nowMs: presentation.nowMs,
      ...(presentation.minimumStartTimeMs === undefined ? {} : { minimumStartTimeMs: presentation.minimumStartTimeMs }),
      ...(presentation.libraryFilter === undefined ? {} : { libraryFilter: presentation.libraryFilter }),
    };
    const pageEnd = window.offset + presentation.channels.length;
    for (let index = intent.channelOffset; index < Math.min(this.#total, intent.channelOffset + intent.channelLimit); index += 1) {
      this.#loading.delete(index);
      this.#requestGeneration.delete(index);
      this.#errors.delete(index);
      this.#errorRanges.delete(index);
      if (index >= pageEnd) this.#rows.delete(index);
    }
    presentation.channels.forEach((channel, localIndex) => {
      this.#rows.set(window.offset + localIndex, channel);
    });
    const key = `${String(window.offset)}:${String(presentation.channels.length)}`;
    this.#pages.delete(key);
    this.#pages.set(key, { key, start: window.offset, end: pageEnd, used: ++this.#clock });
    this.#visibleStart = clampInteger(this.#visibleStart, 0, Math.max(0, this.#total - this.#visibleCount));
    this.#evict();
    return true;
  }

  fail(intent: GuideChannelWindowIntent): boolean {
    if (!this.#isCurrent(intent) || !this.#isLatestRange(intent)) return false;
    const end = this.#total === 0
      ? intent.channelOffset + intent.channelLimit
      : Math.min(this.#total, intent.channelOffset + intent.channelLimit);
    const range = Object.freeze({ start: intent.channelOffset, end });
    for (let index = intent.channelOffset; index < end; index += 1) {
      this.#loading.delete(index);
      this.#requestGeneration.delete(index);
      if (!this.#rows.has(index)) {
        this.#errors.add(index);
        this.#errorRanges.set(index, range);
      }
    }
    return true;
  }

  release(intent: GuideChannelWindowIntent): boolean {
    if (!this.#isCurrent(intent)) return false;
    let released = false;
    const end = this.#total === 0
      ? intent.channelOffset + intent.channelLimit
      : Math.min(this.#total, intent.channelOffset + intent.channelLimit);
    for (let index = intent.channelOffset; index < end; index += 1) {
      if (this.#requestGeneration.get(index) !== intent.generation) continue;
      this.#requestGeneration.delete(index);
      this.#loading.delete(index);
      released = true;
    }
    return released;
  }

  retryVisible(generation: number): GuideChannelWindowIntent | null {
    const { start, end } = this.#projectionBounds();
    let cleared = false;
    for (let index = start; index < end; index += 1) {
      if (this.#errors.delete(index)) cleared = true;
      this.#errorRanges.delete(index);
    }
    return cleared ? this.beginForeground(generation) : null;
  }

  retryAt(absoluteIndex: number, generation: number): GuideChannelWindowIntent | null {
    const range = this.#errorRanges.get(absoluteIndex);
    if (range === undefined) return null;
    for (let index = range.start; index < range.end; index += 1) {
      const candidate = this.#errorRanges.get(index);
      if (candidate?.start !== range.start || candidate.end !== range.end) continue;
      this.#errors.delete(index);
      this.#errorRanges.delete(index);
    }
    return this.#intent(generation, range.start, range.end - range.start);
  }

  project(nextGeneration = this.#generation + 1): GuideChannelWindowProjection {
    const { start, end } = this.#projectionBounds();
    const indexes = Array.from({ length: end - start }, (_, offset) => start + offset);
    const focusedIndex = this.#focusedIndex;
    if (focusedIndex !== null && this.#rows.has(focusedIndex) && !indexes.includes(focusedIndex)) {
      if (indexes.length >= 24) {
        const visibleEnd = this.#visibleStart + this.#visibleCount;
        const overscanVictim = indexes
          .filter((index) => index < this.#visibleStart || index >= visibleEnd)
          .sort((left, right) => Math.abs(right - focusedIndex) - Math.abs(left - focusedIndex))[0];
        if (overscanVictim !== undefined) indexes.splice(indexes.indexOf(overscanVictim), 1);
      }
      if (indexes.length < 24) {
        indexes.push(focusedIndex);
        indexes.sort((left, right) => left - right);
      }
    }
    const rows: GuideChannelWindowRow[] = [];
    for (const index of indexes) {
      const channel = this.#rows.get(index);
      rows.push(channel === undefined
        ? { state: this.#errors.has(index) ? 'error' : 'loading', absoluteIndex: index }
        : { state: 'ready', absoluteIndex: index, channel });
    }
    return {
      rows,
      offset: start,
      total: this.#total,
      completeVisibleRowCount: this.#visibleCount,
      request: this.beginForeground(nextGeneration),
    };
  }

  presentation(): NormalizedEpgPresentationSource & { readonly sparseChannelRows: readonly GuideChannelWindowRow[] } {
    const projection = this.project();
    return {
      channels: projection.rows.flatMap((row) => row.state === 'ready' ? [row.channel] : []),
      sparseChannelRows: projection.rows,
      nowWatching: this.#metadata.nowWatching,
      nowMs: this.#metadata.nowMs,
      ...(this.#metadata.minimumStartTimeMs === undefined ? {} : { minimumStartTimeMs: this.#metadata.minimumStartTimeMs }),
      channelWindow: { offset: projection.offset, total: projection.total },
      ...(this.#metadata.libraryFilter === undefined ? {} : { libraryFilter: this.#metadata.libraryFilter }),
    };
  }

  absoluteIndexForChannel(channelId: string): number | null {
    for (const [index, channel] of this.#rows) if (channel.id === channelId) return index;
    return null;
  }

  get visibleStart(): number { return this.#visibleStart; }
  get completeVisibleRowCount(): number { return this.#visibleCount; }
  get total(): number { return this.#total; }
  get identity(): string { return this.#identity; }
  get epoch(): number { return this.#epoch; }

  #intent(generation: number, channelOffset: number, channelLimit: number): GuideChannelWindowIntent {
    return {
      identity: this.#identity,
      epoch: this.#epoch,
      generation,
      channelOffset,
      channelLimit: clampInteger(channelLimit, 1, 24),
    };
  }

  #isCurrent(intent: GuideChannelWindowIntent): boolean {
    return intent.identity === this.#identity && intent.epoch === this.#epoch;
  }

  #isLatestRange(intent: GuideChannelWindowIntent): boolean {
    const end = this.#total === 0
      ? intent.channelOffset + intent.channelLimit
      : Math.min(this.#total, intent.channelOffset + intent.channelLimit);
    for (let index = intent.channelOffset; index < end; index += 1) {
      const generation = this.#requestGeneration.get(index);
      if (generation !== undefined && generation !== intent.generation) return false;
    }
    return true;
  }

  #foregroundLimit(): number {
    return Math.min(24, this.#visibleCount + GUIDE_CHANNEL_WINDOW_OVERSCAN * 2);
  }

  #projectionBounds(): { start: number; end: number } {
    if (this.#total === 0) return { start: 0, end: 0 };
    const visibleEnd = Math.min(this.#total, this.#visibleStart + this.#visibleCount);
    const availableOverscan = Math.max(0, 24 - (visibleEnd - this.#visibleStart));
    const leading = Math.min(GUIDE_CHANNEL_WINDOW_OVERSCAN, this.#visibleStart, Math.floor(availableOverscan / 2));
    const trailing = Math.min(
      GUIDE_CHANNEL_WINDOW_OVERSCAN,
      this.#total - visibleEnd,
      availableOverscan - leading,
    );
    const start = this.#visibleStart - leading;
    const end = visibleEnd + trailing;
    return { start, end };
  }

  #touchVisiblePages(): void {
    const { start, end } = this.#projectionBounds();
    for (const page of this.#pages.values()) {
      if (page.start < end && page.end > start ||
        this.#focusedIndex !== null && page.start <= this.#focusedIndex && this.#focusedIndex < page.end) {
        page.used = ++this.#clock;
      }
    }
  }

  #evict(): void {
    const maximumPages = this.#profile === 'reduced-resource' ? 6 : 12;
    while (this.#pages.size > maximumPages) {
      const { start, end } = this.#projectionBounds();
      const victim = [...this.#pages.values()]
        .filter((page) => !(page.start < end && page.end > start) &&
          !(this.#focusedIndex !== null && page.start <= this.#focusedIndex && this.#focusedIndex < page.end))
        .sort((left, right) => left.used - right.used)[0];
      if (victim === undefined) break;
      this.#pages.delete(victim.key);
      for (let index = victim.start; index < victim.end; index += 1) {
        const retained = [...this.#pages.values()].some((page) => page.start <= index && index < page.end);
        if (!retained) this.#rows.delete(index);
      }
    }
  }
}

function clampInteger(value: number, minimum: number, maximum: number): number {
  const integer = Number.isFinite(value) ? Math.trunc(value) : minimum;
  return Math.min(maximum, Math.max(minimum, integer));
}
