import type { PlayerSnapshot } from '../contracts/player.js';
import type { AppRouteId } from './navigation.js';
import type { RendererDomBindings } from './domBindings.js';
import {
  createPlayerOverlayView,
  type PlaybackOptionTrackViewModel,
  type PlayerOverlayPresentationSource,
  type PlayerOverlayState,
} from './overlays.js';

export const PLAYER_OVERLAY_MARKUP = `
<div class="overlay-stack" data-overlay-stack>
  <section class="player-overlay channel-badge" data-overlay="channelBadge" aria-label="Current channel" hidden>
    <strong data-overlay-channel-badge-number></strong>
    <div class="channel-badge__copy">
      <span data-overlay-channel-badge-name></span>
      <p data-overlay-channel-badge-program></p>
    </div>
  </section>
  <section class="player-overlay now-playing-overlay" data-overlay="nowPlaying" aria-label="Now playing" hidden>
    <div class="now-playing__details">
      <p class="now-playing__status" data-overlay-now-playing-status></p>
      <h3 data-overlay-now-playing-title class="now-playing__title"></h3>
      <p data-overlay-now-playing-subtitle class="now-playing__subtitle"></p>
      <p data-overlay-now-playing-channel class="now-playing__channel"></p>
      <div class="now-playing__progress-section">
        <div class="overlay-progress" data-overlay-progress role="progressbar" aria-label="Playback progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"></div>
        <div class="now-playing__time-row">
          <span data-overlay-now-playing-position class="now-playing__position"></span>
          <span data-overlay-now-playing-duration class="now-playing__duration"></span>
        </div>
      </div>
      <p data-overlay-now-playing-up-next class="now-playing__up-next"></p>
    </div>
  </section>
  <section class="player-overlay osd-overlay" data-overlay="playerOsd" aria-label="Player controls" hidden>
    <div class="player-osd__content-row">
      <div class="player-osd__content">
        <div class="player-osd__status" data-osd-status role="status"></div>
        <div class="player-osd__title" data-osd-title></div>
        <div class="player-osd__subtitle" data-osd-subtitle></div>
        <div class="player-osd__pills">
          <span data-osd-audio></span>
          <span data-osd-subtitles></span>
        </div>
      </div>
      <div class="player-osd__actions">
        <button type="button" data-overlay-action="openSubtitleOptions" data-focus-id="overlay-osd-subtitles">Subtitles</button>
        <button type="button" class="player-osd__sleep-action" data-overlay-action="cycleSleepTimer" data-focus-id="overlay-osd-sleep" aria-label="Sleep timer, Off">
          <span>Sleep</span>
          <strong data-osd-sleep>Off</strong>
        </button>
        <button type="button" data-overlay-action="openAudioOptions" data-focus-id="overlay-osd-audio">Audio</button>
        <div class="player-osd__sleep-status" data-osd-sleep-status role="status" aria-live="polite"></div>
        <div class="player-osd__up-next" data-osd-up-next></div>
      </div>
    </div>
    <div class="player-osd__meta">
      <span data-osd-timecode></span>
      <span data-osd-ends-at></span>
      <span data-osd-buffer-text></span>
    </div>
    <div class="player-osd__bar" aria-hidden="true">
      <span class="player-osd__bar-buffer" data-osd-buffer-bar></span>
      <span class="player-osd__bar-played" data-osd-played-bar></span>
    </div>
  </section>
  <section class="player-overlay mini-guide" data-overlay="miniGuide" aria-label="Mini guide" hidden>
    <p class="mini-guide__error" data-overlay-mini-guide-error role="status"></p>
    <div class="mini-guide__list" data-overlay-mini-guide></div>
    <footer class="mini-guide__footer">Use Up/Down to select, Enter to tune.</footer>
  </section>
  <section class="player-overlay channel-number-overlay" data-overlay="channelNumber" aria-label="Channel number" hidden>
    <span class="channel-number-overlay__label">CH</span>
    <strong data-overlay-channel-number-value>---</strong>
    <span data-overlay-channel-number-message role="status"></span>
  </section>
  <section class="player-overlay playback-options" data-overlay="playbackOptions" role="dialog" aria-modal="true" aria-labelledby="playback-options-title" hidden>
    <header class="playback-options__header">
      <p>Playback options</p>
      <h3 id="playback-options-title" data-overlay-playback-summary></h3>
    </header>
    <p class="playback-options__error" data-overlay-options-error role="status"></p>
    <section class="playback-options__section" aria-label="Available tracks">
      <div data-overlay-audio-options hidden></div>
      <div data-overlay-subtitle-options hidden></div>
    </section>
  </section>
  <section class="player-overlay channel-transition" data-overlay="transition" aria-label="Changing channel" role="status" hidden>
    <span class="channel-transition__spinner" aria-hidden="true"></span>
    <span class="channel-transition__copy"><strong>Changing channel</strong><span data-overlay-transition-label></span></span>
  </section>
  <section class="player-overlay player-loading" data-overlay="playerLoading" aria-label="Loading player" role="status" hidden>
    <span class="player-loading__indicator" aria-hidden="true"></span>
    <strong data-overlay-player-loading-label>Loading…</strong>
  </section>
  <section class="player-overlay player-error" data-overlay="playerError" aria-label="Player error" role="alert" hidden>
    <p data-overlay-player-error></p>
    <div class="player-error__actions">
      <button type="button" data-overlay-action="retryPlayer" data-focus-id="overlay-player-retry">Retry</button>
      <button type="button" data-overlay-action="skipPlayer" data-focus-id="overlay-player-skip">Skip</button>
      <button type="button" data-route-action="openGuide" data-focus-id="overlay-player-guide">Guide</button>
    </div>
  </section>
</div>`;

