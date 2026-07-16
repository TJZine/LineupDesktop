import type { PlexLibrarySectionSummary } from '../../contracts/plex.js';
import type { ChannelSetupCommitMode, ChannelSetupSummary } from '../../contracts/channel.js';
import type { AppRouteId, FocusRegistry, FocusState } from '../navigation.js';
import type { ChannelRuntimeController } from '../channelRuntimeActions.js';
import type { CustomChannelController } from '../customChannels/controller.js';
import type { PlexRuntimeController } from '../plexRuntimeActions.js';
import type { SetupRuntimeCoordinator } from './setupRuntimeCoordinator.js';
import {
  clearSetupLibrarySelection,
  normalizeSetupLibrarySelection,
  resolveSetupPreviewCursor,
  selectAllSetupLibraries,
  toggleSetupLibrarySelection,
} from './setupLibrarySelection.js';

export type StagedSetupOwnerId =
  | 'library' | 'preview' | 'build' | 'progress' | 'result' | 'recovery-error'
  | 'setup-custom' | 'custom-list' | 'custom-edit' | 'custom-delete-confirm';

export const STAGED_SETUP_FLOW_ACTIONS = [
  'librarySelectAll', 'libraryClearAll', 'libraryRetry', 'libraryNext',
  'previewToggle', 'previewRetry', 'previewNext', 'selectBuildCategory',
  'toggleReplaceConfirm', 'buildConfirm', 'buildBack', 'progressCancel',
  'resultDone', 'resultWatch', 'recoveryRetry', 'setupBack', 'openSetupCustom',
  'customNew', 'customCancel', 'customDeleteCancel', 'customDone', 'customBack',
] as const;

export type StagedSetupFlowActionId = (typeof STAGED_SETUP_FLOW_ACTIONS)[number];

export interface SetupRecoveryState {
  originStep: 'library' | 'build';
  operation: 'listLibraries' | 'refreshStatus';
  invokerFocusId: string;
}

export interface StagedSetupState {
  owner: StagedSetupOwnerId;
  buildMode: ChannelSetupCommitMode;
  replacementConfirmed: boolean;
  previewExpanded: boolean;
  selectedSectionIds: readonly string[];
  selectionLimitReached: boolean;
  focusIntent: string | null;
  returnRoute: Exclude<AppRouteId, 'channelSetup'>;
  returnFocusId: string;
  enteredFromServer: boolean;
  editorInvokerFocusId: string | null;
  deleteInvokerFocusId: string | null;
  deleteChannelId: string | null;
  resultWatchChannelId: string | null;
  safeError: string | null;
  recovery: SetupRecoveryState | null;
  customParentOwner: 'setup-custom' | 'custom-list';
  commitGeneration: number;
}

export interface StagedSetupController {
  getState(): StagedSetupState;
  enter(returnRoute: Exclude<AppRouteId, 'channelSetup'>, returnFocusId: string, enteredFromServer?: boolean): void;
  showOwner(owner: StagedSetupOwnerId, focusIntent: string): void;
  setBuildMode(mode: ChannelSetupCommitMode): void;
  normalizeSelection(sections: readonly PlexLibrarySectionSummary[]): string;
  toggleLibrary(sectionId: string, sections: readonly PlexLibrarySectionSummary[]): void;
  selectAllLibraries(sections: readonly PlexLibrarySectionSummary[], cursor: string | null): string | null;
  clearLibraries(sections: readonly PlexLibrarySectionSummary[]): void;
  togglePreview(): void;
  toggleReplacementConfirmation(): void;
  beginCommit(): number;
  cancelCommitView(): void;
  completeCommit(generation: number, mode: ChannelSetupCommitMode, before: ChannelSetupSummary | null, after: ChannelSetupSummary | null): boolean;
  failCommit(generation: number, message: string): boolean;
  openCustomEditor(invokerFocusId: string): void;
  closeCustomEditor(savedChannelId?: string | null): void;
  openDeleteConfirmation(channelId: string, invokerFocusId: string): void;
  closeDeleteConfirmation(restoreFocusId?: string): void;
  showRecovery(message: string, recovery: SetupRecoveryState): void;
  invalidateAsync(options?: { keepOwner?: boolean; keepSelection?: boolean }): void;
  applyFocusIntent(registry: FocusRegistry, focusState: FocusState): FocusState;
}

