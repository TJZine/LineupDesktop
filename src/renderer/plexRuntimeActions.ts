import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import type {
  PlexIpcResult,
  PlexRuntimeSnapshot,
} from '../contracts/plex.js';
import {
  applyPlexIpcFailure,
  applyPlexSnapshot,
  clearPlexRendererForCleanup,
  createPlexRuntimeRendererState,
  markPlexRendererOperationPending,
  updatePlexRendererInputs,
  type PlexRendererOperation,
  type PlexRuntimeRendererState,
} from './plexRuntimeState.js';

export interface PlexRuntimeActionScheduler {
  setTimeout: (callback: () => void, delayMs: number) => number;
  clearTimeout: (handle: number) => void;
}

export interface PlexRuntimeController {
  getState: () => PlexRuntimeRendererState;
  setSearchQuery: (query: string) => void;
  setHomeUserPin: (pin: string) => void;
  setSelectedSection: (sectionId: string) => void;
  loadSnapshot: () => Promise<void>;
  requestPin: () => Promise<void>;
  pollPin: () => Promise<void>;
  cancelPin: () => Promise<void>;
  getHomeUsers: () => Promise<void>;
  switchHomeUser: (userId: string) => Promise<void>;
  restoreSelectedServer: () => Promise<void>;
  refreshServers: () => Promise<void>;
  selectServer: (serverId: string) => Promise<void>;
  listLibrarySections: () => Promise<void>;
  listLibraryItems: (sectionId?: string) => Promise<void>;
  searchLibrary: () => Promise<void>;
  getMetadata: (ratingKey: string) => Promise<void>;
  cleanup: () => Promise<void>;
}

