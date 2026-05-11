import {
  MAX_DRIFT_MS,
  RESYNC_THRESHOLD_MS,
  SCHEDULER_ERROR_MESSAGES,
  SYNC_INTERVAL_MS,
} from './constants.js';
import type { IChannelScheduler, IShuffleGenerator } from './interfaces.js';
import {
  buildScheduleIndex,
  calculateNextProgram,
  calculatePreviousProgram,
  calculateProgramAtTime,
  generateScheduleWindow,
} from './scheduleCalculator.js';
import { ShuffleGenerator } from './shuffleGenerator.js';
import type {
  ScheduleConfig,
  ScheduleIndex,
  ScheduledProgram,
  SchedulerClock,
  SchedulerEventMap,
  SchedulerState,
  SchedulerTimerPort,
  ScheduleWindow,
  SyncTimerState,
} from './types.js';

export interface ChannelSchedulerOptions {
  shuffler?: IShuffleGenerator;
  clock?: SchedulerClock;
  timers?: SchedulerTimerPort;
}

const ZERO_CLOCK: SchedulerClock = {
  now: () => 0,
};

class SchedulerEventOwner {
  private readonly handlers: {
    [K in keyof SchedulerEventMap]: Array<(payload: SchedulerEventMap[K]) => void>;
  } = {
    programStart: [],
    programEnd: [],
    scheduleSync: [],
  };

  public on<K extends keyof SchedulerEventMap>(
    event: K,
    handler: (payload: SchedulerEventMap[K]) => void,
  ): void {
    this.handlers[event].push(handler);
  }

  public off<K extends keyof SchedulerEventMap>(
    event: K,
    handler: (payload: SchedulerEventMap[K]) => void,
  ): void {
    const handlers = this.handlers[event];
    const index = handlers.indexOf(handler);
    if (index >= 0) {
      handlers.splice(index, 1);
    }
  }

  public emit<K extends keyof SchedulerEventMap>(event: K, payload: SchedulerEventMap[K]): void {
    for (const handler of [...this.handlers[event]]) {
      handler(payload);
    }
  }

  public clear(): void {
    this.handlers.programStart.length = 0;
    this.handlers.programEnd.length = 0;
    this.handlers.scheduleSync.length = 0;
  }
}

function isShuffleGenerator(value: IShuffleGenerator | ChannelSchedulerOptions): value is IShuffleGenerator {
  return (
    typeof (value as IShuffleGenerator).shuffle === 'function' &&
    typeof (value as IShuffleGenerator).generateSeed === 'function'
  );
}

export class ChannelScheduler implements IChannelScheduler {
  private readonly emitter = new SchedulerEventOwner();
  private readonly shuffler: IShuffleGenerator;
  private readonly clock: SchedulerClock;
  private readonly timers: SchedulerTimerPort | null;

  private config: ScheduleConfig | null = null;
  private index: ScheduleIndex | null = null;
  private isActive = false;
  private currentProgram: ScheduledProgram | null = null;
  private nextProgram: ScheduledProgram | null = null;
  private lastSyncTime = 0;

  private syncTimerState: SyncTimerState = {
    expectedNextTick: 0,
    maxDriftMs: MAX_DRIFT_MS,
    resyncThreshold: RESYNC_THRESHOLD_MS,
    interval: null,
  };

  public constructor(shufflerOrOptions?: IShuffleGenerator | ChannelSchedulerOptions) {
    const options =
      shufflerOrOptions && isShuffleGenerator(shufflerOrOptions)
        ? { shuffler: shufflerOrOptions }
        : shufflerOrOptions;
    this.shuffler = options?.shuffler ?? new ShuffleGenerator();
    this.clock = options?.clock ?? ZERO_CLOCK;
    this.timers = options?.timers ?? null;
  }

  public loadChannel(config: ScheduleConfig): void {
    if (!config.content || config.content.length === 0) {
      throw new Error(SCHEDULER_ERROR_MESSAGES.EMPTY_CHANNEL);
    }

    this.stopSyncTimer();

    const now = this.clock.now();
    const anchorTime = Number.isFinite(config.anchorTime) ? config.anchorTime : now;
    this.config = { ...config, anchorTime };
    this.index = buildScheduleIndex(this.config, this.shuffler, now);
    this.isActive = true;
    this.lastSyncTime = now;
    this.currentProgram = this.getProgramAtTimeForCurrentTime(now, now);
    this.nextProgram = calculateNextProgram(this.currentProgram, this.index, this.config.anchorTime);

    this.startSyncTimer();
    this.emitter.emit('programStart', this.currentProgram);
  }

  public unloadChannel(): void {
    this.stopSyncTimer();
    this.config = null;
    this.index = null;
    this.isActive = false;
    this.currentProgram = null;
    this.nextProgram = null;
    this.lastSyncTime = 0;
  }