export function renderPlayerOverlaysDom(
  overlayState: PlayerOverlayState,
  dom: RendererDomBindings,
  activeRoute: AppRouteId,
  overlayPresentation: PlayerOverlayPresentationSource,
  _previewBadgesEnabled: boolean,
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
      (action === 'cycleSleepTimer' && !view.playerOsd.sleepEligible) ||
      (action === 'retryPlayer' && !view.retryVisible) ||
      (action === 'skipPlayer' && !view.skipVisible);
    button.hidden = (action === 'retryPlayer' && !view.retryVisible) ||
      (action === 'skipPlayer' && !view.skipVisible) ||
      (action === 'openAudioOptions' && !view.playerOsd.audioEligible) ||
      (action === 'openSubtitleOptions' && !view.playerOsd.subtitleEligible);
    if (action === 'cycleSleepTimer') button.hidden = false;
  }
  if (dom.overlayPlayerRetryButton) projectBusyFocusCustody(dom.overlayPlayerRetryButton, view.retryBusy);
  if (dom.overlayPlayerSkipButton) projectBusyFocusCustody(dom.overlayPlayerSkipButton, view.skipBusy);
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
  setElementText(dom.overlayNowPlayingTitleElement, view.nowPlaying.title ?? '');
  setElementText(dom.overlayNowPlayingSubtitleElement, view.nowPlaying.subtitle ?? '');
  setElementText(dom.overlayNowPlayingChannelElement, view.nowPlaying.channelLabel ?? '');
  setElementText(dom.overlayNowPlayingStatusElement, view.nowPlaying.statusLabel);
  setElementText(dom.overlayNowPlayingDescriptionElement, '');
  setElementText(dom.overlayNowPlayingSummaryElement, '');
  setElementText(dom.overlayNowPlayingPositionElement, view.nowPlaying.positionLabel);
  setElementText(dom.overlayNowPlayingDurationElement, view.nowPlaying.durationLabel);
  setElementText(dom.overlayNowPlayingUpNextElement, view.nowPlaying.upNextText ?? '');
  dom.overlayNowPlayingBadgesElement?.replaceChildren();
  if (dom.overlayProgressElement) {
    dom.overlayProgressElement.style.setProperty('--overlay-progress', `${view.nowPlaying.progressPercent}%`);
    dom.overlayProgressElement.setAttribute('aria-valuenow', String(view.nowPlaying.progressPercent));
  }

  renderMiniGuide(dom.overlayMiniGuideElement, view.miniGuideChannels);
  if (dom.overlayMiniGuideErrorElement) {
    dom.overlayMiniGuideErrorElement.textContent = view.miniGuideError ?? '';
    dom.overlayMiniGuideErrorElement.hidden = view.miniGuideError === null;
  }
  if (dom.overlayChannelNumberElement) {
    dom.overlayChannelNumberElement.textContent = view.channelNumberDisplay;
    const container = dom.overlayChannelNumberElement.parentElement;
    if (container) {
      container.dataset.invalid = String(view.channelNumberStatus === 'error');
      container.dataset.channelNumberStatus = view.channelNumberStatus ?? '';
    }
  }
  setElementText(dom.overlayChannelBadgeNumberElement, view.currentChannel?.number ?? '');
  setElementText(dom.overlayChannelBadgeNameElement, view.currentChannel?.name ?? '');
  setElementText(dom.overlayChannelBadgeProgramElement, view.currentChannel?.currentProgram?.title ?? '');
  setElementText(dom.overlayAudioLabelElement, view.playerOsd.audioLabel ?? '');
  setElementText(dom.overlaySubtitleLabelElement, view.playerOsd.subtitleLabel ?? '');
  setElementText(dom.overlayPlaybackSummaryElement, view.playbackOptions?.family === 'audio' ? 'Audio tracks' : 'Subtitles');

  setPlaybackOptionsFamily(dom, view.playbackOptions?.family ?? null);
  setOsdContent(dom, overlayPresentation.playerSnapshot, view);
  renderPlaybackOptionRows(dom.overlayAudioOptionsElement, view.playbackOptions?.family === 'audio' ? view.playbackOptions.tracks : []);
  renderPlaybackOptionRows(dom.overlaySubtitleOptionsElement, view.playbackOptions?.family === 'subtitle' ? view.playbackOptions.tracks : []);
  setElementText(dom.overlayChannelNumberMessageElement, view.channelNumberMessage ?? '');
  if (dom.overlayOptionsErrorElement) {
    dom.overlayOptionsErrorElement.textContent = view.playbackOptions?.error ?? '';
    dom.overlayOptionsErrorElement.hidden = view.playbackOptions?.error === null || view.playbackOptions === null;
  }
  setElementText(dom.overlayTransitionLabelElement, view.transitionLabel === null ? '' : `Channel ${view.transitionLabel}`);
  setElementText(dom.overlayPlayerErrorElement, view.errorMessage ?? '');
  setElementText(
    dom.overlayPlayerLoadingLabelElement,
    loadingLabelFor(overlayPresentation.playerSnapshot),
  );
}

