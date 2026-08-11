import type { RendererDomBindings } from '../domBindings.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { DesktopSettingsValues } from '../../contracts/settings.js';
import {
  formatEpgTimeWindow,
  type EpgProgramCellViewModel,
} from '../epg.js';
import { isSafeArtworkRefId, type ArtworkRef } from '../../contracts/artwork.js';
import type { GuideLibraryFilterState } from '../../contracts/guide.js';
import { projectGuideVirtualRange, type GuideVirtualRange } from '../guideVirtualization.js';
import { guidePerformanceMarks } from '../guidePerformanceMarks.js';
import {
  GUIDE_COMFORTABLE_ROW_HEIGHT,
  GUIDE_DEFAULT_ROW_GAP,
  projectGuideCompleteRowInterval,
  resolveGuideRowDensity,
  type GuideCompleteRowInterval,
  type GuideViewportMetrics,
} from '../guideRowDensity.js';

export interface CellPosition {
  left: number;
  width: number;
  isClippedStart: boolean;
  isClippedEnd: boolean;
}

const GUIDE_TRACK_UNITS = 1000;
const failedArtwork = new WeakMap<HTMLImageElement, Readonly<{
  presentationGeneration: number;
  refId: string;
}>>();
const pendingArtwork = new WeakMap<HTMLImageElement, object>();
type GuideBackgroundState = 'missing' | 'loading' | 'available' | 'error' | 'poster-fallback';
type GuideBackgroundCause = 'missing' | 'placeholder' | 'expired' | 'error';
type GuideBackgroundRequest = Readonly<{
  refId: string;
  generationText: string;
  artworkUrl: string;
}>;
type GuideBackgroundFailures = {
  presentationGeneration: number;
  refIds: Set<string>;
};
const failedBackground = new WeakMap<HTMLImageElement, GuideBackgroundFailures>();
const pendingBackground = new WeakMap<HTMLImageElement, GuideBackgroundRequest>();
const guideLayoutMetrics = new WeakMap<HTMLElement, {
  key: string;
  rowOuterSize: number;
  rowGapSize: number;
  rowStartOffset: number;
  measured: boolean;
}>();

export function invalidateGuideLayoutMetrics(grid: HTMLElement | null): void {
  if (grid !== null) guideLayoutMetrics.delete(grid);
}

export function readGuideViewportRows(grid: HTMLElement | null): Readonly<{ start: number; completeCount: number }> {
  if (grid === null) return { start: 0, completeCount: 6 };
  const metrics = guideLayoutMetrics.get(grid);
  const effectiveDensity = grid.dataset.guideRowDensityEffective === 'compact' ? 'compact' : 'comfortable';
  const fallbackDensity = metrics === undefined ? resolveGuideRowDensity(
    effectiveDensity,
    readGuideViewportMetrics(grid),
    GUIDE_DEFAULT_ROW_GAP,
  ) : null;
  const rowOuterSize = metrics?.rowOuterSize ?? fallbackDensity?.rowOuterSize ?? GUIDE_DEFAULT_ROW_GAP + GUIDE_COMFORTABLE_ROW_HEIGHT;
  const rowHeight = metrics === undefined
    ? fallbackDensity?.rowHeight ?? GUIDE_COMFORTABLE_ROW_HEIGHT
    : Math.max(1, rowOuterSize - metrics.rowGapSize);
  const rowGap = metrics?.rowGapSize ?? fallbackDensity?.rowGap ?? GUIDE_DEFAULT_ROW_GAP;
  const rowStartOffset = metrics?.rowStartOffset ?? readGuideRowStartOffset(grid, rowOuterSize) ?? 0;
  const scrollTop = Number.isFinite(grid.scrollTop) ? Math.max(0, grid.scrollTop) : 0;
  const viewportHeight = grid.clientHeight > 0 ? grid.clientHeight : rowOuterSize * 6;
  const interval = projectGuideCompleteRowInterval(
    viewportHeight,
    rowStartOffset,
    scrollTop,
    rowHeight,
    rowGap,
  );
  return {
    start: interval.start,
    completeCount: Math.min(24, interval.count),
  };
}

export function guideCellPosition(
  startsAtMs: number,
  endsAtMs: number,
  windowStartMs: number,
  windowEndMs: number,
  trackWidth: number = GUIDE_TRACK_UNITS,
): CellPosition {
  const isClippedStart = startsAtMs < windowStartMs;
  const isClippedEnd = endsAtMs > windowEndMs;

  const totalDuration = windowEndMs - windowStartMs;
  if (totalDuration <= 0) {
    return { left: 0, width: 0, isClippedStart, isClippedEnd };
  }
  const startOffset = startsAtMs - windowStartMs;
  const endOffset = endsAtMs - windowStartMs;

  const left = Math.max(0, (startOffset / totalDuration) * trackWidth);
  const right = Math.min(trackWidth, (endOffset / totalDuration) * trackWidth);
  const width = Math.max(0, right - left);

  return { left, width, isClippedStart, isClippedEnd };
}

export function guideVisibleWindow(
  startsAtMs: number,
  endsAtMs: number,
  windowStartMs: number,
  windowEndMs: number
): { startsAtMs: number; endsAtMs: number; durationMs: number } {
  const start = Math.max(startsAtMs, windowStartMs);
  const end = Math.min(endsAtMs, windowEndMs);
  return {
    startsAtMs: start,
    endsAtMs: end,
    durationMs: Math.max(0, end - start),
  };
}

export function guidePresentation(
  width: number,
  temporalState: string,
  isSelected: boolean
): {
  widthTier: 'wide' | 'medium' | 'narrow' | 'sliver';
  isLive: boolean;
  showTicker: boolean;
} {
  let widthTier: 'wide' | 'medium' | 'narrow' | 'sliver';
  if (width >= 350) {
    widthTier = 'wide';
  } else if (width >= 180) {
    widthTier = 'medium';
  } else if (width >= 80) {
    widthTier = 'narrow';
  } else {
    widthTier = 'sliver';
  }

  return {
    widthTier,
    isLive: temporalState === 'current',
    showTicker: isSelected,
  };
}

