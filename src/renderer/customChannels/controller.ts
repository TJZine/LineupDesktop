import type {
  CustomChannelDraftInput,
  CustomChannelDraftValidationSummary,
  CustomChannelMediaCard,
  CustomChannelMediaMetadata,
  CustomChannelMediaPage,
  CustomChannelMediaType,
  CustomChannelSnapshot,
} from '../../contracts/customChannels.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';

export const CUSTOM_CHANNEL_ACTIONS = [
  'loadSnapshot',
  'browseSource',
  'searchMedia',
  'clearSearch',
  'toggleDraftHidden',
  'setFilterAll',
  'setFilterMovies',
  'setFilterEpisodes',
  'saveDraft',
  'addMedia',
  'openMetadata',
  'closeMetadata',
  'removeDraftItem',
  'duplicateChannel',
  'requestDeleteChannel',
  'confirmDeleteChannel',
  'toggleChannelVisibility',
  'moveChannelUp',
  'moveChannelDown',
] as const;

export type CustomChannelActionId = (typeof CUSTOM_CHANNEL_ACTIONS)[number];

export interface CustomChannelRendererState {
  snapshot: CustomChannelSnapshot | null;
  mediaPage: CustomChannelMediaPage | null;
  metadata: CustomChannelMediaMetadata | null;
  draft: CustomChannelDraftInput;
  validation: CustomChannelDraftValidationSummary | null;
  pending: boolean;
  mediaPending: boolean;
  metadataPending: boolean;
  lastError: string | null;
  query: string;
  mediaTypeFilter: 'all' | 'movies' | 'episodes';
  deleteConfirmationChannelId: string | null;
  lastSavedChannelId: string | null;
}

export interface CustomChannelController {
  getState(): CustomChannelRendererState;
  loadSnapshot(): Promise<void>;
  browseSource(sourceId: string | null): Promise<void>;
  searchMedia(sourceId: string | null): Promise<void>;
  clearSearch(): void;
  clearMediaForSourceChange(): void;
  setDraftName(name: string): void;
  setDraftNumber(numberText: string): void;
  setSearchQuery(query: string): void;
  applyAction(action: CustomChannelActionId, detail?: string): Promise<void>;
  handleBack(): boolean;
}

const DEFAULT_PAGE_LIMIT = 24;

