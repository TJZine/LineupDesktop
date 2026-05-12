import test from 'node:test';
import assert from 'node:assert/strict';

import {
  applyBlockPlaybackMode,
  getBlockGroupKey,
  applyPlaybackOrdering,
  ChannelScheduler,
  RESYNC_THRESHOLD_MS,
  SCHEDULER_ERROR_MESSAGES,
  ShuffleGenerator,
  SYNC_INTERVAL_MS,
  applyPlaybackMode,
  buildScheduleIndex,
  calculateNextProgram,
  calculatePreviousProgram,
  calculateProgramAtTime,
  generateScheduleWindow,
} from '../domain/scheduler/index.js';
import type {
  IShuffleGenerator,
  ResolvedContentItem,
  ScheduleConfig,
  SchedulerClock,
  SchedulerTimerHandle,
  SchedulerTimerPort,
} from '../domain/scheduler/index.js';

class FakeClock implements SchedulerClock {
  public currentTime: number;

  public constructor(initialTime: number) {
    this.currentTime = initialTime;
  }

  public now(): number {
    return this.currentTime;
  }
}

class FakeTimers implements SchedulerTimerPort {
  public readonly handlers = new Map<SchedulerTimerHandle, () => void>();
  public clearCount = 0;
  private nextHandle = 1;

  public setInterval(handler: () => void): SchedulerTimerHandle {
    const handle = this.nextHandle;
    this.nextHandle++;
    this.handlers.set(handle, handler);
    return handle;
  }

  public clearInterval(handle: SchedulerTimerHandle): void {
    this.handlers.delete(handle);
    this.clearCount++;
  }

  public tickAll(): void {
    for (const handler of [...this.handlers.values()]) {
      handler();
    }
  }
}

class SequenceClock implements SchedulerClock {
  private readonly values: number[];
  private lastValue: number;

  public constructor(values: number[]) {
    assert.ok(values.length > 0, 'sequence clock needs at least one value');
    this.values = [...values];
    this.lastValue = values[0] as number;
  }

  public now(): number {
    const value = this.values.shift();
    if (value !== undefined) {
      this.lastValue = value;
    }
    return this.lastValue;
  }
}

const baseContent: ResolvedContentItem[] = [
  {
    ratingKey: 'a',
    type: 'movie',
    title: 'A',
    fullTitle: 'A',
    durationMs: 10_000,
    thumb: null,
    year: 2020,
    scheduledIndex: 0,
  },
  {
    ratingKey: 'b',
    type: 'movie',
    title: 'B',
    fullTitle: 'B',
    durationMs: 20_000,
    thumb: null,
    year: 2021,
    scheduledIndex: 1,
  },
  {
    ratingKey: 'c',
    type: 'movie',
    title: 'C',
    fullTitle: 'C',
    durationMs: 30_000,
    thumb: null,
    year: 2022,
    scheduledIndex: 2,
  },
];

function config(overrides: Partial<ScheduleConfig> = {}): ScheduleConfig {
  return {
    channelId: 'channel-1',
    anchorTime: 1_000_000,
    content: baseContent,
    playbackMode: 'sequential',
    shuffleSeed: 12345,
    ...overrides,
  };
}

test('scheduler domain resolves deterministic anchor-time programs and wraps before and after anchor', () => {
  const shuffler = new ShuffleGenerator();
  const index = buildScheduleIndex(config(), shuffler, 55);

  assert.equal(index.generatedAt, 55);
  assert.equal(index.totalLoopDurationMs, 60_000);

  const atAnchor = calculateProgramAtTime(1_000_000, index, 1_000_000);
  assert.equal(atAnchor.item.ratingKey, 'a');
  assert.equal(atAnchor.elapsedMs, 0);
  assert.equal(atAnchor.loopNumber, 0);
  assert.equal(atAnchor.streamDescriptor, null);

  const afterLoop = calculateProgramAtTime(1_065_000, index, 1_000_000);
  assert.equal(afterLoop.item.ratingKey, 'a');
  assert.equal(afterLoop.elapsedMs, 5_000);
  assert.equal(afterLoop.loopNumber, 1);

  const beforeAnchor = calculateProgramAtTime(995_000, index, 1_000_000);
  assert.equal(beforeAnchor.item.ratingKey, 'c');
  assert.equal(beforeAnchor.elapsedMs, 25_000);
  assert.equal(beforeAnchor.loopNumber, -1);
});