export function guideCellDom(
  program: EpgProgramCellViewModel,
  windowStartMs: number,
  windowEndMs: number,
  trackWidth: number = GUIDE_TRACK_UNITS,
  previewBadgesEnabled = true,
): HTMLElement {
  const pos = guideCellPosition(program.startsAtMs, program.endsAtMs, windowStartMs, windowEndMs, trackWidth);
  const pres = guidePresentation(pos.width, program.temporalState, program.isSelected);

  const cell = document.createElement('button');
  cell.type = 'button';
  cell.className = 'epg-grid__program';
  cell.dataset.guideProgramAction = 'activate';
  cell.dataset.focusId = program.focusId;
  cell.dataset.guideChannelId = program.channelId;
  cell.dataset.guideProgramId = program.id;
  cell.dataset.guideGeneration = String(program.presentationGeneration);
  cell.dataset.selectedProgram = String(program.isSelected);
  cell.dataset.temporalState = program.temporalState;
  cell.dataset.guideCellState = program.temporalState;
  cell.dataset.widthTier = pres.widthTier;
  cell.dataset.clippedStart = String(pos.isClippedStart);
  cell.dataset.clippedEnd = String(pos.isClippedEnd);
  cell.setAttribute('role', 'gridcell');
  cell.setAttribute('aria-selected', String(program.isSelected));
  cell.setAttribute('aria-label', `${program.title}, ${program.timeLabel}`);

  cell.style.position = 'absolute';
  cell.style.left = `${toTrackPercent(pos.left, trackWidth)}%`;
  cell.style.width = `max(0px, calc(${toTrackPercent(pos.width, trackWidth)}% - 4px))`;
  cell.style.setProperty('--epg-cell-progress', `${program.progressPercent}%`);

  const meta = document.createElement('div');
  meta.className = 'epg-cell-meta';

  if (pres.isLive) {
    const liveBadge = document.createElement('span');
    liveBadge.className = 'epg-badge epg-badge--live';
    liveBadge.textContent = 'LIVE';
    meta.append(liveBadge);
  }

  if (previewBadgesEnabled && program.episodeLabel && program.episodeLabel.trim()) {
    const epBadge = document.createElement('span');
    epBadge.className = 'epg-badge epg-badge--episode';
    epBadge.textContent = program.episodeLabel.trim();
    meta.append(epBadge);
  }

  const timeSpan = document.createElement('span');
  timeSpan.className = 'epg-cell-time';
  timeSpan.textContent = program.timeLabel;
  meta.append(timeSpan);

  const title = document.createElement('strong');
  title.className = 'epg-cell-title';
  title.textContent = program.title;

  const subtitle = document.createElement('span');
  subtitle.className = 'epg-cell-subtitle';
  subtitle.textContent = program.subtitle;

  const progress = document.createElement('i');
  progress.className = 'epg-cell-progress';
  progress.setAttribute('aria-hidden', 'true');

  cell.append(meta, title, subtitle, progress);
  return cell;
}

export function guideLibraryTabsDom(filter: GuideLibraryFilterState): HTMLElement {
  const tabs = document.createElement('nav');
  tabs.className = 'epg-library-tabs';
  tabs.setAttribute('role', 'tablist');
  tabs.setAttribute('aria-label', 'Guide libraries');
  const choices = [{ id: null, name: 'All' }, ...filter.libraries.map((library) => ({ id: library.id, name: library.name }))];
  for (const choice of choices) {
    const selected = choice.id === filter.selectedLibraryId;
    const tab = document.createElement('button');
    tab.setAttribute('type', 'button');
    tab.className = 'epg-library-tab';
    tab.dataset.guideLibraryId = choice.id ?? '';
    tab.dataset.focusId = guideLibraryFocusId(choice.id);
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    tab.textContent = choice.name;
    tabs.append(tab);
  }
  return tabs;
}

export function guideLibraryFocusId(libraryId: string | null): string {
  if (libraryId === null) return 'guide-library-choice-all';
  let encoded = '';
  for (let index = 0; index < libraryId.length; index += 1) {
    encoded += libraryId.charCodeAt(index).toString(16).padStart(4, '0');
  }
  return `guide-library-choice-id-${encoded}`;
}

export function shouldRenderGuideLibraryTabs(
  enabled: boolean,
  filter: GuideLibraryFilterState | null | undefined,
): filter is GuideLibraryFilterState {
  return enabled && (filter?.libraries.length ?? 0) > 1;
}

export function projectGuideLibraryTabsPending(root: HTMLElement | null, pending: boolean): void {
  for (const tab of Array.from(root?.querySelectorAll<HTMLButtonElement>('[data-guide-library-id]') ?? [])) {
    tab.setAttribute('aria-disabled', String(pending));
    if (pending) {
      tab.dataset.overlayBusyFocusCustody = 'true';
      tab.setAttribute('aria-busy', 'true');
    } else {
      delete tab.dataset.overlayBusyFocusCustody;
      tab.removeAttribute('aria-busy');
    }
  }
}

export function renderEpgGuideDom(...args: Parameters<typeof renderEpgGuideDomContent>): void {
  guidePerformanceMarks.reconcile(
    args[0].guide.presentationGeneration,
    () => renderEpgGuideDomContent(...args),
  );
}

