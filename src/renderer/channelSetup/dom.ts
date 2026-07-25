import type { RendererDomBindings } from '../domBindings.js';
import type { RouteWorkflowViewModel } from '../workflow.js';
import type { ChannelSetupLiveSelectionViewModel } from './viewModel.js';

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
  if (dom.channelDraftListElement) {
    dom.channelDraftListElement.replaceChildren(renderLibrarySource(view));
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