test('scheduler domain requires an injected clock', () => {
  assert.throws(() => new ChannelScheduler(), {
    message: SCHEDULER_ERROR_MESSAGES.CLOCK_REQUIRED,
  });
  assert.throws(() => new ChannelScheduler(new ShuffleGenerator()), {
    message: SCHEDULER_ERROR_MESSAGES.CLOCK_REQUIRED,
  });
});

test('scheduler domain preserves current next previous lookup and schedule windows', () => {
  const scheduler = new ChannelScheduler({
    clock: new FakeClock(1_015_000),
  });
  scheduler.loadChannel(config());

  const current = scheduler.getCurrentProgram();
  assert.equal(current.item.ratingKey, 'b');
  assert.equal(current.elapsedMs, 5_000);
  assert.equal(current.isCurrent, true);

  const next = scheduler.getNextProgram();
  assert.equal(next.item.ratingKey, 'c');
  assert.equal(next.elapsedMs, 0);
  assert.equal(next.isCurrent, false);

  const previous = scheduler.getPreviousProgram();
  assert.equal(previous.item.ratingKey, 'a');
  assert.equal(previous.elapsedMs, 0);
  assert.equal(previous.isCurrent, false);

  const window = scheduler.getScheduleWindow(1_005_000, 1_045_000);
  assert.deepEqual(
    window.programs.map((program) => program.item.ratingKey),
    ['a', 'b', 'c'],
  );
  assert.deepEqual(
    window.programs.map((program) => program.isCurrent),
    [false, true, false],
  );

  const output: ReturnType<typeof scheduler.getUpcoming> = [];
  const upcoming = scheduler.getUpcoming(4, output);
  assert.equal(upcoming, output);
  assert.deepEqual(
    upcoming.map((program) => program.item.ratingKey),
    ['b', 'c', 'a', 'b'],
  );
  assert.deepEqual(
    upcoming.map((program) => program.isCurrent),
    [true, false, false, false],
  );
});

test('scheduler domain snapshots clock once for public read metadata', () => {
  const scheduler = new ChannelScheduler({
    clock: new SequenceClock([
      1_000_000,
      1_009_999,
      1_010_000,
    ]),
  });
  scheduler.loadChannel(config());

  const current = scheduler.getCurrentProgram();
  assert.equal(current.item.ratingKey, 'a');
  assert.equal(current.isCurrent, true);
});

test('scheduler domain snapshots clock once for recalculate state updates', () => {
  const scheduler = new ChannelScheduler({
    clock: new SequenceClock([
      1_000_000,
      1_009_999,
      1_010_000,
    ]),
  });
  scheduler.loadChannel(config());

  scheduler.recalculateFromTime(1_009_999);
  const state = scheduler.getState();

  assert.equal(state.currentProgram?.item.ratingKey, 'a');
  assert.equal(state.currentProgram?.isCurrent, true);
  assert.equal(state.nextProgram?.item.ratingKey, 'b');
  assert.equal(state.nextProgram?.isCurrent, false);
  assert.equal(state.lastSyncTime, 1_009_999);
});

test('scheduler domain falls back only for non-finite anchors through the injected clock', () => {
  const clock = new FakeClock(42_000);
  const scheduler = new ChannelScheduler({ clock });

  scheduler.loadChannel(config({ anchorTime: 0 }));
  assert.equal(scheduler.getScheduleIndex().generatedAt, 42_000);
  assert.equal(scheduler.getProgramAtTime(0).scheduledStartTime, 0);

  scheduler.loadChannel(config({ anchorTime: Number.POSITIVE_INFINITY }));
  assert.equal(scheduler.getProgramAtTime(42_000).scheduledStartTime, 42_000);
});

