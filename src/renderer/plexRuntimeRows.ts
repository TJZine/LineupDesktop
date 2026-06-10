import type {
  PlexHomeUserSummary,
  PlexLibrarySectionSummary,
  PlexMediaItemSummary,
  PlexServerSummary,
} from '../contracts/plex.js';
import type { RendererDomBindings } from './domBindings.js';

export function renderHomeUsers(users: readonly PlexHomeUserSummary[], dom: RendererDomBindings): void {
  renderButtonList(dom.plexHomeUsersElement, users, 'No additional Plex Home profiles loaded.', (user) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'profile-row';
    button.dataset.plexHomeUserId = user.id;
    button.dataset.focusId = createPlexFocusId('plex-dyn-home', user.id);
    const avatar = document.createElement('span');
    avatar.className = 'profile-avatar profile-avatar-fallback';
    avatar.textContent = user.title.trim().slice(0, 1).toUpperCase() || '?';
    const name = document.createElement('strong');
    name.className = 'profile-name';
    name.textContent = user.title;
    const badges = document.createElement('span');
    badges.className = 'profile-badges';
    appendBadge(badges, user.admin, 'profile-admin', 'Admin');
    appendBadge(badges, user.protected, 'profile-lock', 'PIN');
    appendBadge(badges, user.restricted === true, 'profile-restricted', 'Restricted');
    button.append(avatar, name, badges);
    return button;
  });
}

export function renderServers(
  servers: readonly PlexServerSummary[],
  selectedServerId: string | null,
  status: string,
  dom: RendererDomBindings,
): void {
  renderButtonList(dom.plexServersElement, servers, formatServerEmptyText(status), (server) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `server-row${server.serverId === selectedServerId ? ' active' : ''}`;
    button.dataset.plexServerId = server.serverId;
    button.dataset.focusId = createPlexFocusId('plex-dyn-server', server.serverId);
    button.dataset.selected = String(server.serverId === selectedServerId);
    const main = document.createElement('span');
    main.className = 'server-main';
    const name = document.createElement('strong');
    name.className = 'server-name';
    name.textContent = server.name;
    const meta = document.createElement('span');
    meta.className = 'server-meta';
    meta.textContent = formatServerSummary(server);
    main.append(name, meta);
    const action = document.createElement('span');
    action.className = 'server-actions';
    action.textContent = server.serverId === selectedServerId ? 'Connected' : 'Connect';
    button.append(main, action);
    return button;
  });
}

export function renderSections(
  sections: readonly PlexLibrarySectionSummary[],
  selectedSectionId: string | null,
  status: string,
  dom: RendererDomBindings,
): void {
  renderButtonList(dom.plexSectionsElement, sections, formatLibraryEmptyText(status), (section) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `setup-toggle library-toggle${section.id === selectedSectionId ? ' selected' : ''}`;
    button.dataset.plexSectionId = section.id;
    button.dataset.focusId = createPlexFocusId('plex-dyn-section', section.id);
    button.dataset.selected = String(section.id === selectedSectionId);
    const marker = document.createElement('span');
    marker.className = 'setup-toggle-icon';
    marker.dataset.libraryMarker = section.type.slice(0, 1).toUpperCase();
    const label = document.createElement('strong');
    label.className = 'setup-toggle-label';
    label.textContent = section.title;
    const meta = document.createElement('span');
    meta.className = 'setup-toggle-meta';
    meta.textContent = `${formatLibraryType(section.type)} / ${formatContentCount(section.contentCount)}`;
    const state = document.createElement('span');
    state.className = 'setup-toggle-state';
    state.textContent = section.id === selectedSectionId ? 'Selected' : 'Open';
    button.append(marker, label, meta, state);
    return button;
  });
}

