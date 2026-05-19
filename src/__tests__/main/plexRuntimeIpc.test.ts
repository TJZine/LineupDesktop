import test from 'node:test';
import assert from 'node:assert/strict';

import {
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
} from '../../contracts/ipc.js';
import {
  containsPlexForbiddenRendererField,
  type PlexRuntimeSnapshot,
} from '../../contracts/plex.js';
import { DiagnosticEventStore } from '../../main/diagnostics/diagnosticEventStore.js';
import {
  DesktopPlexAuthService,
  PlexAuthError,
  type DesktopPlexAuthTransport,
  type DesktopPlexAuthTransportRequest,
  type DesktopPlexAuthTransportResponse,
  type SaveDesktopPlexAccountCredentialInput,
} from '../../main/plex/auth/index.js';
import {
  createPlexApiResource,
  DesktopPlexServerDiscovery,
  PlexDiscoveryError,
  type DesktopPlexConnectionProbeTransportResult,
  type DesktopPlexDiscoveryTransport,
  type PlexConnection,
  type PlexServer,
  type PlexServerSelectionSource,
} from '../../main/plex/discovery/index.js';
import { DesktopPlexRuntime } from '../../main/plex/desktopPlexRuntime.js';
import {
  LivePlexTransportError,
  LivePlexTransport,
  type LivePlexLibraryTransport,
} from '../../main/plex/livePlexTransport.js';
import {
  cloneRuntimeSnapshot,
  mapRuntimeError,
} from '../../main/plex/desktopPlexRuntimeSupport.js';
import { registerPlexIpcHandlers } from '../../main/plex/plexIpc.js';

const placeholderAccountToken = ['placeholder', 'account', 'value'].join('-');
const placeholderManagedToken = ['placeholder', 'managed', 'value'].join('-');

class FakeAuthTransport implements DesktopPlexAuthTransport {
  public readonly requests: DesktopPlexAuthTransportRequest[] = [];
  private readonly responses = new Map<
    string,
    Array<DesktopPlexAuthTransportResponse | Promise<DesktopPlexAuthTransportResponse>>
  >();
  private readonly errors = new Map<string, unknown[]>();

  enqueue(
    action: DesktopPlexAuthTransportRequest['action'],
    response: DesktopPlexAuthTransportResponse | Promise<DesktopPlexAuthTransportResponse>,
  ): void {
    const queue = this.responses.get(action) ?? [];
    queue.push(response);
    this.responses.set(action, queue);
  }

  enqueueError(action: DesktopPlexAuthTransportRequest['action'], error: unknown): void {
    const queue = this.errors.get(action) ?? [];
    queue.push(error);
    this.errors.set(action, queue);
  }

  async request(input: DesktopPlexAuthTransportRequest): Promise<DesktopPlexAuthTransportResponse> {
    this.requests.push(input);
    if (input.signal?.aborted) {
      throw new PlexAuthError('aborted', 'Plex auth request was aborted');
    }
    const error = this.errors.get(input.action)?.shift();
    if (error !== undefined) {
      throw error;
    }
    const response = this.responses.get(input.action)?.shift();
    if (response === undefined) {
      throw new Error(`Unexpected auth action: ${input.action}`);
    }
    return response;
  }
}

class FakeCredentialStore {
  public saveStatus: 'ok' | 'unavailable' = 'ok';
  public secretValue: string | null = null;
  public profile: { accountId: string; username?: string; displayName?: string } | null = null;

  async saveAccountCredential(input: SaveDesktopPlexAccountCredentialInput) {
    if (this.saveStatus === 'unavailable') {
      return {
        ok: false,
        status: 'unavailable',
        profile: input.profile ?? { accountId: input.accountId },
        diagnostics: [],
      } as const;
    }
    this.secretValue = input.secretValue;
    this.profile = input.profile ?? { accountId: input.accountId };
    return {
      ok: true,
      profile: this.profile,
      credentialHandle: {
        credentialId: `plex-account:${input.accountId}`,
        accountId: input.accountId,
        kind: 'plex-account' as const,
        createdAtMs: 1,
        updatedAtMs: 1,
      },
      diagnostics: [],
    } as const;
  }

  async readDefaultAccountCredentialSecret() {
    if (this.secretValue === null || this.profile === null) {
      return { status: 'missing', accountId: null, diagnostics: [] } as const;
    }
    return {
      status: 'present',
      accountId: this.profile.accountId,
      credentialId: `plex-account:${this.profile.accountId}`,
      secretValue: this.secretValue,
      profile: this.profile,
      shouldReencrypt: false,
      diagnostics: [],
    } as const;
  }
}

class FakeDiscoveryTransport implements DesktopPlexDiscoveryTransport {
  public resources: unknown = [];
  public discoverError: unknown = null;
  public readonly discoverInputs: Array<{ token?: string; signal?: AbortSignal | null }> = [];
  public readonly probeInputs: Array<{
    server: PlexServer;
    connection: PlexConnection;
    token?: string;
  }> = [];
  private readonly probeResponses = new Map<
    string,
    DesktopPlexConnectionProbeTransportResult | Promise<DesktopPlexConnectionProbeTransportResult>
  >();

  enqueueProbe(
    address: string,
    result: DesktopPlexConnectionProbeTransportResult | Promise<DesktopPlexConnectionProbeTransportResult>,
  ): void {
    this.probeResponses.set(address, result);
  }

  async discoverResources(input: { token?: string; signal?: AbortSignal | null } = {}): Promise<unknown> {
    this.discoverInputs.push(input);
    if (this.discoverError !== null) {
      throw this.discoverError;
    }
    return this.resources;
  }

  async probeConnection(input: {
    server: PlexServer;
    connection: PlexConnection;
    token?: string;
  }): Promise<DesktopPlexConnectionProbeTransportResult> {
    this.probeInputs.push(input);
    return this.probeResponses.get(input.connection.address) ?? { outcome: 'unreachable' };
  }
}

class FakeSelectedServerStore {
  public persisted: { serverId: string; name: string; source: PlexServerSelectionSource; lastSelectedAtMs: number } | null = null;
  public readonly persistedByProfileId = new Map<
    string,
    { serverId: string; name: string; source: PlexServerSelectionSource; lastSelectedAtMs: number }
  >();
  public saveCount = 0;

  async readSelectedServerSummary(profileId?: string) {
    return profileId === undefined ? this.persisted : this.persistedByProfileId.get(profileId) ?? null;
  }

  async saveSelectedServerSummary(
    server: PlexServer,
    source: PlexServerSelectionSource,
    options: { profileId?: string } = {},
  ) {
    this.saveCount += 1;
    this.persisted = {
      serverId: server.id,
      name: server.name,
      source,
      lastSelectedAtMs: 50_000,
    };
    if (options.profileId !== undefined) {
      this.persistedByProfileId.set(options.profileId, this.persisted);
    }
    return this.persisted;
  }
}

class FakeLibraryTransport implements LivePlexLibraryTransport {
  public listSectionsResponse: unknown = { kind: 'json', data: { MediaContainer: { Directory: [rawSection()] } } };
  public listItemsResponse: unknown = { kind: 'json', data: { MediaContainer: { Metadata: [rawItem()] } } };
  public listItemsResponses: unknown[] = [];
  public searchResponse: unknown = {
    kind: 'json',
    data: { MediaContainer: { Hub: [{ type: 'movie', Metadata: [rawItem({ ratingKey: 'search-1', title: 'Search' })] }] } },
  };
  public metadataResponse: unknown = { kind: 'json', data: { MediaContainer: { Metadata: [rawItem({ ratingKey: 'meta-1', title: 'Metadata' })] } } };
  public sectionsError: unknown = null;
  public readonly listItemsRequests: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0][] = [];
  public readonly searchRequests: Parameters<LivePlexLibraryTransport['searchLibrary']>[0][] = [];

  async listLibrarySections() {
    if (this.sectionsError !== null) {
      throw this.sectionsError;
    }
    return this.listSectionsResponse as never;
  }

  async listLibraryItems(input: Parameters<LivePlexLibraryTransport['listLibraryItems']>[0]) {
    this.listItemsRequests.push(input);
    return (this.listItemsResponses.shift() ?? this.listItemsResponse) as never;
  }

  async searchLibrary(input: Parameters<LivePlexLibraryTransport['searchLibrary']>[0]) {
    this.searchRequests.push(input);
    return this.searchResponse as never;
  }

  async getMetadata() {
    return this.metadataResponse as never;
  }
}

test('desktop plex runtime signs in with PIN, cancels pending PIN, and rejects credential storage failures safely', async () => {
  const fixture = createRuntimeFixture();
  fixture.authTransport.enqueue('request-pin', {
    status: 201,
    payload: { kind: 'json', data: { id: 7, code: 'ABCD', expiresAt: '2026-05-14T12:00:00.000Z' } },
  });

  const requested = await fixture.runtime.requestPin('req-pin');
  assert.equal(requested.ok, true);
  assert.equal(requested.ok ? requested.value.pin.claimed : false, false);

  const cancelled = await fixture.runtime.cancelPin('cancel-pin', 7);
  assert.equal(cancelled.ok, true);
  assert.equal(cancelled.ok ? cancelled.value.snapshot.auth.pin : 'not-null', null);

  fixture.credentialStore.saveStatus = 'unavailable';
  fixture.authTransport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      kind: 'json',
      data: {
        id: 7,
        code: 'ABCD',
        expiresAt: '2026-05-14T12:00:00.000Z',
        authToken: placeholderAccountToken,
      },
    },
  });
  fixture.authTransport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload() },
  });

  const failed = await fixture.runtime.pollPin('poll-fail', 7);
  assert.equal(failed.ok, false);
  assert.equal(failed.ok ? '' : failed.error.code, 'PLEX_AUTH_INVALID');
  assert.equal(JSON.stringify(failed).includes(placeholderAccountToken), false);
});