test('scheduler domain keeps shuffle seeds deterministic and rejects non-finite seeds', () => {
  const shuffler = new ShuffleGenerator();
  const input = [1, 2, 3, 4, 5];
  const firstShuffle = shuffler.shuffle(input, 12345);
  const secondShuffle = shuffler.shuffle(input, 12345);
  assert.deepEqual(firstShuffle, secondShuffle);
  assert.deepEqual([...firstShuffle].sort((a, b) => a - b), input);
  assert.equal(new Set(firstShuffle).size, input.length);

  const firstIndices = shuffler.shuffleIndices(5, 12345);
  const secondIndices = shuffler.shuffleIndices(5, 12345);
  assert.deepEqual(firstIndices, secondIndices);
  assert.deepEqual([...firstIndices].sort((a, b) => a - b), [0, 1, 2, 3, 4]);
  assert.equal(new Set(firstIndices).size, 5);
  assert.equal(
    shuffler.generateSeed('channel-1', 1_000_000),
    shuffler.generateSeed('channel-1', 1_000_000),
  );
  assert.notEqual(
    shuffler.generateSeed('channel-1', 1_000_000),
    shuffler.generateSeed('channel-2', 1_000_000),
  );
  assert.throws(() => shuffler.shuffle([1, 2, 3], Number.NaN), /finite number/);
  assert.throws(() => shuffler.shuffleIndices(3, Number.POSITIVE_INFINITY), /finite number/);
});

test('scheduler domain applies sequential shuffle and block ordering with normalized indexes', () => {
  const shuffler = new ShuffleGenerator();
  const sequential = applyPlaybackMode(baseContent, 'sequential', 1, shuffler);
  assert.deepEqual(
    sequential.map((item) => [item.ratingKey, item.scheduledIndex]),
    [
      ['a', 0],
      ['b', 1],
      ['c', 2],
    ],
  );

  const firstShuffle = applyPlaybackMode(baseContent, 'shuffle', 42, shuffler);
  const secondShuffle = applyPlaybackMode(baseContent, 'shuffle', 42, shuffler);
  assert.deepEqual(
    firstShuffle.map((item) => item.ratingKey),
    secondShuffle.map((item) => item.ratingKey),
  );

  const episodes: ResolvedContentItem[] = [
    item('a1', 'Show A', 'show-a', 0),
    item('a2', 'Show A', 'show-a', 1),
    item('a3', 'Show A', 'show-a', 2),
    item('b1', 'Show B', 'show-b', 3),
    item('b2', 'Show B', 'show-b', 4),
    item('b3', 'Show B', 'show-b', 5),
  ];
  const block = applyPlaybackMode(episodes, 'block', 1, stableShuffler(), 2);
  assert.deepEqual(
    block.map((contentItem) => [contentItem.ratingKey, contentItem.scheduledIndex]),
    [
      ['a1', 0],
      ['a2', 1],
      ['b1', 2],
      ['b2', 3],
      ['a3', 4],
      ['b3', 5],
    ],
  );

  const sameTitleDifferentThumbs = [
    item('alpha-1', 'Shared Title', 'show-alpha-thumb', 0),
    item('beta-1', 'Shared Title', 'show-beta-thumb', 1),
    item('alpha-2', 'Shared Title', 'show-alpha-thumb', 2),
    item('beta-2', 'Shared Title', 'show-beta-thumb', 3),
  ];
  const collisionSafeBlock = applyPlaybackMode(
    sameTitleDifferentThumbs,
    'block',
    1,
    stableShuffler(),
    1,
  );
  assert.deepEqual(
    collisionSafeBlock.map((contentItem) => contentItem.ratingKey),
    ['alpha-1', 'beta-1', 'alpha-2', 'beta-2'],
  );
});

