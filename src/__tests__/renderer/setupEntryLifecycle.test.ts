import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlexLibrarySectionSummary } from '../../contracts/plex.js';
import { createPlexRuntimeRendererState, type PlexRuntimeRendererState } from '../../renderer/plexRuntimeState.js';
import { applySetupOnboardingBack, createSetupEntryLifecycle, getSetupEntryReturnFocusId, resolveSetupOnboardingBackAction, restoreSetupEntryDestination } from '../../renderer/setup/setupEntryLifecycle.js';
import type { SetupRuntimeState } from '../../renderer/setup/setupRuntimeCoordinator.js';
import { deferred } from '../helpers/deferred.js';

test('setup entry establishes reset, loading, route, and return custody before library completion', async () => {
  const load = deferred<void>();
  const events: string[] = [];
  let runtimeState = runtime('idle');
  const plexState = state('server', [section('movies')]);
  const entry = createSetupEntryLifecycle({
    controller: {
      enter: (route, focusId, fromServer) => events.push(`enter:${route}:${focusId}:${String(fromServer)}`),
      showOwner: (owner, focusId) => events.push(`owner:${owner}:${focusId}`),
      normalizeSelection: () => { events.push('normalize'); return 'plex-dyn-section-movies'; },
      showRecovery: () => events.push('recovery'),
    },
    runtime: {
      getState: () => runtimeState,
      invalidate: () => { runtimeState = runtime('idle'); events.push('runtime-reset'); },
      enterLibrary: () => { runtimeState = runtime('loading'); events.push('runtime-loading'); return load.promise; },
    },
    getPlexState: () => plexState,
    setSetupStage: () => events.push('stage:library'),
    activateSetupRoute: () => events.push('route:channelSetup'),
    loadProfiles: () => events.push('profiles'),
    enterServerSelection: () => events.push('servers'),
  });

  const pending = entry.enter({ originRoute: 'settings', returnFocusId: 'settings-open-channel-setup', enteredFromServer: false });
  assert.deepEqual(events, [
    'enter:settings:settings-open-channel-setup:false',
    'runtime-reset',
    'stage:library',
    'owner:library:setup-back',
    'runtime-loading',
    'route:channelSetup',
  ]);

  runtimeState = runtime('ready');
  load.resolve();
  await pending;
  assert.deepEqual(events.slice(-2), ['normalize', 'owner:library:plex-dyn-section-movies']);
});

test('setup entry ignores stale completion after reentry and invalidation', async () => {
  const first = deferred<void>();
  const second = deferred<void>();
  const applied: string[] = [];
  let invocation = 0;
  let runtimeState = runtime('idle');
  const plexState = state('server', [section('movies')]);
  const entry = createSetupEntryLifecycle({
    controller: {
      enter: () => undefined,
      showOwner: (_owner, focusId) => { if (focusId.startsWith('plex-dyn')) applied.push(focusId); },
      normalizeSelection: () => 'plex-dyn-section-movies',
      showRecovery: () => applied.push('recovery'),
    },
    runtime: {
      getState: () => runtimeState,
      invalidate: () => { runtimeState = runtime('idle'); },
      enterLibrary: () => {
        runtimeState = runtime('loading');
        invocation += 1;
        return invocation === 1 ? first.promise : second.promise;
      },
    },
    getPlexState: () => plexState,
    setSetupStage: () => undefined,
    activateSetupRoute: () => undefined,
    loadProfiles: () => undefined,
    enterServerSelection: () => undefined,
  });

  const stale = entry.enter({ originRoute: 'guide', returnFocusId: 'guide-state-setup', enteredFromServer: false });
  const latest = entry.enter({ originRoute: 'player', returnFocusId: 'player-setup-reminder', enteredFromServer: false });
  runtimeState = runtime('ready');
  first.resolve();
  await stale;
  assert.deepEqual(applied, []);
  second.resolve();
  await latest;
  assert.deepEqual(applied, ['plex-dyn-section-movies']);

  const abandoned = entry.enter({ originRoute: 'settings', returnFocusId: 'settings-open-channel-setup', enteredFromServer: false });
  entry.invalidate();
  runtimeState = runtime('error');
  second.resolve();
  await abandoned;
  assert.deepEqual(applied, ['plex-dyn-section-movies']);
});