function renderEpgGuideDomContent(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  settings: Pick<DesktopSettingsValues,
    'guideTimeRange' |
    'guideRowDensity' |
    'previewBadgesEnabled' |
    'libraryTabsEnabled' |
    'nowWatchingBannerEnabled' |
    'guideLayout'> = {
    guideTimeRange: 'detailed',
    guideRowDensity: 'auto',
    previewBadgesEnabled: true,
    libraryTabsEnabled: true,
    nowWatchingBannerEnabled: true,
    guideLayout: 'classic',
  },
  reconcilePass = 0,
): void {
  renderGuideDetailCopy(view, dom, settings.previewBadgesEnabled);
  renderGuideDetailArtwork(view, dom);

  if (!dom.epgGridElement) {
    return;
  }

  if (view.guide.presentationState === 'ready') {
    dom.epgGridElement.setAttribute('role', 'grid');
  } else {
    dom.epgGridElement.removeAttribute('role');
  }

  const trackWidth = GUIDE_TRACK_UNITS;

  const shell = document.createElement('section');
  shell.className = 'epg-shell';
  const previousGuideLayout = dom.epgGridElement.dataset.guideLayout;
  const previousEffectiveDensity = dom.epgGridElement.dataset.guideRowDensityEffective;
  shell.dataset.epgLayout = settings.guideLayout;
  shell.dataset.guideComposition = settings.guideLayout;
  shell.dataset.guideTimeRange = settings.guideTimeRange;
  shell.dataset.guideRowDensity = settings.guideRowDensity;
  dom.epgGridElement.dataset.guideTimeRange = settings.guideTimeRange;
  dom.epgGridElement.dataset.guideRowDensity = settings.guideRowDensity;
  dom.epgGridElement.dataset.guideLayout = settings.guideLayout;
  projectGuideLayoutAttributes(dom.epgGridElement, dom.epgDetailArtworkElement, settings.guideLayout);

  const classicHeader = document.createElement('header');
  classicHeader.className = 'epg-classic-header';
  classicHeader.dataset.guideShellRegion = 'classic-header';
  classicHeader.hidden = settings.guideLayout !== 'classic';
  classicHeader.setAttribute('aria-hidden', String(settings.guideLayout !== 'classic'));
  const headerBrand = document.createElement('div');
  headerBrand.className = 'epg-classic-header-brand';
  const brand = document.createElement('strong');
  brand.className = 'epg-classic-header-title';
  brand.textContent = view.guide.shell.brandLabel;
  headerBrand.append(brand);

  const shellNowWatching = view.guide.shell.nowWatching;
  const showNowWatching = view.route === 'guide' &&
    view.guide.presentationState === 'ready' &&
    settings.nowWatchingBannerEnabled &&
    shellNowWatching !== null;
  const nowPlaying = !showNowWatching || settings.guideLayout !== 'classic'
    ? null
    : document.createElement('div');
  if (nowPlaying !== null) {
    nowPlaying.className = 'epg-classic-now-playing';
    nowPlaying.dataset.guideNowWatching = 'classic';
    nowPlaying.setAttribute('role', 'status');
    nowPlaying.setAttribute('aria-live', 'polite');
    nowPlaying.setAttribute('aria-atomic', 'true');
    const nowLabel = document.createElement('span');
    nowLabel.className = 'epg-classic-now-playing-label';
    nowLabel.textContent = 'NOW PLAYING';
    nowPlaying.append(nowLabel);
    if (view.guide.shell.nowWatchingChannelLabel !== null) {
      const nowPlayingChannel = document.createElement('span');
      nowPlayingChannel.className = 'epg-classic-now-playing-channel';
      nowPlayingChannel.textContent = view.guide.shell.nowWatchingChannelLabel;
      nowPlaying.append(nowPlayingChannel);
    }
  }

  const focusHint = document.createElement('div');
  focusHint.className = 'epg-classic-header-actions';
  for (const hintAction of view.guide.shell.focusHint.split('·').map((value) => value.trim()).filter(Boolean)) {
    const action = document.createElement('span');
    action.textContent = (focusHint.childElementCount === 0 ? hintAction : `· ${hintAction}`);
    focusHint.append(action);
  }

  classicHeader.append(headerBrand);
  if (nowPlaying !== null) classicHeader.append(nowPlaying);
  classicHeader.append(focusHint);

  const nowWatching = !showNowWatching || settings.guideLayout !== 'overlay'
    ? null
    : document.createElement('div');
  if (nowWatching !== null && shellNowWatching !== null) {
    nowWatching.className = 'epg-now-watching-banner';
    nowWatching.dataset.guideNowWatching = 'overlay';
    nowWatching.setAttribute('role', 'status');
    nowWatching.setAttribute('aria-live', 'polite');
    nowWatching.setAttribute('aria-atomic', 'true');
    const nowBannerLabel = document.createElement('span');
    nowBannerLabel.className = 'epg-now-watching-live';
    nowBannerLabel.textContent = 'NOW PLAYING';
    nowWatching.append(nowBannerLabel);
    if (view.guide.shell.nowWatchingChannelLabel !== null) {
      const nowChannel = document.createElement('strong');
      nowChannel.className = 'epg-now-watching-channel';
      nowChannel.textContent = view.guide.shell.nowWatchingChannelLabel;
      nowWatching.append(nowChannel);
    }
    const nowProgram = document.createElement('span');
    nowProgram.className = 'epg-now-watching-program';
    nowProgram.textContent = shellNowWatching.title;
    const nowTime = document.createElement('span');
    nowTime.className = 'epg-now-watching-time';
    nowTime.textContent = formatEpgTimeWindow(
      shellNowWatching.startsAtMs,
      shellNowWatching.endsAtMs,
    );
    nowWatching.append(nowProgram, nowTime);
  }

  const stateElement = document.createElement('article');
  stateElement.className = 'epg-state-panel';
  stateElement.dataset.epgState = view.guide.state.state;
  const stateLabel = document.createElement('strong');
  stateLabel.textContent = view.guide.state.label;
  const stateDetail = document.createElement('span');
  stateDetail.textContent = view.guide.state.detail;
  stateElement.append(stateLabel, stateDetail);
  const stateActions = document.createElement('div');
  stateActions.className = 'epg-state-actions';
  for (const action of stateActionsFor(view.guide.presentationState)) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.guideAction = action.id;
    button.dataset.focusId = `guide-state-${action.id}`;
    button.textContent = action.label;
    stateActions.append(button);
  }
  if (view.guide.presentationState !== 'ready') {
    stateElement.append(stateActions);
  }

  shell.append(classicHeader);
  if (nowWatching !== null) shell.append(nowWatching);
  const libraryFilter = view.guide.libraryFilter;
  if (shouldRenderGuideLibraryTabs(settings.libraryTabsEnabled, libraryFilter)) {
    shell.append(guideLibraryTabsDom(libraryFilter));
  }
  shell.append(stateElement);
  let needsPostRenderReconcile = false;
  if (view.guide.presentationState === 'ready') {
    stateElement.hidden = true;
    stateElement.setAttribute('aria-hidden', 'true');
    shell.append(stateActions);
    if (view.guide.tuneError !== null) {
      const actionError = document.createElement('p');
      actionError.className = 'epg-action-error';
      actionError.dataset.guideTuneError = '';
      actionError.setAttribute('role', 'status');
      actionError.textContent = view.guide.tuneError;
      shell.append(actionError);
    }
    const previousMetrics = guideLayoutMetrics.get(dom.epgGridElement);
    const layoutChanged = previousGuideLayout !== undefined && previousGuideLayout !== settings.guideLayout;
    const previousRowOuterSize = previousMetrics?.rowOuterSize ?? GUIDE_DEFAULT_ROW_GAP + GUIDE_COMFORTABLE_ROW_HEIGHT;
    const currentRowLayout = previousMetrics?.measured && !layoutChanged && previousEffectiveDensity !== undefined
      ? null
      : readGuideRowLayout(dom.epgGridElement, previousRowOuterSize);
    const previousRowGap = previousMetrics?.measured
      ? previousMetrics.rowGapSize
      : currentRowLayout?.rowGap
        ?? GUIDE_DEFAULT_ROW_GAP;
    const rowStartOffsetForDensity = previousMetrics?.measured && !layoutChanged && previousEffectiveDensity !== undefined
      ? previousMetrics.rowStartOffset
      : currentRowLayout?.rowStartOffset
        ?? previousMetrics?.rowStartOffset
        ?? 0;
    const density = resolveGuideRowDensity(
      settings.guideRowDensity,
      readGuideViewportMetrics(dom.epgGridElement, rowStartOffsetForDensity),
      previousRowGap,
    );
    const densityChanged = previousEffectiveDensity !== undefined && previousEffectiveDensity !== density.effective;
    shell.dataset.guideRowDensityEffective = density.effective;
    shell.dataset.guideCompleteRows = String(density.completeRows);
    shell.dataset.guideCompleteRowFloor = String(density.minimumCompleteRows);
    shell.dataset.guideDensityFloorMet = String(density.floorMet);
    shell.style.setProperty('--guide-row-height', `${String(density.rowHeight)}px`);
    dom.epgGridElement.dataset.guideRowDensityEffective = density.effective;
    const metricsKey = [
      settings.guideLayout,
      settings.guideRowDensity,
      density.effective,
      String(density.rowHeight),
      String(dom.epgGridElement.clientWidth),
      String(dom.epgGridElement.clientHeight),
    ].join(':');
    const cachedMetrics = guideLayoutMetrics.get(dom.epgGridElement);
    const canReuse = !densityChanged && cachedMetrics?.key === metricsKey && cachedMetrics.measured;
    const measuredRows = !densityChanged && !layoutChanged && !canReuse && typeof dom.epgGridElement.querySelectorAll === 'function'
      ? Array.from(dom.epgGridElement.querySelectorAll<HTMLElement>('.epg-grid__row'))
      : [];
    const rowElement = measuredRows[0] ?? null;
    const rowRect = rowElement?.getBoundingClientRect?.();
    const measuredRow = rowRect?.height;
    const hasMeasurement = Number.isFinite(measuredRow) && (measuredRow ?? 0) > 0;
    const representedRowIndex = parseGuideRowIndex(rowElement?.dataset.guideRowIndex);
    const consecutiveRow = representedRowIndex === null
      ? undefined
      : measuredRows.find((row) => parseGuideRowIndex(row.dataset.guideRowIndex) === representedRowIndex + 1);
    const consecutiveRect = consecutiveRow?.getBoundingClientRect();
    const measuredStride = rowRect === undefined || consecutiveRect === undefined
      ? null
      : consecutiveRect.top - rowRect.top;
    const computedGap = rowElement === null ? null : readGuideRowGap(rowElement);
    const rowOuterSize = densityChanged || layoutChanged
      ? density.rowOuterSize
      : canReuse
      ? cachedMetrics.rowOuterSize
      : measuredStride !== null && Number.isFinite(measuredStride) && measuredStride > 0
        ? measuredStride
        : hasMeasurement && computedGap !== null
          ? (measuredRow ?? 0) + computedGap
          : density.rowOuterSize;
    const rowGapSize = densityChanged || layoutChanged
      ? density.rowGap
      : canReuse
      ? cachedMetrics.rowGapSize
      : hasMeasurement ? Math.max(0, rowOuterSize - (measuredRow ?? rowOuterSize)) : 0;
    const gridTop = rowElement === null ? 0 : dom.epgGridElement.getBoundingClientRect().top;
    const rowStartOffset = densityChanged || layoutChanged
      ? rowStartOffsetForDensity
      : canReuse
      ? cachedMetrics.rowStartOffset
      : rowRect === undefined || representedRowIndex === null
        ? 0
        : Math.max(0, rowRect.top - gridTop + dom.epgGridElement.scrollTop - representedRowIndex * rowOuterSize);
    guideLayoutMetrics.set(dom.epgGridElement, {
      key: metricsKey,
      rowOuterSize,
      rowGapSize,
      rowStartOffset,
      measured: canReuse || (!densityChanged && !layoutChanged && hasMeasurement),
    });
    needsPostRenderReconcile = reconcilePass === 0 && (
      previousMetrics === undefined ||
      densityChanged ||
      layoutChanged ||
      (!canReuse && !hasMeasurement)
    );
    const focusedRowIndex = view.guide.selectedProgram === null
      ? -1
      : view.guide.rows.find((row) => row.id === view.guide.selectedProgram?.channelId)?.absoluteIndex ?? -1;
    const completeRowInterval = projectGuideCompleteRowInterval(
      dom.epgGridElement.clientHeight || rowOuterSize * 6,
      rowStartOffset,
      dom.epgGridElement.scrollTop,
      Math.max(1, rowOuterSize - rowGapSize),
      rowGapSize,
    );
    const virtualRange = projectGuideVirtualRange({
      rows: view.guide.rows,
      scrollTop: dom.epgGridElement.scrollTop,
      viewportHeight: dom.epgGridElement.clientHeight || rowOuterSize * 6,
      rowOuterSize,
      rowStartOffset,
      completeRowInterval,
      windowStartMs: view.guide.windowStartMs,
      windowEndMs: view.guide.windowEndMs,
      focusedRowIndex,
      focusedProgramId: view.guide.selectedProgram?.id ?? null,
      rowOffset: view.guide.channelWindow.offset,
      totalRowCount: view.guide.channelWindow.total,
    });
    shell.append(...readyGuideGridDom(
      view,
      trackWidth,
      settings.previewBadgesEnabled,
      virtualRange,
      completeRowInterval,
      rowOuterSize,
      rowGapSize,
    ));
  }
  dom.epgGridElement.replaceChildren(shell);
  if (needsPostRenderReconcile) renderEpgGuideDomContent(view, dom, settings, reconcilePass + 1);
}

