import type {
  DesktopSettingsSnapshot,
  DesktopSettingsValues,
} from '../../contracts/settings.js';
import type { DesktopSettingsStore } from '../persistence/desktopSettingsStore.js';

type DesktopSettingsSnapshotStore = Pick<DesktopSettingsStore, 'loadSnapshot' | 'replace'>;

export class DesktopSettingsSnapshotOwner {
  private snapshot: DesktopSettingsSnapshot;

  constructor(
    private readonly store: DesktopSettingsSnapshotStore,
    initialSnapshot: DesktopSettingsSnapshot,
  ) {
    this.snapshot = copySnapshot(initialSnapshot);
  }

  observeSnapshot(): DesktopSettingsSnapshot {
    return copySnapshot(this.snapshot);
  }

  async loadSnapshot(): Promise<DesktopSettingsSnapshot> {
    const snapshot = await this.store.loadSnapshot();
    this.snapshot = copySnapshot(snapshot);
    return copySnapshot(snapshot);
  }

  async replace(
    expectedRevision: number,
    values: DesktopSettingsValues,
  ): Promise<DesktopSettingsSnapshot> {
    const snapshot = await this.store.replace(expectedRevision, values);
    this.snapshot = copySnapshot(snapshot);
    return copySnapshot(snapshot);
  }
}

function copySnapshot(snapshot: DesktopSettingsSnapshot): DesktopSettingsSnapshot {
  return {
    ...snapshot,
    values: { ...snapshot.values },
  };
}
