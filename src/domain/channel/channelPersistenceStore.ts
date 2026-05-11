import { decodeStoredChannelData, encodeStoredChannelData } from './storedChannelDataCodec.js';
import type { StoredChannelData } from './types.js';

export interface ChannelPersistenceStoragePort {
  readStoredChannelData(): Promise<string | null>;
  writeStoredChannelData(encoded: string): Promise<void>;
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
      return null;
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
