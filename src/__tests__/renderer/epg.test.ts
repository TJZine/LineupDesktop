import assert from 'node:assert/strict';
import test from 'node:test';
import { containsPlexForbiddenRendererField } from '../../contracts/plex.js';
import {
  EPG_SLOT_DURATION_MS,
  EPG_WINDOW_DURATION_MS,
  calculateProgramSpan,
  createEpgGuideView,
  createEpgState,
  createGuideProgramFocusId,
  findEpgProgramCell,
  formatEpgTimeWindow,
  isEpgProgramPlayable,
  moveEpgSelection,
  pageEpgSelection,
  normalizeEpgPresentation,
  setEpgPresentationState,
  updateEpgState,
  type EpgPresentationSource,
  type EpgProgramViewModel,
} from '../../renderer/epg.js';

const BASE = Date.UTC(2026, 4, 12, 20, 0, 0);

function program(id: string, start: number, end: number): EpgProgramViewModel {
  return {
    id,
    title: `Title ${id}`,
    subtitle: `Subtitle ${id}`,
    description: `Description ${id}`,
    showTitle: `Show ${id}`,
    episodeLabel: 'S1 E1',
    rating: 'TV-PG',
    quality: ['HD'],
    genres: ['Drama'],
    startsAtMs: BASE + start * EPG_SLOT_DURATION_MS,
    endsAtMs: BASE + end * EPG_SLOT_DURATION_MS,
  };
}

function presentation(): EpgPresentationSource {
  const current = program('a-current', 1, 3);
  return {
    channels: [
      {
        id: 'channel/a',
        number: '101',
        name: 'Alpha',
        programs: [program('a-past', -1, 1), current, program('a-future', 3, 8)],
      },
      {
        id: 'channel/b',
        number: '202',
        name: 'Beta',
        programs: [program('b-wide', 0, 2), program('b-overlap', 2, 4), program('b-late', 4, 8)],
      },
    ],
    nowWatching: {
      channelId: 'channel/a',
      title: current.title,
      subtitle: current.subtitle,
      startsAtMs: current.startsAtMs,
      endsAtMs: current.endsAtMs,
    },
    nowMs: BASE + 2 * EPG_SLOT_DURATION_MS,
  };
}

test('EPG projects scheduler rows, stable cell ids, slots, clipping, and details', () => {
  const source = presentation();
  const state = createEpgState(source, 7);
  const view = createEpgGuideView(state, source);
  assert.equal(view.presentationState, 'ready');
  assert.equal(view.presentationGeneration, 7);
  assert.equal(view.slots.length, 6);
  assert.equal(view.rows.length, 2);
  assert.equal(view.selectedProgram?.id, 'a-current');
  assert.equal(view.selectedProgram?.focusId, createGuideProgramFocusId('channel/a', 'a-current'));
  assert.equal(view.infoPanel?.description, 'Description a-current');
  assert.equal(view.rows[0]?.programs[0]?.temporalState, 'current');
  assert.equal(view.rows[0]?.programs[1]?.temporalState, 'upcoming');
  assert.equal(view.rows[0]?.programs[0]?.columnStart, 1);
  assert.match(formatEpgTimeWindow(BASE, BASE + EPG_SLOT_DURATION_MS), /^\d{1,2}:\d{2} [AP]M - \d{1,2}:\d{2} [AP]M$/u);
});

test('EPG time labels follow local time across a non-UTC DST transition', () => {
  const processValue: unknown = Reflect.get(globalThis, 'process');
  assert.equal(isTestProcess(processValue), true);
  if (!isTestProcess(processValue)) return;
  const previousTimezone = processValue.env.TZ;
  try {
    processValue.env.TZ = 'America/New_York';
    const beforeSpringForward = Date.UTC(2024, 2, 10, 6, 30);
    const afterSpringForward = Date.UTC(2024, 2, 10, 7, 30);
    assert.equal(formatEpgTimeWindow(beforeSpringForward, afterSpringForward), '1:30 AM - 3:30 AM');
  } finally {
    if (previousTimezone === undefined) delete processValue.env.TZ;
    else processValue.env.TZ = previousTimezone;
  }
});

test('EPG normalization preserves an honest missing now-watching value', () => {
  const source = { ...presentation(), nowWatching: null, nowMs: undefined };
  const before = Date.now();
  const normalized = normalizeEpgPresentation(source);
  const after = Date.now();
  assert.equal(normalized.nowWatching, null);
  assert.ok(normalized.nowMs >= before && normalized.nowMs <= after);
});

test('program span excludes programs outside the active window', () => {
  assert.equal(calculateProgramSpan(program('outside', -3, -2), BASE, BASE + EPG_WINDOW_DURATION_MS), null);
  assert.deepEqual(calculateProgramSpan(program('clipped', -1, 2), BASE, BASE + EPG_WINDOW_DURATION_MS), {
    columnStart: 1,
    columnSpan: 2,
  });
});

test('directional navigation uses adjacent programs and nearest overlap on adjacent channels', () => {
  const source = presentation();
  const initial = createEpgState(source);
  const right = moveEpgSelection(initial, 'right', source);
  assert.equal(right.state.selectedProgramId, 'a-future');
  assert.equal(right.windowChanged, false);
  const down = moveEpgSelection(initial, 'down', source);
  assert.equal(down.state.selectedChannelId, 'channel/b');
  assert.equal(down.state.selectedProgramId, 'b-wide');
  assert.equal(moveEpgSelection(down.state, 'up', source).state.selectedProgramId, 'a-current');
});

