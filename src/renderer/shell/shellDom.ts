import type { RendererShellState } from './shellState.js';

const SHELL_SURFACE_MARKUP = `
  <div class="shell-diagnostics" hidden aria-hidden="true">
    <span data-shell-status>booting</span>
    <span data-shell-capabilities>loading</span>
  </div>
  <section class="shell-bootstrap shell-bootstrap--splash" data-shell-surface="splash" role="region" aria-label="Lineup starting">
    <div class="shell-splash-scene">
      <div class="shell-splash-ambient" aria-hidden="true"></div>
      <div class="shell-splash-content">
        <div class="shell-splash-brand">
          <div class="shell-splash-logo-shell"><img class="shell-splash-logo" src="./assets/lineup-logo-mark.png" alt="" decoding="sync" aria-hidden="true" /></div>
          <img class="shell-splash-wordmark" src="./assets/lineup-wordmark.png" alt="Lineup" decoding="sync" />
        </div>
        <p>Connecting Plex and preparing your lineup.</p>
        <strong>STARTING UP…</strong>
      </div>
    </div>
  </section>
  <section class="shell-bootstrap shell-bootstrap--loading" data-shell-surface="loading" role="region" aria-label="Lineup preparing" hidden aria-hidden="true">
    <div class="shell-splash-scene">
      <div class="shell-splash-ambient" aria-hidden="true"></div>
      <div class="shell-splash-content">
        <div class="shell-splash-brand">
          <div class="shell-splash-logo-shell"><img class="shell-splash-logo" src="./assets/lineup-logo-mark.png" alt="" decoding="sync" aria-hidden="true" /></div>
          <img class="shell-splash-wordmark" src="./assets/lineup-wordmark.png" alt="Lineup" decoding="sync" />
        </div>
        <p>Connecting Plex and preparing your lineup.</p>
        <strong>PREPARING YOUR LINEUP…</strong>
      </div>
    </div>
  </section>
  <section class="shell-blocking-error" data-shell-surface="blocking-error" role="region" aria-label="Blocking error" hidden aria-hidden="true">
    <div class="shell-blocking-error__panel">
      <h2>Something went wrong</h2>
      <p data-shell-blocking-error-message>Lineup could not start.</p>
      <div class="shell-action-row">
        <button type="button" data-shell-action="retry-startup" data-focus-id="shell-error-retry" aria-label="Retry startup">Try again</button>
        <button type="button" data-shell-action="exit" data-focus-id="shell-error-exit" aria-label="Exit Lineup">Exit</button>
      </div>
    </div>
  </section>
  <section class="shell-inline-error" data-shell-surface="inline-error" role="alertdialog" aria-modal="true" aria-labelledby="shell-inline-error-title" aria-describedby="shell-inline-error-description" hidden aria-hidden="true">
    <div class="shell-inline-error__panel">
      <h3 id="shell-inline-error-title">Could not change fullscreen</h3>
      <p id="shell-inline-error-description" data-shell-inline-error-message>Try the fullscreen action again.</p>
      <div class="shell-action-row">
        <button type="button" data-shell-action="dismiss-inline-error" data-focus-id="shell-inline-dismiss" aria-label="Dismiss error">Dismiss</button>
        <button type="button" data-shell-action="retry-fullscreen" data-focus-id="shell-inline-retry" aria-label="Retry action">Try again</button>
      </div>
    </div>
  </section>
  <div class="shell-toast" data-shell-surface="toast" role="status" aria-live="polite" aria-atomic="true" hidden aria-hidden="true">
    <span aria-hidden="true">✓</span><strong data-shell-toast-message></strong>
  </div>
  <section class="shell-exit-confirm" data-shell-surface="exit-confirm" role="dialog" aria-modal="true" aria-labelledby="exit-confirm-title" hidden aria-hidden="true">
    <div>
      <h2 id="exit-confirm-title">Exit Lineup?</h2>
      <p>Playback will stop.</p>
    </div>
    <div class="shell-action-row">
      <button type="button" data-shell-action="cancel-exit" data-focus-id="exit-confirm-cancel" aria-label="Cancel exit">Keep watching</button>
      <button type="button" data-shell-action="confirm-exit" data-focus-id="exit-confirm-exit" aria-label="Exit Lineup">Exit</button>
    </div>
  </section>`;

export interface ShellDomBindings {
  playerPresentation: HTMLElement | null;
  splash: HTMLElement | null;
  loading: HTMLElement | null;
  blockingError: HTMLElement | null;
  blockingErrorMessage: HTMLElement | null;
  retryStartupButton: HTMLButtonElement | null;
  blockingExitButton: HTMLButtonElement | null;
  inlineError: HTMLElement | null;
  inlineErrorMessage: HTMLElement | null;
  inlineDismissButton: HTMLButtonElement | null;
  inlineRetryButton: HTMLButtonElement | null;
  toast: HTMLElement | null;
  toastMessage: HTMLElement | null;
  exitConfirm: HTMLElement | null;
  exitCancelButton: HTMLButtonElement | null;
  exitButton: HTMLButtonElement | null;
}

