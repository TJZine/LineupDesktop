import type { PlayerSnapshot } from '../contracts/player.js';
import { formatEpgTimeWindow } from './epg.js';
import type { ChannelRuntimeRendererState } from './channelRuntimeState.js';
import type { RendererDomBindings } from './domBindings.js';
import { readClosestRouteId, readRouteActionId, readRouteId } from './domBindings.js';
import {
  createPlayerOverlayView,
  type PlaybackOptionTrackViewModel,
  type PlayerOverlayState,
} from './overlays.js';
import {
  getRouteWorkflowView,
  type RouteWorkflowViewModel,
  type WorkflowState,
} from './workflow.js';
import type { ChannelSetupLiveSelectionViewModel } from './channelSetup/viewModel.js';
import { renderChannelSetupDom } from './channelSetup/dom.js';

export function renderRouteDom(
  workflowState: WorkflowState,
  dom: RendererDomBindings,
  channelRuntime?: ChannelRuntimeRendererState,
  liveSelection: ChannelSetupLiveSelectionViewModel | null = null,
): void {
  const activeRoute = workflowState.routeState.activeRoute;
  const view = getRouteWorkflowView(workflowState, channelRuntime, liveSelection);
  document.documentElement.dataset.activeRoute = activeRoute;
  if (dom.routeTitleElement) {
    dom.routeTitleElement.textContent = view.title;
  }
  if (dom.routeStatusElement) {
    dom.routeStatusElement.textContent = view.statusText;
  }

  for (const button of dom.routeButtons) {
    const route = readRouteId(button.dataset.routeButton);
    const isActive = route === activeRoute;
    button.classList.toggle('is-active', isActive);
    if (isActive) {
      button.setAttribute('aria-current', 'page');
    } else {
      button.removeAttribute('aria-current');
    }
  }

  for (const screen of dom.screens) {
    const isActive = screen.dataset.screen === activeRoute;
    screen.hidden = !isActive;
    screen.classList.toggle('screen--active', isActive);
    screen.dataset.workflowTone = isActive ? view.tone : '';
  }
}

export function renderWorkflowDom(
  workflowState: WorkflowState,
  overlayState: PlayerOverlayState,
  playerSnapshot: PlayerSnapshot,
  dom: RendererDomBindings,
  channelRuntime?: ChannelRuntimeRendererState,
  liveSelection: ChannelSetupLiveSelectionViewModel | null = null,
): void {
  const view = getRouteWorkflowView(workflowState, channelRuntime, liveSelection);

  setText(`[data-workflow-kicker="${view.route}"]`, view.kicker);
  setText(`[data-workflow-primary="${view.route}"]`, view.primaryText);
  setText(`[data-workflow-secondary="${view.route}"]`, view.secondaryText);

  if (dom.currentChannelElement) {
    dom.currentChannelElement.textContent = view.currentProgram.channelName;
  }
  if (dom.currentProgramElement) {
    dom.currentProgramElement.textContent = `${view.currentProgram.title} - ${view.currentProgram.subtitle}`;
  }
  if (dom.currentWindowElement) {
    dom.currentWindowElement.textContent = formatEpgTimeWindow(
      view.currentProgram.startsAtMs,
      view.currentProgram.endsAtMs,
    );
  }

  renderChannelList(view, dom);
  renderEpgGuideDom(view, dom);
  renderPlayerOverlaysDom(overlayState, playerSnapshot, dom, view.route);
  renderSettingsDom(view, dom);
  renderChannelSetupDom(view, dom, liveSelection);
  renderRouteActionButtons(view, dom);
}

function renderChannelList(view: RouteWorkflowViewModel, dom: RendererDomBindings): void {
  if (!dom.channelListElement) {
    return;
  }
  dom.channelListElement.replaceChildren(
    ...view.channels.map((channel) => {
      const item = document.createElement('article');
      item.className = 'channel-list__item';
      const number = document.createElement('span');
      number.className = 'channel-list__number';
      number.textContent = channel.number;
      const copy = document.createElement('div');
      const title = document.createElement('strong');
      title.textContent = channel.name;
      const detail = document.createElement('p');
      detail.textContent = `${channel.currentTitle} next: ${channel.nextTitle}`;
      copy.append(title, detail);
      item.append(number, copy);
      return item;
    }),
  );
}

