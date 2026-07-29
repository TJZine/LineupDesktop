import test from 'node:test';
import assert from 'node:assert/strict';

import type { PlayerSnapshot } from '../../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import { createEmptyPlayerSnapshot } from '../../renderer/playerOverlayPresentation.js';
import { createSettingsPlaybackLifecycle } from '../../renderer/settings/settingsPlaybackLifecycle.js';

test('settings playback lifecycle pauses and resumes only its exact playing request', async () => {
  let snapshot = playing('media-1');
  const envelopes: Array<{ intent: string; payload: unknown }> = [];
  const dispatch: LineupDesktopPreloadApi['player']['dispatch'] = async (envelope) => {
    envelopes.push({ intent: envelope.intent, payload: envelope.payload });
    snapshot = envelope.intent === 'player.pauseIfCurrent'
      ? { ...snapshot, status: 'paused', playing: false }
      : { ...snapshot, status: 'playing', playing: true };
    return { ok: true, requestId: envelope.requestId, value: { accepted: true, events: [], snapshot } };
  };
  const lifecycle = createSettingsPlaybackLifecycle({ player: { dispatch }, getSnapshot: () => snapshot });

  await lifecycle.routeChanged('player', 'settings', false);
  await lifecycle.routeChanged('settings', 'player', false);

  assert.deepEqual(envelopes, [
    { intent: 'player.pauseIfCurrent', payload: { snapshotRequestId: 'media-1' } },
    { intent: 'player.playIfCurrent', payload: { snapshotRequestId: 'media-1' } },
  ]);
});

test('settings playback lifecycle never resumes replacement, user-changed, failed, or keep-running playback', async () => {
  let snapshot = playing('media-1');
  const intents: string[] = [];
  let acceptPause = true;
  const dispatch: LineupDesktopPreloadApi['player']['dispatch'] = async (envelope) => {
    intents.push(envelope.intent);
    if (!acceptPause) return {
      ok: true,
      requestId: envelope.requestId,
      value: { accepted: false, events: [], snapshot },
    };
    snapshot = { ...snapshot, status: 'paused', playing: false };
    return { ok: true, requestId: envelope.requestId, value: { accepted: true, events: [], snapshot } };
  };
  const lifecycle = createSettingsPlaybackLifecycle({ player: { dispatch }, getSnapshot: () => snapshot });

  await lifecycle.routeChanged('player', 'settings', true);
  assert.deepEqual(intents, []);
  await lifecycle.routeChanged('player', 'settings', false);
  snapshot = playing('media-2');
  lifecycle.observeSnapshot(snapshot);
  await lifecycle.routeChanged('settings', 'player', false);
  assert.deepEqual(intents, ['player.pauseIfCurrent']);

  acceptPause = false;
  await lifecycle.routeChanged('player', 'settings', false);
  await lifecycle.routeChanged('settings', 'player', false);
  assert.deepEqual(intents, ['player.pauseIfCurrent', 'player.pauseIfCurrent']);
});

test('settings playback lifecycle cleanup releases pause custody', async () => {
  let snapshot = playing('media-1');
  const intents: string[] = [];
  const dispatch: LineupDesktopPreloadApi['player']['dispatch'] = async (envelope) => {
    intents.push(envelope.intent);
    snapshot = { ...snapshot, status: 'paused', playing: false };
    return { ok: true, requestId: envelope.requestId, value: { accepted: true, events: [], snapshot } };
  };
  const lifecycle = createSettingsPlaybackLifecycle({ player: { dispatch }, getSnapshot: () => snapshot });
  await lifecycle.routeChanged('player', 'settings', false);
  lifecycle.cleanup();
  await lifecycle.routeChanged('settings', 'player', false);
  assert.deepEqual(intents, ['player.pauseIfCurrent']);
});

test('settings playback lifecycle does not acquire resume custody after route exit or cleanup', async () => {
  let snapshot = playing('media-1');
  const intents: string[] = [];
  const resolvers: Array<(value: Awaited<ReturnType<LineupDesktopPreloadApi['player']['dispatch']>>) => void> = [];
  const dispatch: LineupDesktopPreloadApi['player']['dispatch'] = (envelope) => {
    intents.push(envelope.intent);
    return new Promise((resolve) => { resolvers.push(resolve); });
  };
  const lifecycle = createSettingsPlaybackLifecycle({ player: { dispatch }, getSnapshot: () => snapshot });

  const entry = lifecycle.routeChanged('player', 'settings', false);
  await lifecycle.routeChanged('settings', 'player', false);
  snapshot = { ...snapshot, status: 'paused', playing: false };
  resolvers.shift()?.({
    ok: true,
    requestId: 'settings-playback-pause-1',
    value: { accepted: true, events: [], snapshot },
  });
  await entry;
  await lifecycle.routeChanged('settings', 'player', false);

  snapshot = playing('media-1');
  const pendingCleanup = lifecycle.routeChanged('player', 'settings', false);
  lifecycle.cleanup();
  snapshot = { ...snapshot, status: 'paused', playing: false };
  resolvers.shift()?.({
    ok: true,
    requestId: 'settings-playback-pause-2',
    value: { accepted: true, events: [], snapshot },
  });
  await pendingCleanup;

  assert.deepEqual(intents, ['player.pauseIfCurrent', 'player.pauseIfCurrent']);
});

function playing(requestId: string): PlayerSnapshot {
  return { ...createEmptyPlayerSnapshot(), requestId, status: 'playing', playing: true };
}
