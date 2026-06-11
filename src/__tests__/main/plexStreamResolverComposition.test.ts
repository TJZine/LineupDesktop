import test from 'node:test';
import assert from 'node:assert/strict';
import {
  PlaybackSelectedConnectionPort,
  PlaybackActiveCredentialPort,
  createLivePlexStreamResolverComposition,
} from '../../main/plex/streamResolverComposition.js';
import type { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';

test('PlaybackSelectedConnectionPort returns connection from runtime', async () => {
  const connection = {
    uri: 'https://plex.local',
    protocol: 'https' as const,
    address: 'plex.local',
    port: 32400,
    local: true,
    relay: false,
    latencyMs: null,
  };
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return connection;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackSelectedConnectionPort(mockRuntime);
  const result = await port.getSelectedConnection();
  assert.deepEqual(result, connection);
});

test('PlaybackSelectedConnectionPort returns null if no connection', async () => {
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return null;
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackSelectedConnectionPort(mockRuntime);
  const result = await port.getSelectedConnection();
  assert.equal(result, null);
});

test('PlaybackActiveCredentialPort returns credentials from runtime', async () => {
  const mockRuntime = {
    async withActivePlexToken(
      _operation: 'getMetadata',
      run: (token: string) => Promise<unknown>,
    ) {
      return run('secret-token');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackActiveCredentialPort(mockRuntime);
  const result = await port.getActiveAuthHeader();
  assert.deepEqual(result, {
    name: 'X-Plex-Token',
    value: 'secret-token',
  });
});

test('PlaybackActiveCredentialPort returns null if no token', async () => {
  const mockRuntime = {
    async withActivePlexToken() {
      throw new Error('missing token');
    },
  } as unknown as DesktopPlexRuntime;

  const port = new PlaybackActiveCredentialPort(mockRuntime);
  const result = await port.getActiveAuthHeader();
  assert.equal(result, null);
});

test('createLivePlexStreamResolverComposition instantiates resolver and pms session port', () => {
  const mockRuntime = {
    getSelectedConnectionForMain() {
      return null;
    },
    async withActivePlexToken() {
      throw new Error('missing token');
    },
    async withActiveLibraryContext() {
      throw new Error('missing context');
    },
    getLibraryTransport() {
      return {};
    },
  } as unknown as DesktopPlexRuntime;

  const composition = createLivePlexStreamResolverComposition(mockRuntime);
  assert.ok(composition.resolver);
  assert.ok(composition.pmsSessionPort);
});
