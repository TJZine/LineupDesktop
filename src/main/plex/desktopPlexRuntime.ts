import type { PlexCancelPinValue, PlexGetHomeUsersValue, PlexGetMetadataValue, PlexIpcResult, PlexListLibraryItemsValue, PlexListLibrarySectionsValue, PlexPollPinValue, PlexRefreshServersValue, PlexRequestPinValue, PlexRestoreSelectedServerValue, PlexRuntimeError, PlexRuntimeOperation, PlexRuntimeSnapshot, PlexSearchLibraryValue, PlexSelectServerValue, PlexServerSelectionSummary, PlexSwitchHomeUserValue } from '../../contracts/plex.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { DesktopPlexAuthService } from './auth/index.js';
import type { DesktopPlexCredentialStore } from './auth/desktopPlexCredentialStore.js';
import type { DesktopPlexServerDiscovery } from './discovery/index.js';
import type { PlexConnection } from './discovery/types.js';
import { isSafeLibraryFilter, isSafeSearchLimit, isSafeSearchTypes, normalizeLibraryPagination, type PlexMediaType } from './library/index.js';
import { applyFailureSnapshot, applyServerSelectionSnapshot, authRequiredError, cloneRuntimeSnapshot, createInitialSnapshot, failureResult, isOptionalShortString, mapCredentialStatus, recordRuntimeDiagnostic, storageError, stripPinSecretFields, success, validatePositiveInteger, validationError } from './desktopPlexRuntimeSupport.js';
import { DesktopPlexLibraryOperationExecutor } from './desktopPlexLibraryOperationExecutor.js';
import { LivePlexTransportError, type LivePlexChannelSetupTransport, type LivePlexLibraryTransport } from './livePlexTransport.js';
import { PlexRuntimeOperationOwner, type PlexRuntimeSnapshotCommit } from './plexRuntimeOperationOwner.js';

export interface DesktopPlexRuntimeOptions {
  authService: DesktopPlexAuthService;
  credentialStore: Pick<DesktopPlexCredentialStore, 'readDefaultAccountCredentialSecret'>;
  serverDiscovery: DesktopPlexServerDiscovery;
  libraryTransport: LivePlexLibraryTransport;
  diagnosticEventStore?: DiagnosticEventStore;
  nowMs?: () => number;
}

export interface ActivePlexLibraryContext {
  connection: PlexConnection;
  token: string;
  transport: LivePlexLibraryTransport;
}

export interface ActiveChannelSetupContext extends ActivePlexLibraryContext {
  profileId: string;
  serverId: string;
  transport: LivePlexChannelSetupTransport;
}

export class DesktopPlexRuntime {
  private readonly authService: DesktopPlexAuthService;
  private readonly credentialStore: DesktopPlexRuntimeOptions['credentialStore'];
  private readonly serverDiscovery: DesktopPlexServerDiscovery;
  private readonly libraryTransport: LivePlexLibraryTransport;
  private readonly libraryOperations: DesktopPlexLibraryOperationExecutor;
  private readonly operationOwner: PlexRuntimeOperationOwner;
  private readonly diagnosticEventStore?: DiagnosticEventStore;
  private readonly nowMs: () => number;
  private readonly channelSetupContextListeners = new Set<() => void>();
  private snapshot: PlexRuntimeSnapshot;

