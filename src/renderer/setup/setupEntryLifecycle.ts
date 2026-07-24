import type { PlexRuntimeSnapshot } from '../../contracts/plex.js';
import type { PlexRuntimeRendererState } from '../plexRuntimeState.js';
import type { AppRouteId } from '../navigation.js';
import type { StagedSetupController } from './stagedSetupController.js';
import type { SetupRuntimeCoordinator } from './setupRuntimeCoordinator.js';

export interface SetupEntryRequest {
  originRoute: Exclude<AppRouteId, 'channelSetup'>;
  returnFocusId: string;
  enteredFromServer: boolean;
}

export interface SetupEntryLifecycle {
  enter(request: SetupEntryRequest): Promise<void>;
  invalidate(): void;
}

export type SetupEntryTarget = 'account' | 'profile' | 'server' | 'library';
export type SetupOnboardingOwner = 'auth-link-code' | 'auth-waiting' | 'auth-error' | 'profile-select' | 'profile-pin' | 'server-select' | 'server-error';
export type SetupOnboardingBackAction = 'close' | 'contain' | 'profile' | 'auth-link' | 'delegate';

export function resolveSetupOnboardingBackAction(
  owner: SetupOnboardingOwner,
  enteredFromServer: boolean,
): SetupOnboardingBackAction {
  if (owner === 'server-select' || owner === 'server-error') return 'profile';
  if (owner === 'auth-waiting' || owner === 'auth-error') return 'auth-link';
  if (owner === 'auth-link-code' || owner === 'profile-select') {
    return enteredFromServer ? 'contain' : 'close';
  }
  return 'delegate';
}

export async function applySetupOnboardingBack(input: {
  owner: SetupOnboardingOwner;
  enteredFromServer: boolean;
  close(): void;
  contain(): void;
  returnToProfile(): void;
  returnToAuthLink(): Promise<void>;
}): Promise<boolean> {
  switch (resolveSetupOnboardingBackAction(input.owner, input.enteredFromServer)) {
    case 'close': input.close(); return true;
    case 'contain': input.contain(); return true;
    case 'profile': input.returnToProfile(); return true;
    case 'auth-link': await input.returnToAuthLink(); return true;
    case 'delegate': return false;
  }
}

export function hasPlexAuthenticationFailure(snapshot: PlexRuntimeSnapshot | null): boolean {
  switch (snapshot?.lastError?.code) {
    case 'PLEX_AUTH_REQUIRED':
    case 'PLEX_AUTH_INVALID':
    case 'PLEX_UNAUTHORIZED':
    case 'PLEX_PIN_EXPIRED':
    case 'PLEX_PIN_TIMEOUT':
      return true;
    default:
      return false;
  }
}

export function resolveSetupEntryTarget(snapshot: PlexRuntimeSnapshot | null): SetupEntryTarget {
  if (snapshot?.auth.state !== 'signed-in' || hasPlexAuthenticationFailure(snapshot)) return 'account';
  if (snapshot.auth.profile === null) return 'profile';
  if (snapshot.servers.selected === null) return 'server';
  return 'library';
}

export function getSetupEntryReturnFocusId(
  route: Exclude<AppRouteId, 'channelSetup'>,
  candidateFocusId: string | null = null,
): string {
  let expectedFocusId: string;
  switch (route) {
    case 'guide': expectedFocusId = 'guide-state-setup'; break;
    case 'settings': expectedFocusId = 'settings-open-channel-setup'; break;
    case 'player': expectedFocusId = 'player-setup-reminder'; break;
  }
  return candidateFocusId === expectedFocusId ? candidateFocusId : expectedFocusId;
}

export function restoreSetupEntryDestination(input: {
  returnRoute: Exclude<AppRouteId, 'channelSetup'>;
  returnFocusId: string;
  beforeActivate?(): void;
  activateRoute(route: Exclude<AppRouteId, 'channelSetup'>): void;
  restoreFocus(focusId: string): void;
}): void {
  input.beforeActivate?.();
  input.activateRoute(input.returnRoute);
  input.restoreFocus(input.returnFocusId);
}

export function createSetupEntryLifecycle(input: {
  controller: Pick<StagedSetupController, 'enter' | 'showOwner' | 'normalizeSelection' | 'showRecovery'>;
  runtime: Pick<SetupRuntimeCoordinator, 'getState' | 'enterLibrary' | 'invalidate'>;
  getPlexState(): PlexRuntimeRendererState;
  setSetupStage(stage: SetupEntryTarget): void;
  activateSetupRoute(): void;
  loadProfiles(): void;
  enterServerSelection(): void;
}): SetupEntryLifecycle {
  let generation = 0;

  return {
    async enter(request) {
      const currentGeneration = ++generation;
      input.controller.enter(request.originRoute, request.returnFocusId, request.enteredFromServer);
      input.runtime.invalidate();

      const initialPlexState = input.getPlexState();
      const target = resolveSetupEntryTarget(initialPlexState.snapshot);
      input.setSetupStage(target);
      if (target !== 'library') {
        input.activateSetupRoute();
        if (target === 'profile') input.loadProfiles();
        else if (target === 'server') input.enterServerSelection();
        return;
      }

      input.controller.showOwner('library', 'setup-back');
      const serverId = initialPlexState.selectedServerId
        ?? initialPlexState.snapshot?.servers.selected?.serverId
        ?? null;
      const libraryLoad = input.runtime.enterLibrary(serverId, initialPlexState);
      input.activateSetupRoute();

      await libraryLoad;
      if (currentGeneration !== generation) return;

      const plexState = input.getPlexState();
      if (serverId === null || plexState.selectedServerId !== serverId) return;
      if (input.runtime.getState().library === 'error') {
        input.controller.showRecovery(plexState.errorText ?? 'Libraries could not be loaded.', {
          originStep: 'library',
          operation: 'listLibraries',
          invokerFocusId: 'setup-library-retry',
        });
        return;
      }

      const focusId = input.controller.normalizeSelection(plexState.snapshot?.library.sections ?? []);
      input.controller.showOwner(
        'library',
        input.runtime.getState().library === 'empty' ? 'setup-library-retry' : focusId,
      );
    },
    invalidate() {
      ++generation;
    },
  };
}
