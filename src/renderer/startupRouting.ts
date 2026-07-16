import type { PlexRuntimeSnapshot } from '../contracts/plex.js';
import type { AppRouteId } from './navigation.js';
import type { ChannelRuntimeRendererState } from './channelRuntimeState.js';
import type { SettingsSectionId } from './settingsSetup.js';

export type RendererStartupTarget =
  | { route: 'player' }
  | { route: 'settings'; category: 'recovery' }
  | { route: 'channelSetup'; stage: 'account' | 'profile' | 'server' | 'library' };

export type ChannelStartupClassification = 'confirmed-empty' | 'configured' | 'recovery';

export function classifyChannelStartupState(state: ChannelRuntimeRendererState): ChannelStartupClassification {
  if (isConfirmedEmptyChannelState(state)) return 'confirmed-empty';
  if (hasUsablePersistedChannels(state)) return 'configured';
  return 'recovery';
}

export function isConfirmedEmptyChannelState(state: ChannelRuntimeRendererState): boolean {
  const summary = state.summary;
  return !state.pending && state.errorText === null && summary?.status === 'not-configured'
    && summary.channelCount === 0 && summary.channels.length === 0 && summary.channelNumbers.length === 0
    && summary.currentChannelId === null && summary.currentChannelNumber === null && summary.currentChannelName === null;
}

export function resolveRendererStartupTarget(
  plexSnapshot: PlexRuntimeSnapshot | null,
  channelState: ChannelRuntimeRendererState,
): RendererStartupTarget {
  if (plexSnapshot?.auth.state !== 'signed-in' || hasAuthenticationFailure(plexSnapshot)) {
    return { route: 'channelSetup', stage: 'account' };
  }
  if (plexSnapshot.auth.profile === null) return { route: 'channelSetup', stage: 'profile' };
  if (plexSnapshot.servers.selected === null) return { route: 'channelSetup', stage: 'server' };
  const channelClassification = classifyChannelStartupState(channelState);
  if (channelClassification === 'confirmed-empty') return { route: 'channelSetup', stage: 'library' };
  if (channelClassification === 'configured') return { route: 'player' };
  return { route: 'settings', category: 'recovery' };
}

export function createRendererRoutingCoordinator(input: {
  getPlexSnapshot(): PlexRuntimeSnapshot | null;
  getChannelState(): ChannelRuntimeRendererState;
  activateRoute(route: AppRouteId): void;
  showPlayer(): void;
  setSetupStage(stage: 'account' | 'profile' | 'server' | 'library'): void;
  setSettingsCategory(category: SettingsSectionId): void;
  loadProfiles(): void;
  enterServerSelection(): void;
  enterLibrary(returnRoute: 'player', returnFocusId: string, enteredFromServer: boolean): Promise<void>;
}) {
  const routeTo = async (target: RendererStartupTarget, enteredFromServer: boolean): Promise<void> => {
    if (target.route === 'player') { input.showPlayer(); return; }
    if (target.route === 'settings') {
      input.setSettingsCategory(target.category);
      input.activateRoute('settings');
      return;
    }

    input.setSetupStage(target.stage);
    input.activateRoute('channelSetup');
    if (target.stage === 'server') input.enterServerSelection();
    else if (target.stage === 'library') {
      await input.enterLibrary('player', 'player-setup-reminder', enteredFromServer);
    }
  };

  return {
    async routeStartup(): Promise<void> {
      const target = resolveRendererStartupTarget(input.getPlexSnapshot(), input.getChannelState());
      const needsProfiles = target.route !== 'channelSetup' || target.stage !== 'account';
      if (input.getPlexSnapshot()?.auth.state === 'signed-in' && needsProfiles) input.loadProfiles();
      await routeTo(target, true);
    },
    async openPlayerSetupReminder(): Promise<boolean> {
      const channelClassification = classifyChannelStartupState(input.getChannelState());
      if (channelClassification === 'recovery') {
        await routeTo({ route: 'settings', category: 'recovery' }, false);
        return true;
      }
      if (channelClassification === 'configured') {
        input.showPlayer();
        return true;
      }
      const target = resolveRendererStartupTarget(input.getPlexSnapshot(), input.getChannelState());
      await routeTo(target, false);
      return true;
    },
  };
}

function hasUsablePersistedChannels(state: ChannelRuntimeRendererState): boolean {
  const summary = state.summary;
  if (state.pending || state.errorText !== null || summary?.status !== 'configured' || !summary.recovery.loaded || summary.channelCount <= 0) return false;
  if (summary.channels.length !== summary.channelCount || summary.channelNumbers.length !== summary.channelCount) return false;
  const current = summary.channels.find((channel) => channel.id === summary.currentChannelId);
  return current !== undefined && current.number === summary.currentChannelNumber
    && current.name === summary.currentChannelName
    && summary.channels.every((channel, index) => channel.number === summary.channelNumbers[index]);
}

function hasAuthenticationFailure(snapshot: PlexRuntimeSnapshot | null): boolean {
  switch (snapshot?.lastError?.code) {
    case 'PLEX_AUTH_REQUIRED': case 'PLEX_AUTH_INVALID': case 'PLEX_UNAUTHORIZED':
    case 'PLEX_PIN_EXPIRED': case 'PLEX_PIN_TIMEOUT': return true;
    default: return false;
  }
}
