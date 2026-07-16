import type { RendererDomBindings } from '../domBindings.js';
import type { PlexRuntimeRendererState } from '../plexRuntimeState.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { CustomChannelRendererState } from '../customChannels/controller.js';
import type { ChannelRuntimeRendererState } from '../channelRuntimeState.js';
import type { SetupRuntimeState } from './setupRuntimeCoordinator.js';
import type { StagedSetupOwnerId, StagedSetupState } from './stagedSetupController.js';
import { eligibleSetupLibraries } from './setupLibrarySelection.js';

export function renderStagedSetupDom(input: {
  state: StagedSetupState;
  runtimeState: SetupRuntimeState;
  view: RouteWorkflowViewModel;
  plexState: PlexRuntimeRendererState;
  customState: CustomChannelRendererState;
  channelState: ChannelRuntimeRendererState;
  dom: RendererDomBindings;
  documentRef?: Document;
}): void {
  const doc = input.documentRef ?? document;
  const ownerId = mapOwnerElement(input.state.owner);
  doc.documentElement.dataset.setupOwner = input.state.owner;
  for (const owner of Array.from(doc.querySelectorAll<HTMLElement>('[data-staged-owner]'))) {
    const active = owner.dataset.stagedOwner === ownerId;
    const background = input.state.owner === 'custom-delete-confirm' && owner.dataset.stagedOwner === 'custom-list';
    owner.hidden = !active && !background;
    owner.inert = !active;
    owner.setAttribute('aria-hidden', String(!active));
    owner.dataset.ownerActive = String(active);
  }

  const sections = eligibleSetupLibraries(input.plexState.snapshot?.library.sections ?? []);
  const selected = sections.filter((section) => input.state.selectedSectionIds.includes(section.id));
  const libraryLoading = input.runtimeState.library === 'loading';
  const libraryEmpty = input.runtimeState.library === 'empty';
  setText(doc.querySelector('[data-setup-library-status]'), libraryStatus(input.runtimeState.library, selected.length));
  toggle(doc.querySelector('[data-setup-library-empty]'), !libraryEmpty);
  toggle(doc.querySelector('[data-setup-limit-message]'), !input.state.selectionLimitReached);
  const toolbar = doc.querySelector<HTMLElement>('.setup-library-toolbar');
  if (toolbar) toolbar.hidden = libraryLoading || libraryEmpty || input.runtimeState.library === 'error';
  const sectionHost = doc.querySelector<HTMLElement>('[data-staged-owner="library"] [data-plex-sections]');
  if (sectionHost) sectionHost.hidden = libraryLoading || libraryEmpty || input.runtimeState.library === 'error';
  setButton(doc, 'setup-select-all', libraryLoading || sections.length === 0, libraryLoading);
  setButton(doc, 'setup-clear-all', libraryLoading || sections.length === 0, libraryLoading);
  setButton(doc, 'setup-next', libraryLoading || selected.length === 0, libraryLoading, 'library');
  for (const row of Array.from(doc.querySelectorAll<HTMLButtonElement>('[data-staged-owner="library"] [data-plex-section-id]'))) {
    const eligible = sections.some((section) => section.id === row.dataset.plexSectionId);
    row.hidden = !eligible;
    row.disabled = libraryLoading || !eligible;
    row.setAttribute('aria-disabled', String(row.disabled));
  }
  setText(input.dom.channelSetupSourceElement, selected.length === 0 ? 'No libraries selected' : `${String(selected.length)} ${selected.length === 1 ? 'library' : 'libraries'} selected`);

  const append = doc.querySelector<HTMLButtonElement>('[data-focus-id="channel-strategy-build-append"]');
  const replace = doc.querySelector<HTMLButtonElement>('[data-focus-id="channel-strategy-build-replace"]');
  const hasSaved = (input.channelState.summary?.channelCount ?? 0) > 0;
  projectMode(append, input.state.buildMode === 'append', false);
  projectMode(replace, input.state.buildMode === 'replace', !hasSaved);
  const previewContent = doc.querySelector<HTMLElement>('.setup-preview-content');
  if (previewContent) previewContent.hidden = !input.state.previewExpanded;
  const previewToggle = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-preview-toggle"]');
  previewToggle?.setAttribute('aria-expanded', String(input.state.previewExpanded));
  setText(doc.querySelector('[data-setup-preview-status]'), previewStatus(input.runtimeState.preview));
  const previewRetry = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-preview-retry"]');
  if (previewRetry) previewRetry.hidden = input.runtimeState.preview !== 'items-error' && input.runtimeState.preview !== 'metadata-error';
  for (const item of Array.from(doc.querySelectorAll<HTMLButtonElement>('[data-plex-items] [data-focus-id]'))) {
    item.disabled = true;
    item.setAttribute('aria-disabled', 'true');
  }

  const replaceConfirm = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-replace-confirm"]');
  if (replaceConfirm) {
    replaceConfirm.hidden = input.state.buildMode !== 'replace';
    replaceConfirm.setAttribute('aria-pressed', String(input.state.replacementConfirmed));
    replaceConfirm.classList.toggle('selected', input.state.replacementConfirmed);
  }
  const buildPending = input.channelState.pending;
  setButton(doc, 'setup-confirm', selected.length === 0 || buildPending || (input.state.buildMode === 'replace' && !input.state.replacementConfirmed), buildPending, 'build');
  renderReview(input, selected.map((section) => section.title), doc);

  const watch = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-result-watch"]');
  if (watch) {
    const available = input.state.resultWatchChannelId !== null;
    watch.hidden = !available; watch.disabled = !available; watch.setAttribute('aria-disabled', String(!available));
  }
  setText(input.dom.channelSetupResultElement, input.view.channelSetupFlow.result.detail);
  setText(doc.querySelector('[data-setup-safe-error]'), input.state.safeError ?? 'Channel setup could not continue.');
  setText(doc.querySelector('[data-setup-recovery-step]'), input.state.recovery?.originStep === 'library' ? 'Step 1 of 3' : 'Step 3 of 3');
  setText(doc.querySelector('[data-custom-delete-error]'), input.customState.lastError ?? '');
  const deleteConfirm = doc.querySelector<HTMLButtonElement>('[data-focus-id="custom-delete-confirm"]');
  if (deleteConfirm) { deleteConfirm.dataset.customChannelDetail = input.state.deleteChannelId ?? ''; setPending(deleteConfirm, input.customState.pendingAction === 'delete'); }
  const setupCustom = input.state.owner === 'setup-custom';
  toggleFooter(doc, 'setup-done', !setupCustom); toggleFooter(doc, 'setup-back', !setupCustom); toggleFooter(doc, 'custom-channel-back', setupCustom);
}

