import test from 'node:test';
import assert from 'node:assert/strict';
import { PlexLibraryMinimalAdapter } from '../../main/channel/plexLibraryMinimalAdapter.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import { LivePlexTransportError, type LivePlexLibraryTransport } from '../../main/plex/livePlexTransport.js';
import type { PlexConnection } from '../../main/plex/discovery/types.js';
import { PlexLibraryError, type RawMediaItem } from '../../main/plex/library/index.js';

class MockLibraryTransport implements LivePlexLibraryTransport {
  public lastListLibraryItemsInput: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0] | null = null;
  public listLibraryItemsMock: () => ReturnType<LivePlexLibraryTransport['listLibraryItems']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } },
  });
  public listLibrarySectionsMock: () => ReturnType<LivePlexLibraryTransport['listLibrarySections']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Directory: [] } },
  });
  public searchLibraryMock: () => ReturnType<LivePlexLibraryTransport['searchLibrary']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } },
  });
  public getCollectionItemsMock: () => ReturnType<LivePlexLibraryTransport['getCollectionItems']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } },
  });
  public getShowEpisodesMock: () => ReturnType<LivePlexLibraryTransport['getShowEpisodes']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } },
  });
  public getPlaylistItemsMock: () => ReturnType<LivePlexLibraryTransport['getPlaylistItems']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } },
  });
  public getMetadataMock: () => ReturnType<LivePlexLibraryTransport['getMetadata']> = async () => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } },
  });

  async listLibraryItems(
    input: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0],
  ): ReturnType<LivePlexLibraryTransport['listLibraryItems']> {
    this.lastListLibraryItemsInput = input;
    return this.listLibraryItemsMock();
  }
  async listLibrarySections(
    _input: Parameters<LivePlexLibraryTransport['listLibrarySections']>[0],
  ): ReturnType<LivePlexLibraryTransport['listLibrarySections']> {
    return this.listLibrarySectionsMock();
  }
  async searchLibrary(
    _input: Parameters<LivePlexLibraryTransport['searchLibrary']>[0],
  ): ReturnType<LivePlexLibraryTransport['searchLibrary']> {
    return this.searchLibraryMock();
  }
  async getCollectionItems(
    _input: Parameters<LivePlexLibraryTransport['getCollectionItems']>[0],
  ): ReturnType<LivePlexLibraryTransport['getCollectionItems']> {
    return this.getCollectionItemsMock();
  }
  async getShowEpisodes(
    _input: Parameters<LivePlexLibraryTransport['getShowEpisodes']>[0],
  ): ReturnType<LivePlexLibraryTransport['getShowEpisodes']> {
    return this.getShowEpisodesMock();
  }
  async getPlaylistItems(
    _input: Parameters<LivePlexLibraryTransport['getPlaylistItems']>[0],
  ): ReturnType<LivePlexLibraryTransport['getPlaylistItems']> {
    return this.getPlaylistItemsMock();
  }
  async getMetadata(
    _input: Parameters<LivePlexLibraryTransport['getMetadata']>[0],
  ): ReturnType<LivePlexLibraryTransport['getMetadata']> {
    return this.getMetadataMock();
  }
  async stopTranscodeSession(
    _input: Parameters<LivePlexLibraryTransport['stopTranscodeSession']>[0],
  ): Promise<void> {
    // No-op
  }
}

class MockPlexRuntime {
  public connection: PlexConnection = {
    uri: 'http://localhost:32400',
    protocol: 'http',
    address: 'localhost',
    port: 32400,
    local: false,
    relay: false,
    latencyMs: null,
  };
  public token: string | null = 'test-token';
  public transport = new MockLibraryTransport();

  getLibraryTransport(): LivePlexLibraryTransport {
    return this.transport;
  }

  async withActiveLibraryContext<T>(
    _operation: 'listLibraryItems' | 'getMetadata',
    run: (context: {
      connection: PlexConnection;
      token: string;
      transport: LivePlexLibraryTransport;
    }) => Promise<T>,
  ): Promise<T> {
    if (this.token === null) {
      throw new LivePlexTransportError('auth-required', 'Plex authentication is required');
    }
    return run({
      connection: this.connection,
      token: this.token,
      transport: this.transport,
    });
  }
}

function createRawEpisode(overrides: Partial<RawMediaItem> = {}): RawMediaItem {
  return {
    ratingKey: 'episode-1',
    key: 'metadata-key-episode-1',
    type: 'episode',
    title: 'Pilot',
    titleSort: 'Pilot',
    summary: 'A metadata-only episode fixture.',
    year: 2026,
    duration: 1_800_000,
    addedAt: 1_700_000_100,
    updatedAt: 1_700_000_200,
    thumb: 'episode-thumb-key',
    art: 'episode-art-key',
    rating: 8.5,
    contentRating: 'TV-PG',
    grandparentTitle: 'Example Show',
    parentTitle: 'Season 1',
    Media: [
      {
        id: 'media-1',
        duration: 1_800_000,
        bitrate: 4_000,
        width: 1920,
        height: 1080,
        aspectRatio: 1.78,
        videoCodec: 'H264',
        audioCodec: 'AAC',
        audioChannels: 2,
        container: 'MKV',
        videoResolution: '1080',
        Part: [
          {
            id: 'part-1',
            key: 'part-key-1',
            duration: 1_800_000,
            file: 'episode-file.mkv',
            size: 42_000,
            container: 'mkv',
            Stream: [
              {
                id: 'stream-1',
                streamType: 1,
                codec: 'h264',
                displayTitle: '1080p',
              },
            ],
          },
        ],
      },
    ],
    ...overrides,
  };
}

