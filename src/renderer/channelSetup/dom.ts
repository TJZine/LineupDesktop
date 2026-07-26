import type { RendererDomBindings } from '../domBindings.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { ChannelRuntimeRendererState } from '../channelRuntimeState.js';
import type { StagedSetupState } from '../setup/stagedSetupController.js';
import {
  createChannelBuilderConfigRows,
  createChannelBuilderReview,
  type ChannelSetupLiveSelectionViewModel,
} from './viewModel.js';

export function renderChannelSetupDom(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
  activeSetupStage: string,
): void {
  // Update stage category rail active states and visibility of setup sections
  if (typeof document !== 'undefined' && typeof document.querySelectorAll === 'function') {
    const stageButtons = document.querySelectorAll<HTMLButtonElement>('[data-setup-stage]');
    for (const button of Array.from(stageButtons)) {
      const isActive = button.dataset.setupStage === activeSetupStage;
      button.classList.toggle('is-active', isActive);
    }

    const setupSections = document.querySelectorAll<HTMLElement>('[data-setup-section]');
    for (const section of Array.from(setupSections)) {
      const isActive = section.dataset.setupSection === activeSetupStage;
      if (isActive) {
        section.removeAttribute('hidden');
      } else {
        section.setAttribute('hidden', '');
      }
    }
  }

  if (dom.channelSetupSourceElement) {
    dom.channelSetupSourceElement.textContent = view.channelSetupSummary.sourceName;
  }
  if (dom.channelSetupEnabledElement) {
    dom.channelSetupEnabledElement.textContent =
      `${view.channelSetupSummary.enabledChannelCount} of ${view.channelSetupSummary.totalChannelCount}`;
  }
  if (dom.channelSetupBlocksElement) {
    dom.channelSetupBlocksElement.textContent =
      liveSelection === null
        ? 'No selected source'
        : `${String(view.channelSetupSummary.totalBlockCount)} library items`;
  }
}

export function renderChannelBuilderDom(input: {
  state: StagedSetupState;
  channelState: ChannelRuntimeRendererState;
  progress: RouteWorkflowViewModel['channelSetupProgress'];
  documentRef: Document;
}): void {
  renderBuilderConfig(input);
  renderBuilderReview(input);
  renderBuilderProgress(input);
}

function renderBuilderReview(input: Parameters<typeof renderChannelBuilderDom>[0]): void {
  const { documentRef: doc } = input;
  const review = createChannelBuilderReview(input.channelState.operation);
  const rows = [
    ['Created', String(review.counts.created), review.samples.created],
    ['Removed', String(review.counts.removed), review.samples.removed],
    ['Unchanged', String(review.counts.unchanged), review.samples.unchanged],
  ] as const;
  const host = doc.querySelector<HTMLElement>('[data-staged-owner="build"] [data-channel-review-list]');
  host?.replaceChildren(...rows.map(([label, value, samples]) => {
    const row = doc.createElement('div');
    row.className = 'setup-review-row';
    const strong = doc.createElement('strong');
    strong.textContent = label;
    const span = doc.createElement('span');
    span.textContent = samples.length === 0 ? value : `${value} — ${samples.join(', ')}`;
    row.append(strong, span);
    return row;
  }));
  const tone = review.status === 'blocked'
    ? 'Build blocked'
    : review.status === 'slow'
      ? 'Review completed with slow or partial discovery'
      : 'Review ready';
  setText(doc.querySelector('[data-channel-review-impact]'), `${tone}. ${input.state.buildMode === 'replace' ? 'Replacement requires explicit confirmation.' : 'The saved lineup remains until apply commits.'}`);
  setText(doc.querySelector('[data-channel-review-validation]'), [
    ...review.warnings,
    ...(review.reachedCap ? ['Maximum channel cap reached.'] : []),
  ].join(' '));
  const regularApply = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-confirm"]');
  const replaceApply = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-confirm-replace"]');
  projectAction(regularApply, !review.canApply || input.channelState.pending || input.state.buildMode === 'replace', input.state.buildMode === 'replace');
  projectAction(replaceApply, !review.canApply || input.channelState.pending || input.state.buildMode !== 'replace', input.state.buildMode !== 'replace');
}

