import { ChannelError } from './channelError.js';
import { cloneChannelForOwnership } from './channelDomainClone.js';
import { ChannelPersistenceSaveQueue } from './channelPersistenceSaveQueue.js';
import type { ChannelRepository, LoadedChannelState } from './channelRepository.js';
import type {
  ChannelClock,
  ChannelLogger,
  ChannelPersistencePort,
  ChannelTimerPort,
} from './interfaces.js';
import type { ChannelConfig, ChannelManagerEventMap, StoredChannelData } from './types.js';

export interface ChannelPersistenceCoordinatorConfig {
  repository: ChannelRepository;
  clock: ChannelClock;
  timers: ChannelTimerPort;
  debounceMs: number;
  logger?: ChannelLogger;
  emitPersistenceWarning?: (payload: ChannelManagerEventMap['persistenceWarning']) => void;
}

export interface PersistableChannelState {
  channels: Iterable<ChannelConfig>;
  channelOrder: readonly string[];
  currentChannelId: string | null;
}

export class ChannelPersistenceCoordinator implements ChannelPersistencePort {
  private readonly repository: ChannelRepository;
  private readonly clock: ChannelClock;
  private readonly saveQueue: ChannelPersistenceSaveQueue;

  public constructor(config: ChannelPersistenceCoordinatorConfig) {
    this.repository = config.repository;
    this.clock = config.clock;
    this.saveQueue = new ChannelPersistenceSaveQueue({
      runSave: async () => {
        throw new ChannelError(
          'STORAGE_VALIDATION_FAILED',
          'ChannelPersistenceCoordinator save requires a state snapshot',
        );
      },
      createDisposedError: () => new Error('Channel persistence coordinator disposed'),
      emitPersistenceWarning: config.emitPersistenceWarning ?? (() => undefined),
      logger: config.logger,
      clock: config.clock,
      timers: config.timers,
      debounceMs: config.debounceMs,
    });
  }

  public async load(): Promise<StoredChannelData | null> {
    const loaded = await this.loadNormalized();
    if (loaded === null) {
      return null;
    }
    if (loaded.didMutate) {
      await this.repository.saveStoredChannelData(loaded.data);
    }
    return loaded.data;
  }

  public loadNormalized(): Promise<LoadedChannelState> {
    return this.repository.loadNormalized();
  }

  public queueSave(state: PersistableChannelState): void {
    const snapshot = makeChannelSnapshot(state, this.clock.now());
    this.saveQueue.queueWithSnapshot(() => this.repository.saveStoredChannelData(snapshot));
  }

  public saveState(state: PersistableChannelState): Promise<void> {
    const snapshot = makeChannelSnapshot(state, this.clock.now());
    return this.saveQueue.saveWithSnapshot(() => this.repository.saveStoredChannelData(snapshot));
  }

  public save(data: StoredChannelData): Promise<void> {
    return this.repository.saveStoredChannelData(data);
  }

  public flushState(state: PersistableChannelState): Promise<void> {
    const snapshot = makeChannelSnapshot(state, this.clock.now());
    return this.saveQueue.flushWithSnapshot(() => this.repository.saveStoredChannelData(snapshot));
  }

  public flush(state?: PersistableChannelState): Promise<void> {
    if (state) {
      return this.flushState(state);
    }
    return this.saveQueue.flush();
  }

  public supersedePendingSave(): void {
    this.saveQueue.supersedePendingSave();
  }

  public async persistCurrentChannelIdBestEffort(channelId: string | null): Promise<void> {
    try {
      await this.repository.saveCurrentChannelId(channelId);
    } catch (error) {
      this.saveQueue.reportFailure('Failed to persist current channel', error);
    }
  }

  public dispose(): void {
    this.saveQueue.dispose();
  }
}

function makeChannelSnapshot(state: PersistableChannelState, savedAt: number): StoredChannelData {
  return {
    channels: Array.from(state.channels, cloneChannelForOwnership),
    channelOrder: [...state.channelOrder],
    currentChannelId: state.currentChannelId,
    savedAt,
  };
}
