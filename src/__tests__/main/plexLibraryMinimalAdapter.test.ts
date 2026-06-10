import test from 'node:test';
import assert from 'node:assert/strict';
import { PlexLibraryMinimalAdapter } from '../../main/channel/plexLibraryMinimalAdapter.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import type { LivePlexLibraryTransport } from '../../main/plex/livePlexTransport.js';

class MockLibraryTransport implements Partial<LivePlexLibraryTransport> {
  public listLibraryItemsMock = async (): Promise<any> => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } }
  });
  public getCollectionItemsMock = async (): Promise<any> => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } }
  });
  public getShowEpisodesMock = async (): Promise<any> => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } }
  });
  public getPlaylistItemsMock = async (): Promise<any> => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } }
  });
  public getMetadataMock = async (): Promise<any> => ({
    kind: 'json',
    data: { MediaContainer: { Metadata: [] } }
  });

  async listLibraryItems(input: any): Promise<any> {
    return this.listLibraryItemsMock();
  }
  async getCollectionItems(input: any): Promise<any> {
    return this.getCollectionItemsMock();
  }
  async getShowEpisodes(input: any): Promise<any> {
    return this.getShowEpisodesMock();
  }
  async getPlaylistItems(input: any): Promise<any> {
    return this.getPlaylistItemsMock();
  }
  async getMetadata(input: any): Promise<any> {
    return this.getMetadataMock();
  }
}

class MockPlexRuntime {
  public connection: any = { uri: 'http://localhost:32400' };
  public token: string | null = 'test-token';
  public transport = new MockLibraryTransport();

  getActiveConnectionAndToken() {
    return { connection: this.connection, token: this.token };
  }

  getLibraryTransport() {
    return this.transport as unknown as LivePlexLibraryTransport;
  }
}

function createRawEpisode(overrides: Record<string, any> = {}): Record<string, any> {
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
