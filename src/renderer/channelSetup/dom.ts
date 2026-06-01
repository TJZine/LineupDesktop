import type { RendererDomBindings } from '../domBindings.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { ChannelSetupLiveSelectionViewModel } from './viewModel.js';

export function renderChannelSetupDom(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  liveSelection: ChannelSetupLiveSelectionViewModel | null,
): void {
  if (dom.channelSetupFixtureStatusElement) {
    dom.channelSetupFixtureStatusElement.textContent = view.channelSetupFlow.stageLabel;
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
  if (dom.setupStepsElement) {
    dom.setupStepsElement.replaceChildren(
      ...view.channelSetupFlow.stages.map((stage) => {
        const item = document.createElement('li');
        item.dataset.stepState = stage.state;
        const label = document.createElement('strong');
        label.textContent = stage.label;
        const detail = document.createElement('span');
        detail.textContent = stage.detail;
        item.append(label, detail);
        return item;
      }),
    );
  }
  if (dom.channelDraftListElement) {
    dom.channelDraftListElement.replaceChildren(renderLibrarySource(view));
  }
  if (dom.channelSetupStrategyElement) {
    dom.channelSetupStrategyElement.replaceChildren(
      ...view.channelSetupFlow.strategyOptions.map((option) => {
        const item = document.createElement('button');
        item.type = 'button';
        item.className = `setup-toggle${option.selected ? ' selected' : ''}`;
        item.dataset.strategyOption = option.id;
        item.dataset.setupAction = option.actionId;
        item.dataset.focusId = option.focusId;
        item.disabled = option.disabled;
        item.setAttribute('aria-pressed', String(option.selected));
        const label = document.createElement('span');
        label.className = 'setup-toggle-label';
        label.textContent = option.label;
        const meta = document.createElement('span');
        meta.className = 'setup-toggle-meta';
        meta.textContent = option.detail;
        const value = document.createElement('span');
        value.className = 'setup-toggle-state';
        value.textContent = option.value;
        item.append(label, meta, value);
        return item;
      }),
    );
  }
  if (dom.channelSetupReviewElement) {
    dom.channelSetupReviewElement.replaceChildren(
      ...view.channelSetupFlow.reviewRows.map((row) => {
        const item = document.createElement('div');
        item.className = 'setup-preview-row';
        const label = document.createElement('span');
        label.className = 'setup-preview-label';
        label.textContent = row.label;
        const value = document.createElement('span');
        value.className = 'setup-preview-value';
        value.textContent = row.value;
        const detail = document.createElement('span');
        detail.className = 'setup-preview-detail';
        detail.textContent = row.detail;
        item.append(label, value, detail);
        return item;
      }),
    );
  }
  if (dom.setupValidationElement) {
    const messages = view.setupValidationMessages.length === 0
      ? ['Choose a movie or show library section before saving channels.']
      : view.setupValidationMessages;
    dom.setupValidationElement.replaceChildren(
      ...messages.map((message) => {
        const item = document.createElement('p');
        item.textContent = message;
        return item;
      }),
    );
  }
  if (dom.channelSetupResultElement) {
    dom.channelSetupResultElement.dataset.resultTone = view.channelSetupFlow.result.tone;
    dom.channelSetupResultElement.replaceChildren(renderResult(view));
  }
  for (const button of dom.channelCommitButtons) {
    const action = button.dataset.channelCommitAction;
    button.disabled = channelCommitDisabled(action, view);
    switch (action) {
      case 'append':
        button.textContent = view.channelSetupFlow.buildMode === 'append'
          ? 'Build append mode'
          : 'Build appended channel';
        break;
      case 'replace':
        button.textContent = view.channelSetupFlow.buildMode === 'replace'
          ? 'Review replace mode'
          : 'Choose replace mode';
        break;
      case 'confirmReplace':
        button.textContent = 'Confirm & Replace';
        break;
    }
  }
}

function renderLibrarySource(view: RouteWorkflowViewModel): HTMLElement {
  const item = document.createElement('article');
  item.className = `channel-draft-list__item channel-draft-list__item--source${view.channelSetupFlow.library.selected ? ' selected' : ''}`;
  item.dataset.reviewStatus = view.channelSetupFlow.library.selected ? 'active' : 'disabled';
  const marker = document.createElement('span');
  marker.className = 'channel-list__number';
  marker.textContent = view.channelSetupFlow.library.marker;
  const copy = document.createElement('div');
  const title = document.createElement('strong');
  title.textContent = view.channelSetupFlow.library.title;
  const detail = document.createElement('p');
  detail.textContent = `${view.channelSetupFlow.library.detail} ${view.channelSetupFlow.library.countLabel}`;
  copy.append(title, detail);
  item.append(marker, copy);
  return item;
}

function renderResult(view: RouteWorkflowViewModel): HTMLElement {
  const item = document.createElement('article');
  item.className = 'setup-result-card';
  const title = document.createElement('strong');
  title.textContent = view.channelSetupFlow.result.title;
  const detail = document.createElement('p');
  detail.textContent = view.channelSetupFlow.result.detail;
  item.append(title, detail);
  return item;
}

function channelCommitDisabled(
  action: string | undefined,
  view: RouteWorkflowViewModel,
): boolean {
  switch (action) {
    case 'append':
      return !view.channelSetupCommitAvailability.append;
    case 'replace':
      return !view.channelSetupCommitAvailability.replace;
    case 'confirmReplace':
      return !view.channelSetupCommitAvailability.confirmReplace;
    default:
      return true;
  }
}
