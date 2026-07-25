import type { PlexCancelPinValue, PlexGetHomeUsersValue, PlexGetMetadataValue, PlexIpcResult, PlexListLibraryItemsValue, PlexListLibrarySectionsValue, PlexPollPinValue, PlexRefreshServersValue, PlexRequestPinValue, PlexRestoreSelectedServerValue, PlexRuntimeError, PlexRuntimeOperation, PlexRuntimeSnapshot, PlexSearchLibraryValue, PlexSelectServerValue, PlexServerSelectionSummary, PlexSwitchHomeUserValue } from '../../contracts/plex.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import {
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
} from '../../domain/channelBuilder/index.js';
import type { DesktopPlexAuthService } from './auth/index.js';
import type { DesktopPlexCredentialStore } from './auth/desktopPlexCredentialStore.js';
import type { DesktopPlexServerDiscovery } from './discovery/index.js';
import type { PlexConnection } from './discovery/types.js';
import { clearTimeout } from 'node:timers';
import {
  createChannelBuilderFacetSession,
  invalidateChannelBuilderFacetSession,
  ChannelBuilderFacetTransportUnavailableError,
  type ChannelBuilderFacetAccessInput,
  type ChannelBuilderFacetSession,
} from './desktopPlexChannelBuilderFacetSource.js';
import {
  DesktopPlexContextNotifications,
  type DesktopPlexBuilderContextListener,
  type DesktopPlexBuilderContextResult,
  type DesktopPlexBuilderContextUnsubscribe,
  type DesktopPlexBuilderLibraryPair,
} from './desktopPlexContextNotifications.js';
import { isSafeLibraryFilter, isSafeSearchLimit, isSafeSearchTypes, normalizeLibraryPagination, type PlexLibrarySection, type PlexMediaType } from './library/index.js';
import { applyFailureSnapshot, applyServerSelectionSnapshot, authRequiredError, cloneRuntimeSnapshot, createInitialSnapshot, failureResult, isOptionalShortString, mapCredentialStatus, recordRuntimeDiagnostic, storageError, stripPinSecretFields, success, validatePositiveInteger, validationError } from './desktopPlexRuntimeSupport.js';
import { DesktopPlexLibraryOperationExecutor } from './desktopPlexLibraryOperationExecutor.js';
import { LivePlexTransportError, type LivePlexChannelBuilderFacetTransport, type LivePlexLibraryTransport } from './livePlexTransport.js';
import { PlexRuntimeOperationOwner, type PlexRuntimeSnapshotCommit } from './plexRuntimeOperationOwner.js';

export interface DesktopPlexRuntimeOptions {
  authService: DesktopPlexAuthService;
  credentialStore: Pick<DesktopPlexCredentialStore, 'readDefaultAccountCredentialSecret'>;
  serverDiscovery: DesktopPlexServerDiscovery;
  libraryTransport: LivePlexLibraryTransport;
  channelBuilderFacetTransport?: LivePlexChannelBuilderFacetTransport;
  diagnosticEventStore?: DiagnosticEventStore;
  nowMs?: () => number;
}

export interface ActivePlexLibraryContext {
  connection: PlexConnection;
  token: string;
  transport: LivePlexLibraryTransport;
}

export class DesktopPlexRuntime {
  private readonly authService: DesktopPlexAuthService;
  private readonly credentialStore: DesktopPlexRuntimeOptions['credentialStore'];
  private readonly serverDiscovery: DesktopPlexServerDiscovery;
  private readonly libraryTransport: LivePlexLibraryTransport;
  private readonly channelBuilderFacetTransport: LivePlexChannelBuilderFacetTransport | null;
  private readonly libraryOperations: DesktopPlexLibraryOperationExecutor;
  private readonly builderContextNotifications = new DesktopPlexContextNotifications();
  private readonly operationOwner: PlexRuntimeOperationOwner;
  private readonly diagnosticEventStore?: DiagnosticEventStore;
  private readonly nowMs: () => number;
  private snapshot: PlexRuntimeSnapshot;
  private authoritativeLibraryPairs: readonly DesktopPlexBuilderLibraryPair[] | null = null;

