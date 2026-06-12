import type { PlayerSnapshot } from '../contracts/player.js';
import { formatEpgTimeWindow } from './epg.js';
import type { ChannelRuntimeRendererState } from './channelRuntimeState.js';
import type { RendererDomBindings } from './domBindings.js';
import type { SettingsSectionId } from './settingsSetup.js';
import { readClosestRouteId, readRouteActionId, readRouteId } from './domBindings.js';
import {
  createPlayerOverlayView,
  type PlaybackOptionTrackViewModel,
  type PlayerOverlayPresentationSource,
  type PlayerOverlayState,
} from './overlays.js';
import {
  getRouteWorkflowView,
  type RouteWorkflowViewModel,
  type WorkflowState,
} from './workflow.js';
import type { ChannelSetupLiveSelectionViewModel } from './channelSetup/viewModel.js';
import { renderChannelSetupDom } from './channelSetup/dom.js';
import { DEFAULT_PLAYER_OVERLAY_PRESENTATION } from './overlayViewModels.js';
import { renderSettingsDom } from './settingsSetupDom.js';
import { renderEpgGuideDom } from './epg/guideDom.js';


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
  overlayPresentation: PlayerOverlayPresentationSource = DEFAULT_PLAYER_OVERLAY_PRESENTATION,
  activeSettingsCategory: SettingsSectionId = 'playback',
): void {
  const view = getRouteWorkflowView(workflowState, channelRuntime, liveSelection);

  setText(`[data-workflow-kicker="${view.route}"]`, view.kicker);
  setText(`[data-workflow-primary="${view.route}"]`, view.primaryText);
  setText(`[data-workflow-secondary="${view.route}"]`, view.secondaryText);

  if (dom.currentChannelElement) {
    dom.currentChannelElement.textContent = view.currentProgram.channelName;
  }
  if (dom.currentProgramElement) {
    dom.currentProgramElement.textContent = [
      view.currentProgram.title,
      view.currentProgram.subtitle,
    ].filter((value) => value.length > 0).join(' - ');
  }
  if (dom.currentWindowElement) {
    dom.currentWindowElement.textContent =
      view.currentProgram.startsAtMs === null || view.currentProgram.endsAtMs === null
        ? view.guide.state.detail
        : formatEpgTimeWindow(
          view.currentProgram.startsAtMs,
          view.currentProgram.endsAtMs,
        );
  }

  renderChannelList(view, dom);
  renderEpgGuideDom(view, dom);
  renderPlayerOverlaysDom(overlayState, dom, view.route, {
    ...overlayPresentation,
    playerSnapshot,
  });
  renderSettingsDom(view, dom, activeSettingsCategory);
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



function renderPlayerOverlaysDom(
  overlayState: PlayerOverlayState,
  dom: RendererDomBindings,
  activeRoute: RouteWorkflowViewModel['route'],
  overlayPresentation: PlayerOverlayPresentationSource,
): void {
  const view = createPlayerOverlayView(overlayState, overlayPresentation);
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
    dom.overlayNowPlayingStatusElement.textContent = [
      view.nowPlaying.statusLabel,
      `${view.nowPlaying.positionLabel} / ${view.nowPlaying.durationLabel}`,
      view.nowPlaying.badges.join(' / '),
      view.nowPlaying.playbackSummary,
      view.nowPlaying.upNextText,
      view.nowPlaying.description,
    ].join(' - ');
  }
  if (dom.overlayNowPlayingDescriptionElement) {
    dom.overlayNowPlayingDescriptionElement.textContent = view.nowPlaying.description;
  }
  if (dom.overlayNowPlayingSummaryElement) {
    dom.overlayNowPlayingSummaryElement.textContent = view.nowPlaying.playbackSummary;
  }
  if (dom.overlayNowPlayingPositionElement) {
    dom.overlayNowPlayingPositionElement.textContent = view.nowPlaying.positionLabel;
  }
  if (dom.overlayNowPlayingDurationElement) {
    dom.overlayNowPlayingDurationElement.textContent = view.nowPlaying.durationLabel;
  }
  if (dom.overlayNowPlayingUpNextElement) {
    dom.overlayNowPlayingUpNextElement.textContent = view.nowPlaying.upNextText;
  }
  if (dom.overlayNowPlayingBadgesElement) {
    dom.overlayNowPlayingBadgesElement.replaceChildren(
      ...view.nowPlaying.badges.map((badge) => {
        const span = document.createElement('span');
        span.className = 'now-playing__badge';
        span.textContent = badge;
        return span;
      }),
    );
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
        number.className = 'mini-guide__channel-number';
        number.textContent = channel.number;
        const logo = document.createElement('div');
        logo.className = 'mini-guide__icon-placeholder';
        const copy = document.createElement('div');
        copy.className = 'mini-guide__details';
        const name = document.createElement('span');
        name.className = 'mini-guide__channel-name';
        name.textContent = channel.name;
        const title = document.createElement('p');
        title.className = 'mini-guide__current-title';
        title.textContent = `${channel.nowStartLabel} ${channel.currentTitle}`;
        const next = document.createElement('p');
        next.className = 'mini-guide__next-title';
        next.textContent = `Next: ${channel.nextTitle}`;
        const progress = document.createElement('i');
        progress.className = 'mini-guide__progress';
        progress.style.setProperty('--mini-guide-progress', `${channel.nowProgressPercent}%`);
        copy.append(name, title, next, progress);
        item.append(number, logo, copy);
        return item;
      }),
    );
  }
  if (dom.overlayChannelNumberElement) {
    dom.overlayChannelNumberElement.textContent = view.channelNumberDisplay;
    const container = dom.overlayChannelNumberElement.parentElement;
    if (container) {
      container.dataset.invalid = String(view.channelNumberInvalid);
    }
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
    dom.overlayAudioLabelElement.textContent = view.playerOsd.audioLabel;
  }
  if (dom.overlaySubtitleLabelElement) {
    dom.overlaySubtitleLabelElement.textContent = view.playerOsd.subtitleLabel;
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
    dom.overlayPlaybackSummaryElement.textContent = [
      view.playerOsd.statusLabel,
      view.playerOsd.timecode,
      view.playerOsd.endsAtText,
      view.playerOsd.upNextText,
      view.playbackOptions.playbackSummary,
    ].join(' - ');
  }
  if (dom.osdStatusElement) {
    dom.osdStatusElement.textContent = view.playerOsd.statusLabel;
    dom.osdStatusElement.setAttribute('aria-label', view.playerOsd.statusLabel);
  }
  if (dom.osdTitleElement) {
    dom.osdTitleElement.textContent = view.playerOsd.title;
  }
  if (dom.osdSubtitleElement) {
    dom.osdSubtitleElement.textContent = view.playerOsd.subtitle;
  }
  if (dom.osdAudioElement) {
    dom.osdAudioElement.textContent = `Audio: ${view.playerOsd.audioLabel}`;
  }
  if (dom.osdSubtitlesElement) {
    dom.osdSubtitlesElement.textContent = `Subs: ${view.playerOsd.subtitleLabel}`;
  }
  if (dom.osdUpNextElement) {
    dom.osdUpNextElement.textContent = view.playerOsd.upNextText;
  }
  if (dom.osdTimecodeElement) {
    dom.osdTimecodeElement.textContent = view.playerOsd.timecode;
  }
  if (dom.osdEndsAtElement) {
    dom.osdEndsAtElement.textContent = view.playerOsd.endsAtText;
  }
  if (dom.osdBufferTextElement) {
    dom.osdBufferTextElement.textContent = view.playerOsd.bufferText;
  }
  dom.osdBufferBarElement?.style.setProperty('--osd-buffer', `${view.playerOsd.bufferedPercent}%`);
  dom.osdPlayedBarElement?.style.setProperty('--osd-played', `${view.playerOsd.playedPercent}%`);
  renderPlaybackOptionRows(dom.overlayAudioOptionsElement, view.playbackOptions.audioTracks, 'overlay-audio-track-');
  renderPlaybackOptionRows(dom.overlaySubtitleOptionsElement, view.playbackOptions.subtitleTracks, 'overlay-subtitle-track-');
}

function renderPlaybackOptionRows(
  host: HTMLElement | null,
  tracks: readonly PlaybackOptionTrackViewModel[],
  focusIdPrefix: string,
): void {
  if (!host) {
    return;
  }
  host.replaceChildren(
    ...tracks.map((track) => {
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'playback-options__row';
      row.dataset.trackId = track.id;
      row.dataset.selected = String(track.selected);
      row.dataset.available = String(track.available);
      row.disabled = !track.available;
      row.setAttribute('aria-disabled', String(!track.available));
      if (track.available) {
        row.dataset.focusId = `${focusIdPrefix}${track.id}`;
      }
      const label = document.createElement('strong');
      label.textContent = track.label;
      const meta = document.createElement('span');
      meta.textContent = track.meta;
      const state = document.createElement('em');
      state.textContent = track.stateLabel;
      row.append(label, meta, state);

      if (track.selected && focusIdPrefix === 'overlay-audio-track-') {
        const eq = document.createElement('div');
        eq.className = 'playback-options__equalizer';
        for (let i = 0; i < 4; i++) {
          const bar = document.createElement('span');
          eq.append(bar);
        }
        row.append(eq);
      }

      return row;
    }),
  );
}