function renderGuideDetailCopy(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  previewBadgesEnabled: boolean,
): void {
  const selectedRow = view.guide.selectedProgram === null
    ? undefined
    : view.guide.rows.find((row) => row.id === view.guide.selectedProgram?.channelId);
  const info = view.guide.infoPanel;
  const fallbackTitle = view.guide.state.label;
  const title = (info?.title ?? fallbackTitle).slice(0, 160);
  const detailState = info === null ? view.guide.state.detail : info.timeLabel;
  if (dom.epgDetailChannelElement) {
    dom.epgDetailChannelElement.textContent =
      selectedRow === undefined ? '' : `${selectedRow.number} - ${selectedRow.name}`;
    dom.epgDetailChannelElement.dataset.channelState = selectedRow === undefined ? 'missing' : 'selected';
  }
  if (dom.epgDetailEyebrowElement) {
    dom.epgDetailEyebrowElement.textContent = info?.eyebrow ?? '';
    dom.epgDetailEyebrowElement.hidden = info === null || info.eyebrow.length === 0;
  }
  if (dom.epgDetailTitleElement) {
    dom.epgDetailTitleElement.textContent = title;
    dom.epgDetailTitleElement.dataset.titleFallback = info === null ? 'state' : 'text';
  }
  if (dom.epgDetailSubtitleElement) {
    dom.epgDetailSubtitleElement.textContent = info?.subtitle ?? '';
    dom.epgDetailSubtitleElement.hidden = info === null || info.subtitle.length === 0;
  }
  if (dom.epgDetailTimeElement) {
    dom.epgDetailTimeElement.textContent = detailState;
    dom.epgDetailTimeElement.dataset.detailState = info === null ? view.guide.presentationState : 'selected';
  }
  if (dom.epgDetailBadgesElement) {
    renderGuideDetailBadges(dom.epgDetailBadgesElement, info === null || !previewBadgesEnabled ? [] : info.badges);
  }
  if (dom.epgDetailGenresElement) {
    dom.epgDetailGenresElement.textContent = info?.genres ?? '';
    dom.epgDetailGenresElement.hidden = info === null || info.genres.length === 0;
  }
  if (dom.epgDetailDescriptionElement) {
    dom.epgDetailDescriptionElement.textContent = (info?.description ?? '').slice(0, 600);
    dom.epgDetailDescriptionElement.hidden = info === null || info.description.length === 0;
  }
}