export function createCustomChannelController(input: {
  bridge: LineupDesktopPreloadApi['customChannels'];
  onStateChanged(): void;
}): CustomChannelController {
  let state: CustomChannelRendererState = createInitialState();
  let operationSequence = 0;
  let mediaOperationSequence = 0;
  let metadataOperationSequence = 0;

  const setState = (next: CustomChannelRendererState): void => {
    state = next;
    input.onStateChanged();
  };

  const runOperation = async (
    operation: () => Promise<CustomChannelRendererState>,
  ): Promise<void> => {
    const operationId = ++operationSequence;
    setState({ ...state, pending: true, lastError: null });
    try {
      const next = await operation();
      if (operationId !== operationSequence) return;
      setState({ ...next, pending: false });
    } catch {
      if (operationId !== operationSequence) return;
      setState({ ...state, pending: false, lastError: 'Custom channel action failed. Try again.' });
    }
  };

  const runMediaOperation = async (
    operation: () => Promise<CustomChannelRendererState>,
  ): Promise<void> => {
    const operationId = ++mediaOperationSequence;
    setState({ ...state, mediaPending: true, lastError: null });
    try {
      const next = await operation();
      if (operationId !== mediaOperationSequence) return;
      setState({ ...next, mediaPending: false });
    } catch {
      if (operationId !== mediaOperationSequence) return;
      setState({ ...state, mediaPending: false, lastError: 'Media lookup failed. Try again.' });
    }
  };

  const runMetadataOperation = async (
    operation: () => Promise<CustomChannelRendererState>,
  ): Promise<void> => {
    const operationId = ++metadataOperationSequence;
    setState({ ...state, metadataPending: true, lastError: null });
    try {
      const next = await operation();
      if (operationId !== metadataOperationSequence) return;
      setState({ ...next, metadataPending: false });
    } catch {
      if (operationId !== metadataOperationSequence) return;
      setState({ ...state, metadataPending: false, lastError: 'Media details failed to load. Try again.' });
    }
  };

  const invalidateMediaOperations = (): void => {
    mediaOperationSequence++;
    metadataOperationSequence++;
  };

  return {
    getState: () => state,
    loadSnapshot: async () => {
      await runOperation(async () => applySnapshotResult(state, await input.bridge.getSnapshot()));
    },
    browseSource: async (sourceId) => {
      if (sourceId === null) {
        setState({ ...state, mediaPage: null, lastError: 'Choose a library before browsing media.' });
        return;
      }
      await runMediaOperation(async () =>
        applyMediaResult(state, await input.bridge.listMedia({
          sourceType: 'library',
          sourceId,
          limit: DEFAULT_PAGE_LIMIT,
          mediaTypes: mediaTypesForFilter(state.mediaTypeFilter),
          draftContent: state.draft.content,
        }))
      );
    },
    searchMedia: async (sourceId) => {
      const query = state.query.trim();
      if (query.length === 0) {
        setState({ ...state, lastError: 'Enter a search term before searching media.' });
        return;
      }
      await runMediaOperation(async () =>
        applyMediaResult(state, await input.bridge.listMedia({
          sourceType: 'search',
          ...(sourceId === null ? {} : { sourceId }),
          query,
          limit: DEFAULT_PAGE_LIMIT,
          mediaTypes: mediaTypesForFilter(state.mediaTypeFilter),
          draftContent: state.draft.content,
        }))
      );
    },
    clearSearch: () => {
      invalidateMediaOperations();
      setState({ ...state, query: '', mediaPage: null, metadata: null, mediaPending: false, metadataPending: false, lastError: null });
    },
    clearMediaForSourceChange: () => {
      invalidateMediaOperations();
      setState({
        ...state,
        query: '',
        mediaPage: null,
        metadata: null,
        draft: createDraftFromSnapshotOrInitial(state.snapshot),
        validation: null,
        mediaPending: false,
        metadataPending: false,
        lastError: null,
        lastSavedChannelId: null,
      });
    },
    setDraftName: (name) => {
      setState({
        ...state,
        draft: { ...state.draft, name: name.slice(0, 120) },
        validation: null,
        lastSavedChannelId: null,
      });
    },
    setDraftNumber: (numberText) => {
      const number = Number.parseInt(numberText, 10);
      setState({
        ...state,
        draft: {
          ...state.draft,
          number: Number.isFinite(number) ? number : state.draft.number,
        },
        validation: null,
        lastSavedChannelId: null,
      });
    },
    setSearchQuery: (query) => {
      invalidateMediaOperations();
      setState({
        ...state,
        query: query.slice(0, 128),
        mediaPage: null,
        metadata: null,
        mediaPending: false,
        metadataPending: false,
      });
    },
    applyAction: async (action, detail) => {
      switch (action) {
        case 'loadSnapshot':
          await runOperation(async () => applySnapshotResult(state, await input.bridge.getSnapshot()));
          return;
        case 'toggleDraftHidden':
          setState({
            ...state,
            draft: { ...state.draft, hidden: !state.draft.hidden },
            lastSavedChannelId: null,
          });
          return;
        case 'setFilterAll':
        case 'setFilterMovies':
        case 'setFilterEpisodes':
          invalidateMediaOperations();
          setState({
            ...state,
            mediaTypeFilter: filterForAction(action),
            mediaPage: null,
            metadata: null,
            mediaPending: false,
            metadataPending: false,
            lastError: null,
          });
          return;
        case 'saveDraft':
          await runOperation(async () => {
            const draft = normalizeDraftForSave(state.draft);
            const validation = await input.bridge.validateDraft(draft);
            if (!validation.ok) return { ...state, lastError: validation.error.message };
            if (!validation.value.valid) {
              return {
                ...state,
                validation: validation.value,
                lastError: null,
              };
            }
            const result = await input.bridge.saveDraft(draft);
            if (!result.ok) return { ...state, lastError: result.error.message };
            return {
              ...state,
              snapshot: result.value.snapshot,
              validation: validation.value,
              draft: createDraftFromSnapshot(result.value.snapshot),
              deleteConfirmationChannelId: null,
              lastError: null,
              lastSavedChannelId: result.value.changedChannelId,
            };
          });
          return;
        case 'addMedia':
          if (detail !== undefined) setState(addMediaCardToDraft(state, detail));
          return;
        case 'openMetadata':
          if (detail !== undefined) {
            await runMetadataOperation(async () =>
              applyMetadataResult(state, await input.bridge.getMediaMetadata({ ratingKey: detail }))
            );
          }
          return;
        case 'closeMetadata':
          metadataOperationSequence++;
          setState({ ...state, metadata: null, metadataPending: false, lastError: null });
          return;
        case 'removeDraftItem':
          if (detail !== undefined) setState(removeDraftItem(state, detail));
          return;
        case 'duplicateChannel':
          if (detail !== undefined) {
            await runOperation(async () => {
              const result = await input.bridge.duplicateChannelDraft({ channelId: detail });
              if (!result.ok) return { ...state, lastError: result.error.message };
              return {
                ...state,
                draft: result.value.draft,
                validation: result.value.validation,
                lastError: null,
                lastSavedChannelId: null,
              };
            });
          }
          return;
        case 'requestDeleteChannel':
          setState({ ...state, deleteConfirmationChannelId: detail ?? null, lastError: null });
          return;
        case 'confirmDeleteChannel':
          if (detail !== undefined) {
            await runOperation(async () => {
              const result = await input.bridge.deleteChannel({ channelId: detail, confirm: true });
              if (!result.ok) return { ...state, lastError: result.error.message };
              return {
                ...state,
                snapshot: result.value.snapshot,
                deleteConfirmationChannelId: null,
                lastError: null,
              };
            });
          }
          return;
        case 'toggleChannelVisibility':
          if (detail !== undefined) {
            const channel = state.snapshot?.channels.find((candidate) => candidate.id === detail);
            if (channel === undefined) return;
            await runOperation(async () => {
              const result = await input.bridge.setChannelVisibility({
                channelId: detail,
                hidden: !channel.hidden,
              });
              if (!result.ok) return { ...state, lastError: result.error.message };
              return { ...state, snapshot: result.value.snapshot, lastError: null };
            });
          }
          return;
        case 'moveChannelUp':
        case 'moveChannelDown':
          if (detail !== undefined) {
            await runOperation(async () => reorderChannel(state, input.bridge, detail, action === 'moveChannelUp' ? -1 : 1));
          }
          return;
        case 'browseSource':
        case 'searchMedia':
        case 'clearSearch':
          return;
      }
    },
    handleBack: () => {
      if (state.metadata !== null || state.metadataPending) {
        metadataOperationSequence++;
        setState({ ...state, metadata: null, metadataPending: false });
        return true;
      }
      if (state.deleteConfirmationChannelId !== null) {
        setState({ ...state, deleteConfirmationChannelId: null });
        return true;
      }
      if (state.query.length > 0 || state.mediaPage !== null || state.lastError !== null) {
        invalidateMediaOperations();
        setState({ ...state, query: '', mediaPage: null, mediaPending: false, lastError: null });
        return true;
      }
      return false;
    },
  };
}

