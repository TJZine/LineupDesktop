import type { IShuffleGenerator } from './interfaces.js';
import { shuffleWithSeed } from './shared/prng.js';

export class ShuffleGenerator implements IShuffleGenerator {
  public shuffle<T>(items: T[], seed: number): T[] {
    return shuffleWithSeed(items, seed);
  }

  public shuffleIndices(count: number, seed: number): number[] {
    const indices: number[] = [];
    for (let index = 0; index < count; index++) {
      indices.push(index);
    }
    return this.shuffle(indices, seed);
  }

  public generateSeed(channelId: string, anchorTime: number): number {
    let hash = 0;

    for (let index = 0; index < channelId.length; index++) {
      const char = channelId.charCodeAt(index);
      hash = ((hash << 5) - hash + char) | 0;
    }

    hash = hash ^ (anchorTime | 0);
    hash = hash ^ ((anchorTime / 0x100000000) | 0);

    return Math.abs(hash);
  }
}