function setOsdContent(
  dom: RendererDomBindings,
  snapshot: PlayerSnapshot,
  view: ReturnType<typeof createPlayerOverlayView>,
): void {
  if (dom.osdStatusElement) {
    dom.osdStatusElement.textContent = view.playerOsd.statusLabel;
    dom.osdStatusElement.setAttribute('aria-label', view.playerOsd.statusLabel);
  }
  setElementText(dom.osdTitleElement, view.playerOsd.title ?? '');
  setElementText(dom.osdSubtitleElement, view.playerOsd.subtitle ?? '');
  setElementText(dom.osdAudioElement, view.playerOsd.audioLabel === undefined ? '' : `Audio: ${view.playerOsd.audioLabel}`);
  setElementText(dom.osdSubtitlesElement, view.playerOsd.subtitleLabel === undefined ? '' : `Subs: ${view.playerOsd.subtitleLabel}`);
  setElementText(dom.osdSleepElement, view.playerOsd.sleepLabel);
  setElementText(dom.osdSleepStatusElement, view.playerOsd.sleepStatus);
  dom.osdSleepButton?.setAttribute('aria-label', view.playerOsd.sleepAccessibleLabel);
  setElementText(dom.osdUpNextElement, view.nowPlaying.upNextText ?? '');
  setElementText(dom.osdTimecodeElement, view.playerOsd.timecode);
  setElementText(dom.osdEndsAtElement, '');
  setElementText(dom.osdBufferTextElement, snapshot.status === 'buffering' ? 'Buffering' : '');
  dom.osdBufferBarElement?.style.setProperty('--osd-buffer', `${view.playerOsd.bufferedPercent}%`);
  dom.osdPlayedBarElement?.style.setProperty('--osd-played', `${view.playerOsd.playedPercent}%`);
}

