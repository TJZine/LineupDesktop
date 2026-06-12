import type { CustomChannelActionId, CustomChannelController } from './controller.js';

export interface CustomChannelActionDispatchInput {
  action: CustomChannelActionId;
  detail: string | undefined;
  selectedSourceId: string | null;
  controller: CustomChannelController;
  refreshChannels(): void;
  refreshGuide(): void;
  render(): void;
}

export async function dispatchCustomChannelAction(input: CustomChannelActionDispatchInput): Promise<void> {
  if (input.action === 'browseSource') {
    await input.controller.browseSource(input.selectedSourceId);
  } else if (input.action === 'searchMedia') {
    await input.controller.searchMedia(input.selectedSourceId);
  } else if (input.action === 'clearSearch') {
    input.controller.clearSearch();
  } else {
    await input.controller.applyAction(input.action, input.detail);
  }

  if (shouldRefreshRuntimeChannels(input.action)) {
    input.refreshChannels();
    input.refreshGuide();
  }

  input.render();
}

function shouldRefreshRuntimeChannels(action: CustomChannelActionId): boolean {
  return action === 'saveDraft'
    || action === 'confirmDeleteChannel'
    || action === 'toggleChannelVisibility'
    || action === 'moveChannelUp'
    || action === 'moveChannelDown';
}