test('desktop plex runtime switches Plex Home users with active-profile token in main memory only', async () => {
  const fixture = createRuntimeFixture();
  await signIn(fixture);
  fixture.authTransport.enqueue('get-home-users', {
    status: 200,
    payload: { kind: 'json', data: { MediaContainer: { users: [{ id: 'managed', title: 'Managed', protected: true }] } } },
  });
  fixture.authTransport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authToken: placeholderManagedToken } },
  });
  fixture.authTransport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'managed', username: 'managed' }) },
  });

  const users = await fixture.runtime.getHomeUsers('home-users');
  const switched = await fixture.runtime.switchHomeUser('switch-user', { userId: 'managed', pin: '1234' });

  assert.equal(users.ok, true);
  assert.equal(switched.ok, true);
  assert.equal(switched.ok ? switched.value.profile.accountId : '', 'managed');
  assert.equal(fixture.credentialStore.secretValue, placeholderAccountToken);
  assert.equal(JSON.stringify(switched).includes(placeholderManagedToken), false);
  assertRendererSafe(switched);
});

test('desktop plex runtime uses active profile token for server discovery and probing after Home switch', async () => {
  const fixture = createRuntimeFixture();
  await signIn(fixture);
  fixture.authTransport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authToken: placeholderManagedToken } },
  });
  fixture.authTransport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'managed', username: 'managed' }) },
  });
  const switched = await fixture.runtime.switchHomeUser('switch-managed', {
    userId: 'managed',
    pin: '1234',
  });
  fixture.discoveryTransport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Managed Server',
      connections: [connection({ address: 'managed-local', uri: 'https://managed.example:32400' })],
    }),
  ];
  fixture.discoveryTransport.enqueueProbe('managed-local', { outcome: 'reachable', latencyMs: 12 });
  fixture.discoveryTransport.enqueueProbe('managed-local', { outcome: 'reachable', latencyMs: 10 });

  const refreshed = await fixture.runtime.refreshServers('refresh-managed');
  const selected = await fixture.runtime.selectServer('select-managed', 'server-1');
  const restored = await fixture.runtime.restoreSelectedServer('restore-managed');

  assert.equal(switched.ok, true);
  assert.equal(refreshed.ok, true);
  assert.equal(selected.ok, true);
  assert.equal(restored.ok, true);
  assert.deepEqual(
    fixture.discoveryTransport.discoverInputs.map((input) => input.token),
    [placeholderManagedToken, placeholderManagedToken],
  );
  assert.deepEqual(
    fixture.discoveryTransport.probeInputs.map((input) => input.token),
    [placeholderManagedToken, placeholderManagedToken],
  );
  assert.equal(fixture.selectedServerStore.persistedByProfileId.get('managed')?.serverId, 'server-1');
  assert.equal(fixture.credentialStore.secretValue, placeholderAccountToken);
  assertRendererSafe([refreshed, selected, restored]);
});

test('desktop plex runtime does not reuse selected server across Plex Home profile switch', async () => {
  const fixture = createRuntimeFixture();
  await signIn(fixture);
  fixture.discoveryTransport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Living Room',
      connections: [connection({ address: 'local', uri: 'https://local.example:32400' })],
    }),
  ];
  fixture.discoveryTransport.enqueueProbe('local', { outcome: 'reachable', latencyMs: 12 });

  assert.equal((await fixture.runtime.refreshServers('refresh')).ok, true);
  assert.equal((await fixture.runtime.selectServer('select-account', 'server-1')).ok, true);
  assert.equal(fixture.selectedServerStore.persistedByProfileId.get('account-1')?.serverId, 'server-1');

  fixture.authTransport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authToken: placeholderManagedToken } },
  });
  fixture.authTransport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'managed', username: 'managed' }) },
  });

  const switched = await fixture.runtime.switchHomeUser('switch-managed', { userId: 'managed', pin: '1234' });
  const restored = await fixture.runtime.restoreSelectedServer('restore-managed');

  assert.equal(switched.ok, true);
  assert.equal(restored.ok, true);
  assert.deepEqual(restored.ok ? restored.value.selection : null, {
    kind: 'selection-failed',
    reason: 'no-persisted-server',
    persisted: false,
  });
  assert.equal(restored.ok ? restored.value.snapshot.servers.selected : 'not-null', null);
  assert.equal(fixture.discovery.getSelectedConnectionForMain(), null);
  assert.equal(fixture.selectedServerStore.persistedByProfileId.get('account-1')?.serverId, 'server-1');
  assert.equal(fixture.selectedServerStore.persistedByProfileId.get('managed'), undefined);
  assertRendererSafe(restored);
});

test('desktop plex runtime rejects stale library commits after Plex Home profile switch', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  const libraryStarted = createDeferred<void>();
  const staleSections = createDeferred<unknown>();
  fixture.libraryTransport.listLibrarySections = async () => {
    libraryStarted.resolve();
    return staleSections.promise as never;
  };

  const staleSectionsResult = fixture.runtime.listLibrarySections('sections-old-profile');
  await libraryStarted.promise;
  fixture.authTransport.enqueue('switch-home-user', {
    status: 200,
    payload: { kind: 'json', data: { authToken: placeholderManagedToken } },
  });
  fixture.authTransport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'managed', username: 'managed' }) },
  });

  const switched = await fixture.runtime.switchHomeUser('switch-managed-race', {
    userId: 'managed',
    pin: '1234',
  });
  staleSections.resolve({
    kind: 'json',
    data: { MediaContainer: { Directory: [rawSection({ title: 'Old Profile' })] } },
  });
  const stale = await staleSectionsResult;
  const snapshot = fixture.runtime.getSnapshot('snapshot-after-profile-switch-race');

  assert.equal(switched.ok, true);
  assert.equal(stale.ok, false);
  assert.equal(stale.ok ? '' : stale.error.code, 'PLEX_STALE_RESULT');
  assert.equal(stale.ok ? false : stale.stale, true);
  assert.equal(snapshot.ok ? snapshot.value.auth.profile?.accountId : '', 'managed');
  assert.equal(snapshot.ok ? snapshot.value.servers.selected : 'not-null', null);
  assert.equal(snapshot.ok ? snapshot.value.library.status : '', 'idle');
  assert.equal(snapshot.ok ? snapshot.value.library.sections.length : -1, 0);
  assert.equal(snapshot.ok ? snapshot.value.library.items.length : -1, 0);
  assert.equal(snapshot.ok ? snapshot.value.library.search : 'not-null', null);
  assert.equal(snapshot.ok ? snapshot.value.library.metadata : 'not-null', null);
  assertRendererSafe([stale, snapshot]);
});

test('desktop plex runtime refreshes, restores, and selects servers while keeping connection details in main custody', async () => {
  const fixture = createRuntimeFixture();
  await signIn(fixture);
  fixture.discoveryTransport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Living Room',
      connections: [connection({ address: 'local', uri: 'https://local.example:32400' })],
    }),
  ];
  fixture.discoveryTransport.enqueueProbe('local', { outcome: 'reachable', latencyMs: 12 });

  const refreshed = await fixture.runtime.refreshServers('refresh');
  const selected = await fixture.runtime.selectServer('select', 'server-1');
  const restored = await fixture.runtime.restoreSelectedServer('restore');

  assert.equal(refreshed.ok, true);
  assert.equal(selected.ok, true);
  assert.equal(restored.ok, true);
  assert.deepEqual(
    fixture.discoveryTransport.discoverInputs.map((input) => input.token),
    [placeholderAccountToken, placeholderAccountToken],
  );
  assert.equal(
    fixture.discoveryTransport.probeInputs.every((input) => input.token === placeholderAccountToken),
    true,
  );
  assert.equal(fixture.discovery.getSelectedConnectionForMain()?.uri, 'https://local.example:32400');
  assert.equal(JSON.stringify(selected).includes('local.example'), false);
  assertRendererSafe(selected);
});

