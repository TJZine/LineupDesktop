import test from 'node:test';
import assert from 'node:assert/strict';
import { PlaybackMediaDetailPort } from '../../main/plex/playbackMediaDetailPort.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';

test('PlaybackMediaDetailPort rejects an empty raw rating key before transport', async () => {
  const mockRuntime = {
    async withActiveLibraryContext() {
      throw new Error('should not be called');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ ratingKey: '   ' });
  assert.equal(result, null);
});

test('PlaybackMediaDetailPort returns null if connection/token is missing', async () => {
  const mockRuntime = {
    async withActiveLibraryContext() {
      throw new Error('missing context');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ ratingKey: '123' });
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
    async withActiveLibraryContext(
      _operation: 'getMetadata',
      run: (context: {
        connection: { uri: string };
        token: string;
        transport: typeof mockTransport;
      }) => Promise<unknown>,
    ) {
      return run({
        connection: { uri: 'http://localhost' },
        token: 'token',
        transport: mockTransport,
      });
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ ratingKey: '123' });
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
    async withActiveLibraryContext(
      _operation: 'getMetadata',
      run: (context: {
        connection: { uri: string };
        token: string;
        transport: typeof mockTransport;
      }) => Promise<unknown>,
    ) {
      return run({
        connection: { uri: 'http://localhost' },
        token: 'token',
        transport: mockTransport,
      });
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackMediaDetailPort(mockRuntime);
  const result = await port.getMediaDetail({ ratingKey: '123' });
  assert.equal(result, null);
});
