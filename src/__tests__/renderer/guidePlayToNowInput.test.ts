import assert from 'node:assert/strict';
import test from 'node:test';

import type { RendererDomBindings } from '../../renderer/domBindings.js';
import { FocusRegistry, type AppRouteId, type FocusState } from '../../renderer/navigation.js';
import { createNavigationLifecycle } from '../../renderer/shell/navigationLifecycle.js';
import { createRendererShellState, type RendererShellState } from '../../renderer/shell/shellState.js';
import {
  EPG_SLOT_DURATION_MS,
  createEpgGuideView,
  createEpgState,
  focusEpgNow,
  type EpgPresentationSource,
  type EpgProgramViewModel,
  type EpgState,
} from '../../renderer/epg.js';

function createHarness(route: AppRouteId = 'guide', onGuideMediaPlay?: () => boolean) {
  const focusRegistry = new FocusRegistry();
  focusRegistry.register({ id: 'guide-program-1', route: 'guide', order: 0 });
  focusRegistry.register({ id: 'player-guide', route: 'player', order: 0 });
  let activeRoute = route;
  let focus: FocusState = { activeRoute: route, activeId: route === 'guide' ? 'guide-program-1' : 'player-guide' };
  let shell: RendererShellState = { ...createRendererShellState(), bootstrap: 'ready' };
  const guideInputs: string[] = [];
  const playerInputs: string[] = [];
  const pages: number[] = [];
  const lifecycle = createNavigationLifecycle({
    getRoute: () => activeRoute,
    getFocusState: () => focus,
    setFocusState: (value) => { focus = value; },
    getShellState: () => shell,
    setShellState: (value) => { shell = value; },
    render: () => undefined,
    focusRegistry,
    dom: { focusableElements: [] } as unknown as RendererDomBindings,
    onFocusChanged: () => undefined,
    scrollFocusedIntoView: () => undefined,
    handleGuideDirection: () => false,
    handleGuidePage: (offset) => { pages.push(offset); return true; },
    handleGuideMediaPlay: () => {
      guideInputs.push('mediaPlay');
      return onGuideMediaPlay?.() ?? true;
    },
    handlePlayerInput: (input) => { playerInputs.push(input); return true; },
    openInfoRecovery: () => undefined,
    activateRoute: (value) => { activeRoute = value; },
    isProfileModalActive: () => false,
    closeProfileModal: () => undefined,
    handleChannelSetupBack: async () => false,
    dismissInlineError: () => { shell = { ...shell, inlineError: null }; },
    requestFullscreen: async () => undefined,
    invalidateFullscreenRequest: () => undefined,
    closeWindow: () => undefined,
  });
  return {
    lifecycle, guideInputs, playerInputs, pages,
    protect: () => { shell = { ...shell, inlineError: { message: 'Protected', desiredFullscreen: false } }; },
  };
}

function createProgram(id: string, startsAtMs: number, endsAtMs: number): EpgProgramViewModel {
  return {
    id,
    title: id,
    subtitle: '',
    description: '',
    showTitle: '',
    episodeLabel: '',
    rating: '',
    quality: [],
    genres: [],
    startsAtMs,
    endsAtMs,
    artwork: { poster: null, background: null },
  };
}

function createIntegratedPlayToNowHarness(
  initialState: EpgState,
  presentation: EpgPresentationSource,
  commandNow: number,
) {
  let state = initialState;
  const refreshes: string[] = [];
  const restoredFocusIds: string[] = [];
  const harness = createHarness('guide', () => {
    const previousWindowStartMs = state.windowStartMs;
    state = focusEpgNow(state, presentation, commandNow);
    if (state.windowStartMs !== previousWindowStartMs) {
      refreshes.push('guide-media-play-now');
    } else {
      const selectedFocusId = createEpgGuideView(state, presentation).selectedProgram?.focusId;
      if (selectedFocusId !== undefined) restoredFocusIds.push(selectedFocusId);
    }
    return true;
  });
  return { harness, getState: () => state, refreshes, restoredFocusIds };
}

test('Guide consumes only MediaPlay for play-to-now and preserves paging', async () => {
  const harness = createHarness();
  await harness.lifecycle.handleInput('mediaPlay');
  await harness.lifecycle.handleInput('mediaPause');
  await harness.lifecycle.handleInput('mediaPlayPause');
  await harness.lifecycle.handleInput('pageDown');
  await harness.lifecycle.handleInput('pageUp');
  assert.deepEqual(harness.guideInputs, ['mediaPlay']);
  assert.deepEqual(harness.pages, [5, -5]);
  assert.deepEqual(harness.playerInputs, []);
});

test('protected state and Player first refusal precede Guide MediaPlay', async () => {
  const protectedHarness = createHarness();
  protectedHarness.protect();
  await protectedHarness.lifecycle.handleInput('mediaPlay');
  assert.deepEqual(protectedHarness.guideInputs, []);

  const playerHarness = createHarness('player');
  await playerHarness.lifecycle.handleInput('mediaPlay');
  assert.deepEqual(playerHarness.playerInputs, ['mediaPlay']);
  assert.deepEqual(playerHarness.guideInputs, []);
});

