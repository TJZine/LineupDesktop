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
    screen.inert = !isActive;
    screen.setAttribute('aria-hidden', String(!isActive));
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
  overlayPresentation?: PlayerOverlayPresentationSource,
  activeSettingsCategory: SettingsSectionId = 'appearance',
  activeSetupStage: string = 'account',
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
  renderEpgGuideDom(view, dom, workflowState.settingsDraft);
  const presentation = overlayPresentation ?? {
    channels: [],
    currentChannelId: null,
    playerSnapshot,
    nowMs: Date.now(),
  };
  renderPlayerOverlaysDom(overlayState, dom, view.route, {
    ...presentation,
    playerSnapshot,
  }, workflowState.settingsDraft.previewBadgesEnabled);
  renderSettingsDom(view, dom, activeSettingsCategory);
  renderChannelSetupDom(view, dom, liveSelection, activeSetupStage);
  renderRouteActionButtons(view, dom);
  renderSetupReminders(view, workflowState.settingsDraft.setupReminderEnabled);
}

function renderSetupReminders(view: RouteWorkflowViewModel, enabled: boolean): void {
  if (typeof document.querySelectorAll !== 'function') return;
  const visible = enabled && view.settings.channelCount === 0;
  for (const reminder of Array.from(document.querySelectorAll<HTMLElement>('[data-setup-reminder]'))) {
    reminder.hidden = !visible;
    reminder.setAttribute('aria-hidden', String(!visible));
  }
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
  previewBadgesEnabled: boolean,
): void {
  const view = createPlayerOverlayView(overlayState, overlayPresentation);
  const isPlayerRoute = activeRoute === 'player';
  document.documentElement.dataset.activeOverlay = isPlayerRoute ? (view.activeOverlayId ?? '') : '';

  for (const element of dom.overlayElements) {
    const overlayId = element.dataset.overlay as keyof typeof view.visibleOverlays | undefined;
    const isVisible = isPlayerRoute && overlayId !== undefined && view.visibleOverlays[overlayId] === true;
    element.hidden = !isVisible;
    element.setAttribute('aria-hidden', String(!isVisible));
    element.dataset.overlayActive = String(isPlayerRoute && overlayId === view.activeOverlayId);
  }

  for (const button of dom.overlayActionButtons) {
    const action = button.dataset.overlayAction;
    button.disabled = !isPlayerRoute ||
      (action === 'openAudioOptions' && !view.playerOsd.audioEligible) ||
      (action === 'openSubtitleOptions' && !view.playerOsd.subtitleEligible) ||
      (action === 'retryPlayer' && !view.retryVisible);
    button.hidden = (action === 'retryPlayer' && !view.retryVisible) ||
      (action === 'openAudioOptions' && !view.playerOsd.audioEligible) ||
      (action === 'openSubtitleOptions' && !view.playerOsd.subtitleEligible);
  }
  if (dom.overlayPlayerRetryButton) {
    projectBusyFocusCustody(dom.overlayPlayerRetryButton, view.retryBusy);
  }
  if (dom.overlayPlayerGuideButton) {
    dom.overlayPlayerGuideButton.hidden = !view.guideVisible;
    dom.overlayPlayerGuideButton.disabled = !isPlayerRoute || !view.guideVisible;
  }

  if (dom.overlayStackElement) {
    dom.overlayStackElement.hidden = !isPlayerRoute;
    dom.overlayStackElement.setAttribute('aria-hidden', String(!isPlayerRoute));
    dom.overlayStackElement.dataset.overlayRouteActive = String(isPlayerRoute);
    dom.overlayStackElement.dataset.overlayStack = isPlayerRoute ? view.stack.join(',') : '';
  }
  if (dom.overlayNowPlayingTitleElement) {
    dom.overlayNowPlayingTitleElement.textContent = view.nowPlaying.title ?? '';
  }
  if (dom.overlayNowPlayingSubtitleElement) {
    dom.overlayNowPlayingSubtitleElement.textContent = view.nowPlaying.subtitle ?? '';
  }
  if (dom.overlayNowPlayingChannelElement) {
    dom.overlayNowPlayingChannelElement.textContent = view.nowPlaying.channelLabel ?? '';
  }
  if (dom.overlayNowPlayingStatusElement) {
    dom.overlayNowPlayingStatusElement.textContent = [
      view.nowPlaying.statusLabel,
      `${view.nowPlaying.positionLabel} / ${view.nowPlaying.durationLabel}`,
      view.nowPlaying.upNextText ?? '',
    ].filter(Boolean).join(' - ');
  }
  if (dom.overlayNowPlayingDescriptionElement) {
    dom.overlayNowPlayingDescriptionElement.textContent = '';
  }
  if (dom.overlayNowPlayingSummaryElement) {
    dom.overlayNowPlayingSummaryElement.textContent = '';
  }
  if (dom.overlayNowPlayingPositionElement) {
    dom.overlayNowPlayingPositionElement.textContent = view.nowPlaying.positionLabel;
  }
  if (dom.overlayNowPlayingDurationElement) {
    dom.overlayNowPlayingDurationElement.textContent = view.nowPlaying.durationLabel;
  }
  if (dom.overlayNowPlayingUpNextElement) {
    dom.overlayNowPlayingUpNextElement.textContent = view.nowPlaying.upNextText ?? '';
  }
  if (dom.overlayNowPlayingBadgesElement) {
    dom.overlayNowPlayingBadgesElement.replaceChildren(
      ...(previewBadgesEnabled ? [] : []),
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
        const item = document.createElement('button');
        item.type = 'button';
        item.className = 'mini-guide__item';
        item.dataset.selectedChannel = String(channel.selected);
        item.dataset.overlayChannelId = channel.id;
        item.dataset.focusId = `overlay-mini-channel-${encodeURIComponent(channel.id)}`;
        projectBusyFocusCustody(item, channel.busy);
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
        title.textContent = channel.currentProgram?.title ?? '';
        const next = document.createElement('p');
        next.className = 'mini-guide__next-title';
        next.textContent = channel.nextProgram === undefined ? '' : `Next: ${channel.nextProgram.title}`;
        const progress = document.createElement('i');
        progress.className = 'mini-guide__progress';
        progress.style.setProperty('--mini-guide-progress', `${channel.progressPercent ?? 0}%`);
        copy.append(name, title, next, progress);
        item.append(number, logo, copy);
        return item;
      }),
    );
  }
  if (dom.overlayMiniGuideErrorElement) dom.overlayMiniGuideErrorElement.textContent = view.miniGuideError ?? '';
  if (dom.overlayChannelNumberElement) {
    dom.overlayChannelNumberElement.textContent = view.channelNumberDisplay;
    const container = dom.overlayChannelNumberElement.parentElement;
    if (container) {
      container.dataset.invalid = String(view.channelNumberStatus === 'error');
    }
  }
  if (dom.overlayChannelBadgeNumberElement) {
    dom.overlayChannelBadgeNumberElement.textContent = view.currentChannel?.number ?? '';
  }
  if (dom.overlayChannelBadgeNameElement) {
    dom.overlayChannelBadgeNameElement.textContent = view.currentChannel?.name ?? '';
  }
  if (dom.overlayChannelBadgeProgramElement) {
    dom.overlayChannelBadgeProgramElement.textContent = view.currentChannel?.currentProgram?.title ?? '';
  }
  if (dom.overlayAudioLabelElement) {
    dom.overlayAudioLabelElement.textContent = view.playerOsd.audioLabel ?? '';
  }
  if (dom.overlaySubtitleLabelElement) {
    dom.overlaySubtitleLabelElement.textContent = view.playerOsd.subtitleLabel ?? '';
  }
  if (dom.overlayPlaybackSummaryElement) {
    dom.overlayPlaybackSummaryElement.textContent = view.playbackOptions?.family === 'audio' ? 'Audio tracks' : 'Subtitles';
  }
  if (dom.osdStatusElement) {
    dom.osdStatusElement.textContent = view.playerOsd.statusLabel;
    dom.osdStatusElement.setAttribute('aria-label', view.playerOsd.statusLabel);
  }
  if (dom.osdTitleElement) {
    dom.osdTitleElement.textContent = view.playerOsd.title ?? '';
  }
  if (dom.osdSubtitleElement) {
    dom.osdSubtitleElement.textContent = view.playerOsd.subtitle ?? '';
  }
  if (dom.osdAudioElement) {
    dom.osdAudioElement.textContent = view.playerOsd.audioLabel === undefined ? '' : `Audio: ${view.playerOsd.audioLabel}`;
  }
  if (dom.osdSubtitlesElement) {
    dom.osdSubtitlesElement.textContent = view.playerOsd.subtitleLabel === undefined ? '' : `Subs: ${view.playerOsd.subtitleLabel}`;
  }
  if (dom.osdUpNextElement) {
    dom.osdUpNextElement.textContent = view.nowPlaying.upNextText ?? '';
  }
  if (dom.osdTimecodeElement) {
    dom.osdTimecodeElement.textContent = view.playerOsd.timecode;
  }
  if (dom.osdEndsAtElement) {
    dom.osdEndsAtElement.textContent = '';
  }
  if (dom.osdBufferTextElement) {
    dom.osdBufferTextElement.textContent = overlayPresentation.playerSnapshot.status === 'buffering' ? 'Buffering' : '';
  }
  dom.osdBufferBarElement?.style.setProperty('--osd-buffer', `${view.playerOsd.bufferedPercent}%`);
  dom.osdPlayedBarElement?.style.setProperty('--osd-played', `${view.playerOsd.playedPercent}%`);
  renderPlaybackOptionRows(dom.overlayAudioOptionsElement, view.playbackOptions?.family === 'audio' ? view.playbackOptions.tracks : []);
  renderPlaybackOptionRows(dom.overlaySubtitleOptionsElement, view.playbackOptions?.family === 'subtitle' ? view.playbackOptions.tracks : []);
  if (dom.overlayChannelNumberMessageElement) dom.overlayChannelNumberMessageElement.textContent = view.channelNumberMessage ?? '';
  if (dom.overlayOptionsErrorElement) dom.overlayOptionsErrorElement.textContent = view.playbackOptions?.error ?? '';
  if (dom.overlayTransitionLabelElement) dom.overlayTransitionLabelElement.textContent = view.transitionLabel === null ? '' : `Channel ${view.transitionLabel}`;
  if (dom.overlayPlayerErrorElement) dom.overlayPlayerErrorElement.textContent = view.errorMessage ?? '';
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
      const row = document.createElement('button');
      row.type = 'button';
      row.className = 'playback-options__row';
      row.dataset.trackId = track.trackId ?? 'subtitles-off';
      row.dataset.selected = String(track.selected);
      row.dataset.available = 'true';
      row.dataset.focusId = track.focusId;
      projectBusyFocusCustody(row, track.busy);
      const label = document.createElement('strong');
      label.textContent = track.label;
      const meta = document.createElement('span');
      meta.textContent = track.meta ?? '';
      const state = document.createElement('em');
      state.textContent = track.selected ? 'Selected' : '';
      row.append(label, meta, state);

      if (track.selected) {
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

function projectBusyFocusCustody(element: HTMLButtonElement, busy: boolean): void {
  element.setAttribute('aria-busy', String(busy));
  if (busy) {
    element.setAttribute('aria-disabled', 'true');
    element.dataset.overlayBusyFocusCustody = 'true';
    return;
  }
  element.removeAttribute('aria-disabled');
  delete element.dataset.overlayBusyFocusCustody;
}
