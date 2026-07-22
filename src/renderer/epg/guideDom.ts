import type { RendererDomBindings } from '../domBindings.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { DesktopSettingsValues } from '../../contracts/settings.js';
import {
  formatEpgTimeWindow,
  type EpgProgramCellViewModel,
} from '../epg.js';

export interface CellPosition {
  left: number;
  width: number;
  isClippedStart: boolean;
  isClippedEnd: boolean;
}

const GUIDE_TRACK_UNITS = 1000;

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

export function renderEpgGuideDom(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  settings: Pick<DesktopSettingsValues, 'guideDensity' | 'previewBadgesEnabled'> = {
    guideDensity: 'comfortable',
    previewBadgesEnabled: true,
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
    dom.epgDetailTitleElement.textContent = view.guide.infoPanel?.title ?? view.guide.state.label;
  }
  if (dom.epgDetailTimeElement) {
    dom.epgDetailTimeElement.textContent = view.guide.infoPanel === null ? view.guide.state.detail : [
      view.guide.infoPanel.eyebrow,
      view.guide.infoPanel.subtitle,
      view.guide.infoPanel.timeLabel,
      settings.previewBadgesEnabled ? view.guide.infoPanel.badges.join(' / ') : '',
      view.guide.infoPanel.genres,
      view.guide.infoPanel.description,
    ].filter(Boolean).join(' - ');
  }

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
  shell.dataset.epgLayout = view.guide.shell.layoutMode;
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
  const nowPlaying = shellNowWatching === null ? null : document.createElement('div');
  if (nowPlaying !== null) {
    nowPlaying.className = 'epg-classic-now-playing';
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

  const nowWatching = shellNowWatching === null ? null : document.createElement('div');
  if (nowWatching !== null && shellNowWatching !== null) {
    nowWatching.className = 'epg-now-watching-banner';
    nowWatching.setAttribute('aria-live', 'polite');
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
  stateElement.append(stateActions);

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

  const rows = view.guide.rows.map((row) => {
    const rowElement = document.createElement('section');
    rowElement.className = 'epg-grid__row';
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
      const cell = guideCellDom(
        program,
        windowStartMs,
        windowEndMs,
        trackWidth,
        settings.previewBadgesEnabled,
      );
      programs.append(cell);
    }

    if (hasMarker) {
      const line = document.createElement('div');
      line.className = 'epg-current-time-line';
      line.style.left = `${toTrackPercent(markerLeft, trackWidth)}%`;
      programs.append(line);
    }

    rowElement.append(programs);
    return rowElement;
  });

  shell.append(classicHeader);
  if (nowWatching !== null) shell.append(nowWatching);
  shell.append(stateElement);
  if (view.guide.presentationState === 'ready') {
    stateElement.hidden = true;
    stateElement.setAttribute('aria-hidden', 'true');
    if (view.guide.tuneError !== null) {
      const actionError = document.createElement('p');
      actionError.className = 'epg-action-error';
      actionError.dataset.guideTuneError = '';
      actionError.setAttribute('role', 'status');
      actionError.textContent = view.guide.tuneError;
      shell.append(actionError);
    }
    shell.append(header, ...rows);
  }
  dom.epgGridElement.replaceChildren(shell);
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
      return [];
  }
}

function toTrackPercent(value: number, trackWidth: number): number {
  if (!Number.isFinite(value) || !Number.isFinite(trackWidth) || trackWidth <= 0) {
    return 0;
  }
  const percent = Math.max(0, Math.min(100, (value / trackWidth) * 100));
  return Math.round(percent * 1_000_000) / 1_000_000;
}