function renderSettingsDom(view: RouteWorkflowViewModel, dom: RendererDomBindings): void {
  if (dom.settingsSourceElement) {
    dom.settingsSourceElement.textContent = view.settings.libraryName;
  }
  if (dom.settingsChannelsElement) {
    dom.settingsChannelsElement.textContent = String(view.settings.channelCount);
  }
  if (dom.settingsStateElement) {
    dom.settingsStateElement.textContent = `${view.settings.setupState}; ${view.settings.recoveryDetail}`;
  }
  if (dom.settingsSectionsElement) {
    dom.settingsSectionsElement.replaceChildren(
      ...view.settings.sections.map((section) => {
        const article = document.createElement('article');
        article.className = 'settings-section';
        const title = document.createElement('h3');
        title.textContent = section.title;
        const detail = document.createElement('p');
        detail.textContent = section.detail;
        const list = document.createElement('dl');
        for (const setting of section.items) {
          const row = document.createElement('div');
          const label = document.createElement('dt');
          label.textContent = setting.label;
          const value = document.createElement('dd');
          value.textContent = `${setting.valueLabel} - ${setting.description}`;
          row.append(label, value);
          list.append(row);
        }
        article.append(title, detail, list);
        return article;
      }),
    );
  }
}

function renderRouteActionButtons(view: RouteWorkflowViewModel, dom: RendererDomBindings): void {
  for (const button of dom.routeActionButtons) {
    const action = readRouteActionId(button.dataset.routeAction);
    const route = readClosestRouteId(button);
    const viewAction =
      action === null || route === null || route !== view.route
        ? null
        : view.actions.find((candidate) => candidate.id === action);
    if (viewAction !== undefined && viewAction !== null) {
      button.textContent = viewAction.label;
    }
  }
}

function setText(selector: string, value: string): void {
  const element = document.querySelector<HTMLElement>(selector);
  if (element) {
    element.textContent = value;
  }
}

function renderEpgGuideDom(view: RouteWorkflowViewModel, dom: RendererDomBindings): void {
  const selectedRow = view.guide.rows.find((row) => row.id === view.guide.selectedProgram.channelId);
  if (dom.epgDetailChannelElement) {
    dom.epgDetailChannelElement.textContent =
      selectedRow === undefined ? '' : `${selectedRow.number} ${selectedRow.name}`;
  }
  if (dom.epgDetailTitleElement) {
    dom.epgDetailTitleElement.textContent = view.guide.selectedProgram.title;
  }
  if (dom.epgDetailTimeElement) {
    dom.epgDetailTimeElement.textContent = `${view.guide.selectedProgram.subtitle} - ${formatEpgTimeWindow(
      view.guide.selectedProgram.startsAtMs,
      view.guide.selectedProgram.endsAtMs,
    )}`;
  }

  if (!dom.epgGridElement) {
    return;
  }

  const header = document.createElement('div');
  header.className = 'epg-grid__header';
  header.append(document.createElement('span'));
  const slotTrack = document.createElement('div');
  slotTrack.className = 'epg-grid__slots';
  for (const slot of view.guide.slots) {
    const label = document.createElement('span');
    label.textContent = slot.label;
    slotTrack.append(label);
  }
  header.append(slotTrack);

  const rows = view.guide.rows.map((row) => {
    const rowElement = document.createElement('section');
    rowElement.className = 'epg-grid__row';
    rowElement.dataset.selectedChannel = String(row.isSelected);
    const channel = document.createElement('div');
    channel.className = 'epg-grid__channel';
    const number = document.createElement('strong');
    number.textContent = row.number;
    const name = document.createElement('span');
    name.textContent = row.name;
    channel.append(number, name);
    rowElement.append(channel);

    const programs = document.createElement('div');
    programs.className = 'epg-grid__programs';
    for (const program of row.programs) {
      const cell = document.createElement('article');
      cell.className = 'epg-grid__program';
      cell.dataset.selectedProgram = String(program.isSelected);
      cell.style.gridColumn = `${program.columnStart} / span ${program.columnSpan}`;
      const title = document.createElement('strong');
      title.textContent = program.title;
      const subtitle = document.createElement('span');
      subtitle.textContent = program.subtitle;
      cell.append(title, subtitle);
      programs.append(cell);
    }
    rowElement.append(programs);
    return rowElement;
  });

  dom.epgGridElement.replaceChildren(header, ...rows);
}