interface DispatchInput {
  action: StagedSetupFlowActionId;
  controller: StagedSetupController;
  runtime: SetupRuntimeCoordinator;
  channelController: ChannelRuntimeController;
  sections: readonly PlexLibrarySectionSummary[];
  getSections?(): readonly PlexLibrarySectionSummary[];
  getCurrentPlexError?(): string | null;
  previewCursor: string | null;
  getPreviewRatingKey?(): string | null;
  sectionsServerId?(): string | null;
  setPreviewCursor(sectionId: string): void;
  closePreviewMetadata(): void;
  returnToServer(): void;
  closeSetup(): void;
  tuneChannel(channelId: string): Promise<boolean>;
  startBlankCustomDraft(): void;
  cancelCustomDraft(): void;
  cancelCustomDeleteConfirmation(): void;
}

export async function dispatchStagedSetupAction(input: DispatchInput): Promise<void> {
  const state = input.controller.getState();
  switch (input.action) {
    case 'librarySelectAll': {
      const cursor = input.controller.selectAllLibraries(input.sections, input.previewCursor);
      if (cursor !== null && cursor !== input.previewCursor) input.setPreviewCursor(cursor);
      return;
    }
    case 'libraryClearAll': input.controller.clearLibraries(input.sections); return;
    case 'libraryRetry':
      await input.runtime.retryLibraries(input.sectionsServerId?.() ?? null);
      if (input.controller.getState() !== state) return;
      if (input.runtime.getState().library === 'error') {
        input.controller.showRecovery(input.getCurrentPlexError?.() ?? 'Libraries could not be loaded.', libraryRecovery());
      } else {
        const focus = input.controller.normalizeSelection(input.getSections?.() ?? input.sections);
        input.controller.showOwner('library', input.runtime.getState().library === 'empty' ? 'setup-library-retry' : focus);
      }
      return;
    case 'libraryNext':
      if (state.selectedSectionIds.length > 0) input.controller.showOwner('preview', 'setup-category-build');
      return;
    case 'selectBuildCategory': input.controller.showOwner('preview', modeFocus(state.buildMode)); return;
    case 'previewToggle':
      input.controller.togglePreview();
      if (state.previewExpanded) { input.runtime.collapsePreview(); input.closePreviewMetadata(); }
      else if (input.previewCursor !== null) {
        const preview = input.runtime.getState();
        if (preview.previewSectionId !== input.previewCursor || (preview.preview !== 'ready' && preview.preview !== 'empty')) {
          await input.runtime.loadPreview(input.previewCursor);
        }
        const ratingKey = input.getPreviewRatingKey?.() ?? null;
        if (input.runtime.getState().preview === 'ready' && ratingKey !== null) {
          await input.runtime.loadPreviewMetadata(ratingKey);
        }
      }
      return;
    case 'previewRetry': await input.runtime.retryPreview(); return;
    case 'previewNext': input.controller.showOwner('build', state.buildMode === 'replace' ? 'setup-replace-confirm' : 'setup-confirm'); return;
    case 'buildBack': input.controller.showOwner('preview', modeFocus(state.buildMode)); return;
    case 'toggleReplaceConfirm': input.controller.toggleReplacementConfirmation(); return;
    case 'buildConfirm':
      if (input.channelController.getState().pending || state.selectedSectionIds.length === 0) return;
      if (state.buildMode === 'replace' && !state.replacementConfirmed) return;
      await commitCurrentSetup(input);
      return;
    case 'progressCancel': input.controller.cancelCommitView(); input.channelController.clearActionState(); return;
    case 'resultDone': case 'customDone': input.closeSetup(); return;
    case 'resultWatch': {
      if (state.resultWatchChannelId === null) { input.controller.showOwner('result', 'setup-result-watch'); return; }
      const tuned = await input.tuneChannel(state.resultWatchChannelId);
      if (input.controller.getState() !== state) return;
      if (tuned) input.closeSetup();
      else input.controller.showOwner('result', 'setup-result-watch');
      return;
    }
    case 'recoveryRetry':
      if (state.recovery?.originStep === 'library') {
        await input.runtime.retryLibraries(input.sectionsServerId?.() ?? null);
        if (input.controller.getState() !== state) return;
        if (input.runtime.getState().library === 'error') input.controller.showRecovery(input.getCurrentPlexError?.() ?? 'Libraries could not be loaded.', state.recovery);
        else {
          const focus = input.controller.normalizeSelection(input.getSections?.() ?? input.sections);
          input.controller.showOwner('library', input.runtime.getState().library === 'empty' ? 'setup-library-retry' : focus);
        }
      }
      else {
        await input.channelController.loadStatus();
        if (input.controller.getState() !== state) return;
        if (input.channelController.getState().errorText === null) input.controller.showOwner('build', state.buildMode === 'replace' ? 'setup-replace-confirm' : 'setup-confirm');
        else input.controller.showRecovery(input.channelController.getState().errorText ?? 'Channel setup could not continue.', state.recovery ?? buildRecovery());
      }
      return;
    case 'setupBack': handleSetupBack(input, state); return;
    case 'openSetupCustom': input.controller.showOwner('setup-custom', 'custom-channel-new'); return;
    case 'customNew': input.startBlankCustomDraft(); input.controller.openCustomEditor('custom-channel-new'); return;
    case 'customCancel': input.cancelCustomDraft(); input.controller.closeCustomEditor(); return;
    case 'customDeleteCancel': input.cancelCustomDeleteConfirmation(); input.controller.closeDeleteConfirmation(); return;
    case 'customBack': input.controller.showOwner('preview', 'channel-strategy-build-custom'); return;
  }
}

