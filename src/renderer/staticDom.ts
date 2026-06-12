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
          <div class="now-playing__backdrop" aria-hidden="true"></div>
          <div class="now-playing__content-wrapper">
            <div class="now-playing__poster" aria-hidden="true">
              <div class="now-playing__poster-placeholder"></div>
            </div>
            <div class="now-playing__details">
              <div class="now-playing__logo-zone">
                <div class="now-playing__clear-logo-placeholder"></div>
                <h3 data-overlay-now-playing-title class="now-playing__title"></h3>
              </div>
              <p data-overlay-now-playing-subtitle class="now-playing__subtitle"></p>
              <div class="now-playing__badges-row" data-overlay-now-playing-badges></div >
              <div class="now-playing__meta-row">
                <span data-overlay-now-playing-channel class="now-playing__channel"></span>
                <span data-overlay-now-playing-summary class="now-playing__summary"></span>
              </div>
              <p data-overlay-now-playing-description class="now-playing__description"></p>
              <div class="now-playing__progress-section">
                <div class="overlay-progress" data-overlay-progress role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"></div>
                <div class="now-playing__time-row">
                  <span data-overlay-now-playing-position class="now-playing__position"></span>
                  <span data-overlay-now-playing-duration class="now-playing__duration"></span>
                </div>
              </div>
              <p data-overlay-now-playing-up-next class="now-playing__up-next"></p>
            </div>
          </div>
        </section>
        <section class="player-overlay osd-overlay" data-overlay="playerOsd" aria-label="Player controls">
          <div class="player-osd__content">
            <div class="player-osd__status" data-osd-status role="status"></div>
            <div class="player-osd__title" data-osd-title></div>
            <div class="player-osd__subtitle" data-osd-subtitle></div>
            <div class="player-osd__pills">
              <span data-osd-audio></span>
              <span data-osd-subtitles></span>
            </div>
            <div class="player-osd__up-next" data-osd-up-next></div>
          </div>
          <div class="player-osd__actions">
            <button type="button" data-overlay-action="cycleAudioTrack" data-focus-id="overlay-audio-cycle">Audio</button>
            <button type="button" data-overlay-action="cycleSubtitleTrack" data-focus-id="overlay-subtitle-cycle">Subtitles</button>
            <button type="button" data-overlay-action="openMiniGuide" data-focus-id="overlay-mini-guide">Mini guide</button>
            <button type="button" data-overlay-action="togglePlaybackOptions" data-focus-id="overlay-playback-options">Options</button>
            <button type="button" data-overlay-action="closeTopOverlay" data-focus-id="overlay-close">Close</button>
          </div>
          <div class="player-osd__digit-entry" aria-label="Digit entry">
            <button type="button" data-overlay-action="channelDigit1" data-focus-id="overlay-channel-1">1</button>
            <button type="button" data-overlay-action="channelDigit0" data-focus-id="overlay-channel-0">0</button>
            <button type="button" data-overlay-action="channelDigit4" data-focus-id="overlay-channel-4">4</button>
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
          <div class="mini-guide__controls">
            <button type="button" data-overlay-action="previousMiniGuideChannel" data-focus-id="overlay-mini-previous">Channel up</button>
            <button type="button" data-overlay-action="nextMiniGuideChannel" data-focus-id="overlay-mini-next">Channel down</button>
          </div>
          <div class="mini-guide__list" data-overlay-mini-guide></div>
          <footer class="mini-guide__footer">
            <span>Use Up/Down to select, Enter to tune.</span>
          </footer>
        </section>
        <section class="player-overlay channel-number-overlay" data-overlay="channelNumber" aria-label="Channel number" hidden>
          <span data-overlay-channel-number-value>---</span>
          <div class="channel-number-overlay__controls">
            <button type="button" data-overlay-action="commitChannelNumber" data-focus-id="overlay-channel-commit">Tune</button>
            <button type="button" data-overlay-action="clearChannelNumber" data-focus-id="overlay-channel-clear">Clear</button>
          </div>
        </section>
        <section class="player-overlay playback-options" data-overlay="playbackOptions" aria-label="Playback options" hidden>
          <header class="playback-options__header">
            <p>Playback options</p>
            <strong data-overlay-playback-summary></strong>
          </header>
          <dl class="playback-options__summary-list">
            <div><dt>Audio</dt><dd data-overlay-audio-label></dd></div>
            <div><dt>Subtitles</dt><dd data-overlay-subtitle-label></dd></div>
            <div><dt>Volume</dt><dd data-overlay-volume-label></dd></div>
            <div><dt>Rate</dt><dd data-overlay-rate-label></dd></div>
          </dl>
          <div class="playback-options__lists">
            <section class="playback-options__section">
              <h4>Audio tracks</h4>
              <div data-overlay-audio-options></div>
            </section>
            <section class="playback-options__section">
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
        <span>Player</span>
        <strong data-screen-state-text="player">Player controls are available for the current program.</strong>
      </div>
      <p class="screen__kicker" data-workflow-kicker="player">Now playing</p>
      <h2 id="screen-player-title">Player</h2>
      <p data-workflow-primary="player">Ready for playback.</p>
      <p data-workflow-secondary="player">Playback controls, guide access, and route chrome stay visible over the player.</p>
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
        <span>Guide</span>
        <strong data-screen-state-text="guide">Guide rows show the current lineup.</strong>
      </div>
      <p class="screen__kicker" data-workflow-kicker="guide">Guide</p>
      <h2 id="screen-guide-title">Guide</h2>
      <p data-workflow-primary="guide">Tonight at a glance.</p>
      <p data-workflow-secondary="guide">Use directional controls to move through time windows, channels, and programs.</p>
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
    <div class="screen__content settings-shell">
      <nav class="settings-rail" aria-label="Settings categories">
        <div class="settings-profile-row">
          <div class="settings-profile-avatar">P</div>
          <span class="settings-profile-name">Plex Profile</span>
        </div>
        <div class="settings-rail-categories">
          <button type="button" data-settings-category="playback" data-focus-id="settings-cat-playback" class="settings-cat-btn">Playback</button>
          <button type="button" data-settings-category="guide" data-focus-id="settings-cat-guide" class="settings-cat-btn">Guide</button>
          <button type="button" data-settings-category="setup" data-focus-id="settings-cat-setup" class="settings-cat-btn">Recovery</button>
        </div>
        <div class="settings-rail-nav">
          <button type="button" data-route-action="openChannelSetup" data-focus-id="settings-setup">Channel setup</button>
          <button type="button" data-route-action="resumePlayer" data-focus-id="settings-player">Back to player</button>
        </div>
      </nav>
      <main class="settings-detail-pane">
        <header class="settings-detail-header">
          <p class="screen__kicker" data-workflow-kicker="settings">Settings</p>
          <h2 id="screen-settings-title">Settings</h2>
          <p class="settings-subtitle" data-workflow-primary="settings">Desktop preferences.</p>
          <p data-workflow-secondary="settings" style="display: none;"></p>
        </header>
        <dl class="settings-summary" style="display: none;">
          <div><dt>Source</dt><dd data-settings-source></dd></div>
          <div><dt>Channels</dt><dd data-settings-channels></dd></div>
          <div><dt>Status</dt><dd data-settings-state></dd></div>
        </dl>
        <div class="settings-sections" data-settings-sections></div>
      </main>
    </div>
  </section>
  <section id="screen-channel-setup" class="screen screen--onboarding" data-screen="channelSetup" data-style-surface="screen" aria-labelledby="screen-channel-setup-title" hidden>
    <div class="screen__content plex-onboarding-shell">
      <nav class="setup-rail" aria-label="Setup stages">
        <div class="setup-profile-row">
          <div class="setup-profile-avatar">S</div>
          <span class="setup-profile-name">Setup Stages</span>
        </div>
        <div class="setup-rail-stages">
          <button type="button" data-setup-stage="account" data-focus-id="setup-stage-account" class="setup-stage-btn">1. Sign In</button>
          <button type="button" data-setup-stage="server" data-focus-id="setup-stage-server" class="setup-stage-btn">2. Choose Server</button>
          <button type="button" data-setup-stage="library" data-focus-id="setup-stage-library" class="setup-stage-btn">3. Browse Library</button>
          <button type="button" data-setup-stage="preview" data-focus-id="setup-stage-preview" class="setup-stage-btn">4. Media Preview</button>
          <button type="button" data-setup-stage="build" data-focus-id="setup-stage-build" class="setup-stage-btn">5. Build Lineup</button>
          <button type="button" data-setup-stage="custom" data-focus-id="setup-stage-custom" class="setup-stage-btn">6. Custom Channels</button>
        </div>
        <div class="setup-rail-nav">
          <button type="button" data-route-action="openSettings" data-focus-id="setup-settings">Settings</button>
          <button type="button" data-route-action="resumePlayer" data-focus-id="setup-player">Back to player</button>
        </div>
      </nav>
      <main class="setup-detail-pane">
        <header class="plex-onboarding-hero">
          <p class="screen__kicker" data-workflow-kicker="channelSetup">Channel setup</p>
          <h2 id="screen-channel-setup-title">Plex setup</h2>
          <p data-workflow-primary="channelSetup">Connect Plex, choose a profile and server, then browse your library.</p>
          <p data-workflow-secondary="channelSetup">Lineup Desktop shows the account, server, library, and media details needed for setup.</p>
        </header>
        <div class="screen-shell-state" data-shell-state="loading">
          <span>Persisted setup status</span>
          <strong data-screen-state-text="channelSetup">Review account, server, library, and persisted channel recovery in one place.</strong>
        </div>
        <div class="setup-sections" data-plex-runtime-panel>
          <section class="plex-runtime__stage setup-section" data-setup-section="account" aria-labelledby="plex-stage-account">
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
          <section class="plex-runtime__stage setup-section" data-setup-section="server" aria-labelledby="plex-stage-server" hidden>
            <h4 id="plex-stage-server">2. Choose server</h4>
            <p class="plex-runtime__stage-copy">Pick the Plex server Lineup Desktop should use for this profile.</p>
            <div class="plex-runtime__controls" aria-label="Plex server controls">
              <button type="button" data-plex-action="restoreSelectedServer" data-focus-id="plex-restore-server">Use saved server</button>
              <button type="button" data-plex-action="refreshServers" data-focus-id="plex-refresh-servers">Find servers</button>
              <button type="button" data-plex-action="clearSelectedServer" data-focus-id="plex-clear-server">Change server</button>
            </div>
            <div class="plex-runtime__list" data-plex-servers></div>
          </section>
          <section class="plex-runtime__stage setup-section" data-setup-section="library" aria-labelledby="plex-stage-library" hidden>
            <h4 id="plex-stage-library">3. Browse library</h4>
            <p class="plex-runtime__stage-copy">Choose a movie or show library section. Media items below are for metadata preview only.</p>
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
          <section class="plex-runtime__stage plex-runtime__stage--secondary setup-section" data-setup-section="preview" aria-labelledby="plex-stage-metadata" hidden>
            <h4 id="plex-stage-metadata">Optional media preview</h4>
            <p class="plex-runtime__stage-copy">Review a selected media summary only if needed. Channel creation uses the selected library section.</p>
            <button type="button" data-plex-action="clearMetadata" data-focus-id="plex-clear-metadata">Close preview</button>
            <div class="plex-runtime__metadata" data-plex-metadata></div>
          </section>
          <section class="channel-setup-commit setup-section" data-setup-section="build" aria-labelledby="channel-setup-commit-title" hidden>
            <header>
              <div>
                <p class="screen__kicker">Channel setup</p>
                <h3 id="channel-setup-commit-title">Build channels</h3>
              </div>
              <strong data-channel-setup-status></strong>
            </header>
            <ol class="setup-steps" data-channel-review-steps></ol>
            <dl class="setup-summary">
              <div><dt>Source</dt><dd data-channel-setup-source></dd></div>
              <div><dt>Enabled channels</dt><dd data-channel-setup-enabled></dd></div>
              <div><dt>Blocks</dt><dd data-channel-setup-blocks></dd></div>
            </dl>
            <div class="setup-review">
              <section>
                <h4>1. Library source</h4>
                <div class="channel-draft-list" data-channel-review-list></div>
              </section>
              <section>
                <h4>2. Strategy</h4>
                <div class="setup-list" data-channel-strategy-options></div>
              </section>
              <section>
                <h4>3. Review</h4>
                <div class="setup-preview-rows" data-channel-review-impact></div>
              </section>
              <section>
                <h4>4. Result</h4>
                <div class="setup-validation" data-channel-review-validation></div>
                <div class="setup-result" data-channel-setup-result></div>
              </section>
            </div>
            <div class="plex-runtime__controls" aria-label="Channel setup commit controls">
              <button type="button" data-channel-commit-action="append" data-focus-id="channel-append">Confirm & Build</button>
              <button type="button" data-channel-commit-action="replace" data-focus-id="channel-replace">Review replacement</button>
              <button type="button" data-channel-commit-action="confirmReplace" data-focus-id="channel-confirm-replace">Confirm & Replace</button>
            </div>
          </section>
          <section class="custom-channel-workspace setup-section" data-custom-channel-panel data-setup-section="custom" aria-labelledby="custom-channel-workspace-title" hidden>
            <header class="custom-channel-workspace__header">
              <div>
                <p class="screen__kicker">Custom channels</p>
                <h3 id="custom-channel-workspace-title">Author channels</h3>
              </div>
              <p data-custom-channel-status>Custom channels have not loaded yet.</p>
              <button type="button" data-custom-channel-action="loadSnapshot" data-focus-id="custom-channel-refresh">Refresh</button>
            </header>
            <div class="custom-channel-workspace__grid">
              <section class="custom-channel-panel custom-channel-panel--list" aria-label="Saved custom channels">
                <h4>Saved channels</h4>
                <div class="custom-channel-list" data-custom-channel-list></div>
              </section>
              <section class="custom-channel-panel custom-channel-panel--media" aria-label="Custom channel media picker">
                <header class="custom-channel-panel__toolbar">
                  <h4>Media picker</h4>
                  <div class="custom-channel-search">
                    <input data-custom-channel-search-query data-focus-id="custom-channel-search-query" maxlength="128" aria-label="Custom channel media search" />
                    <button type="button" data-custom-channel-action="browseSource" data-focus-id="custom-channel-browse">Browse source</button>
                    <button type="button" data-custom-channel-action="searchMedia" data-focus-id="custom-channel-search">Search</button>
                    <button type="button" data-custom-channel-action="clearSearch" data-focus-id="custom-channel-clear-search">Clear</button>
                  </div>
                  <div class="custom-channel-filterbar" aria-label="Media filters">
                    <button type="button" data-custom-channel-action="setFilterAll" data-focus-id="custom-channel-filter-all">All</button>
                    <button type="button" data-custom-channel-action="setFilterMovies" data-focus-id="custom-channel-filter-movies">Movies</button>
                    <button type="button" data-custom-channel-action="setFilterEpisodes" data-focus-id="custom-channel-filter-episodes">Episodes</button>
                  </div>
                </header>
                <div class="custom-channel-media-grid" data-custom-channel-media></div>
              </section>
              <section class="custom-channel-panel custom-channel-panel--draft" aria-label="Custom channel editor">
                <h4>Channel editor</h4>
                <label class="custom-channel-field">
                  <span>Name</span>
                  <input data-custom-channel-name data-focus-id="custom-channel-name" maxlength="120" />
                </label>
                <label class="custom-channel-field">
                  <span>Number</span>
                  <input data-custom-channel-number data-focus-id="custom-channel-number" inputmode="numeric" maxlength="3" />
                </label>
                <button type="button" data-custom-channel-action="toggleDraftHidden" data-focus-id="custom-channel-hidden">Toggle hidden</button>
                <div data-custom-channel-draft></div>
                <button type="button" data-custom-channel-action="saveDraft" data-focus-id="custom-channel-save">Save custom channel</button>
              </section>
            </div>
          </section>
        </div>
      </main>
      <div class="profile-pin-modal" id="profile-pin-modal" hidden>
        <div class="profile-pin-modal__dialog">
          <header class="profile-pin-modal__header">
            <h3 id="profile-pin-modal-title">Enter Profile PIN</h3>
            <p class="profile-pin-modal__user-name" id="profile-pin-modal-username"></p>
          </header>
          <div class="profile-pin-modal__slots">
            <span class="profile-pin-modal__slot" data-pin-slot="0"></span>
            <span class="profile-pin-modal__slot" data-pin-slot="1"></span>
            <span class="profile-pin-modal__slot" data-pin-slot="2"></span>
            <span class="profile-pin-modal__slot" data-pin-slot="3"></span>
          </div>
          <p class="profile-pin-modal__error" id="profile-pin-modal-error" hidden>Incorrect PIN. Please try again.</p>
          <div class="profile-pin-modal__numpad">
            <button type="button" class="numpad-btn" data-numpad="1" data-focus-id="numpad-1">1</button>
            <button type="button" class="numpad-btn" data-numpad="2" data-focus-id="numpad-2">2</button>
            <button type="button" class="numpad-btn" data-numpad="3" data-focus-id="numpad-3">3</button>
            <button type="button" class="numpad-btn" data-numpad="4" data-focus-id="numpad-4">4</button>
            <button type="button" class="numpad-btn" data-numpad="5" data-focus-id="numpad-5">5</button>
            <button type="button" class="numpad-btn" data-numpad="6" data-focus-id="numpad-6">6</button>
            <button type="button" class="numpad-btn" data-numpad="7" data-focus-id="numpad-7">7</button>
            <button type="button" class="numpad-btn" data-numpad="8" data-focus-id="numpad-8">8</button>
            <button type="button" class="numpad-btn" data-numpad="9" data-focus-id="numpad-9">9</button>
            <button type="button" class="numpad-btn numpad-btn--clear" data-numpad="clear" data-focus-id="numpad-clear">Clear</button>
            <button type="button" class="numpad-btn" data-numpad="0" data-focus-id="numpad-0">0</button>
            <button type="button" class="numpad-btn numpad-btn--cancel" data-numpad="cancel" data-focus-id="numpad-cancel">Cancel</button>
          </div>
        </div>
      </div>
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
