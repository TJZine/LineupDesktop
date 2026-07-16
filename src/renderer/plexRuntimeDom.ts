import type { PlexServerSummary } from '../contracts/plex.js';
import type { RendererDomBindings } from './domBindings.js';
import type { PlexRuntimeRendererState } from './plexRuntimeState.js';
import {
  renderHomeUsers,
  renderItems,
  renderMetadata,
  renderSections,
  renderServers,
} from './plexRuntimeRows.js';
import { createPlexLinkQr } from './onboarding/plexLinkQr.js';

export type PlexOnboardingStateId =
  | 'auth-link-code'
  | 'auth-waiting'
  | 'auth-error'
  | 'profile-select'
  | 'profile-pin'
  | 'server-select'
  | 'server-error';

const SETUP_STAGES = new Set(['library', 'preview', 'build', 'custom']);

export function readPlexOnboardingState(
  state: PlexRuntimeRendererState,
  activeSetupStage = 'account',
  profilePinActive = false,
): PlexOnboardingStateId | null {
  if (profilePinActive) return 'profile-pin';
  if (SETUP_STAGES.has(activeSetupStage)) return null;
  const authState = state.snapshot?.auth.state ?? 'signed-out';
  if (authState !== 'signed-in') {
    if (state.errorText !== null) return 'auth-error';
    return (state.snapshot?.auth.pin ?? null) === null ? 'auth-link-code' : 'auth-waiting';
  }
  if (activeSetupStage === 'server') {
    return state.errorText === null ? 'server-select' : 'server-error';
  }
  return 'profile-select';
}

export function renderPlexRuntimeDom(
  state: PlexRuntimeRendererState,
  dom: RendererDomBindings,
  activeSetupStage = 'account',
  profilePinActive = false,
  setupSelectedSectionIds: readonly string[] = [],
  previewBadgesEnabled = true,
): void {
  if (!dom.plexPanelElement) {
    return;
  }

  const snapshot = state.snapshot;
  const onboardingState = readPlexOnboardingState(state, activeSetupStage, profilePinActive);
  const supportsOnboardingDom = document.documentElement !== undefined
    && typeof document.querySelectorAll === 'function'
    && typeof document.querySelector === 'function';
  if (supportsOnboardingDom) document.documentElement.dataset.onboardingState = onboardingState ?? 'setup';
  for (const owner of supportsOnboardingDom ? Array.from(document.querySelectorAll<HTMLElement>('[data-onboarding-owner]')) : []) {
    const visible = owner.dataset.onboardingOwner === onboardingState
      || (onboardingState === 'profile-pin' && owner.dataset.onboardingOwner === 'profile-select');
    owner.hidden = !visible;
    owner.inert = !visible || onboardingState === 'profile-pin';
    owner.setAttribute('aria-hidden', String(!visible || onboardingState === 'profile-pin'));
  }
  const host = supportsOnboardingDom ? document.querySelector<HTMLElement>('[data-onboarding-host]') : null;
  if (host) {
    host.hidden = onboardingState === null;
    host.inert = onboardingState === null;
    host.setAttribute('aria-hidden', String(onboardingState === null));
  }
  const setupWorkspace = supportsOnboardingDom ? document.querySelector<HTMLElement>('[data-setup-workspace]') : null;
  if (setupWorkspace) {
    setupWorkspace.hidden = onboardingState !== null;
    setupWorkspace.inert = onboardingState !== null;
    setupWorkspace.setAttribute('aria-hidden', String(onboardingState !== null));
  }

  if (supportsOnboardingDom) ensureStaticLinkQrs();
  const activeOwner = onboardingState === null || onboardingState === 'profile-pin'
    ? null
    : supportsOnboardingDom ? document.querySelector<HTMLElement>(`[data-onboarding-owner="${onboardingState}"]`) : null;
  setText(
    activeOwner?.querySelector<HTMLElement>('[data-onboarding-status]') ?? null,
    onboardingState === null ? '' : onboardingStatus(state, onboardingState),
  );
  const activeError = activeOwner?.querySelector<HTMLElement>('[data-onboarding-error]') ?? null;
  setText(activeError, state.errorText ?? '');
  activeError?.toggleAttribute('hidden', state.errorText === null);
  setText(dom.plexStatusElement, state.statusText);
  setText(dom.plexErrorElement, state.errorText ?? '');
  dom.plexErrorElement?.toggleAttribute('hidden', state.errorText === null);
  setText(dom.plexAccountStateElement, formatAccountState(snapshot));
  setText(dom.plexServerStateElement, formatSelectedServerState(snapshot?.servers.items ?? [], state.selectedServerId, snapshot?.servers.status ?? 'idle'));
  setText(dom.plexLibraryStateElement, snapshot === null ? 'Not loaded' : `${formatStatus(snapshot.library.status)} / ${snapshot.library.sections.length} libraries`);

  const profilePending = state.pending.getHomeUsers || state.pending.switchHomeUser;
  const serverPending = state.pending.restoreSelectedServer
    || state.pending.refreshServers
    || state.pending.selectServer;
  renderPin(snapshot?.auth.pin ?? null, dom);
  renderHomeUsers(snapshot?.auth.homeUsers ?? [], dom, profilePending);
  renderServers(
    snapshot?.servers.items ?? [],
    state.selectedServerId,
    snapshot?.servers.status ?? 'idle',
    dom,
    serverPending,
  );
  renderSections(snapshot?.library.sections ?? [], state.selectedSectionId, snapshot?.library.status ?? 'idle', dom, setupSelectedSectionIds);
  renderItems(
    snapshot?.library.search?.items ?? snapshot?.library.items ?? [],
    state.selectedItemRatingKey,
    snapshot?.library.status ?? 'idle',
    snapshot?.library.search?.query ?? null,
    dom,
    previewBadgesEnabled,
  );
  renderMetadata(state.lastMetadata ?? snapshot?.library.metadata ?? null, dom, previewBadgesEnabled);

  if (dom.plexHomeUserPinInput && dom.plexHomeUserPinInput.value !== state.homeUserPin) {
    dom.plexHomeUserPinInput.value = state.homeUserPin;
  }
  if (dom.plexSearchQueryInput && dom.plexSearchQueryInput.value !== state.searchQuery) {
    dom.plexSearchQueryInput.value = state.searchQuery;
  }

  const anyPending = Object.values(state.pending).some(Boolean);
  for (const button of dom.plexActionButtons) {
    const disabled = shouldDisableAction(button.dataset.plexAction, state, anyPending);
    button.disabled = disabled;
    if (typeof button.setAttribute === 'function') {
      button.setAttribute('aria-disabled', String(disabled));
      button.setAttribute('aria-busy', String(state.pending[button.dataset.plexAction as keyof typeof state.pending] === true));
    }
  }
  const setupButton = supportsOnboardingDom ? document.querySelector<HTMLButtonElement>('[data-focus-id="btn-server-setup"]') : null;
  if (setupButton) projectPendingControl(setupButton, serverPending || state.selectedServerId === null, serverPending);
  for (const switchButton of supportsOnboardingDom ? Array.from(document.querySelectorAll<HTMLButtonElement>('[data-focus-id="btn-server-switch-profile"]')) : []) {
    projectPendingControl(switchButton, serverPending, serverPending);
  }
}