function renderGuideDetailBadges(
  container: HTMLElement,
  badges: readonly string[],
): void {
  const slots = typeof container.querySelectorAll === 'function'
    ? Array.from(container.querySelectorAll<HTMLElement>('[data-epg-detail-badge-slot]'))
    : [];
  if (slots.length === 0) {
    container.textContent = badges.join(' / ');
    container.hidden = badges.length === 0;
    return;
  }
  for (const [index, slot] of slots.entries()) {
    const value = badges[index] ?? '';
    slot.textContent = value;
    slot.hidden = value.length === 0;
  }
  container.hidden = badges.length === 0;
}

function projectGuideLayoutAttributes(
  grid: HTMLElement,
  figure: HTMLElement | null,
  layout: 'classic' | 'overlay',
): void {
  grid.dataset.guideLayout = layout;
  const guideScreen = typeof grid.closest === 'function'
    ? grid.closest<HTMLElement>('[data-screen="guide"]')
    : null;
  if (guideScreen !== null) guideScreen.dataset.guideLayout = layout;
  if (figure === null) return;
  const detail = typeof figure.closest === 'function'
    ? figure.closest<HTMLElement>('.guide-detail')
    : null;
  if (detail !== null) {
    detail.dataset.guideLayout = layout;
    detail.dataset.guideComposition = layout;
  }
}

export function renderGuideDetailArtwork(
  view: RouteWorkflowViewModel,
  dom: Pick<RendererDomBindings,
    'epgDetailBackgroundElement' |
    'epgDetailBackgroundImageElement' |
    'epgDetailArtworkElement' |
    'epgDetailPosterElement' |
    'epgDetailArtworkPlaceholderElement'>,
): void {
  const figure = dom.epgDetailArtworkElement;
  const image = dom.epgDetailPosterElement;
  const placeholder = dom.epgDetailArtworkPlaceholderElement;
  if (figure === null || image === null || placeholder === null) return;
  placeholder.setAttribute('aria-hidden', 'true');
  const info = view.guide.infoPanel;
  const nowMs = view.guide.nowMs;
  renderGuideDetailPoster(info, nowMs, figure, image, placeholder);
  renderGuideDetailBackground(
    info,
    nowMs,
    view.guide.presentationGeneration,
    dom.epgDetailBackgroundElement,
    dom.epgDetailBackgroundImageElement,
  );
}

function renderGuideDetailPoster(
  info: RouteWorkflowViewModel['guide']['infoPanel'],
  nowMs: number,
  figure: HTMLElement,
  image: HTMLImageElement,
  placeholder: HTMLElement,
): void {
  const artwork = info?.artwork.poster ?? null;
  if (!isValidGuideArtworkRef(artwork, 'poster', nowMs)) {
    placeholder.textContent = 'Artwork unavailable';
    clearGuideArtworkImage(image);
    failedArtwork.delete(image);
    setArtworkState(figure, image, placeholder, 'missing');
    return;
  }
  const failed = failedArtwork.get(image);
  if (
    info !== null &&
    failed?.presentationGeneration === info.presentationGeneration &&
    failed.refId === artwork.id
  ) {
    placeholder.textContent = 'Artwork unavailable';
    clearGuideArtworkImage(image);
    setArtworkState(figure, image, placeholder, 'error');
    return;
  }
  if (info === null) return;
  const generationText = String(info.presentationGeneration);
  const artworkUrl = guideArtworkUrl(artwork.id);
  if (
    image.dataset.artworkRefId === artwork.id &&
    image.dataset.artworkGeneration === generationText &&
    image.getAttribute('src') === artworkUrl
  ) return;
  clearGuideArtworkImage(image);
  image.dataset.artworkRefId = artwork.id;
  image.dataset.artworkGeneration = generationText;
  image.alt = clampArtworkAlt(
    artwork.altText.length > 0 ? artwork.altText : `Poster for ${info.title}`,
  );
  image.decoding = 'async';
  image.draggable = false;
  placeholder.textContent = 'Loading artwork…';
  setArtworkState(figure, image, placeholder, 'loading');
  const request = Object.freeze({ refId: artwork.id, generationText });
  pendingArtwork.set(image, request);
  image.onload = () => {
    if (!isPendingArtwork(image, request, artwork.id, generationText, artworkUrl)) return;
    pendingArtwork.delete(image);
    image.onload = null;
    image.onerror = null;
    setArtworkState(figure, image, placeholder, 'available');
  };
  image.onerror = () => {
    if (!isPendingArtwork(image, request, artwork.id, generationText, artworkUrl)) return;
    failedArtwork.set(image, {
      presentationGeneration: info.presentationGeneration,
      refId: artwork.id,
    });
    placeholder.textContent = 'Artwork unavailable';
    clearGuideArtworkImage(image);
    setArtworkState(figure, image, placeholder, 'error');
  };
  image.src = artworkUrl;
}

