import { decodeStoredChannelData, encodeStoredChannelData } from './storedChannelDataCodec.js';
import type { StoredChannelData } from './types.js';

export class CorruptChannelPersistenceDataError extends Error {
  public constructor() {
    super('Stored channel data is corrupt.');
    this.name = 'CorruptChannelPersistenceDataError';
  }
}

export interface ChannelPersistenceStoragePort {
  readStoredChannelData(): Promise<string | null>;
  /**
   * Persists the complete stored channel snapshot. Implementations that keep a
   * separate current-channel index must update that index from the encoded
   * snapshot in the same mutation.
   */
  writeStoredChannelData(encoded: string): Promise<void>;
  /**
   * Clears the stored channel snapshot and any separate current-channel pointer
   * in one storage mutation.
   */
  clearStoredChannelData(): Promise<void>;
  readCurrentChannelId(): Promise<string | null>;
  writeCurrentChannelId(channelId: string | null): Promise<void>;
}

export class ChannelPersistenceStore {
  public constructor(private readonly storage: ChannelPersistenceStoragePort) {}

  public async readStoredChannelData(): Promise<Partial<StoredChannelData> | null> {
    const raw = await this.storage.readStoredChannelData();
    if (raw === null) {
      return null;
    }
    if (raw.trim().length === 0) {
      await this.storage.clearStoredChannelData();
      return null;
    }

    const parsed = decodeStoredChannelData(raw);
    if (parsed === null) {
      await this.storage.clearStoredChannelData();
      throw new CorruptChannelPersistenceDataError();
    }
    return parsed;
  }

  public async writeStoredChannelData(data: StoredChannelData): Promise<void> {
    await this.storage.writeStoredChannelData(encodeStoredChannelData(data));
  }

  public async clearStoredChannelData(): Promise<void> {
    await this.storage.clearStoredChannelData();
  }

  public async readCurrentChannelId(): Promise<string | null> {
    const raw = await this.storage.readCurrentChannelId();
    if (raw === null) {
      return null;
    }

    const normalized = raw.trim();
    if (normalized.length === 0) {
      await this.storage.writeCurrentChannelId(null);
      return null;
    }
    if (normalized !== raw) {
      await this.storage.writeCurrentChannelId(normalized);
    }
    return normalized;
  }

  public async writeCurrentChannelId(channelId: string | null): Promise<void> {
    const normalized = channelId?.trim() ?? '';
    await this.storage.writeCurrentChannelId(normalized.length > 0 ? normalized : null);
  }
}
