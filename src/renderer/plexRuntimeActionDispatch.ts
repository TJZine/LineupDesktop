import type { PlexRuntimeActionId } from './domBindings.js';
import type { PlexRuntimeController } from './plexRuntimeActions.js';

export interface PlexRuntimeActionDispatchOptions {
  controller: PlexRuntimeController;
  clearSourceActionState(): void;
}

export async function dispatchPlexRuntimeAction(
  action: PlexRuntimeActionId,
  options: PlexRuntimeActionDispatchOptions,
): Promise<void> {
  const { controller } = options;
  switch (action) {
    case 'loadSnapshot':
      await controller.loadSnapshot();
      return;
    case 'requestPin':
      await controller.requestPin();
      return;
    case 'pollPin':
      await controller.pollPin();
      return;
    case 'cancelPin':
      await controller.cancelPin();
      return;
    case 'dismissPinError':
      controller.dismissPinError();
      return;
    case 'getHomeUsers':
      await controller.getHomeUsers();
      return;
    case 'restoreSelectedServer':
      options.clearSourceActionState();
      await controller.restoreSelectedServer();
      return;
    case 'refreshServers':
      await controller.refreshServers();
      return;
    case 'listLibrarySections':
      await controller.listLibrarySections();
      return;
    case 'listLibraryItems':
      await controller.listLibraryItems();
      return;
    case 'searchLibrary':
      await controller.searchLibrary();
      return;
    case 'clearMetadata':
      controller.clearMetadata();
      return;
    case 'clearSearch':
      controller.clearSearch();
      return;
    case 'clearItems':
      controller.clearItems();
      return;
    case 'clearSelectedSection':
      options.clearSourceActionState();
      controller.clearSelectedSection();
      return;
    case 'clearSelectedServer':
      options.clearSourceActionState();
      controller.clearSelectedServer();
      return;
    case 'clearPinSubflow':
      options.clearSourceActionState();
      await controller.clearPinSubflow();
      return;
  }
}
