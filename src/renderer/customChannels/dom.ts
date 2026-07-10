import type { RendererDomBindings } from '../domBindings.js';
import type { CustomChannelRendererState } from './controller.js';
import type {
  CustomChannelContentEntryInput,
  CustomChannelMediaCard,
  CustomChannelSummary,
} from '../../contracts/customChannels.js';

export function renderCustomChannelWorkspace(
  state: CustomChannelRendererState,
  dom: RendererDomBindings,
): void {
  if (!dom.customChannelStatusElement || !dom.customChannelListElement || !dom.customChannelMediaElement || !dom.customChannelDraftElement) {
    return;
  }
  dom.customChannelStatusElement.textContent = statusText(state);
  renderChannelList(state, dom.customChannelListElement);
  renderMediaPicker(state, dom.customChannelMediaElement);
  renderDraft(state, dom.customChannelDraftElement);
  syncInputs(state, dom);
}

function renderChannelList(state: CustomChannelRendererState, host: HTMLElement): void {
  const channels = state.snapshot?.channels ?? [];
  if (channels.length === 0) {
    host.replaceChildren(emptyText('No custom channels saved yet.'));
    return;
  }
  host.replaceChildren(...channels.map((channel, index) => renderChannelRow(channel, state, index)));
}

function renderChannelRow(
  channel: CustomChannelSummary,
  state: CustomChannelRendererState,
  index: number,
): HTMLElement {
  const row = document.createElement('article');
  row.className = 'custom-channel-row';
  row.dataset.hidden = String(channel.hidden);
  row.dataset.current = String(channel.isCurrent);

  const number = document.createElement('span');
  number.className = 'custom-channel-row__number';
  number.textContent = String(channel.number);

  const copy = document.createElement('div');
  copy.className = 'custom-channel-row__copy';
  const title = document.createElement('strong');
  title.textContent = channel.name;
  const detail = document.createElement('span');
  detail.textContent = `${String(channel.itemCount)} items / ${channel.playbackMode}${channel.hidden ? ' / hidden' : ''}`;
  copy.append(title, detail);

  const actions = document.createElement('div');
  actions.className = 'custom-channel-row__actions';
  actions.append(
    actionButton('Duplicate', 'duplicateChannel', channel.id, `custom-channel-duplicate-${channel.id}`),
    actionButton(channel.hidden ? 'Show' : 'Hide', 'toggleChannelVisibility', channel.id, `custom-channel-hide-${channel.id}`),
    actionButton('Up', 'moveChannelUp', channel.id, `custom-channel-up-${channel.id}`, index === 0),
    actionButton('Down', 'moveChannelDown', channel.id, `custom-channel-down-${channel.id}`, index === (state.snapshot?.channels.length ?? 1) - 1),
    state.deleteConfirmationChannelId === channel.id
      ? actionButton('Confirm delete', 'confirmDeleteChannel', channel.id, `custom-channel-confirm-delete-${channel.id}`)
      : actionButton('Delete', 'requestDeleteChannel', channel.id, `custom-channel-delete-${channel.id}`),
  );

  row.append(number, copy, actions);
  return row;
}

function renderMediaPicker(state: CustomChannelRendererState, host: HTMLElement): void {
  const items = state.mediaPage?.items ?? [];
  if (state.mediaPending) {
    host.replaceChildren(emptyText('Loading media...'));
    return;
  }
  if (items.length === 0) {
    host.replaceChildren(emptyText(`Browse or search ${filterLabel(state.mediaTypeFilter)} to add media.`));
    return;
  }
  const metadata = renderMetadataPanel(state);
  host.replaceChildren(
    ...(metadata === null ? [] : [metadata]),
    ...items.map((item) => renderMediaCard(item, state)),
  );
}

function renderMediaCard(
  item: CustomChannelMediaCard,
  state: CustomChannelRendererState,
): HTMLElement {
  const card = document.createElement('article');
  card.className = 'custom-media-card';
  const alreadyAdded = state.draft.content.some((entry) =>
    entry.type === 'manualItem' && entry.ratingKey === item.ratingKey
  );

  const poster = document.createElement('span');
  poster.className = 'custom-media-card__poster';
  poster.textContent = item.title.slice(0, 1).toUpperCase() || '?';

  const copy = document.createElement('div');
  copy.className = 'custom-media-card__copy';
  const title = document.createElement('strong');
  title.textContent = item.title;
  const detail = document.createElement('span');
  detail.textContent = [item.type, item.subtitle, item.year === null ? null : String(item.year)]
    .filter((value): value is string => value !== null && value.length > 0)
    .join(' / ');
  copy.append(title, detail);

  const add = actionButton(
    alreadyAdded ? 'Added' : 'Add',
    'addMedia',
    item.ratingKey,
    `custom-media-add-${item.ratingKey}`,
    alreadyAdded,
  );
  add.setAttribute('aria-pressed', String(alreadyAdded));
  const details = actionButton('Details', 'openMetadata', item.ratingKey, `custom-media-details-${item.ratingKey}`);
  const actions = document.createElement('div');
  actions.className = 'custom-media-card__actions';
  actions.append(details, add);
  card.append(poster, copy, actions);
  return card;
}

