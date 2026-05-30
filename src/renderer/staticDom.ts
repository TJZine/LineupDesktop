const STATIC_SCREEN_MARKUP = `
<section class="screen-stack" aria-live="polite" data-static-screens-mounted>
  <div class="player-presentation" data-player-presentation-surface aria-label="Player presentation surface">
    <div class="player-surface" aria-hidden="true"></div>
      <div class="overlay-stack" data-overlay-stack>
        <section class="player-overlay channel-badge" data-overlay="channelBadge" aria-label="Channel badge">
          <strong data-overlay-channel-badge-number></strong>
          <div>
            <span data-overlay-channel-badge-name></span>
            <p data-overlay-channel-badge-program></p>
          </div>
        </section>
        <section class="player-overlay now-playing-overlay" data-overlay="nowPlaying" aria-label="Now playing">
          <p data-overlay-now-playing-channel></p>
          <h3 data-overlay-now-playing-title></h3>
          <p data-overlay-now-playing-subtitle></p>
          <p data-overlay-now-playing-status></p>
          <div class="overlay-progress" data-overlay-progress role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"></div>
        </section>
        <section class="player-overlay osd-overlay" data-overlay="playerOsd" aria-label="Player controls">
          <button type="button" data-overlay-action="openMiniGuide" data-focus-id="overlay-mini-guide">Mini guide</button>
          <button type="button" data-overlay-action="togglePlaybackOptions" data-focus-id="overlay-playback-options">Options</button>
          <button type="button" data-overlay-action="channelDigit1" data-focus-id="overlay-channel-1">1</button>
          <button type="button" data-overlay-action="channelDigit0" data-focus-id="overlay-channel-0">0</button>
          <button type="button" data-overlay-action="channelDigit4" data-focus-id="overlay-channel-4">4</button>
          <button type="button" data-overlay-action="closeTopOverlay" data-focus-id="overlay-close">Close</button>
        </section>
        <section class="player-overlay mini-guide" data-overlay="miniGuide" aria-label="Mini guide" hidden>
          <div class="mini-guide__controls">
            <button type="button" data-overlay-action="previousMiniGuideChannel" data-focus-id="overlay-mini-previous">Channel up</button>
            <button type="button" data-overlay-action="nextMiniGuideChannel" data-focus-id="overlay-mini-next">Channel down</button>
          </div>
          <div class="mini-guide__list" data-overlay-mini-guide></div>
        </section>
        <section class="player-overlay channel-number-overlay" data-overlay="channelNumber" aria-label="Channel number" hidden>
          <span data-overlay-channel-number-value>---</span>
          <div>
            <button type="button" data-overlay-action="commitChannelNumber" data-focus-id="overlay-channel-commit">Tune</button>
            <button type="button" data-overlay-action="clearChannelNumber" data-focus-id="overlay-channel-clear">Clear</button>
          </div>
        </section>
        <section class="player-overlay playback-options" data-overlay="playbackOptions" aria-label="Playback options" hidden>
          <header class="playback-options__header">
            <p>Playback options</p>
            <strong data-overlay-playback-summary></strong>
          </header>
          <dl>
            <div><dt>Audio</dt><dd data-overlay-audio-label></dd></div>
            <div><dt>Subtitles</dt><dd data-overlay-subtitle-label></dd></div>
            <div><dt>Volume</dt><dd data-overlay-volume-label></dd></div>
            <div><dt>Rate</dt><dd data-overlay-rate-label></dd></div>
          </dl>
          <div class="playback-options__lists">
            <section>
              <h4>Audio tracks</h4>
              <div data-overlay-audio-options></div>
            </section>
            <section>
              <h4>Subtitle tracks</h4>
              <div data-overlay-subtitle-options></div>
            </section>
          </div>
          <div class="playback-options__controls">
            <button type="button" data-overlay-action="cycleAudioTrack" data-focus-id="overlay-audio-cycle">Audio</button>
            <button type="button" data-overlay-action="cycleSubtitleTrack" data-focus-id="overlay-subtitle-cycle">Subtitles</button>
            <button type="button" data-overlay-action="volumeDown" data-focus-id="overlay-volume-down">Volume -</button>
            <button type="button" data-overlay-action="volumeUp" data-focus-id="overlay-volume-up">Volume +</button>
            <button type="button" data-overlay-action="toggleMute" data-focus-id="overlay-mute">Mute</button>
          </div>
        </section>
      </div>
  </div>
  <section id="screen-player" class="screen screen--active" data-screen="player" data-style-surface="screen" aria-labelledby="screen-player-title">
    <div class="screen__content">
      <div class="screen-shell-state" data-shell-state="active">
        <span>Player preview</span>
        <strong data-screen-state-text="player">Player controls are available for the local preview surface.</strong>
      </div>
      <p class="screen__kicker" data-workflow-kicker="player">Now playing</p>
      <h2 id="screen-player-title">Player</h2>
      <p data-workflow-primary="player">Ready for playback.</p>
      <p data-workflow-secondary="player">Playback preview is local-only.</p>
      <dl class="program-summary">
        <div><dt>Channel</dt><dd data-current-channel></dd></div>
        <div><dt>Program</dt><dd data-current-program></dd></div>
        <div><dt>Time</dt><dd data-current-window></dd></div>
      </dl>
      <div class="workflow-actions" data-workflow-actions="player">
        <button type="button" data-route-action="openGuide" data-focus-id="player-guide">Open guide</button>
        <button type="button" data-route-action="openSettings" data-focus-id="player-settings">Settings</button>
      </div>
      <button type="button" data-overlay-action="toggleOsd" data-focus-id="player-osd">Toggle OSD</button>
      <button type="button" data-fullscreen-toggle data-focus-id="player-fullscreen" aria-pressed="false">Toggle fullscreen</button>
    </div>
  </section>
  <section id="screen-guide" class="screen" data-screen="guide" data-style-surface="screen" aria-labelledby="screen-guide-title" hidden>
    <div class="screen__content">
      <div class="screen-shell-state" data-shell-state="active">
        <span>Guide preview</span>
        <strong data-screen-state-text="guide">Guide rows show the current local lineup preview.</strong>
      </div>
      <p class="screen__kicker" data-workflow-kicker="guide">Guide</p>
      <h2 id="screen-guide-title">Guide</h2>
      <p data-workflow-primary="guide">Tonight at a glance.</p>
      <p data-workflow-secondary="guide">Lineup preview.</p>
      <div class="guide-controls" aria-label="Guide shell controls">
        <button type="button" data-epg-action="previousWindow" data-focus-id="guide-window-previous">Earlier</button>
        <button type="button" data-epg-action="nextWindow" data-focus-id="guide-window-next">Later</button>
        <button type="button" data-epg-action="previousChannel" data-focus-id="guide-channel-previous">Channel up</button>
        <button type="button" data-epg-action="nextChannel" data-focus-id="guide-channel-next">Channel down</button>
        <button type="button" data-epg-action="previousProgram" data-focus-id="guide-program-previous">Previous show</button>
        <button type="button" data-epg-action="nextProgram" data-focus-id="guide-program-next">Next show</button>
      </div>
      <section class="guide-detail" aria-label="Selected guide program">
        <p data-epg-detail-channel></p>
        <h3 data-epg-detail-title></h3>
        <p data-epg-detail-time></p>
      </section>
      <div class="screen-shell-state" data-shell-state="empty">
        <span>Empty state</span>
        <strong>No saved channels are loaded for this local setup state.</strong>
      </div>
      <div class="epg-grid" data-epg-grid aria-label="Guide schedule grid"></div>
      <div class="workflow-actions" data-workflow-actions="guide">
        <button type="button" data-route-action="resumePlayer" data-focus-id="guide-watch">Watch now</button>
        <button type="button" data-route-action="openChannelSetup" data-focus-id="guide-setup">Edit lineup</button>
      </div>
    </div>
  </section>
  <section id="screen-settings" class="screen" data-screen="settings" data-style-surface="screen" aria-labelledby="screen-settings-title" hidden>
    <div class="screen__content">
      <div class="screen-shell-state" data-shell-state="active">
        <span>Settings preview</span>
        <strong data-screen-state-text="settings">Preference changes apply to this local preview session only.</strong>
      </div>
      <p class="screen__kicker" data-workflow-kicker="settings">Settings</p>
      <h2 id="screen-settings-title">Settings</h2>
      <p data-workflow-primary="settings">Desktop preferences.</p>
      <p data-workflow-secondary="settings">Desktop local preview.</p>
      <dl class="settings-summary">
        <div><dt>Source</dt><dd data-settings-source></dd></div>
        <div><dt>Channels</dt><dd data-settings-channels></dd></div>
        <div><dt>Status</dt><dd data-settings-state></dd></div>
      </dl>
      <div class="settings-sections" data-settings-sections></div>
      <div class="settings-controls" aria-label="Settings shell controls">
        <button type="button" data-settings-action="cycleLaunchMode" data-focus-id="settings-launch-mode">Startup surface</button>
        <button type="button" data-settings-action="cycleGuideDensity" data-focus-id="settings-guide-density">Guide density</button>
        <button type="button" data-settings-action="togglePreviewBadges" data-focus-id="settings-preview-badges">Preview badges</button>
        <button type="button" data-settings-action="toggleSetupReminder" data-focus-id="settings-setup-reminder">Setup reminder</button>
        <button type="button" data-settings-action="exportSupportBundle" data-focus-id="settings-support-bundle">Export support bundle</button>
      </div>
      <div class="workflow-actions" data-workflow-actions="settings">
        <button type="button" data-route-action="openChannelSetup" data-focus-id="settings-setup">Channel setup</button>
        <button type="button" data-route-action="resumePlayer" data-focus-id="settings-player">Back to player</button>
      </div>
    </div>
  </section>
  <section id="screen-channel-setup" class="screen screen--onboarding" data-screen="channelSetup" data-style-surface="screen" aria-labelledby="screen-channel-setup-title" hidden>
    <div class="screen__content plex-onboarding-shell">
      <div class="plex-onboarding-hero">
        <p class="screen__kicker" data-workflow-kicker="channelSetup">Channel setup</p>
        <h2 id="screen-channel-setup-title">Plex setup</h2>
        <p data-workflow-primary="channelSetup">Connect Plex, choose a profile and server, then browse your library.</p>
        <p data-workflow-secondary="channelSetup">Lineup Desktop shows the account, server, library, and media details needed for setup.</p>
      </div>
      <div class="screen-shell-state" data-shell-state="loading">
        <span>Persisted setup status</span>
        <strong data-screen-state-text="channelSetup">Review account, server, library, and persisted channel recovery in one place.</strong>
      </div>
      <section class="plex-runtime plex-onboarding" data-plex-runtime-panel aria-label="Plex onboarding">
        <header class="plex-runtime__header">
          <div>
            <h3>Plex onboarding</h3>
            <p data-plex-status>Not loaded</p>
          </div>
          <p class="plex-runtime__error" data-plex-error hidden></p>
        </header>
        <dl class="plex-runtime__summary">
          <div><dt>Account</dt><dd data-plex-account-state></dd></div>
          <div><dt>Server</dt><dd data-plex-server-state></dd></div>
          <div><dt>Library</dt><dd data-plex-library-state></dd></div>
        </dl>
        <section class="plex-runtime__stage" aria-labelledby="plex-stage-account">
          <h4 id="plex-stage-account">1. Sign in</h4>
          <p class="plex-runtime__stage-copy">Link a Plex account and select the profile Lineup Desktop should use.</p>
          <div class="plex-runtime__controls" aria-label="Plex sign-in controls">
            <button type="button" data-plex-action="loadSnapshot" data-focus-id="plex-load">Resume setup</button>
            <button type="button" data-plex-action="requestPin" data-focus-id="plex-request-pin">Get link code</button>
            <button type="button" data-plex-action="pollPin" data-focus-id="plex-poll-pin">I signed in</button>
            <button type="button" data-plex-action="cancelPin" data-focus-id="plex-cancel-pin">Cancel</button>
            <button type="button" data-plex-action="clearPinSubflow" data-focus-id="plex-clear-pin">Start over</button>
          </div>
          <div class="plex-runtime__pin" data-plex-pin></div>
          <div class="plex-runtime__controls" aria-label="Plex profile controls">
            <input data-plex-home-user-pin data-focus-id="plex-home-pin" inputmode="numeric" autocomplete="off" maxlength="12" aria-label="Plex Home PIN" />
            <button type="button" data-plex-action="getHomeUsers" data-focus-id="plex-home-users">Choose profile</button>
          </div>
          <div class="plex-runtime__list" data-plex-home-users></div>
        </section>
        <section class="plex-runtime__stage" aria-labelledby="plex-stage-server">
          <h4 id="plex-stage-server">2. Choose server</h4>
          <p class="plex-runtime__stage-copy">Pick the Plex server Lineup Desktop should use for this profile.</p>
          <div class="plex-runtime__controls" aria-label="Plex server controls">
            <button type="button" data-plex-action="restoreSelectedServer" data-focus-id="plex-restore-server">Use saved server</button>
            <button type="button" data-plex-action="refreshServers" data-focus-id="plex-refresh-servers">Find servers</button>
            <button type="button" data-plex-action="clearSelectedServer" data-focus-id="plex-clear-server">Change server</button>
          </div>
          <div class="plex-runtime__list" data-plex-servers></div>
        </section>
        <section class="plex-runtime__stage" aria-labelledby="plex-stage-library">
          <h4 id="plex-stage-library">3. Browse library</h4>
          <p class="plex-runtime__stage-copy">Choose a library, browse items, or search before previewing metadata.</p>
          <div class="plex-runtime__controls" aria-label="Plex library controls">
            <button type="button" data-plex-action="listLibrarySections" data-focus-id="plex-list-sections">Open libraries</button>
            <button type="button" data-plex-action="clearSelectedSection" data-focus-id="plex-clear-section">Change library</button>
            <button type="button" data-plex-action="listLibraryItems" data-focus-id="plex-list-items">Browse library</button>
            <button type="button" data-plex-action="clearItems" data-focus-id="plex-clear-items">Clear results</button>
            <input data-plex-search-query data-focus-id="plex-search-query" maxlength="120" aria-label="Library search" />
            <button type="button" data-plex-action="searchLibrary" data-focus-id="plex-search">Search</button>
            <button type="button" data-plex-action="clearSearch" data-focus-id="plex-clear-search">Clear search</button>
          </div>
          <div class="plex-runtime__list" data-plex-sections></div>
          <div class="plex-runtime__list" data-plex-items></div>
        </section>
        <section class="plex-runtime__stage" aria-labelledby="plex-stage-metadata">
          <h4 id="plex-stage-metadata">4. Preview item</h4>
          <p class="plex-runtime__stage-copy">Review the selected media summary before continuing setup later.</p>
          <button type="button" data-plex-action="clearMetadata" data-focus-id="plex-clear-metadata">Close preview</button>
          <div class="plex-runtime__metadata" data-plex-metadata></div>
        </section>
      </section>
      <section class="channel-setup-commit" aria-labelledby="channel-setup-commit-title">
        <header>
          <div>
            <p class="screen__kicker">Channel setup</p>
            <h3 id="channel-setup-commit-title">Review and save channels</h3>
          </div>
          <strong data-channel-setup-fixture-status></strong>
        </header>
        <ol class="setup-steps" data-channel-review-steps></ol>
        <dl class="setup-summary">
          <div><dt>Source</dt><dd data-channel-setup-source></dd></div>
          <div><dt>Enabled channels</dt><dd data-channel-setup-enabled></dd></div>
          <div><dt>Blocks</dt><dd data-channel-setup-blocks></dd></div>
        </dl>
        <div class="plex-runtime__controls" aria-label="Channel setup commit controls">
          <button type="button" data-channel-commit-action="append" data-focus-id="channel-append">Append selected library</button>
          <button type="button" data-channel-commit-action="replace" data-focus-id="channel-replace">Replace lineup</button>
          <button type="button" data-channel-commit-action="confirmReplace" data-focus-id="channel-confirm-replace">Confirm replace</button>
        </div>
        <div class="setup-review">
          <section>
            <h4>Compact guide order</h4>
            <div class="channel-draft-list" data-channel-review-list></div>
          </section>
          <section>
            <h4>Guarded review</h4>
            <div class="setup-validation" data-channel-review-validation></div>
          </section>
        </div>
      </section>
    </div>
  </section>
</section>`;

export function mountStaticRendererDom(documentRef: Document = document): void {
  const root = documentRef.querySelector<HTMLElement>('[data-static-screen-root]');
  if (root === null || root.querySelector('[data-static-screens-mounted]') !== null) {
    return;
  }

  root.innerHTML = STATIC_SCREEN_MARKUP;
}