test('PlexLibraryMinimalAdapter getLibraryItems pages and parses items correctly', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);

  let calls = 0;
  runtime.transport.listLibraryItemsMock = async () => {
    calls++;
    if (calls === 1) {
      // Return a page with 50 items to trigger next page
      const metadata = Array.from({ length: 50 }, (_, i) => createRawEpisode({ ratingKey: `ep-${i}` }));
      return { kind: 'json', data: { MediaContainer: { Metadata: metadata } } };
    }
    // Return second page with 2 items to complete pagination
    return {
      kind: 'json',
      data: {
        MediaContainer: {
          Metadata: [
            createRawEpisode({ ratingKey: 'ep-50' }),
            createRawEpisode({ ratingKey: 'ep-51' })
          ]
        }
      }
    };
  };

  const items = await adapter.getLibraryItems('library-1');
  assert.equal(items.length, 52);
  assert.equal(items[0]?.ratingKey, 'ep-0');
  assert.equal(items[51]?.ratingKey, 'ep-51');
  assert.equal(calls, 2);
});

test('PlexLibraryMinimalAdapter maps domain abort signals to transport AbortSignal', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);
  const abortHandlers: Array<() => void> = [];
  const domainSignal = {
    aborted: false,
    addEventListener(event: 'abort', handler: () => void) {
      assert.equal(event, 'abort');
      abortHandlers.push(handler);
    },
  };

  await adapter.getLibraryItems('library-1', { signal: domainSignal });

  const transportSignal = runtime.transport.lastListLibraryItemsInput?.signal;
  assert.ok(transportSignal instanceof AbortSignal);
  assert.equal(transportSignal.aborted, false);
  assert.equal(abortHandlers.length, 1);
  abortHandlers[0]?.();
  assert.equal(transportSignal.aborted, true);
});

test('PlexLibraryMinimalAdapter reports missing Plex credentials as structured transport errors', async () => {
  const runtime = new MockPlexRuntime();
  runtime.token = null;
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);

  await assert.rejects(
    () => adapter.getLibraryItems('library-1'),
    (error) => error instanceof LivePlexTransportError && error.code === 'auth-required',
  );
});

test('PlexLibraryMinimalAdapter guards infinite pagination with structured library error', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);
  runtime.transport.listLibraryItemsMock = async () => ({
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: Array.from({ length: 50 }, (_, i) => createRawEpisode({ ratingKey: `loop-${i}` })),
      },
    },
  });

  await assert.rejects(
    () => adapter.getLibraryItems('library-loop'),
    (error) => error instanceof PlexLibraryError && error.code === 'pagination-limit-exceeded',
  );
});

test('PlexLibraryMinimalAdapter getCollectionItems fetches and parses collection items', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);

  runtime.transport.getCollectionItemsMock = async () => ({
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: [
          createRawEpisode({ ratingKey: 'collection-item-1' })
        ]
      }
    }
  });

  const items = await adapter.getCollectionItems('coll-123');
  assert.equal(items.length, 1);
  assert.equal(items[0]?.ratingKey, 'collection-item-1');
  assert.equal(items[0]?.title, 'Pilot');
  assert.equal(items[0]?.media?.[0]?.videoResolution, '1080');
});

test('PlexLibraryMinimalAdapter getShowEpisodes fetches show episodes', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);

  runtime.transport.getShowEpisodesMock = async () => ({
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: [
          createRawEpisode({ ratingKey: 'show-item-1' })
        ]
      }
    }
  });

  const items = await adapter.getShowEpisodes('show-123');
  assert.equal(items.length, 1);
  assert.equal(items[0]?.ratingKey, 'show-item-1');
});

test('PlexLibraryMinimalAdapter getPlaylistItems fetches playlist items', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);

  runtime.transport.getPlaylistItemsMock = async () => ({
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: [
          createRawEpisode({ ratingKey: 'playlist-item-1' })
        ]
      }
    }
  });

  const items = await adapter.getPlaylistItems('playlist-123');
  assert.equal(items.length, 1);
  assert.equal(items[0]?.ratingKey, 'playlist-item-1');
});

test('PlexLibraryMinimalAdapter getItem fetches single metadata item', async () => {
  const runtime = new MockPlexRuntime();
  const adapter = new PlexLibraryMinimalAdapter(runtime as unknown as DesktopPlexRuntime);

  runtime.transport.getMetadataMock = async () => ({
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: [
          createRawEpisode({ ratingKey: 'item-123' })
        ]
      }
    }
  });

  const item = await adapter.getItem('item-123');
  assert.notEqual(item, null);
  assert.equal(item?.ratingKey, 'item-123');
});