export function createStagedSetupActionDispatcher(input: {
  controller: StagedSetupController;
  runtime: SetupRuntimeCoordinator;
  channelController: ChannelRuntimeController;
  plexController: PlexRuntimeController;
  customController: CustomChannelController;
  returnToServer(): void;
  closeSetup(): void;
  tuneChannel(channelId: string): Promise<boolean>;
}): (action: StagedSetupFlowActionId) => Promise<void> {
  return async (action) => {
    const plex = input.plexController.getState();
    await dispatchStagedSetupAction({
      action, controller: input.controller, runtime: input.runtime, channelController: input.channelController,
      sections: plex.snapshot?.library.sections ?? [], previewCursor: plex.selectedSectionId,
      getSections: () => input.plexController.getState().snapshot?.library.sections ?? [],
      getCurrentPlexError: () => input.plexController.getState().errorText,
      getPreviewRatingKey: () => {
        const current = input.plexController.getState();
        const sectionId = input.runtime.getState().previewSectionId;
        if (sectionId === null || current.selectedSectionId !== sectionId || current.snapshot?.library.selectedSectionId !== sectionId) return null;
        return current.snapshot.library.items[0]?.ratingKey ?? null;
      },
      setPreviewCursor: (id) => input.plexController.setSelectedSection(id),
      closePreviewMetadata: () => input.plexController.clearMetadata(),
      returnToServer: input.returnToServer, closeSetup: input.closeSetup, tuneChannel: input.tuneChannel,
      startBlankCustomDraft: () => input.customController.startBlankDraft(),
      cancelCustomDraft: () => input.customController.cancelDraft(),
      cancelCustomDeleteConfirmation: () => input.customController.cancelDeleteConfirmation(),
      sectionsServerId: () => input.plexController.getState().selectedServerId,
    });
  };
}

export async function handleStagedSetupBack(input: {
  controller: StagedSetupController; customController: CustomChannelController;
  plexController: PlexRuntimeController; dispatch(action: StagedSetupFlowActionId): Promise<void>;
}): Promise<boolean> {
  const state = input.controller.getState();
  if (state.owner === 'custom-delete-confirm') { await input.dispatch('customDeleteCancel'); return true; }
  if (state.owner === 'progress') return true;
  if (state.owner === 'custom-edit') {
    if (input.customController.handleBack()) return true;
    await input.dispatch('customCancel'); return true;
  }
  if (state.owner === 'preview' && state.previewExpanded) {
    input.plexController.clearMetadata(); await input.dispatch('previewToggle'); return true;
  }
  await input.dispatch(state.owner === 'result' ? 'resultDone' : 'setupBack');
  return true;
}