test('Guide paging moves five eligible channel rows while preserving focused time overlap', () => {
  const source: EpgPresentationSource = {
    ...presentation(),
    channels: Array.from({ length: 8 }, (_, index) => ({
      id: `channel-${String(index)}`,
      number: String(100 + index),
      name: `Channel ${String(index)}`,
      programs: [program(`program-${String(index)}`, 1, 3)],
    })),
    nowWatching: null,
  };
  const initial = {
    ...createEpgState(source),
    selectedChannelId: 'channel-1',
    selectedProgramId: 'program-1',
  };
  const next = pageEpgSelection(initial, 5, source);
  assert.equal(next.handled, true);
  assert.equal(next.state.selectedChannelId, 'channel-6');
  assert.equal(next.state.selectedProgramId, 'program-6');
  assert.equal(pageEpgSelection(next.state, -5, source).state.selectedChannelId, 'channel-1');
});

test('left and right edge navigation requests exactly one adjacent slot beyond bounded response extrema', () => {
  const source = presentation();
  const base = createEpgState(source);
  const priorBoundary = {
    ...base,
    windowStartMs: BASE - EPG_SLOT_DURATION_MS,
    selectedChannelId: 'channel/a',
    selectedProgramId: 'a-past',
  };
  const prior = moveEpgSelection(priorBoundary, 'left', source);
  assert.equal(prior.handled, true);
  assert.equal(prior.windowChanged, true);
  assert.equal(prior.state.windowStartMs, BASE - 2 * EPG_SLOT_DURATION_MS);

  const nextBoundary = {
    ...base,
    windowStartMs: BASE + 2 * EPG_SLOT_DURATION_MS,
    selectedChannelId: 'channel/a',
    selectedProgramId: 'a-future',
  };
  const next = moveEpgSelection(nextBoundary, 'right', source);
  assert.equal(next.handled, true);
  assert.equal(next.windowChanged, true);
  assert.equal(next.state.windowStartMs, BASE + 3 * EPG_SLOT_DURATION_MS);
});

test('non-first Guide selection survives edge loading and resolves to its stable focus id', () => {
  const source = presentation();
  const selected = {
    ...createEpgState(source, 3),
    windowStartMs: BASE + 2 * EPG_SLOT_DURATION_MS,
    selectedChannelId: 'channel/b',
    selectedProgramId: 'b-late',
  };
  const edge = moveEpgSelection(selected, 'right', source);
  const loading = setEpgPresentationState(edge.state, 'loading', 4);
  assert.equal(loading.selectedChannelId, 'channel/b');
  assert.equal(loading.selectedProgramId, 'b-late');

  const response = presentation();
  const resolved = updateEpgState(loading, response, 4);
  const view = createEpgGuideView(resolved, response);
  assert.equal(view.selectedProgram?.channelId, 'channel/b');
  assert.equal(view.selectedProgram?.id, 'b-late');
  assert.equal(view.selectedProgram?.focusId, createGuideProgramFocusId('channel/b', 'b-late'));
});

test('playability uses the exact current-program half-open interval', () => {
  const current = program('current', 1, 3);
  assert.equal(isEpgProgramPlayable(current, current.startsAtMs), true);
  assert.equal(isEpgProgramPlayable(current, current.endsAtMs - 1), true);
  assert.equal(isEpgProgramPlayable(current, current.endsAtMs), false);
});

test('presentation variants distinguish channel and program emptiness', () => {
  const source = presentation();
  const base = createEpgState(source);
  for (const state of ['loading', 'error'] as const) {
    const view = createEpgGuideView(setEpgPresentationState(base, state), source);
    assert.equal(view.presentationState, state);
    assert.equal(view.rows.length, 0);
  }
  const noChannels: EpgPresentationSource = { channels: [], nowWatching: null, nowMs: BASE };
  assert.equal(updateEpgState(base, noChannels, 8).presentationState, 'empty-channels');
  const noPrograms: EpgPresentationSource = {
    channels: [{ id: 'channel', number: '1', name: 'Channel', programs: [] }],
    nowWatching: null,
    nowMs: BASE,
  };
  assert.equal(updateEpgState(base, noPrograms, 9).presentationState, 'empty-programs');
});

test('presentation refresh preserves a valid identity and clears stale tune feedback', () => {
  const source = presentation();
  const state = { ...createEpgState(source), tuneError: 'Unable to tune.' };
  const updated = updateEpgState(state, source, 11);
  assert.equal(updated.selectedChannelId, state.selectedChannelId);
  assert.equal(updated.selectedProgramId, state.selectedProgramId);
  assert.equal(updated.presentationGeneration, 11);
  assert.equal(updated.tuneError, null);
  assert.equal(findEpgProgramCell(updated, source, 'channel/a', 'a-current')?.focusId, createGuideProgramFocusId('channel/a', 'a-current'));
});

test('Guide state and projected cells stay renderer-safe', () => {
  const source = presentation();
  assert.equal(containsPlexForbiddenRendererField(source), false);
  assert.equal(containsPlexForbiddenRendererField(createEpgGuideView(createEpgState(source), source)), false);
});

function isTestProcess(value: unknown): value is { env: Record<string, string | undefined> } {
  if (typeof value !== 'object' || value === null) return false;
  const env: unknown = Reflect.get(value, 'env');
  return typeof env === 'object' && env !== null;
}
