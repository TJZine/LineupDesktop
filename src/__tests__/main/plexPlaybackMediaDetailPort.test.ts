import test from 'node:test';
import assert from 'node:assert/strict';
import { PlaybackMediaDetailPort } from '../../main/plex/playbackMediaDetailPort.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';

test('PlaybackMediaDetailPort returns null for non-plex media ID', async () => {
  const mockRuntime = {
    getActiveConnectionAndToken() {
      return { connection: {}, token: 'token' };
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ mediaId: 'other-id' });
  assert.equal(result, null);
});

test('PlaybackMediaDetailPort returns null if connection/token is missing', async () => {
  const mockRuntime = {
    getActiveConnectionAndToken() {
      return { connection: null, token: null };
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ mediaId: 'plex-media-123' });
  assert.equal(result, null);
});

test('PlaybackMediaDetailPort fetches and parses metadata', async () => {
  const rawItem = {
    ratingKey: '123',
    key: '/library/metadata/123',
    type: 'episode',
    title: 'Test Episode',
    summary: 'Test Summary',
    year: 2026,
    duration: 1800000,
    addedAt: 1700000000,
    updatedAt: 1700000100,
    Media: [
      {
        id: 'media-1',
        duration: 1800000,
        Part: [
          {
            id: 'part-1',
            key: '/library/parts/123',
            file: 'test.mkv',
            size: 1000,
            container: 'mkv',
            Stream: [],
          },
        ],
      },
    ],
  };

  const mockTransport = {
    async getMetadata() {
      return {
        kind: 'json' as const,
        data: {
          MediaContainer: {
            Metadata: [rawItem],
          },
        },
      };
    },
  };

  const mockRuntime = {
    getActiveConnectionAndToken() {
      return {
        connection: { uri: 'http://localhost' },
        token: 'token',
      };
    },
    getLibraryTransport() {
      return mockTransport;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ mediaId: 'plex-media-123' });
  assert.ok(result);
  assert.equal(result.ratingKey, '123');
  assert.equal(result.title, 'Test Episode');
  assert.equal(result.media.length, 1);
  assert.equal(result.media[0]?.parts.length, 1);
});

test('PlaybackMediaDetailPort returns null on transport error', async () => {
  const mockTransport = {
    async getMetadata() {
      throw new Error('network error');
    },
  };

  const mockRuntime = {
    getActiveConnectionAndToken() {
      return {
        connection: { uri: 'http://localhost' },
        token: 'token',
      };
    },
    getLibraryTransport() {
      return mockTransport;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ mediaId: 'plex-media-123' });
  assert.equal(result, null);
});