function renderMiniGuide(
  host: HTMLElement | null,
  channels: ReturnType<typeof createPlayerOverlayView>['miniGuideChannels'],
): void {
  if (!host) return;
  host.replaceChildren(...channels.map((channel) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'mini-guide__item';
    item.dataset.selectedChannel = String(channel.selected);
    item.dataset.overlayChannelId = channel.id;
    item.dataset.focusId = `overlay-mini-channel-${encodeURIComponent(channel.id)}`;
    item.setAttribute('aria-current', channel.selected ? 'true' : 'false');
    projectBusyFocusCustody(item, channel.busy);

    const number = document.createElement('strong');
    number.className = 'mini-guide__channel-number';
    number.textContent = channel.number;
    const copy = document.createElement('span');
    copy.className = 'mini-guide__channel-copy';
    const name = document.createElement('strong');
    name.className = 'mini-guide__channel-name';
    name.textContent = channel.name;
    const title = document.createElement('span');
    title.className = 'mini-guide__current-title';
    title.textContent = channel.currentProgram?.title ?? '';
    copy.append(name, title);
    const progress = document.createElement('i');
    progress.className = 'mini-guide__progress';
    progress.style.setProperty('--mini-guide-progress', `${channel.progressPercent ?? 0}%`);
    const next = document.createElement('span');
    next.className = 'mini-guide__next-title';
    next.textContent = channel.nextProgram === undefined ? '' : `Next: ${channel.nextProgram.title}`;
    item.append(number, copy, progress, next);
    return item;
  }));
}

function setPlaybackOptionsFamily(
  dom: RendererDomBindings,
  family: 'audio' | 'subtitle' | null,
): void {
  setHiddenInert(dom.overlayAudioOptionsElement, family !== 'audio');
  setHiddenInert(dom.overlaySubtitleOptionsElement, family !== 'subtitle');
}

function setHiddenInert(element: HTMLElement | null, hidden: boolean): void {
  if (!element) return;
  element.hidden = hidden;
  element.inert = hidden;
  element.setAttribute('aria-hidden', String(hidden));
}

function renderPlaybackOptionRows(
  host: HTMLElement | null,
  tracks: readonly PlaybackOptionTrackViewModel[],
): void {
  if (!host) return;
  host.replaceChildren(...tracks.map((track) => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'playback-options__row';
    row.dataset.trackId = track.trackId ?? 'subtitles-off';
    row.dataset.selected = String(track.selected);
    row.dataset.available = 'true';
    row.dataset.focusId = track.focusId;
    row.setAttribute('aria-pressed', String(track.selected));
    projectBusyFocusCustody(row, track.busy);
    const label = document.createElement('strong');
    label.textContent = track.label;
    const meta = document.createElement('span');
    meta.className = 'playback-options__meta';
    meta.textContent = track.meta ?? '';
    const state = document.createElement('span');
    state.className = 'playback-options__state';
    const stateLabel = document.createElement('em');
    stateLabel.textContent = track.selected ? 'Selected' : '';
    state.append(stateLabel);
    if (track.selected) {
      const equalizer = document.createElement('span');
      equalizer.className = 'playback-options__equalizer';
      equalizer.setAttribute('aria-hidden', 'true');
      for (let index = 0; index < 3; index += 1) equalizer.append(document.createElement('span'));
      state.append(equalizer);
    }
    row.append(label, meta, state);
    return row;
  }));
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

function setElementText(element: HTMLElement | null | undefined, value: string): void {
  if (element) element.textContent = value;
}

function loadingLabelFor(snapshot: PlayerSnapshot): string {
  if (snapshot.status === 'buffering') return 'Buffering…';
  if (snapshot.status === 'stalled') return 'Playback stalled…';
  if (snapshot.status === 'seeking') return 'Seeking…';
  return 'Loading…';
}