test('scheduler domain validates and normalizes block sizes', () => {
  assert.throws(
    () =>
      applyBlockPlaybackMode({
        items: [],
        seed: 0,
        blockSize: 0,
        shuffleKeys: (keys) => keys,
      }),
    /blockSize=0/,
  );
  assert.throws(
    () =>
      applyBlockPlaybackMode({
        items: [],
        seed: 0,
        blockSize: 1.5,
        shuffleKeys: (keys) => keys,
      }),
    RangeError,
  );

  const normalized = applyPlaybackOrdering({
    items: [item('a1', 'Show A', 'show-a', 0), item('b1', 'Show B', 'show-b', 1)],
    mode: 'block',
    seed: 0,
    blockSize: Number.NaN,
    shuffleItems: (values) => [...values],
  });
  assert.deepEqual(
    normalized.map((contentItem) => contentItem.ratingKey),
    ['a1', 'b1'],
  );
  assert.equal(getBlockGroupKey({ ratingKey: 'rating', showThumb: '', showTitle: 'Show Title' }), 'Show Title');
  assert.equal(getBlockGroupKey({ ratingKey: 'rating', showThumb: '', showTitle: '' }), 'rating');
});

test('scheduler domain emits events and injected timers can be paused and unloaded without leaks', () => {
  const clock = new FakeClock(1_000_000);
  const timers = new FakeTimers();
  const scheduler = new ChannelScheduler({ clock, timers });
  const started: string[] = [];
  const ended: string[] = [];
  let syncCount = 0;

  scheduler.on('programStart', (program) => started.push(program.item.ratingKey));
  scheduler.on('programEnd', (program) => ended.push(program.item.ratingKey));
  scheduler.on('scheduleSync', () => {
    syncCount++;
  });

  scheduler.loadChannel(config());
  assert.equal(timers.handlers.size, 1);
  assert.deepEqual(started, ['a']);

  clock.currentTime = 1_015_000;
  timers.tickAll();
  assert.deepEqual(ended, ['a']);
  assert.deepEqual(started, ['a', 'b']);
  assert.equal(syncCount, 1);

  scheduler.pauseSyncTimer();
  assert.equal(timers.handlers.size, 0);
  assert.equal(timers.clearCount, 1);

  scheduler.resumeSyncTimer();
  assert.equal(timers.handlers.size, 1);

  scheduler.unloadChannel();
  assert.equal(timers.handlers.size, 0);
  assert.equal(timers.clearCount, 2);
});

test('scheduler domain resume immediately syncs stale state before rearming timer', () => {
  const clock = new FakeClock(1_000_000);
  const timers = new FakeTimers();
  const scheduler = new ChannelScheduler({ clock, timers });
  const started: string[] = [];
  const ended: string[] = [];
  const syncPrograms: string[] = [];

  scheduler.on('programStart', (program) => started.push(program.item.ratingKey));
  scheduler.on('programEnd', (program) => ended.push(program.item.ratingKey));
  scheduler.on('scheduleSync', (state) => {
    syncPrograms.push(state.currentProgram?.item.ratingKey ?? 'none');
  });

  scheduler.loadChannel(config());
  scheduler.pauseSyncTimer();
  clock.currentTime = 1_015_000;

  scheduler.resumeSyncTimer();

  assert.deepEqual(ended, ['a']);
  assert.deepEqual(started, ['a', 'b']);
  assert.deepEqual(syncPrograms, ['b']);
  assert.equal(scheduler.getState().currentProgram?.item.ratingKey, 'b');
  assert.equal(scheduler.getState().nextProgram?.item.ratingKey, 'c');
  assert.equal(scheduler.getState().lastSyncTime, 1_015_000);
  assert.equal(timers.handlers.size, 1);
});

test('scheduler domain hard resync reports measured timer drift', () => {
  const clock = new FakeClock(1_000_000);
  const timers = new FakeTimers();
  const scheduler = new ChannelScheduler({ clock, timers });
  const hardSyncs: Array<{ wasHardResync?: boolean; detectedDriftMs?: number }> = [];

  scheduler.on('scheduleSync', (state) => {
    hardSyncs.push({
      wasHardResync: state.wasHardResync,
      detectedDriftMs: state.detectedDriftMs,
    });
  });

  scheduler.loadChannel(config());
  clock.currentTime = 1_000_000 + SYNC_INTERVAL_MS + RESYNC_THRESHOLD_MS + 250;
  timers.tickAll();

  assert.deepEqual(hardSyncs, [{
    wasHardResync: true,
    detectedDriftMs: RESYNC_THRESHOLD_MS + 250,
  }]);
  clock.currentTime += SYNC_INTERVAL_MS;
  timers.tickAll();
  assert.equal(hardSyncs.length, 2);
  assert.equal(hardSyncs[1]?.wasHardResync, undefined);
});