export function mountShellDom(root: HTMLElement, screenMarkup: string): void {
  root.innerHTML = `${screenMarkup}${SHELL_SURFACE_MARKUP}`;
}

export function queryShellDom(documentRef: Document = document): ShellDomBindings {
  return {
    playerPresentation: documentRef.querySelector('[data-player-presentation-surface]'),
    splash: documentRef.querySelector('[data-shell-surface="splash"]'),
    loading: documentRef.querySelector('[data-shell-surface="loading"]'),
    blockingError: documentRef.querySelector('[data-shell-surface="blocking-error"]'),
    blockingErrorMessage: documentRef.querySelector('[data-shell-blocking-error-message]'),
    retryStartupButton: documentRef.querySelector('[data-shell-action="retry-startup"]'),
    blockingExitButton: documentRef.querySelector('[data-shell-action="exit"]'),
    inlineError: documentRef.querySelector('[data-shell-surface="inline-error"]'),
    inlineErrorMessage: documentRef.querySelector('[data-shell-inline-error-message]'),
    inlineDismissButton: documentRef.querySelector('[data-shell-action="dismiss-inline-error"]'),
    inlineRetryButton: documentRef.querySelector('[data-shell-action="retry-fullscreen"]'),
    toast: documentRef.querySelector('[data-shell-surface="toast"]'),
    toastMessage: documentRef.querySelector('[data-shell-toast-message]'),
    exitConfirm: documentRef.querySelector('[data-shell-surface="exit-confirm"]'),
    exitCancelButton: documentRef.querySelector('[data-shell-action="cancel-exit"]'),
    exitButton: documentRef.querySelector('[data-shell-action="confirm-exit"]'),
  };
}

export function renderShellDom(
  state: RendererShellState,
  bindings: ShellDomBindings,
  screens: readonly HTMLElement[],
): void {
  const blockingOwner = state.bootstrap !== 'ready';
  setOwnerVisible(bindings.splash, state.bootstrap === 'splash');
  setOwnerVisible(bindings.loading, state.bootstrap === 'loading');
  setOwnerVisible(bindings.blockingError, state.bootstrap === 'error');
  setOwnerVisible(bindings.inlineError, !blockingOwner && state.inlineError !== null);
  setOwnerVisible(bindings.toast, !blockingOwner && state.toast !== null);
  setOwnerVisible(bindings.exitConfirm, !blockingOwner && state.exitConfirmOpen);

  if (bindings.blockingErrorMessage) {
    bindings.blockingErrorMessage.textContent = state.blockingErrorMessage ?? 'Lineup could not start.';
  }
  if (bindings.inlineErrorMessage) {
    bindings.inlineErrorMessage.textContent = state.inlineError?.message ?? '';
  }
  if (bindings.toastMessage) {
    bindings.toastMessage.textContent = state.toast?.message ?? '';
  }
  bindings.toast?.classList.toggle('shell-toast--fading', state.toast?.phase === 'fading');
  setPending(bindings.retryStartupButton, state.bootstrap === 'loading');
  setPending(bindings.inlineRetryButton, state.fullscreenPending);

  const presentationRouteVisible = screens.some((screen) =>
    (screen.dataset.screen === 'player' || screen.dataset.screen === 'guide') && !screen.hidden);
  const presentationVisible = !blockingOwner && !state.exitConfirmOpen && presentationRouteVisible;
  const backgroundInteractive = state.inlineError === null;
  if (bindings.playerPresentation) {
    bindings.playerPresentation.hidden = !presentationVisible;
    bindings.playerPresentation.inert = true;
    bindings.playerPresentation.setAttribute('aria-hidden', 'true');
  }
  for (const screen of screens) {
    const routeVisible = !screen.hidden;
    const interactive = !blockingOwner && routeVisible && !state.exitConfirmOpen && backgroundInteractive;
    screen.hidden = blockingOwner || state.exitConfirmOpen || !routeVisible;
    setInteractive(screen, interactive, !interactive);
  }
}

function setOwnerVisible(element: HTMLElement | null, visible: boolean): void {
  if (element === null) return;
  element.hidden = !visible;
  element.setAttribute('aria-hidden', String(!visible));
  setInteractive(element, visible, !visible);
}

function setInteractive(element: HTMLElement, interactive: boolean, ariaHidden: boolean): void {
  element.inert = !interactive;
  element.setAttribute('aria-hidden', String(ariaHidden));
}

function setPending(button: HTMLButtonElement | null, pending: boolean): void {
  if (button === null) return;
  button.disabled = pending;
  button.setAttribute('aria-disabled', String(pending));
  button.setAttribute('aria-busy', String(pending));
}
