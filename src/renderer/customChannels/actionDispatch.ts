import type { CustomChannelActionId, CustomChannelActionOutcome, CustomChannelController } from './controller.js';

export interface CustomChannelActionDispatchInput {
  action: CustomChannelActionId;
  detail: string | undefined;
  selectedSourceId: string | null;
  controller: CustomChannelController;
  refreshChannels(): void;
  refreshGuide(): void;
  render(): void;
  flow?: {
    openEditor(invokerFocusId: string): void;
    closeEditor(savedChannelId: string | null): void;
    openDelete(channelId: string, invokerFocusId: string): void;
    closeDelete(restoreFocusId: string): void;
    restoreDeleteFocus(focusId: string): void;
    restoreListFocus(focusId: string): void;
  };
}

export async function dispatchCustomChannelAction(input: CustomChannelActionDispatchInput): Promise<void> {
  if (input.action === 'requestDeleteChannel' && input.detail !== undefined) {
    const outcome = await input.controller.applyAction(input.action, input.detail);
    if (outcome === 'succeeded') input.flow?.openDelete(input.detail, `custom-channel-delete-${input.detail}`);
    return;
  }
  const beforeChannels = input.controller.getState().snapshot?.channels ?? [];
  const beforeIndex = input.detail === undefined ? -1 : beforeChannels.findIndex((channel) => channel.id === input.detail);
  let outcome: CustomChannelActionOutcome;
  if (input.action === 'browseSource') {
    outcome = await input.controller.browseSource(input.selectedSourceId);
  } else if (input.action === 'searchMedia') {
    outcome = await input.controller.searchMedia(input.selectedSourceId);
  } else if (input.action === 'clearSearch') {
    input.controller.clearSearch();
    outcome = 'succeeded';
  } else {
    outcome = await input.controller.applyAction(input.action, input.detail);
  }

  input.render();
  if (outcome === 'failed' && input.action === 'confirmDeleteChannel') {
    input.flow?.restoreDeleteFocus('custom-delete-confirm');
    return;
  }
  if (outcome !== 'succeeded') return;

  if (shouldRefreshRuntimeChannels(input.action)) {
    input.refreshChannels();
    input.refreshGuide();
  }
  coordinateFlow(input, beforeIndex);
}

function coordinateFlow(input: CustomChannelActionDispatchInput, beforeIndex: number): void {
  const detail = input.detail;
  const state = input.controller.getState();
  if (input.action === 'duplicateChannel' && detail !== undefined && state.lastError === null && !state.pending) {
    input.flow?.openEditor(`custom-channel-duplicate-${detail}`);
  } else if (input.action === 'saveDraft' && state.lastError === null && state.validation?.valid === true) {
    input.flow?.closeEditor(state.lastSavedChannelId);
  } else if (input.action === 'confirmDeleteChannel' && detail !== undefined) {
    const channels = state.snapshot?.channels ?? [];
    const next = channels[Math.min(Math.max(beforeIndex, 0), Math.max(channels.length - 1, 0))];
    input.flow?.closeDelete(next ? `custom-channel-duplicate-${next.id}` : 'custom-channel-new');
  } else if (detail !== undefined && ['toggleChannelVisibility', 'moveChannelUp', 'moveChannelDown'].includes(input.action)) {
    const prefix = input.action === 'toggleChannelVisibility' ? 'hide' : input.action === 'moveChannelUp' ? 'up' : 'down';
    input.flow?.restoreListFocus(`custom-channel-${prefix}-${detail}`);
  }
}

function shouldRefreshRuntimeChannels(action: CustomChannelActionId): boolean {
  return action === 'saveDraft'
    || action === 'confirmDeleteChannel'
    || action === 'toggleChannelVisibility'
    || action === 'moveChannelUp'
    || action === 'moveChannelDown';
}
