import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createEpgGuideView,
  createEpgState,
  type EpgChannelRowViewModel,
  type EpgPresentationSource,
  type EpgProgramCellViewModel,
} from '../../renderer/epg.js';
import {
  invalidateGuideLayoutMetrics,
  renderEpgGuideDom,
} from '../../renderer/epg/guideDom.js';
import {
  AGGRESSIVE_GUIDE_PRELOAD_PROFILE,
  DEFAULT_GUIDE_PRELOAD_PROFILE,
  GUIDE_DOM_CELL_CAP,
  GUIDE_DOM_ROW_CAP,
  GuidePresentationLru,
  projectGuideCacheIdentity,
  projectGuideVirtualRange,
} from '../../renderer/guideVirtualization.js';
import type { RendererDomBindings } from '../../renderer/domBindings.js';
import type { RouteWorkflowViewModel } from '../../renderer/workflow.js';

const SLOT = 30 * 60_000;
const ROW_OUTER_SIZE = 120;
const ACTUAL_ROW_STRIDE = 124;
const ACTUAL_SHELL_GAP = 16;

test('300-by-48 projection preserves header-relative viewport geometry, internal gaps, focus, and graceful caps', () => {
  const rows = fixtureRows();
  const rowStartOffset = 300;
  const input = {
    rows,
    scrollTop: rowStartOffset + 140 * ROW_OUTER_SIZE,
    viewportHeight: 6 * ROW_OUTER_SIZE,
    rowOuterSize: ROW_OUTER_SIZE,
    rowStartOffset,
    windowStartMs: 12 * SLOT,
    windowEndMs: 18 * SLOT,
    focusedRowIndex: 200,
    focusedProgramId: 'program-200-15',
  } as const;
  const projection = projectGuideVirtualRange(input);
  assert.ok(projection.rowIndexes.length <= GUIDE_DOM_ROW_CAP);
  assert.ok(projection.programIds.size <= GUIDE_DOM_CELL_CAP);
  assert.ok(projection.rowIndexes.includes(200));
  assert.ok(projection.programIds.has('program-200-15'));
  for (let visible = 140; visible < 146; visible += 1) assert.ok(projection.rowIndexes.includes(visible));
  assert.ok(projection.rowPlacements.some(({ rowIndex, gapBefore }) => rowIndex === 200 && gapBefore > 0));
  assert.deepEqual(
    projectGuideVirtualRange({ ...input, scrollTop: rowStartOffset }).rowIndexes.slice(0, 4),
    [0, 1, 2, 3],
  );

  const oversized = projectGuideVirtualRange({
    ...input,
    scrollTop: rowStartOffset + 100 * ROW_OUTER_SIZE,
    viewportHeight: 30 * ROW_OUTER_SIZE,
    focusedRowIndex: 115,
  });
  assert.equal(oversized.visibleRowsClamped, true);
  assert.equal(oversized.rowIndexes.length, GUIDE_DOM_ROW_CAP);
  assert.ok(oversized.rowIndexes.includes(115));
  assert.deepEqual(oversized.rowIndexes, Array.from(
    { length: GUIDE_DOM_ROW_CAP },
    (_, index) => (oversized.rowIndexes[0] ?? 0) + index,
  ));
});

