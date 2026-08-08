import type { RendererDomBindings } from '../domBindings.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { DesktopSettingsValues } from '../../contracts/settings.js';
import {
  formatEpgTimeWindow,
  type EpgProgramCellViewModel,
} from '../epg.js';
import { isSafeArtworkRefId } from '../../contracts/artwork.js';
import type { GuideLibraryFilterState } from '../../contracts/guide.js';
import { projectGuideVirtualRange, type GuideVirtualRange } from '../guideVirtualization.js';

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

export function renderEpgGuideDom(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  settings: Pick<DesktopSettingsValues,
    'guideDensity' |
    'previewBadgesEnabled' |
    'libraryTabsEnabled' |
    'nowWatchingBannerEnabled' |
    'guideLayout'> = {
    guideDensity: 'comfortable',
    previewBadgesEnabled: true,
    libraryTabsEnabled: true,
    nowWatchingBannerEnabled: true,
    guideLayout: 'classic',
  },
): void {
  const selectedRow = view.guide.selectedProgram === null
    ? undefined
    : view.guide.rows.find((row) => row.id === view.guide.selectedProgram?.channelId);
  if (dom.epgDetailChannelElement) {
    dom.epgDetailChannelElement.textContent =
      selectedRow === undefined ? '' : `${selectedRow.number} - ${selectedRow.name}`;
  }
  if (dom.epgDetailTitleElement) {
    dom.epgDetailTitleElement.textContent =
      (view.guide.infoPanel?.title ?? view.guide.state.label).slice(0, 160);
  }
  if (dom.epgDetailTimeElement) {
    dom.epgDetailTimeElement.textContent = view.guide.infoPanel === null ? view.guide.state.detail : [
      view.guide.infoPanel.eyebrow,
      view.guide.infoPanel.subtitle,
      view.guide.infoPanel.timeLabel,
      settings.previewBadgesEnabled ? view.guide.infoPanel.badges.join(' / ') : '',
      view.guide.infoPanel.genres,
    ].filter(Boolean).join(' - ');
  }
  if (dom.epgDetailDescriptionElement) {
    dom.epgDetailDescriptionElement.textContent =
      (view.guide.infoPanel?.description ?? '').slice(0, 600);
  }
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
  shell.dataset.epgLayout = settings.guideLayout;
  shell.dataset.guideDensity = settings.guideDensity;
  dom.epgGridElement.dataset.guideDensity = settings.guideDensity;

  const classicHeader = document.createElement('header');
  classicHeader.className = 'epg-classic-header';
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
    const metricsKey = `${settings.guideDensity}:${settings.guideLayout}`;
    const cachedMetrics = guideLayoutMetrics.get(dom.epgGridElement);
    const canReuse = cachedMetrics?.key === metricsKey && cachedMetrics.measured;
    const measuredRows = !canReuse && typeof dom.epgGridElement.querySelectorAll === 'function'
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
    const rowOuterSize = canReuse
      ? cachedMetrics.rowOuterSize
      : measuredStride !== null && Number.isFinite(measuredStride) && measuredStride > 0
        ? measuredStride
        : hasMeasurement && computedGap !== null
          ? (measuredRow ?? 0) + computedGap
          : 120;
    const rowGapSize = canReuse
      ? cachedMetrics.rowGapSize
      : hasMeasurement ? Math.max(0, rowOuterSize - (measuredRow ?? rowOuterSize)) : 0;
    const gridTop = rowElement === null ? 0 : dom.epgGridElement.getBoundingClientRect().top;
    const rowStartOffset = canReuse
      ? cachedMetrics.rowStartOffset
      : rowRect === undefined || representedRowIndex === null
        ? 0
        : Math.max(0, rowRect.top - gridTop + dom.epgGridElement.scrollTop - representedRowIndex * rowOuterSize);
    guideLayoutMetrics.set(dom.epgGridElement, {
      key: metricsKey,
      rowOuterSize,
      rowGapSize,
      rowStartOffset,
      measured: canReuse || hasMeasurement,
    });
    const focusedRowIndex = view.guide.selectedProgram === null
      ? -1
      : view.guide.rows.findIndex((row) => row.id === view.guide.selectedProgram?.channelId);
    const virtualRange = projectGuideVirtualRange({
      rows: view.guide.rows,
      scrollTop: dom.epgGridElement.scrollTop,
      viewportHeight: dom.epgGridElement.clientHeight || rowOuterSize * 6,
      rowOuterSize,
      rowStartOffset,
      windowStartMs: view.guide.windowStartMs,
      windowEndMs: view.guide.windowEndMs,
      focusedRowIndex,
      focusedProgramId: view.guide.selectedProgram?.id ?? null,
    });
    shell.append(...readyGuideGridDom(
      view,
      trackWidth,
      settings.previewBadgesEnabled,
      virtualRange,
      rowOuterSize,
      rowGapSize,
    ));
  }
  dom.epgGridElement.replaceChildren(shell);
}

export function renderGuideDetailArtwork(
  view: RouteWorkflowViewModel,
  dom: Pick<RendererDomBindings,
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
  const artwork = info?.artwork ?? null;
  const nowMs = view.guide.nowMs;
  if (
    info === null ||
    artwork === null ||
    artwork.status === 'placeholder' ||
    artwork.expiresAtMs <= nowMs ||
    artwork.kind !== 'poster' ||
    !isSafeArtworkRefId(artwork.id)
  ) {
    placeholder.textContent = 'Artwork unavailable';
    clearGuideArtworkImage(image);
    failedArtwork.delete(image);
    setArtworkState(figure, image, placeholder, 'missing');
    return;
  }
  const failed = failedArtwork.get(image);
  if (
    failed?.presentationGeneration === info.presentationGeneration &&
    failed.refId === artwork.id
  ) {
    placeholder.textContent = 'Artwork unavailable';
    clearGuideArtworkImage(image);
    setArtworkState(figure, image, placeholder, 'error');
    return;
  }
  const generationText = String(info.presentationGeneration);
  if (
    image.dataset.artworkRefId === artwork.id &&
    image.dataset.artworkGeneration === generationText &&
    image.getAttribute('src') !== null
  ) return;
  image.onload = null;
  image.onerror = null;
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
  const artworkUrl = `lineup://shell/artwork/${encodeURIComponent(artwork.id)}`;
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
    marker.style.left = `${toTrackPercent(markerLeft, trackWidth)}%`;
    slotTrack.append(marker);
  }

  header.append(slotTrack);

  const rows: HTMLElement[] = [];
  for (const placement of virtualRange.rowPlacements) {
    if (placement.gapBefore > 0) {
      rows.push(guideRowSpacer(placement.gapBefore * rowOuterSize - rowGapSize));
    }
    const rowIndex = placement.rowIndex;
    const row = view.guide.rows[rowIndex];
    if (row === undefined) continue;
    const rowElement = document.createElement('section');
    rowElement.className = 'epg-grid__row';
    rowElement.dataset.guideRowIndex = String(rowIndex);
    rowElement.setAttribute('role', 'row');
    rowElement.dataset.selectedChannel = String(row.isSelected);
    const channel = document.createElement('div');
    channel.className = 'epg-grid__channel';
    channel.setAttribute('role', 'rowheader');
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
