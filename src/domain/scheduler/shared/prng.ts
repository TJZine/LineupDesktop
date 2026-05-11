export function createMulberry32(seed: number): () => number {
  let state = seed;
  return function nextRandom(): number {
    let value = (state += 0x6d2b79f5);
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

export function shuffleWithSeed<T>(items: T[], seed: number): T[] {
  if (!Number.isFinite(seed)) {
    throw new Error('Seed must be a finite number');
  }

  if (items.length <= 1) {
    return [...items];
  }

  const result = [...items];
  const random = createMulberry32(seed);

  for (let index = result.length - 1; index > 0; index--) {
    const swapIndex = Math.floor(random() * (index + 1));
    const item = result[index] as T;
    result[index] = result[swapIndex] as T;
    result[swapIndex] = item;
  }

  return result;
}