test('Guide MediaPlay invokes the real command-time focus transition without playback dispatch', async () => {
  const base = Date.UTC(2026, 7, 1, 12, 0);
  const presentation: EpgPresentationSource = {
    nowMs: base + EPG_SLOT_DURATION_MS - 1,
    nowWatching: null,
    channels: [{
      id: 'channel-1', number: '1', name: 'One', programs: [
        { id: 'old', title: 'Old', subtitle: '', description: '', showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [], startsAtMs: base, endsAtMs: base + EPG_SLOT_DURATION_MS, artwork: { poster: null, background: null } },
        { id: 'new', title: 'New', subtitle: '', description: '', showTitle: '', episodeLabel: '', rating: '', quality: [], genres: [], startsAtMs: base + EPG_SLOT_DURATION_MS, endsAtMs: base + 2 * EPG_SLOT_DURATION_MS, artwork: { poster: null, background: null } },
      ],
    }],
  };
  const commandNow = base + EPG_SLOT_DURATION_MS;
  let state = createEpgState(presentation, 0, 'wide');
  let callbackCount = 0;
  const harness = createHarness('guide', () => {
    callbackCount += 1;
    state = focusEpgNow(state, presentation, commandNow);
    return true;
  });
  await harness.lifecycle.handleInput('mediaPlay');
  assert.equal(callbackCount, 1);
  assert.equal(state.windowStartMs, commandNow);
  assert.equal(state.selectedProgramId, 'new');
  assert.deepEqual(harness.playerInputs, []);

  const protectedHarness = createHarness('guide', () => {
    callbackCount += 1;
    return true;
  });
  protectedHarness.protect();
  await protectedHarness.lifecycle.handleInput('mediaPlay');
  assert.equal(callbackCount, 1);
  assert.deepEqual(protectedHarness.playerInputs, []);
});

test('Guide MediaPlay restores deterministic focused-channel fallback during a same-window gap', async () => {
  const base = Date.UTC(2026, 7, 1, 12, 0);
  const presentation: EpgPresentationSource = {
    nowMs: base,
    nowWatching: null,
    channels: [{
      id: 'channel-1',
      number: '1',
      name: 'One',
      programs: [createProgram('next', base + EPG_SLOT_DURATION_MS, base + 2 * EPG_SLOT_DURATION_MS)],
    }],
  };
  const initialState: EpgState = {
    ...createEpgState(presentation, 0, 'wide'),
    windowStartMs: base,
    selectedChannelId: 'channel-1',
    selectedProgramId: 'missing',
    tuneError: 'Previous tune failed',
  };
  const integrated = createIntegratedPlayToNowHarness(initialState, presentation, base + 1);

  await integrated.harness.lifecycle.handleInput('mediaPlay');

  assert.equal(integrated.getState().selectedChannelId, 'channel-1');
  assert.equal(integrated.getState().selectedProgramId, 'next');
  assert.equal(integrated.getState().tuneError, null);
  assert.deepEqual(integrated.restoredFocusIds, ['guide-program-channel-1--next']);
  assert.deepEqual(integrated.refreshes, []);
  assert.deepEqual(integrated.harness.playerInputs, []);
});

test('Guide MediaPlay keeps shifted-window fallback intent and refreshes without playback', async () => {
  const base = Date.UTC(2026, 7, 1, 12, 0);
  const presentation: EpgPresentationSource = {
    nowMs: base,
    nowWatching: null,
    channels: [{
      id: 'channel-1',
      number: '1',
      name: 'One',
      programs: [createProgram('later', base + 2 * EPG_SLOT_DURATION_MS, base + 3 * EPG_SLOT_DURATION_MS)],
    }],
  };
  const initialState: EpgState = {
    ...createEpgState(presentation, 0, 'wide'),
    windowStartMs: base,
    selectedChannelId: 'channel-1',
    selectedProgramId: 'missing',
  };
  const commandNow = base + EPG_SLOT_DURATION_MS;
  const integrated = createIntegratedPlayToNowHarness(initialState, presentation, commandNow);

  await integrated.harness.lifecycle.handleInput('mediaPlay');

  assert.equal(integrated.getState().windowStartMs, commandNow);
  assert.equal(integrated.getState().selectedChannelId, 'channel-1');
  assert.equal(integrated.getState().selectedProgramId, 'later');
  assert.deepEqual(integrated.restoredFocusIds, []);
  assert.deepEqual(integrated.refreshes, ['guide-media-play-now']);
  assert.deepEqual(integrated.harness.playerInputs, []);
});

test('Guide MediaPlay falls back to the first channel with a visible program', async () => {
  const base = Date.UTC(2026, 7, 1, 12, 0);
  const presentation: EpgPresentationSource = {
    nowMs: base,
    nowWatching: null,
    channels: [
      {
        id: 'channel-empty',
        number: '1',
        name: 'Empty now',
        programs: [createProgram('outside', base + 7 * EPG_SLOT_DURATION_MS, base + 8 * EPG_SLOT_DURATION_MS)],
      },
      {
        id: 'channel-visible',
        number: '2',
        name: 'Visible now',
        programs: [createProgram('visible', base + EPG_SLOT_DURATION_MS, base + 2 * EPG_SLOT_DURATION_MS)],
      },
    ],
  };
  const initialState: EpgState = {
    ...createEpgState(presentation, 0, 'wide'),
    windowStartMs: base,
    selectedChannelId: 'channel-empty',
    selectedProgramId: 'outside',
  };
  const integrated = createIntegratedPlayToNowHarness(initialState, presentation, base + 1);

  await integrated.harness.lifecycle.handleInput('mediaPlay');

  assert.equal(integrated.getState().selectedChannelId, 'channel-visible');
  assert.equal(integrated.getState().selectedProgramId, 'visible');
  assert.deepEqual(integrated.restoredFocusIds, ['guide-program-channel-visible--visible']);
  assert.deepEqual(integrated.refreshes, []);
  assert.deepEqual(integrated.harness.playerInputs, []);
});
