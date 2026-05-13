/** Scheduler tick interval used to compare expected and observed timer wakeups. */
export const SYNC_INTERVAL_MS = 1000;

/** Soft drift threshold below which the scheduler syncs without hard resync. */
export const MAX_DRIFT_MS = 500;

/** Hard resync threshold for late timer wakeups that exceed normal adjustment. */
export const RESYNC_THRESHOLD_MS = 2000;

export const SCHEDULER_ERROR_MESSAGES = {
  EMPTY_CHANNEL: 'Cannot schedule empty channel',
  NO_CHANNEL_LOADED: 'No channel loaded',
  INVALID_TIME_RANGE: 'Invalid time range: start must be before end',
  INVALID_SCHEDULE_DURATION: 'Schedule has zero total duration - all items have durationMs 0',
  INVALID_ITEM_DURATION: 'Schedule items must have a positive integer durationMs',
  CLOCK_REQUIRED: 'ChannelScheduler requires an injected SchedulerClock',
  RANDOM_MODE_UNSUPPORTED: 'Random mode must be resolved upstream - pass shuffle with a fresh seed instead',
} as const;