export function createPlexRuntimeController({
  bridge,
  onStateChanged,
  scheduler = {
    setTimeout: (callback, delayMs) => window.setTimeout(callback, delayMs),
    clearTimeout: (handle) => window.clearTimeout(handle),
  },
  pollIntervalMs = 2500,
}: {
  bridge: LineupDesktopPreloadApi['plex'];
  onStateChanged: (state: PlexRuntimeRendererState) => void;
  scheduler?: PlexRuntimeActionScheduler;
  pollIntervalMs?: number;
}): PlexRuntimeController {
  let state = createPlexRuntimeRendererState();
  let operationEpoch = 0;
  let disposed = false;
  let pollTimer: number | null = null;
  let activePinId: number | null = null;

  const commit = (nextState: PlexRuntimeRendererState): void => {
    state = nextState;
    onStateChanged(state);
  };

  const commitSnapshot = (snapshot: PlexRuntimeSnapshot, statusText?: string): void => {
    activePinId = snapshot.auth.pin?.claimed === false ? snapshot.auth.pin.id : null;
    commit(applyPlexSnapshot(state, snapshot, statusText));
  };

  const run = async <TValue>(
    operation: PlexRendererOperation,
    invoke: () => Promise<PlexIpcResult<TValue>>,
    applySuccess: (value: TValue) => PlexRuntimeSnapshot | null,
    statusText: string,
  ): Promise<PlexIpcResult<TValue> | null> => {
    if (disposed) {
      return null;
    }
    const epoch = ++operationEpoch;
    commit(markPlexRendererOperationPending(state, operation, true));
    const result = await invoke().catch(() => null);
    if (disposed || epoch !== operationEpoch) {
      return result;
    }
    if (result === null) {
      commit({
        ...markPlexRendererOperationPending(state, operation, false),
        statusText: 'Failed',
        errorText: 'The Plex operation failed.',
      });
      return null;
    }
    if (result.ok) {
      const snapshot = applySuccess(result.value);
      if (snapshot !== null) {
        commitSnapshot(snapshot, statusText);
      }
    } else {
      commit(applyPlexIpcFailure(state, result));
    }
    commit(markPlexRendererOperationPending(state, operation, false));
    return result;
  };

  const clearPollTimer = (): void => {
    if (pollTimer !== null) {
      scheduler.clearTimeout(pollTimer);
      pollTimer = null;
    }
  };

  const schedulePoll = (): void => {
    clearPollTimer();
    if (disposed || activePinId === null) {
      return;
    }
    pollTimer = scheduler.setTimeout(() => {
      pollTimer = null;
      void controller.pollPin();
    }, pollIntervalMs);
  };

  const controller: PlexRuntimeController = {
    getState: () => state,
    setSearchQuery(query: string): void {
      commit(updatePlexRendererInputs(state, { searchQuery: sanitizeInput(query, 120) }));
    },
    setHomeUserPin(pin: string): void {
      commit(updatePlexRendererInputs(state, { homeUserPin: sanitizeInput(pin, 12) }));
    },
    setSelectedSection(sectionId: string): void {
      commit(updatePlexRendererInputs(state, { selectedSectionId: sanitizeInput(sectionId, 120) }));
    },
    async loadSnapshot(): Promise<void> {
      await run('getSnapshot', bridge.getSnapshot, (value) => value, 'Snapshot loaded');
    },
    async requestPin(): Promise<void> {
      clearPollTimer();
      const result = await run(
        'requestPin',
        bridge.requestPin,
        (value) => {
          activePinId = value.pin.id;
          return value.snapshot;
        },
        'PIN requested',
      );
      if (result?.ok) {
        schedulePoll();
      }
    },
    async pollPin(): Promise<void> {
      if (activePinId === null || !Number.isFinite(activePinId) || activePinId <= 0) {
        return;
      }
      const pinId = activePinId;
      const result = await run(
        'pollPin',
        () => bridge.pollPin({ pinId }),
        (value) => value.snapshot,
        'PIN checked',
      );
      if (result?.ok && result.value.pin.claimed === false) {
        schedulePoll();
      }
    },
    async cancelPin(): Promise<void> {
      clearPollTimer();
      const pinId = activePinId ?? state.snapshot?.auth.pin?.id ?? null;
      if (pinId === null || !Number.isFinite(pinId) || pinId <= 0) {
        return;
      }
      activePinId = null;
      await run(
        'cancelPin',
        () => bridge.cancelPin({ pinId }),
        (value) => value.snapshot,
        'PIN cancelled',
      );
    },
    async getHomeUsers(): Promise<void> {
      await run('getHomeUsers', bridge.getHomeUsers, (value) => value.snapshot, 'Profiles loaded');
    },
    async switchHomeUser(userId: string): Promise<void> {
      const safeUserId = sanitizeInput(userId, 120);
      if (safeUserId.length === 0) {
        return;
      }
      const pin = state.homeUserPin.trim();
      await run(
        'switchHomeUser',
        () => bridge.switchHomeUser({ userId: safeUserId, pin: pin.length === 0 ? null : pin }),
        (value) => value.snapshot,
        'Profile switched',
      );
      commit(updatePlexRendererInputs(state, { homeUserPin: '' }));
    },
    async restoreSelectedServer(): Promise<void> {
      await run(
        'restoreSelectedServer',
        bridge.restoreSelectedServer,
        (value) => value.snapshot,
        'Server restored',
      );
    },
    async refreshServers(): Promise<void> {
      await run('refreshServers', bridge.refreshServers, (value) => value.snapshot, 'Servers refreshed');
    },
    async selectServer(serverId: string): Promise<void> {
      const safeServerId = sanitizeInput(serverId, 160);
      if (safeServerId.length === 0) {
        return;
      }
      await run(
        'selectServer',
        () => bridge.selectServer({ serverId: safeServerId }),
        (value) => value.snapshot,
        'Server selected',
      );
    },
    async listLibrarySections(): Promise<void> {
      await run(
        'listLibrarySections',
        bridge.listLibrarySections,
        (value) => value.snapshot,
        'Libraries loaded',
      );
    },
    async listLibraryItems(sectionId?: string): Promise<void> {
      const safeSectionId = sanitizeInput(sectionId ?? state.selectedSectionId ?? '', 120);
      if (safeSectionId.length === 0) {
        return;
      }
      commit(updatePlexRendererInputs(state, { selectedSectionId: safeSectionId }));
      await run(
        'listLibraryItems',
        () => bridge.listLibraryItems({ sectionId: safeSectionId, offset: 0, limit: 24 }),
        (value) => value.snapshot,
        'Items loaded',
      );
    },
    async searchLibrary(): Promise<void> {
      const query = state.searchQuery.trim();
      if (query.length === 0) {
        return;
      }
      await run(
        'searchLibrary',
        () => bridge.searchLibrary({
          query,
          sectionId: state.selectedSectionId ?? undefined,
          limit: 24,
        }),
        (value) => value.snapshot,
        'Search complete',
      );
    },
    async getMetadata(ratingKey: string): Promise<void> {
      const safeRatingKey = sanitizeInput(ratingKey, 160);
      if (safeRatingKey.length === 0) {
        return;
      }
      await run(
        'getMetadata',
        () => bridge.getMetadata({ ratingKey: safeRatingKey }),
        (value) => value.snapshot,
        'Metadata loaded',
      );
    },
    async cleanup(): Promise<void> {
      if (disposed) {
        return;
      }
      ++operationEpoch;
      clearPollTimer();
      const pinId = activePinId ?? state.snapshot?.auth.pin?.id ?? null;
      activePinId = null;
      const cleanupEpoch = operationEpoch;
      commit(clearPlexRendererForCleanup(state));
      if (pinId !== null && Number.isFinite(pinId) && pinId > 0) {
        commit(markPlexRendererOperationPending(state, 'cleanup', true));
        const result = await bridge.cancelPin({ pinId }).catch(() => null);
        if (disposed || cleanupEpoch !== operationEpoch) {
          return;
        }
        if (result?.ok) {
          commit(applyPlexSnapshot(state, result.value.snapshot, 'Cleaned up'));
          commit(clearPlexRendererForCleanup(state));
        } else if (result !== null) {
          commit(applyPlexIpcFailure(state, result));
          commit(clearPlexRendererForCleanup(state));
        }
        commit(markPlexRendererOperationPending(state, 'cleanup', false));
      }
    },
  };

  return controller;
}

function sanitizeInput(value: string, maxLength: number): string {
  return value
    .split('')
    .filter((char) => {
      const code = char.charCodeAt(0);
      return code >= 0x20 && code < 0x7f;
    })
    .join('')
    .trim()
    .slice(0, maxLength);
}
