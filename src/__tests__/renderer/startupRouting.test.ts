import test from 'node:test';
import assert from 'node:assert/strict';

import type { ChannelSetupSummary } from '../../contracts/channel.js';
import type { PlexRuntimeSnapshot } from '../../contracts/plex.js';
import type { ChannelRuntimeRendererState } from '../../renderer/channelRuntimeState.js';
import { createStagedSetupController } from '../../renderer/setup/stagedSetupController.js';
import { createRendererRoutingCoordinator, resolveRendererStartupTarget } from '../../renderer/startupRouting.js';

test('startup routing gives authentication state precedence over channel recovery', () => {
  const channels = channelState(configuredSummary());
  for (const snapshot of [
    null,
    plexSnapshot({ authState: 'signed-out' }),
    plexSnapshot({ authState: 'pin-pending' }),
    plexSnapshot({ authFailure: true }),
  ]) {
    assert.deepEqual(resolveRendererStartupTarget(snapshot, channels), {
      route: 'channelSetup', stage: 'account',
    });
  }
});

test('startup routing selects existing profile and server onboarding stages', () => {
  assert.deepEqual(resolveRendererStartupTarget(plexSnapshot({ profile: false }), channelState(configuredSummary())), {
    route: 'channelSetup', stage: 'profile',
  });
  assert.deepEqual(resolveRendererStartupTarget(plexSnapshot({ server: false }), channelState(configuredSummary())), {
    route: 'channelSetup', stage: 'server',
  });
});

test('startup routing distinguishes confirmed empty, configured, and recovery channel states', () => {
  const signedIn = plexSnapshot();
  assert.deepEqual(resolveRendererStartupTarget(signedIn, channelState(emptySummary())), {
    route: 'channelSetup', stage: 'library',
  });
  assert.deepEqual(resolveRendererStartupTarget(signedIn, channelState(configuredSummary())), {
    route: 'player',
  });

  const recoveryStates = [
    channelState(null),
    channelState(channelSummary('recovering', 1, 1)),
    channelState(channelSummary('recovery-failed', 1, 1)),
    channelState(channelSummary('configured', 0, 0)),
    channelState(channelSummary('configured', 1, 0)),
    channelState(channelSummary('not-configured', 1, 1)),
    channelState(null, 'Persisted channels could not be recovered.'),
    channelState(null, 'Persisted channel storage is unavailable.'),
    channelState(null, 'Channel setup status is not authorized.'),
    channelState(null, 'Channel setup status could not be loaded.'),
  ];
  for (const state of recoveryStates) {
    assert.deepEqual(resolveRendererStartupTarget(signedIn, state), {
      route: 'settings', category: 'recovery',
    });
  }
});

test('routing coordinator enters confirmed-empty library setup from Player with exact return custody', async () => {
  const routes: string[] = [];
  const stages: string[] = [];
  const enterCalls: unknown[] = [];
  let libraryInvocations = 0;
  const setup = createStagedSetupController({ onStateChanged: () => undefined });
  const coordinator = createRendererRoutingCoordinator({
    getPlexSnapshot: () => plexSnapshot(),
    getChannelState: () => channelState(emptySummary()),
    activateRoute: (route) => routes.push(route),
    showPlayer: () => routes.push('player'),
    setSetupStage: (stage) => stages.push(stage),
    setSettingsCategory: () => undefined,
    loadProfiles: () => undefined,
    enterServerSelection: () => undefined,
    enterLibrary: async (returnRoute, returnFocusId, enteredFromServer) => {
      enterCalls.push({ returnRoute, returnFocusId, enteredFromServer });
      setup.enter(returnRoute, returnFocusId, enteredFromServer);
      setup.showOwner('library', 'setup-back');
      libraryInvocations += 1;
    },
  });

  assert.equal(await coordinator.openPlayerSetupReminder(), true);
  assert.deepEqual(stages, ['library']);
  assert.deepEqual(routes, ['channelSetup']);
  assert.deepEqual(enterCalls, [{
    returnRoute: 'player', returnFocusId: 'player-setup-reminder', enteredFromServer: false,
  }]);
  assert.equal(libraryInvocations, 1);
  assert.equal(setup.getState().owner, 'library');
  assert.equal(setup.getState().returnRoute, 'player');
  assert.equal(setup.getState().returnFocusId, 'player-setup-reminder');
  assert.equal(setup.getState().enteredFromServer, false);
});

test('routing coordinator sends unresolved channel state to Settings recovery', async () => {
  const calls: string[] = [];
  const coordinator = createRendererRoutingCoordinator({
    getPlexSnapshot: () => plexSnapshot(), getChannelState: () => channelState(null),
    activateRoute: (route) => calls.push(`route:${route}`), showPlayer: () => calls.push('player'),
    setSetupStage: () => undefined, setSettingsCategory: (category) => calls.push(`category:${category}`),
    loadProfiles: () => calls.push('profiles'), enterServerSelection: () => undefined,
    enterLibrary: async () => undefined,
  });

  await coordinator.routeStartup();
  assert.deepEqual(calls, ['profiles', 'category:recovery', 'route:settings']);

  calls.splice(0);
  assert.equal(await coordinator.openPlayerSetupReminder(), true);
  assert.deepEqual(calls, ['category:recovery', 'route:settings']);
});

function channelState(
  summary: ChannelSetupSummary | null,
  errorText: string | null = null,
): ChannelRuntimeRendererState {
  return { summary, errorText, pending: false, statusText: '', commitMode: 'append', confirmReplace: false };
}

function plexSnapshot(options: {
  authState?: PlexRuntimeSnapshot['auth']['state']; profile?: boolean; server?: boolean; authFailure?: boolean;
} = {}): PlexRuntimeSnapshot {
  const authState = options.authState ?? 'signed-in';
  return {
    auth: {
      state: authState, pin: null,
      profile: authState === 'signed-in' && options.profile !== false ? { accountId: 'account' } : null,
      homeUsers: [], credentialStatus: authState === 'signed-in' ? 'present' : 'missing',
    },
    servers: {
      status: 'ready',
      selected: options.server === false ? null : {
        serverId: 'server', name: 'Server', owned: true, connectionCount: 1,
        hasLocalConnection: true, hasRemoteConnection: false, hasRelayConnection: false, selected: true,
      },
      items: [], lastSelection: null,
    },
    library: { status: 'idle', sections: [], selectedSectionId: null, items: [], search: null, metadata: null },
    lastError: options.authFailure === true ? {
      code: 'PLEX_AUTH_INVALID', message: 'Sign-in required.', retryable: true,
      recoverable: true, operation: 'getSnapshot',
    } : null,
    updatedAtMs: 1,
  };
}

function emptySummary(): ChannelSetupSummary { return channelSummary('not-configured', 0, 0); }
function configuredSummary(): ChannelSetupSummary { return channelSummary('configured', 1, 1); }

function channelSummary(status: ChannelSetupSummary['status'], channelCount: number, listedCount: number): ChannelSetupSummary {
  const channels = listedCount === 0 ? [] : [{
    id: 'channel', number: 101, name: 'Movies', sourceLibraryId: 'movies', sourceLibraryName: 'Movies', itemCount: 1,
  }];
  return {
    status, channelCount,
    currentChannelId: channels[0]?.id ?? null, currentChannelNumber: channels[0]?.number ?? null,
    currentChannelName: channels[0]?.name ?? null, channelNumbers: channels.map(({ number }) => number), channels,
    updatedAtMs: 1, recovery: { loaded: status === 'configured', repaired: false },
  };
}
