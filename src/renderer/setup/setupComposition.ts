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
import { createSetupEntryLifecycle } from './setupEntryLifecycle.js';
import { createChannelBuilderController, type ChannelBuilderAction } from './channelBuilderController.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';

export function createSetupComposition(input: {
  plexController: PlexRuntimeController;
  channelController: ChannelRuntimeController;
  channelSetupBridge: LineupDesktopPreloadApi['channelSetup'];
  customController: CustomChannelController;
  render(): void;
  returnToServer(): void;
  closeSetup(): void;
  tuneChannel(channelId: string): Promise<boolean>;
  clearDependentActionState(): void;
  setSetupStage(stage: 'account' | 'profile' | 'server' | 'library'): void;
  activateSetupRoute(): void;
  loadProfiles(): void;
  enterServerSelection(): void;
}) {
  const controller = createStagedSetupController({ onStateChanged: input.render });
  const builder = createChannelBuilderController({ bridge: input.channelSetupBridge, onStateChanged: input.render });
  const runtime = createSetupRuntimeCoordinator({
    getPlexState: input.plexController.getState,
    listLibrarySections: input.plexController.listLibrarySections,
    listLibraryItems: input.plexController.listLibraryItems,
    getMetadata: input.plexController.getMetadata,
    onStateChanged: input.render,
  });
  const entry = createSetupEntryLifecycle({
    controller,
    runtime,
    getPlexState: input.plexController.getState,
    setSetupStage: input.setSetupStage,
    activateSetupRoute: input.activateSetupRoute,
    loadProfiles: input.loadProfiles,
    enterServerSelection: input.enterServerSelection,
  });
  const invalidate = (keepOwner = false): void => {
    entry.invalidate();
    runtime.invalidate();
    builder.invalidate();
    controller.invalidateAsync({ keepOwner });
  };
  const dispatch = createStagedSetupActionDispatcher({
    controller,
    runtime,
    channelController: input.channelController,
    builder,
    plexController: input.plexController,
    customController: input.customController,
    returnToServer: () => {
      invalidate();
      input.returnToServer();
    },
    closeSetup: input.closeSetup,
    tuneChannel: input.tuneChannel,
  });
  return {
    controller,
    builder,
    runtime,
    dispatch,
    enter(returnRoute: Exclude<AppRouteId, 'channelSetup'>, returnFocusId: string, enteredFromServer = true) {
      void builder.initialize();
      return entry.enter({ originRoute: returnRoute, returnFocusId, enteredFromServer });
    },
    async selectSection(sectionId: string) {
      const sections = input.plexController.getState().snapshot?.library.sections ?? [];
      controller.toggleLibrary(sectionId, sections);
      input.clearDependentActionState();
      input.plexController.setSelectedSection(sectionId);
      await runtime.loadPreview(sectionId);
    },
    setBuildMode(mode: 'append' | 'replace') { controller.setBuildMode(mode); },
    applyBuilder(action: ChannelBuilderAction, detail?: string) {
      builder.apply(action, detail);
      const focusIntent = builder.getState().focusIntent; const owner = controller.getState().owner;
      if (focusIntent !== null && (owner === 'preview' || owner === 'build')) controller.showOwner(owner, focusIntent);
    },
    handleBuilderDirection(direction: 'up' | 'down' | 'left' | 'right') { return direction === 'up' || direction === 'down' ? builder.handlePriorityDirection(direction) : false; },
    dismissBuilderTransient() { return builder.dismissTransient(); },
    apply(action: StagedSetupFlowActionId) { return dispatch(action); },
    invalidate,
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
