import type { IpcMainInvokeEvent } from 'electron';

import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import {
  DesktopPlexAuthService,
  type DesktopPlexAuthTransport,
  type DesktopPlexAuthTransportRequest,
  type DesktopPlexAuthTransportResponse,
  type SaveDesktopPlexAccountCredentialInput,
} from './auth/index.js';
import {
  createPlexApiResource,
  DesktopPlexServerDiscovery,
  type DesktopPlexConnectionProbeTransportResult,
  type DesktopPlexDiscoveryTransport,
  type PlexConnection,
  type PlexServer,
  type PlexServerSelectionSource,
} from './discovery/index.js';
import { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import { LivePlexTransportError, type LivePlexChannelSetupTransport } from './livePlexTransport.js';
import { registerPlexIpcHandlers } from './plexIpc.js';

const SYNTHETIC_ACCOUNT_ID = 'proof-account';
const SYNTHETIC_SERVER_ID = 'proof-server';
const SYNTHETIC_SECRET = 'synthetic-proof-value';

export async function registerChannelSetupProofPlexComposition(input: {
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  diagnosticEventStore?: DiagnosticEventStore;
}): Promise<{ runtime: DesktopPlexRuntime; teardown(): Promise<void> }> {
  const authTransport = new SyntheticAuthTransport();
  const credentialStore = new SyntheticCredentialStore();
  const discoveryTransport = new SyntheticDiscoveryTransport();
  const selectedServerStore = new SyntheticSelectedServerStore();
  const serverDiscovery = new DesktopPlexServerDiscovery({
    transport: discoveryTransport,
    selectedServerStore,
  });
  const libraryTransport = new SyntheticLibraryTransport();
  const authService = new DesktopPlexAuthService({
    config: {
      clientIdentifier: 'proof-client', product: 'Lineup Desktop', version: '0.0.0',
      platform: 'Desktop', platformVersion: 'proof', device: 'Desktop', deviceName: 'Lineup Desktop',
    },
    transport: authTransport,
    credentialStore,
    pollIntervalMs: 1,
  });
  const runtime = new DesktopPlexRuntime({
    authService,
    credentialStore,
    serverDiscovery,
    libraryTransport,
    diagnosticEventStore: input.diagnosticEventStore,
  });

  await runtime.requestPin('proof-request-pin');
  await runtime.pollPin('proof-poll-pin', 41);
  await runtime.refreshServers('proof-refresh-servers');
  await runtime.selectServer('proof-select-server', SYNTHETIC_SERVER_ID);

  const teardownIpc = registerPlexIpcHandlers({
    runtime,
    isAuthorizedEvent: input.isAuthorizedEvent,
    createRequestId: input.createRequestId,
  });
  return { runtime, teardown: teardownIpc };
}

class SyntheticAuthTransport implements DesktopPlexAuthTransport {
  async request(input: DesktopPlexAuthTransportRequest): Promise<DesktopPlexAuthTransportResponse> {
    if (input.action === 'request-pin') {
      return { status: 201, payload: json({ id: 41, code: 'SAFE', expiresAt: '2099-01-01T00:00:00.000Z' }) };
    }
    if (input.action === 'check-pin-status') {
      return { status: 200, payload: json({ id: 41, code: 'SAFE', expiresAt: '2099-01-01T00:00:00.000Z', authToken: SYNTHETIC_SECRET }) };
    }
    if (input.action === 'validate-token') {
      return { status: 200, payload: json({ id: SYNTHETIC_ACCOUNT_ID, username: 'Proof Viewer', email: 'proof@example.invalid' }) };
    }
    throw new Error('Unexpected synthetic authentication operation.');
  }
}

class SyntheticCredentialStore {
  private profile: { accountId: string; username?: string; displayName?: string } | null = null;
  private secretValue: string | null = null;

  async saveAccountCredential(input: SaveDesktopPlexAccountCredentialInput) {
    this.profile = input.profile ?? { accountId: input.accountId };
    this.secretValue = input.secretValue;
    return {
      ok: true as const,
      profile: this.profile,
      credentialHandle: {
        credentialId: `plex-account:${input.accountId}`,
        accountId: input.accountId,
        kind: 'plex-account' as const,
        createdAtMs: 1,
        updatedAtMs: 1,
      },
      diagnostics: [],
    };
  }

  async readDefaultAccountCredentialSecret() {
    if (this.profile === null || this.secretValue === null) {
      return { status: 'missing' as const, accountId: null, diagnostics: [] };
    }
    return {
      status: 'present' as const,
      accountId: this.profile.accountId,
      credentialId: `plex-account:${this.profile.accountId}`,
      secretValue: this.secretValue,
      profile: this.profile,
      shouldReencrypt: false,
      diagnostics: [],
    };
  }
}

class SyntheticDiscoveryTransport implements DesktopPlexDiscoveryTransport {
  async discoverResources(): Promise<unknown> {
    return [createPlexApiResource({
      clientIdentifier: SYNTHETIC_SERVER_ID,
      name: 'Proof Server',
      connections: [syntheticConnection()],
    })];
  }

  async probeConnection(): Promise<DesktopPlexConnectionProbeTransportResult> {
    return { outcome: 'reachable', latencyMs: 1 };
  }
}

class SyntheticSelectedServerStore {
  private persisted: { serverId: string; name: string; source: PlexServerSelectionSource; lastSelectedAtMs: number } | null = null;

  async readSelectedServerSummary() { return this.persisted; }

  async saveSelectedServerSummary(server: PlexServer, source: PlexServerSelectionSource) {
    this.persisted = { serverId: server.id, name: server.name, source, lastSelectedAtMs: 1 };
    return this.persisted;
  }
}

class SyntheticLibraryTransport implements LivePlexChannelSetupTransport {
  private failNextFacetLoad = true;

  async listLibrarySections() {
    return json({ MediaContainer: { Directory: [
      syntheticSection('proof-movies', 'Proof Movies', 'movie'),
      syntheticSection('proof-shows', 'Proof Shows', 'show'),
    ] } });
  }

  async listLibraryItems(input: Parameters<LivePlexChannelSetupTransport['listLibraryItems']>[0]) {
    const count = input.sectionId === 'proof-movies' ? 18 : 24;
    return json({ MediaContainer: {
      totalSize: count,
      size: input.limit > 1 ? 2 : 1,
      Metadata: input.limit > 1 ? syntheticTelevisionItems(input.sectionId) : [syntheticMedia(input.sectionId)],
    } });
  }

  async searchLibrary() { return json({ MediaContainer: { Hub: [] } }); }
  async getMetadata() { return json({ MediaContainer: { Metadata: [syntheticMedia('proof-movies')] } }); }
  async getCollectionItems() { return json({ MediaContainer: { Metadata: [] } }); }
  async getShowEpisodes() { return json({ MediaContainer: { Metadata: [] } }); }
  async getPlaylistItems() { return json({ MediaContainer: { Metadata: [] } }); }
  async stopTranscodeSession() { /* Proof transport has no remote session. */ }

  async listVideoPlaylists(input: Parameters<LivePlexChannelSetupTransport['listVideoPlaylists']>[0]) {
    if (this.failNextFacetLoad) {
      this.failNextFacetLoad = false;
      throw new LivePlexTransportError('server-error', 'Synthetic retryable facet failure.');
    }
    await proofDelay(5_000, input.signal ?? null);
    return json({ MediaContainer: { Metadata: [
      { ratingKey: 'proof-playlist', title: 'Proof Playlist', playlistType: 'video', leafCount: 12 },
    ] } });
  }

  async listLibraryTagDirectory(input: Parameters<LivePlexChannelSetupTransport['listLibraryTagDirectory']>[0]) {
    const labels = {
      genre: ['Adventure', 'Comedy'], director: ['Director One'], year: ['1990'],
      actor: ['Performer One'], studio: ['Proof Studio'],
    }[input.family];
    return json({ MediaContainer: { Directory: labels.map((title, index) => ({ key: `${input.family}-${String(index + 1)}`, title, count: 6 })) } });
  }
}

function syntheticConnection(): PlexConnection {
  return { uri: 'https://proof.invalid:32400', protocol: 'https', address: 'proof.invalid', port: 32400, local: true, relay: false, latencyMs: 1 };
}

function syntheticMedia(sectionId: string) {
  return { ratingKey: `${sectionId}-item`, key: `/library/metadata/${sectionId}-item`, title: sectionId === 'proof-movies' ? 'Proof Feature' : 'Proof Series', type: sectionId === 'proof-movies' ? 'movie' : 'show', summary: 'Synthetic proof media.', year: 2026, duration: 1_800_000, addedAt: 1_700_000_000, updatedAt: 1_700_000_001 };
}

function syntheticSection(key: string, title: string, type: 'movie' | 'show') {
  return { key, uuid: `${key}-uuid`, title, type, agent: 'proof-agent', scanner: 'proof-scanner', scannedAt: 1_700_000_000 };
}

function syntheticTelevisionItems(sectionId: string) {
  if (sectionId !== 'proof-shows') return [syntheticMedia(sectionId)];
  return [
    { ...syntheticMedia(sectionId), ratingKey: 'proof-episode-1', type: 'episode', grandparentRatingKey: 'proof-series-1', Actor: [{ id: 'actor-1', tag: 'Performer One' }], Director: [{ id: 'director-1', tag: 'Director One' }] },
    { ...syntheticMedia(sectionId), ratingKey: 'proof-episode-2', type: 'episode', grandparentRatingKey: 'proof-series-2', Actor: [{ id: 'actor-1', tag: 'Performer One' }], Director: [{ id: 'director-1', tag: 'Director One' }] },
  ];
}

function json(data: unknown) { return { kind: 'json' as const, data }; }

function proofDelay(durationMs: number, signal: AbortSignal | null): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted === true) { reject(new LivePlexTransportError('aborted', 'Synthetic proof request aborted.')); return; }
    const timer = setTimeout(resolve, durationMs);
    signal?.addEventListener('abort', () => { clearTimeout(timer); reject(new LivePlexTransportError('aborted', 'Synthetic proof request aborted.')); }, { once: true });
  });
}
