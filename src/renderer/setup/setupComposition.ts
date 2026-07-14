import type { AppRouteId } from '../navigation.js';
import type { ChannelRuntimeController } from '../channelRuntimeActions.js';
import type { CustomChannelController } from '../customChannels/controller.js';
import type { PlexRuntimeController } from '../plexRuntimeActions.js';
import {
  createStagedSetupActionDispatcher,
  createStagedSetupController,
  type StagedSetupFlowActionId,
} from './stagedSetupController.js';
import { createSetupRuntimeCoordinator } from './setupRuntimeCoordinator.js';

export function createSetupComposition(input: {
  plexController: PlexRuntimeController;
  channelController: ChannelRuntimeController;
  customController: CustomChannelController;
  render(): void;
  returnToServer(): void;
  closeSetup(): void;
  tuneChannel(channelId: string): Promise<boolean>;
  clearDependentActionState(): void;
}) {
  let entryGeneration = 0;
  const controller = createStagedSetupController({ onStateChanged: input.render });
  const runtime = createSetupRuntimeCoordinator({
    getPlexState: input.plexController.getState,
    listLibrarySections: input.plexController.listLibrarySections,
    listLibraryItems: input.plexController.listLibraryItems,
    getMetadata: input.plexController.getMetadata,
    onStateChanged: input.render,
  });
  const dispatch = createStagedSetupActionDispatcher({
    controller,
    runtime,
    channelController: input.channelController,
    plexController: input.plexController,
    customController: input.customController,
    returnToServer: input.returnToServer,
    closeSetup: input.closeSetup,
    tuneChannel: input.tuneChannel,
  });
  return {
    controller,
    runtime,
    dispatch,
    async enter(returnRoute: Exclude<AppRouteId, 'channelSetup'>, returnFocusId: string, enteredFromServer = true) {
      const currentEntry = ++entryGeneration;
      controller.enter(returnRoute, returnFocusId, enteredFromServer);
      controller.showOwner('library', 'setup-back');
      await runtime.enterLibrary(input.plexController.getState().selectedServerId, input.plexController.getState());
      if (currentEntry !== entryGeneration) return;
      const plex = input.plexController.getState();
      if (runtime.getState().library === 'error') {
        controller.showRecovery(plex.errorText ?? 'Libraries could not be loaded.', {
          originStep: 'library', operation: 'listLibraries', invokerFocusId: 'setup-library-retry',
        });
      } else {
        const focus = controller.normalizeSelection(plex.snapshot?.library.sections ?? []);
        if (runtime.getState().library === 'empty') controller.showOwner('library', 'setup-library-retry');
        else controller.showOwner('library', focus);
      }
    },
    async selectSection(sectionId: string) {
      const sections = input.plexController.getState().snapshot?.library.sections ?? [];
      controller.toggleLibrary(sectionId, sections);
      input.clearDependentActionState();
      input.plexController.setSelectedSection(sectionId);
      await runtime.loadPreview(sectionId);
    },
    setBuildMode(mode: 'append' | 'replace') { controller.setBuildMode(mode); },
    apply(action: StagedSetupFlowActionId) { return dispatch(action); },
    invalidate(keepOwner = false) { ++entryGeneration; runtime.invalidate(); controller.invalidateAsync({ keepOwner }); },
  };
}

type SetupInvalidationOwner = Pick<ReturnType<typeof createSetupComposition>, 'invalidate'>;

export function clearSetupSourceLifecycle(input: {
  composition: SetupInvalidationOwner;
  channelController: Pick<ChannelRuntimeController, 'clearActionState'>;
  customController: Pick<CustomChannelController, 'invalidateOperations' | 'clearMediaForSourceChange'>;
}, keepOwner: boolean): void {
  input.composition.invalidate(keepOwner);
  input.channelController.clearActionState();
  input.customController.invalidateOperations();
  input.customController.clearMediaForSourceChange();
}

export function cleanupSetupRouteLifecycle(input: {
  composition: SetupInvalidationOwner;
  customController: Pick<CustomChannelController, 'invalidateOperations'>;
}): void {
  input.composition.invalidate();
  input.customController.invalidateOperations();
}