  public pauseSyncTimer(): void {
    this.stopSyncTimer();
  }

  public resumeSyncTimer(): void {
    if (!this.isActive || !this.config || !this.index || this.syncTimerState.interval !== null) {
      return;
    }
    this.startSyncTimer();
  }

  public getProgramAtTime(time: number): ScheduledProgram {
    return this.getProgramAtTimeForCurrentTime(time, this.clock.now());
  }

  public getCurrentProgram(): ScheduledProgram {
    const now = this.clock.now();
    return this.getProgramAtTimeForCurrentTime(now, now);
  }

  public getNextProgram(): ScheduledProgram {
    const now = this.clock.now();
    const current = this.getProgramAtTimeForCurrentTime(now, now);
    return calculateNextProgram(
      current,
      this.index as ScheduleIndex,
      this.config?.anchorTime ?? 0,
      now,
    );
  }

  public getPreviousProgram(): ScheduledProgram {
    const now = this.clock.now();
    const current = this.getProgramAtTimeForCurrentTime(now, now);
    return calculatePreviousProgram(
      current,
      this.index as ScheduleIndex,
      this.config?.anchorTime ?? 0,
      now,
    );
  }

  public getScheduleWindow(
    startTime: number,
    endTime: number,
    output?: ScheduledProgram[],
  ): ScheduleWindow {
    this.ensureLoaded();
    const now = this.clock.now();

    if (startTime >= endTime) {
      throw new Error(SCHEDULER_ERROR_MESSAGES.INVALID_TIME_RANGE);
    }

    return {
      startTime,
      endTime,
      programs: generateScheduleWindow(
        startTime,
        endTime,
        this.index as ScheduleIndex,
        this.config?.anchorTime ?? 0,
        output,
        now,
      ),
    };
  }

  public getUpcoming(count: number, output?: ScheduledProgram[]): ScheduledProgram[] {
    this.ensureLoaded();
    const now = this.clock.now();

    const programs = output ?? [];
    programs.length = 0;

    if (count <= 0) {
      return programs;
    }

    let current = this.getProgramAtTimeForCurrentTime(now, now);
    programs.push(current);

    for (let index = 1; index < count; index++) {
      current = calculateNextProgram(
        current,
        this.index as ScheduleIndex,
        this.config?.anchorTime ?? 0,
        now,
      );
      programs.push(current);
    }

    return programs;
  }

  public syncToCurrentTime(): void {
    if (!this.isActive || !this.config || !this.index) {
      return;
    }

    const now = this.clock.now();
    this.updateCurrentProgram(this.getProgramAtTimeForCurrentTime(now, now), now);
    this.emitter.emit('scheduleSync', this.getState());
  }

  public isScheduleStale(currentTime: number): boolean {
    if (!this.currentProgram) {
      return true;
    }

    const drift = Math.abs(currentTime - this.lastSyncTime);
    return drift > RESYNC_THRESHOLD_MS;
  }

  public recalculateFromTime(time: number): void {
    if (!this.isActive || !this.config || !this.index) {
      return;
    }

    const now = this.clock.now();
    this.updateCurrentProgram(this.getProgramAtTimeForCurrentTime(time, now), now);
  }

  public jumpToProgram(program: ScheduledProgram): void {
    if (!this.isActive || !this.config || !this.index) {
      return;
    }

    const now = this.clock.now();
    const programPositionInLoop = this.index.itemStartOffsets[program.scheduleIndex] ?? 0;
    const loopOffset = program.loopNumber * this.index.totalLoopDurationMs;
    const programStartFromAnchor = loopOffset + programPositionInLoop;
    const trueElapsed = now - program.scheduledStartTime;
    const isLive = trueElapsed >= 0 && trueElapsed < program.item.durationMs;
    const effectiveElapsed = isLive ? trueElapsed : 0;
    const newAnchorTime = now - effectiveElapsed - programStartFromAnchor;

    this.config = { ...this.config, anchorTime: newAnchorTime };

    if (this.currentProgram) {
      this.emitter.emit('programEnd', this.currentProgram);
    }

    this.currentProgram = this.getProgramAtTimeForCurrentTime(now, now);
    this.nextProgram = calculateNextProgram(
      this.currentProgram,
      this.index,
      this.config.anchorTime,
      now,
    );
    this.lastSyncTime = now;

    this.emitter.emit('programStart', this.currentProgram);
  }

  public skipToNext(): void {
    if (!this.isActive || !this.config || !this.index) {
      return;
    }

    this.jumpToProgram(this.getNextProgram());
  }

  public skipToPrevious(): void {
    if (!this.isActive || !this.config || !this.index) {
      return;
    }

    const previous = this.getPreviousProgram();
    this.jumpToProgram({
      ...previous,
      elapsedMs: 0,
      remainingMs: previous.item.durationMs,
    });
  }