test('actual Guide DOM reconciliation keeps buffer data nonfocusable, caches layout reads, and meets timing caps', () => {
  const originalDocument = globalThis.document;
  const metrics = { reads: 0 };
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: { createElement: (tagName: string) => new TimingElement(tagName, metrics) },
  });
  try {
    const source = fixturePresentation();
    const baseState = createEpgState(source, 1, 'compact');
    const state200 = {
      ...baseState,
      windowStartMs: 12 * SLOT,
      selectedChannelId: 'channel-200',
      selectedProgramId: 'program-200-15',
    };
    const state201 = {
      ...baseState,
      windowStartMs: 12 * SLOT,
      selectedChannelId: 'channel-201',
      selectedProgramId: 'program-201-15',
    };
    const view200 = routeView(createEpgGuideView(state200, source));
    const view201 = routeView(createEpgGuideView(state201, source));
    assert.ok(view200.guide.rows[0]?.programs.length > 6, 'production view retains the time buffer');

    const grid = new TimingElement('main', metrics);
    grid.clientHeight = 6 * ROW_OUTER_SIZE;
    const dom = guideDomBindings(grid);

    renderEpgGuideDom(view200, dom);
    grid.scrollTop = 300 + 140 * ACTUAL_ROW_STRIDE;
    renderEpgGuideDom(view200, dom);
    assert.equal(metrics.reads, 3, 'two consecutive rows and grid geometry are sampled once');
    const spacerHeights = grid.descendants()
      .filter((node) => node.dataset.epgVirtualSpacer === '')
      .map((node) => Number.parseInt(node.style.height, 10));
    assert.ok(spacerHeights.includes(137 * ACTUAL_ROW_STRIDE - ACTUAL_SHELL_GAP));
    assert.ok(spacerHeights.includes(51 * ACTUAL_ROW_STRIDE - ACTUAL_SHELL_GAP));
    const renderedProgramIds = grid.descendants()
      .map((node) => node.dataset.guideProgramId)
      .filter((id): id is string => id !== undefined);
    assert.ok(renderedProgramIds.length > 0);
    assert.ok(renderedProgramIds.some((id) => Number(id.split('-').at(-1)) < 12), 'the -120-minute DOM buffer is mounted');
    assert.ok(renderedProgramIds.some((id) => Number(id.split('-').at(-1)) >= 18), 'the +120-minute DOM buffer is mounted');
    const bufferedCells = grid.descendants().filter((node) => node.dataset.guideBufferedProgram !== undefined);
    assert.ok(bufferedCells.length > 0);
    assert.ok(bufferedCells.every((node) => node.dataset.focusId === undefined
      && node.dataset.guideProgramAction === undefined
      && node.getAttribute('aria-hidden') === 'true'
      && node.tabIndex === -1
      && node.style.width === '0px'), 'off-window buffer cells are inert and absent from focus registration');
    assert.ok(grid.descendants().filter((node) => node.dataset.focusId !== undefined && node.dataset.guideProgramId !== undefined)
      .every((node) => {
        const index = Number(node.dataset.guideProgramId?.split('-').at(-1));
        return index >= 12 && index < 18;
      }));

    for (let warmRun = 0; warmRun < 3; warmRun += 1) renderEpgGuideDom(view200, dom);
    const readsBeforeScroll = metrics.reads;
    const reconciles = measure(100, () => {
      grid.scrollTop = 300 + 140 * ACTUAL_ROW_STRIDE;
      renderEpgGuideDom(view200, dom);
    });
    assert.equal(metrics.reads, readsBeforeScroll, 'cached scroll reconciles do not resample layout');
    assertTiming(reconciles, 50, 100, 'reconcile');

    let focused = false;
    const focus = measure(100, () => {
      focused = !focused;
      renderEpgGuideDom(focused ? view201 : view200, dom);
    });
    assertTiming(focus, 16, 32, 'changed focus');

    invalidateGuideLayoutMetrics(grid as unknown as HTMLElement);
    renderEpgGuideDom(view200, dom);
    assert.equal(metrics.reads, readsBeforeScroll + 3, 'explicit layout invalidation permits one new stride/grid sample');
    const rowIndexesAfterScrolledInvalidation = grid.descendants()
      .map((node) => node.dataset.guideRowIndex)
      .filter((value): value is string => value !== undefined)
      .map(Number);
    for (let visible = 140; visible < 146; visible += 1) {
      assert.ok(rowIndexesAfterScrolledInvalidation.includes(visible), `row ${String(visible)} remains visible after scrolled invalidation`);
    }

    const freshGrid = new TimingElement('main', metrics);
    freshGrid.clientHeight = 6 * ROW_OUTER_SIZE;
    const start = globalThis.performance.now();
    renderEpgGuideDom(view200, guideDomBindings(freshGrid));
    const elapsed = globalThis.performance.now() - start;
    assert.ok(elapsed <= 100, `first visible DOM reconcile after bridge-shaped data ${String(elapsed)}ms`);
  } finally {
    if (originalDocument === undefined) delete (globalThis as { document?: Document }).document;
    else Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
  }
});

