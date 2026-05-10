import type { PlexSelectedServerSummary } from '../../../contracts/persistence.js';
import type { DesktopPersistenceStore } from '../../persistence/desktopPersistenceStore.js';
import { PlexDiscoveryError } from './plexDiscoveryError.js';
import type { PlexServer, PlexServerSelectionSource } from './types.js';

export interface DesktopPlexSelectedServerStoreOptions {
  persistenceStore: Pick<DesktopPersistenceStore, 'getRendererSafeSnapshot' | 'setSelectedPlexServer'>;
  nowMs?: () => number;
}

export class DesktopPlexSelectedServerStore {
  private readonly persistenceStore: DesktopPlexSelectedServerStoreOptions['persistenceStore'];
  private readonly nowMs: () => number;

  constructor(options: DesktopPlexSelectedServerStoreOptions) {
    this.persistenceStore = options.persistenceStore;
    this.nowMs = options.nowMs ?? Date.now;
  }

  async readSelectedServerSummary(): Promise<PlexSelectedServerSummary | null> {
    const snapshot = await this.persistenceStore.getRendererSafeSnapshot();
    return snapshot.selectedServer;
  }

  async saveSelectedServerSummary(
    server: PlexServer,
    source: PlexServerSelectionSource,
  ): Promise<PlexSelectedServerSummary> {
    const summary: PlexSelectedServerSummary = {
      serverId: server.id,
      name: server.name,
      source,
      lastSelectedAtMs: this.nowMs(),
    };
    const snapshot = await this.persistenceStore.setSelectedPlexServer(summary);
    if (
      snapshot.selectedServer?.serverId !== summary.serverId ||
      snapshot.selectedServer.name !== summary.name ||
      snapshot.selectedServer.source !== summary.source ||
      snapshot.selectedServer.lastSelectedAtMs !== summary.lastSelectedAtMs
    ) {
      throw new PlexDiscoveryError('server-error', 'Plex selected-server state could not be saved');
    }
    return summary;
  }

  async clearSelectedServerSummary(): Promise<void> {
    await this.persistenceStore.setSelectedPlexServer(null);
  }
}