function renderPlayerOverlaysDom(
  overlayState: PlayerOverlayState,
  playerSnapshot: PlayerSnapshot,
  dom: RendererDomBindings,
  activeRoute: RouteWorkflowViewModel['route'],
): void {
  const view = createPlayerOverlayView(overlayState, playerSnapshot);
  const isPlayerRoute = activeRoute === 'player';
  document.documentElement.dataset.activeOverlay = isPlayerRoute ? (view.activeOverlayId ?? '') : '';

  for (const element of dom.overlayElements) {
    const overlayId = element.dataset.overlay;
    const isVisible =
      isPlayerRoute &&
      (overlayId === 'playerOsd' ||
        overlayId === 'nowPlaying' ||
        overlayId === 'miniGuide' ||
        overlayId === 'channelNumber' ||
        overlayId === 'channelBadge' ||
        overlayId === 'playbackOptions')
        ? view.visibleOverlays[overlayId]
        : false;
    element.hidden = !isVisible;
    element.setAttribute('aria-hidden', String(!isVisible));
    element.dataset.overlayActive = String(isPlayerRoute && overlayId === view.activeOverlayId);
  }

  for (const button of dom.overlayActionButtons) {
    button.disabled = !isPlayerRoute;
  }

  if (dom.overlayStackElement) {
    dom.overlayStackElement.hidden = !isPlayerRoute;
    dom.overlayStackElement.setAttribute('aria-hidden', String(!isPlayerRoute));
    dom.overlayStackElement.dataset.overlayRouteActive = String(isPlayerRoute);
    dom.overlayStackElement.dataset.overlayStack = isPlayerRoute ? view.stack.join(',') : '';
  }
  if (dom.overlayNowPlayingTitleElement) {
    dom.overlayNowPlayingTitleElement.textContent = view.nowPlaying.title;
  }
  if (dom.overlayNowPlayingSubtitleElement) {
    dom.overlayNowPlayingSubtitleElement.textContent = view.nowPlaying.subtitle;
  }
  if (dom.overlayNowPlayingChannelElement) {
    dom.overlayNowPlayingChannelElement.textContent = `${view.nowPlaying.channelNumber} ${view.nowPlaying.channelName}`;
  }
  if (dom.overlayNowPlayingStatusElement) {
    dom.overlayNowPlayingStatusElement.textContent = `${view.nowPlaying.statusLabel} ${view.nowPlaying.positionLabel} / ${view.nowPlaying.durationLabel}`;
  }
  if (dom.overlayProgressElement) {
    dom.overlayProgressElement.style.setProperty(
      '--overlay-progress',
      `${view.nowPlaying.progressPercent}%`,
    );
    dom.overlayProgressElement.setAttribute('aria-valuenow', String(view.nowPlaying.progressPercent));
  }
  if (dom.overlayMiniGuideElement) {
    dom.overlayMiniGuideElement.replaceChildren(
      ...view.miniGuideChannels.map((channel) => {
        const item = document.createElement('article');
        item.className = 'mini-guide__item';
        item.dataset.selectedChannel = String(channel.selected);
        const number = document.createElement('strong');
        number.textContent = channel.number;
        const copy = document.createElement('div');
        const name = document.createElement('span');
        name.textContent = channel.name;
        const title = document.createElement('p');
        title.textContent = `${channel.currentTitle} next: ${channel.nextTitle}`;
        copy.append(name, title);
        item.append(number, copy);
        return item;
      }),
    );
  }
  if (dom.overlayChannelNumberElement) {
    dom.overlayChannelNumberElement.textContent = view.channelNumberDisplay;
  }
  if (dom.overlayChannelBadgeNumberElement) {
    dom.overlayChannelBadgeNumberElement.textContent = view.channelBadge.number;
  }
  if (dom.overlayChannelBadgeNameElement) {
    dom.overlayChannelBadgeNameElement.textContent = view.channelBadge.name;
  }
  if (dom.overlayChannelBadgeProgramElement) {
    dom.overlayChannelBadgeProgramElement.textContent = view.channelBadge.currentTitle;
  }
  if (dom.overlayAudioLabelElement) {
    dom.overlayAudioLabelElement.textContent = view.playbackOptions.selectedAudioLabel;
  }
  if (dom.overlaySubtitleLabelElement) {
    dom.overlaySubtitleLabelElement.textContent = view.playbackOptions.selectedSubtitleLabel;
  }
  if (dom.overlayVolumeLabelElement) {
    dom.overlayVolumeLabelElement.textContent = view.playbackOptions.muted
      ? 'Muted'
      : `${view.playbackOptions.volumePercent}%`;
  }
  if (dom.overlayRateLabelElement) {
    dom.overlayRateLabelElement.textContent = view.playbackOptions.playbackRateLabel;
  }
  if (dom.overlayPlaybackSummaryElement) {
    dom.overlayPlaybackSummaryElement.textContent = view.playbackOptions.playbackSummary;
  }
  renderPlaybackOptionRows(dom.overlayAudioOptionsElement, view.playbackOptions.audioTracks);
  renderPlaybackOptionRows(dom.overlaySubtitleOptionsElement, view.playbackOptions.subtitleTracks);
}

function renderPlaybackOptionRows(
  host: HTMLElement | null,
  tracks: readonly PlaybackOptionTrackViewModel[],
): void {
  if (!host) {
    return;
  }
  host.replaceChildren(
    ...tracks.map((track) => {
      const row = document.createElement('div');
      row.className = 'playback-options__row';
      row.dataset.selected = String(track.selected);
      row.dataset.available = String(track.available);
      const label = document.createElement('strong');
      label.textContent = track.label;
      const meta = document.createElement('span');
      meta.textContent = track.meta;
      const state = document.createElement('em');
      state.textContent = track.stateLabel;
      row.append(label, meta, state);
      return row;
    }),
  );
}
