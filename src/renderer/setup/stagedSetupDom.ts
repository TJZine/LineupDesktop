import type { RendererDomBindings } from '../domBindings.js';
import type { PlexRuntimeRendererState } from '../plexRuntimeState.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { CustomChannelRendererState } from '../customChannels/controller.js';
import type { ChannelRuntimeRendererState } from '../channelRuntimeState.js';
import type { SetupRuntimeState } from './setupRuntimeCoordinator.js';
import type { StagedSetupOwnerId, StagedSetupState } from './stagedSetupController.js';
import { eligibleSetupLibraries } from './setupLibrarySelection.js';
import type { ChannelBuilderAdjustableControl, ChannelBuilderCategory, ChannelBuilderState } from './channelBuilderController.js';
import type { ChannelSetupStrategyKey } from '../../contracts/channel.js';

export function renderStagedSetupDom(input: {
  state: StagedSetupState;
  builderState: ChannelBuilderState;
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

  renderChannelBuilderDom(input.builderState, doc);

  const append = doc.querySelector<HTMLButtonElement>('[data-focus-id="channel-strategy-build-append"]');
  const replace = doc.querySelector<HTMLButtonElement>('[data-focus-id="channel-strategy-build-replace"]');
  projectMode(append, input.builderState.draft.buildMode === 'append', false);
  projectMode(replace, input.builderState.draft.buildMode === 'replace', false);
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

  const replaceConfirm = doc.querySelector<HTMLButtonElement>('[data-focus-id="builder-replace-confirm"]');
  if (replaceConfirm) {
    replaceConfirm.hidden = input.builderState.draft.buildMode !== 'replace';
    replaceConfirm.setAttribute('aria-pressed', String(input.builderState.replaceConfirmed));
    replaceConfirm.classList.toggle('selected', input.builderState.replaceConfirmed);
  }
  const buildPending = input.builderState.phase === 'progress';
  setButton(doc, 'setup-confirm', input.builderState.phase !== 'review-ready' || buildPending ||
    (input.builderState.draft.buildMode === 'replace' && !input.builderState.replaceConfirmed), buildPending, 'build');
  renderReview(input, doc);
  setButton(doc, 'setup-next', input.builderState.phase !== 'preview-ready' || input.builderState.preview?.status !== 'ready', input.builderState.phase === 'review-loading', 'preview');

  const watch = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-result-watch"]');
  if (watch) {
    const available = input.state.resultWatchChannelId !== null;
    watch.hidden = !available; watch.disabled = !available; watch.setAttribute('aria-disabled', String(!available));
  }
  setText(input.dom.channelSetupResultElement, resultText(input.builderState));
  const resultPresentation = resultHeading(input.builderState);
  setText(doc.querySelector('[data-builder-result-title]'), resultPresentation.title);
  setText(doc.querySelector('[data-builder-result-intro]'), resultPresentation.intro);
  setText(doc.querySelector('[data-setup-safe-error]'), input.builderState.safeError ?? input.state.safeError ?? 'Channel setup could not continue.');
  setText(doc.querySelector('[data-setup-recovery-step]'), input.state.recovery?.originStep === 'library' ? 'Step 1 of 3' : 'Step 3 of 3');
  setText(doc.querySelector('[data-custom-delete-error]'), input.customState.lastError ?? '');
  const deleteConfirm = doc.querySelector<HTMLButtonElement>('[data-focus-id="custom-delete-confirm"]');
  if (deleteConfirm) { deleteConfirm.dataset.customChannelDetail = input.state.deleteChannelId ?? ''; setPending(deleteConfirm, input.customState.pendingAction === 'delete'); }
  const setupCustom = input.state.owner === 'setup-custom';
  toggleFooter(doc, 'setup-done', !setupCustom); toggleFooter(doc, 'setup-back', !setupCustom); toggleFooter(doc, 'custom-channel-back', setupCustom);
}

function renderReview(input: Parameters<typeof renderStagedSetupDom>[0], doc: Document): void {
  const review = input.builderState.review;
  const rows = review === null ? [['Review', input.builderState.phase === 'review-loading' ? (input.builderState.slow ? 'Review is taking longer than expected…' : 'Calculating lineup changes…') : 'Waiting for an up-to-date preview']] : [
    ['Created', String(review.diff.summary.created)], ['Removed', String(review.diff.summary.removed)],
    ['Unchanged', String(review.diff.summary.unchanged)], ['Build mode', input.builderState.draft.buildMode],
  ];
  const host = doc.querySelector<HTMLElement>('[data-builder-review-list]');
  host?.replaceChildren(...rows.map(([label, value]) => {
    const row = doc.createElement('div'); row.className = 'setup-review-row';
    const strong = doc.createElement('strong'); strong.textContent = label;
    const span = doc.createElement('span'); span.textContent = value;
    row.append(strong, span); return row;
  }));
  setText(doc.querySelector('[data-builder-review-impact]'), input.builderState.draft.buildMode === 'replace'
    ? 'Replace removes all existing channels, including custom channels. This requires explicit confirmation.'
    : input.builderState.draft.buildMode === 'merge' ? 'Matching generated channels update in place; custom channels remain untouched.' : 'Existing channels remain and unmatched generated channels are appended.');
  setText(doc.querySelector('[data-channel-review-validation]'), input.builderState.phase === 'review-error' ? input.builderState.safeError ?? 'Review unavailable.' : input.builderState.phase === 'review-loading' ? (input.builderState.slow ? 'Still reviewing. You can keep waiting.' : 'Reviewing…') : '');
  const retry = doc.querySelector<HTMLButtonElement>('[data-focus-id="builder-review-retry"]');
  if (retry) { retry.hidden = input.builderState.phase !== 'review-error'; retry.disabled = input.builderState.phase !== 'review-error'; }
}

const STRATEGIES: readonly ChannelSetupStrategyKey[] = ['playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors'];
const CATEGORIES: readonly ChannelBuilderCategory[] = ['content-sources', 'advanced-sources', 'build-options', 'series-ordering', 'limits', 'priority-order'];
const CONTENT_STRATEGIES: readonly ChannelSetupStrategyKey[] = ['collections', 'playlists', 'recentlyAdded'];
const ADVANCED_STRATEGIES: readonly ChannelSetupStrategyKey[] = ['genres', 'directors', 'decades', 'studios', 'actors'];
export function renderChannelBuilderDom(state: ChannelBuilderState, doc: Document): void {
  const categories = doc.querySelector<HTMLElement>('[data-builder-categories]');
  if (categories) {
    const scrollTop = categories.scrollTop;
    categories.replaceChildren(...CATEGORIES.map((category) => {
    const button = doc.createElement('button'); button.type = 'button'; button.dataset.builderAction = 'selectCategory';
    button.dataset.builderDetail = category; button.dataset.focusId = `builder-category-${category}`;
    button.className = state.activeCategory === category ? 'selected' : ''; button.setAttribute('aria-pressed', String(state.activeCategory === category));
      const strong = doc.createElement('strong'); strong.textContent = categoryLabel(category); button.append(strong); return button;
    }));
    categories.scrollTop = scrollTop;
  }
  const detail = doc.querySelector<HTMLElement>('[data-builder-detail]');
  if (detail) {
    const scrollTop = detail.scrollTop;
    detail.replaceChildren();
    const title = doc.createElement('h3'); title.textContent = categoryLabel(state.activeCategory); detail.append(title);
    renderCategoryControls(state, detail, doc);
    detail.scrollTop = scrollTop;
  }
  const status = state.phase === 'preview-loading' ? (state.slow ? 'Preview is taking longer than expected…' : 'Updating preview…') :
    state.phase === 'preview-error' ? state.safeError ?? 'Preview unavailable.' : state.phase === 'preview-blocked' ? state.safeError ?? 'Preview blocked.' :
      state.preview === null ? 'Change an option to preview the generated lineup.' : `${String(state.preview.selectedGeneratedCount)} of ${String(state.preview.eligibleGeneratedCount)} eligible channels selected.`;
  setText(doc.querySelector('[data-builder-preview-status]'), status);
  setText(doc.querySelector('[data-builder-preview-counts]'), state.preview === null ? '' :
    `${String(state.preview.droppedByMinItemsCount)} below minimum · ${String(state.preview.droppedByPlanCapCount)} over plan cap`);
  const retry = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-preview-retry"]');
  if (retry) { retry.hidden = state.phase !== 'preview-error'; retry.disabled = state.phase !== 'preview-error'; }
  setText(doc.querySelector('[data-builder-selected-count]'), state.preview === null ? 'No current preview' : `${String(state.preview.selectedGeneratedCount)} planned`);
  setText(doc.querySelector('[data-builder-warning]'), state.preview?.warnings.join(' · ') ?? '');
  const progress = doc.querySelector<HTMLElement>('[data-builder-progress]');
  if (progress) {
    const value = state.progress?.current ?? 0; const total = state.progress?.total;
    progress.setAttribute('aria-valuenow', String(value));
    if (total === null || total === undefined) progress.removeAttribute('aria-valuemax'); else progress.setAttribute('aria-valuemax', String(total));
    const fill = progress.querySelector<HTMLElement>('span'); if (fill) fill.style.width = total && total > 0 ? `${String(Math.min(100, Math.round(value / total * 100)))}%` : '12%';
  }
  setText(doc.querySelector('[data-builder-progress-detail]'), state.progress === null ? 'Preparing channel plan…' : `${state.progress.label}. ${state.progress.detail}`);
  setText(doc.querySelector('[data-builder-cancel-status]'), state.cancelStatus === 'accepted' ? 'Cancellation requested. Waiting for the terminal result.' : state.cancelStatus === 'too-late' ? 'The atomic apply has started; waiting for completion.' : state.cancelStatus === 'requesting' ? 'Requesting cancellation…' : '');
  const cancel = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-progress-cancel"]');
  if (cancel) { cancel.disabled = state.phase !== 'progress' || state.cancelStatus !== 'idle'; cancel.setAttribute('aria-disabled', String(cancel.disabled)); cancel.setAttribute('aria-busy', String(state.cancelStatus === 'requesting')); }
}

function renderCategoryControls(state: ChannelBuilderState, host: HTMLElement, doc: Document): void {
  if (state.activeCategory === 'content-sources' || state.activeCategory === 'advanced-sources') {
    for (const strategy of state.activeCategory === 'content-sources' ? CONTENT_STRATEGIES : ADVANCED_STRATEGIES) renderStrategyControls(state, strategy, host, doc);
    return;
  }
  if (state.activeCategory === 'build-options') {
    renderAdjustable(state, host, doc, 'build-mode', 'Build mode', 'Replace, append, or merge with your lineup.', state.draft.buildMode);
    renderAdjustable(state, host, doc, 'combine-mode', 'Actor/Studio combine', 'Separate movies + TV or combine together.', state.draft.actorStudioCombineMode === 'combined' ? 'Combined' : 'Separate');
    host.append(controlButton(doc, 'builder-alternates', 'Add Alternate Lineups', 'toggleAlternates', undefined, expansion(state).addAlternateLineups, 'Create extra deterministic shuffle lineups.'));
    renderAdjustable(state, host, doc, 'alternate-copies', 'Alternate Lineup Copies', 'How many extra copies per generated channel.', String(expansion(state).alternateLineupCopies), !expansion(state).addAlternateLineups);
    const custom = doc.createElement('button'); custom.type = 'button'; custom.dataset.setupFlowAction = 'openSetupCustom'; custom.dataset.focusId = 'channel-strategy-build-custom'; custom.textContent = 'Create a custom channel (Desktop option)'; host.append(custom); return;
  }
  if (state.activeCategory === 'series-ordering') {
    renderAdjustable(state, host, doc, 'base-mode', 'Base Series Mode', 'Default playback mode for TV-derived channels.', series(state).basePlaybackMode === 'block' ? `Block • ${String(series(state).baseBlockSize)}` : capitalize(series(state).basePlaybackMode));
    renderAdjustable(state, host, doc, 'base-block', 'Base Block Size', 'Episodes per show before switching in block mode.', String(series(state).baseBlockSize), series(state).basePlaybackMode !== 'block');
    renderAdjustable(state, host, doc, 'variant-type', 'Variant Type', 'Optional extra series channel mode.', expansion(state).variantType === 'block' ? `Block • ${String(expansion(state).variantBlockSize)}` : capitalize(expansion(state).variantType));
    renderAdjustable(state, host, doc, 'variant-block', 'Variant Block Size', 'Block size for generated block variants.', String(expansion(state).variantBlockSize), expansion(state).variantType !== 'block'); return;
  }
  if (state.activeCategory === 'limits') {
    renderAdjustable(state, host, doc, 'max-channels', 'Max channels', 'Limit the generated plan to at most 500 channels.', String(state.draft.maxChannels));
    renderAdjustable(state, host, doc, 'min-items', 'Min items', 'Minimum content items per generated channel.', String(state.draft.minItemsPerChannel)); return;
  }
  renderGuideOrder(state, host, doc);
}
function renderStrategyControls(state: ChannelBuilderState, strategy: ChannelSetupStrategyKey, host: HTMLElement, doc: Document): void {
  const value = state.draft.strategyConfig[strategy] ?? { enabled: true, priority: STRATEGIES.indexOf(strategy) + 1, scope: 'per-library' };
  host.append(controlButton(doc, `builder-strategy-${strategy}`, categoryLabel(strategy), 'toggleStrategy', strategy, value.enabled !== false, strategyMeta(strategy), value.enabled === false ? 'Off' : 'On'));
  if (['genres', 'studios', 'actors', 'directors'].includes(strategy)) {
    const trigger = controlButton(doc, `builder-${strategy}-scope`, `Scope: ${value.scope === 'cross-library' ? 'Across libraries' : 'Per library'}`, 'toggleScopeDropdown', strategy);
    trigger.setAttribute('aria-haspopup', 'listbox'); trigger.setAttribute('aria-expanded', String(state.openScopeDropdown === strategy)); host.append(trigger);
    if (state.openScopeDropdown === strategy) {
      const list = doc.createElement('div'); list.className = 'builder-scope-menu'; list.setAttribute('role', 'listbox'); list.setAttribute('aria-label', `${categoryLabel(strategy)} scope`);
      for (const scope of ['per-library', 'cross-library'] as const) { const option = controlButton(doc, `builder-scope-option-${strategy}-${scope}`, scope === 'per-library' ? 'Per library' : 'Across selected libraries', 'selectScope', `${strategy}:${scope}`, value.scope === scope); option.setAttribute('role', 'option'); option.setAttribute('aria-selected', String(value.scope === scope)); list.append(option); }
      host.append(list);
    }
  }
}
function renderAdjustable(state: ChannelBuilderState, host: HTMLElement, doc: Document, control: ChannelBuilderAdjustableControl, label: string, meta: string, value: string, disabled = false): void {
  const trigger = controlButton(doc, `builder-control-${control}`, label, 'toggleAdjustable', control, state.openAdjustableControl === control, meta, value); trigger.disabled = disabled; trigger.setAttribute('aria-disabled', String(disabled)); trigger.setAttribute('aria-haspopup', 'listbox'); trigger.setAttribute('aria-expanded', String(state.openAdjustableControl === control)); host.append(trigger);
  if (state.openAdjustableControl !== control || disabled) return;
  const menu = doc.createElement('div'); menu.className = 'builder-adjustable-menu'; menu.setAttribute('role', 'listbox'); menu.setAttribute('aria-label', label);
  for (const optionValue of adjustableOptions(control)) { const option = controlButton(doc, `builder-option-${control}-${String(optionValue)}`, formatOption(optionValue), 'selectAdjustable', `${control}:${String(optionValue)}`, currentAdjustableValue(state, control) === String(optionValue)); option.setAttribute('role', 'option'); option.setAttribute('aria-selected', String(currentAdjustableValue(state, control) === String(optionValue))); menu.append(option); }
  host.append(menu);
}
function renderGuideOrder(state: ChannelBuilderState, host: HTMLElement, doc: Document): void {
  const active = orderedStrategies(state).filter((key) => state.draft.strategyConfig[key]?.enabled !== false);
  const reset = controlButton(doc, 'builder-guide-reset', 'Reset Order', 'resetGuideOrder'); reset.disabled = active.every((key, index) => key === STRATEGIES.filter((candidate) => state.draft.strategyConfig[candidate]?.enabled !== false)[index]); host.append(reset);
  for (const [index, strategy] of active.entries()) { const grabbed = state.grabbedPriorityKey === strategy; const row = controlButton(doc, `builder-priority-${strategy}`, `${String(index + 1)}  ${categoryLabel(strategy)}`, 'togglePriorityGrab', strategy, grabbed, grabbed ? 'Up/Down to move · OK to place · Back to cancel' : 'OK to pick up · Up/Down to move', grabbed ? 'Picked up' : '↕'); row.classList.add('builder-priority-row'); row.disabled = active.length < 2; row.setAttribute('aria-label', `Guide order ${String(index + 1)}: ${categoryLabel(strategy)}${grabbed ? ', picked up' : ''}`); host.append(row); }
  const status = doc.createElement('p'); status.className = 'builder-guide-order-hint'; status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite'); status.textContent = active.length < 2 ? 'Enable more sources to customize order.' : state.grabbedPriorityKey === null ? 'OK to pick up · Up/Down to move · OK to place' : 'Up/Down to move · OK to place · Back to cancel'; host.append(status);
}
function controlButton(doc: Document, focusId: string, label: string, action: string, detail?: string, selected = false, meta?: string, stateText?: string): HTMLButtonElement { const button = doc.createElement('button'); button.type = 'button'; button.dataset.focusId = focusId; button.dataset.builderAction = action; if (detail) button.dataset.builderDetail = detail; const labelNode = doc.createElement('strong'); labelNode.textContent = label; button.append(labelNode); if (meta) { const metaNode = doc.createElement('small'); metaNode.textContent = meta; button.append(metaNode); } if (stateText) { const stateNode = doc.createElement('span'); stateNode.className = 'builder-control-state'; stateNode.textContent = stateText; button.append(stateNode); } button.classList.toggle('selected', selected); button.setAttribute('aria-pressed', String(selected)); return button; }
function categoryLabel(value: string): string { const categories: Record<string, string> = { 'content-sources': 'Content Sources', 'advanced-sources': 'Advanced Sources', 'build-options': 'Build Options', 'series-ordering': 'Series Ordering', limits: 'Limits', 'priority-order': 'Guide Order', recentlyAdded: 'Recently added' }; return categories[value] ?? value[0]!.toUpperCase() + value.slice(1); }
function strategyMeta(value: ChannelSetupStrategyKey): string { return { playlists: 'Channels from Plex playlists.', collections: 'One channel per collection.', recentlyAdded: 'Per library, newest first.', genres: 'Filter channels by genre.', studios: 'Channels by studio.', actors: 'Channels by actor.', decades: 'Channels by decade.', directors: 'Channels by director.' }[value]; }
function orderedStrategies(state: ChannelBuilderState): ChannelSetupStrategyKey[] { return [...STRATEGIES].sort((a, b) => (state.draft.strategyConfig[a]?.priority ?? 0) - (state.draft.strategyConfig[b]?.priority ?? 0)); }
function adjustableOptions(control: ChannelBuilderAdjustableControl): readonly (string | number)[] { if (control === 'build-mode') return ['replace', 'append', 'merge']; if (control === 'combine-mode') return ['separate', 'combined']; if (control === 'alternate-copies') return [1, 2, 3]; if (control === 'base-mode') return ['shuffle', 'sequential', 'block']; if (control === 'variant-type') return ['none', 'sequential', 'block']; if (control === 'base-block' || control === 'variant-block') return [2, 3, 4, 5]; if (control === 'max-channels') return [50, 100, 150, 200, 300, 400, 500]; return [1, 5, 10, 20, 50]; }
function currentAdjustableValue(state: ChannelBuilderState, control: ChannelBuilderAdjustableControl): string { if (control === 'build-mode') return state.draft.buildMode; if (control === 'combine-mode') return state.draft.actorStudioCombineMode; if (control === 'alternate-copies') return String(expansion(state).alternateLineupCopies); if (control === 'base-mode') return series(state).basePlaybackMode; if (control === 'base-block') return String(series(state).baseBlockSize); if (control === 'variant-type') return expansion(state).variantType; if (control === 'variant-block') return String(expansion(state).variantBlockSize); if (control === 'max-channels') return String(state.draft.maxChannels); return String(state.draft.minItemsPerChannel); }
function formatOption(value: string | number): string { return typeof value === 'number' ? String(value) : capitalize(value); }
function capitalize(value: string): string { return value.charAt(0).toUpperCase() + value.slice(1); }
function expansion(state: ChannelBuilderState) { return { addAlternateLineups: false, alternateLineupCopies: 1, variantType: 'none', variantBlockSize: 2, ...state.draft.channelExpansion }; }
function series(state: ChannelBuilderState) { return { basePlaybackMode: 'shuffle', baseBlockSize: 2, ...state.draft.seriesOrdering }; }
function resultText(state: ChannelBuilderState): string {
  const result = state.result; if (result === null) return state.safeError ?? 'Build result unavailable.';
  if (result.kind === 'canceled') return 'Build canceled before channels were applied.';
  if (result.kind === 'failed') return result.error.message;
  const guide = result.guideRefresh.kind === 'completed' ? 'Guide refreshed.' : result.guideRefresh.message;
  return `${String(result.counts.createdCount)} created, ${String(result.counts.updatedCount)} updated, ${String(result.counts.preservedCount)} preserved. ${guide}`;
}
function resultHeading(state: ChannelBuilderState): { title: string; intro: string } {
  if (state.result?.kind === 'canceled') return { title: 'Build canceled', intro: 'No channel changes were applied.' };
  if (state.result?.kind === 'committed-with-record-warning' || (state.result?.kind === 'committed' && state.result.guideRefresh.kind !== 'completed')) return { title: 'Lineup ready with a warning', intro: 'Channels were saved. Review the summary before continuing.' };
  return { title: 'Lineup ready', intro: 'The saved channel summary has been refreshed.' };
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