test('desktop plex runtime clears library data when selected server changes', async () => {
  const fixture = createRuntimeFixture();
  await signIn(fixture);
  fixture.discoveryTransport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Living Room',
      connections: [connection({ address: 'local', uri: 'https://local.example:32400' })],
    }),
    createPlexApiResource({
      clientIdentifier: 'server-2',
      name: 'Bedroom',
      connections: [connection({ address: 'remote', uri: 'https://remote.example:32400' })],
    }),
  ];
  fixture.discoveryTransport.enqueueProbe('local', { outcome: 'reachable', latencyMs: 12 });
  fixture.discoveryTransport.enqueueProbe('remote', { outcome: 'reachable', latencyMs: 10 });

  assert.equal((await fixture.runtime.refreshServers('refresh')).ok, true);
  assert.equal((await fixture.runtime.selectServer('select-local', 'server-1')).ok, true);
  assert.equal((await fixture.runtime.listLibrarySections('sections')).ok, true);
  assert.equal((await fixture.runtime.listLibraryItems('items', { sectionId: '1' })).ok, true);
  assert.equal((await fixture.runtime.searchLibrary('search', { query: 'movie' })).ok, true);
  assert.equal((await fixture.runtime.getMetadata('metadata', 'meta-1')).ok, true);

  const populatedSnapshot = fixture.runtime.getSnapshot('snapshot-populated');
  assert.equal(populatedSnapshot.ok ? populatedSnapshot.value.library.sections.length : 0, 1);
  assert.equal(populatedSnapshot.ok ? populatedSnapshot.value.library.items.length : 0, 1);
  assert.equal(populatedSnapshot.ok ? populatedSnapshot.value.library.search?.items.length : 0, 1);
  assert.equal(populatedSnapshot.ok ? populatedSnapshot.value.library.metadata?.ratingKey : '', 'meta-1');

  const switched = await fixture.runtime.selectServer('select-remote', 'server-2');
  const switchedSnapshot = fixture.runtime.getSnapshot('snapshot-switched');

  assert.equal(switched.ok, true);
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.servers.selected?.serverId : '', 'server-2');
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.library.status : '', 'idle');
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.library.sections.length : -1, 0);
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.library.selectedSectionId : 'not-null', null);
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.library.items.length : -1, 0);
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.library.search : 'not-null', null);
  assert.equal(switchedSnapshot.ok ? switchedSnapshot.value.library.metadata : 'not-null', null);
  assertRendererSafe(switchedSnapshot);
});

test('desktop plex runtime maps aborted discovery refresh and restore to cancellation', async () => {
  const refreshFixture = createRuntimeFixture();
  await signIn(refreshFixture);
  refreshFixture.discoveryTransport.discoverError = new LivePlexTransportError(
    'aborted',
    'Plex request was aborted',
  );

  const refreshed = await refreshFixture.runtime.refreshServers('refresh-aborted');
  const refreshSnapshot = refreshFixture.runtime.getSnapshot('snapshot-refresh-aborted');

  assert.equal(refreshed.ok, false);
  assert.equal(refreshed.ok ? '' : refreshed.error.code, 'PLEX_CANCELLED');
  assert.equal(refreshed.ok ? false : refreshed.cancelled, true);
  assert.equal(refreshSnapshot.ok ? refreshSnapshot.value.lastError : 'not-null', null);

  const structuralRefreshFixture = createRuntimeFixture();
  await signIn(structuralRefreshFixture);
  structuralRefreshFixture.discoveryTransport.discoverError = Object.assign(
    new Error('Plex request was aborted'),
    { code: 'aborted' },
  );

  const structurallyRefreshed = await structuralRefreshFixture.runtime.refreshServers('refresh-structural-aborted');
  const structuralRefreshSnapshot = structuralRefreshFixture.runtime.getSnapshot('snapshot-refresh-structural-aborted');

  assert.equal(structurallyRefreshed.ok, false);
  assert.equal(structurallyRefreshed.ok ? '' : structurallyRefreshed.error.code, 'PLEX_CANCELLED');
  assert.equal(structurallyRefreshed.ok ? false : structurallyRefreshed.cancelled, true);
  assert.equal(structuralRefreshSnapshot.ok ? structuralRefreshSnapshot.value.lastError : 'not-null', null);

  const restoreFixture = createRuntimeFixture();
  await signIn(restoreFixture);
  restoreFixture.selectedServerStore.persisted = {
    serverId: 'server-1',
    name: 'Living Room',
    source: 'manual',
    lastSelectedAtMs: 50_000,
  };
  restoreFixture.selectedServerStore.persistedByProfileId.set(
    'account-1',
    restoreFixture.selectedServerStore.persisted,
  );
  restoreFixture.discoveryTransport.discoverError = new LivePlexTransportError(
    'aborted',
    'Plex request was aborted',
  );

  const restored = await restoreFixture.runtime.restoreSelectedServer('restore-aborted');
  const restoreSnapshot = restoreFixture.runtime.getSnapshot('snapshot-restore-aborted');

  assert.equal(restored.ok, false);
  assert.equal(restored.ok ? '' : restored.error.code, 'PLEX_CANCELLED');
  assert.equal(restored.ok ? false : restored.cancelled, true);
  assert.equal(restoreSnapshot.ok ? restoreSnapshot.value.lastError : 'not-null', null);
});

test('desktop plex runtime preserves discovery timeout as retryable server unreachable', async () => {
  const fixture = createRuntimeFixture();
  await signIn(fixture);
  fixture.discoveryTransport.discoverError = new LivePlexTransportError(
    'timeout',
    'Plex request timed out',
    undefined,
    { retryable: true },
  );

  const refreshed = await fixture.runtime.refreshServers('refresh-timeout');

  assert.equal(refreshed.ok, false);
  assert.equal(refreshed.ok ? '' : refreshed.error.code, 'PLEX_SERVER_UNREACHABLE');
  assert.equal(refreshed.ok ? false : refreshed.error.retryable, true);
  assert.equal(refreshed.ok ? true : refreshed.cancelled, undefined);
});

test('desktop plex runtime maps auth and discovery server errors without leaking privileged context', () => {
  const authError = mapRuntimeError(
    new PlexAuthError('server-error', `failed ${placeholderAccountToken}`, 500, {
      retryable: true,
    }),
    'requestPin',
  );
  const discoveryError = mapRuntimeError(
    new PlexDiscoveryError('server-error', `failed ${placeholderAccountToken}`, 503, {
      retryable: true,
    }),
    'refreshServers',
  );

  assert.equal(authError.code, 'PLEX_UNKNOWN');
  assert.equal(authError.httpStatus, 500);
  assert.equal(authError.retryable, true);
  assert.equal(discoveryError.code, 'PLEX_UNKNOWN');
  assert.equal(discoveryError.httpStatus, 503);
  assert.equal(discoveryError.retryable, true);
  assert.equal(JSON.stringify([authError, discoveryError]).includes(placeholderAccountToken), false);
});

test('desktop plex runtime maps live transport server errors by operation owner', () => {
  const refreshError = mapRuntimeError(
    new LivePlexTransportError('server-error', `failed ${placeholderAccountToken}`, 503, {
      retryable: true,
    }),
    'refreshServers',
  );
  const libraryError = mapRuntimeError(
    new LivePlexTransportError('server-error', `failed ${placeholderAccountToken}`, 500, {
      retryable: true,
    }),
    'listLibrarySections',
  );

  assert.equal(refreshError.code, 'PLEX_UNKNOWN');
  assert.equal(refreshError.message, 'Plex operation failed.');
  assert.equal(refreshError.httpStatus, 503);
  assert.equal(refreshError.retryable, true);
  assert.equal(libraryError.code, 'PLEX_LIBRARY_FAILED');
  assert.equal(libraryError.message, 'Plex library request failed.');
  assert.equal(libraryError.httpStatus, 500);
  assert.equal(libraryError.retryable, true);
  assert.equal(JSON.stringify([refreshError, libraryError]).includes(placeholderAccountToken), false);
});