function renderReview(input: Parameters<typeof renderStagedSetupDom>[0], titles: readonly string[], doc: Document): void {
  const saved = input.channelState.summary?.channelCount ?? 0;
  const planned = input.state.buildMode === 'append' ? saved + titles.length : titles.length;
  const rows = [
    ['Selected libraries', titles.length === 0 ? 'None' : titles.join(', ')],
    ['Saved lineup', `${String(saved)} channels`],
    ['Build mode', input.state.buildMode === 'replace' ? 'Replace saved lineup' : 'Append to saved lineup'],
    ['Planned channel count', `${String(planned)} channels after build (planned)`],
  ];
  const host = doc.querySelector<HTMLElement>('[data-staged-owner="build"] [data-channel-review-list]');
  host?.replaceChildren(...rows.map(([label, value]) => {
    const row = doc.createElement('div'); row.className = 'setup-review-row';
    const strong = doc.createElement('strong'); strong.textContent = label;
    const span = doc.createElement('span'); span.textContent = value;
    row.append(strong, span); return row;
  }));
  setText(doc.querySelector('[data-staged-owner="build"] [data-channel-review-impact]'), input.state.buildMode === 'replace' ? 'The saved lineup will be replaced only after confirmation.' : 'Saved channels will be kept and selected libraries appended.');
}

function mapOwnerElement(owner: StagedSetupOwnerId): string { return owner === 'setup-custom' ? 'custom-list' : owner; }
function libraryStatus(state: SetupRuntimeState['library'], selected: number): string {
  if (state === 'loading') return 'Loading libraries…';
  if (state === 'error') return 'Libraries could not be loaded.';
  if (state === 'empty') return 'No eligible libraries found.';
  return selected === 0 ? 'Select at least one library.' : `${String(selected)} selected`;
}
function previewStatus(state: SetupRuntimeState['preview']): string {
  if (state === 'loading') return 'Loading preview…';
  if (state === 'empty') return 'No preview items are available.';
  if (state === 'items-error' || state === 'metadata-error') return 'Preview unavailable.';
  return state === 'ready' ? 'Preview ready.' : '';
}
function projectMode(button: HTMLButtonElement | null, selected: boolean, disabled: boolean): void {
  if (!button) return;
  button.classList.toggle('selected', selected); button.setAttribute('aria-pressed', String(selected));
  button.disabled = disabled; button.setAttribute('aria-disabled', String(disabled));
}
function setButton(doc: Document, id: string, disabled: boolean, busy: boolean, owner?: string): void {
  const selector = `${owner ? `[data-staged-owner="${owner}"] ` : ''}[data-focus-id="${id}"]`;
  for (const button of Array.from(doc.querySelectorAll<HTMLButtonElement>(selector))) { button.disabled = disabled; button.setAttribute('aria-disabled', String(disabled)); button.setAttribute('aria-busy', String(busy)); }
}
function setPending(button: HTMLButtonElement, pending: boolean): void { button.disabled = pending; button.setAttribute('aria-disabled', String(pending)); button.setAttribute('aria-busy', String(pending)); }
function toggle(element: Element | null, hidden: boolean): void { if (element instanceof HTMLElement) element.hidden = hidden; }
function toggleFooter(doc: Document, id: string, hidden: boolean): void { const button = doc.querySelector<HTMLButtonElement>(`[data-staged-owner="custom-list"] [data-focus-id="${id}"]`); if (button) { button.hidden = hidden; button.disabled = hidden; button.setAttribute('aria-hidden', String(hidden)); } }
function setText(element: Element | null | undefined, text: string): void { if (element) element.textContent = text; }
