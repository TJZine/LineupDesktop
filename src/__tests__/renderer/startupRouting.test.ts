import test from 'node:test';
import assert from 'node:assert/strict';

import type { ChannelSetupSummary } from '../../contracts/channel.js';
import type { PlexRuntimeSnapshot } from '../../contracts/plex.js';
import type { ChannelRuntimeRendererState } from '../../renderer/channelRuntimeState.js';
import { createPlexRuntimeRendererState, type PlexRuntimeRendererState } from '../../renderer/plexRuntimeState.js';
import { createSetupEntryLifecycle } from '../../renderer/setup/setupEntryLifecycle.js';
import { createStagedSetupController } from '../../renderer/setup/stagedSetupController.js';
import type { SetupRuntimeState } from '../../renderer/setup/setupRuntimeCoordinator.js';
import { createRendererRoutingCoordinator, initializeRendererStartup, resolveRendererStartupTarget } from '../../renderer/startupRouting.js';

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
  const harness = createLifecycleRoutingHarness();
  const opening = harness.coordinator.openPlayerSetupReminder();

  assert.equal(harness.runtimeState().library, 'loading');
  assert.deepEqual(harness.events, ['stage:library', 'loading', 'route:channelSetup']);
  assert.equal(harness.controller.getState().returnRoute, 'player');
  assert.equal(harness.controller.getState().returnFocusId, 'player-setup-reminder');
  assert.equal(harness.controller.getState().enteredFromServer, false);
  assert.equal(harness.controller.getState().focusIntent, 'setup-back');

  harness.resolveLoad(0);
  assert.equal(await opening, true);
  assert.equal(harness.controller.getState().focusIntent, 'plex-dyn-section-movies');
});

test('confirmed-empty startup delegates route activation and async completion to the library entry lifecycle', async () => {
  const harness = createLifecycleRoutingHarness();
  const routing = harness.coordinator.routeStartup();
  assert.deepEqual(harness.events, ['stage:library', 'loading', 'route:channelSetup']);
  assert.equal(harness.runtimeState().library, 'loading');
  assert.equal(harness.controller.getState().enteredFromServer, true);
  assert.equal(harness.controller.getState().focusIntent, 'setup-back');

  harness.resolveLoad(0);
  await routing;
  assert.equal(harness.controller.getState().focusIntent, 'plex-dyn-section-movies');
});

test('startup and Player rerun share account, profile, and server setup target resolution', async () => {
  const cases = [
    { snapshot: plexSnapshot({ authState: 'signed-out' }), expected: ['stage:account', 'route:channelSetup'] },
    { snapshot: plexSnapshot({ authFailure: true }), expected: ['stage:account', 'route:channelSetup'] },
    { snapshot: plexSnapshot({ profile: false }), expected: ['stage:profile', 'route:channelSetup', 'profiles'] },
    { snapshot: plexSnapshot({ server: false }), expected: ['stage:server', 'route:channelSetup', 'servers'] },
  ] as const;
  for (const testCase of cases) {
    const startup = createLifecycleRoutingHarness(testCase.snapshot);
    await startup.coordinator.routeStartup();
    assert.deepEqual(startup.events, testCase.expected);
    assert.equal(startup.runtimeState().library, 'idle');

    const rerun = createLifecycleRoutingHarness(testCase.snapshot);
    assert.equal(await rerun.coordinator.openPlayerSetupReminder(), true);
    assert.deepEqual(rerun.events, testCase.expected);
    assert.equal(rerun.runtimeState().library, 'idle');
  }
});

test('routing lifecycle ignores the first completion after a Player reminder reentry', async () => {
  const harness = createLifecycleRoutingHarness();
  const stale = harness.coordinator.openPlayerSetupReminder();
  const latest = harness.coordinator.openPlayerSetupReminder();
  assert.equal(harness.controller.getState().focusIntent, 'setup-back');

  harness.resolveLoad(0);
  await stale;
  assert.equal(harness.controller.getState().focusIntent, 'setup-back');
  harness.resolveLoad(1);
  await latest;
  assert.equal(harness.controller.getState().focusIntent, 'plex-dyn-section-movies');
});

test('startup reveals the routed loading screen as soon as shell capabilities are ready', async () => {
  const events: string[] = [];
  let resolveRoute!: () => void;
  let resolveShell!: () => void;
  const route = new Promise<void>((resolve) => { resolveRoute = resolve; });
  const shell = new Promise<void>((resolve) => { resolveShell = resolve; });
  const startup = initializeRendererStartup({
    loadInitialState: async () => { events.push('state-ready'); },
    routeStartup: async () => {
      events.push('route-prefix:loading');
      await route;
      events.push('route-complete');
    },
    startShell: async () => {
      events.push('shell-start');
      await shell;
      events.push('shell-ready:route-visible');
    },
    isShellReady: () => events.includes('shell-ready:route-visible'),
  });

  await Promise.resolve();
  assert.deepEqual(events, ['state-ready', 'route-prefix:loading', 'shell-start']);
  resolveShell();
  await Promise.resolve();
  assert.deepEqual(events, [
    'state-ready', 'route-prefix:loading', 'shell-start', 'shell-ready:route-visible',
  ]);
  resolveRoute();
  assert.equal(await startup, 'ready');
  assert.equal(events.at(-1), 'route-complete');
});

