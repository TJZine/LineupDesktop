import type {
  ChannelConfig,
  ChannelCreateInput,
  ChannelManagerEventMap,
  ChannelUpdateInput,
  DomainPlexMediaType,
  ImportResult,
  ResolvedChannelContent,
  ResolvedContentItem,
  StoredChannelData,
} from './types.js';

export interface DomainDisposable {
  dispose(): void;
}

export interface ChannelClock {
  now(): number;
}

export type ChannelTimerHandle = unknown;

export interface ChannelTimerPort {
  setTimeout(handler: () => void, delayMs: number): ChannelTimerHandle;
  clearTimeout(handle: ChannelTimerHandle): void;
}

export interface ChannelLogger {
  warn(message: string, detail?: unknown): void;
  error(message: string, detail?: unknown): void;
}

export interface ChannelAbortSignal {
  readonly aborted: boolean;
  addEventListener?(event: 'abort', handler: () => void, options?: { once?: boolean }): void;
  removeEventListener?(event: 'abort', handler: () => void): void;
}

export interface ChannelResolveOptions {
  signal?: ChannelAbortSignal | null;
}

export interface IChannelManager {
  createChannel(config: ChannelCreateInput, options?: ChannelCreateOptions): Promise<ChannelConfig>;
  updateChannel(id: string, updates: ChannelUpdateInput): Promise<ChannelConfig>;
  deleteChannel(id: string): Promise<void>;
  getChannel(id: string): ChannelConfig | null;
  getAllChannels(): ChannelConfig[];
  getChannelByNumber(number: number): ChannelConfig | null;
  resolveChannelContent(
    channelId: string,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedChannelContent>;
  refreshChannelContent(
    channelId: string,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedChannelContent>;
  resolveChannelItemsForSchedule(
    channelId: string,
    options?: ChannelResolveOptions,
  ): Promise<ResolvedContentItem[]>;
  reorderChannels(orderedIds: string[]): Promise<void>;
  setCurrentChannel(channelId: string): void;
  getCurrentChannel(): ChannelConfig | null;
  getNextChannel(): ChannelConfig | null;
  getPreviousChannel(): ChannelConfig | null;
  exportChannels(): string;
  importChannels(data: string): Promise<ImportResult>;
  saveChannels(): Promise<void>;
  flushSaves(): Promise<void>;
  dispose(): void;
  loadChannels(): Promise<void>;
  replaceAllChannels(
    channels: ChannelConfig[],
    options?: { currentChannelId?: string | null },
  ): Promise<void>;
  on<K extends keyof ChannelManagerEventMap>(
    event: K,
    handler: (payload: ChannelManagerEventMap[K]) => void,
  ): DomainDisposable;
}

export interface ChannelCreateOptions extends ChannelResolveOptions {
  initialContent?: ReadonlyArray<ResolvedContentItem> | undefined;
}

export interface ChannelManagerConfig {
  plexLibrary: IPlexLibraryMinimal;
  clock: ChannelClock;
  generateId: () => string;
  timers?: ChannelTimerPort;
  logger?: ChannelLogger;
  persistence?: ChannelPersistencePort;
}

export interface ChannelPersistencePort {
  load(): Promise<StoredChannelData | null>;
  save(data: StoredChannelData): Promise<void>;
  queueSave?(data: StoredChannelData): void;
  flush?(data?: StoredChannelData): Promise<void>;
  dispose?(): void;
}

export interface IPlexLibraryMinimal {
  getLibraryItems(
    libraryId: string,
    options?: {
      includeCollections?: boolean;
      filter?: Record<string, string | number>;
      signal?: ChannelAbortSignal | null;
    },
  ): Promise<PlexMediaItemMinimal[]>;
  getCollectionItems(
    collectionKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]>;
  getShowEpisodes(
    showKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]>;
  getPlaylistItems(
    playlistKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal[]>;
  getItem(
    ratingKey: string,
    options?: ChannelResolveOptions,
  ): Promise<PlexMediaItemMinimal | null>;
}

export interface DomainPlexMediaStream {
  streamType?: number;
  codec?: string;
  channels?: number;
  title?: string;
  language?: string;
  languageCode?: string;
  selected?: boolean;
  default?: boolean;
  profile?: string;
  doviProfile?: string;
  colorTrc?: string;
  colorSpace?: string;
  colorPrimaries?: string;
  displayTitle?: string;
  extendedDisplayTitle?: string;
}

export interface DomainPlexMediaPart {
  streams?: DomainPlexMediaStream[];
}

export interface DomainPlexMediaFile {
  videoResolution?: string;
  audioCodec?: string;
  audioChannels?: number;
  parts?: DomainPlexMediaPart[];
}

export interface PlexMediaItemMinimal {
  ratingKey: string;
  type: DomainPlexMediaType;
  title: string;
  year: number;
  durationMs: number;
  thumb: string | null;
  art?: string | null;
  grandparentThumb?: string | null;
  summary?: string;
  media?: DomainPlexMediaFile[];
  grandparentTitle?: string;
  parentTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  rating?: number;
  contentRating?: string;
  genres?: string[];
  directors?: string[];
  addedAtMs?: number;
  viewCount?: number;
  clearLogo?: string | null;
  grandparentRatingKey?: string;
  parentRatingKey?: string;
}