  constructor(options: DesktopPlexRuntimeOptions) {
    this.authService = options.authService;
    this.credentialStore = options.credentialStore;
    this.serverDiscovery = options.serverDiscovery;
    this.libraryTransport = options.libraryTransport;
    this.libraryOperations = new DesktopPlexLibraryOperationExecutor(options.libraryTransport);
    this.diagnosticEventStore = options.diagnosticEventStore;
    this.nowMs = options.nowMs ?? Date.now;
    this.snapshot = createInitialSnapshot(this.nowMs());
    this.operationOwner = new PlexRuntimeOperationOwner({
      commitSnapshot: (update) => {
        this.snapshot = update(this.snapshot);
      },
      fail: <T>(requestId: string, error: PlexRuntimeError, failOptions = {}) =>
        this.fail<T>(requestId, error, failOptions),
      recordDiagnostic: (operation, status, code) => {
        this.recordDiagnostic(operation, status, code);
      },
    });
  }
  getLibraryTransport(): LivePlexLibraryTransport {
    return this.libraryTransport;
  }
  getSelectedConnectionForMain(): PlexConnection | null {
    return this.serverDiscovery.getSelectedConnectionForMain();
  }
  async withActivePlexToken<T>(
    operation: Extract<PlexRuntimeOperation, 'listLibraryItems' | 'getMetadata'> | 'startPlayback',
    run: (token: string) => Promise<T>,
  ): Promise<T> {
    const token = this.authService.getActiveTokenForMain();
    if (token === null) {
      throw new LivePlexTransportError('auth-required', `${operation} requires Plex authentication`);
    }
    return run(token);
  }
  async withActiveLibraryContext<T>(
    operation: Extract<PlexRuntimeOperation, 'listLibraryItems' | 'getMetadata'>,
    run: (context: ActivePlexLibraryContext) => Promise<T>,
  ): Promise<T> {
    const token = await this.withActivePlexToken(operation, async (activeToken) => activeToken);
    const connection = this.requireSelectedConnection(operation);
    return run({
      connection,
      token,
      transport: this.libraryTransport,
    });
  }
  subscribeChannelSetupContextInvalidation(listener: () => void): () => void {
    this.channelSetupContextListeners.add(listener);
    return () => { this.channelSetupContextListeners.delete(listener); };
  }
  async withActiveChannelSetupContext<T>(
    run: (context: ActiveChannelSetupContext) => Promise<T>,
  ): Promise<T> {
    const profileId = this.requireActiveProfileId('listLibraryItems');
    const token = this.authService.getActiveTokenForMain();
    if (token === null) throw authRequiredError('listLibraryItems');
    const connection = this.requireSelectedConnection('listLibraryItems');
    const serverId = this.serverDiscovery.getSelectedServerSummary()?.serverId?.trim() ?? '';
    if (serverId.length === 0) {
      throw new LivePlexTransportError('server-unreachable', 'Channel setup requires a selected Plex server');
    }
    if (!isChannelSetupTransport(this.libraryTransport)) {
      throw new LivePlexTransportError('server-error', 'Plex channel setup facets are unavailable');
    }
    const contextIdentity = this.getChannelSetupContextIdentity();
    const result = await run({ profileId, serverId, connection, token, transport: this.libraryTransport });
    if (contextIdentity !== this.getChannelSetupContextIdentity()) {
      throw new LivePlexTransportError('aborted', 'Channel setup context changed');
    }
    return result;
  }
  getSnapshot(requestId: string): PlexIpcResult<PlexRuntimeSnapshot> {
    return success(requestId, this.cloneSnapshot());
  }
  async requestPin(requestId: string): Promise<PlexIpcResult<PlexRequestPinValue>> {
    return this.operationOwner.run(requestId, 'requestPin', async ({ signal, commit }) => {
      const pin = stripPinSecretFields(await this.authService.requestPin({ signal }));
      commit((snapshot) => ({
        ...snapshot,
        auth: { ...snapshot.auth, state: 'pin-pending', pin },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { pin, snapshot: this.cloneSnapshot() };
    });
  }

  async pollPin(requestId: string, pinId: number): Promise<PlexIpcResult<PlexPollPinValue>> {
    const validation = validatePositiveInteger(pinId, 'pollPin');
    if (validation !== null) {
      return this.fail(requestId, validation);
    }
    return this.operationOwner.run(requestId, `pollPin:${pinId}`, async ({ signal, commit }) => {
      const result = await this.authService.pollForPin(pinId, { signal });
      const pin = stripPinSecretFields(result.pin);
      commit((snapshot) => ({
        ...snapshot,
        auth: {
          ...snapshot.auth,
          state: result.profile === null ? 'pin-pending' : 'signed-in',
          pin,
          profile: result.profile,
          credentialStatus: result.profile === null ? snapshot.auth.credentialStatus : 'present',
        },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { pin, profile: result.profile, snapshot: this.cloneSnapshot() };
    });
  }

  async cancelPin(requestId: string, pinId: number): Promise<PlexIpcResult<PlexCancelPinValue>> {
    const validation = validatePositiveInteger(pinId, 'cancelPin');
    if (validation !== null) {
      return this.fail(requestId, validation);
    }
    this.operationOwner.abort(`pollPin:${pinId}`);
    return this.operationOwner.run(requestId, `cancelPin:${pinId}`, async ({ signal, commit }) => {
      await this.authService.cancelPin(pinId, { signal });
      commit((snapshot) => ({
        ...snapshot,
        auth: {
          ...snapshot.auth,
          state: snapshot.auth.profile === null ? 'signed-out' : 'signed-in',
          pin: snapshot.auth.pin?.id === pinId ? null : snapshot.auth.pin,
        },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { pinId, snapshot: this.cloneSnapshot() };
    });
  }

  async getHomeUsers(requestId: string): Promise<PlexIpcResult<PlexGetHomeUsersValue>> {
    return this.operationOwner.run(requestId, 'getHomeUsers', async ({ signal, commit }) => {
      await this.ensureAccountToken(signal, commit);
      const users = await this.authService.getHomeUsers({ signal });
      commit((snapshot) => ({
        ...snapshot,
        auth: { ...snapshot.auth, homeUsers: users },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { users, snapshot: this.cloneSnapshot() };
    });
  }

  async switchHomeUser(
    requestId: string,
    input: { userId: string; pin?: string | null },
  ): Promise<PlexIpcResult<PlexSwitchHomeUserValue>> {
    const userId = input.userId.trim();
    if (userId.length === 0 || !isOptionalShortString(input.pin)) {
      return this.fail(requestId, validationError('switchHomeUser'));
    }
    return this.operationOwner.run(requestId, 'switchHomeUser', async ({ signal, commit }) => {
      await this.ensureAccountToken(signal, commit);
      const result = await this.authService.switchHomeUser(userId, {
        pin: input.pin ?? null,
        signal,
      });
      this.operationOwner.abortExcept('switchHomeUser');
      this.notifyChannelSetupContextInvalidated();
      this.serverDiscovery.resetDiscoveryContext();
      commit((snapshot) => ({
        ...snapshot,
        auth: {
          ...snapshot.auth,
          state: 'signed-in',
          profile: result.activeProfile,
        },
        servers: {
          status: 'idle',
          selected: null,
          items: [],
          lastSelection: null,
        },
        library: {
          status: 'idle',
          sections: [],
          selectedSectionId: null,
          items: [],
          search: null,
          metadata: null,
        },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { profile: result.activeProfile, snapshot: this.cloneSnapshot() };
    });
  }

  async restoreSelectedServer(requestId: string): Promise<PlexIpcResult<PlexRestoreSelectedServerValue>> {
    return this.operationOwner.run(requestId, 'restoreSelectedServer', async ({ signal, commit }) => {
      const previousContext = this.getChannelSetupContextIdentity();
      try {
        const token = await this.requireActiveToken(signal, commit, 'restoreSelectedServer');
        const profileId = this.requireActiveProfileId('restoreSelectedServer');
        this.setServerStatus('loading', commit);
        const selection = await this.serverDiscovery.restoreSelectedServer({ token, profileId, signal });
        if (selection.kind === 'selected') {
          this.operationOwner.abortExcept('restoreSelectedServer');
        }
        this.applyServerSelection(selection, commit);
        return { selection, snapshot: this.cloneSnapshot() };
      } finally {
        this.notifyChannelSetupContextIfChanged(previousContext);
      }
    });
  }

  async refreshServers(requestId: string): Promise<PlexIpcResult<PlexRefreshServersValue>> {
    return this.operationOwner.run(requestId, 'refreshServers', async ({ signal, commit }) => {
      const previousContext = this.getChannelSetupContextIdentity();
      try {
        const token = await this.requireActiveToken(signal, commit, 'refreshServers');
        this.setServerStatus('loading', commit);
        const servers = await this.serverDiscovery.refreshServers({ token, signal });
        commit((snapshot) => ({
          ...snapshot,
          servers: {
            ...snapshot.servers,
            status: 'ready',
            selected: this.serverDiscovery.getSelectedServerSummary(),
            items: servers,
          },
          lastError: null,
          updatedAtMs: this.nowMs(),
        }));
        return { servers, snapshot: this.cloneSnapshot() };
      } finally {
        this.notifyChannelSetupContextIfChanged(previousContext);
      }
    });
  }

  async selectServer(
    requestId: string,
    serverId: string,
  ): Promise<PlexIpcResult<PlexSelectServerValue>> {
    const normalizedServerId = serverId.trim();
    if (normalizedServerId.length === 0) {
      return this.fail(requestId, validationError('selectServer'));
    }
    return this.operationOwner.run(requestId, 'selectServer', async ({ signal, commit }) => {
      const previousContext = this.getChannelSetupContextIdentity();
      try {
        const token = await this.requireActiveToken(signal, commit, 'selectServer');
        const profileId = this.requireActiveProfileId('selectServer');
        this.setServerStatus('loading', commit);
        const selection = await this.serverDiscovery.selectServer(normalizedServerId, {
          source: 'manual',
          token,
          profileId,
          signal,
        });
        if (selection.kind === 'selected') {
          this.operationOwner.abortExcept('selectServer');
        }
        this.applyServerSelection(selection, commit);
        return { selection, snapshot: this.cloneSnapshot() };
      } finally {
        this.notifyChannelSetupContextIfChanged(previousContext);
      }
    });
  }

  async listLibrarySections(requestId: string): Promise<PlexIpcResult<PlexListLibrarySectionsValue>> {
    return this.operationOwner.run(requestId, 'listLibrarySections', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'listLibrarySections');
      const connection = this.requireSelectedConnection('listLibrarySections');
      this.setLibraryStatus('loading', commit);
      const sections = await this.libraryOperations.listSections({
        connection,
        token,
        signal,
      });
      commit((snapshot) => ({
        ...snapshot,
        library: { ...snapshot.library, status: 'ready', sections },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { sections, snapshot: this.cloneSnapshot() };
    });
  }

  async listLibraryItems(
    requestId: string,
    input: {
      sectionId: string;
      offset?: number;
      limit?: number;
      sort?: string;
      filter?: Readonly<Record<string, string | number>>;
      includeCollections?: boolean;
    },
  ): Promise<PlexIpcResult<PlexListLibraryItemsValue>> {
    const sectionId = input.sectionId.trim();
    if (
      sectionId.length === 0 ||
      !isOptionalShortString(input.sort) ||
      !isSafeLibraryFilter(input.filter) ||
      (input.includeCollections !== undefined && typeof input.includeCollections !== 'boolean')
    ) {
      return this.fail(requestId, validationError('listLibraryItems'));
    }
    if (typeof input.limit === 'number' && Number.isFinite(input.limit) && input.limit <= 0) {
      return this.operationOwner.run(requestId, 'listLibraryItems', async ({ commit }) => {
        commit((snapshot) => ({
          ...snapshot,
          library: {
            ...snapshot.library,
            status: 'ready',
            selectedSectionId: sectionId,
            items: [],
          },
          lastError: null,
          updatedAtMs: this.nowMs(),
        }));
        return { sectionId, offset: normalizeLibraryPagination(input).offset, limit: 0, items: [], snapshot: this.cloneSnapshot() };
      });
    }
    return this.operationOwner.run(requestId, 'listLibraryItems', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'listLibraryItems');
      const connection = this.requireSelectedConnection('listLibraryItems');
      this.setLibraryStatus('loading', commit);
      const result = await this.libraryOperations.listItems(
        {
          sectionId,
          ...(input.offset !== undefined ? { offset: input.offset } : {}),
          ...(input.limit !== undefined ? { limit: input.limit } : {}),
          ...(input.sort !== undefined ? { sort: input.sort } : {}),
          ...(input.filter !== undefined ? { filter: input.filter } : {}),
          ...(input.includeCollections !== undefined ? { includeCollections: input.includeCollections } : {}),
        },
        { connection, token, signal },
      );
      commit((snapshot) => ({
        ...snapshot,
        library: {
          ...snapshot.library,
          status: 'ready',
          selectedSectionId: sectionId,
          items: result.items,
        },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { sectionId, offset: result.offset, limit: result.limit, items: result.items, snapshot: this.cloneSnapshot() };
    });
  }

  async searchLibrary(
    requestId: string,
    input: { query: string; sectionId?: string; limit?: number; types?: readonly PlexMediaType[] },
  ): Promise<PlexIpcResult<PlexSearchLibraryValue>> {
    const query = input.query.trim();
    const sectionId = input.sectionId?.trim() ?? null;
    if (
      query.length === 0 ||
      sectionId === '' ||
      !isSafeSearchTypes(input.types) ||
      !isSafeSearchLimit(input.limit)
    ) {
      return this.fail(requestId, validationError('searchLibrary'));
    }
    const limit = normalizeLibraryPagination({ limit: input.limit }).limit;
    return this.operationOwner.run(requestId, 'searchLibrary', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'searchLibrary');
      const connection = this.requireSelectedConnection('searchLibrary');
      this.setLibraryStatus('loading', commit);
      const summaries = await this.libraryOperations.search(
        {
          query,
          sectionId,
          limit,
          ...(input.types !== undefined ? { types: input.types } : {}),
        },
        { connection, token, signal },
      );
      commit((snapshot) => ({
        ...snapshot,
        library: {
          ...snapshot.library,
          status: 'ready',
          search: { query, items: summaries },
        },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { query, sectionId, items: summaries, snapshot: this.cloneSnapshot() };
    });
  }

  async getMetadata(
    requestId: string,
    ratingKey: string,
  ): Promise<PlexIpcResult<PlexGetMetadataValue>> {
    const normalizedRatingKey = ratingKey.trim();
    if (normalizedRatingKey.length === 0) {
      return this.fail(requestId, validationError('getMetadata'));
    }
    return this.operationOwner.run(requestId, 'getMetadata', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'getMetadata');
      const connection = this.requireSelectedConnection('getMetadata');
      this.setLibraryStatus('loading', commit);
      const item = await this.libraryOperations.getMetadata(
        normalizedRatingKey,
        { connection, token, signal },
      );
      commit((snapshot) => ({
        ...snapshot,
        library: { ...snapshot.library, status: 'ready', metadata: item ?? null },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { item: item ?? null, snapshot: this.cloneSnapshot() };
    });
  }

  async shutdown(): Promise<void> {
    this.notifyChannelSetupContextInvalidated();
    this.channelSetupContextListeners.clear();
    this.operationOwner.shutdown();
  }

  private notifyChannelSetupContextInvalidated(): void {
    for (const listener of this.channelSetupContextListeners) listener();
  }

  private notifyChannelSetupContextIfChanged(previousContext: string): void {
    if (previousContext !== this.getChannelSetupContextIdentity()) {
      this.notifyChannelSetupContextInvalidated();
    }
  }

  private getChannelSetupContextIdentity(): string {
    const profileId = this.authService.getActiveUserId()?.trim() ?? '';
    const serverId = this.serverDiscovery.getSelectedServerSummary()?.serverId?.trim() ?? '';
    const connection = this.serverDiscovery.getSelectedConnectionForMain();
    return `${profileId}\0${serverId}\0${connection?.uri ?? ''}`;
  }

  private async ensureAccountToken(
    signal: AbortSignal,
    commit: PlexRuntimeSnapshotCommit,
  ): Promise<string> {
    const existingToken = this.authService.getAccountTokenForMain();
    if (existingToken !== null) {
      return existingToken;
    }
    const read = await this.credentialStore.readDefaultAccountCredentialSecret();
    if (read.status !== 'present') {
      commit((snapshot) => ({
        ...snapshot,
        auth: { ...snapshot.auth, credentialStatus: mapCredentialStatus(read.status) },
        updatedAtMs: this.nowMs(),
      }));
      throw storageError(read.status);
    }
    const restoredProfile = await this.authService.restoreAccountToken(read.secretValue, { signal });
    commit((snapshot) => ({
      ...snapshot,
      auth: {
        ...snapshot.auth,
        state: 'signed-in',
        profile: restoredProfile,
        credentialStatus: 'present',
      },
      updatedAtMs: this.nowMs(),
    }));
    return read.secretValue;
  }

  private async requireActiveToken(
    signal: AbortSignal,
    commit: PlexRuntimeSnapshotCommit,
    operation: PlexRuntimeOperation,
  ): Promise<string> {
    await this.ensureAccountToken(signal, commit);
    const token = this.authService.getActiveTokenForMain();
    if (token === null) {
      throw authRequiredError(operation);
    }
    return token;
  }

  private requireSelectedConnection(operation: PlexRuntimeOperation) {
    const connection = this.serverDiscovery.getSelectedConnectionForMain();
    if (connection === null) {
      throw new LivePlexTransportError(
        'server-unreachable',
        `${operation} requires a selected Plex server`,
      );
    }
    return connection;
  }

  private requireActiveProfileId(operation: PlexRuntimeOperation): string {
    const profileId = this.authService.getActiveUserId()?.trim() ?? '';
    if (profileId.length === 0) {
      throw authRequiredError(operation);
    }
    return profileId;
  }

  private setServerStatus(
    status: PlexRuntimeSnapshot['servers']['status'],
    commit: PlexRuntimeSnapshotCommit,
  ): void {
    commit((snapshot) => ({
      ...snapshot,
      servers: { ...snapshot.servers, status },
      updatedAtMs: this.nowMs(),
    }));
  }

  private setLibraryStatus(
    status: PlexRuntimeSnapshot['library']['status'],
    commit: PlexRuntimeSnapshotCommit,
  ): void {
    commit((snapshot) => ({
      ...snapshot,
      library: { ...snapshot.library, status },
      updatedAtMs: this.nowMs(),
    }));
  }

  private applyServerSelection(
    selection: PlexServerSelectionSummary,
    commit: PlexRuntimeSnapshotCommit,
  ): void {
    commit((snapshot) => applyServerSelectionSnapshot({
      snapshot,
      selection,
      selected: this.serverDiscovery.getSelectedServerSummary(),
      items: this.serverDiscovery.getServerSummaries(),
      nowMs: this.nowMs(),
    }));
  }

  private fail<T>(
    requestId: string,
    error: PlexRuntimeError,
    options: { cancelled?: boolean; stale?: boolean; mutateSnapshot?: boolean } = {},
  ): PlexIpcResult<T> {
    if (options.mutateSnapshot ?? true) {
      this.snapshot = applyFailureSnapshot(this.snapshot, error, this.nowMs());
    }
    return failureResult(requestId, error, options);
  }

  private recordDiagnostic(
    operation: PlexRuntimeOperation,
    status: 'started' | 'succeeded' | 'failed' | 'cancelled',
    code?: string,
  ): void {
    recordRuntimeDiagnostic({
      eventStore: this.diagnosticEventStore,
      snapshot: this.snapshot,
      operation,
      status,
      ...(code !== undefined ? { code } : {}),
    });
  }

  private cloneSnapshot(): PlexRuntimeSnapshot {
    return cloneRuntimeSnapshot(this.snapshot);
  }
}

function isChannelSetupTransport(transport: LivePlexLibraryTransport): transport is LivePlexChannelSetupTransport {
  const candidate = transport as Partial<LivePlexChannelSetupTransport>;
  return typeof candidate.listVideoPlaylists === 'function' && typeof candidate.listLibraryTagDirectory === 'function';
}