test('desktop plex runtime snapshot clone isolates nested renderer-safe state', () => {
  const server = {
    serverId: 'server-1',
    name: 'Server',
    owned: true,
    connectionCount: 1,
    hasLocalConnection: true,
    hasRemoteConnection: false,
    hasRelayConnection: false,
    selected: true,
    health: {
      status: 'ok' as const,
      connectionKind: 'local' as const,
      latencyMs: 12,
      testedAtMs: 1,
    },
  };
  const item = {
    ratingKey: 'rating-1',
    type: 'movie' as const,
    title: 'Movie',
    sortTitle: 'Movie',
    summary: 'Summary',
    year: 2026,
    durationMs: 1_000,
    addedAtMs: 1,
    updatedAtMs: 2,
    genres: ['Drama'],
    directors: ['Director'],
    actors: ['Actor'],
    studios: ['Studio'],
  };
  const snapshot: PlexRuntimeSnapshot = {
    auth: {
      state: 'signed-in',
      pin: { id: 7, code: 'ABCD', expiresAtMs: 1, claimed: false },
      profile: {
        accountId: 'account-1',
        username: 'viewer',
        displayName: 'Viewer',
        activeProfileId: 'home-1',
        preferredSubtitleLanguage: 'en',
      },
      homeUsers: [{ id: 'home-1', title: 'Home User', admin: false, protected: true }],
      credentialStatus: 'present',
    },
    servers: {
      status: 'ready',
      selected: server,
      items: [server],
      lastSelection: { kind: 'selected', server, persisted: true },
    },
    library: {
      status: 'ready',
      sections: [{
        id: 'section-1',
        title: 'Movies',
        type: 'movie',
        contentCount: 1,
        episodeCount: 0,
        lastScannedAtMs: 1,
      }],
      selectedSectionId: 'section-1',
      items: [item],
      search: { query: 'movie', items: [item] },
      metadata: item,
    },
    lastError: {
      code: 'PLEX_LIBRARY_FAILED',
      message: 'Plex library request failed.',
      retryable: true,
      recoverable: true,
      operation: 'listLibraryItems',
      httpStatus: 500,
    },
    updatedAtMs: 10,
  };

  const cloned = cloneRuntimeSnapshot(snapshot);

  assert.deepEqual(cloned, snapshot);
  assert.notEqual(cloned.auth.pin, snapshot.auth.pin);
  assert.notEqual(cloned.auth.profile, snapshot.auth.profile);
  assert.notEqual(cloned.auth.homeUsers, snapshot.auth.homeUsers);
  assert.notEqual(cloned.auth.homeUsers[0], snapshot.auth.homeUsers[0]);
  assert.notEqual(cloned.servers.selected, snapshot.servers.selected);
  assert.notEqual(cloned.servers.selected?.health, snapshot.servers.selected?.health);
  assert.notEqual(cloned.servers.items, snapshot.servers.items);
  assert.notEqual(cloned.servers.items[0], snapshot.servers.items[0]);
  assert.notEqual(cloned.servers.items[0]?.health, snapshot.servers.items[0]?.health);
  assert.notEqual(cloned.servers.lastSelection, snapshot.servers.lastSelection);
  assert.equal(cloned.servers.lastSelection?.kind, 'selected');
  if (cloned.servers.lastSelection?.kind === 'selected' && snapshot.servers.lastSelection?.kind === 'selected') {
    assert.notEqual(cloned.servers.lastSelection.server, snapshot.servers.lastSelection.server);
    assert.notEqual(cloned.servers.lastSelection.server.health, snapshot.servers.lastSelection.server.health);
  }
  assert.notEqual(cloned.library.sections, snapshot.library.sections);
  assert.notEqual(cloned.library.sections[0], snapshot.library.sections[0]);
  assert.notEqual(cloned.library.items, snapshot.library.items);
  assert.notEqual(cloned.library.items[0], snapshot.library.items[0]);
  assert.notEqual(cloned.library.items[0]?.genres, snapshot.library.items[0]?.genres);
  assert.notEqual(cloned.library.items[0]?.directors, snapshot.library.items[0]?.directors);
  assert.notEqual(cloned.library.items[0]?.actors, snapshot.library.items[0]?.actors);
  assert.notEqual(cloned.library.items[0]?.studios, snapshot.library.items[0]?.studios);
  assert.notEqual(cloned.library.search, snapshot.library.search);
  assert.notEqual(cloned.library.search?.items, snapshot.library.search?.items);
  assert.notEqual(cloned.library.search?.items[0], snapshot.library.search?.items[0]);
  assert.notEqual(cloned.library.metadata, snapshot.library.metadata);
  assert.notEqual(cloned.library.metadata?.genres, snapshot.library.metadata?.genres);
  assert.notEqual(cloned.lastError, snapshot.lastError);
});

test('desktop plex runtime projects library sections, items, search, metadata, diagnostics, and sanitized errors', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);

  const sections = await fixture.runtime.listLibrarySections('sections');
  const items = await fixture.runtime.listLibraryItems('items', { sectionId: '1', limit: 25 });
  const search = await fixture.runtime.searchLibrary('search', { query: 'movie', limit: 10 });
  const metadata = await fixture.runtime.getMetadata('metadata', 'meta-1');

  assert.equal(sections.ok, true);
  assert.equal(items.ok, true);
  assert.equal(search.ok, true);
  assert.equal(metadata.ok, true);
  assert.equal(items.ok ? items.value.items[0]?.title : '', 'Movie');
  assert.equal(search.ok ? search.value.items[0]?.ratingKey : '', 'search-1');
  assert.equal(metadata.ok ? metadata.value.item?.title : '', 'Metadata');
  assertRendererSafe([sections, items, search, metadata]);

  fixture.libraryTransport.metadataResponse = { kind: 'json', data: { MediaContainer: { Metadata: [] } } };
  const missing = await fixture.runtime.getMetadata('metadata-missing', 'missing');
  assert.equal(missing.ok, true);
  assert.equal(missing.ok ? missing.value.item : 'not-null', null);
  assert.equal(missing.ok ? missing.value.snapshot.library.metadata : 'not-null', null);
  assert.equal(containsPlexForbiddenRendererField(missing), false);

  const records = fixture.diagnostics.getRecords();
  assert.equal(JSON.stringify(records).includes('local.example'), false);
  assert.equal(JSON.stringify(records).includes(placeholderAccountToken), false);
});

test('desktop plex runtime paginates library browse and forwards safe filters', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  fixture.libraryTransport.listItemsResponses = [
    {
      kind: 'json',
      data: {
        MediaContainer: {
          Metadata: Array.from({ length: 100 }, (_, index) =>
            rawItem({ ratingKey: `item-${index + 1}`, title: `Item ${index + 1}` }),
          ),
        },
      },
    },
    {
      kind: 'json',
      data: {
        MediaContainer: {
          Metadata: [
            rawItem({ ratingKey: 'item-3', title: 'Item 3' }),
            rawItem({ ratingKey: 'item-4', title: 'Item 4' }),
          ],
        },
      },
    },
  ];

  const result = await fixture.runtime.listLibraryItems('items-paged', {
    sectionId: '1',
    offset: 5,
    sort: 'titleSort:asc',
    filter: { type: 1, year: 2020 },
    includeCollections: true,
  });

  assert.equal(result.ok, true);
  assert.equal(result.ok ? result.value.items.length : 0, 102);
  assert.deepEqual(
    fixture.libraryTransport.listItemsRequests.map((request) => ({
      offset: request.offset,
      limit: request.limit,
      sort: request.sort,
      filter: request.filter,
      includeCollections: request.includeCollections,
    })),
    [
      {
        offset: 5,
        limit: 100,
        sort: 'titleSort:asc',
        filter: { type: 1, year: 2020 },
        includeCollections: true,
      },
      {
        offset: 105,
        limit: 100,
        sort: 'titleSort:asc',
        filter: { type: 1, year: 2020 },
        includeCollections: true,
      },
    ],
  );
  assertRendererSafe([result]);
});

test('desktop plex runtime trims library browse results to requested limit', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  fixture.libraryTransport.listItemsResponse = {
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: [
          rawItem({ ratingKey: 'item-1', title: 'Item 1' }),
          rawItem({ ratingKey: 'item-2', title: 'Item 2' }),
          rawItem({ ratingKey: 'item-3', title: 'Item 3' }),
          rawItem({ ratingKey: 'item-4', title: 'Item 4' }),
        ],
      },
    },
  };

  const result = await fixture.runtime.listLibraryItems('items-trim', { sectionId: '1', limit: 3 });

  assert.equal(result.ok, true);
  assert.deepEqual(
    result.ok ? result.value.items.map((item) => item.ratingKey) : [],
    ['item-1', 'item-2', 'item-3'],
  );
  assert.deepEqual(
    fixture.libraryTransport.listItemsRequests.map((request) => ({ offset: request.offset, limit: request.limit })),
    [{ offset: 0, limit: 3 }],
  );
});

test('desktop plex runtime returns empty browse results without transport for non-positive limits', async () => {
  const fixture = createRuntimeFixture();

  const result = await fixture.runtime.listLibraryItems('items-empty', { sectionId: '1', limit: 0 });

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value.items : ['unexpected'], []);
  assert.equal(fixture.libraryTransport.listItemsRequests.length, 0);
  assert.equal(result.ok ? result.value.snapshot.library.selectedSectionId : null, '1');
  assertRendererSafe([result]);
});

test('desktop plex runtime rejects unsafe library browse filter and include flags', async () => {
  const fixture = createRuntimeFixture();

  const tokenFilter = await fixture.runtime.listLibraryItems('items-token-filter', {
    sectionId: '1',
    filter: { token: 'unsafe' },
  });
  const badIncludeCollections = await fixture.runtime.listLibraryItems(
    'items-bad-include-collections',
    { sectionId: '1', includeCollections: 'yes' as never },
  );

  assert.equal(tokenFilter.ok, false);
  assert.equal(tokenFilter.ok ? '' : tokenFilter.error.code, 'PLEX_VALIDATION_FAILED');
  assert.equal(badIncludeCollections.ok, false);
  assert.equal(badIncludeCollections.ok ? '' : badIncludeCollections.error.code, 'PLEX_VALIDATION_FAILED');
  assert.equal(fixture.libraryTransport.listItemsRequests.length, 0);
  assertRendererSafe([tokenFilter, badIncludeCollections]);
});

test('desktop plex runtime rejects explicit non-positive search limits', async () => {
  const fixture = createRuntimeFixture();

  const zero = await fixture.runtime.searchLibrary('search-zero-limit', { query: 'movie', limit: 0 });
  const negative = await fixture.runtime.searchLibrary('search-negative-limit', { query: 'movie', limit: -1 });

  assert.equal(zero.ok, false);
  assert.equal(zero.ok ? '' : zero.error.code, 'PLEX_VALIDATION_FAILED');
  assert.equal(negative.ok, false);
  assert.equal(negative.ok ? '' : negative.error.code, 'PLEX_VALIDATION_FAILED');
  assert.equal(fixture.libraryTransport.searchRequests.length, 0);
  assertRendererSafe([zero, negative]);
});

