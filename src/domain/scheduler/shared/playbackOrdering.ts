import type { ResolvedContentItem } from '../types.js';
import { applyBlockPlaybackMode } from './blockPlayback.js';

export type SharedPlaybackOrderingMode = 'sequential' | 'shuffle' | 'block';

export function applyPlaybackOrdering(options: {
  items: ResolvedContentItem[];
  mode: SharedPlaybackOrderingMode;
  seed: number;
  blockSize: number | undefined;
  shuffleItems: <T>(items: T[], seed: number) => T[];
}): ResolvedContentItem[] {
  const { items, mode, seed, blockSize, shuffleItems } = options;

  switch (mode) {
    case 'sequential':
      return normalizeScheduledIndexes(items);
    case 'shuffle':
      return normalizeScheduledIndexes(shuffleItems(items, seed));
    case 'block':
      return normalizeScheduledIndexes(
        applyBlockPlaybackMode({
          items,
          seed,
          blockSize: normalizeBlockSize(blockSize),
          shuffleKeys: shuffleItems,
        }),
      );
    default:
      return assertNeverSharedPlaybackOrderingMode(mode);
  }
}

function normalizeScheduledIndexes(items: ResolvedContentItem[]): ResolvedContentItem[] {
  return items.map((item, index) => ({
    ...item,
    scheduledIndex: index,
  }));
}

function normalizeBlockSize(blockSize: number | undefined): number {
  const normalizedBlockSize =
    typeof blockSize === 'number' && Number.isFinite(blockSize) ? blockSize : 3;
  return Math.max(1, Math.floor(normalizedBlockSize));
}

function assertNeverSharedPlaybackOrderingMode(mode: never): never {
  throw new Error(`Unknown shared playback ordering mode: ${String(mode)}`);
}
