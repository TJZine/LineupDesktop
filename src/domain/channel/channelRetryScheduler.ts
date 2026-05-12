import { CHANNEL_RETRY_DELAY_MS } from './constants.js';
import type { ChannelClock, ChannelLogger, ChannelTimerHandle, ChannelTimerPort } from './interfaces.js';
import type { ChannelConfig } from './types.js';

type ChannelRetrySchedulerConfig = {
  getChannel: (channelId: string) => ChannelConfig | null;
  resolve: (channel: ChannelConfig, isCurrent: () => boolean) => Promise<unknown>;
  logger: ChannelLogger;
  timers?: ChannelTimerPort;
  clock: ChannelClock;
};

type PendingRetry = {
  timeout: ChannelTimerHandle;
  generation: number;
  queuedAt: number;
};

export class ChannelRetryScheduler {
  private readonly getChannel: (channelId: string) => ChannelConfig | null;
  private readonly resolve: (channel: ChannelConfig, isCurrent: () => boolean) => Promise<unknown>;
  private readonly logger: ChannelLogger;
  private readonly timers: ChannelTimerPort | null;
  private readonly clock: ChannelClock;
  private readonly pendingRetries = new Map<string, PendingRetry>();
  private generation = 0;

  public constructor(config: ChannelRetrySchedulerConfig) {
    this.getChannel = config.getChannel;
    this.resolve = config.resolve;
    this.logger = config.logger;
    this.timers = config.timers ?? null;
    this.clock = config.clock;
  }

  public queue(channelId: string): void {
    if (!this.timers || this.pendingRetries.has(channelId)) {
      return;
    }

    const generation = this.generation;
    const timeout = this.timers.setTimeout(() => {
      this.pendingRetries.delete(channelId);
      void this.execute(channelId, generation);
    }, CHANNEL_RETRY_DELAY_MS);

    this.pendingRetries.set(channelId, { timeout, generation, queuedAt: this.clock.now() });
  }

  public cancel(channelId: string): void {
    const pendingRetry = this.pendingRetries.get(channelId);
    if (!pendingRetry || !this.timers) {
      return;
    }
    this.timers.clearTimeout(pendingRetry.timeout);
    this.pendingRetries.delete(channelId);
  }

  public cancelAll(): void {
    this.generation += 1;
    if (this.timers) {
      for (const pendingRetry of this.pendingRetries.values()) {
        this.timers.clearTimeout(pendingRetry.timeout);
      }
    }
    this.pendingRetries.clear();
  }

  public hasPendingRetry(channelId: string): boolean {
    return this.pendingRetries.has(channelId);
  }

  private async execute(channelId: string, generation: number): Promise<void> {
    const isCurrent = (): boolean => generation === this.generation;
    if (!isCurrent()) return;

    const channel = this.getChannel(channelId);
    if (!channel) return;

    try {
      await this.resolve(channel, isCurrent);
      if (!isCurrent()) return;
      this.logger.warn(`Retry succeeded for channel ${channelId}`);
    } catch (error) {
      if (!isCurrent()) return;
      this.logger.warn(`Retry failed for channel ${channelId}`, summarizeError(error));
    }
  }
}

function summarizeError(error: unknown): unknown {
  if (error instanceof Error) {
    return { name: error.name, message: error.message };
  }
  return error;
}
