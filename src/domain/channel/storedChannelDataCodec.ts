import type { StoredChannelData } from './types.js';

function isStoredChannelDataShape(value: unknown): value is Partial<StoredChannelData> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }

  const candidate = value as Partial<StoredChannelData>;
  return Array.isArray(candidate.channels) && Array.isArray(candidate.channelOrder);
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
