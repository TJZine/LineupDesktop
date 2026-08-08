import type { ChannelConfig } from '../../domain/channel/types.js';

export function channelLibraryIds(channel: ChannelConfig): string[] {
  const values = libraryIdsFromContentSource(channel.contentSource);
  if (channel.sourceLibraryId !== undefined) values.push(channel.sourceLibraryId);
  return [...new Set(values)];
}

export function libraryIdsFromContentSource(source: ChannelConfig['contentSource']): string[] {
  if (source.type === 'library') return [source.libraryId];
  if (source.type === 'mixed') return source.sources.flatMap(libraryIdsFromContentSource);
  return [];
}
