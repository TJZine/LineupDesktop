export interface BlockPlaybackItem {
  ratingKey: string;
  showTitle?: string;
  showThumb?: string | null;
}

export function getBlockGroupKey(item: BlockPlaybackItem): string {
  return item.showThumb ?? item.showTitle ?? item.ratingKey;
}

export function applyBlockPlaybackMode<TItem extends BlockPlaybackItem>(options: {
  items: TItem[];
  seed: number;
  blockSize: number;
  shuffleKeys: (keys: string[], seed: number) => string[];
}): TItem[] {
  const { items, seed, blockSize, shuffleKeys } = options;

  if (!Number.isInteger(blockSize) || blockSize <= 0) {
    throw new RangeError(`[applyBlockPlaybackMode] Invalid blockSize=${String(blockSize)}`);
  }

  const groups = new Map<string, TItem[]>();
  for (const item of items) {
    const key = getBlockGroupKey(item);
    const group = groups.get(key);
    if (group) {
      group.push(item);
    } else {
      groups.set(key, [item]);
    }
  }

  const keys = shuffleKeys(Array.from(groups.keys()), seed);
  const queues = keys.map((key) => ({
    items: groups.get(key) ?? [],
    offset: 0,
  }));

  const result: TItem[] = [];
  while (queues.length > 0) {
    for (let index = 0; index < queues.length; index++) {
      const queue = queues[index];
      if (!queue) {
        continue;
      }

      const endExclusive = Math.min(queue.items.length, queue.offset + blockSize);
      for (let itemIndex = queue.offset; itemIndex < endExclusive; itemIndex++) {
        const item = queue.items[itemIndex];
        if (item) {
          result.push(item);
        }
      }

      queue.offset = endExclusive;
      if (queue.offset >= queue.items.length) {
        queues.splice(index, 1);
        index--;
      }
    }
  }

  return result;
}
