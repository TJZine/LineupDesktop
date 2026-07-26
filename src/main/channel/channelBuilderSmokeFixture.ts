import type {
  ChannelAggregate,
  ChannelAggregateMutationRequest,
  ChannelAggregateMutationResult,
  ChannelPersistenceStoragePort,
} from '../../domain/channel/channelPersistenceStore.js';
import type { StoredChannelData } from '../../domain/channel/types.js';
import type {
  ChannelBuilderFacetAccessInput,
  ChannelBuilderFacetSession,
} from '../plex/channelBuilderFacetSession.js';
import type {
  DesktopPlexBuilderContextListener,
  DesktopPlexBuilderContextResult,
} from '../plex/desktopPlexContextNotifications.js';
import type { ChannelBuilderPlexContextSource } from './channelBuilderContextEpochOwner.js';
import {
  isSmokeBootstrapCapability,
  type SmokeBootstrapCapability,
} from '../smokeBootstrapOwner.js';

export type ChannelBuilderSmokeFixture = Readonly<{
  storage: ChannelPersistenceStoragePort;
  contextSource: ChannelBuilderPlexContextSource;
}>;

const context: DesktopPlexBuilderContextResult = Object.freeze({
  ok: true,
  snapshot: Object.freeze({
    activeProfileId: 'smoke-profile',
    selectedServerId: 'smoke-server',
    libraryPairs: Object.freeze([
      Object.freeze({ libraryId: 'smoke-library', libraryUuid: 'smoke-library-uuid' }),
    ]),
  }),
});

export function createChannelBuilderSmokeFixture(
  capability: SmokeBootstrapCapability,
): ChannelBuilderSmokeFixture {
  if (!isSmokeBootstrapCapability(capability)) {
    throw new TypeError('A validated smoke capability is required.');
  }
  return Object.freeze({
    storage: new SmokeMemoryStorage(),
    contextSource: new SmokeContextSource(),
  });
}

class SmokeContextSource implements ChannelBuilderPlexContextSource {
  public getBuilderContextForMain(): DesktopPlexBuilderContextResult {
    return context;
  }

  public subscribeBuilderContextForMain(
    listener: DesktopPlexBuilderContextListener,
  ): () => void {
    listener({ kind: 'initial', revision: 0, result: context });
    return () => undefined;
  }

  public async withChannelBuilderFacetSession<T>(
    input: ChannelBuilderFacetAccessInput,
    run: (session: ChannelBuilderFacetSession) => Promise<T>,
  ): Promise<T> {
    if (input.signal.aborted) throw new Error('Smoke builder operation was canceled.');
    return run(smokeSession);
  }
}

const smokeItems = Object.freeze(
  Array.from({ length: 6 }, (_, index) => Object.freeze({
    ratingKey: `smoke-item-${index + 1}`,
    key: `/library/metadata/smoke-item-${index + 1}`,
    type: 'movie' as const,
    title: `Smoke Item ${index + 1}`,
    sortTitle: `Smoke Item ${index + 1}`,
    summary: '',
    year: 2020 + index,
    durationMs: 60_000,
    addedAt: new Date(1_000 + index),
    updatedAt: new Date(1_000 + index),
    thumb: null,
    art: null,
    media: [],
  })),
);

const smokeSessionValue: ChannelBuilderFacetSession = {
  libraries: Object.freeze([Object.freeze({
    id: 'smoke-library',
    uuid: 'smoke-library-uuid',
    title: 'Smoke Library',
    type: 'movie' as const,
    agent: '',
    scanner: '',
    contentCount: smokeItems.length,
    lastScannedAt: new Date(0),
    art: null,
    thumb: null,
  })]),
  listCollectionsPage: async (request) => ({
    entries: [],
    offset: request.offset,
    totalSize: 0,
  }),
  listServerPlaylistsPage: async (request) => ({
    entries: [],
    offset: request.offset,
    totalSize: 0,
  }),
  listTagDirectoryPage: async (request) => ({
    entries: [],
    offset: request.offset,
    totalSize: 0,
  }),
  listLibraryItemsPage: async (request) => ({
    entries: request.offset === 0 ? [...smokeItems] : [],
    offset: request.offset,
    totalSize: smokeItems.length,
  }),
};
const smokeSession: ChannelBuilderFacetSession = Object.freeze(smokeSessionValue);

class SmokeMemoryStorage implements ChannelPersistenceStoragePort {
  private aggregate: ChannelAggregate = {
    storedChannelData: null,
    currentChannelId: null,
    lineupRevision: 0,
    channelBuilderState: null,
  };

  public async readStoredChannelData(): Promise<string | null> {
    return this.aggregate.storedChannelData === null
      ? null
      : JSON.stringify(this.aggregate.storedChannelData);
  }

  public async writeStoredChannelData(encoded: string): Promise<void> {
    this.aggregate = {
      ...this.aggregate,
      storedChannelData: JSON.parse(encoded) as StoredChannelData,
    };
  }

  public async clearStoredChannelData(): Promise<void> {
    this.aggregate = { ...this.aggregate, storedChannelData: null, currentChannelId: null };
  }

  public async readCurrentChannelId(): Promise<string | null> {
    return this.aggregate.currentChannelId;
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    this.aggregate = { ...this.aggregate, currentChannelId: channelId };
  }

  public async readChannelAggregate(): Promise<ChannelAggregate> {
    return this.aggregate;
  }

  public async mutateChannelAggregate(
    request: ChannelAggregateMutationRequest,
  ): Promise<ChannelAggregateMutationResult> {
    if (
      request.kind === 'builder-lineup' &&
      request.expectedLineupRevision !== this.aggregate.lineupRevision
    ) {
      return { status: 'conflict', actualLineupRevision: this.aggregate.lineupRevision };
    }
    if (request.onCommitBarrier() === 'cancel') return { status: 'canceled' };
    this.aggregate = request.mutate(this.aggregate);
    return { status: 'committed', aggregate: this.aggregate };
  }
}