function renderBuilderConfig(input: Parameters<typeof renderChannelBuilderDom>[0]): void {
  const { documentRef: doc } = input;
  const host = doc.querySelector<HTMLElement>('[data-channel-builder-config]');
  const config = input.state.builderConfig?.config;
  if (host === null || config === undefined) return;
  const modeGroup = group(doc, 'Lineup mode');
  modeGroup.append(
    actionButton(doc, 'Append', 'channel-strategy-build-append', 'configModeAppend', config.buildMode === 'append'),
    actionButton(doc, 'Merge', 'channel-strategy-build-merge', 'configModeMerge', config.buildMode === 'merge'),
    actionButton(doc, 'Replace', 'channel-strategy-build-replace', 'configModeReplace', config.buildMode === 'replace'),
    actionButton(doc, 'Custom channels', 'channel-strategy-build-custom', 'openSetupCustom'),
  );
  const limits = group(doc, 'Limits and grouping');
  limits.append(
    actionButton(doc, `Max channels − (${String(config.maxChannels)})`, 'builder-max-down', 'configMaxDown'),
    actionButton(doc, 'Max channels +', 'builder-max-up', 'configMaxUp'),
    actionButton(doc, `Minimum items − (${String(config.minItemsPerChannel)})`, 'builder-min-down', 'configMinDown'),
    actionButton(doc, 'Minimum items +', 'builder-min-up', 'configMinUp'),
    actionButton(doc, `Actors/studios: ${config.actorStudioCombineMode}`, 'builder-combine', 'configCombineMode'),
  );
  const strategyGroup = group(doc, 'Channel strategies');
  for (const row of createChannelBuilderConfigRows(config)) {
    const card = doc.createElement('article');
    card.className = 'setup-builder-strategy';
    const title = doc.createElement('h4');
    title.textContent = row.label;
    card.append(
      title,
      actionButton(doc, row.enabled ? 'Enabled' : 'Disabled', `builder-${row.key}-toggle`, `strategyToggle:${row.key}`, row.enabled),
      actionButton(doc, `Priority − (${String(row.priority)})`, `builder-${row.key}-priority-down`, `strategyPriorityDown:${row.key}`, undefined, !row.enabled),
      actionButton(doc, 'Priority +', `builder-${row.key}-priority-up`, `strategyPriorityUp:${row.key}`, undefined, !row.enabled),
    );
    if (row.scopeEditable) {
      card.append(actionButton(doc, row.scope === 'cross-library' ? 'Across libraries' : 'Per library', `builder-${row.key}-scope`, `strategyScope:${row.key}`, undefined, !row.enabled));
    }
    strategyGroup.append(card);
  }
  const expansion = group(doc, 'Lineup variants');
  expansion.append(
    actionButton(doc, config.channelExpansion.addAlternateLineups ? 'Alternate lineups on' : 'Alternate lineups off', 'builder-alternates', 'configAlternates', config.channelExpansion.addAlternateLineups),
    actionButton(doc, `Copies: ${String(config.channelExpansion.alternateLineupCopies)}`, 'builder-alternate-copies', 'configAlternateCopies', undefined, !config.channelExpansion.addAlternateLineups),
    actionButton(doc, `Variant: ${config.channelExpansion.variantType}`, 'builder-variant-type', 'configVariantType'),
    actionButton(doc, `Variant block: ${String(config.channelExpansion.variantBlockSize)}`, 'builder-variant-block', 'configVariantBlockSize', undefined, config.channelExpansion.variantType !== 'block'),
    actionButton(doc, `Series: ${config.seriesOrdering.basePlaybackMode}`, 'builder-series-mode', 'configSeriesMode'),
    actionButton(doc, `Series block: ${String(config.seriesOrdering.baseBlockSize)}`, 'builder-series-block', 'configSeriesBlockSize', undefined, config.seriesOrdering.basePlaybackMode !== 'block'),
  );
  host.replaceChildren(modeGroup, limits, strategyGroup, expansion);
}

function renderBuilderProgress(input: Parameters<typeof renderChannelBuilderDom>[0]): void {
  const { documentRef: doc } = input;
  const cancelButton = doc.querySelector<HTMLButtonElement>('[data-focus-id="setup-progress-cancel"]');
  if (cancelButton) {
    const canceling = input.channelState.operation?.state === 'canceling';
    cancelButton.hidden = !input.progress.canCancel && !canceling;
    cancelButton.disabled = !input.progress.canCancel;
    cancelButton.textContent = canceling ? 'Canceling…' : 'Cancel build';
    cancelButton.setAttribute('aria-disabled', String(cancelButton.disabled));
  }
  setText(doc.querySelector('[data-channel-operation-status]'), input.progress.statusText);
  const progressBar = doc.querySelector<HTMLElement>('.setup-progress-bar');
  const progressFill = progressBar?.querySelector<HTMLElement>('span');
  if (progressBar) {
    const total = input.progress.progress.total;
    const determinate = total !== null && total > 0;
    progressBar.setAttribute('aria-valuemin', '0');
    if (determinate) {
      progressBar.setAttribute('aria-valuemax', String(total));
      progressBar.setAttribute('aria-valuenow', String(Math.min(input.progress.progress.completed, total)));
    } else {
      progressBar.removeAttribute('aria-valuemax');
      progressBar.removeAttribute('aria-valuenow');
    }
    progressBar.dataset.determinate = String(determinate);
    if (progressFill) progressFill.style.width = determinate
      ? `${String(Math.min(100, Math.round((input.progress.progress.completed / total) * 100)))}%`
      : '';
  }
}

function group(doc: Document, label: string): HTMLElement {
  const section = doc.createElement('section');
  section.className = 'setup-builder-group';
  const heading = doc.createElement('h3');
  heading.textContent = label;
  section.append(heading);
  return section;
}

function actionButton(
  doc: Document,
  label: string,
  focusId: string,
  flowAction: string,
  pressed?: boolean,
  disabled = false,
): HTMLButtonElement {
  const button = doc.createElement('button');
  button.type = 'button';
  button.textContent = label;
  button.dataset.focusId = focusId;
  button.dataset.setupFlowAction = flowAction;
  button.disabled = disabled;
  button.setAttribute('aria-disabled', String(disabled));
  if (pressed !== undefined) {
    button.setAttribute('aria-pressed', String(pressed));
    button.classList.toggle('selected', pressed);
  }
  return button;
}

function projectAction(
  button: HTMLButtonElement | null,
  disabled: boolean,
  hidden: boolean,
): void {
  if (button === null) return;
  button.disabled = disabled;
  button.hidden = hidden;
  button.setAttribute('aria-disabled', String(disabled));
}

function setText(element: Element | null, text: string): void {
  if (element) element.textContent = text;
}