test('desktop plex runtime guards infinite library browse pagination safely', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  fixture.libraryTransport.listItemsResponse = {
    kind: 'json',
    data: {
      MediaContainer: {
        Metadata: Array.from({ length: 100 }, (_, index) =>
          rawItem({ ratingKey: `loop-${index}`, title: 'Loop' }),
        ),
      },
    },
  };

  const failed = await fixture.runtime.listLibraryItems('items-loop', { sectionId: '1' });

  assert.equal(failed.ok, false);
  assert.equal(failed.ok ? '' : failed.error.code, 'PLEX_LIBRARY_FAILED');
  assert.equal(fixture.libraryTransport.listItemsRequests.length, 1_000);
  assert.equal(containsPlexForbiddenRendererField(failed), false);
  assert.equal(JSON.stringify(failed).includes(placeholderAccountToken), false);
});

test('desktop plex runtime forwards search types and skips non-requested hubs', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  fixture.libraryTransport.searchResponse = {
    kind: 'json',
    data: {
      MediaContainer: {
        Hub: [
          { type: 'movie', Metadata: [rawItem({ ratingKey: 'movie-1', title: 'Movie' })] },
          { type: 'show', Metadata: [rawItem({ ratingKey: 'show-1', type: 'show', title: 'Show' })] },
          { type: 'unknown', Metadata: [rawItem({ ratingKey: 'unknown-1', title: 'Unknown' })] },
        ],
      },
    },
  };

  const result = await fixture.runtime.searchLibrary('search-types', {
    query: 'library',
    sectionId: '1',
    limit: 10,
    types: ['movie'],
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.ok ? result.value.items.map((item) => item.ratingKey) : [], ['movie-1']);
  assert.deepEqual(fixture.libraryTransport.searchRequests.map((request) => request.types), [['movie']]);
  assertRendererSafe([result]);
});

test('desktop plex runtime maps not-found metadata to semantic null and preserves malformed payload failures', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  fixture.libraryTransport.getMetadata = async () => {
    throw new LivePlexTransportError('resource-not-found', 'Plex resource was not found', 404);
  };

  const missing = await fixture.runtime.getMetadata('metadata-404', 'missing');
  assert.equal(missing.ok, true);
  assert.equal(missing.ok ? missing.value.item : 'not-null', null);
  assert.equal(missing.ok ? missing.value.snapshot.library.metadata : 'not-null', null);

  fixture.libraryTransport.getMetadata = async () =>
    ({ kind: 'json', data: { MediaContainer: { Metadata: {} } } }) as never;
  const malformed = await fixture.runtime.getMetadata('metadata-malformed', 'broken');
  assert.equal(malformed.ok, false);
  assert.equal(malformed.ok ? '' : malformed.error.code, 'PLEX_PARSE_FAILED');
  assert.equal(containsPlexForbiddenRendererField(malformed), false);
});

test('desktop plex runtime rejects malformed JSON library payload envelopes safely', async () => {
  const invalidPayloads = [
    { kind: 'json' },
    { kind: 'json', data: null },
    { kind: 'json', data: {} },
  ];

  for (const invalidPayload of invalidPayloads) {
    const fixture = createRuntimeFixture();
    await signInAndSelectServer(fixture);
    fixture.libraryTransport.listItemsResponse = invalidPayload;

    const failed = await fixture.runtime.listLibraryItems('items-invalid-payload', { sectionId: '1' });

    assert.equal(failed.ok, false);
    assert.equal(failed.ok ? '' : failed.error.code, 'PLEX_PARSE_FAILED');
    assert.equal(containsPlexForbiddenRendererField(failed), false);
    assert.equal(JSON.stringify(failed).includes(placeholderAccountToken), false);
  }
});

test('desktop plex runtime returns cancelled and stale envelopes without committing stale results', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  const deferred = createDeferred<unknown>();
  fixture.libraryTransport.listSectionsResponse = deferred.promise;
  fixture.libraryTransport.listLibrarySections = async () => deferred.promise as never;

  const stalePromise = fixture.runtime.listLibrarySections('sections-old');
  fixture.libraryTransport.listLibrarySections = async () =>
    ({ kind: 'json', data: { MediaContainer: { Directory: [rawSection({ title: 'Fresh' })] } } }) as never;
  const fresh = await fixture.runtime.listLibrarySections('sections-new');
  deferred.resolve({ kind: 'json', data: { MediaContainer: { Directory: [rawSection({ title: 'Stale' })] } } });
  const stale = await stalePromise;

  assert.equal(fresh.ok, true);
  assert.equal(fresh.ok ? fresh.value.sections[0]?.title : '', 'Fresh');
  assert.equal(stale.ok, false);
  assert.equal(stale.ok ? '' : stale.error.code, 'PLEX_STALE_RESULT');
  assert.equal(stale.ok ? false : stale.stale, true);
  const snapshotAfterStale = fixture.runtime.getSnapshot('snapshot-after-stale');
  assert.equal(
    snapshotAfterStale.ok ? snapshotAfterStale.value.library.sections[0]?.title : '',
    'Fresh',
  );

  const slowAuth = createRuntimeFixture({
    sleep: (_durationMs, signal) =>
      new Promise<void>((_resolve, reject) => {
        if (signal?.aborted) {
          reject(new PlexAuthError('aborted', 'aborted'));
          return;
        }
        signal?.addEventListener('abort', () => reject(new PlexAuthError('aborted', 'aborted')), { once: true });
      }),
  });
  await signIn(slowAuth, { claimed: false });
  const poll = slowAuth.runtime.pollPin('poll-pending', 7);
  const cancel = await slowAuth.runtime.cancelPin('cancel-pending', 7);
  const cancelled = await poll;

  assert.equal(cancel.ok, true);
  assert.equal(cancelled.ok, false);
  assert.equal(cancelled.ok ? '' : cancelled.error.code, 'PLEX_CANCELLED');
  assert.equal(cancelled.ok ? false : cancelled.cancelled, true);
  const snapshotAfterCancel = slowAuth.runtime.getSnapshot('snapshot-after-cancel');
  assert.notEqual(snapshotAfterCancel.ok ? snapshotAfterCancel.value.lastError?.code : '', 'PLEX_CANCELLED');
});

test('desktop plex runtime treats live transport timeout as retryable failure but caller abort as cancellation', async () => {
  const fixture = createRuntimeFixture();
  await signInAndSelectServer(fixture);
  fixture.libraryTransport.sectionsError = new LivePlexTransportError(
    'timeout',
    'Plex request timed out',
    undefined,
    { retryable: true },
  );

  const timedOut = await fixture.runtime.listLibrarySections('sections-timeout');
  const timeoutSnapshot = fixture.runtime.getSnapshot('snapshot-timeout');

  assert.equal(timedOut.ok, false);
  assert.equal(timedOut.ok ? '' : timedOut.error.code, 'PLEX_SERVER_UNREACHABLE');
  assert.equal(timedOut.ok ? false : timedOut.error.retryable, true);
  assert.equal(timeoutSnapshot.ok ? timeoutSnapshot.value.library.status : '', 'failed');
  assert.equal(timeoutSnapshot.ok ? timeoutSnapshot.value.lastError?.code : '', 'PLEX_SERVER_UNREACHABLE');

  const aborted = createRuntimeFixture({
    sleep: (_durationMs, signal) =>
      new Promise<void>((_resolve, reject) => {
        if (signal?.aborted) {
          reject(new PlexAuthError('aborted', 'aborted'));
          return;
        }
        signal?.addEventListener('abort', () => reject(new PlexAuthError('aborted', 'aborted')), { once: true });
      }),
  });
  await signIn(aborted, { claimed: false });
  const poll = aborted.runtime.pollPin('poll-aborted', 7);
  const cancel = await aborted.runtime.cancelPin('cancel-aborted', 7);
  const cancelled = await poll;
  const abortSnapshot = aborted.runtime.getSnapshot('snapshot-aborted');

  assert.equal(cancel.ok, true);
  assert.equal(cancelled.ok, false);
  assert.equal(cancelled.ok ? '' : cancelled.error.code, 'PLEX_CANCELLED');
  assert.notEqual(abortSnapshot.ok ? abortSnapshot.value.lastError?.code : '', 'PLEX_CANCELLED');
});