test('Desktop cache identities and LRU protect current/focused entries within both profile caps', () => {
  const identity = projectGuideCacheIdentity({
    scopeToken: 'scope-a', revision: 1, selectedLibraryId: null, pastItemsWindow: 'auto',
    guideDensity: 'compact', aggressivePreload: false,
  });
  for (const changed of [
    { scopeToken: 'scope-b' }, { revision: 2 }, { selectedLibraryId: 'library' },
    { pastItemsWindow: '30' }, { guideDensity: 'comfortable' }, { aggressivePreload: true },
  ]) {
    assert.notEqual(projectGuideCacheIdentity({
      scopeToken: 'scope-a', revision: 1, selectedLibraryId: null, pastItemsWindow: 'auto',
      guideDensity: 'compact', aggressivePreload: false, ...changed,
    }), identity);
  }

  for (const [profile, expectedEntries] of [
    [DEFAULT_GUIDE_PRELOAD_PROFILE, 6],
    [AGGRESSIVE_GUIDE_PRELOAD_PROFILE, 12],
  ] as const) {
    const cache = new GuidePresentationLru<string>(profile);
    cache.set({ key: 'focused', value: 'focused', programCount: 500, focused: true, current: false });
    cache.set({ key: 'current', value: 'current', programCount: 500, focused: false, current: true });
    for (let index = 0; index < expectedEntries + 4; index += 1) {
      cache.set({ key: `buffer-${String(index)}`, value: `buffer-${String(index)}`, programCount: 500, focused: false, current: false });
    }
    assert.ok(cache.size <= profile.maximumEntries);
    assert.ok(cache.programCount <= profile.maximumPrograms);
    assert.equal(cache.get('focused'), 'focused');
    assert.equal(cache.get('current'), 'current');
    cache.set({ key: 'replacement-focus', value: 'replacement-focus', programCount: 500, focused: true, current: false });
    assert.equal(cache.get('replacement-focus'), 'replacement-focus');
    assert.ok(cache.size <= profile.maximumEntries);
    cache.clear();
    assert.equal(cache.size, 0);
  }
});

function fixtureRows(): readonly EpgChannelRowViewModel[] {
  return Array.from({ length: 300 }, (_, rowIndex) => ({
    id: `channel-${String(rowIndex)}`, number: String(rowIndex + 1), name: `Channel ${String(rowIndex + 1)}`,
    isSelected: rowIndex === 200,
    programs: Array.from({ length: 48 }, (_, programIndex) => program(rowIndex, programIndex)),
  }));
}

function fixturePresentation(): EpgPresentationSource {
  return {
    channels: fixtureRows().map((row) => ({
      id: row.id, number: row.number, name: row.name,
      programs: row.programs.map(({ channelId: _channelId, focusId: _focusId, presentationGeneration: _generation,
        columnStart: _columnStart, columnSpan: _columnSpan, isSelected: _selected, temporalState: _temporal,
        progressPercent: _progress, widthTier: _tier, timeLabel: _time, ...entry }) => entry),
    })),
    nowWatching: null, nowMs: SLOT / 2, minimumStartTimeMs: 0,
    channelWindow: { offset: 0, total: 300 },
    libraryFilter: { scopeToken: 'scope', revision: 1, libraries: [], selectedLibraryId: null, persistenceStatus: 'ready' },
  };
}

function routeView(guide: ReturnType<typeof createEpgGuideView>): RouteWorkflowViewModel {
  return { route: 'guide', guide } as unknown as RouteWorkflowViewModel;
}

