import { mountShellDom } from './shell/shellDom.js';
import { createLineupBrandGlyph } from './onboarding/lineupBrandGlyph.js';

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
  <section id="screen-player" class="screen screen--active screen--player" data-screen="player" data-style-surface="screen" aria-label="Player">
      <div class="player-quick-actions" aria-label="Player quick actions">
        <button type="button" data-route-action="openGuide" data-focus-id="player-guide">Open guide</button>
        <button type="button" data-route-action="openSettings" data-focus-id="player-settings">Settings</button>
        <button type="button" data-overlay-action="toggleOsd" data-focus-id="player-osd">Player controls</button>
        <button type="button" data-fullscreen-toggle data-focus-id="player-fullscreen" aria-pressed="false">Toggle fullscreen</button>
      </div>
      <aside class="setup-reminder" data-setup-reminder="player" aria-label="Channel setup reminder" hidden><span>No channels are ready yet.</span><button type="button" data-route-action="openChannelSetup">Set up channels</button></aside>
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
      <aside class="setup-reminder" data-setup-reminder="guide" aria-label="Channel setup reminder" hidden><span>Add channels to fill the Guide.</span><button type="button" data-route-action="openChannelSetup">Set up channels</button></aside>
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
          <button type="button" data-settings-category="appearance" data-focus-id="settings-category-appearance" class="settings-cat-btn">Appearance</button>
          <button type="button" data-settings-category="guide" data-focus-id="settings-category-guide" class="settings-cat-btn">Guide</button>
          <button type="button" data-settings-category="recovery" data-focus-id="settings-category-recovery" class="settings-cat-btn">Recovery</button>
        </div>
        <div class="settings-rail-nav">
          <button type="button" data-route-action="openChannelSetup" data-focus-id="settings-open-channel-setup">Channel setup</button>
          <button type="button" data-route-action="resumePlayer" data-focus-id="settings-player">Back to player</button>
        </div>
      </nav>
      <main class="settings-detail-pane">
        <header class="settings-detail-header">
          <p class="screen__kicker" data-workflow-kicker="settings">Settings</p>
          <h2 id="screen-settings-title">Settings</h2>
          <p class="settings-subtitle" data-workflow-primary="settings">Desktop preferences.</p>
          <p class="settings-error" data-settings-error role="status" hidden></p>
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
  <section id="screen-channel-setup" class="screen screen--onboarding" data-screen="channelSetup" data-style-surface="screen" data-plex-runtime-panel aria-labelledby="screen-channel-setup-title" hidden>
    <div class="onboarding-host" data-onboarding-host>
      <section class="onboarding-owner onboarding-auth" data-onboarding-owner="auth-link-code" aria-labelledby="auth-link-title" hidden>
        <div class="onboarding-panel">
          <header><h2 id="auth-link-title">Sign in to Plex</h2><p>Scan the QR code or visit plex.tv/link</p></header>
          <div class="auth-link-layout"><div class="auth-link-qr" data-plex-link-qr></div><p data-onboarding-status>Ready to request a sign-in code.</p></div>
          <div class="onboarding-actions"><button type="button" data-plex-action="requestPin" data-focus-id="btn-auth-request">Request PIN</button></div>
        </div>
      </section>
      <section class="onboarding-owner onboarding-auth" data-onboarding-owner="auth-waiting" aria-labelledby="auth-waiting-title" hidden>
        <div class="onboarding-panel">
          <header><h2 id="auth-waiting-title">Sign in to Plex</h2><p>Scan the QR code or visit plex.tv/link</p></header>
          <div class="auth-link-layout"><div class="auth-link-qr" data-plex-link-qr></div><div class="auth-code" data-plex-pin></div></div>
          <p data-onboarding-status aria-live="polite">Waiting for sign-in…</p>
          <div class="onboarding-actions"><button type="button" data-plex-action="cancelPin" data-focus-id="btn-auth-cancel">Cancel</button></div>
        </div>
      </section>
      <section class="onboarding-owner onboarding-auth" data-onboarding-owner="auth-error" aria-labelledby="auth-error-title" hidden>
        <div class="onboarding-panel">
          <header><h2 id="auth-error-title">Sign in to Plex</h2><p>Scan the QR code or visit plex.tv/link</p></header>
          <div class="auth-code auth-code--idle" aria-hidden="true"><span>–</span><span>–</span><span>–</span><span>–</span></div>
          <div class="onboarding-error" role="alert" data-onboarding-error></div>
          <div class="onboarding-actions onboarding-actions--stacked"><button type="button" data-plex-action="requestPin" data-focus-id="btn-auth-retry">Retry</button><button type="button" data-plex-action="dismissPinError" data-focus-id="btn-auth-cancel">Cancel</button></div>
        </div>
      </section>
      <section class="onboarding-owner onboarding-profile" data-onboarding-owner="profile-select" aria-labelledby="profile-select-title" hidden>
        <div class="onboarding-panel">
          <header><span data-lineup-brand-glyph></span><h2 id="profile-select-title">Who's watching?</h2><p>Choose a Plex Home profile to continue.</p></header>
          <p data-onboarding-status aria-live="polite"></p>
          <div class="profile-list" data-plex-home-users role="listbox" aria-label="Plex Home profiles"></div>
          <div class="onboarding-error" role="alert" data-onboarding-error hidden></div>
        </div>
      </section>
      <section class="onboarding-owner onboarding-server" data-onboarding-owner="server-select" aria-labelledby="server-select-title" hidden>
        <div class="onboarding-panel">
          <header><span data-lineup-brand-glyph></span><h2 id="server-select-title">Select Plex Server</h2><p>Choose a server to continue setup.</p></header>
          <p data-onboarding-status aria-live="polite"></p>
          <div class="server-list" data-plex-servers role="listbox" aria-label="Plex servers"></div>
          <div class="onboarding-actions"><button type="button" data-plex-action="refreshServers" data-focus-id="btn-server-refresh">Refresh</button><button type="button" data-setup-stage="library" data-focus-id="btn-server-setup">Setup</button><button type="button" data-setup-stage="profile" data-focus-id="btn-server-switch-profile">Switch Profile</button></div>
        </div>
      </section>
      <section class="onboarding-owner onboarding-server" data-onboarding-owner="server-error" aria-labelledby="server-error-title" hidden>
        <div class="onboarding-panel">
          <header><span data-lineup-brand-glyph></span><h2 id="server-error-title">Select Plex Server</h2><p>Choose a server to continue setup.</p></header>
          <div class="onboarding-error" role="alert" data-onboarding-error></div>
          <div class="onboarding-actions onboarding-actions--stacked"><button type="button" data-plex-action="refreshServers" data-focus-id="btn-server-refresh">Refresh</button><button type="button" data-setup-stage="profile" data-focus-id="btn-server-switch-profile">Switch Profile</button></div>
        </div>
      </section>
    </div>
    <main class="setup-workflow" data-setup-workspace hidden>
      <section class="setup-owner" data-staged-owner="library" aria-labelledby="setup-library-title">
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 1 of 3</span><div class="setup-owner__intro"><h3 id="setup-library-title">Choose libraries</h3><p>Choose the movie and show libraries that should become channels.</p></div></header>
        <div class="setup-status" data-setup-library-status data-channel-setup-status role="status"></div>
        <div class="setup-owner__body"><div class="setup-library-toolbar"><button type="button" data-setup-flow-action="librarySelectAll" data-focus-id="setup-select-all">Select All</button><button type="button" data-setup-flow-action="libraryClearAll" data-focus-id="setup-clear-all">Clear All</button></div><p class="setup-limit-message" data-setup-limit-message hidden>Up to 24 libraries can be selected.</p><div class="setup-library-list" data-plex-sections></div><div class="setup-library-empty" data-setup-library-empty hidden><p>No movie or show libraries are available.</p><button type="button" data-setup-flow-action="libraryRetry" data-focus-id="setup-library-retry">Retry</button></div></div>
        <footer class="setup-owner__actions"><span data-channel-setup-source>No libraries selected</span><button type="button" data-setup-flow-action="libraryNext" data-focus-id="setup-next">Next</button><button type="button" data-setup-flow-action="setupBack" data-focus-id="setup-back">Back</button></footer>
      </section>
      <section class="setup-owner" data-staged-owner="preview" aria-labelledby="setup-preview-title" hidden>
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 2 of 3</span><div class="setup-owner__intro"><h3 id="setup-preview-title">Configure channels</h3><p>Choose how the selected libraries change your saved lineup.</p></div></header>
        <div class="setup-owner__body"><div class="setup-strategy-split"><nav class="setup-strategy-rail" aria-label="Channel categories"><button type="button" class="selected" aria-pressed="true" data-setup-flow-action="selectBuildCategory" data-focus-id="setup-category-build"><strong>Build mode</strong><span>Append, replace, or customize</span></button></nav><section class="setup-strategy-detail"><h3>Build mode</h3><p>Choose one real Desktop build operation.</p><button type="button" data-setup-action="selectAppendBuildMode" data-focus-id="channel-strategy-build-append">Append</button><button type="button" data-setup-action="selectReplaceBuildMode" data-focus-id="channel-strategy-build-replace">Replace</button><button type="button" data-setup-flow-action="openSetupCustom" data-focus-id="channel-strategy-build-custom">Custom <small>Desktop extension</small></button></section></div><section class="setup-preview-strip"><button type="button" data-setup-flow-action="previewToggle" data-focus-id="setup-preview-toggle" aria-expanded="false">Library preview</button><div class="setup-preview-content" hidden><p data-setup-preview-status></p><div class="setup-preview-items" data-plex-items></div><div class="setup-preview-metadata" data-plex-metadata></div><button type="button" data-setup-flow-action="previewRetry" data-focus-id="setup-preview-retry" hidden>Retry preview</button></div></section></div>
        <footer class="setup-owner__actions"><button type="button" data-setup-flow-action="previewNext" data-focus-id="setup-next">Next</button><button type="button" data-setup-flow-action="setupBack" data-focus-id="setup-back">Back</button></footer>
      </section>
      <section class="setup-owner" data-staged-owner="build" aria-labelledby="channel-setup-commit-title" hidden>
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 3 of 3</span><div class="setup-owner__intro"><h3 id="channel-setup-commit-title">Review and build</h3><p>Review the planned lineup change before the atomic build starts.</p></div></header>
        <div class="setup-owner__body setup-review-layout"><div class="setup-build-review"><div data-channel-review-list></div><div data-channel-review-impact></div><div data-channel-review-validation role="status"></div><button type="button" class="setup-replace-confirm" data-setup-flow-action="toggleReplaceConfirm" data-focus-id="setup-replace-confirm" aria-pressed="false" hidden>Confirm replacement of the saved lineup</button></div><aside class="setup-summary-card"><span>Saved lineup</span><strong data-channel-setup-enabled></strong><p><span data-channel-setup-blocks></span></p></aside></div>
        <footer class="setup-owner__actions"><button type="button" data-setup-flow-action="buildBack" data-focus-id="setup-back">Back</button><button type="button" data-setup-flow-action="buildConfirm" data-focus-id="setup-confirm">Build channels</button></footer>
      </section>
      <section class="setup-owner" data-staged-owner="progress" aria-labelledby="setup-progress-title" hidden><header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 3 of 3</span><div class="setup-owner__intro"><h3 id="setup-progress-title">Building lineup</h3><p>The atomic channel operation is in progress.</p></div></header><div class="setup-owner__body setup-operation-state"><div class="setup-progress-bar" role="progressbar"><span></span></div><p>Applying selected libraries. This view can be closed without claiming to cancel the saved operation.</p></div><footer class="setup-owner__actions"><button type="button" data-setup-flow-action="progressCancel" data-focus-id="setup-progress-cancel">Cancel build view</button></footer></section>
      <section class="setup-owner" data-staged-owner="result" aria-labelledby="setup-result-title" hidden><header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 3 of 3</span><div class="setup-owner__intro"><h3 id="setup-result-title">Lineup ready</h3><p>The saved channel summary has been refreshed.</p></div></header><div class="setup-owner__body setup-operation-state"><span class="setup-success-mark" aria-hidden="true">✓</span><p data-channel-setup-result></p></div><footer class="setup-owner__actions"><button type="button" data-setup-flow-action="resultDone" data-focus-id="setup-done">Done</button><button type="button" data-setup-flow-action="resultWatch" data-focus-id="setup-result-watch">Watch built channel</button></footer></section>
      <section class="setup-owner" data-staged-owner="recovery-error" aria-labelledby="setup-error-title" hidden><header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step" data-setup-recovery-step>Step 3 of 3</span><div class="setup-owner__intro"><h3 id="setup-error-title">Setup needs attention</h3><p>Retry the failed safe operation or return without changing the lineup.</p></div></header><div class="setup-owner__body setup-operation-state"><span class="setup-error-mark" aria-hidden="true">!</span><p data-setup-safe-error role="alert"></p></div><footer class="setup-owner__actions"><button type="button" data-setup-flow-action="recoveryRetry" data-focus-id="setup-error-retry">Retry</button><button type="button" data-setup-flow-action="setupBack" data-focus-id="setup-error-back">Back</button></footer></section>
      <section class="setup-owner custom-channel-workspace" data-staged-owner="custom-list" data-custom-channel-panel aria-labelledby="custom-channel-workspace-title" hidden>
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Desktop extension</span><div class="setup-owner__intro"><h3 id="custom-channel-workspace-title">Custom channels</h3><p>Duplicate a saved channel or start with a blank channel.</p><span data-custom-channel-status></span></div></header>
        <div class="setup-owner__body custom-channel-list" data-custom-channel-list></div>
        <footer class="setup-owner__actions"><button type="button" data-setup-flow-action="customNew" data-focus-id="custom-channel-new">New custom channel</button><button type="button" data-setup-flow-action="customDone" data-focus-id="setup-done">Finish setup</button><button type="button" data-setup-flow-action="customBack" data-focus-id="setup-back">Back</button><button type="button" data-setup-flow-action="customBack" data-focus-id="custom-channel-back" hidden>Back to setup</button></footer>
      </section>
      <section class="setup-owner custom-channel-editor" data-staged-owner="custom-edit" aria-labelledby="custom-channel-editor-title" hidden>
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Desktop extension</span><div class="setup-owner__intro"><h3 id="custom-channel-editor-title">Channel editor</h3><p>Choose a name, number, and playable media.</p><span>New or duplicate</span></div></header>
        <div class="setup-owner__body custom-editor-layout"><section class="custom-editor-fields"><label class="custom-channel-field"><span>Name</span><input data-custom-channel-name data-focus-id="custom-channel-name" maxlength="120" /></label><label class="custom-channel-field"><span>Number</span><input data-custom-channel-number data-focus-id="custom-channel-number" inputmode="numeric" maxlength="3" /></label><button type="button" data-custom-channel-action="toggleDraftHidden" data-focus-id="custom-channel-hidden">Toggle hidden</button><div data-custom-channel-draft></div></section><section class="custom-editor-media"><div class="custom-channel-search"><input data-custom-channel-search-query data-focus-id="custom-channel-search-query" maxlength="128" aria-label="Custom channel media search" /><button type="button" data-custom-channel-action="browseSource" data-focus-id="custom-channel-browse">Browse source</button><button type="button" data-custom-channel-action="searchMedia" data-focus-id="custom-channel-search">Search</button><button type="button" data-custom-channel-action="clearSearch" data-focus-id="custom-channel-clear-search">Clear</button></div><div class="custom-channel-filterbar"><button type="button" data-custom-channel-action="setFilterAll" data-focus-id="custom-channel-filter-all">All</button><button type="button" data-custom-channel-action="setFilterMovies" data-focus-id="custom-channel-filter-movies">Movies</button><button type="button" data-custom-channel-action="setFilterEpisodes" data-focus-id="custom-channel-filter-episodes">Episodes</button></div><div class="custom-channel-media-grid" data-custom-channel-media></div></section></div>
        <footer class="setup-owner__actions"><button type="button" data-custom-channel-action="saveDraft" data-focus-id="custom-channel-save">Save custom channel</button><button type="button" data-setup-flow-action="customCancel" data-focus-id="custom-channel-cancel">Cancel</button></footer>
      </section>
      <section class="setup-modal" data-staged-owner="custom-delete-confirm" role="dialog" aria-modal="true" aria-labelledby="custom-delete-title" hidden><div class="setup-modal__dialog"><h2 id="custom-delete-title">Delete custom channel?</h2><p>The saved channel will be removed from this lineup.</p><p data-custom-delete-error role="alert"></p><button type="button" data-setup-flow-action="customDeleteCancel" data-focus-id="custom-delete-cancel">Cancel channel deletion</button><button type="button" data-custom-channel-action="confirmDeleteChannel" data-focus-id="custom-delete-confirm">Delete custom channel</button></div></section>
      <input data-plex-search-query hidden aria-hidden="true" tabindex="-1" />
      <div data-channel-review-steps hidden></div><div data-channel-strategy-options hidden></div>
    </main>
    <div class="profile-pin-modal" id="profile-pin-modal" role="dialog" aria-modal="true" aria-labelledby="profile-pin-modal-title" aria-hidden="true" hidden>
        <div class="profile-pin-modal__dialog">
          <div class="profile-pin-user" aria-hidden="true">
            <div class="profile-pin-avatar profile-pin-avatar-fallback" data-profile-pin-avatar></div>
          </div>
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
          <div class="profile-pin-modal__numpad">
            <button type="button" class="numpad-btn" data-numpad="1" data-focus-id="btn-profile-pin-1">1</button>
            <button type="button" class="numpad-btn" data-numpad="2" data-focus-id="btn-profile-pin-2">2</button>
            <button type="button" class="numpad-btn" data-numpad="3" data-focus-id="btn-profile-pin-3">3</button>
            <button type="button" class="numpad-btn" data-numpad="4" data-focus-id="btn-profile-pin-4">4</button>
            <button type="button" class="numpad-btn" data-numpad="5" data-focus-id="btn-profile-pin-5">5</button>
            <button type="button" class="numpad-btn" data-numpad="6" data-focus-id="btn-profile-pin-6">6</button>
            <button type="button" class="numpad-btn" data-numpad="7" data-focus-id="btn-profile-pin-7">7</button>
            <button type="button" class="numpad-btn" data-numpad="8" data-focus-id="btn-profile-pin-8">8</button>
            <button type="button" class="numpad-btn" data-numpad="9" data-focus-id="btn-profile-pin-9">9</button>
            <button type="button" class="numpad-btn numpad-btn--backspace" data-numpad="backspace" data-focus-id="btn-profile-pin-backspace" aria-label="Backspace">←</button>
            <button type="button" class="numpad-btn" data-numpad="0" data-focus-id="btn-profile-pin-0">0</button>
          </div>
          <p class="profile-pin-modal__error" id="profile-pin-modal-error" hidden>Incorrect PIN. Please try again.</p>
          <button type="button" class="profile-pin-cancel" data-numpad="cancel" data-focus-id="btn-profile-pin-cancel">Cancel</button>
        </div>
    </div>
  </section>
</section>`;

export function mountStaticRendererDom(documentRef: Document = document): void {
  const root = documentRef.querySelector<HTMLElement>('[data-static-screen-root]');
  if (root === null || root.querySelector('[data-static-screens-mounted]') !== null) {
    return;
  }

  mountShellDom(root, STATIC_SCREEN_MARKUP);
  mountLineupBrandGlyphs(root, documentRef);
}

function mountLineupBrandGlyphs(root: HTMLElement, documentRef: Document): void {
  const querySelectorAll = Reflect.get(root, 'querySelectorAll');
  if (typeof querySelectorAll !== 'function') return;
  const placeholders = Array.from(
    root.querySelectorAll<HTMLElement>('[data-lineup-brand-glyph]'),
  );
  for (const placeholder of placeholders) {
    placeholder.replaceWith(createLineupBrandGlyph('lineup-glyph', documentRef));
  }
}
