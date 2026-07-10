import type {
  CustomChannelSnapshot,
  CustomChannelStorageSummary,
  CustomChannelSummary,
} from '../../contracts/customChannels.js';
import type { ChannelConfig, ChannelContentSource, StoredChannelData } from '../../domain/channel/index.js';
import { MAX_CHANNELS, MAX_CHANNEL_NUMBER, MIN_CHANNEL_NUMBER } from '../../domain/channel/index.js';

export function summarizeCustomChannelSnapshot(input: {
  data: StoredChannelData | null;
  repaired: boolean;
  updatedAtMs: number;
  storage: CustomChannelStorageSummary['status'];
}): CustomChannelSnapshot {
  const channels = orderChannels(input.data?.channels ?? [], input.data?.channelOrder ?? []);
  const currentChannelId = input.data?.currentChannelId ?? null;
  return {
    channels: channels.map((channel) => summarizeCustomChannel(channel, currentChannelId)),
    currentChannelId,
    visibleChannelCount: channels.filter((channel) => channel.hidden !== true).length,
    hiddenChannelCount: channels.filter((channel) => channel.hidden === true).length,
    maxChannels: MAX_CHANNELS,
    nextAvailableNumber: findNextAvailableNumber(channels),
    updatedAtMs: input.updatedAtMs,
    storage: { status: input.storage, repaired: input.repaired },
  };
}

export function orderChannels(
  channels: readonly ChannelConfig[],
  channelOrder: readonly string[],
): ChannelConfig[] {
  const byId = new Map(channels.map((channel) => [channel.id, channel]));
  const ordered = channelOrder.flatMap((id) => {
    const channel = byId.get(id);
    if (channel === undefined) return [];
    byId.delete(id);
    return [channel];
  });
  return [
    ...ordered,
    ...[...byId.values()].sort((left, right) => left.number - right.number || left.id.localeCompare(right.id)),
  ];
}

export function summarizeCustomChannel(
  channel: ChannelConfig,
  currentChannelId: string | null,
): CustomChannelSummary {
  return {
    id: channel.id,
    number: channel.number,
    name: channel.name,
    description: channel.description ?? null,
    itemCount: channel.itemCount,
    estimatedDurationMs: channel.totalDurationMs,
    sourceSummary: summarizeSource(channel.contentSource),
    playbackMode: channel.playbackMode,
    hidden: channel.hidden === true,
    updatedAtMs: channel.updatedAt,
    isCurrent: currentChannelId === channel.id,
  };
}

export function findNextAvailableNumber(channels: readonly ChannelConfig[]): number | null {
  const used = new Set(channels.map((channel) => channel.number));
  for (let number = MIN_CHANNEL_NUMBER; number <= MAX_CHANNEL_NUMBER; number++) {
    if (!used.has(number)) return number;
  }
  return null;
}

function summarizeSource(source: ChannelContentSource): string {
  switch (source.type) {
    case 'library':
      return source.libraryType === 'show' ? 'Show library' : 'Movie library';
    case 'show':
      return 'Show';
    case 'collection':
      return 'Collection';
    case 'playlist':
      return 'Playlist';
    case 'manual':
      return `${String(source.items.length)} selected item${source.items.length === 1 ? '' : 's'}`;
    case 'mixed':
      return `${String(source.sources.length)} sources`;
  }
}