test('scheduler domain preserves active timer and state when replacement load fails', () => {
  const clock = new FakeClock(1_000_000);
  const timers = new FakeTimers();
  const scheduler = new ChannelScheduler({ clock, timers });
  scheduler.loadChannel(config());
  assert.equal(timers.handlers.size, 1);
  const oldState = scheduler.getState();

  assert.throws(
    () => scheduler.loadChannel(config({
      channelId: 'invalid',
      content: [item('bad-duration', 'Invalid', 'invalid', 0, 0)],
    })),
    { message: SCHEDULER_ERROR_MESSAGES.INVALID_ITEM_DURATION },
  );

  assert.equal(timers.handlers.size, 1);
  assert.equal(scheduler.getState().channelId, oldState.channelId);
  assert.equal(scheduler.getState().currentProgram?.item.ratingKey, oldState.currentProgram?.item.ratingKey);
});

test('scheduler domain emits balanced program events when active channel is replaced', () => {
  const clock = new FakeClock(1_000_000);
  const scheduler = new ChannelScheduler({ clock });
  const events: string[] = [];

  scheduler.on('programStart', (program) => events.push(`start:${program.item.ratingKey}`));
  scheduler.on('programEnd', (program) => events.push(`end:${program.item.ratingKey}`));

  scheduler.loadChannel(config());
  scheduler.loadChannel(config({
    channelId: 'replacement',
    content: [item('replacement-a', 'Replacement A', 'movie', 0, 10_000)],
  }));

  assert.deepEqual(events, ['start:a', 'end:a', 'start:replacement-a']);
});

test('scheduler domain prevents reentrant resume timer leaks during active replacement end events', () => {
  const clock = new FakeClock(1_000_000);
  const timers = new FakeTimers();
  const scheduler = new ChannelScheduler({ clock, timers });
  const statesDuringEnd: boolean[] = [];

  scheduler.on('programEnd', () => {
    statesDuringEnd.push(scheduler.getState().isActive);
    scheduler.resumeSyncTimer();
  });

  scheduler.loadChannel(config());
  assert.equal(timers.handlers.size, 1);

  scheduler.loadChannel(config({
    channelId: 'replacement',
    content: [item('replacement-a', 'Replacement A', 'movie', 0, 10_000)],
  }));

  assert.deepEqual(statesDuringEnd, [false]);
  assert.equal(scheduler.getState().isActive, true);
  assert.equal(scheduler.getState().channelId, 'replacement');
  assert.equal(timers.handlers.size, 1);

  scheduler.unloadChannel();
  assert.equal(timers.handlers.size, 0);
  assert.equal(scheduler.getState().isActive, false);
});

test('scheduler domain emits balanced program events when active channel is unloaded', () => {
  const clock = new FakeClock(1_000_000);
  const scheduler = new ChannelScheduler({ clock });
  const events: string[] = [];

  scheduler.on('programStart', (program) => events.push(`start:${program.item.ratingKey}`));
  scheduler.on('programEnd', (program) => events.push(`end:${program.item.ratingKey}`));

  scheduler.loadChannel(config());
  scheduler.unloadChannel();
  scheduler.unloadChannel();

  assert.deepEqual(events, ['start:a', 'end:a']);
});

