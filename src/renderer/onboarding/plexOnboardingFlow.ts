import type { PlexRuntimeController } from '../plexRuntimeActions.js';
import type { PlexRuntimeRendererState } from '../plexRuntimeState.js';
import type { AppRouteId, FocusRegistry, FocusState } from '../navigation.js';
import type { ChannelSetupSummary } from '../../contracts/channel.js';

export type InitialChannelSetupStage = 'account' | 'server' | 'library';

export function resolveChannelSetupEntryStage(
  plexState: PlexRuntimeRendererState,
): InitialChannelSetupStage {
  if (plexState.snapshot?.auth.state !== 'signed-in') return 'account';
  if (plexState.snapshot.auth.profile === null) return 'account';
  return plexState.selectedServerId === null ? 'server' : 'library';
}

export function resolveInitialChannelSetupStage(
  plexState: PlexRuntimeRendererState,
  channelSummary: ChannelSetupSummary | null,
): InitialChannelSetupStage | null {
  if (
    channelSummary === null ||
    channelSummary.status !== 'not-configured' ||
    channelSummary.channelCount !== 0
  ) return null;
  return resolveChannelSetupEntryStage(plexState);
}

export interface PlexOnboardingFlow {
  rememberProfileFocus(focusId: string | null): void;
  setFocusIntent(focusId: string | null): void;
  applyFocusIntent(registry: FocusRegistry, state: FocusState): FocusState;
  advanceToServerSelection(): Promise<void>;
  refreshServerSelection(): Promise<void>;
  selectServer(serverId: string): Promise<void>;
  changeStage(stage: string): Promise<void>;
  returnToProfileSelection(): void;
}

export function createPlexOnboardingFlow({
  controller,
  documentRef,
  getRoute,
  getStage,
  setStage,
  render,
}: {
  controller: PlexRuntimeController;
  documentRef: Document;
  getRoute: () => AppRouteId;
  getStage: () => string;
  setStage: (stage: string) => void;
  render: () => void;
}): PlexOnboardingFlow {
  let focusIntent: string | null = null;
  let profileReturnFocusId: string | null = null;
  const isCurrentStage = (stage: string): boolean => getRoute() === 'channelSetup' && getStage() === stage;

  const refreshServerSelection = async (): Promise<void> => {
    await controller.refreshServers();
    if (!isCurrentStage('server')) return;
    const firstServer = documentRef.querySelector<HTMLButtonElement>('[data-plex-server-id]:not([disabled])');
    focusIntent = firstServer?.dataset.focusId ?? 'btn-server-refresh';
    render();
  };

  const advanceToServerSelection = async (): Promise<void> => {
    controller.invalidateOnboardingOperations();
    setStage('server');
    focusIntent = 'btn-server-refresh';
    render();
    await controller.restoreSelectedServer();
    if (!isCurrentStage('server')) return;
    await refreshServerSelection();
  };

  return {
    rememberProfileFocus(focusId): void {
      if (focusId?.startsWith('btn-profile-') === true) profileReturnFocusId = focusId;
    },
    setFocusIntent(focusId): void {
      focusIntent = focusId;
    },
    applyFocusIntent(registry, state): FocusState {
      if (focusIntent === null) return state;
      const focused = registry.focusTarget(state, focusIntent).state;
      if (focused.activeId === focusIntent) focusIntent = null;
      return focused;
    },
    advanceToServerSelection,
    refreshServerSelection,
    async selectServer(serverId): Promise<void> {
      await controller.selectServer(serverId);
      const state = controller.getState();
      if (isCurrentStage('server') && !state.pending.selectServer && state.errorText === null && state.selectedServerId === serverId) {
        focusIntent = 'btn-server-setup';
        render();
      }
    },
    async changeStage(stage): Promise<void> {
      if (stage === 'server') {
        await advanceToServerSelection();
        return;
      }
      controller.invalidateOnboardingOperations(stage === 'profile');
      setStage(stage);
      if (stage === 'profile') focusIntent = profileReturnFocusId;
      render();
    },
    returnToProfileSelection(): void {
      controller.invalidateOnboardingOperations(true);
      setStage('profile');
      focusIntent = profileReturnFocusId;
      render();
    },
  };
}
