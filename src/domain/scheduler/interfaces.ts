import type {
  ScheduleConfig,
  ScheduleIndex,
  ScheduledProgram,
  SchedulerState,
  ScheduleWindow,
} from './types.js';

export interface IShuffleGenerator {
  shuffle<T>(items: T[], seed: number): T[];

  shuffleIndices(count: number, seed: number): number[];

  generateSeed(channelId: string, anchorTime: number): number;
}

export interface IChannelScheduler {
  loadChannel(config: ScheduleConfig): void;

  unloadChannel(): void;

  pauseSyncTimer(): void;

  resumeSyncTimer(): void;

  getProgramAtTime(time: number): ScheduledProgram;

  getCurrentProgram(): ScheduledProgram;

  getNextProgram(): ScheduledProgram;

  getPreviousProgram(): ScheduledProgram;

  getScheduleWindow(
    startTime: number,
    endTime: number,
    output?: ScheduledProgram[],
  ): ScheduleWindow;

  getUpcoming(count: number, output?: ScheduledProgram[]): ScheduledProgram[];

  syncToCurrentTime(): void;

  isScheduleStale(currentTime: number): boolean;

  recalculateFromTime(time: number): void;

  jumpToProgram(program: ScheduledProgram): void;

  skipToNext(): void;

  skipToPrevious(): void;

  getState(): SchedulerState;

  getScheduleIndex(): ScheduleIndex;

  on(event: 'programStart', handler: (program: ScheduledProgram) => void): void;

  on(event: 'programEnd', handler: (program: ScheduledProgram) => void): void;

  on(event: 'scheduleSync', handler: (state: SchedulerState) => void): void;

  off(event: 'programStart', handler: (program: ScheduledProgram) => void): void;

  off(event: 'programEnd', handler: (program: ScheduledProgram) => void): void;

  off(event: 'scheduleSync', handler: (state: SchedulerState) => void): void;
}