test('scheduler domain prevents reentrant resume timer leaks during active unload end events', () => {
  const clock = new FakeClock(1_000_000);
  const timers = new FakeTimers();
  const scheduler = new ChannelScheduler({ clock, timers });
  const statesDuringEnd: boolean[] = [];

  scheduler.on('programEnd', () => {
    statesDuringEnd.push(scheduler.getState().isActive);
    scheduler.resumeSyncTimer();
  });

  scheduler.loadChannel(config());
  assert.equal(timers.handlers.size, 1);

  scheduler.unloadChannel();

  assert.deepEqual(statesDuringEnd, [false]);
  assert.equal(scheduler.getState().isActive, false);
  assert.equal(timers.handlers.size, 0);
});

test('scheduler domain isolates event handler failures', () => {
  const errors: Array<{ message: string; detail?: unknown }> = [];
  const scheduler = new ChannelScheduler({
    clock: new FakeClock(1_000_000),
    logger: {
      error: (message, detail) => errors.push({ message, detail }),
    },
  });
  const started: string[] = [];
  scheduler.on('programStart', () => {
    throw new Error('listener failed');
  });
  scheduler.on('programStart', (program) => {
    started.push(program.item.ratingKey);
  });

  scheduler.loadChannel(config());

  assert.deepEqual(started, ['a']);
  assert.equal(errors.length, 1);
  assert.equal(errors[0]?.message, 'Scheduler event handler failed for programStart');
});

test('scheduler domain rejects empty channels invalid windows and invalid item durations', () => {
  const shuffler = new ShuffleGenerator();
  assert.throws(() => buildScheduleIndex(config({ content: [] }), shuffler), {
    message: SCHEDULER_ERROR_MESSAGES.EMPTY_CHANNEL,
  });
  for (const durationMs of [0, -1, Number.NaN, 1.5]) {
    assert.throws(
      () =>
        buildScheduleIndex(
          config({
            content: [item(`duration-${String(durationMs)}`, 'Invalid', 'invalid', 0, durationMs)],
          }),
          shuffler,
        ),
      {
        message: SCHEDULER_ERROR_MESSAGES.INVALID_ITEM_DURATION,
      },
    );
  }

  const scheduler = new ChannelScheduler({ clock: new FakeClock(1_000_000) });
  assert.throws(() => scheduler.getCurrentProgram(), {
    message: SCHEDULER_ERROR_MESSAGES.NO_CHANNEL_LOADED,
  });
  scheduler.loadChannel(config());
  assert.throws(() => scheduler.getScheduleWindow(1_001_000, 1_000_000), {
    message: SCHEDULER_ERROR_MESSAGES.INVALID_TIME_RANGE,
  });
});

test('scheduler domain calculator returns adjacent programs and reusable windows', () => {
  const shuffler = new ShuffleGenerator();
  const index = buildScheduleIndex(config(), shuffler);
  const current = calculateProgramAtTime(1_010_000, index, 1_000_000);
  const next = calculateNextProgram(current, index, 1_000_000);
  const previous = calculatePreviousProgram(current, index, 1_000_000);
  const output = [current];
  const programs = generateScheduleWindow(1_000_000, 1_060_000, index, 1_000_000, output);

  assert.equal(current.item.ratingKey, 'b');
  assert.equal(next.item.ratingKey, 'c');
  assert.equal(previous.item.ratingKey, 'a');
  assert.equal(next.elapsedMs, 0);
  assert.equal(previous.elapsedMs, 0);
  assert.equal(next.isCurrent, false);
  assert.equal(previous.isCurrent, false);
  assert.equal(programs, output);
  assert.deepEqual(
    programs.map((program) => program.item.ratingKey),
    ['a', 'b', 'c'],
  );
});

function item(
  ratingKey: string,
  showTitle: string,
  showThumb: string,
  scheduledIndex: number,
  durationMs = 1,
): ResolvedContentItem {
  return {
    ratingKey,
    type: 'episode',
    title: ratingKey,
    fullTitle: ratingKey,
    durationMs,
    thumb: null,
    year: 2020,
    scheduledIndex,
    showTitle,
    showThumb,
  };
}

function stableShuffler(): IShuffleGenerator {
  return {
    shuffle: <T,>(values: T[]): T[] => [...values],
    shuffleIndices: (count: number): number[] => Array.from({ length: count }, (_, index) => index),
    generateSeed: (): number => 0,
  };
}