function renderMetadataPanel(state: CustomChannelRendererState): HTMLElement | null {
  if (state.metadata === null && !state.metadataPending) return null;
  const panel = document.createElement('article');
  panel.className = 'custom-media-metadata';
  const title = document.createElement('strong');
  title.textContent = state.metadataPending ? 'Loading details...' : state.metadata?.title ?? 'Media details';
  const detail = document.createElement('span');
  detail.textContent = state.metadata === null
    ? 'Details are loading.'
    : [state.metadata.type, state.metadata.subtitle, state.metadata.contentRating ?? null]
      .filter((value): value is string => value !== null && value.length > 0)
      .join(' / ');
  const summary = document.createElement('p');
  summary.textContent = state.metadata?.summary ?? 'No summary is available.';
  panel.append(title, detail, summary, actionButton('Close details', 'closeMetadata', '', 'custom-media-close-details'));
  return panel;
}

function renderDraft(state: CustomChannelRendererState, host: HTMLElement): void {
  const header = document.createElement('div');
  header.className = 'custom-draft__summary';
  const count = document.createElement('strong');
  count.textContent = `${String(state.draft.content.length)} selected`;
  const visibility = document.createElement('span');
  visibility.textContent = state.draft.hidden ? 'Hidden after save' : 'Visible after save';
  header.append(count, visibility);

  const items = document.createElement('div');
  items.className = 'custom-draft__items';
  if (state.draft.content.length === 0) {
    items.append(emptyText('Add media from the picker to build this channel.'));
  } else {
    items.append(...state.draft.content.map(renderDraftItem));
  }

  const validation = document.createElement('div');
  validation.className = 'custom-draft__validation';
  const messages = validationMessages(state);
  validation.replaceChildren(...messages.map((message) => {
    const item = document.createElement('p');
    item.textContent = message;
    return item;
  }));

  host.replaceChildren(header, items, validation);
}

function renderDraftItem(entry: CustomChannelContentEntryInput, index: number): HTMLElement {
  const item = document.createElement('article');
  item.className = 'custom-draft-item';
  const title = document.createElement('strong');
  title.textContent = entry.title;
  const detail = document.createElement('span');
  detail.textContent = entry.type === 'manualItem' ? entry.mediaType : entry.type;
  item.append(title, detail, actionButton('Remove', 'removeDraftItem', String(index), `custom-draft-remove-${String(index)}`));
  return item;
}

function validationMessages(state: CustomChannelRendererState): string[] {
  if (state.lastError !== null) return [state.lastError];
  if (state.validation !== null && !state.validation.valid) {
    return state.validation.issues.map((issue) => issue.message);
  }
  if (state.lastSavedChannelId !== null) return ['Channel saved.'];
  return [];
}

function statusText(state: CustomChannelRendererState): string {
  if (state.pending) return 'Saving custom channel changes...';
  if (state.snapshot === null) return 'Custom channels have not loaded yet.';
  return `${String(state.snapshot.visibleChannelCount)} visible / ${String(state.snapshot.hiddenChannelCount)} hidden`;
}

function filterLabel(filter: CustomChannelRendererState['mediaTypeFilter']): string {
  if (filter === 'movies') return 'movies';
  if (filter === 'episodes') return 'episodes';
  return 'media';
}

function syncInputs(state: CustomChannelRendererState, dom: RendererDomBindings): void {
  if (dom.customChannelNameInput && dom.customChannelNameInput.value !== state.draft.name) {
    dom.customChannelNameInput.value = state.draft.name;
  }
  if (dom.customChannelNumberInput && dom.customChannelNumberInput.value !== String(state.draft.number)) {
    dom.customChannelNumberInput.value = String(state.draft.number);
  }
  if (dom.customChannelSearchInput && dom.customChannelSearchInput.value !== state.query) {
    dom.customChannelSearchInput.value = state.query;
  }
}

function actionButton(
  label: string,
  action: string,
  detail: string,
  focusId: string,
  disabled = false,
): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = label;
  button.dataset.customChannelAction = action;
  button.dataset.customChannelDetail = detail;
  button.dataset.focusId = focusId;
  button.disabled = disabled;
  return button;
}

function emptyText(text: string): HTMLElement {
  const empty = document.createElement('p');
  empty.className = 'custom-channel-empty';
  empty.textContent = text;
  return empty;
}
