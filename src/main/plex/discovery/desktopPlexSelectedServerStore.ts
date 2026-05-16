import type { PlexSelectedServerSummary } from '../../../contracts/persistence.js';
import type { DesktopPersistenceStore } from '../../persistence/desktopPersistenceStore.js';
import { PlexDiscoveryError } from './plexDiscoveryError.js';
import type { PlexServer, PlexServerSelectionSource } from './types.js';

export interface DesktopPlexSelectedServerStoreOptions {
  persistenceStore: Pick<DesktopPersistenceStore, 'getSelectedPlexServer' | 'setSelectedPlexServer'>;
  nowMs?: () => number;
}

export interface DesktopPlexSelectedServerSaveOptions {
  profileId: string;
  signal?: AbortSignal | null;
}

export class DesktopPlexSelectedServerStore {
  private readonly persistenceStore: DesktopPlexSelectedServerStoreOptions['persistenceStore'];
  private readonly nowMs: () => number;

  constructor(options: DesktopPlexSelectedServerStoreOptions) {
    this.persistenceStore = options.persistenceStore;
    this.nowMs = options.nowMs ?? Date.now;
  }

  async readSelectedServerSummary(profileId: string): Promise<PlexSelectedServerSummary | null> {
    const normalizedProfileId = normalizeProfileId(profileId);
    if (normalizedProfileId === null) {
      return null;
    }
    return this.persistenceStore.getSelectedPlexServer(normalizedProfileId);
  }

  async saveSelectedServerSummary(
    server: PlexServer,
    source: PlexServerSelectionSource,
    options: DesktopPlexSelectedServerSaveOptions,
  ): Promise<PlexSelectedServerSummary> {
    throwIfAborted(options.signal);
    const profileId = normalizeProfileId(options.profileId);
    if (profileId === null) {
      throw new PlexDiscoveryError('auth-required', 'Plex active profile is required to save selected server');
    }
    const summary: PlexSelectedServerSummary = {
      serverId: server.id,
      name: server.name,
      source,
      lastSelectedAtMs: this.nowMs(),
    };
    try {
      await this.persistenceStore.setSelectedPlexServer(profileId, summary, {
        signal: options.signal ?? null,
      });
    } catch (error) {
      throwIfAborted(options.signal);
      throw error;
    }
    const persisted = await this.persistenceStore.getSelectedPlexServer(profileId);
    if (
      persisted?.serverId !== summary.serverId ||
      persisted.name !== summary.name ||
      persisted.source !== summary.source ||
      persisted.lastSelectedAtMs !== summary.lastSelectedAtMs
    ) {
      throw new PlexDiscoveryError('server-error', 'Plex selected-server state could not be saved');
    }
    return summary;
  }

  async clearSelectedServerSummary(profileId: string): Promise<void> {
    const normalizedProfileId = normalizeProfileId(profileId);
    if (normalizedProfileId === null) {
      return;
    }
    await this.persistenceStore.setSelectedPlexServer(normalizedProfileId, null);
  }
}

function throwIfAborted(signal?: AbortSignal | null): void {
  if (signal?.aborted) {
    throw new PlexDiscoveryError('aborted', 'Plex selected-server save was aborted');
  }
}

function normalizeProfileId(profileId: string): string | null {
  const normalized = profileId.trim();
  return normalized.length > 0 ? normalized : null;
}
