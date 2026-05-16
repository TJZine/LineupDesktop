import type { PlexCancelPinValue, PlexGetHomeUsersValue, PlexGetMetadataValue, PlexIpcResult, PlexListLibraryItemsValue, PlexListLibrarySectionsValue, PlexPollPinValue, PlexRefreshServersValue, PlexRequestPinValue, PlexRestoreSelectedServerValue, PlexRuntimeError, PlexRuntimeOperation, PlexRuntimeSnapshot, PlexSearchLibraryValue, PlexSelectServerValue, PlexServerSelectionSummary, PlexSwitchHomeUserValue } from '../../contracts/plex.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import type { DesktopPlexAuthService } from './auth/index.js';
import type { DesktopPlexCredentialStore } from './auth/desktopPlexCredentialStore.js';
import type { DesktopPlexServerDiscovery } from './discovery/index.js';
import { extractLibrarySectionDirectories, extractMetadataArray, extractSearchHubMetadata, extractSearchHubs, normalizeLibraryPagination, parseLibrarySections, parseMediaItems, PLEX_LIBRARY_CONSTANTS, toRendererSafeLibrarySectionSummary, toRendererSafeMediaItemSummary, type PlexMediaType, type RawLibrarySection, type RawMediaItem } from './library/index.js';
import { PlexLibraryError } from './library/plexLibraryError.js';
import { applyFailureSnapshot, applyServerSelectionSnapshot, authRequiredError, cloneRuntimeSnapshot, createInitialSnapshot, failureResult, isOptionalShortString, mapCredentialStatus, mapRuntimeError, normalizeOperationKey, payloadAsContainer, recordRuntimeDiagnostic, staleError, StaleRuntimeMutationError, storageError, stripPinSecretFields, success, validatePositiveInteger, validationError } from './desktopPlexRuntimeSupport.js';
import { LivePlexTransportError, type LivePlexLibraryTransport } from './livePlexTransport.js';

type SnapshotCommit = (update: (snapshot: PlexRuntimeSnapshot) => PlexRuntimeSnapshot) => void;

export interface DesktopPlexRuntimeOptions {
  authService: DesktopPlexAuthService;
  credentialStore: Pick<DesktopPlexCredentialStore, 'readDefaultAccountCredentialSecret'>;
  serverDiscovery: DesktopPlexServerDiscovery;
  libraryTransport: LivePlexLibraryTransport;
  diagnosticEventStore?: DiagnosticEventStore;
  nowMs?: () => number;
}

export class DesktopPlexRuntime {
  private readonly authService: DesktopPlexAuthService;
  private readonly credentialStore: DesktopPlexRuntimeOptions['credentialStore'];
  private readonly serverDiscovery: DesktopPlexServerDiscovery;
  private readonly libraryTransport: LivePlexLibraryTransport;
  private readonly diagnosticEventStore?: DiagnosticEventStore;
  private readonly nowMs: () => number;
  private readonly activeOperations = new Map<string, AbortController>();
  private runtimeEpoch = 0;
  private snapshot: PlexRuntimeSnapshot;