export function createStagedSetupController(input: { onStateChanged(): void }): StagedSetupController {
  let state = createInitialState();
  const set = (patch: Partial<StagedSetupState>): void => { state = { ...state, ...patch }; input.onStateChanged(); };
  return {
    getState: () => state,
    enter(returnRoute, returnFocusId, enteredFromServer = true) {
      state = { ...createInitialState(), commitGeneration: state.commitGeneration + 1, returnRoute, returnFocusId, enteredFromServer };
      input.onStateChanged();
    },
    showOwner(owner, focusIntent) { set({ owner, focusIntent, safeError: null }); },
    setBuildMode(buildMode) { set({ buildMode, replacementConfirmed: false, focusIntent: modeFocus(buildMode) }); },
    normalizeSelection(sections) {
      const selectedSectionIds = normalizeSetupLibrarySelection(state.selectedSectionIds, sections);
      const firstEligibleId = sections.find((section) => section.type === 'movie' || section.type === 'show')?.id;
      const focusSectionId = selectedSectionIds[0] ?? firstEligibleId;
      const focusIntent = focusSectionId === undefined ? 'setup-select-all' : sectionFocus(focusSectionId);
      set({ selectedSectionIds, selectionLimitReached: false, focusIntent });
      return focusIntent;
    },
    toggleLibrary(sectionId, sections) {
      const result = toggleSetupLibrarySelection(state.selectedSectionIds, sectionId, sections);
      set({ selectedSectionIds: result.selectedSectionIds, selectionLimitReached: result.limitReached, focusIntent: sectionFocus(sectionId) });
    },
    selectAllLibraries(sections, cursor) {
      const result = selectAllSetupLibraries(sections);
      set({ selectedSectionIds: result.selectedSectionIds, selectionLimitReached: result.limitReached, focusIntent: result.selectedSectionIds[0] === undefined ? 'setup-select-all' : sectionFocus(result.selectedSectionIds[0]) });
      return resolveSetupPreviewCursor(result.selectedSectionIds, cursor);
    },
    clearLibraries(sections) {
      const result = clearSetupLibrarySelection();
      const firstEligibleId = sections.find((section) => section.type === 'movie' || section.type === 'show')?.id;
      set({ selectedSectionIds: result.selectedSectionIds, selectionLimitReached: result.limitReached, focusIntent: firstEligibleId === undefined ? 'setup-select-all' : sectionFocus(firstEligibleId) });
    },
    togglePreview() { set({ previewExpanded: !state.previewExpanded, focusIntent: 'setup-preview-toggle' }); },
    toggleReplacementConfirmation() { set({ replacementConfirmed: !state.replacementConfirmed, focusIntent: 'setup-replace-confirm' }); },
    beginCommit() { const commitGeneration = state.commitGeneration + 1; set({ owner: 'progress', commitGeneration, focusIntent: 'setup-progress-cancel', safeError: null }); return commitGeneration; },
    cancelCommitView() { set({ owner: 'build', commitGeneration: state.commitGeneration + 1, focusIntent: 'setup-confirm', safeError: null }); },
    completeCommit(generation, mode, before, after) {
      if (generation !== state.commitGeneration || state.owner !== 'progress') return false;
      set({ owner: 'result', focusIntent: 'setup-done', resultWatchChannelId: chooseWatchChannelId(mode, before, after), replacementConfirmed: false }); return true;
    },
    failCommit(generation, message) {
      if (generation !== state.commitGeneration || state.owner !== 'progress') return false;
      set({ owner: 'recovery-error', focusIntent: 'setup-error-retry', safeError: safeRendererText(message), recovery: buildRecovery() }); return true;
    },
    openCustomEditor(invokerFocusId) { set({ owner: 'custom-edit', customParentOwner: state.owner === 'setup-custom' ? 'setup-custom' : 'custom-list', editorInvokerFocusId: invokerFocusId, focusIntent: 'custom-channel-name' }); },
    closeCustomEditor(savedChannelId = null) { set({ owner: state.customParentOwner, editorInvokerFocusId: null, focusIntent: savedChannelId === null ? state.editorInvokerFocusId ?? 'custom-channel-new' : `custom-channel-duplicate-${savedChannelId}` }); },
    openDeleteConfirmation(channelId, invokerFocusId) { set({ owner: 'custom-delete-confirm', customParentOwner: state.owner === 'setup-custom' ? 'setup-custom' : 'custom-list', deleteChannelId: channelId, deleteInvokerFocusId: invokerFocusId, focusIntent: 'custom-delete-cancel' }); },
    closeDeleteConfirmation(restoreFocusId) { set({ owner: state.customParentOwner, deleteChannelId: null, deleteInvokerFocusId: null, focusIntent: restoreFocusId ?? state.deleteInvokerFocusId ?? 'custom-channel-new' }); },
    showRecovery(message, recovery) { set({ owner: 'recovery-error', safeError: safeRendererText(message), recovery, focusIntent: 'setup-error-retry' }); },
    invalidateAsync(options = {}) { set({ ...(options.keepOwner ? {} : { owner: 'library' as const }), ...(options.keepSelection ? {} : { selectedSectionIds: [] }), commitGeneration: state.commitGeneration + 1, replacementConfirmed: false, resultWatchChannelId: null, safeError: null, focusIntent: options.keepOwner ? state.focusIntent : 'setup-select-all' }); },
    applyFocusIntent(registry, focusState) {
      if (state.focusIntent === null) return focusState;
      const next = registry.focusTarget(focusState, state.focusIntent).state;
      if (next.activeId === state.focusIntent) state = { ...state, focusIntent: null };
      return next;
    },
  };
}