test('desktop plex auth ignores aborted profile commits and preserves live abort versus timeout semantics', async () => {
  const transport = new FakeAuthTransport();
  const credentialStore = new FakeCredentialStore();
  const service = new DesktopPlexAuthService({
    config: authConfig(),
    transport,
    credentialStore,
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'old-account', username: 'old' }) },
  });
  await service.restoreAccountToken(placeholderAccountToken);
  assert.equal(service.getAccountTokenForMain(), placeholderAccountToken);

  const validateNew = createDeferred<DesktopPlexAuthTransportResponse>();
  const abortController = new AbortController();
  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      kind: 'json',
      data: {
        id: 8,
        code: 'WXYZ',
        expiresAt: '2026-05-14T12:00:00.000Z',
        authToken: placeholderManagedToken,
      },
    },
  });
  transport.enqueue('validate-token', validateNew.promise);
  const check = service.checkPinStatus(8, { signal: abortController.signal });
  validateNew.resolve({
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'new-account', username: 'new' }) },
  });
  abortController.abort();

  await assert.rejects(
    () => check,
    (error) => error instanceof PlexAuthError && error.code === 'aborted',
  );
  assert.equal(service.getAccountTokenForMain(), placeholderAccountToken);
  assert.equal(service.getActiveTokenForMain(), placeholderAccountToken);
  assert.notEqual(credentialStore.secretValue, placeholderManagedToken);

  const abortedFixture = createRuntimeFixture();
  await signIn(abortedFixture, { claimed: false });
  abortedFixture.authTransport.enqueueError(
    'check-pin-status',
    new LivePlexTransportError('aborted', 'Plex request was aborted'),
  );
  const aborted = await abortedFixture.runtime.pollPin('poll-live-abort', 7);
  const abortedSnapshot = abortedFixture.runtime.getSnapshot('snapshot-live-abort');
  assert.equal(aborted.ok, false);
  assert.equal(aborted.ok ? '' : aborted.error.code, 'PLEX_CANCELLED');
  assert.equal(aborted.ok ? false : aborted.cancelled, true);
  assert.equal(abortedSnapshot.ok ? abortedSnapshot.value.lastError : 'not-null', null);

  const timeoutFixture = createRuntimeFixture();
  timeoutFixture.authTransport.enqueueError(
    'request-pin',
    new LivePlexTransportError('timeout', 'Plex request timed out', undefined, { retryable: true }),
  );
  const timedOut = await timeoutFixture.runtime.requestPin('pin-live-timeout');
  assert.equal(timedOut.ok, false);
  assert.equal(timedOut.ok ? '' : timedOut.error.code, 'PLEX_SERVER_UNREACHABLE');
  assert.equal(timedOut.ok ? false : timedOut.error.retryable, true);

  const pinExpiredFixture = createRuntimeFixture();
  pinExpiredFixture.authTransport.enqueueError(
    'request-pin',
    new PlexAuthError('pin-expired', 'Plex PIN expired'),
  );
  const pinExpired = await pinExpiredFixture.runtime.requestPin('pin-expired');
  assert.equal(pinExpired.ok, false);
  assert.equal(pinExpired.ok ? '' : pinExpired.error.code, 'PLEX_PIN_EXPIRED');
  assert.equal(pinExpired.ok ? '' : pinExpired.error.message, 'Plex link code expired. Request a new code and try again.');

  const pinTimeoutFixture = createRuntimeFixture();
  pinTimeoutFixture.authTransport.enqueueError(
    'request-pin',
    new PlexAuthError('pin-timeout', 'Plex PIN timed out'),
  );
  const pinTimeout = await pinTimeoutFixture.runtime.requestPin('pin-timeout');
  assert.equal(pinTimeout.ok, false);
  assert.equal(pinTimeout.ok ? '' : pinTimeout.error.code, 'PLEX_PIN_TIMEOUT');
  assert.equal(pinTimeout.ok ? '' : pinTimeout.error.message, 'Plex link code timed out. Request a new code and try again.');
});

test('desktop plex auth aborts in-flight credential persistence before saving account credential', async () => {
  const transport = new FakeAuthTransport();
  const saveStarted = createDeferred<void>();
  const releaseSave = createDeferred<void>();
  let persistedSecret: string | null = null;
  const credentialStore = {
    async saveAccountCredential(
      input: SaveDesktopPlexAccountCredentialInput,
      options: { signal?: AbortSignal | null } = {},
    ) {
      saveStarted.resolve();
      await releaseSave.promise;
      if (options.signal?.aborted) {
        throw new PlexAuthError('aborted', 'Plex credential save was aborted');
      }
      persistedSecret = input.secretValue;
      return {
        ok: true,
        profile: input.profile ?? { accountId: input.accountId },
        credentialHandle: {
          credentialId: `plex-account:${input.accountId}`,
          accountId: input.accountId,
          kind: 'plex-account' as const,
          createdAtMs: 1,
          updatedAtMs: 1,
        },
        diagnostics: [],
      } as const;
    },
  };
  const service = new DesktopPlexAuthService({
    config: authConfig(),
    transport,
    credentialStore,
  });
  const abortController = new AbortController();
  transport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      kind: 'json',
      data: {
        id: 9,
        code: 'SAVE',
        expiresAt: '2026-05-14T12:00:00.000Z',
        authToken: placeholderManagedToken,
      },
    },
  });
  transport.enqueue('validate-token', {
    status: 200,
    payload: { kind: 'json', data: accountPayload({ id: 'new-account', username: 'new' }) },
  });

  const check = service.checkPinStatus(9, { signal: abortController.signal });
  await saveStarted.promise;
  abortController.abort();
  releaseSave.resolve();

  await assert.rejects(
    () => check,
    (error) => error instanceof PlexAuthError && error.code === 'aborted',
  );
  assert.equal(persistedSecret, null);
  assert.equal(service.getAccountTokenForMain(), null);
  assert.equal(service.getActiveTokenForMain(), null);
});

test('desktop plex discovery ignores aborted selection commits and selected-server persistence', async () => {
  const transport = new FakeDiscoveryTransport();
  const selectedServerStore = new FakeSelectedServerStore();
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore,
    nowMs: () => 60_000,
  });
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-old',
      name: 'Old Server',
      connections: [connection({ address: 'old', uri: 'https://old.example:32400' })],
    }),
    createPlexApiResource({
      clientIdentifier: 'server-new',
      name: 'New Server',
      connections: [connection({ address: 'new', uri: 'https://new.example:32400' })],
    }),
  ];
  transport.enqueueProbe('old', { outcome: 'reachable', latencyMs: 10 });
  await discovery.refreshServers();
  const selectedOld = await discovery.selectServer('server-old', { profileId: 'profile-a' });
  assert.equal(selectedOld.kind, 'selected');
  assert.equal(selectedServerStore.persisted?.serverId, 'server-old');
  assert.equal(discovery.getSelectedServerSummary()?.serverId, 'server-old');
  assert.equal(selectedServerStore.saveCount, 1);

  const newProbe = createDeferred<DesktopPlexConnectionProbeTransportResult>();
  const abortController = new AbortController();
  transport.enqueueProbe('new', newProbe.promise);
  const staleSelection = discovery.selectServer('server-new', {
    profileId: 'profile-a',
    signal: abortController.signal,
  });
  abortController.abort();
  newProbe.resolve({ outcome: 'reachable', latencyMs: 5 });

  await assert.rejects(
    () => staleSelection,
    (error) => error instanceof Error && 'code' in error && error.code === 'aborted',
  );
  assert.equal(selectedServerStore.persisted?.serverId, 'server-old');
  assert.equal(selectedServerStore.saveCount, 1);
  assert.equal(discovery.getSelectedServerSummary()?.serverId, 'server-old');
  assert.equal(discovery.getSelectedConnectionForMain()?.address, 'old');
});

test('desktop plex discovery aborts in-flight selected-server persistence before saving selection', async () => {
  const transport = new FakeDiscoveryTransport();
  const saveStarted = createDeferred<void>();
  const releaseSave = createDeferred<void>();
  let persisted: { serverId: string; name: string; source: PlexServerSelectionSource } | null = {
    serverId: 'server-old',
    name: 'Old Server',
    source: 'manual',
  };
  const selectedServerStore = {
    async readSelectedServerSummary() {
      return persisted === null
        ? null
        : { ...persisted, lastSelectedAtMs: 50_000 };
    },
    async saveSelectedServerSummary(
      server: PlexServer,
      source: PlexServerSelectionSource,
      options: { signal?: AbortSignal | null } = {},
    ) {
      saveStarted.resolve();
      await releaseSave.promise;
      if (options.signal?.aborted) {
        throw new PlexDiscoveryError('aborted', 'Plex selected-server save was aborted');
      }
      persisted = { serverId: server.id, name: server.name, source };
      return { ...persisted, lastSelectedAtMs: 60_000 };
    },
  };
  const discovery = new DesktopPlexServerDiscovery({
    transport,
    selectedServerStore,
    nowMs: () => 60_000,
  });
  transport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-old',
      name: 'Old Server',
      connections: [connection({ address: 'old', uri: 'https://old.example:32400' })],
    }),
    createPlexApiResource({
      clientIdentifier: 'server-new',
      name: 'New Server',
      connections: [connection({ address: 'new', uri: 'https://new.example:32400' })],
    }),
  ];
  transport.enqueueProbe('new', { outcome: 'reachable', latencyMs: 5 });
  await discovery.refreshServers();

  const abortController = new AbortController();
  const selection = discovery.selectServer('server-new', {
    profileId: 'profile-a',
    signal: abortController.signal,
  });
  await saveStarted.promise;
  abortController.abort();
  releaseSave.resolve();

  await assert.rejects(
    () => selection,
    (error) => error instanceof PlexDiscoveryError && error.code === 'aborted',
  );
  assert.equal(persisted?.serverId, 'server-old');
  assert.equal(discovery.getSelectedServerSummary(), null);
  assert.equal(discovery.getSelectedConnectionForMain(), null);
});

test('live plex transport normalizes JSON/text responses, auth headers, status, and aborts', async () => {
  const seen: Array<{ url: string; headers: HeadersInit | undefined }> = [];
  const transport = new LivePlexTransport({
    authConfig: authConfig(),
    fetch: async (url, init) => {
      seen.push({ url: String(url), headers: init?.headers });
      return new Response(JSON.stringify({ ok: true }), {
        status: String(url).includes('/identity') ? 401 : 200,
        headers: { 'Content-Type': 'application/json' },
      });
    },
    timeoutMs: 5,
  });

  const auth = await transport.request({
    action: 'validate-token',
    config: authConfig(),
    token: placeholderAccountToken,
  });
  const probe = await transport.probeConnection({
    server: {} as PlexServer,
    connection: connection({ uri: 'https://server.example:32400' }),
    token: placeholderAccountToken,
  });

  assert.equal(auth.status, 200);
  assert.equal(probe.outcome, 'auth-required');
  assert.equal(new Headers(seen[0]?.headers).get('X-Plex-Token'), placeholderAccountToken);
  assert.equal(new Headers(seen[1]?.headers).get('X-Plex-Token'), placeholderAccountToken);
  assert.equal(new Headers(seen[1]?.headers).get('X-Plex-Client-Identifier'), 'desktop-client');
  assert.equal(new Headers(seen[1]?.headers).get('X-Plex-Product'), 'Lineup Desktop');
  assert.equal(JSON.stringify(auth).includes(placeholderAccountToken), false);
});

