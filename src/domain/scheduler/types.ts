export type PlaybackMode = 'sequential' | 'shuffle' | 'block' | 'random';

export type SchedulerPlaybackMode = Exclude<PlaybackMode, 'random'>;

export type SchedulerMediaType = 'movie' | 'episode';

export type StreamDescriptor = unknown;

export interface ResolvedContentItem {
  ratingKey: string;
  type: SchedulerMediaType;
  title: string;
  fullTitle: string;
  durationMs: number;
  thumb: string | null;
  year: number | null;
  scheduledIndex: number;
  showTitle?: string;
  showThumb?: string;
  seasonNumber?: number;
  episodeNumber?: number;
}

export interface ResolvedChannelContent {
  channelId: string;
  items: ResolvedContentItem[];
  resolvedAt: number;
}

export interface ScheduleConfig {
  channelId: string;
  anchorTime: number;
  content: ResolvedContentItem[];
  playbackMode: SchedulerPlaybackMode;
  shuffleSeed: number;
  blockSize?: number;
}

export interface ScheduledProgram {
  item: ResolvedContentItem;
  scheduledStartTime: number;
  scheduledEndTime: number;
  elapsedMs: number;
  remainingMs: number;
  scheduleIndex: number;
  loopNumber: number;
  streamDescriptor: StreamDescriptor | null;
  isCurrent: boolean;
}

export interface ScheduleWindow {
  startTime: number;
  endTime: number;
  programs: ScheduledProgram[];
}

export interface ScheduleIndex {
  channelId: string;
  generatedAt: number;
  totalLoopDurationMs: number;
  itemStartOffsets: number[];
  orderedItems: ResolvedContentItem[];
}

export interface SchedulerState {
  channelId: string;
  isActive: boolean;
  currentProgram: ScheduledProgram | null;
  nextProgram: ScheduledProgram | null;
  schedulePosition: {
    loopNumber: number;
    itemIndex: number;
    offsetMs: number;
  };
  lastSyncTime: number;
  wasHardResync?: boolean;
  detectedDriftMs?: number;
}

export interface SchedulerClock {
  now(): number;
}

export type SchedulerTimerHandle = unknown;

export interface SchedulerTimerPort {
  setInterval(handler: () => void, intervalMs: number): SchedulerTimerHandle;
  clearInterval(handle: SchedulerTimerHandle): void;
}

export interface SyncTimerState {
  expectedNextTick: number;
  maxDriftMs: number;
  resyncThreshold: number;
  interval: SchedulerTimerHandle | null;
}

export interface SchedulerEventMap {
  programStart: ScheduledProgram;
  programEnd: ScheduledProgram;
  scheduleSync: SchedulerState;
}