function createInitialState(): CustomChannelRendererState {
  return {
    snapshot: null,
    mediaPage: null,
    metadata: null,
    draft: {
      number: 1,
      name: 'Custom Channel',
      hidden: false,
      content: [],
      playbackMode: 'sequential',
    },
    validation: null,
    pending: false,
    mediaPending: false,
    metadataPending: false,
    lastError: null,
    query: '',
    mediaTypeFilter: 'all',
    deleteConfirmationChannelId: null,
    lastSavedChannelId: null,
  };
}

function createDraftFromSnapshotOrInitial(snapshot: CustomChannelSnapshot | null): CustomChannelDraftInput {
  return snapshot === null ? createInitialState().draft : createDraftFromSnapshot(snapshot);
}

function createDraftFromSnapshot(snapshot: CustomChannelSnapshot): CustomChannelDraftInput {
  return {
    number: snapshot.nextAvailableNumber ?? Math.min(snapshot.channels.length + 1, snapshot.maxChannels),
    name: 'Custom Channel',
    hidden: false,
    content: [],
    playbackMode: 'sequential',
  };
}

function applySnapshotResult(
  current: CustomChannelRendererState,
  result: Awaited<ReturnType<LineupDesktopPreloadApi['customChannels']['getSnapshot']>>,
): CustomChannelRendererState {
  if (!result.ok) return { ...current, lastError: result.error.message };
  return {
    ...current,
    snapshot: result.value,
    draft: current.draft.content.length === 0 ? createDraftFromSnapshot(result.value) : current.draft,
    lastError: null,
  };
}

function applyMediaResult(
  current: CustomChannelRendererState,
  result: Awaited<ReturnType<LineupDesktopPreloadApi['customChannels']['listMedia']>>,
): CustomChannelRendererState {
  if (!result.ok) return { ...current, mediaPage: null, lastError: result.error.message };
  return { ...current, mediaPage: result.value, lastError: null };
}

function applyMetadataResult(
  current: CustomChannelRendererState,
  result: Awaited<ReturnType<LineupDesktopPreloadApi['customChannels']['getMediaMetadata']>>,
): CustomChannelRendererState {
  if (!result.ok) return { ...current, metadata: null, lastError: result.error.message };
  return { ...current, metadata: result.value, lastError: null };
}

function mediaTypesForFilter(filter: CustomChannelRendererState['mediaTypeFilter']): readonly CustomChannelMediaType[] | undefined {
  if (filter === 'movies') return ['movie'];
  if (filter === 'episodes') return ['episode'];
  return undefined;
}

function filterForAction(action: CustomChannelActionId): CustomChannelRendererState['mediaTypeFilter'] {
  if (action === 'setFilterMovies') return 'movies';
  if (action === 'setFilterEpisodes') return 'episodes';
  return 'all';
}

function addMediaCardToDraft(
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
    draft: {
      ...current.draft,
      content: [
        ...current.draft.content,
        mediaCardToManualItem(card),
      ],
    },
    validation: null,
    lastError: null,
    lastSavedChannelId: null,
  };
}

function removeDraftItem(
  current: CustomChannelRendererState,
  indexText: string,
): CustomChannelRendererState {
  const index = Number.parseInt(indexText, 10);
  if (!Number.isInteger(index) || index < 0 || index >= current.draft.content.length) return current;
  return {
    ...current,
    draft: {
      ...current.draft,
      content: current.draft.content.filter((_, candidateIndex) => candidateIndex !== index),
    },
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

function normalizeDraftForSave(draft: CustomChannelDraftInput): CustomChannelDraftInput {
  return {
    ...draft,
    name: draft.name.trim(),
    content: [...draft.content],
  };
}

async function reorderChannel(
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
