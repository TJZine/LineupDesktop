import type {
  CustomChannelDraftInput,
  CustomChannelMediaCard,
  CustomChannelMediaType,
} from '../../contracts/customChannels.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import type { CustomChannelActionId, CustomChannelRendererState } from './controller.js';

export type CustomChannelOperationKind = 'snapshot' | 'duplicate' | 'save' | 'delete' | 'visibility' | 'reorder';

export interface CustomChannelOperationOwner {
  begin(kind: CustomChannelOperationKind, detail?: string): number;
  beginMedia(): number;
  beginMetadata(): number;
  isCurrent(operationId: number): boolean;
  isCurrentMedia(operationId: number): boolean;
  isCurrentMetadata(operationId: number): boolean;
  invalidateAll(): void;
  invalidateMedia(): void;
  invalidateMetadata(): void;
  current(): { kind: CustomChannelOperationKind; detail: string | null } | null;
  clear(operationId: number): void;
}

export function mediaTypesForFilter(filter: CustomChannelRendererState['mediaTypeFilter']): readonly CustomChannelMediaType[] | undefined {
  if (filter === 'movies') return ['movie'];
  if (filter === 'episodes') return ['episode'];
  return undefined;
}

export function filterForAction(action: CustomChannelActionId): CustomChannelRendererState['mediaTypeFilter'] {
  if (action === 'setFilterMovies') return 'movies';
  if (action === 'setFilterEpisodes') return 'episodes';
  return 'all';
}

export function addMediaCardToDraft(
  current: CustomChannelRendererState,
  ratingKey: string,
): CustomChannelRendererState {
  const card = current.mediaPage?.items.find((item) => item.ratingKey === ratingKey);
  if (card === undefined) return current;
  if (card.availability === 'unsupported' || (card.type !== 'movie' && card.type !== 'episode')) {
    return { ...current, lastError: 'Only playable movies and episodes can be added to a custom channel.' };
  }
  if (card.durationMs === null || card.durationMs <= 0) {
    return { ...current, lastError: 'This item is missing a playable duration and cannot be added.' };
  }
  if (current.draft.content.some((entry) => entry.type === 'manualItem' && entry.ratingKey === card.ratingKey)) {
    return { ...current, lastError: 'That item is already in the draft.' };
  }
  return {
    ...current,
    draft: { ...current.draft, content: [...current.draft.content, mediaCardToManualItem(card)] },
    validation: null,
    lastError: null,
    lastSavedChannelId: null,
  };
}

export function removeDraftItem(
  current: CustomChannelRendererState,
  indexText: string,
): CustomChannelRendererState {
  const index = Number.parseInt(indexText, 10);
  if (!Number.isInteger(index) || index < 0 || index >= current.draft.content.length) return current;
  return {
    ...current,
    draft: { ...current.draft, content: current.draft.content.filter((_, candidateIndex) => candidateIndex !== index) },
    validation: null,
    lastError: null,
    lastSavedChannelId: null,
  };
}

function mediaCardToManualItem(card: CustomChannelMediaCard): CustomChannelDraftInput['content'][number] {
  return {
    type: 'manualItem',
    ratingKey: card.ratingKey,
    title: card.title,
    durationMs: card.durationMs ?? 1,
    mediaType: card.type === 'episode' ? 'episode' : 'movie',
    ...(card.parentTitle === undefined ? {} : { parentTitle: card.parentTitle }),
    ...(card.year === null ? {} : { year: card.year }),
    ...(card.seasonNumber === undefined ? {} : { seasonNumber: card.seasonNumber }),
    ...(card.episodeNumber === undefined ? {} : { episodeNumber: card.episodeNumber }),
  };
}

export function normalizeDraftForSave(draft: CustomChannelDraftInput): CustomChannelDraftInput {
  return { ...draft, name: draft.name.trim(), content: [...draft.content] };
}

export async function reorderChannel(
  current: CustomChannelRendererState,
  bridge: LineupDesktopPreloadApi['customChannels'],
  channelId: string,
  delta: -1 | 1,
): Promise<CustomChannelRendererState> {
  const channels = current.snapshot?.channels ?? [];
  const index = channels.findIndex((channel) => channel.id === channelId);
  const nextIndex = index + delta;
  if (index < 0 || nextIndex < 0 || nextIndex >= channels.length) return current;
  const channelIds = channels.map((channel) => channel.id);
  const [moved] = channelIds.splice(index, 1);
  if (moved === undefined) return current;
  channelIds.splice(nextIndex, 0, moved);
  const result = await bridge.reorderChannels({ channelIds });
  if (!result.ok) return { ...current, lastError: result.error.message };
  return { ...current, snapshot: result.value.snapshot, lastError: null };
}

export function createCustomChannelOperationOwner(): CustomChannelOperationOwner {
  let operationSequence = 0;
  let mediaOperationSequence = 0;
  let metadataOperationSequence = 0;
  let active: { id: number; kind: CustomChannelOperationKind; detail: string | null } | null = null;

  return {
    begin(kind, detail) {
      const id = ++operationSequence;
      active = { id, kind, detail: detail ?? null };
      return id;
    },
    beginMedia: () => ++mediaOperationSequence,
    beginMetadata: () => ++metadataOperationSequence,
    isCurrent: (operationId) => operationId === operationSequence,
    isCurrentMedia: (operationId) => operationId === mediaOperationSequence,
    isCurrentMetadata: (operationId) => operationId === metadataOperationSequence,
    invalidateAll() {
      operationSequence++;
      mediaOperationSequence++;
      metadataOperationSequence++;
      active = null;
    },
    invalidateMedia() {
      mediaOperationSequence++;
      metadataOperationSequence++;
    },
    invalidateMetadata() {
      metadataOperationSequence++;
    },
    current: () => active === null ? null : { kind: active.kind, detail: active.detail },
    clear(operationId) {
      if (active?.id === operationId) active = null;
    },
  };
}