function projectPendingControl(button: HTMLButtonElement, disabled: boolean, busy: boolean): void {
  button.disabled = disabled;
  button.setAttribute('aria-disabled', String(disabled));
  button.setAttribute('aria-busy', String(busy));
}

export function readPlexServerId(element: HTMLElement): string | null {
  return readSafeDataId(element.dataset.plexServerId);
}

export function readPlexHomeUserId(element: HTMLElement): string | null {
  return readSafeDataId(element.dataset.plexHomeUserId);
}

export function readPlexSectionId(element: HTMLElement): string | null {
  return readSafeDataId(element.dataset.plexSectionId);
}

export function readPlexRatingKey(element: HTMLElement): string | null {
  return readSafeDataId(element.dataset.plexRatingKey);
}

function renderPin(
  pin: { id: number; code: string; expiresAtMs: number; claimed: boolean } | null,
  dom: RendererDomBindings,
): void {
  if (!dom.plexPinElement) {
    return;
  }
  dom.plexPinElement.replaceChildren();
  if (pin === null) {
    const idle = document.createElement('p');
    idle.textContent = 'Plex sign-in is ready.';
    dom.plexPinElement.append(idle);
    return;
  }
  const pinBoxes = document.createElement('div');
  pinBoxes.className = 'auth-code__characters';

  const chars = pin.code.split('');
  for (const char of chars) {
    const box = document.createElement('span');
    box.className = 'auth-code__character';
    box.textContent = char;
    pinBoxes.append(box);
  }

  const expiry = document.createElement('span');
  expiry.className = 'auth-code__expiry';
  const remainingSecs = Math.max(0, Math.round((pin.expiresAtMs - Date.now()) / 1000));
  expiry.textContent = pin.claimed
    ? 'Code claimed. Checking account status...'
    : `Code expires in ${remainingSecs}s (at ${formatTime(pin.expiresAtMs)}).`;

  dom.plexPinElement.append(pinBoxes, expiry);
}

