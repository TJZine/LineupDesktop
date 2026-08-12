import { mountShellDom } from './shell/shellDom.js';
import { createLineupBrandGlyph } from './onboarding/lineupBrandGlyph.js';
import { PLAYER_OVERLAY_MARKUP } from './playerOverlayDom.js';

const STATIC_SCREEN_MARKUP = `
<section class="screen-stack" data-static-screens-mounted>
  <div class="player-presentation" data-player-presentation-surface data-native-presentation-aperture="opaque" aria-hidden="true" inert></div>
  <section id="screen-player" class="screen screen--active screen--player" data-screen="player" data-style-surface="screen" aria-label="Player">
      ${PLAYER_OVERLAY_MARKUP}
      <aside class="setup-reminder" data-setup-reminder="player" aria-label="Channel setup reminder" hidden><span>No channels are ready yet.</span><button type="button" data-route-action="openChannelSetup">Set up channels</button></aside>
  </section>
  <section id="screen-guide" class="screen" data-screen="guide" data-guide-layout="classic" data-style-surface="screen" aria-labelledby="screen-guide-title" hidden>
    <div class="screen__content">
      <div class="screen-shell-state" data-shell-state="active">
        <span>Guide</span>
        <strong data-screen-state-text="guide">Guide rows show the current lineup.</strong>
      </div>
      <p class="screen__kicker" data-workflow-kicker="guide">Guide</p>
      <h2 id="screen-guide-title">Guide</h2>
      <p data-workflow-primary="guide">Tonight at a glance.</p>
      <p data-workflow-secondary="guide">Use directional controls to move through time windows, channels, and programs.</p>
      <section class="guide-detail" data-guide-layout="classic" data-guide-composition="classic" aria-label="Selected guide program">
        <div class="guide-detail__background" data-epg-detail-background data-background-state="missing" data-background-source="theme" aria-hidden="true">
          <img data-epg-detail-background-image alt="" aria-hidden="true" decoding="async" draggable="false" hidden>
        </div>
        <figure data-epg-detail-artwork data-artwork-state="missing">
          <img data-epg-detail-poster alt="" decoding="async" draggable="false" hidden>
          <span data-epg-detail-artwork-placeholder aria-hidden="true">Artwork unavailable</span>
        </figure>
        <div class="guide-detail__copy" data-guide-info-panel>
          <div class="guide-detail__identity" role="status" aria-live="polite" aria-atomic="true">
            <p class="guide-detail__channel" data-epg-detail-channel></p>
            <p class="guide-detail__eyebrow" data-epg-detail-eyebrow></p>
            <h3 data-epg-detail-title data-title-fallback="text"></h3>
            <p class="guide-detail__subtitle" data-epg-detail-subtitle></p>
            <p class="guide-detail__time" data-epg-detail-time></p>
          </div>
          <div class="guide-detail__metadata">
            <div class="guide-detail__badges" data-epg-detail-badges role="group" aria-label="Program details">
              <span data-epg-detail-badge-slot="0" hidden></span>
              <span data-epg-detail-badge-slot="1" hidden></span>
              <span data-epg-detail-badge-slot="2" hidden></span>
              <span data-epg-detail-badge-slot="3" hidden></span>
              <span data-epg-detail-badge-slot="4" hidden></span>
            </div>
            <p class="guide-detail__genres" data-epg-detail-genres></p>
            <p class="guide-detail__description" data-epg-detail-description></p>
          </div>
        </div>
      </section>
      <div id="guide-grid" class="epg-grid" data-epg-grid role="grid" aria-label="Guide schedule grid"></div>
    </div>
  </section>
  <section id="screen-settings" class="screen" data-screen="settings" data-style-surface="screen" aria-labelledby="screen-settings-title" hidden>
    <div class="screen__content settings-shell">
      <nav class="settings-rail" aria-label="Settings categories">
        <div class="settings-profile-row">
          <div class="settings-profile-avatar">P</div>
          <span class="settings-profile-name" data-settings-profile-name>No profile selected.</span>
        </div>
        <div class="settings-rail-categories">
          <button type="button" data-settings-category="audio-subtitles" data-focus-id="settings-category-audio-subtitles" class="settings-cat-btn">Audio &amp; Subtitles</button>
          <button type="button" data-settings-category="playback-hdr" data-focus-id="settings-category-playback-hdr" class="settings-cat-btn">Playback &amp; HDR</button>
          <button type="button" data-settings-category="appearance" data-focus-id="settings-category-appearance" class="settings-cat-btn">Appearance</button>
          <button type="button" data-settings-category="guide" data-focus-id="settings-category-guide" class="settings-cat-btn">Guide</button>
          <button type="button" data-settings-category="account" data-focus-id="settings-category-account" class="settings-cat-btn">Account</button>
          <button type="button" data-settings-category="developer" data-focus-id="settings-category-developer" class="settings-cat-btn">Developer</button>
          <button type="button" data-settings-category="recovery" data-focus-id="settings-category-recovery" class="settings-cat-btn">Recovery</button>
        </div>
        <div class="settings-rail-nav">
          <button type="button" data-settings-action="switchProfile" data-focus-id="settings-switch-profile">Switch Profile</button>
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

  <section id="screen-audio-setup" class="screen" data-screen="audioSetup" data-style-surface="screen" aria-labelledby="audio-setup-title" hidden>
    <div class="screen__content audio-setup-shell">
      <p class="screen__kicker">First-run setup</p>
      <h2 id="audio-setup-title">Audio Setup</h2>
      <p>Choose a renderer-safe audio output. You can change this later in Settings.</p>
      <p data-audio-setup-status role="status" aria-live="polite"></p>
      <div class="audio-output-list" data-audio-setup-outputs></div>
      <button type="button" data-audio-setup-action="complete" data-focus-id="audio-setup-complete">Use selected output</button>
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
        <div class="setup-status" data-setup-library-status role="status"></div>
        <div class="setup-owner__body"><div class="setup-library-toolbar"><button type="button" data-setup-flow-action="librarySelectAll" data-focus-id="setup-select-all">Select All</button><button type="button" data-setup-flow-action="libraryClearAll" data-focus-id="setup-clear-all">Clear All</button></div><p class="setup-limit-message" data-setup-limit-message hidden>Up to 24 libraries can be selected.</p><div class="setup-library-list" data-plex-sections></div><div class="setup-library-empty" data-setup-library-empty hidden><p>No movie or show libraries are available.</p><button type="button" data-setup-flow-action="libraryRetry" data-focus-id="setup-library-retry">Retry</button></div></div>
        <footer class="setup-owner__actions"><span data-channel-setup-source>No libraries selected</span><button type="button" data-setup-flow-action="libraryNext" data-focus-id="setup-next">Next</button><button type="button" data-setup-flow-action="setupBack" data-focus-id="setup-back">Back</button></footer>
      </section>
      <section class="setup-owner" data-staged-owner="preview" aria-labelledby="setup-preview-title" hidden>
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 2 of 3</span><div class="setup-owner__intro"><h3 id="setup-preview-title">Configure channels</h3><p>Choose how the selected libraries change your saved lineup.</p></div></header>
        <div class="setup-owner__body"><div class="setup-strategy-split"><nav class="setup-strategy-rail" aria-label="Channel categories"><button type="button" class="selected" aria-pressed="true" data-setup-flow-action="selectBuildCategory" data-focus-id="setup-category-build"><strong>Builder configuration</strong><span>Mode, limits, strategies, and variants</span></button></nav><section class="setup-builder-config" data-channel-builder-config aria-label="Channel builder configuration"></section></div><section class="setup-preview-strip"><button type="button" data-setup-flow-action="previewToggle" data-focus-id="setup-preview-toggle" aria-expanded="false">Library preview</button><div class="setup-preview-content" hidden><p data-setup-preview-status></p><div class="setup-preview-items" data-plex-items></div><div class="setup-preview-metadata" data-plex-metadata></div><button type="button" data-setup-flow-action="previewRetry" data-focus-id="setup-preview-retry" hidden>Retry preview</button></div></section></div>
        <footer class="setup-owner__actions"><button type="button" data-setup-flow-action="previewNext" data-focus-id="setup-next">Next</button><button type="button" data-setup-flow-action="setupBack" data-focus-id="setup-back">Back</button></footer>
      </section>
      <section class="setup-owner" data-staged-owner="build" aria-labelledby="channel-setup-commit-title" hidden>
        <header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 3 of 3</span><div class="setup-owner__intro"><h3 id="channel-setup-commit-title">Review and build</h3><p>Review the planned lineup change before the atomic build starts.</p></div></header>
        <div class="setup-owner__body setup-review-layout"><div class="setup-build-review"><div data-channel-review-list></div><div data-channel-review-impact></div><div data-channel-review-validation role="status"></div></div><aside class="setup-summary-card"><span>Saved lineup</span><strong data-channel-setup-enabled></strong><p><span data-channel-setup-blocks></span></p></aside></div>
        <footer class="setup-owner__actions"><button type="button" data-setup-flow-action="buildBack" data-focus-id="setup-back">Back</button><button type="button" data-setup-flow-action="buildConfirm" data-focus-id="setup-confirm">Build channels</button><button type="button" data-setup-flow-action="openReplaceConfirm" data-focus-id="setup-confirm-replace" hidden>Replace channels</button></footer>
      </section>
      <section class="setup-modal" data-staged-owner="replace-confirm" role="dialog" aria-modal="true" aria-labelledby="setup-replace-confirm-title" hidden><div class="setup-modal__dialog"><h2 id="setup-replace-confirm-title">Replace the saved lineup?</h2><p>Existing channels will be removed only after replacement channels are ready and the atomic save succeeds.</p><button type="button" data-setup-flow-action="cancelReplaceConfirm" data-focus-id="setup-replace-cancel">Keep saved lineup</button><button type="button" data-setup-flow-action="confirmReplace" data-focus-id="setup-replace-confirm">Replace and build</button></div></section>
      <section class="setup-owner" data-staged-owner="progress" aria-labelledby="setup-progress-title" hidden><header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 3 of 3</span><div class="setup-owner__intro"><h3 id="setup-progress-title">Preparing lineup</h3><p>Desktop is reviewing or applying the requested lineup.</p></div></header><div class="setup-owner__body setup-operation-state"><div class="setup-progress-bar" role="progressbar" aria-label="Channel setup progress"><span></span></div><p data-channel-operation-status role="status">Preparing selected libraries.</p></div><footer class="setup-owner__actions"><button type="button" data-setup-flow-action="progressCancel" data-focus-id="setup-progress-cancel">Cancel build</button></footer></section>
      <section class="setup-owner" data-staged-owner="result" aria-labelledby="setup-result-title" hidden><header class="setup-owner__header"><h2 class="setup-owner__title">Channel Setup</h2><span class="setup-owner__step">Step 3 of 3</span><div class="setup-owner__intro"><h3 id="setup-result-title" data-setup-result-title>Lineup ready</h3><p data-setup-result-intro>The saved channel summary has been refreshed.</p></div></header><div class="setup-owner__body setup-operation-state"><span class="setup-success-mark" data-setup-result-mark aria-hidden="true">✓</span><p data-channel-setup-result></p><div data-channel-setup-result-detail></div></div><footer class="setup-owner__actions"><button type="button" data-setup-flow-action="resultDone" data-focus-id="setup-done">Done</button><button type="button" data-setup-flow-action="resultWatch" data-focus-id="setup-result-watch">Watch built channel</button></footer></section>
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