test('setup return activates each destination before restoring its exact captured focus', () => {
  const cases = [
    ['player', 'player-setup-reminder'],
    ['settings', 'settings-open-channel-setup'],
    ['guide', 'guide-state-setup'],
  ] as const;
  for (const [returnRoute, returnFocusId] of cases) {
    const events: string[] = [];
    restoreSetupEntryDestination({
      returnRoute,
      returnFocusId,
      beforeActivate: returnRoute === 'guide' ? () => events.push('retain-guide-focus') : undefined,
      activateRoute: (route) => events.push(`render:${route}`),
      restoreFocus: (focusId) => events.push(`focus:${focusId}`),
    });
    assert.deepEqual(events, [
      ...(returnRoute === 'guide' ? ['retain-guide-focus'] : []),
      `render:${returnRoute}`,
      `focus:${returnFocusId}`,
    ]);
  }
});

test('setup entry return focus is route-owned and never inherited from unrelated active focus', () => {
  assert.equal(getSetupEntryReturnFocusId('player', 'player-settings'), 'player-setup-reminder');
  assert.equal(getSetupEntryReturnFocusId('settings', 'settings-export-support-bundle'), 'settings-open-channel-setup');
  assert.equal(getSetupEntryReturnFocusId('guide', 'guide-program-channel--program'), 'guide-state-setup');
  assert.equal(getSetupEntryReturnFocusId('guide', 'guide-state-setup'), 'guide-state-setup');
});

test('setup onboarding Back distinguishes rerun custody from contained first run', () => {
  assert.equal(resolveSetupOnboardingBackAction('auth-link-code', false), 'close');
  assert.equal(resolveSetupOnboardingBackAction('profile-select', false), 'close');
  assert.equal(resolveSetupOnboardingBackAction('auth-link-code', true), 'contain');
  assert.equal(resolveSetupOnboardingBackAction('profile-select', true), 'contain');
  assert.equal(resolveSetupOnboardingBackAction('server-select', false), 'profile');
  assert.equal(resolveSetupOnboardingBackAction('server-error', true), 'profile');
  assert.equal(resolveSetupOnboardingBackAction('auth-waiting', false), 'auth-link');
  assert.equal(resolveSetupOnboardingBackAction('auth-error', true), 'auth-link');
});

test('setup onboarding Back applies explicit auth-link transition before origin close', async () => {
  let owner: Parameters<typeof applySetupOnboardingBack>[0]['owner'] = 'auth-error';
  let closeCalls = 0;
  const back = () => applySetupOnboardingBack({
    owner,
    enteredFromServer: false,
    close: () => { closeCalls += 1; },
    contain: () => undefined,
    returnToProfile: () => undefined,
    returnToAuthLink: async () => { owner = 'auth-link-code'; },
  });

  assert.equal(await back(), true);
  assert.equal(owner, 'auth-link-code');
  assert.equal(closeCalls, 0);
  assert.equal(await back(), true);
  assert.equal(closeCalls, 1);
});

function runtime(library: SetupRuntimeState['library']): SetupRuntimeState {
  return { library, preview: 'collapsed', serverId: library === 'idle' ? null : 'server', previewSectionId: null, previewRatingKey: null };
}

function section(id: string): PlexLibrarySectionSummary {
  return { id, title: 'Movies', type: 'movie', contentCount: 1, lastScannedAtMs: 0 };
}

function state(serverId: string, sections: readonly PlexLibrarySectionSummary[]): PlexRuntimeRendererState {
  return {
    ...createPlexRuntimeRendererState(),
    selectedServerId: serverId,
    snapshot: {
      auth: { state: 'signed-in', pin: null, profile: { accountId: 'account' }, homeUsers: [], credentialStatus: 'present' },
      servers: { status: 'ready', selected: { serverId, name: 'Server', owned: true, connectionCount: 1, hasLocalConnection: true, hasRemoteConnection: false, hasRelayConnection: false, selected: true }, items: [], lastSelection: null },
      library: { status: 'ready', sections, selectedSectionId: null, items: [], search: null, metadata: null },
      lastError: null,
      updatedAtMs: 0,
    },
  };
}