function ensureStaticLinkQrs(): void {
  if (typeof document.createElementNS !== 'function') return;
  for (const host of Array.from(document.querySelectorAll<HTMLElement>('[data-plex-link-qr]'))) {
    if (host.childElementCount === 0) host.append(createPlexLinkQr(document));
  }
}

function onboardingStatus(state: PlexRuntimeRendererState, owner: PlexOnboardingStateId): string {
  switch (owner) {
    case 'auth-link-code':
      return state.pending.requestPin ? 'Requesting a sign-in code…' : 'Ready to request a sign-in code.';
    case 'auth-waiting':
      return 'Waiting for sign-in…';
    case 'auth-error':
      return '';
    case 'profile-select': {
      const count = state.snapshot?.auth.homeUsers.length ?? 0;
      return state.pending.getHomeUsers ? 'Loading profiles…' : count === 0 ? 'No profiles are available.' : 'Choose a profile.';
    }
    case 'server-select': {
      const count = state.snapshot?.servers.items.length ?? 0;
      return state.pending.refreshServers ? 'Looking for servers…' : count === 0 ? 'No servers found.' : 'Choose a server.';
    }
    case 'server-error':
      return '';
    case 'profile-pin':
      return '';
  }
}

function shouldDisableAction(
  action: string | undefined,
  state: PlexRuntimeRendererState,
  anyPending: boolean,
): boolean {
  switch (action) {
    case 'pollPin':
    case 'cancelPin':
      return anyPending || state.snapshot?.auth.pin === null || state.snapshot?.auth.pin === undefined;
    case 'dismissPinError':
      return false;
    case 'listLibraryItems':
      return anyPending || state.selectedServerId === null || state.selectedSectionId === null;
    case 'searchLibrary':
      return anyPending || state.selectedServerId === null || state.searchQuery.trim().length === 0;
    case 'clearMetadata':
      return anyPending || (state.lastMetadata === null && (state.snapshot?.library.metadata ?? null) === null);
    case 'clearSearch':
      return anyPending || (state.searchQuery.trim().length === 0 && (state.snapshot?.library.search ?? null) === null);
    case 'clearItems':
      return anyPending || (state.snapshot?.library.items.length ?? 0) === 0;
    case 'clearSelectedSection':
      return anyPending || state.selectedSectionId === null;
    case 'clearSelectedServer':
      return anyPending || state.selectedServerId === null;
    case 'clearPinSubflow':
      return anyPending || (
        state.homeUserPin.length === 0
        && (state.snapshot?.auth.pin ?? null) === null
        && (state.snapshot?.auth.homeUsers.length ?? 0) === 0
      );
    default:
      return anyPending;
  }
}

function formatSelectedServerState(
  servers: readonly PlexServerSummary[],
  selectedServerId: string | null,
  fallbackStatus: string,
): string {
  if (selectedServerId === null) {
    return formatStatus(fallbackStatus);
  }
  return servers.find((server) => server.serverId === selectedServerId)?.name ?? 'Selected server';
}

function formatAccountState(snapshot: PlexRuntimeRendererState['snapshot']): string {
  if (snapshot === null) {
    return 'Not loaded';
  }
  const profileName =
    snapshot.auth.profile?.displayName
    ?? snapshot.auth.profile?.username
    ?? snapshot.auth.profile?.accountId
    ?? null;
  const profileText = profileName === null ? 'No profile selected' : profileName;
  return `${formatAuthState(snapshot.auth.state)} / ${profileText} / ${formatCredentialStatus(snapshot.auth.credentialStatus)}`;
}

function formatAuthState(value: string): string {
  switch (value) {
    case 'signed-out':
      return 'Signed out';
    case 'pin-pending':
      return 'PIN pending';
    case 'signed-in':
      return 'Signed in';
    default:
      return 'Unknown';
  }
}

function formatCredentialStatus(value: string): string {
  switch (value) {
    case 'missing':
      return 'No credential';
    case 'present':
      return 'Credential present';
    case 'unavailable':
      return 'Credential unavailable';
    case 'corrupt':
      return 'Credential corrupt';
    default:
      return 'Unknown';
  }
}

function formatStatus(value: string): string {
  switch (value) {
    case 'idle':
      return 'Idle';
    case 'loading':
      return 'Loading';
    case 'ready':
      return 'Ready';
    case 'failed':
      return 'Failed';
    default:
      return 'Unknown';
  }
}

function formatTime(value: number): string {
  return Number.isFinite(value) ? new Date(value).toISOString().slice(11, 16) : 'Unknown';
}

function readSafeDataId(value: string | undefined): string | null {
  if (value === undefined) {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 || trimmed.length > 180 ? null : trimmed;
}

function setText(element: HTMLElement | null, value: string): void {
  if (element) {
    element.textContent = value;
  }
}