function guideDomBindings(grid: TimingElement): RendererDomBindings {
  return {
    epgGridElement: grid,
    epgDetailChannelElement: null,
    epgDetailTitleElement: null,
    epgDetailTimeElement: null,
    epgDetailDescriptionElement: null,
    epgDetailArtworkElement: null,
    epgDetailPosterElement: null,
    epgDetailArtworkPlaceholderElement: null,
  } as unknown as RendererDomBindings;
}

function program(rowIndex: number, programIndex: number): EpgProgramCellViewModel {
  return {
    id: `program-${String(rowIndex)}-${String(programIndex)}`, channelId: `channel-${String(rowIndex)}`,
    focusId: `focus-${String(rowIndex)}-${String(programIndex)}`, title: 'Program', subtitle: '', description: '',
    showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [], startsAtMs: programIndex * SLOT,
    endsAtMs: (programIndex + 1) * SLOT, artwork: null, presentationGeneration: 1, columnStart: programIndex + 1,
    columnSpan: 1, isSelected: rowIndex === 200 && programIndex === 15, temporalState: 'upcoming',
    progressPercent: 0, widthTier: 'narrow', timeLabel: '',
  };
}

function measure(count: number, operation: () => unknown): number[] {
  return Array.from({ length: count }, () => {
    const start = globalThis.performance.now();
    operation();
    return globalThis.performance.now() - start;
  });
}

function assertTiming(values: readonly number[], p95Cap: number, maxCap: number, label: string): void {
  const p95 = percentile(values, 95);
  const maximum = Math.max(...values);
  assert.ok(p95 <= p95Cap, `${label} p95 ${String(p95)}ms`);
  assert.ok(maximum <= maxCap, `${label} max ${String(maximum)}ms`);
}

function percentile(values: readonly number[], value: number): number {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * value / 100) - 1)] ?? 0;
}

class TimingElement {
  className = '';
  dataset: Record<string, string> = {};
  textContent = '';
  type = '';
  hidden = false;
  tabIndex = 0;
  scrollTop = 0;
  clientHeight = 0;
  screenTop = 700;
  parent: TimingElement | null = null;
  readonly children: TimingElement[] = [];
  readonly attributes = new Map<string, string>();
  readonly style = {
    position: '', left: '', width: '', height: '',
    setProperty: (_name: string, _value: string) => undefined,
  };
  constructor(readonly tagName: string, private readonly metrics: { reads: number }) {}
  get childElementCount(): number { return this.children.length; }
  setAttribute(name: string, value: string): void { this.attributes.set(name, value); }
  getAttribute(name: string): string | null { return this.attributes.get(name) ?? null; }
  removeAttribute(name: string): void { this.attributes.delete(name); }
  append(...children: TimingElement[]): void {
    for (const child of children) child.parent = this;
    this.children.push(...children);
  }
  replaceChildren(...children: TimingElement[]): void {
    for (const child of children) child.parent = this;
    this.children.splice(0, this.children.length, ...children);
  }
  querySelector<T>(_selector: string): T | null {
    return (this.descendants().find((node) => node.className.split(' ').includes('epg-grid__row')) ?? null) as T | null;
  }
  querySelectorAll<T>(_selector: string): T[] {
    return this.descendants().filter((node) => node.className.split(' ').includes('epg-grid__row')) as T[];
  }
  getBoundingClientRect(): DOMRect {
    this.metrics.reads += 1;
    const grid = this.root();
    const rowIndex = Number(this.dataset.guideRowIndex ?? 0);
    const top = this.className === 'epg-grid__row'
      ? grid.screenTop + 300 + rowIndex * ACTUAL_ROW_STRIDE - grid.scrollTop
      : this.screenTop;
    return { height: this.className === 'epg-grid__row' ? 108 : this.clientHeight, top } as DOMRect;
  }
  descendants(): TimingElement[] {
    return this.children.flatMap((child) => [child, ...child.descendants()]);
  }
  private root(): TimingElement { return this.parent === null ? this : this.parent.root(); }
}