export function renderItems(
  items: readonly PlexMediaItemSummary[],
  selectedItemRatingKey: string | null,
  status: string,
  searchQuery: string | null,
  dom: RendererDomBindings,
): void {
  renderButtonList(dom.plexItemsElement, items, formatItemsEmptyText(status, searchQuery), (item) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `setup-toggle media-toggle${item.ratingKey === selectedItemRatingKey ? ' selected' : ''}`;
    button.dataset.plexRatingKey = item.ratingKey;
    button.dataset.focusId = createPlexFocusId('plex-dyn-item', item.ratingKey);
    button.dataset.selected = String(item.ratingKey === selectedItemRatingKey);
    const label = document.createElement('strong');
    label.className = 'setup-toggle-label';
    label.textContent = item.title;
    const meta = document.createElement('span');
    meta.className = 'setup-toggle-meta';
    meta.textContent = `${formatMediaType(item.type)} / ${formatYear(item.year)}`;
    const state = document.createElement('span');
    state.className = 'setup-toggle-state';
    state.textContent = item.ratingKey === selectedItemRatingKey ? 'Previewing' : 'Preview';
    button.append(label, meta, state);
    return button;
  });
}

export function renderMetadata(item: PlexMediaItemSummary | null, dom: RendererDomBindings): void {
  if (!dom.plexMetadataElement) {
    return;
  }
  dom.plexMetadataElement.replaceChildren();
  if (item === null) {
    const idle = document.createElement('p');
    idle.textContent = 'Choose a library item to preview its metadata.';
    dom.plexMetadataElement.append(idle);
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
  emptyText: string,
  createButton: (value: TValue) => HTMLButtonElement,
): void {
  if (!host) {
    return;
  }
  if (values.length === 0) {
    const empty = document.createElement('p');
    empty.textContent = emptyText;
    host.replaceChildren(empty);
    return;
  }
  host.replaceChildren(...values.map(createButton));
}

function formatServerEmptyText(status: string): string {
  switch (status) {
    case 'loading':
      return 'Looking for Plex servers...';
    case 'failed':
      return 'Servers could not be loaded.';
    case 'ready':
      return 'No Plex servers were found for this profile.';
    default:
      return 'Find servers to continue setup.';
  }
}

function formatLibraryEmptyText(status: string): string {
  switch (status) {
    case 'loading':
      return 'Loading libraries...';
    case 'failed':
      return 'Libraries could not be loaded.';
    case 'ready':
      return 'No libraries were found on the selected server.';
    default:
      return 'Open libraries after choosing a server.';
  }
}

function formatItemsEmptyText(status: string, searchQuery: string | null): string {
  if (searchQuery !== null) {
    return searchQuery.trim().length === 0
      ? 'No search results.'
      : `No search results for "${searchQuery.trim()}".`;
  }
  switch (status) {
    case 'loading':
      return 'Loading library items...';
    case 'failed':
      return 'Library items could not be loaded.';
    case 'ready':
      return 'No items found in this library.';
    default:
      return 'Browse a library or search to see items.';
  }
}

function formatServerSummary(server: PlexServerSummary): string {
  const connectionTypes = [
    server.hasLocalConnection ? 'local' : null,
    server.hasRemoteConnection ? 'remote' : null,
    server.hasRelayConnection ? 'relay' : null,
  ].filter((value): value is string => value !== null);
  const owner = server.owned ? 'Owned' : 'Shared';
  const health = formatServerHealth(server);
  const connections = connectionTypes.length === 0 ? `${server.connectionCount} connections` : connectionTypes.join(', ');
  return `${owner} / ${connections} / ${health}`;
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
    default:
      return assertUnreachable(server.health.status);
  }
}

function formatLibraryType(value: PlexLibrarySectionSummary['type']): string {
  switch (value) {
    case 'movie':
      return 'Movies';
    case 'show':
      return 'Shows';
    case 'artist':
      return 'Music';
    case 'photo':
      return 'Photos';
    default:
      return assertUnreachable(value);
  }
}

function formatContentCount(value: number | null): string {
  return value === null ? 'Unknown count' : `${value} items`;
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
    default:
      return assertUnreachable(value);
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

function appendBadge(host: HTMLElement, shouldAppend: boolean, className: string, text: string): void {
  if (!shouldAppend) {
    return;
  }
  const badge = document.createElement('span');
  badge.className = className;
  badge.textContent = text;
  host.append(badge);
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

function assertUnreachable(_value: never): string {
  return 'Unknown';
}