  constructor(options: DesktopPlexRuntimeOptions) {
    this.authService = options.authService;
    this.credentialStore = options.credentialStore;
    this.serverDiscovery = options.serverDiscovery;
    this.libraryTransport = options.libraryTransport;
    this.channelBuilderFacetTransport = options.channelBuilderFacetTransport ?? null;
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
  getBuilderContextForMain(): DesktopPlexBuilderContextResult {
    return this.builderContextNotifications.get();
  }
  subscribeBuilderContextForMain(
    listener: DesktopPlexBuilderContextListener,
  ): DesktopPlexBuilderContextUnsubscribe {
    return this.builderContextNotifications.subscribe(listener);
  }
  async withChannelBuilderFacetSession<T>(
    input: ChannelBuilderFacetAccessInput,
    run: (session: ChannelBuilderFacetSession) => Promise<T>,
  ): Promise<T> {
    if (this.channelBuilderFacetTransport === null) {
      throw new ChannelBuilderFacetTransportUnavailableError();
    }
    const context = this.requireCurrentBuilderContext(input);
    const token = this.authService.getActiveTokenForMain();
    if (token === null) {
      throw new LivePlexTransportError(
        'auth-required',
        'Channel Builder facet discovery requires Plex authentication',
      );
    }
    const connection = this.requireSelectedConnection('listLibraryItems');
    const controller = new AbortController();
    const abortFromCaller = () => controller.abort(input.signal.reason);
    input.signal.addEventListener('abort', abortFromCaller, { once: true });
    if (input.signal.aborted) abortFromCaller();
    const deadlineDelayMs = Math.max(0, input.deadlineAtMs - this.nowMs());
    const deadline = setTimeout(() => controller.abort(), deadlineDelayMs);
    const unsubscribe = this.subscribeBuilderContextForMain((event) => {
      if (event.kind === 'changed' && !matchesBuilderContext(event.result, input)) {
        controller.abort(CHANNEL_BUILDER_CONTEXT_CHANGED);
      }
    });
    const baseSession = createChannelBuilderFacetSession(
      {
        facetTransport: this.channelBuilderFacetTransport,
        itemTransport: this.libraryTransport,
      },
      {
        connection,
        token,
        libraries: projectFacetLibraries(this.snapshot.library.sections, context.libraryPairs),
      },
    );
    const session = bindSessionSignal(baseSession, controller.signal);
    try {
      const result = await run(session);
      if (controller.signal.reason === CHANNEL_BUILDER_CONTEXT_CHANGED) {
        throw channelBuilderContextChangedError();
      }
      this.requireCurrentBuilderContext(input);
      return result;
    } catch (error) {
      if (controller.signal.reason === CHANNEL_BUILDER_CONTEXT_CHANGED) {
        throw channelBuilderContextChangedError();
      }
      throw error;
    } finally {
      invalidateChannelBuilderFacetSession(baseSession);
      unsubscribe();
      clearTimeout(deadline);
      input.signal.removeEventListener('abort', abortFromCaller);
    }
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
      this.clearAndPublishBuilderContext();
      return { profile: result.activeProfile, snapshot: this.cloneSnapshot() };
    });
  }

  async restoreSelectedServer(requestId: string): Promise<PlexIpcResult<PlexRestoreSelectedServerValue>> {
    return this.operationOwner.run(requestId, 'restoreSelectedServer', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'restoreSelectedServer');
      const profileId = this.requireActiveProfileId('restoreSelectedServer');
      const previousServerId =
        this.serverDiscovery.getSelectedServerSummary()?.serverId ?? null;
      this.setServerStatus('loading', commit);
      const selection = await this.serverDiscovery.restoreSelectedServer({ token, profileId, signal });
      if (selection.kind === 'selected') {
        this.operationOwner.abortExcept('restoreSelectedServer');
      }
      this.applyServerSelection(selection, commit);
      this.clearBuilderContextIfServerChanged(previousServerId);
      return { selection, snapshot: this.cloneSnapshot() };
    });
  }

  async refreshServers(requestId: string): Promise<PlexIpcResult<PlexRefreshServersValue>> {
    return this.operationOwner.run(requestId, 'refreshServers', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'refreshServers');
      const previousServerId =
        this.serverDiscovery.getSelectedServerSummary()?.serverId ?? null;
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
      this.clearBuilderContextIfServerChanged(previousServerId);
      return { servers, snapshot: this.cloneSnapshot() };
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
      const token = await this.requireActiveToken(signal, commit, 'selectServer');
      const profileId = this.requireActiveProfileId('selectServer');
      const previousServerId =
        this.serverDiscovery.getSelectedServerSummary()?.serverId ?? null;
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
      this.clearBuilderContextIfServerChanged(previousServerId);
      return { selection, snapshot: this.cloneSnapshot() };
    });
  }

  async listLibrarySections(requestId: string): Promise<PlexIpcResult<PlexListLibrarySectionsValue>> {
    return this.operationOwner.run(requestId, 'listLibrarySections', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'listLibrarySections');
      const connection = this.requireSelectedConnection('listLibrarySections');
      this.setLibraryStatus('loading', commit);
      this.clearAndPublishBuilderContext();
      let result: Awaited<ReturnType<DesktopPlexLibraryOperationExecutor['listSectionsForMain']>>;
      try {
        result = await this.libraryOperations.listSectionsForMain({
          connection,
          token,
          signal,
        });
      } catch (error) {
        this.clearAndPublishBuilderContext();
        throw error;
      }
      commit((snapshot) => ({
        ...snapshot,
        library: { ...snapshot.library, status: 'ready', sections: result.sections },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      this.authoritativeLibraryPairs =
        result.libraryPairs.length === 0 ? null : result.libraryPairs;
      this.publishBuilderContext();
      return { sections: result.sections, snapshot: this.cloneSnapshot() };
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
    this.operationOwner.shutdown();
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

  private requireCurrentBuilderContext(
    input: ChannelBuilderFacetAccessInput,
  ): Readonly<{ libraryPairs: readonly DesktopPlexBuilderLibraryPair[] }> {
    const result = this.getBuilderContextForMain();
    if (!matchesBuilderContext(result, input) || result === null || !result.ok) {
      throw channelBuilderContextChangedError();
    }
    return { libraryPairs: result.snapshot.libraryPairs };
  }

  private clearAndPublishBuilderContext(): void {
    this.authoritativeLibraryPairs = null;
    this.publishBuilderContext();
  }

  private clearBuilderContextIfServerChanged(previousServerId: string | null): void {
    const selectedServerId =
      this.serverDiscovery.getSelectedServerSummary()?.serverId ?? null;
    if (selectedServerId !== previousServerId) {
      this.clearAndPublishBuilderContext();
    }
  }

  private publishBuilderContext(): void {
    const activeProfileId = this.authService.getActiveUserId()?.trim() ?? '';
    if (activeProfileId.length === 0) {
      this.builderContextNotifications.publish({
        ok: false,
        error: { code: 'profile-unavailable' },
      });
      return;
    }
    const selectedServerId =
      this.serverDiscovery.getSelectedServerSummary()?.serverId.trim() ?? '';
    if (selectedServerId.length === 0) {
      this.builderContextNotifications.publish({
        ok: false,
        error: { code: 'server-unavailable' },
      });
      return;
    }
    if (this.authoritativeLibraryPairs === null) {
      this.builderContextNotifications.publish({
        ok: false,
        error: { code: 'libraries-unavailable' },
      });
      return;
    }
    this.builderContextNotifications.publish({
      ok: true,
      snapshot: {
        activeProfileId,
        selectedServerId,
        libraryPairs: this.authoritativeLibraryPairs,
      },
    });
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

const CHANNEL_BUILDER_CONTEXT_CHANGED = Symbol('channel-builder-context-changed');

function channelBuilderContextChangedError(): Error & { code: 'CHANNEL_CONTEXT_CHANGED' } {
  return Object.assign(new Error('Channel Builder context changed.'), {
    code: 'CHANNEL_CONTEXT_CHANGED' as const,
  });
}

function matchesBuilderContext(
  result: DesktopPlexBuilderContextResult,
  input: ChannelBuilderFacetAccessInput,
): boolean {
  if (result === null || !result.ok) return false;
  const pairsById = new Map(
    result.snapshot.libraryPairs.map((pair) => [pair.libraryId, pair] as const),
  );
  const selectedPairs: DesktopPlexBuilderLibraryPair[] = [];
  for (const libraryId of input.selectedLibraryIds) {
    const pair = pairsById.get(libraryId);
    if (pair === undefined) return false;
    selectedPairs.push(pair);
  }
  try {
    return (
      createProfileBinding(result.snapshot.activeProfileId) ===
        input.expectedContext.profileBinding &&
      createServerBinding(result.snapshot.selectedServerId) ===
        input.expectedContext.serverBinding &&
      createLibrarySetBinding(selectedPairs) === input.expectedContext.librarySetBinding
    );
  } catch {
    return false;
  }
}

function projectFacetLibraries(
  sections: readonly PlexRuntimeSnapshot['library']['sections'][number][],
  pairs: readonly DesktopPlexBuilderLibraryPair[],
): readonly PlexLibrarySection[] {
  const pairById = new Map(pairs.map((pair) => [pair.libraryId, pair] as const));
  return sections.map((section) => {
    const pair = pairById.get(section.id);
    if (pair === undefined) throw channelBuilderContextChangedError();
    return {
      id: section.id,
      uuid: pair.libraryUuid,
      title: section.title,
      type: section.type,
      agent: '',
      scanner: '',
      contentCount: section.contentCount,
      ...(section.episodeCount === undefined ? {} : { episodeCount: section.episodeCount }),
      lastScannedAt: new Date(section.lastScannedAtMs),
      art: null,
      thumb: null,
    };
  });
}

function bindSessionSignal(
  session: ChannelBuilderFacetSession,
  signal: AbortSignal,
): ChannelBuilderFacetSession {
  return {
    libraries: session.libraries,
    listCollectionsPage: (request) =>
      session.listCollectionsPage({ ...request, signal }),
    listServerPlaylistsPage: (request) =>
      session.listServerPlaylistsPage({ ...request, signal }),
    listTagDirectoryPage: (request) =>
      session.listTagDirectoryPage({ ...request, signal }),
    listLibraryItemsPage: (request) =>
      session.listLibraryItemsPage({ ...request, signal }),
  };
}
