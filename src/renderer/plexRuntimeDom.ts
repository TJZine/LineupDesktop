import type {
  PlexHomeUserSummary,
  PlexLibrarySectionSummary,
  PlexMediaItemSummary,
  PlexServerSummary,
} from '../contracts/plex.js';
import type { RendererDomBindings } from './domBindings.js';
import type { PlexRuntimeRendererState } from './plexRuntimeState.js';

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
    snapshot === null
      ? 'Not loaded'
      : `${formatAuthState(snapshot.auth.state)} / ${formatCredentialStatus(snapshot.auth.credentialStatus)}`,
  );
  setText(
    dom.plexServerStateElement,
    snapshot?.servers.selected?.name ?? formatStatus(snapshot?.servers.status ?? 'idle'),
  );
  setText(
    dom.plexLibraryStateElement,
    snapshot === null
      ? 'Not loaded'
      : `${formatStatus(snapshot.library.status)} / ${snapshot.library.sections.length} libraries`,
  );

  renderPin(snapshot?.auth.pin ?? null, dom);
  renderHomeUsers(snapshot?.auth.homeUsers ?? [], dom);
  renderServers(snapshot?.servers.items ?? [], dom);
  renderSections(snapshot?.library.sections ?? [], state.selectedSectionId, dom);
  renderItems(snapshot?.library.search?.items ?? snapshot?.library.items ?? [], dom);
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
    return;
  }
  const code = document.createElement('strong');
  code.textContent = pin.code;
  const detail = document.createElement('span');
  detail.textContent = `${pin.claimed ? 'Claimed' : 'Pending'} / ${formatTime(pin.expiresAtMs)}`;
  dom.plexPinElement.append(code, detail);
}

function renderHomeUsers(users: readonly PlexHomeUserSummary[], dom: RendererDomBindings): void {
  renderButtonList(dom.plexHomeUsersElement, users, (user) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.plexHomeUserId = user.id;
    button.dataset.focusId = createPlexFocusId('plex-dyn-home', user.id);
    button.textContent = `${user.title}${user.protected ? ' / PIN' : ''}`;
    return button;
  });
}

function renderServers(servers: readonly PlexServerSummary[], dom: RendererDomBindings): void {
  renderButtonList(dom.plexServersElement, servers, (server) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.plexServerId = server.serverId;
    button.dataset.focusId = createPlexFocusId('plex-dyn-server', server.serverId);
    button.dataset.selected = String(server.selected);
    button.textContent = `${server.name} / ${formatServerHealth(server)}`;
    return button;
  });
}

function renderSections(
  sections: readonly PlexLibrarySectionSummary[],
  selectedSectionId: string | null,
  dom: RendererDomBindings,
): void {
  renderButtonList(dom.plexSectionsElement, sections, (section) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.plexSectionId = section.id;
    button.dataset.focusId = createPlexFocusId('plex-dyn-section', section.id);
    button.dataset.selected = String(section.id === selectedSectionId);
    const count = section.contentCount === null ? 'unknown' : String(section.contentCount);
    button.textContent = `${section.title} / ${section.type} / ${count}`;
    return button;
  });
}

function renderItems(items: readonly PlexMediaItemSummary[], dom: RendererDomBindings): void {
  renderButtonList(dom.plexItemsElement, items, (item) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.plexRatingKey = item.ratingKey;
    button.dataset.focusId = createPlexFocusId('plex-dyn-item', item.ratingKey);
    button.textContent = `${item.title} / ${formatMediaType(item.type)} / ${formatYear(item.year)}`;
    return button;
  });
}

function renderMetadata(item: PlexMediaItemSummary | null, dom: RendererDomBindings): void {
  if (!dom.plexMetadataElement) {
    return;
  }
  dom.plexMetadataElement.replaceChildren();
  if (item === null) {
    return;
  }
  const title = document.createElement('strong');
  title.textContent = item.title;
  const details = document.createElement('p');
  details.textContent = [
    formatMediaType(item.type),
    formatYear(item.year),
    formatDuration(item.durationMs),
    item.contentRating ?? null,
  ].filter((value): value is string => value !== null).join(' / ');
  const summary = document.createElement('p');
  summary.textContent = item.summary;
  dom.plexMetadataElement.append(title, details, summary);
}

function renderButtonList<TValue>(
  host: HTMLElement | null,
  values: readonly TValue[],
  createButton: (value: TValue) => HTMLButtonElement,
): void {
  if (!host) {
    return;
  }
  host.replaceChildren(...values.map(createButton));
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
      return anyPending || state.selectedSectionId === null;
    case 'searchLibrary':
      return anyPending || state.searchQuery.trim().length === 0;
    default:
      return anyPending;
  }
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

function formatServerHealth(server: PlexServerSummary): string {
  if (server.health === undefined) {
    return server.selected ? 'Selected' : 'Available';
  }
  switch (server.health.status) {
    case 'ok':
      return server.selected ? 'Selected' : 'Available';
    case 'unreachable':
      return 'Unreachable';
    case 'auth-required':
      return 'Sign-in required';
    case 'access-denied':
      return 'Access denied';
  }
}

function formatMediaType(value: PlexMediaItemSummary['type']): string {
  switch (value) {
    case 'movie':
      return 'Movie';
    case 'show':
      return 'Show';
    case 'episode':
      return 'Episode';
    case 'track':
      return 'Track';
    case 'clip':
      return 'Clip';
  }
}

function formatYear(value: number): string {
  return Number.isFinite(value) && value > 0 ? String(value) : 'Unknown year';
}

function formatDuration(value: number): string | null {
  if (!Number.isFinite(value) || value <= 0) {
    return null;
  }
  const minutes = Math.round(value / 60_000);
  return `${minutes} min`;
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

function createPlexFocusId(prefix: string, value: string): string {
  const trimmed = value.trim();
  const encoded = [...trimmed]
    .map((char) => {
      const code = char.charCodeAt(0);
      const isSafe =
        (code >= 0x30 && code <= 0x39)
        || (code >= 0x41 && code <= 0x5a)
        || (code >= 0x61 && code <= 0x7a)
        || char === '.'
        || char === '_'
        || char === '-';
      return isSafe ? char : `-${code.toString(16)}-`;
    })
    .join('')
    .replace(/-+/gu, '-')
    .replace(/^-|-$/gu, '');
  const safeValue = encoded.length === 0 ? 'unknown' : encoded;
  if (safeValue.length <= 96) {
    return `${prefix}-${safeValue}`;
  }
  return `${prefix}-${safeValue.slice(0, 80)}-${hashFocusValue(trimmed)}`;
}

function hashFocusValue(value: string): string {
  let hash = 5381;
  for (const char of value) {
    hash = ((hash << 5) + hash + char.charCodeAt(0)) >>> 0;
  }
  return hash.toString(36);
}