  public getState(): SchedulerState {
    return {
      channelId: this.config?.channelId ?? '',
      isActive: this.isActive,
      currentProgram: this.currentProgram,
      nextProgram: this.nextProgram,
      schedulePosition: {
        loopNumber: this.currentProgram?.loopNumber ?? 0,
        itemIndex: this.currentProgram?.scheduleIndex ?? 0,
        offsetMs: this.currentProgram?.elapsedMs ?? 0,
      },
      lastSyncTime: this.lastSyncTime,
    };
  }

  public getScheduleIndex(): ScheduleIndex {
    this.ensureLoaded();
    return this.index as ScheduleIndex;
  }

  public on(event: 'programStart', handler: (program: ScheduledProgram) => void): void;
  public on(event: 'programEnd', handler: (program: ScheduledProgram) => void): void;
  public on(event: 'scheduleSync', handler: (state: SchedulerState) => void): void;
  public on<K extends keyof SchedulerEventMap>(
    event: K,
    handler: (payload: SchedulerEventMap[K]) => void,
  ): void {
    this.emitter.on(event, handler);
  }

  public off(event: 'programStart', handler: (program: ScheduledProgram) => void): void;
  public off(event: 'programEnd', handler: (program: ScheduledProgram) => void): void;
  public off(event: 'scheduleSync', handler: (state: SchedulerState) => void): void;
  public off<K extends keyof SchedulerEventMap>(
    event: K,
    handler: (payload: SchedulerEventMap[K]) => void,
  ): void {
    this.emitter.off(event, handler);
  }

  private ensureLoaded(): void {
    if (!this.config || !this.index) {
      throw new Error(SCHEDULER_ERROR_MESSAGES.NO_CHANNEL_LOADED);
    }
  }

  private getProgramAtTimeForCurrentTime(time: number, currentTime: number): ScheduledProgram {
    this.ensureLoaded();
    return calculateProgramAtTime(
      time,
      this.index as ScheduleIndex,
      this.config?.anchorTime ?? 0,
      currentTime,
    );
  }

  private updateCurrentProgram(newProgram: ScheduledProgram, currentTime = this.clock.now()): boolean {
    const programChanged =
      this.currentProgram !== null &&
      (newProgram.scheduledStartTime !== this.currentProgram.scheduledStartTime ||
        newProgram.scheduledEndTime !== this.currentProgram.scheduledEndTime);

    if (programChanged) {
      this.emitter.emit('programEnd', this.currentProgram as ScheduledProgram);
      this.emitter.emit('programStart', newProgram);
    }

    this.currentProgram = newProgram;
    this.nextProgram = calculateNextProgram(
      newProgram,
      this.index as ScheduleIndex,
      this.config?.anchorTime ?? 0,
      currentTime,
    );
    this.lastSyncTime = currentTime;

    return programChanged;
  }

  private startSyncTimer(): void {
    if (!this.timers) {
      return;
    }

    this.syncTimerState.expectedNextTick = this.clock.now() + SYNC_INTERVAL_MS;
    this.syncTimerState.interval = this.timers.setInterval(() => {
      const now = this.clock.now();
      const drift = now - this.syncTimerState.expectedNextTick;

      if (Math.abs(drift) < this.syncTimerState.maxDriftMs) {
        this.syncToCurrentTime();
        this.syncTimerState.expectedNextTick = now + SYNC_INTERVAL_MS;
        return;
      }

      if (drift > this.syncTimerState.resyncThreshold) {
        this.hardResync();
        this.syncTimerState.expectedNextTick = now + SYNC_INTERVAL_MS;
        return;
      }

      this.syncToCurrentTime();
      if (drift > 0) {
        const adjustment = Math.min(drift, 100);
        this.syncTimerState.expectedNextTick = now + SYNC_INTERVAL_MS - adjustment;
      } else {
        this.syncTimerState.expectedNextTick = now + SYNC_INTERVAL_MS;
      }
    }, SYNC_INTERVAL_MS);
  }

  private stopSyncTimer(): void {
    if (this.syncTimerState.interval !== null && this.timers) {
      this.timers.clearInterval(this.syncTimerState.interval);
    }
    this.syncTimerState.interval = null;
  }

  private hardResync(): void {
    if (!this.config || !this.index) {
      return;
    }

    const now = this.clock.now();
    const previousCurrent = this.currentProgram;
    this.updateCurrentProgram(this.getProgramAtTimeForCurrentTime(now, now), now);

    const previousEndTime = previousCurrent ? previousCurrent.scheduledEndTime : now;
    this.emitter.emit('scheduleSync', {
      ...this.getState(),
      wasHardResync: true,
      detectedDriftMs: now - previousEndTime,
    });
  }
}