  constructor(options: DesktopPlexRuntimeOptions) {
    this.authService = options.authService;
    this.credentialStore = options.credentialStore;
    this.serverDiscovery = options.serverDiscovery;
    this.libraryTransport = options.libraryTransport;
    this.diagnosticEventStore = options.diagnosticEventStore;
    this.nowMs = options.nowMs ?? Date.now;
    this.snapshot = createInitialSnapshot(this.nowMs());
  }
  getSnapshot(requestId: string): PlexIpcResult<PlexRuntimeSnapshot> {
    return success(requestId, this.cloneSnapshot());
  }
  async requestPin(requestId: string): Promise<PlexIpcResult<PlexRequestPinValue>> {
    return this.runOperation(requestId, 'requestPin', async ({ signal, commit }) => {
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
    return this.runOperation(requestId, `pollPin:${pinId}`, async ({ signal, commit }) => {
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
    this.activeOperations.get(`pollPin:${pinId}`)?.abort();
    return this.runOperation(requestId, `cancelPin:${pinId}`, async ({ signal, commit }) => {
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
    return this.runOperation(requestId, 'getHomeUsers', async ({ signal, commit }) => {
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
    return this.runOperation(requestId, 'switchHomeUser', async ({ signal, commit }) => {
      await this.ensureAccountToken(signal, commit);
      const result = await this.authService.switchHomeUser(userId, {
        pin: input.pin ?? null,
        signal,
      });
      this.abortActiveOperationsExcept('switchHomeUser');
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
    return this.runOperation(requestId, 'restoreSelectedServer', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'restoreSelectedServer');
      const profileId = this.requireActiveProfileId('restoreSelectedServer');
      this.setServerStatus('loading', commit);
      const selection = await this.serverDiscovery.restoreSelectedServer({ token, profileId, signal });
      if (selection.kind === 'selected') {
        this.abortActiveOperationsExcept('restoreSelectedServer');
      }
      this.applyServerSelection(selection, commit);
      return { selection, snapshot: this.cloneSnapshot() };
    });
  }

  async refreshServers(requestId: string): Promise<PlexIpcResult<PlexRefreshServersValue>> {
    return this.runOperation(requestId, 'refreshServers', async ({ signal, commit }) => {
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
    return this.runOperation(requestId, 'selectServer', async ({ signal, commit }) => {
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
        this.abortActiveOperationsExcept('selectServer');
      }
      this.applyServerSelection(selection, commit);
      return { selection, snapshot: this.cloneSnapshot() };
    });
  }

  async listLibrarySections(requestId: string): Promise<PlexIpcResult<PlexListLibrarySectionsValue>> {
    return this.runOperation(requestId, 'listLibrarySections', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'listLibrarySections');
      const connection = this.requireSelectedConnection('listLibrarySections');
      this.setLibraryStatus('loading', commit);
      const payload = await this.libraryTransport.listLibrarySections({ connection, token, signal });
      const sections = parseLibrarySections(
        extractLibrarySectionDirectories(payloadAsContainer<RawLibrarySection>(payload), 'library sections'),
      ).map(toRendererSafeLibrarySectionSummary);
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
      return this.runOperation(requestId, 'listLibraryItems', async ({ commit }) => {
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
    const { offset, limit } = normalizeLibraryPagination(input);
    const hasRequestedLimit = typeof input.limit === 'number' && Number.isFinite(input.limit);
    return this.runOperation(requestId, 'listLibraryItems', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'listLibraryItems');
      const connection = this.requireSelectedConnection('listLibraryItems');
      this.setLibraryStatus('loading', commit);
      const items: RawMediaItem[] = [];
      let nextOffset = offset;
      let iterations = 0;
      while (true) {
        if (++iterations > PLEX_LIBRARY_CONSTANTS.MAX_PAGINATION_ITERATIONS) {
          throw new PlexLibraryError(
            'pagination-limit-exceeded',
            'Plex library pagination limit was exceeded',
          );
        }
        const payload = await this.libraryTransport.listLibraryItems({
          connection,
          token,
          sectionId,
          offset: nextOffset,
          limit,
          ...(input.sort !== undefined ? { sort: input.sort } : {}),
          ...(input.filter !== undefined ? { filter: input.filter } : {}),
          ...(input.includeCollections !== undefined ? { includeCollections: input.includeCollections } : {}),
          signal,
        });
        const pageItems = extractMetadataArray<RawMediaItem>(
          payloadAsContainer<RawMediaItem>(payload),
          'library items',
        );
        items.push(...pageItems);
        if (pageItems.length < limit || (hasRequestedLimit && items.length >= limit)) {
          break;
        }
        nextOffset += pageItems.length;
      }
      const summaries = parseMediaItems(hasRequestedLimit ? items.slice(0, limit) : items)
        .map(toRendererSafeMediaItemSummary);
      commit((snapshot) => ({
        ...snapshot,
        library: {
          ...snapshot.library,
          status: 'ready',
          selectedSectionId: sectionId,
          items: summaries,
        },
        lastError: null,
        updatedAtMs: this.nowMs(),
      }));
      return { sectionId, offset, limit, items: summaries, snapshot: this.cloneSnapshot() };
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
    return this.runOperation(requestId, 'searchLibrary', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'searchLibrary');
      const connection = this.requireSelectedConnection('searchLibrary');
      this.setLibraryStatus('loading', commit);
      const payload = await this.libraryTransport.searchLibrary({
        connection,
        token,
        query,
        sectionId,
        limit,
        ...(input.types !== undefined ? { types: input.types } : {}),
        signal,
      });
      const items = extractSearchHubs(payloadAsContainer<RawMediaItem>(payload), 'search')
        .flatMap((hub) => {
          if (input.types !== undefined && input.types.length > 0) {
            const hubType = mapSearchHubTypeToMediaType(hub.type);
            if (hubType === null || !input.types.includes(hubType)) {
              return [];
            }
          }
          return extractSearchHubMetadata(hub, `search hub "${hub.type}"`);
        })
        .slice(0, limit);
      const summaries = parseMediaItems(items).map(toRendererSafeMediaItemSummary);
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
    return this.runOperation(requestId, 'getMetadata', async ({ signal, commit }) => {
      const token = await this.requireActiveToken(signal, commit, 'getMetadata');
      const connection = this.requireSelectedConnection('getMetadata');
      this.setLibraryStatus('loading', commit);
      const payload = await this.libraryTransport.getMetadata({
        connection,
        token,
        ratingKey: normalizedRatingKey,
        signal,
      }).catch((error: unknown) => {
        if (error instanceof LivePlexTransportError && error.code === 'resource-not-found') {
          return null;
        }
        throw error;
      });
      if (payload === null) {
        commit((snapshot) => ({
          ...snapshot,
          library: { ...snapshot.library, status: 'ready', metadata: null },
          lastError: null,
          updatedAtMs: this.nowMs(),
        }));
        return { item: null, snapshot: this.cloneSnapshot() };
      }
      const item = parseMediaItems(
        extractMetadataArray<RawMediaItem>(payloadAsContainer<RawMediaItem>(payload), 'metadata'),
      ).map(toRendererSafeMediaItemSummary)[0];
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
    this.runtimeEpoch += 1;
    for (const controller of this.activeOperations.values()) {
      controller.abort();
    }
    this.activeOperations.clear();
  }
  private async runOperation<T>(
    requestId: string,
    operationKey: string,
    action: (context: { signal: AbortSignal; commit: SnapshotCommit }) => Promise<T>,
  ): Promise<PlexIpcResult<T>> {
    const operation = normalizeOperationKey(operationKey);
    const previous = this.activeOperations.get(operationKey);
    previous?.abort();
    const controller = new AbortController();
    const epoch = this.runtimeEpoch;
    this.activeOperations.set(operationKey, controller);
    this.recordDiagnostic(operation, 'started');
    const isCurrent = () =>
      this.runtimeEpoch === epoch && this.activeOperations.get(operationKey) === controller;
    const commit: SnapshotCommit = (update) => {
      if (!isCurrent()) {
        throw new StaleRuntimeMutationError();
      }
      this.snapshot = update(this.snapshot);
    };
    try {
      const value = await action({ signal: controller.signal, commit });
      if (!isCurrent()) {
        return this.fail(requestId, staleError(operation), { stale: true, mutateSnapshot: false });
      }
      this.recordDiagnostic(operation, 'succeeded');
      return success(requestId, value);
    } catch (error) {
      const stale = error instanceof StaleRuntimeMutationError || this.runtimeEpoch !== epoch || !isCurrent();
      const runtimeError = stale
        ? staleError(operation)
        : mapRuntimeError(error, operation);
      const cancelled = runtimeError.code === 'PLEX_CANCELLED';
      this.recordDiagnostic(operation, cancelled ? 'cancelled' : 'failed', runtimeError.code);
      return this.fail(requestId, runtimeError, {
        cancelled,
        stale,
        mutateSnapshot: !stale && !cancelled,
      });
    } finally {
      if (this.activeOperations.get(operationKey) === controller) {
        this.activeOperations.delete(operationKey);
      }
    }
  }

  private abortActiveOperationsExcept(operationKey: string): void {
    for (const [activeOperationKey, controller] of this.activeOperations.entries()) {
      if (activeOperationKey === operationKey) {
        continue;
      }
      controller.abort();
      this.activeOperations.delete(activeOperationKey);
    }
  }

  private async ensureAccountToken(
    signal: AbortSignal,
    commit: SnapshotCommit,
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
    commit: SnapshotCommit,
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
    commit: SnapshotCommit,
  ): void {
    commit((snapshot) => ({
      ...snapshot,
      servers: { ...snapshot.servers, status },
      updatedAtMs: this.nowMs(),
    }));
  }

  private setLibraryStatus(
    status: PlexRuntimeSnapshot['library']['status'],
    commit: SnapshotCommit,
  ): void {
    commit((snapshot) => ({
      ...snapshot,
      library: { ...snapshot.library, status },
      updatedAtMs: this.nowMs(),
    }));
  }

  private applyServerSelection(
    selection: PlexServerSelectionSummary,
    commit: SnapshotCommit,
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

const SEARCH_HUB_MEDIA_TYPES: Readonly<Record<string, PlexMediaType>> = { movie: 'movie', movies: 'movie', show: 'show', shows: 'show', episode: 'episode', episodes: 'episode', track: 'track', tracks: 'track', clip: 'clip', clips: 'clip' };

const SAFE_FILTER_KEY_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/u;
const SAFE_LIBRARY_FILTER_KEYS = new Set(['actor', 'audienceRating', 'collection', 'contentRating', 'country', 'decade', 'director', 'episode.unwatched', 'genre', 'hdr', 'producer', 'rating', 'resolution', 'studio', 'subtitleLanguage', 'type', 'unwatched', 'watched', 'writer', 'year']);
const SAFE_SEARCH_TYPES = new Set<PlexMediaType>(['movie', 'show', 'episode', 'track', 'clip']);

function isSafeLibraryFilter(value: unknown): value is Readonly<Record<string, string | number>> | undefined {
  if (value === undefined) {
    return true;
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return false;
  }
  for (const [key, child] of Object.entries(value)) {
    if (!SAFE_FILTER_KEY_PATTERN.test(key) || !SAFE_LIBRARY_FILTER_KEYS.has(key)) {
      return false;
    }
    if (typeof child === 'number' && Number.isFinite(child)) {
      continue;
    }
    if (typeof child === 'string' && child.length > 0 && child.length <= 256) {
      continue;
    }
    return false;
  }
  return true;
}

function isSafeSearchTypes(value: unknown): value is readonly PlexMediaType[] | undefined {
  return (
    value === undefined ||
    (Array.isArray(value) &&
      value.length <= SAFE_SEARCH_TYPES.size &&
      value.every((type) => SAFE_SEARCH_TYPES.has(type)))
  );
}

function isSafeSearchLimit(value: unknown): value is number | undefined {
  return value === undefined ||
    (typeof value === 'number' && Number.isFinite(value) && Number.isInteger(value) && value > 0);
}

function mapSearchHubTypeToMediaType(type: string): PlexMediaType | null {
  return SEARCH_HUB_MEDIA_TYPES[type.trim().toLowerCase()] ?? null;
}
