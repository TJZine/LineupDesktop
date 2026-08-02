import {
  type ChannelAggregate,
  type ChannelAggregateMutationResult,
  type ChannelPersistenceStore,
} from '../../domain/channel/channelPersistenceStore.js';
import { cloneChannelForOwnership } from '../../domain/channel/channelDomainClone.js';
import type { GuideArtworkSessionGenerationOwner } from '../plex/guideArtworkSessionGenerationOwner.js';

export class ChannelLineupMutationCoordinator {
  public constructor(
    private readonly store: ChannelPersistenceStore,
    private readonly guideArtworkSessionGenerationOwner?: GuideArtworkSessionGenerationOwner,
  ) {}

  public async mutateBuilderLineup(input: Readonly<{
    expectedLineupRevision: number;
    mutate: (current: Readonly<ChannelAggregate>) => ChannelAggregate;
    onCommitBarrier: () => 'proceed' | 'cancel';
  }>): Promise<ChannelAggregateMutationResult> {
    const lease = this.guideArtworkSessionGenerationOwner?.beginTransition('lineup-transition');
    try {
      return await this.store.mutateChannelAggregate({
        kind: 'builder-lineup',
        expectedLineupRevision: input.expectedLineupRevision,
        mutate: input.mutate,
        onCommitBarrier: input.onCommitBarrier,
      });
    } finally {
      lease?.settle();
    }
  }

  public async mutateCustomLineup(input: Readonly<{
    mutate: (current: Readonly<ChannelAggregate>) => ChannelAggregate;
    shouldCommit?: () => boolean;
  }>): Promise<
    | Readonly<{ status: 'committed'; aggregate: ChannelAggregate }>
    | Readonly<{ status: 'rejected' }>
  > {
    const lease = this.guideArtworkSessionGenerationOwner?.beginTransition('lineup-transition');
    try {
      const result = await this.store.mutateChannelAggregate({
        kind: 'custom-lineup',
        expectedLineupRevision: null,
        mutate: input.mutate,
        onCommitBarrier: () => input.shouldCommit?.() === false ? 'cancel' : 'proceed',
      });
      if (result.status === 'canceled') return { status: 'rejected' };
      if (result.status !== 'committed') {
        throw new Error('Custom channel aggregate mutation did not commit.');
      }
      return result;
    } finally {
      lease?.settle();
    }
  }

  public async setCurrentChannel(input: Readonly<{
    channelId: string | null;
  }>): Promise<
    | Readonly<{ status: 'committed'; aggregate: ChannelAggregate }>
    | Readonly<{ status: 'invalid-channel'; aggregate: ChannelAggregate }>
  > {
    let invalid = false;
    const result = await this.store.mutateChannelAggregate({
      kind: 'current-channel',
      mutate: (latest) => {
        if (
          input.channelId !== null &&
          !latest.storedChannelData?.channels.some(
            (channel) => channel.id === input.channelId,
          )
        ) {
          invalid = true;
          return latest as ChannelAggregate;
        }
        return {
          ...latest,
          currentChannelId: input.channelId,
          storedChannelData: latest.storedChannelData === null
            ? null
            : {
                ...latest.storedChannelData,
                channels: latest.storedChannelData.channels.map(cloneChannelForOwnership),
                channelOrder: [...latest.storedChannelData.channelOrder],
                currentChannelId: input.channelId,
              },
        };
      },
      onCommitBarrier: () => 'proceed',
    });
    if (result.status !== 'committed') {
      throw new Error('Current channel aggregate mutation did not commit.');
    }
    if (invalid) return { status: 'invalid-channel', aggregate: result.aggregate };
    return result;
  }
}