test('live plex transport encodes library browse filters and search types safely', async () => {
  const seen: string[] = [];
  const transport = new LivePlexTransport({
    fetch: async (url) => {
      seen.push(String(url));
      return new Response(JSON.stringify({ MediaContainer: { Metadata: [] } }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  });

  await transport.listLibraryItems({
    connection: connection({ uri: 'https://server.example:32400' }),
    token: placeholderAccountToken,
    sectionId: '1',
    offset: 10,
    limit: 25,
    sort: 'titleSort:asc',
    filter: { type: 1, year: 2020 },
    includeCollections: true,
  });
  await transport.searchLibrary({
    connection: connection({ uri: 'https://server.example:32400' }),
    token: placeholderAccountToken,
    query: 'movie',
    sectionId: '1',
    limit: 5,
    types: ['movie', 'episode'],
  });

  const browse = new URL(seen[0] ?? '');
  assert.equal(browse.pathname, '/library/sections/1/all');
  assert.equal(browse.searchParams.get('X-Plex-Container-Start'), '10');
  assert.equal(browse.searchParams.get('X-Plex-Container-Size'), '25');
  assert.equal(browse.searchParams.get('sort'), 'titleSort:asc');
  assert.equal(browse.searchParams.get('type'), '1');
  assert.equal(browse.searchParams.get('year'), '2020');
  assert.equal(browse.searchParams.get('includeCollections'), '1');

  const search = new URL(seen[1] ?? '');
  assert.equal(search.pathname, '/hubs/search');
  assert.equal(search.searchParams.get('query'), 'movie');
  assert.equal(search.searchParams.get('sectionId'), '1');
  assert.equal(search.searchParams.get('limit'), '5');
  assert.equal(search.searchParams.get('types'), 'movie,episode');
  assert.equal(JSON.stringify(seen).includes(placeholderAccountToken), false);
});

test('live plex transport sends account token for plex.tv discovery and separates timeout from caller abort', async () => {
  const seenDiscoveryHeaders: Headers[] = [];
  const discoveryTransport = new LivePlexTransport({
    authConfig: authConfig(),
    fetch: async (_url, init) => {
      const headers = new Headers(init?.headers);
      seenDiscoveryHeaders.push(headers);
      return new Response(JSON.stringify([{ clientIdentifier: 'server-1' }]), {
        status: headers.get('X-Plex-Token') === placeholderAccountToken ? 200 : 401,
        headers: { 'Content-Type': 'application/json' },
      });
    },
    timeoutMs: 5,
  });
  const resources = await discoveryTransport.discoverResources({ token: placeholderAccountToken });
  assert.equal(Array.isArray(resources), true);
  assert.equal(seenDiscoveryHeaders[0]?.get('X-Plex-Token'), placeholderAccountToken);
  assert.equal(seenDiscoveryHeaders[0]?.get('X-Plex-Client-Identifier'), 'desktop-client');
  assert.equal(seenDiscoveryHeaders[0]?.get('X-Plex-Product'), 'Lineup Desktop');

  const timeoutTransport = new LivePlexTransport({
    fetch: (_url, init) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new DOMException('aborted', 'AbortError')), {
          once: true,
        });
      }),
    timeoutMs: 1,
  });
  await assert.rejects(
    () => timeoutTransport.discoverResources({ token: placeholderAccountToken }),
    (error) => error instanceof LivePlexTransportError && error.code === 'timeout' && error.retryable,
  );

  const abortController = new AbortController();
  const aborted = timeoutTransport.discoverResources({
    token: placeholderAccountToken,
    signal: abortController.signal,
  });
  abortController.abort();
  await assert.rejects(
    () => aborted,
    (error) => error instanceof LivePlexTransportError && error.code === 'aborted',
  );

  const alreadyAbortedController = new AbortController();
  alreadyAbortedController.abort();
  const preAbortedTransport = new LivePlexTransport({
    fetch: (_url, init) => {
      assert.equal((init?.signal as AbortSignal | undefined)?.aborted, true);
      return Promise.reject(new DOMException('aborted', 'AbortError'));
    },
    timeoutMs: 100,
  });
  await assert.rejects(
    () => preAbortedTransport.discoverResources({
      token: placeholderAccountToken,
      signal: alreadyAbortedController.signal,
    }),
    (error) => error instanceof LivePlexTransportError && error.code === 'aborted',
  );
});