test('startup reports shell failure without awaiting or leaking rejected route work', async () => {
  let rejectRoute!: (error: Error) => void;
  const route = new Promise<void>((_resolve, reject) => { rejectRoute = reject; });
  const outcome = await initializeRendererStartup({
    loadInitialState: async () => undefined,
    routeStartup: () => route,
    startShell: async () => undefined,
    isShellReady: () => false,
  });
  assert.equal(outcome, 'error');
  rejectRoute(new Error('late route failure'));
  await Promise.resolve();
});

test('startup normalizes unexpected initial, shell, and routed failures to error', async () => {
  assert.equal(await initializeRendererStartup({
    loadInitialState: async () => { throw new Error('initial failure'); },
    routeStartup: async () => undefined,
    startShell: async () => undefined,
    isShellReady: () => true,
  }), 'error');
  assert.equal(await initializeRendererStartup({
    loadInitialState: async () => undefined,
    routeStartup: async () => undefined,
    startShell: async () => { throw new Error('shell failure'); },
    isShellReady: () => false,
  }), 'error');
  assert.equal(await initializeRendererStartup({
    loadInitialState: async () => undefined,
    routeStartup: async () => { throw new Error('route failure'); },
    startShell: async () => undefined,
    isShellReady: () => true,
  }), 'error');
});

test('routing coordinator sends unresolved channel state to Settings recovery', async () => {
  const calls: string[] = [];
  const coordinator = createRendererRoutingCoordinator({
    getPlexSnapshot: () => plexSnapshot(), getChannelState: () => channelState(null),
    activateRoute: (route) => calls.push(`route:${route}`), showPlayer: () => calls.push('player'),
    setSettingsCategory: (category) => calls.push(`category:${category}`),
    enterSetup: async () => undefined,
  });

  await coordinator.routeStartup();
  assert.deepEqual(calls, ['category:recovery', 'route:settings']);

  calls.splice(0);
  assert.equal(await coordinator.openPlayerSetupReminder(), true);
  assert.deepEqual(calls, ['category:recovery', 'route:settings']);
});

function createLifecycleRoutingHarness(snapshot: PlexRuntimeSnapshot = plexSnapshot()) {
  const events: string[] = [];
  const loads = [createVoidDeferred(), createVoidDeferred()];
  let loadIndex = 0;
  let runtimeState: SetupRuntimeState = setupRuntimeState('idle');
  const plexState: PlexRuntimeRendererState = {
    ...createPlexRuntimeRendererState(),
    selectedServerId: snapshot.servers.selected?.serverId ?? null,
    snapshot: {
      ...snapshot,
      library: {
        status: 'ready',
        sections: [{ id: 'movies', title: 'Movies', type: 'movie', contentCount: 1, lastScannedAtMs: 0 }],
        selectedSectionId: null,
        items: [],
        search: null,
        metadata: null,
      },
    },
  };
  const controller = createStagedSetupController({ onStateChanged: () => undefined });
  const entry = createSetupEntryLifecycle({
    controller,
    runtime: {
      getState: () => runtimeState,
      invalidate: () => { runtimeState = setupRuntimeState('idle'); },
      enterLibrary: () => {
        runtimeState = setupRuntimeState('loading');
        events.push('loading');
        const load = loads[loadIndex];
        loadIndex += 1;
        return load?.promise ?? Promise.resolve();
      },
    },
    getPlexState: () => plexState,
    setSetupStage: (stage) => events.push(`stage:${stage}`),
    activateSetupRoute: () => events.push('route:channelSetup'),
    loadProfiles: () => events.push('profiles'),
    enterServerSelection: () => events.push('servers'),
  });
  const coordinator = createRendererRoutingCoordinator({
    getPlexSnapshot: () => plexState.snapshot,
    getChannelState: () => channelState(emptySummary()),
    activateRoute: (route) => events.push(`unexpected-route:${route}`),
    showPlayer: () => events.push('player'),
    setSettingsCategory: () => undefined,
    enterSetup: (returnRoute, returnFocusId, enteredFromServer) => entry.enter({
      originRoute: returnRoute,
      returnFocusId,
      enteredFromServer,
    }),
  });

  return {
    controller,
    coordinator,
    events,
    runtimeState: () => runtimeState,
    resolveLoad(index: number) {
      runtimeState = setupRuntimeState('ready');
      loads[index]?.resolve();
    },
  };
}

function createVoidDeferred(): { promise: Promise<void>; resolve(): void } {
  let resolve!: () => void;
  const promise = new Promise<void>((complete) => { resolve = complete; });
  return { promise, resolve };
}

function setupRuntimeState(library: SetupRuntimeState['library']): SetupRuntimeState {
  return {
    library,
    preview: 'collapsed',
    serverId: library === 'idle' ? null : 'server',
    previewSectionId: null,
    previewRatingKey: null,
  };
}

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
