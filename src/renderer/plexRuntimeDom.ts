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

export function renderPlexRuntimeDom(
  state: PlexRuntimeRendererState,
  dom: RendererDomBindings,
): void {
  if (!dom.plexPanelElement) {
    return;
  }

  const snapshot = state.snapshot;
  setText(dom.plexStatusElement, state.statusText);
  setText(dom.plexErrorElement, state.errorText ?? '');
  dom.plexErrorElement?.toggleAttribute('hidden', state.errorText === null);
  setText(
    dom.plexAccountStateElement,
    formatAccountState(snapshot),
  );
  setText(
    dom.plexServerStateElement,
    formatSelectedServerState(
      snapshot?.servers.items ?? [],
      state.selectedServerId,
      snapshot?.servers.status ?? 'idle',
    ),
  );
  setText(
    dom.plexLibraryStateElement,
    snapshot === null
      ? 'Not loaded'
      : `${formatStatus(snapshot.library.status)} / ${snapshot.library.sections.length} libraries`,
  );

  renderPin(snapshot?.auth.pin ?? null, dom);
  renderHomeUsers(snapshot?.auth.homeUsers ?? [], dom);
  renderServers(snapshot?.servers.items ?? [], state.selectedServerId, snapshot?.servers.status ?? 'idle', dom);
  renderSections(snapshot?.library.sections ?? [], state.selectedSectionId, snapshot?.library.status ?? 'idle', dom);
  renderItems(
    snapshot?.library.search?.items ?? snapshot?.library.items ?? [],
    state.selectedItemRatingKey,
    snapshot?.library.status ?? 'idle',
    snapshot?.library.search?.query ?? null,
    dom,
  );
  renderMetadata(state.lastMetadata ?? snapshot?.library.metadata ?? null, dom);

  if (dom.plexHomeUserPinInput && dom.plexHomeUserPinInput.value !== state.homeUserPin) {
    dom.plexHomeUserPinInput.value = state.homeUserPin;
  }
  if (dom.plexSearchQueryInput && dom.plexSearchQueryInput.value !== state.searchQuery) {
    dom.plexSearchQueryInput.value = state.searchQuery;
  }

  const anyPending = Object.values(state.pending).some(Boolean);
  for (const button of dom.plexActionButtons) {
    button.disabled = shouldDisableAction(button.dataset.plexAction, state, anyPending);
  }
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
    idle.className = 'plex-runtime__pin-idle';
    idle.textContent = 'Start Plex sign-in to request a link code.';
    dom.plexPinElement.append(idle);
    return;
  }

  const container = document.createElement('div');
  container.className = 'plex-runtime__pin-container';

  // Left side: QR Code placeholder card
  const qrCard = document.createElement('div');
  qrCard.className = 'plex-runtime__qr-card';

  const qrBox = document.createElement('div');
  qrBox.className = 'plex-runtime__qr-box';
  for (let i = 0; i < 9; i++) {
    const cell = document.createElement('div');
    cell.className = 'plex-runtime__qr-cell';
    qrBox.append(cell);
  }

  const qrLabel = document.createElement('span');
  qrLabel.className = 'plex-runtime__qr-label';
  qrLabel.textContent = 'Scan to link';

  qrCard.append(qrBox, qrLabel);

  // Right side: Character-separated PIN boxes
  const pinDetails = document.createElement('div');
  pinDetails.className = 'plex-runtime__pin-details';

  const pinBoxes = document.createElement('div');
  pinBoxes.className = 'plex-runtime__pin-boxes';

  const chars = pin.code.split('');
  for (const char of chars) {
    const box = document.createElement('span');
    box.className = 'plex-runtime__pin-char';
    box.textContent = char;
    pinBoxes.append(box);
  }

  const instruction = document.createElement('p');
  instruction.className = 'plex-runtime__pin-instruction';
  instruction.innerHTML = 'Visit <strong class="plex-accent-text">plex.tv/link</strong> on your phone or computer and enter the code above.';

  const expiry = document.createElement('span');
  expiry.className = 'plex-runtime__pin-expiry';
  const remainingSecs = Math.max(0, Math.round((pin.expiresAtMs - Date.now()) / 1000));
  expiry.textContent = pin.claimed
    ? 'Code claimed. Checking account status...'
    : `Code expires in ${remainingSecs}s (at ${formatTime(pin.expiresAtMs)}).`;

  pinDetails.append(pinBoxes, instruction, expiry);
  container.append(qrCard, pinDetails);
  dom.plexPinElement.append(container);
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
