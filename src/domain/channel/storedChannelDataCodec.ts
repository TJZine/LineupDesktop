import type { StoredChannelData } from './types.js';

function isStoredChannelDataShape(value: unknown): value is Partial<StoredChannelData> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }

  const candidate = value as Partial<StoredChannelData>;
  return (
    Array.isArray(candidate.channels) &&
    candidate.channels.every((channel) => channel !== null && typeof channel === 'object' && !Array.isArray(channel)) &&
    Array.isArray(candidate.channelOrder) &&
    candidate.channelOrder.every((channelId) => typeof channelId === 'string') &&
    (
      candidate.currentChannelId === undefined ||
      candidate.currentChannelId === null ||
      typeof candidate.currentChannelId === 'string'
    ) &&
    (
      candidate.savedAt === undefined ||
      (typeof candidate.savedAt === 'number' && Number.isFinite(candidate.savedAt))
    )
  );
}

export function decodeStoredChannelData(raw: string): Partial<StoredChannelData> | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }

  return isStoredChannelDataShape(parsed) ? parsed : null;
}

export function encodeStoredChannelData(data: StoredChannelData): string {
  return JSON.stringify(data);
}