async function commitCurrentSetup(input: DispatchInput): Promise<void> {
  const state = input.controller.getState();
  const before = input.channelController.getState().summary;
  const generation = input.controller.beginCommit();
  const outcome = await input.channelController.commit({ mode: state.buildMode, sectionIds: [...state.selectedSectionIds], ...(state.buildMode === 'replace' ? { confirmReplace: true } : {}) });
  if (outcome === 'skipped' || outcome === 'stale') return;
  const runtime = input.channelController.getState();
  if (outcome === 'failed' || runtime.errorText !== null) input.controller.failCommit(generation, runtime.errorText ?? 'Channel setup could not continue. Try again.');
  else input.controller.completeCommit(generation, state.buildMode, before, runtime.summary);
}

function handleSetupBack(input: DispatchInput, state: StagedSetupState): void {
  if (state.owner === 'library') { if (state.enteredFromServer) input.returnToServer(); else input.closeSetup(); return; }
  if (state.owner === 'preview') { input.controller.showOwner('library', state.selectedSectionIds[0] ? sectionFocus(state.selectedSectionIds[0]) : 'setup-select-all'); return; }
  if (state.owner === 'build') { input.controller.showOwner('preview', modeFocus(state.buildMode)); return; }
  if (state.owner === 'recovery-error') { if (state.recovery?.originStep === 'library') { if (state.enteredFromServer) input.returnToServer(); else input.closeSetup(); } else input.controller.showOwner('preview', modeFocus(state.buildMode)); return; }
  if (state.owner === 'setup-custom' || state.owner === 'custom-list') { input.controller.showOwner('preview', 'channel-strategy-build-custom'); return; }
  if (state.owner === 'result') input.closeSetup();
}

function createInitialState(): StagedSetupState {
  return { owner: 'library', buildMode: 'append', replacementConfirmed: false, previewExpanded: false, selectedSectionIds: [], selectionLimitReached: false, focusIntent: 'setup-select-all', returnRoute: 'player', returnFocusId: 'player-settings', enteredFromServer: true, editorInvokerFocusId: null, deleteInvokerFocusId: null, deleteChannelId: null, resultWatchChannelId: null, safeError: null, recovery: null, customParentOwner: 'setup-custom', commitGeneration: 0 };
}

function buildRecovery(): SetupRecoveryState { return { originStep: 'build', operation: 'refreshStatus', invokerFocusId: 'setup-confirm' }; }
function libraryRecovery(): SetupRecoveryState { return { originStep: 'library', operation: 'listLibraries', invokerFocusId: 'setup-library-retry' }; }
function modeFocus(mode: ChannelSetupCommitMode): string { return `channel-strategy-build-${mode}`; }
function sectionFocus(id: string): string { return `plex-dyn-section-${id}`; }
function chooseWatchChannelId(mode: ChannelSetupCommitMode, before: ChannelSetupSummary | null, after: ChannelSetupSummary | null): string | null {
  const beforeIds = new Set(before?.channels.map((channel) => channel.id) ?? []);
  return (after?.channels ?? []).filter((channel) => mode === 'replace' || !beforeIds.has(channel.id)).slice().sort((a, b) => a.number - b.number || a.id.localeCompare(b.id))[0]?.id ?? null;
}
function safeRendererText(message: string): string {
  const normalized = Array.from(message, (c) => ((c.codePointAt(0) ?? 0) < 32 ? ' ' : c)).join('').replace(/\s+/gu, ' ').trim();
  return normalized.length === 0 || /https?:|file:|token|credential|header|\/Users\/|[A-Za-z]:\\/iu.test(normalized) ? 'Channel setup could not continue. Try again.' : normalized.slice(0, 180);
}