function renderGuideDetailBackground(
  info: RouteWorkflowViewModel['guide']['infoPanel'],
  nowMs: number,
  presentationGeneration: number,
  surface: HTMLElement | null,
  image: HTMLImageElement | null,
): void {
  if (surface === null || image === null) return;
  surface.setAttribute('aria-hidden', 'true');
  image.setAttribute('aria-hidden', 'true');
  image.alt = '';
  image.decoding = 'async';
  image.draggable = false;
  const failedRefs = failedBackgroundForGeneration(image, presentationGeneration);
  if (info === null) {
    clearGuideBackgroundImage(image);
    setGuideBackgroundState(surface, image, 'missing', 'theme');
    delete surface.dataset.backgroundCause;
    return;
  }

  const background = info.artwork.background;
  const poster = isValidGuideArtworkRef(info.artwork.poster, 'poster', nowMs)
    ? info.artwork.poster
    : null;
  if (isValidGuideArtworkRef(background, 'background', nowMs)) {
    const generationText = String(presentationGeneration);
    const artworkUrl = guideArtworkUrl(background.id);
    if (failedRefs.has(background.id)) {
      renderGuideBackgroundFallback(surface, image, poster, 'error');
      return;
    }
    if (isCurrentGuideBackgroundSource(image, background.id, generationText, artworkUrl)) {
      return;
    }
    startGuideBackgroundRequest({
      surface,
      image,
      info,
      artwork: background,
      fallbackPoster: poster,
      presentationGeneration,
    });
    return;
  }

  renderGuideBackgroundFallback(surface, image, poster, guideBackgroundCause(background, nowMs));
}

function renderGuideBackgroundFallback(
  surface: HTMLElement,
  image: HTMLImageElement,
  poster: ArtworkRef | null,
  cause: GuideBackgroundCause,
): void {
  clearGuideBackgroundImage(image);
  setGuideBackgroundState(
    surface,
    image,
    poster === null && cause === 'error' ? 'error' : poster === null ? 'missing' : 'poster-fallback',
    poster === null ? 'theme' : 'poster',
  );
  surface.dataset.backgroundCause = cause;
}

function startGuideBackgroundRequest(input: {
  surface: HTMLElement;
  image: HTMLImageElement;
  info: NonNullable<RouteWorkflowViewModel['guide']['infoPanel']>;
  artwork: ArtworkRef;
  fallbackPoster: ArtworkRef | null;
  presentationGeneration: number;
}): void {
  const { surface, image, artwork, fallbackPoster, presentationGeneration } = input;
  const generationText = String(presentationGeneration);
  const artworkUrl = guideArtworkUrl(artwork.id);
  clearGuideBackgroundImage(image);
  image.dataset.artworkRefId = artwork.id;
  image.dataset.artworkGeneration = generationText;
  image.dataset.backgroundSource = 'background';
  image.alt = '';
  image.decoding = 'async';
  image.draggable = false;
  setGuideBackgroundState(surface, image, 'loading', 'background');
  delete surface.dataset.backgroundCause;
  const request: GuideBackgroundRequest = Object.freeze({
    refId: artwork.id,
    generationText,
    artworkUrl,
  });
  pendingBackground.set(image, request);
  image.onload = () => {
    if (!isPendingGuideBackground(image, request)) return;
    pendingBackground.delete(image);
    image.onload = null;
    image.onerror = null;
    setGuideBackgroundState(surface, image, 'available', 'background');
  };
  image.onerror = () => {
    if (!isPendingGuideBackground(image, request)) return;
    pendingBackground.delete(image);
    image.onload = null;
    image.onerror = null;
    failedBackgroundForGeneration(image, presentationGeneration).add(artwork.id);
    renderGuideBackgroundFallback(surface, image, fallbackPoster, 'error');
  };
  image.src = artworkUrl;
}

function failedBackgroundForGeneration(
  image: HTMLImageElement,
  presentationGeneration: number,
): Set<string> {
  const current = failedBackground.get(image);
  if (current?.presentationGeneration === presentationGeneration) return current.refIds;
  const next = { presentationGeneration, refIds: new Set<string>() };
  failedBackground.set(image, next);
  return next.refIds;
}

function isCurrentGuideBackgroundSource(
  image: HTMLImageElement,
  refId: string,
  generationText: string,
  artworkUrl: string,
): boolean {
  return image.dataset.artworkRefId === refId &&
    image.dataset.artworkGeneration === generationText &&
    image.dataset.backgroundSource === 'background' &&
    image.getAttribute('src') === artworkUrl;
}

function isPendingGuideBackground(
  image: HTMLImageElement,
  request: GuideBackgroundRequest,
): boolean {
  return pendingBackground.get(image) === request &&
    isCurrentGuideBackgroundSource(
      image,
      request.refId,
      request.generationText,
      request.artworkUrl,
    );
}

function clearGuideBackgroundImage(image: HTMLImageElement): void {
  pendingBackground.delete(image);
  image.onload = null;
  image.onerror = null;
  image.removeAttribute('src');
  image.alt = '';
  image.hidden = true;
  delete image.dataset.artworkRefId;
  delete image.dataset.artworkGeneration;
  delete image.dataset.backgroundSource;
}

function setGuideBackgroundState(
  surface: HTMLElement,
  image: HTMLImageElement,
  state: GuideBackgroundState,
  source: 'background' | 'poster' | 'theme',
): void {
  surface.dataset.backgroundState = state;
  surface.dataset.backgroundSource = source;
  if (source === 'poster') surface.dataset.backgroundFallback = 'poster';
  else if (source === 'theme') surface.dataset.backgroundFallback = 'theme';
  else delete surface.dataset.backgroundFallback;
  image.hidden = state !== 'available';
}

function guideBackgroundCause(
  artwork: ArtworkRef | null,
  nowMs: number,
): GuideBackgroundCause {
  if (artwork === null || !isSafeArtworkRefId(artwork.id)) return 'missing';
  if (artwork.status === 'placeholder') return 'placeholder';
  if (!Number.isFinite(artwork.expiresAtMs) || artwork.expiresAtMs <= nowMs) return 'expired';
  return 'missing';
}