test('live plex transport requests the short Plex link PIN code form', async () => {
  const seen: URL[] = [];
  const transport = new LivePlexTransport({
    fetch: async (url) => {
      seen.push(url instanceof URL ? url : new URL(String(url)));
      return new Response(JSON.stringify({
        id: 7,
        code: 'ABCD',
        expiresAt: '2026-05-14T12:00:00.000Z',
        authToken: null,
      }), {
        status: 201,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  });

  const result = await transport.request({
    action: 'request-pin',
    config: authConfig(),
  });

  assert.equal(result.status, 201);
  assert.equal(seen[0]?.pathname, '/api/v2/pins');
  assert.equal(seen[0]?.searchParams.has('strong'), false);
});

test('live plex transport uses versioned Plex Home endpoints and sends switch PIN as query', async () => {
  const seen: Array<{ url: URL; init: RequestInit | undefined }> = [];
  const transport = new LivePlexTransport({
    fetch: async (url, init) => {
      seen.push({ url: url instanceof URL ? url : new URL(String(url)), init });
      return new Response(JSON.stringify({ MediaContainer: { User: [] } }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    },
  });

  await transport.request({
    action: 'get-home-users',
    config: authConfig(),
    token: placeholderAccountToken,
    homeEndpointVersion: 'v2',
  });
  await transport.request({
    action: 'get-home-users',
    config: authConfig(),
    token: placeholderAccountToken,
    homeEndpointVersion: 'v1',
  });
  await transport.request({
    action: 'switch-home-user',
    config: authConfig(),
    token: placeholderAccountToken,
    userId: 'kid',
    pin: ' 1234 ',
    homeEndpointVersion: 'v2',
  });

  assert.equal(seen[0]?.url.pathname, '/api/v2/home/users');
  assert.equal(seen[1]?.url.pathname, '/api/home/users');
  assert.equal(seen[2]?.url.pathname, '/api/v2/home/users/kid/switch');
  assert.equal(seen[2]?.url.searchParams.get('pin'), '1234');
  assert.equal(seen[2]?.init?.body, undefined);
  assert.equal(new Headers(seen[2]?.init?.headers).get('X-Plex-Token'), placeholderAccountToken);
});

test('live plex transport redacts switch PINs from request failure causes', async () => {
  const transport = new LivePlexTransport({
    fetch: async (url, init) => {
      const headers = new Headers(init?.headers);
      throw new Error(
        [
          `failed ${String(url)}`,
          `X-Plex-Token=${headers.get('X-Plex-Token') ?? ''}`,
          'pin=1234',
        ].join(' '),
      );
    },
  });

  await assert.rejects(
    () =>
      transport.request({
        action: 'switch-home-user',
        config: authConfig(),
        token: placeholderAccountToken,
        userId: 'kid',
        pin: ' 1234 ',
        homeEndpointVersion: 'v2',
      }),
    (error) => {
      const serialized = JSON.stringify(error);
      return (
        error instanceof LivePlexTransportError &&
        error.code === 'server-unreachable' &&
        !serialized.includes('1234') &&
        !serialized.includes(placeholderAccountToken) &&
        serialized.includes('pin=[REDACTED]')
      );
    },
  );
});

test('plex IPC authorizes exact channels and returns validation/result envelopes', async () => {
  const ipcMain = new FakeIpcMain();
  const seenListItems: unknown[] = [];
  const seenSearches: unknown[] = [];
  const runtime = {
    getSnapshot: (requestId: string) => ({ ok: true, requestId, value: { updatedAtMs: 1 } }),
    requestPin: (requestId: string) => ({ ok: true, requestId, value: { pin: { id: 1 } } }),
    pollPin: (requestId: string, pinId: number) => ({ ok: true, requestId, value: { pinId } }),
    listLibraryItems: (requestId: string, payload: unknown) => {
      seenListItems.push(payload);
      return {
        ok: true,
        requestId,
        value: { sectionId: '1', offset: 0, limit: 100, items: [], snapshot: { updatedAtMs: 1 } },
      };
    },
    searchLibrary: (requestId: string, payload: unknown) => {
      seenSearches.push(payload);
      return {
        ok: true,
        requestId,
        value: { query: 'movie', sectionId: null, items: [], snapshot: { updatedAtMs: 1 } },
      };
    },
    shutdown: async () => undefined,
  };
  registerPlexIpcHandlers({
    runtime: runtime as never,
    isAuthorizedEvent: (event) => event === (AUTHORIZED_EVENT as never),
    createRequestId: (prefix) => `${prefix}-fallback`,
    ipcMain: ipcMain as never,
  });

  const unauthorized = await ipcMain.invoke(LINEUP_PLEX_GET_SNAPSHOT_CHANNEL, {}, {
    requestId: 'snapshot-1',
    payload: {},
  }) as { ok: false; error: { code: string } };
  const invalid = await ipcMain.invoke(LINEUP_PLEX_POLL_PIN_CHANNEL, AUTHORIZED_EVENT, {
    requestId: 'bad',
    payload: { pinId: 0 },
  }) as { ok: false; error: { code: string } };
  const success = await ipcMain.invoke(LINEUP_PLEX_REQUEST_PIN_CHANNEL, AUTHORIZED_EVENT, {
    requestId: 'pin-1',
    payload: {},
  }) as { ok: boolean };
  const extraPayloadKey = await ipcMain.invoke(LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL, AUTHORIZED_EVENT, {
    requestId: 'items-extra-key',
    payload: { sectionId: '1', limit: 10, unexpected: true },
  }) as { ok: false; error: { code: string }; requestId: string };
  const itemsWithFilters = await ipcMain.invoke(LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL, AUTHORIZED_EVENT, {
    requestId: 'items-filters',
    payload: {
      sectionId: '1',
      offset: 0,
      filter: { type: 1, year: 2020 },
      includeCollections: true,
    },
  }) as { ok: boolean };
  const searchWithTypes = await ipcMain.invoke(LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL, AUTHORIZED_EVENT, {
    requestId: 'search-types',
    payload: { query: 'movie', types: ['movie', 'episode'] },
  }) as { ok: boolean };
  const searchZeroLimit = await ipcMain.invoke(LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL, AUTHORIZED_EVENT, {
    requestId: 'search-zero-limit',
    payload: { query: 'movie', limit: 0 },
  }) as { ok: false; error: { code: string }; requestId: string };

  assert.equal(unauthorized.ok, false);
  assert.equal(unauthorized.error.code, 'PLEX_UNAUTHORIZED');
  assert.equal(invalid.ok, false);
  assert.equal(invalid.error.code, 'PLEX_VALIDATION_FAILED');
  assert.equal(success.ok, true);
  assert.equal(extraPayloadKey.ok, false);
  assert.equal(extraPayloadKey.requestId, 'items-extra-key');
  assert.equal(extraPayloadKey.error.code, 'PLEX_VALIDATION_FAILED');
  assert.equal(itemsWithFilters.ok, true);
  assert.equal(searchWithTypes.ok, true);
  assert.equal(searchZeroLimit.ok, false);
  assert.equal(searchZeroLimit.requestId, 'search-zero-limit');
  assert.equal(searchZeroLimit.error.code, 'PLEX_VALIDATION_FAILED');
  assert.deepEqual(seenListItems, [
    {
      sectionId: '1',
      offset: 0,
      filter: { type: 1, year: 2020 },
      includeCollections: true,
    },
  ]);
  assert.deepEqual(seenSearches, [{ query: 'movie', types: ['movie', 'episode'] }]);
  assert.deepEqual(ipcMain.channels.sort(), [
    'lineup:plex:cancelPin',
    'lineup:plex:getHomeUsers',
    'lineup:plex:getMetadata',
    'lineup:plex:getSnapshot',
    'lineup:plex:listLibraryItems',
    'lineup:plex:listLibrarySections',
    'lineup:plex:pollPin',
    'lineup:plex:refreshServers',
    'lineup:plex:requestPin',
    'lineup:plex:restoreSelectedServer',
    'lineup:plex:searchLibrary',
    'lineup:plex:selectServer',
    'lineup:plex:switchHomeUser',
  ]);
});

const AUTHORIZED_EVENT = { authorized: true };

class FakeIpcMain {
  private readonly handlers = new Map<string, (event: unknown, payload: unknown) => unknown>();

  get channels(): string[] {
    return [...this.handlers.keys()];
  }

  handle(channel: string, handler: (event: unknown, payload: unknown) => unknown): void {
    this.handlers.set(channel, handler);
  }

  removeHandler(channel: string): void {
    this.handlers.delete(channel);
  }

  async invoke(channel: string, event: unknown, payload: unknown) {
    const handler = this.handlers.get(channel);
    assert.notEqual(handler, undefined);
    return handler!(event, payload);
  }
}

function createRuntimeFixture(options: {
  sleep?: (durationMs: number, signal?: AbortSignal | null) => Promise<void>;
} = {}) {
  const authTransport = new FakeAuthTransport();
  const credentialStore = new FakeCredentialStore();
  const discoveryTransport = new FakeDiscoveryTransport();
  const selectedServerStore = new FakeSelectedServerStore();
  const discovery = new DesktopPlexServerDiscovery({
    transport: discoveryTransport,
    selectedServerStore,
    nowMs: () => 60_000,
  });
  const libraryTransport = new FakeLibraryTransport();
  const diagnostics = new DiagnosticEventStore();
  const authService = new DesktopPlexAuthService({
    config: authConfig(),
    transport: authTransport,
    credentialStore,
    pollIntervalMs: 1,
    pinTimeoutMs: 25,
    ...(options.sleep !== undefined ? { sleep: options.sleep } : {}),
  });
  const runtime = new DesktopPlexRuntime({
    authService,
    credentialStore,
    serverDiscovery: discovery,
    libraryTransport,
    diagnosticEventStore: diagnostics,
    nowMs: () => 100_000,
  });

  return {
    runtime,
    authTransport,
    credentialStore,
    discoveryTransport,
    selectedServerStore,
    discovery,
    libraryTransport,
    diagnostics,
  };
}

async function signIn(
  fixture: ReturnType<typeof createRuntimeFixture>,
  options: { claimed?: boolean } = {},
): Promise<void> {
  const claimed = options.claimed ?? true;
  fixture.authTransport.enqueue('request-pin', {
    status: 201,
    payload: { kind: 'json', data: { id: 7, code: 'ABCD', expiresAt: '2026-05-14T12:00:00.000Z' } },
  });
  fixture.authTransport.enqueue('check-pin-status', {
    status: 200,
    payload: {
      kind: 'json',
      data: {
        id: 7,
        code: 'ABCD',
        expiresAt: '2026-05-14T12:00:00.000Z',
        authToken: claimed ? placeholderAccountToken : null,
      },
    },
  });
  if (claimed) {
    fixture.authTransport.enqueue('validate-token', {
      status: 200,
      payload: { kind: 'json', data: accountPayload() },
    });
  }
  await fixture.runtime.requestPin('request-pin');
  if (claimed) {
    const polled = await fixture.runtime.pollPin('poll-pin', 7);
    assert.equal(polled.ok, true);
  }
}

async function signInAndSelectServer(fixture: ReturnType<typeof createRuntimeFixture>): Promise<void> {
  await signIn(fixture);
  fixture.discoveryTransport.resources = [
    createPlexApiResource({
      clientIdentifier: 'server-1',
      name: 'Living Room',
      connections: [connection({ address: 'local', uri: 'https://local.example:32400' })],
    }),
  ];
  fixture.discoveryTransport.enqueueProbe('local', { outcome: 'reachable', latencyMs: 12 });
  const refreshed = await fixture.runtime.refreshServers('refresh');
  const selected = await fixture.runtime.selectServer('select', 'server-1');
  assert.equal(refreshed.ok, true);
  assert.equal(selected.ok, true);
}

function authConfig() {
  return {
    clientIdentifier: 'desktop-client',
    product: 'Lineup Desktop',
    version: '0.0.0',
    platform: 'Desktop',
    platformVersion: 'test',
    device: 'Desktop',
    deviceName: 'Lineup Desktop',
  };
}

function accountPayload(input: { id?: string; username?: string } = {}) {
  return {
    id: input.id ?? 'account-1',
    username: input.username ?? 'viewer',
    email: 'viewer@example.invalid',
  };
}

function connection(input: Partial<PlexConnection> = {}): PlexConnection {
  return {
    uri: input.uri ?? 'https://server.example:32400',
    protocol: input.protocol ?? 'https',
    address: input.address ?? 'server',
    port: input.port ?? 32400,
    local: input.local ?? true,
    relay: input.relay ?? false,
    latencyMs: input.latencyMs ?? null,
  };
}

function rawSection(input: Partial<{ key: string; title: string }> = {}) {
  return {
    key: input.key ?? '1',
    uuid: 'library-1',
    title: input.title ?? 'Movies',
    type: 'movie',
    agent: 'agent',
    scanner: 'scanner',
    scannedAt: 1_700_000_000,
  };
}

function rawItem(input: Partial<{ ratingKey: string; title: string; type: string }> = {}) {
  return {
    ratingKey: input.ratingKey ?? 'movie-1',
    key: '/library/metadata/movie-1',
    type: input.type ?? 'movie',
    title: input.title ?? 'Movie',
    summary: 'Summary',
    year: 2026,
    duration: 1_000,
    addedAt: 1_700_000_000,
    updatedAt: 1_700_000_001,
  };
}

function createDeferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((resolver) => {
    resolve = resolver;
  });
  return { promise, resolve };
}

function assertRendererSafe(value: unknown): void {
  assert.equal(containsPlexForbiddenRendererField(value), false);
}