function isValidGuideArtworkRef(
  artwork: ArtworkRef | null,
  kind: ArtworkRef['kind'],
  nowMs: number,
): artwork is ArtworkRef {
  return artwork !== null &&
    artwork.status === 'available' &&
    artwork.kind === kind &&
    Number.isFinite(artwork.expiresAtMs) &&
    artwork.expiresAtMs > nowMs &&
    isSafeArtworkRefId(artwork.id);
}

function guideArtworkUrl(refId: string): string {
  return `lineup://shell/artwork/${encodeURIComponent(refId)}`;
}

function isPendingArtwork(
  image: HTMLImageElement,
  request: object,
  refId: string,
  generationText: string,
  artworkUrl: string,
): boolean {
  return pendingArtwork.get(image) === request &&
    image.dataset.artworkRefId === refId &&
    image.dataset.artworkGeneration === generationText &&
    image.getAttribute('src') === artworkUrl;
}

function clearGuideArtworkImage(image: HTMLImageElement): void {
  pendingArtwork.delete(image);
  image.onload = null;
  image.onerror = null;
  image.removeAttribute('src');
  image.alt = '';
  delete image.dataset.artworkRefId;
  delete image.dataset.artworkGeneration;
}

function setArtworkState(
  figure: HTMLElement,
  image: HTMLImageElement,
  placeholder: HTMLElement,
  state: 'missing' | 'loading' | 'available' | 'error',
): void {
  figure.dataset.artworkState = state;
  image.hidden = state !== 'available';
  placeholder.hidden = state === 'available';
}

function clampArtworkAlt(value: string): string {
  return value.slice(0, 160);
}

function readyGuideGridDom(
  view: RouteWorkflowViewModel,
  trackWidth: number,
  previewBadgesEnabled: boolean,
  virtualRange: GuideVirtualRange,
  completeRowInterval: GuideCompleteRowInterval,
  rowOuterSize: number,
  rowGapSize: number,
): HTMLElement[] {
  const header = document.createElement('div');
  header.className = 'epg-time-header';
  header.setAttribute('role', 'row');
  const channelHeader = document.createElement('span');
  channelHeader.setAttribute('role', 'columnheader');
  channelHeader.setAttribute('aria-label', 'Channel');
  header.append(channelHeader);

  const slotTrack = document.createElement('div');
  slotTrack.className = 'epg-time-header-slots';

  const slotWidth = trackWidth / view.guide.slots.length;
  view.guide.slots.forEach((slot, index) => {
    const label = document.createElement('span');
    label.className = 'epg-time-slot';
    label.setAttribute('role', 'columnheader');
    label.style.position = 'absolute';
    label.style.left = `${toTrackPercent(index * slotWidth, trackWidth)}%`;
    label.style.width = `${toTrackPercent(slotWidth, trackWidth)}%`;
    label.textContent = slot.label;
    slotTrack.append(label);
  });

  // Render current-time marker in header if within window
  const nowMs = view.guide.nowMs;
  const windowStartMs = view.guide.windowStartMs;
  const windowEndMs = view.guide.windowEndMs;
  const totalDuration = windowEndMs - windowStartMs;
  let hasMarker = false;
  let markerLeft = 0;

  if (nowMs >= windowStartMs && nowMs <= windowEndMs && totalDuration > 0) {
    markerLeft = ((nowMs - windowStartMs) / totalDuration) * trackWidth;
    hasMarker = true;

    const marker = document.createElement('div');
    marker.className = 'epg-current-time-marker';
    marker.dataset.currentTimeMarker = 'true';
    marker.setAttribute('aria-hidden', 'true');
    marker.style.left = `${toTrackPercent(markerLeft, trackWidth)}%`;
    const markerLabel = document.createElement('span');
    markerLabel.className = 'epg-current-time-marker-label';
    markerLabel.textContent = 'NOW';
    marker.append(markerLabel);
    slotTrack.append(marker);
  }

  header.append(slotTrack);

  const rows: HTMLElement[] = [];
  for (const placement of virtualRange.rowPlacements) {
    if (placement.gapBefore > 0) {
      rows.push(guideRowSpacer(placement.gapBefore * rowOuterSize - rowGapSize));
    }
    const rowIndex = placement.rowIndex;
    const row = view.guide.rows.find((candidate, localIndex) =>
      (candidate.absoluteIndex ?? view.guide.channelWindow.offset + localIndex) === rowIndex);
    if (row === undefined) continue;
    const rowElement = document.createElement('section');
    rowElement.className = 'epg-grid__row';
    rowElement.dataset.guideRowIndex = String(rowIndex);
    const completeVisible = rowIndex >= completeRowInterval.start &&
      rowIndex < completeRowInterval.start + completeRowInterval.count;
    rowElement.dataset.guideRowBuffer = String(!completeVisible);
    rowElement.inert = !completeVisible;
    if (!completeVisible) rowElement.className += ' epg-grid__row--buffer';
    if (row.loadState !== undefined && row.loadState !== 'ready') {
      rowElement.className += ' epg-grid__row--placeholder';
      rowElement.dataset.guideRowState = row.loadState;
      rowElement.setAttribute('aria-hidden', !completeVisible || row.loadState === 'loading' ? 'true' : 'false');
      if (row.loadState === 'loading') {
        const loading = document.createElement('span');
        loading.className = 'epg-grid__row-status';
        loading.textContent = 'Loading channel…';
        rowElement.append(loading);
      } else {
        const retry = document.createElement('button');
        retry.type = 'button';
        retry.className = 'epg-grid__row-status';
        retry.dataset.guideAction = 'retry';
        retry.dataset.guideRetryIndex = String(rowIndex);
        retry.dataset.focusId = `guide-window-retry-${String(rowIndex)}`;
        retry.textContent = 'Channel unavailable — Retry';
        rowElement.append(retry);
      }
      rows.push(rowElement);
      continue;
    }
    if (!completeVisible) rowElement.setAttribute('aria-hidden', 'true');
    rowElement.setAttribute('role', 'row');
    rowElement.setAttribute('aria-selected', String(row.isSelected));
    rowElement.dataset.selectedChannel = String(row.isSelected);
    rowElement.dataset.currentChannel = String(row.isNowWatching);
    rowElement.dataset.tunedChannel = String(row.isNowWatching);
    const channel = document.createElement('div');
    channel.className = 'epg-grid__channel';
    channel.dataset.channelCurrent = String(row.isNowWatching);
    channel.dataset.channelTuned = String(row.isNowWatching);
    channel.setAttribute('role', 'rowheader');
    channel.setAttribute(
      'aria-label',
      `${row.number} - ${row.name}${row.isNowWatching ? ' — Live, tuned' : ''}`,
    );
    const number = document.createElement('strong');
    number.textContent = row.number;
    const name = document.createElement('span');
    name.textContent = row.name;
    channel.append(number, name);
    rowElement.append(channel);

    const programs = document.createElement('div');
    programs.className = 'epg-grid__programs';

    for (const program of row.programs) {
      if (!virtualRange.programIds.has(program.id)) continue;
      const cell = guideCellDom(
        program,
        windowStartMs,
        windowEndMs,
        trackWidth,
        previewBadgesEnabled,
      );
      if (program.endsAtMs <= windowStartMs || program.startsAtMs >= windowEndMs) {
        projectBufferedGuideCell(cell, program.endsAtMs <= windowStartMs ? 'before' : 'after');
      }
      programs.append(cell);
    }

    if (hasMarker) {
      const line = document.createElement('div');
      line.className = 'epg-current-time-line';
      line.dataset.currentTimeMarker = 'true';
      line.setAttribute('aria-hidden', 'true');
      line.style.left = `${toTrackPercent(markerLeft, trackWidth)}%`;
      programs.append(line);
    }

    rowElement.append(programs);
    rows.push(rowElement);
  }
  if (virtualRange.trailingRows > 0) {
    rows.push(guideRowSpacer(virtualRange.trailingRows * rowOuterSize - rowGapSize));
  }

  return [header, ...rows];
}

function projectBufferedGuideCell(cell: HTMLElement, side: 'before' | 'after'): void {
  delete cell.dataset.guideProgramAction;
  delete cell.dataset.focusId;
  cell.tabIndex = -1;
  cell.setAttribute('aria-hidden', 'true');
  cell.removeAttribute('role');
  (cell as HTMLButtonElement).disabled = true;
  cell.style.left = side === 'before' ? '-1px' : '100%';
  cell.style.width = '0px';
}

function parseGuideRowIndex(value: string | undefined): number | null {
  if (value === undefined || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

function readGuideRowStartOffset(grid: HTMLElement, fallbackRowOuterSize: number): number | null {
  return readGuideRowLayout(grid, fallbackRowOuterSize)?.rowStartOffset ?? null;
}

function readGuideRowLayout(
  grid: HTMLElement,
  fallbackRowOuterSize: number,
): Readonly<{ rowStartOffset: number; rowGap: number | null }> | null {
  if (typeof grid.querySelectorAll !== 'function') return null;
  const rows = Array.from(grid.querySelectorAll<HTMLElement>('.epg-grid__row'));
  const row = rows[0];
  const rowIndex = parseGuideRowIndex(row?.dataset.guideRowIndex);
  const rowRect = row?.getBoundingClientRect?.();
  if (row === undefined || rowIndex === null || rowRect === undefined) return null;
  const gridRect = grid.getBoundingClientRect?.();
  if (gridRect === undefined) return null;
  const nextRow = rows.find((candidate) => parseGuideRowIndex(candidate.dataset.guideRowIndex) === rowIndex + 1);
  const nextRect = nextRow?.getBoundingClientRect?.();
  const measuredStride = nextRect === undefined ? null : nextRect.top - rowRect.top;
  const rowOuterSize = measuredStride !== null && Number.isFinite(measuredStride) && measuredStride > 0
    ? measuredStride
    : fallbackRowOuterSize;
  const computedGap = readGuideRowGap(row);
  const rowGap = computedGap ?? (
    measuredStride !== null && Number.isFinite(measuredStride) && measuredStride >= rowRect.height
      ? Math.max(0, measuredStride - rowRect.height)
      : null
  );
  const scrollTop = Number.isFinite(grid.scrollTop) ? Math.max(0, grid.scrollTop) : 0;
  return {
    rowStartOffset: Math.max(0, rowRect.top - gridRect.top + scrollTop - rowIndex * rowOuterSize),
    rowGap,
  };
}

function readGuideViewportMetrics(grid: HTMLElement, rowStartOffset = 0): GuideViewportMetrics {
  const view = grid.ownerDocument?.defaultView;
  const globalWindow = typeof window === 'undefined' ? undefined : window;
  const availableHeight = Math.max(0, grid.clientHeight - Math.max(0, rowStartOffset));
  return {
    width: view?.innerWidth ?? globalWindow?.innerWidth ?? grid.clientWidth,
    height: view?.innerHeight ?? globalWindow?.innerHeight ?? grid.clientHeight,
    devicePixelRatio: view?.devicePixelRatio ?? globalWindow?.devicePixelRatio ?? 1,
    availableWidth: grid.clientWidth,
    availableHeight: grid.clientHeight > 0 ? availableHeight : undefined,
  };
}

function readGuideRowGap(row: HTMLElement): number | null {
  const parent = row.parentElement;
  const view = row.ownerDocument?.defaultView;
  if (parent === null || parent === undefined || view === null || view === undefined) return null;
  const value = Number.parseFloat(view.getComputedStyle(parent).rowGap);
  return Number.isFinite(value) && value >= 0 ? value : null;
}

function guideRowSpacer(height: number): HTMLElement {
  const spacer = document.createElement('div');
  spacer.className = 'epg-grid__row-spacer';
  spacer.setAttribute('aria-hidden', 'true');
  spacer.style.height = `${String(Math.max(0, height))}px`;
  return spacer;
}

function stateActionsFor(
  state: RouteWorkflowViewModel['guide']['presentationState'],
): readonly { id: 'back' | 'setup' | 'refresh' | 'retry'; label: string }[] {
  switch (state) {
    case 'loading':
      return [{ id: 'back', label: 'Back' }];
    case 'empty-channels':
      return [{ id: 'setup', label: 'Set up channels' }, { id: 'back', label: 'Back' }];
    case 'empty-programs':
      return [
        { id: 'refresh', label: 'Refresh' },
        { id: 'setup', label: 'Edit lineup' },
        { id: 'back', label: 'Back' },
      ];
    case 'error':
      return [{ id: 'retry', label: 'Retry' }, { id: 'back', label: 'Back' }];
    case 'ready':
      return [{ id: 'setup', label: 'Edit lineup' }];
  }
}

function toTrackPercent(value: number, trackWidth: number): number {
  if (!Number.isFinite(value) || !Number.isFinite(trackWidth) || trackWidth <= 0) {
    return 0;
  }
  const percent = Math.max(0, Math.min(100, (value / trackWidth) * 100));
  return Math.round(percent * 1_000_000) / 1_000_000;
}
